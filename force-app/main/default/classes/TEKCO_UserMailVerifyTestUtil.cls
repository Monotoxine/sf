/**
 * Shared helpers for the User Mail Verify test classes.
 */
@IsTest
public class TEKCO_UserMailVerifyTestUtil {
  public static final String TEST_BRAND = 'UMV_TEST_BRAND';

  /** Records every call instead of hitting the platform. */
  public class PerformerSpy implements TEKCO_UserMailVerifyPerformer {
    public List<Id> verified = new List<Id>();
    public List<Id> reset = new List<Id>();
    public List<String> notificationTitles = new List<String>();
    public List<String> notificationBodies = new List<String>();
    public Boolean throwOnVerify = false;

    public void sendVerification(
      Id userId,
      Id emailTemplateId,
      Id networkId,
      String startUrl
    ) {
      if (throwOnVerify) {
        throw new CalloutException('simulated verification failure');
      }
      verified.add(userId);
    }

    public void resetPassword(Id userId, Boolean notifyUser) {
      reset.add(userId);
    }

    public void notify(Id recipientId, String title, String body) {
      notificationTitles.add(title);
      notificationBodies.add(body);
    }
  }

  public static PerformerSpy installSpy() {
    PerformerSpy spy = new PerformerSpy();
    TEKCO_UserMailVerifyService.performer = spy;
    return spy;
  }

  /**
   * Points the access check at a permission set a test can actually create.
   * The real one already exists in the org, so it cannot be inserted again.
   */
  public static void useAccessPermissionSet(String permissionSetName) {
    TEKCO_UserMailVerifyConstants.permissionSetOverride = permissionSetName;
    TEKCO_UserMailVerifyAccess.clearCache();
  }

  public static User buildUser(String alias, String email) {
    Profile standard = [
      SELECT Id
      FROM Profile
      WHERE UserType = 'Standard'
      LIMIT 1
    ];
    String stamp = alias + System.now().getTime();
    User u = new User(
      Alias = alias.left(8),
      Email = email,
      EmailEncodingKey = 'UTF-8',
      LastName = 'UmvTest',
      LanguageLocaleKey = 'en_US',
      LocaleSidKey = 'en_US',
      ProfileId = standard.Id,
      TimeZoneSidKey = 'Europe/Paris',
      Username = stamp + '@umv-test.example.com'
    );
    u.put('TEKCO_Brand__c', TEST_BRAND);
    return u;
  }

  public static List<User> insertUsers(Integer count) {
    List<User> users = new List<User>();
    for (Integer i = 0; i < count; i++) {
      users.add(buildUser('umv' + i, 'umv' + i + '@umv-test.example.com'));
    }
    insert users;
    return users;
  }
}
