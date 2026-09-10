/**
 * Unit actions behind the User Mail Verify feature.
 *
 * Holds no orchestration: chunking, chaining and counting live in
 * TEKCO_UserMailVerify_QBL.
 *
 * The platform calls sit here directly. They were behind an injectable
 * interface so the orchestration could be asserted against a test double; that
 * seam was removed for readability, and with it the tests that counted sends,
 * resets and notifications. Reintroducing the interface is what brings them
 * back.
 */
public with sharing class TEKCO_UserMailVerifyService {
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

  public static ActionOutcome sendVerification(
    Id userId,
    String username,
    String startUrl
  ) {
    return sendVerification(userId, username, null, null, startUrl);
  }

  public static ActionOutcome sendVerification(
    Id userId,
    String username,
    Id emailTemplateId,
    Id networkId,
    String startUrl
  ) {
    try {
      System.UserManagement.sendAsyncEmailConfirmation(
        userId,
        emailTemplateId,
        networkId,
        startUrl
      );
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
      System.resetPassword(userId, notifyUser == true);
      return new ActionOutcome(userId, username, true, null);
    } catch (Exception e) {
      return new ActionOutcome(userId, username, false, e.getMessage());
    }
  }

  public static void notifyCompletion(
    Id recipientId,
    String title,
    String body
  ) {
    try {
      String typeName = TEKCO_UserMailVerifyConstants.NOTIFICATION_TYPE;
      List<CustomNotificationType> types = [
        SELECT Id
        FROM CustomNotificationType
        WHERE DeveloperName = :typeName
        LIMIT 1
      ];
      if (types.isEmpty()) {
        System.debug(
          LoggingLevel.WARN,
          'Custom notification type not found, skipping notification: ' +
          typeName
        );
        return;
      }

      Messaging.CustomNotification notification = new Messaging.CustomNotification();
      notification.setNotificationTypeId(types[0].Id);
      notification.setTitle(truncate(title, 250));
      notification.setBody(truncate(body, 750));
      notification.setTargetId(recipientId);
      notification.send(new Set<String>{ String.valueOf(recipientId) });
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'Completion notification failed: ' + e.getMessage()
      );
    }
  }

  public static String truncate(String value, Integer maxLength) {
    if (value == null || value.length() <= maxLength) {
      return value;
    }
    return value.substring(0, maxLength - 3) + '...';
  }
}
