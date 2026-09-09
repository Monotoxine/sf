/**
 * Shared helpers for the User Mail Verify test classes.
 */
@IsTest
public class TEKCO_UserMailVerifyTestUtil {
  private static String cachedBrand;
  private static Boolean brandResolved = false;

  /**
   * A real value taken from the Brands value set.
   *
   * TEKCO_Brand__c is backed by a global value set, which is normally
   * restricted: an invented value would be rejected at insert. Reading the
   * describe keeps the tests working whatever the value set contains, and
   * returns null when the field is absent so a test can skip rather than fail.
   */
  public static String testBrand() {
    if (!brandResolved) {
      brandResolved = true;
      Schema.SObjectField field = Schema.SObjectType.User.fields.getMap()
        .get('TEKCO_Brand__c');
      if (field != null) {
        for (
          Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()
        ) {
          if (entry.isActive()) {
            cachedBrand = entry.getValue();
            break;
          }
        }
      }
    }
    return cachedBrand;
  }

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
    // put() throws on a field the org does not have, so guard the assignment.
    if (testBrand() != null) {
      u.put('TEKCO_Brand__c', testBrand());
    }
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
