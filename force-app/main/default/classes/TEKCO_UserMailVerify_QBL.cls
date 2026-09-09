/**
 * Runs a User Mail Verify request asynchronously, one chunk per transaction.
 */
public with sharing class TEKCO_UserMailVerify_QBL implements Queueable {
  public enum Phase {
    STRIP_INVALID,
    VERIFY,
    RESET
  }

  private static final Integer MAX_REPORTED_ERRORS = 10;

  private final Phase currentPhase;
  private final Phase finalPhase;

  private final Id requesterId;
  private final List<Id> allUserIds;
  private final List<Id> pending;
  private final Integer chunkSize;

  private Integer successCount;
  private Integer failureCount;
  private Integer strippedCount;
  private List<String> errors;

  public static Id startVerification(List<Id> userIds) {
    return System.enqueueJob(
      new TEKCO_UserMailVerify_QBL(
        Phase.STRIP_INVALID,
        Phase.VERIFY,
        userIds,
        chunkFor(Phase.STRIP_INVALID)
      )
    );
  }

  public static Id startPasswordReset(List<Id> userIds) {
    return System.enqueueJob(
      new TEKCO_UserMailVerify_QBL(
        Phase.STRIP_INVALID,
        Phase.RESET,
        userIds,
        chunkFor(Phase.STRIP_INVALID)
      )
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
    return new TEKCO_UserMailVerify_QBL(
      phaseToRun,
      phaseToRun,
      userIds,
      chunkSize
    );
  }

  private TEKCO_UserMailVerify_QBL(
    Phase phaseToRun,
    Phase phaseToFinishWith,
    List<Id> userIds,
    Integer chunkSize
  ) {
    this.currentPhase = phaseToRun;
    this.finalPhase = phaseToFinishWith;
    this.allUserIds = new List<Id>(userIds);
    this.pending = new List<Id>(userIds);
    this.chunkSize = chunkSize;
    this.requesterId = UserInfo.getUserId();
    this.successCount = 0;
    this.failureCount = 0;
    this.strippedCount = 0;
    this.errors = new List<String>();
  }

  /** Continuation constructor: carries the running totals into the next link. */
  private TEKCO_UserMailVerify_QBL(
    TEKCO_UserMailVerify_QBL previous,
    Phase phaseToRun,
    List<Id> pending
  ) {
    this.currentPhase = phaseToRun;
    this.finalPhase = previous.finalPhase;
    this.allUserIds = previous.allUserIds;
    this.pending = pending;
    this.chunkSize = chunkFor(phaseToRun);
    this.requesterId = previous.requesterId;
    this.successCount = previous.successCount;
    this.failureCount = previous.failureCount;
    this.strippedCount = previous.strippedCount;
    this.errors = previous.errors;
  }

  public void execute(QueueableContext context) {
    List<Id> chunk = takeChunk();

    if (currentPhase == Phase.STRIP_INVALID) {
      processStrip(chunk);
    } else {
      processActions(chunk);
    }

    if (!pending.isEmpty()) {
      chain(new TEKCO_UserMailVerify_QBL(this, currentPhase, pending));
      return;
    }

    if (
      currentPhase == Phase.STRIP_INVALID &&
      finalPhase != Phase.STRIP_INVALID
    ) {
      chain(
        new TEKCO_UserMailVerify_QBL(this, finalPhase, new List<Id>(allUserIds))
      );
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

  private void processStrip(List<Id> chunk) {
    for (
      TEKCO_UserMailVerifyService.ActionOutcome outcome : TEKCO_UserMailVerifyService.stripInvalidSuffix(
        chunk
      )
    ) {
      if (outcome.success) {
        strippedCount++;
      } else {
        failureCount++;
        recordError(outcome, 'address cleanup');
      }
    }
  }

  private void processActions(List<Id> chunk) {
    Map<Id, User> usersById = new Map<Id, User>(
      [SELECT Id, Username FROM User WHERE Id IN :chunk]
    );

    for (Id userId : chunk) {
      User u = usersById.get(userId);
      String username = (u == null) ? String.valueOf(userId) : u.Username;

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

  /**
   * Chaining is skipped under test: Apex allows only one queued job from a
   * running test, so the assertions cover a single chunk.
   */
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
    if (strippedCount > 0) {
      lines.add(
        strippedCount + ' address(es) had the .invalid suffix removed.'
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
