/**
 * Shared helpers for the User Mail Verify test classes.
 */
@IsTest
public class TEKCO_UserMailVerifyTestUtil {
  private static Map<String, Object> cachedSample;
  private static Boolean sampleResolved = false;

  /**
   * Brand, and country when the org has one, copied from a real user.
   *
   * Reading the first active entry of the describe used to be enough, until it
   * produced INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST: the value set is
   * restricted, and brand may depend on country, so an entry that looks active
   * in the describe is not necessarily assignable on its own. Values the org
   * already accepts on a live record are, and taking both from the same record
   * keeps the pair consistent.
   *
   * Returns null when the field is absent or no user carries a brand, so a
   * test can skip rather than fail.
   */
  private static Map<String, Object> brandSample() {
    if (sampleResolved) {
      return cachedSample;
    }
    sampleResolved = true;

    Map<String, Schema.SObjectField> fields = Schema.SObjectType.User.fields.getMap();
    if (!fields.containsKey('TEKCO_Brand__c')) {
      return null;
    }
    Boolean hasCountry = fields.containsKey('TEKCO_Country__c');

    // Dynamic so the class still compiles in an org without these fields.
    List<User> found = Database.query(
      'SELECT TEKCO_Brand__c' +
        (hasCountry ? ', TEKCO_Country__c' : '') +
        ' FROM User WHERE TEKCO_Brand__c != null LIMIT 1'
    );
    if (found.isEmpty()) {
      return null;
    }

    cachedSample = new Map<String, Object>{
      'TEKCO_Brand__c' => found[0].get('TEKCO_Brand__c')
    };
    if (hasCountry && found[0].get('TEKCO_Country__c') != null) {
      cachedSample.put('TEKCO_Country__c', found[0].get('TEKCO_Country__c'));
    }
    return cachedSample;
  }

  public static String testBrand() {
    Map<String, Object> sample = brandSample();
    return sample == null ? null : (String) sample.get('TEKCO_Brand__c');
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
    Map<String, Object> sample = brandSample();
    if (sample != null) {
      for (String fieldName : sample.keySet()) {
        u.put(fieldName, sample.get(fieldName));
      }
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
