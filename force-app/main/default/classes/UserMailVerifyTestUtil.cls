/**
 * Shared helpers for the User Mail Verify test classes.
 */
@IsTest
public class UserMailVerifyTestUtil {
  public static final String TEST_BRAND = 'UMV_TEST_BRAND';

  /** Records every call instead of hitting the platform. */
  public class PerformerSpy implements UserMailVerifyPerformer {
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
    UserMailVerifyService.performer = spy;
    return spy;
  }

  public static void applySettings(
    Integer maxPerRun,
    Integer chunkVerify,
    Integer chunkReset,
    String permissionSetName
  ) {
    UserMailVerifySettings.testOverride = new User_Mail_Verify_Setting__mdt(
      Max_Users_Per_Run__c = maxPerRun,
      Chunk_Size_Verify__c = chunkVerify,
      Chunk_Size_Reset__c = chunkReset,
      Max_Rows_Displayed__c = 500,
      Access_Permission_Set__c = permissionSetName,
      Notification_Type_Name__c = 'UserMailVerify_Run_Complete'
    );
    UserMailVerifySettings.clearCache();
    UserMailVerifyAccess.clearCache();
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
