/**
 * Runs a User Mail Verify request asynchronously, one chunk per transaction.
 */
public with sharing class TEKCO_UserMailVerify_QBL implements Queueable {
  public enum Phase {
    VERIFY,
    RESET
  }

  private static final Integer MAX_REPORTED_ERRORS = 10;

  private final Phase currentPhase;

  private final Id requesterId;
  private final List<Id> allUserIds;
  private final List<Id> pending;
  private final Integer chunkSize;

  private Integer successCount;
  private Integer failureCount;
  private Integer alreadyVerifiedCount;
  private List<String> errors;

  public static Id startVerification(List<Id> userIds) {
    return System.enqueueJob(
      new TEKCO_UserMailVerify_QBL(
        Phase.VERIFY,
        userIds,
        chunkFor(Phase.VERIFY)
      )
    );
  }

  public static Id startPasswordReset(List<Id> userIds) {
    return System.enqueueJob(
      new TEKCO_UserMailVerify_QBL(Phase.RESET, userIds, chunkFor(Phase.RESET))
    );
  }

  private static Integer chunkFor(Phase phaseToRun) {
    return phaseToRun == Phase.RESET
      ? TEKCO_UserMailVerifyConstants.RESET_HARD_LIMIT
      : TEKCO_UserMailVerifyConstants.CHUNK_SIZE_VERIFY;
  }

  @TestVisible
  private static TEKCO_UserMailVerify_QBL forPhase(
    Phase phaseToRun,
    List<Id> userIds,
    Integer chunkSize
  ) {
    return new TEKCO_UserMailVerify_QBL(phaseToRun, userIds, chunkSize);
  }

  private TEKCO_UserMailVerify_QBL(
    Phase phaseToRun,
    List<Id> userIds,
    Integer chunkSize
  ) {
    this.currentPhase = phaseToRun;
    this.allUserIds = new List<Id>(userIds);
    this.pending = new List<Id>(userIds);
    this.chunkSize = chunkSize;
    this.requesterId = UserInfo.getUserId();
    this.successCount = 0;
    this.failureCount = 0;
    this.alreadyVerifiedCount = 0;
    this.errors = new List<String>();
  }

  private TEKCO_UserMailVerify_QBL(
    TEKCO_UserMailVerify_QBL previous,
    List<Id> pending
  ) {
    this.currentPhase = previous.currentPhase;
    this.allUserIds = previous.allUserIds;
    this.pending = pending;
    this.chunkSize = previous.chunkSize;
    this.requesterId = previous.requesterId;
    this.successCount = previous.successCount;
    this.failureCount = previous.failureCount;
    this.alreadyVerifiedCount = previous.alreadyVerifiedCount;
    this.errors = previous.errors;
  }

  public void execute(QueueableContext context) {
    processActions(takeChunk());

    if (!pending.isEmpty()) {
      chain(new TEKCO_UserMailVerify_QBL(this, pending));
      return;
    }

    TEKCO_UserMailVerifyService.notifyCompletion(
      requesterId,
      buildTitle(),
      buildBody()
    );
  }

  private List<Id> takeChunk() {
    List<Id> chunk = new List<Id>();
    Integer size = Math.min(chunkSize, pending.size());
    for (Integer i = 0; i < size; i++) {
      chunk.add(pending.remove(0));
    }
    return chunk;
  }

  private void processActions(List<Id> chunk) {
    Boolean skipVerified =
      currentPhase == Phase.VERIFY &&
      TEKCO_UserMailVerifySelector.hasVerifiedField();

    Map<Id, User> usersById = new Map<Id, User>(
      (List<User>) Database.query(
        'SELECT Id, Username' +
          (skipVerified ? ', HasUserVerifiedEmail' : '') +
          ' FROM User WHERE Id IN :chunk'
      )
    );

    for (Id userId : chunk) {
      User u = usersById.get(userId);
      String username = (u == null) ? String.valueOf(userId) : u.Username;

      if (skipVerified && u != null && u.get('HasUserVerifiedEmail') == true) {
        alreadyVerifiedCount++;
        continue;
      }

      TEKCO_UserMailVerifyService.ActionOutcome outcome = (currentPhase ==
        Phase.VERIFY)
        ? TEKCO_UserMailVerifyService.sendVerification(userId, username, null)
        : TEKCO_UserMailVerifyService.resetPassword(userId, username, true);

      if (outcome.success) {
        successCount++;
      } else {
        failureCount++;
        recordError(
          outcome,
          currentPhase == Phase.VERIFY ? 'verification' : 'password reset'
        );
      }
    }
  }

  private void recordError(
    TEKCO_UserMailVerifyService.ActionOutcome outcome,
    String label
  ) {
    String line = outcome.username + ' (' + label + '): ' + outcome.message;
    System.debug(LoggingLevel.ERROR, 'TEKCO_UserMailVerify - ' + line);
    if (errors.size() < MAX_REPORTED_ERRORS) {
      errors.add(line);
    }
  }

  private void chain(TEKCO_UserMailVerify_QBL next) {
    if (Test.isRunningTest()) {
      return;
    }
    System.enqueueJob(next);
  }

  private String buildTitle() {
    String action = (currentPhase == Phase.RESET)
      ? 'Verify and reset'
      : 'Verification';
    return failureCount == 0
      ? action + ' finished'
      : action + ' finished with ' + failureCount + ' failure(s)';
  }

  private String buildBody() {
    List<String> lines = new List<String>();
    lines.add(
      successCount +
        ' of ' +
        allUserIds.size() +
        ' user(s) processed successfully.'
    );
    if (alreadyVerifiedCount > 0) {
      lines.add(
        alreadyVerifiedCount +
        ' user(s) skipped: their address is already verified.'
      );
    }
    if (failureCount > 0) {
      lines.add(failureCount + ' failure(s):');
      lines.addAll(errors);
      if (failureCount > errors.size()) {
        lines.add(
          '...and ' +
            (failureCount - errors.size()) +
            ' more. See the Apex debug logs for the full list.'
        );
      }
    }
    return String.join(lines, '\n');
  }
}
