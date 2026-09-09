/**
 * Unit actions behind the User Mail Verify feature.
 *
 * Holds no orchestration: chunking, chaining and counting live in
 * UserMailVerifyQueueable. Every platform call is routed through
 * UserMailVerifyPerformer so it can be mocked in tests.
 */
public with sharing class UserMailVerifyService {
  private static final String INVALID_SUFFIX = '.invalid';

  /** Swappable in tests. Defaults to the real platform calls. */
  @TestVisible
  private static UserMailVerifyPerformer performer = new UserMailVerifyPerformerImpl();

  /** Outcome of one action on one user. */
  public class ActionOutcome {
    public Id userId;
    public String username;
    public Boolean success;
    public String message;

    public ActionOutcome(
      Id userId,
      String username,
      Boolean success,
      String message
    ) {
      this.userId = userId;
      this.username = username;
      this.success = success;
      this.message = message;
    }
  }

  /**
   * Removes the ".invalid" suffix from the given users' email addresses.
   *
   * Returns the outcome per user. Runs as its own transaction step: the new
   * address must be committed before a verification link is generated against
   * it, otherwise the link can be built from the pre-update address.
   *
   * Note that this is an email *change*, so it is subject to Email Change
   * Verification. Depending on org configuration the address may stay pending
   * until the user clicks the confirmation link.
   */
  public static List<ActionOutcome> stripInvalidSuffix(List<Id> userIds) {
    List<ActionOutcome> outcomes = new List<ActionOutcome>();
    if (userIds == null || userIds.isEmpty()) {
      return outcomes;
    }

    List<User> toUpdate = new List<User>();
    for (User u : [
      SELECT Id, Username, Email
      FROM User
      WHERE Id IN :userIds
    ]) {
      if (u.Email != null && u.Email.endsWithIgnoreCase(INVALID_SUFFIX)) {
        u.Email = u.Email.substring(
          0,
          u.Email.length() - INVALID_SUFFIX.length()
        );
        toUpdate.add(u);
      }
    }
    if (toUpdate.isEmpty()) {
      return outcomes;
    }

    // allOrNone = false: one rejected address must not block the others.
    List<Database.SaveResult> results = Database.update(toUpdate, false);
    for (Integer i = 0; i < results.size(); i++) {
      User u = toUpdate[i];
      if (results[i].isSuccess()) {
        outcomes.add(new ActionOutcome(u.Id, u.Username, true, null));
      } else {
        outcomes.add(
          new ActionOutcome(u.Id, u.Username, false, firstError(results[i]))
        );
      }
    }
    return outcomes;
  }

  public static ActionOutcome sendVerification(
    Id userId,
    String username,
    String startUrl
  ) {
    return sendVerification(userId, username, null, null, startUrl);
  }

  /**
   * emailTemplateId and networkId only take effect for Experience Cloud users.
   * For internal users Salesforce sends its standard verification email
   * whatever template is passed, so the tab leaves both null.
   */
  public static ActionOutcome sendVerification(
    Id userId,
    String username,
    Id emailTemplateId,
    Id networkId,
    String startUrl
  ) {
    try {
      performer.sendVerification(userId, emailTemplateId, networkId, startUrl);
      return new ActionOutcome(userId, username, true, null);
    } catch (Exception e) {
      return new ActionOutcome(userId, username, false, e.getMessage());
    }
  }

  public static ActionOutcome resetPassword(
    Id userId,
    String username,
    Boolean notifyUser
  ) {
    try {
      performer.resetPassword(userId, notifyUser == true);
      return new ActionOutcome(userId, username, true, null);
    } catch (Exception e) {
      return new ActionOutcome(userId, username, false, e.getMessage());
    }
  }

  /**
   * Sends the completion notification to the administrator who started the run.
   * Resolving and sending is the performer's business; failures there are
   * absorbed so they cannot undo completed work.
   */
  public static void notifyCompletion(
    Id recipientId,
    String title,
    String body
  ) {
    performer.notify(recipientId, truncate(title, 250), truncate(body, 750));
  }

  public static String truncate(String value, Integer maxLength) {
    if (value == null || value.length() <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength - 3) + '...';
  }

  private static String firstError(Database.SaveResult result) {
    return result.getErrors().isEmpty()
      ? 'Unknown error'
      : result.getErrors()[0].getMessage();
  }
}
