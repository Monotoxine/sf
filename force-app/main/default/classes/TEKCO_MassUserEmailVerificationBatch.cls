/**
 * Triggers email address verification in bulk, across the whole org.
 *
 * PROBLEM SOLVED
 * --------------
 * Creating a user through the API (Talend, Data Loader, ...) sends NO email
 * verification message. The user stays unverified, the "Verify" action remains
 * next to their address in Setup > Users, and Salesforce refuses to send mail on
 * their behalf ("The current user's email address isn't verified"). Without
 * tooling, that link has to be clicked one record at a time.
 *
 * This batch is the bulk equivalent of that click. It wraps the official async
 * email verification method:
 *
 *   System.UserManagement.sendAsyncEmailConfirmation(
 *       userId, emailTemplateId, networkId, startUrl);
 *
 * Each targeted user receives the standard verification link and clicks it once.
 * This batch changes no email address.
 *
 * The unit actions are delegated to TEKCO_UserMailVerifyService, shared with the
 * User Mail Verify tab, so the two paths cannot drift apart.
 *
 * SCOPE COMPARED TO THE TAB
 * -------------------------
 * The tab is for a hand-picked selection reviewed on screen. This batch is for
 * an unattended, org-wide sweep. Prefer the tab whenever a human is choosing the
 * users.
 *
 * PASSWORD RESET
 * --------------
 * Creating a user through the API does not send credentials either. In the user
 * interface, "Generate new password and notify user immediately" covers that
 * second need; in bulk, enable sendPasswordReset:
 *
 *   TEKCO_MassUserEmailVerificationBatch b = new TEKCO_MassUserEmailVerificationBatch();
 *   b.sendPasswordReset = true;
 *   Database.executeBatch(b, 10);   // <-- 10, mandatory, see below
 *
 * System.resetPassword is capped at 10 calls per transaction. With
 * sendPasswordReset enabled the batch size MUST therefore be 10 at most. Beyond
 * that, the surplus users in each chunk are counted as failures with an explicit
 * message rather than processed silently: nothing is lost, but the run has to be
 * repeated with the right batch size.
 *
 * The operation invalidates the existing password. Enable it deliberately, and
 * never over a wider scope than intended.
 *
 * EXAMPLES
 * --------
 * Every active, unverified user:
 *   Database.executeBatch(new TEKCO_MassUserEmailVerificationBatch(), 50);
 *
 * Only the batch loaded today by the integration:
 *   TEKCO_MassUserEmailVerificationBatch b = new TEKCO_MassUserEmailVerificationBatch();
 *   b.createdSince = System.now().addDays(-1);
 *   Database.executeBatch(b, 50);
 *
 * An explicit list of ids (pilot run):
 *   TEKCO_MassUserEmailVerificationBatch b = new TEKCO_MassUserEmailVerificationBatch();
 *   b.userIds = new Set<Id>{ '005...' };
 *   Database.executeBatch(b, 50);
 *
 * LIMITS
 * ------
 * Sends to INTERNAL users are not capped. The 5,000 emails per day ceiling
 * applies to external addresses only: take it into account for an Experience
 * Cloud user base.
 */
