/**
 * Runs a User Mail Verify request asynchronously, one chunk per transaction.
 *
 * Chunking exists because System.resetPassword is capped at 10 calls per
 * transaction, and because a bulk send should not sit inside the user's HTTP
 * request. Each link in the chain hands its counters to the next through the
 * constructor, so a single summary survives the whole run and only the final
 * link notifies the administrator.
 *
 * There is no address cleanup phase. Removing a ".invalid" suffix from Apex
 * leaves the change pending an Email Change Verification the user cannot
 * complete, since the address it is sent to is the dead one. The only sequence
 * that works sets a password first, which this screen has no business doing on
 * a verification. Suffixed addresses are surfaced and filtered by the screen
 * instead, and handled by hand in Setup.
 */
public with sharing class TEKCO_UserMailVerify_QBL implements Queueable {
  public enum Phase {
    VERIFY,
    RESET
  }

  /** Failure messages kept in the summary; beyond this, see the debug logs. */
  private static final Integer MAX_REPORTED_ERRORS = 10;

  private final Phase currentPhase;

  private final Id requesterId;
  private final List<Id> allUserIds;
  private final List<Id> pending;
  private final Integer chunkSize;

  private Integer successCount;
  private Integer failureCount;
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

  /**
   * Lets a test run one phase without queueing it. Apex allows a single job
   * per test transaction, and chaining is skipped under test anyway.
   */
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
    this.errors = new List<String>();
  }

  /** Continuation constructor: carries the running totals into the next link. */
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
