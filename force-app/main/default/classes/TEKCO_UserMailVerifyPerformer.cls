/**
 * Seam over the platform calls that cannot be exercised in a test context.
 *
 * System.UserManagement.sendAsyncEmailConfirmation, System.resetPassword and
 * Messaging.CustomNotification either send real messages or invalidate real
 * credentials. Routing them through this interface lets the orchestration logic
 * be tested against a mock, without sending mail or breaking passwords.
 */
public interface TEKCO_UserMailVerifyPerformer {
  void sendVerification(
    Id userId,
    Id emailTemplateId,
    Id networkId,
    String startUrl
  );
  void resetPassword(Id userId, Boolean notifyUser);
  void notify(Id recipientId, String title, String body);
}