public with sharing class TEKCO_MassUserEmailVerificationBatch implements Database.Batchable<sObject>, Database.Stateful {
  /** Restricts the run to users whose email is not verified yet. */
  public Boolean onlyUnverified = true;

  /** Targets only users created since this date. Null means no filter. */
  public Datetime createdSince;

  /** Explicit id list. When not empty, it overrides every other selection filter. */
  public Set<Id> userIds;

  /** Targets only addresses on this domain (e.g. 'mycompany.com'). Null means all. */
  public String emailDomainFilter;

  /**
   * Custom email template.
   *
   * NO EFFECT FOR INTERNAL USERS: Salesforce sends its standard verification
   * email whatever template is passed. The parameter only takes effect for
   * Experience Cloud users, with networkId set. The message an internal user
   * receives is therefore not customisable — account for that when announcing a
   * bulk run.
   */
  public Id emailTemplateId;

  /** Experience Cloud site. Null for internal users. */
  public Id networkId;

  /** Landing page after the verification click. Null means the org home page. */
  public String startUrl;

  /** Sends the email verification link. */
  public Boolean sendVerification = true;

  /**
   * Resets the password and sends the credentials.
   * Equivalent to "Generate new password and notify user immediately".
   * INVALIDATES the existing password: explicit opt-in only, and batch size
   * limited to 10 (see the class header).
   */
  public Boolean sendPasswordReset = false;

  /** Notify the user on reset. False performs a silent reset. */
  public Boolean notifyUserOnReset = true;

  /**
   * Guardrail: outside a sandbox, sendPasswordReset is refused until this flag
   * is raised explicitly.
   *
   * Reason: in a production org authenticated through SSO, users have no
   * Salesforce password to enter. A bulk reset there mails them "set your
   * password" messages nobody can or should use. Email verification is
   * unaffected: it gates sending mail as the user, not authentication.
   */
  public Boolean allowPasswordResetInProduction = false;

  /** Counts the targets without sending anything. Use it for the first run. */
  public Boolean dryRun = false;

  /**
   * Include addresses ending in ".invalid" (a sandbox refresh artefact). Those
   * addresses can receive nothing, so excluding them avoids pointless sends.
   * No effect outside a sandbox.
   */
  public Boolean includeInvalidAddresses = true;

  /**
   * Salesforce cap: 10 System.resetPassword calls per transaction.
   * Single source shared with the User Mail Verify tab.
   */
  private static final Integer MAX_PASSWORD_RESETS_PER_CHUNK = TEKCO_UserMailVerifySettings.RESET_HARD_LIMIT;

  public Integer sentCount = 0;
  public Integer resetCount = 0;
  public Integer skippedCount = 0;
  public Integer failedCount = 0;
  public Integer resetFailedCount = 0;
  private List<String> errors = new List<String>();

  private static Boolean hasVerifiedEmailFieldCache;

  /**
   * True when the standard User.HasUserVerifiedEmail field is available.
   * Detected at runtime: its absence must not fail the batch, the
   * TwoFactorMethodsInfo fallback takes over instead.
   */
  @TestVisible
  private static Boolean hasVerifiedEmailField() {
    if (hasVerifiedEmailFieldCache == null) {
      hasVerifiedEmailFieldCache = Schema.SObjectType.User.fields.getMap()
        .containsKey('hasuserverifiedemail');
    }
    return hasVerifiedEmailFieldCache;
  }

  public Database.QueryLocator start(Database.BatchableContext ctx) {
    if (sendPasswordReset == true && allowPasswordResetInProduction != true) {
      Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1]
      .IsSandbox;
      if (!isSandbox) {
        throw new BatchException(
          'sendPasswordReset is refused outside a sandbox. Under SSO, users have ' +
            'no Salesforce password to enter, and a bulk reset would mail them ' +
            'unusable credentials. If the reset is genuinely intended here, set ' +
            'allowPasswordResetInProduction = true.'
        );
      }
    }

    // Binds declared outside the conditional blocks: they must still be in
    // scope when Database.getQueryLocator resolves them.
    Set<Id> ids = userIds;
    Datetime since = createdSince;
    String domainLike = '%@' + emailDomainFilter;

    String soql = 'SELECT Id, Username, Email FROM User WHERE Email != null';

    if (ids != null && !ids.isEmpty()) {
      // An explicit selection wins over every other filter.
      soql += ' AND Id IN :ids';
    } else {
      soql += ' AND IsActive = true';

      if (onlyUnverified == true && hasVerifiedEmailField()) {
        // Filtering at source is cheaper than the per-chunk fallback, and needs
        // no "Manage Multi-Factor Authentication in API" permission.
        soql += ' AND HasUserVerifiedEmail = false';
      }
      if (since != null) {
        soql += ' AND CreatedDate >= :since';
      }
      if (String.isNotBlank(emailDomainFilter)) {
        soql += ' AND Email LIKE :domainLike';
      }
      if (includeInvalidAddresses == false) {
        soql += ' AND (NOT Email LIKE \'%.invalid\')';
      }
    }
    return Database.getQueryLocator(soql);
  }

  public void execute(Database.BatchableContext ctx, List<User> scope) {
    Set<Id> targets = new Set<Id>();
    for (User u : scope) {
      targets.add(u.Id);
    }

    // Already filtered by the query when User.HasUserVerifiedEmail is available.
    if (onlyUnverified == true && !hasVerifiedEmailField()) {
      targets = filterUnverified(targets);
    }

    Integer resetsThisChunk = 0;

    for (User u : scope) {
      if (!targets.contains(u.Id)) {
        skippedCount++;
        continue;
      }
      if (dryRun == true) {
        sentCount++;
        if (sendPasswordReset == true) {
          resetCount++;
        }
        continue;
      }

      if (sendVerification == true) {
        TEKCO_UserMailVerifyService.ActionOutcome verifyOutcome = TEKCO_UserMailVerifyService.sendVerification(
          u.Id,
          u.Username,
          emailTemplateId,
          networkId,
          startUrl
        );
        if (verifyOutcome.success) {
          sentCount++;
        } else {
          failedCount++;
          logError(u.Username + ' (verification): ' + verifyOutcome.message);
        }
      }

      if (sendPasswordReset == true) {
        if (resetsThisChunk >= MAX_PASSWORD_RESETS_PER_CHUNK) {
          // Counted as a failure rather than dropped silently: nothing is lost,
          // but the run has to be repeated with a batch size of 10.
          resetFailedCount++;
          logError(
            u.Username +
              ' (reset): reached the limit of ' +
              MAX_PASSWORD_RESETS_PER_CHUNK +
              ' resets per transaction. Re-run with ' +
              'Database.executeBatch(batch, 10).'
          );
          continue;
        }
        TEKCO_UserMailVerifyService.ActionOutcome resetOutcome = TEKCO_UserMailVerifyService.resetPassword(
          u.Id,
          u.Username,
          notifyUserOnReset
        );
        if (resetOutcome.success) {
          resetsThisChunk++;
          resetCount++;
        } else {
          resetFailedCount++;
          logError(u.Username + ' (reset): ' + resetOutcome.message);
        }
      }
    }
  }

  private void logError(String message) {
    if (errors.size() < 50) {
      errors.add(message);
    }
  }

  public void finish(Database.BatchableContext ctx) {
    System.debug('TEKCO_MassUserEmailVerificationBatch finished.');
    System.debug('  Verification links sent : ' + sentCount);
    System.debug('  Passwords reset         : ' + resetCount);
    System.debug('  Skipped (already done)  : ' + skippedCount);
    System.debug('  Verification failures   : ' + failedCount);
    System.debug('  Reset failures          : ' + resetFailedCount);
    for (String err : errors) {
      System.debug('  !! ' + err);
    }
  }

  /**
   * Fallback for orgs that do not expose User.HasUserVerifiedEmail.
   * TwoFactorMethodsInfo requires the "Manage Multi-Factor Authentication in
   * API" permission; if the read fails, every candidate is kept, which is the
   * safe direction — sending a link to an already verified user has no side
   * effect.
   */
  private Set<Id> filterUnverified(Set<Id> candidates) {
    Set<Id> unverified = new Set<Id>();
    try {
      for (TwoFactorMethodsInfo info : [
        SELECT UserId
        FROM TwoFactorMethodsInfo
        WHERE UserId IN :candidates AND HasUserVerifiedEmailAddress = FALSE
      ]) {
        unverified.add(info.UserId);
      }
    } catch (Exception e) {
      System.debug('TwoFactorMethodsInfo is not readable: ' + e.getMessage());
      return candidates;
    }
    return unverified;
  }

  public class BatchException extends Exception {
  }
}
