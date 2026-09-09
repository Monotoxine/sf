/**
 * Builds the list of users eligible for bulk email verification.
 *
 * A user qualifies when all of the following hold:
 *   - active
 *   - not frozen
 *   - email address not yet verified
 *   - belongs to the selected brand
 *   - is not the running user
 *
 * The running user is excluded on purpose: the same screen resets passwords,
 * and locking yourself out of an admin tool is not a recoverable mistake.
 */
public with sharing class TEKCO_UserMailVerifySelector {
  /** Ceiling on rows pulled from the database before in-memory filtering. */
  private static final Integer QUERY_CEILING = 2000;

  /** Verification filters accepted by findByBrands. */
  public static final String FILTER_UNVERIFIED = 'UNVERIFIED';
  public static final String FILTER_VERIFIED = 'VERIFIED';
  public static final String FILTER_ALL = 'ALL';

  /** Suffix filters accepted by findByBrands. */
  public static final String SUFFIX_ALL = 'ALL';
  public static final String SUFFIX_ONLY = 'ONLY';
  public static final String SUFFIX_NONE = 'NONE';

  private static final String INVALID_SUFFIX_PATTERN = '%.invalid';

  /** Brand field on User, backed by the Brands global value set. */
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
    /** Null when the org exposes no verification signal at all. */
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

  /** One entry of the Brands value set, shaped for a lightning-combobox. */
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

  /**
   * Active values of the Brands global value set behind User.TEKCO_Brand__c.
   *
   * Read through a describe rather than the UI API's getPicklistValues: that
   * wire needs a record type id, and the User object does not support record
   * types, so it would never fire.
   *
   * Returns an empty list when the field is absent, letting the screen say so
   * instead of failing to load.
   */
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

  /** Forced in tests, where the org type cannot be chosen. */
  @TestVisible
  private static Boolean sandboxOverride;

  /** True when this org is a sandbox. */
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

  /**
   * True when the standard User.HasUserVerifiedEmail field exists in this org.
   * Detected at runtime: the field is not present everywhere, and its absence
   * must degrade to the TwoFactorMethodsInfo lookup rather than fail.
   */
  @TestVisible
  private static Boolean hasVerifiedField() {
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
    // The brand field itself may be missing; say nothing rather than throw.
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
    Set<Id> unverifiedIds = hasVerifiedField()
      ? null
      : unverifiedViaTwoFactor(candidates);
    Id runningUserId = UserInfo.getUserId();

    List<UserRow> matches = new List<UserRow>();
    for (User u : candidates) {
      if (u.Id == runningUserId || frozenIds.contains(u.Id)) {
        continue;
      }
      Boolean verified = verificationState(u, unverifiedIds);
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
    // Ordered by brand first: rows from several brands are shown together.
    String tail = ' ORDER BY ' + BRAND_FIELD + ', Name LIMIT ' + QUERY_CEILING;

    String predicate = verificationPredicate(verificationFilter);

    if (hasVerifiedField() && predicate != null) {
      // Filtering at source is cheaper, but HasUserVerifiedEmail is not
      // documented as filterable. If the org rejects the predicate, fall
      // back to filtering the same rows in memory.
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

  /**
   * Addresses still carrying the ".invalid" suffix. Plain LIKE on Email, so
   * unlike the verification predicate it is always safe to push to the query.
   */
  private static String suffixPredicate(String filter) {
    if (SUFFIX_ONLY.equals(filter)) {
      return ' AND Email LIKE \'' + INVALID_SUFFIX_PATTERN + '\'';
    }
    if (SUFFIX_NONE.equals(filter)) {
      return ' AND (NOT Email LIKE \'' + INVALID_SUFFIX_PATTERN + '\')';
    }
    return '';
  }

  /** Null for the ALL filter, which needs no predicate at all. */
  private static String verificationPredicate(String filter) {
    if (FILTER_ALL.equals(filter)) {
      return null;
    }
    return FILTER_VERIFIED.equals(filter)
      ? ' AND HasUserVerifiedEmail = true'
      : ' AND HasUserVerifiedEmail = false';
  }

  /** True, false, or null when the org exposes no verification signal. */
  private static Boolean verificationState(User u, Set<Id> unverifiedIds) {
    if (unverifiedIds != null) {
      return !unverifiedIds.contains(u.Id);
    }
    if (!hasVerifiedField()) {
      return null;
    }
    return u.get('HasUserVerifiedEmail') == true;
  }

  /**
   * An unknown state counts as unverified: hiding work an administrator might
   * need to do is worse than showing a user who turns out to be fine.
   */
  private static Boolean matchesFilter(Boolean verified, String filter) {
    if (FILTER_ALL.equals(filter)) {
      return true;
    }
    if (FILTER_VERIFIED.equals(filter)) {
      return verified == true;
    }
    return verified != true;
  }

  /**
   * Frozen users, resolved through UserLogin.
   *
   * Filtered on IsFrozen = true rather than selecting the non-frozen ones:
   * a user with no UserLogin record is not frozen, and querying
   * IsFrozen = false would wrongly drop them.
   */
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

  /**
   * Fallback verification source. Requires the "Manage Multi-Factor
   * Authentication in API" permission; without it the lookup fails and every
   * candidate is treated as unverified, which is the safe direction — sending
   * a link to an already verified user has no side effect.
   */
  private static Set<Id> unverifiedViaTwoFactor(List<User> candidates) {
    Set<Id> candidateIds = new Map<Id, User>(candidates).keySet();
    Set<Id> unverified = new Set<Id>();
    try {
      for (TwoFactorMethodsInfo info : [
        SELECT UserId
        FROM TwoFactorMethodsInfo
        WHERE UserId IN :candidateIds AND HasUserVerifiedEmailAddress = FALSE
      ]) {
        unverified.add(info.UserId);
      }
      return unverified;
    } catch (Exception e) {
      System.debug(
        LoggingLevel.WARN,
        'TwoFactorMethodsInfo is not readable, treating all candidates as unverified: ' +
        e.getMessage()
      );
      return null;
    }
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
