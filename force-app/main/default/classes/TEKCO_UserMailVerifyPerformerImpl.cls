/**
 * Production implementation of TEKCO_UserMailVerifyPerformer: the only place in the
 * feature that touches the real platform calls.
 */
public with sharing class TEKCO_UserMailVerifyPerformerImpl implements TEKCO_UserMailVerifyPerformer {
  public void sendVerification(
    Id userId,
    Id emailTemplateId,
    Id networkId,
    String startUrl
  ) {
    System.UserManagement.sendAsyncEmailConfirmation(
      userId,
      emailTemplateId,
      networkId,
      startUrl
    );
  }

  public void resetPassword(Id userId, Boolean notifyUser) {
    System.resetPassword(userId, notifyUser);
  }

  /**
   * Resolving the notification type belongs here rather than in the service:
   * it is a platform detail, and keeping it behind the seam means a test
   * double never depends on that metadata existing.
   *
   * A missing type must never fail work that has already been done, so the
   * failure is logged and swallowed.
   */
  public void notify(Id recipientId, String title, String body) {
    try {
      String typeName = TEKCO_UserMailVerifySettings.getInstance()
        .notificationTypeName;
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
      notification.setTitle(title);
      notification.setBody(body);
      // The notification has to point at a record; the recipient's own
      // user record is the only one this feature is guaranteed to have.
      notification.setTargetId(recipientId);
      notification.send(new Set<String>{ String.valueOf(recipientId) });
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'Completion notification failed: ' + e.getMessage()
      );
    }
  }
}
