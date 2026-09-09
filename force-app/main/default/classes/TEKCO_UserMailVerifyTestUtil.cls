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
