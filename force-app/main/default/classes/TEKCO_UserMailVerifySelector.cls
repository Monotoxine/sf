/**
 * Builds the list of users eligible for bulk email verification.
 */
public with sharing class TEKCO_UserMailVerifySelector {
  private static final Integer QUERY_CEILING = 2000;

  public static final String FILTER_UNVERIFIED = 'UNVERIFIED';
  public static final String FILTER_VERIFIED = 'VERIFIED';
  public static final String FILTER_ALL = 'ALL';

  public static final String SUFFIX_ALL = 'ALL';
  public static final String SUFFIX_ONLY = 'ONLY';
  public static final String SUFFIX_NONE = 'NONE';

  private static final String INVALID_SUFFIX_PATTERN = '%.invalid';

  private static final String BRAND_FIELD = 'TEKCO_Brand__c';

  public class UserRow {
    @AuraEnabled
    public Id id;
    @AuraEnabled
    public String name;
    @AuraEnabled
    public String username;
    @AuraEnabled
    public String email;
    @AuraEnabled
    public String profileName;
    @AuraEnabled
    public Datetime createdDate;
    @AuraEnabled
    public String brand;
    @AuraEnabled
    public Boolean isVerified;
    @AuraEnabled
    public Boolean hasInvalidSuffix;
  }

  public class UserListResult {
    @AuraEnabled
    public List<UserRow> rows = new List<UserRow>();
    @AuraEnabled
    public Integer totalCount = 0;
    @AuraEnabled
    public Boolean isTruncated = false;
  }

  public class BrandOption {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;

    public BrandOption(String label, String value) {
      this.label = label;
      this.value = value;
    }
  }

  public static List<BrandOption> getBrandOptions() {
    List<BrandOption> options = new List<BrandOption>();
    Schema.SObjectField field = Schema.SObjectType.User.fields.getMap()
      .get(BRAND_FIELD);
    if (field == null) {
      return options;
    }
    for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
      if (entry.isActive()) {
        options.add(new BrandOption(entry.getLabel(), entry.getValue()));
      }
    }
    return options;
  }

  private static Boolean sandboxCache;

  @TestVisible
  private static Boolean sandboxOverride;

  public static Boolean isSandbox() {
    if (sandboxOverride != null) {
      return sandboxOverride;
    }
    if (sandboxCache == null) {
      sandboxCache = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
    }
    return sandboxCache;
  }

  private static Boolean verifiedFieldCache;

  public static Boolean hasVerifiedField() {
    if (verifiedFieldCache == null) {
      verifiedFieldCache = Schema.SObjectType.User.fields.getMap()
        .containsKey('hasuserverifiedemail');
    }
    return verifiedFieldCache;
  }

  public static UserListResult findByBrands(
    List<String> brands,
    String verificationFilter,
    String suffixFilter,
    Integer maxRows
  ) {
    UserListResult result = new UserListResult();
    if (brands == null || brands.isEmpty()) {
      return result;
    }
    if (Schema.SObjectType.User.fields.getMap().get(BRAND_FIELD) == null) {
      return result;
    }

    List<User> candidates = queryCandidates(
      brands,
      verificationFilter,
      suffixFilter
    );
    if (candidates.isEmpty()) {
      return result;
    }

    Set<Id> frozenIds = frozenUserIds(candidates);
    Id runningUserId = UserInfo.getUserId();

    List<UserRow> matches = new List<UserRow>();
    for (User u : candidates) {
      if (u.Id == runningUserId || frozenIds.contains(u.Id)) {
        continue;
      }
      Boolean verified = verificationState(u);
      if (!matchesFilter(verified, verificationFilter)) {
        continue;
      }
      matches.add(toRow(u, verified));
    }

    result.totalCount = matches.size();
    Integer cap = (maxRows == null || maxRows <= 0) ? matches.size() : maxRows;
    if (matches.size() > cap) {
      result.isTruncated = true;
      for (Integer i = 0; i < cap; i++) {
        result.rows.add(matches[i]);
      }
    } else {
      result.rows = matches;
    }
    return result;
  }

  private static List<User> queryCandidates(
    List<String> brands,
    String verificationFilter,
    String suffixFilter
  ) {
    String fields =
      'Id, Name, Username, Email, Profile.Name, CreatedDate, ' + BRAND_FIELD;
    if (hasVerifiedField()) {
      fields += ', HasUserVerifiedEmail';
    }
    String base =
      'SELECT ' +
      fields +
      ' FROM User WHERE IsActive = true AND Email != null AND ' +
      BRAND_FIELD +
      ' IN :brands' +
      suffixPredicate(suffixFilter);
    String tail = ' ORDER BY ' + BRAND_FIELD + ', Name LIMIT ' + QUERY_CEILING;

    String predicate = verificationPredicate(verificationFilter);

    if (hasVerifiedField() && predicate != null) {
      try {
        return Database.query(base + predicate + tail);
      } catch (Exception e) {
        System.debug(
          LoggingLevel.WARN,
          'HasUserVerifiedEmail is not filterable here, falling back to in-memory filtering: ' +
          e.getMessage()
        );
      }
    }
    return Database.query(base + tail);
  }

  private static String suffixPredicate(String filter) {
    if (SUFFIX_ONLY.equals(filter)) {
      return ' AND Email LIKE \'' + INVALID_SUFFIX_PATTERN + '\'';
    }
    if (SUFFIX_NONE.equals(filter)) {
      return ' AND (NOT Email LIKE \'' + INVALID_SUFFIX_PATTERN + '\')';
    }
    return '';
  }

  private static String verificationPredicate(String filter) {
    if (FILTER_ALL.equals(filter)) {
      return null;
    }
    return FILTER_VERIFIED.equals(filter)
      ? ' AND HasUserVerifiedEmail = true'
      : ' AND HasUserVerifiedEmail = false';
  }

  private static Boolean verificationState(User u) {
    return hasVerifiedField() ? u.get('HasUserVerifiedEmail') == true : null;
  }

  private static Boolean matchesFilter(Boolean verified, String filter) {
    if (FILTER_ALL.equals(filter)) {
      return true;
    }
    if (FILTER_VERIFIED.equals(filter)) {
      return verified == true;
    }
    return verified != true;
  }

  private static Set<Id> frozenUserIds(List<User> candidates) {
    Set<Id> candidateIds = new Map<Id, User>(candidates).keySet();
    Set<Id> frozen = new Set<Id>();
    for (UserLogin login : [
      SELECT UserId
      FROM UserLogin
      WHERE UserId IN :candidateIds AND IsFrozen = TRUE
    ]) {
      frozen.add(login.UserId);
    }
    return frozen;
  }

  private static UserRow toRow(User u, Boolean verified) {
    UserRow row = new UserRow();
    row.id = u.Id;
    row.name = u.Name;
    row.username = u.Username;
    row.email = u.Email;
    row.profileName = u.Profile == null ? null : u.Profile.Name;
    row.createdDate = u.CreatedDate;
    row.brand = (String) u.get(BRAND_FIELD);
    row.isVerified = verified;
    row.hasInvalidSuffix =
      u.Email != null && u.Email.endsWithIgnoreCase('.invalid');
    return row;
  }
}
