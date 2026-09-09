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
public with sharing class UserMailVerifySelector {
  /** Ceiling on rows pulled from the database before in-memory filtering. */
  private static final Integer QUERY_CEILING = 2000;

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

  public static UserListResult findUnverifiedByBrand(
    String brand,
    Integer maxRows
  ) {
    UserListResult result = new UserListResult();
    if (String.isBlank(brand)) {
      return result;
    }

    List<User> candidates = queryCandidates(brand);
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
      if (!isUnverified(u, unverifiedIds)) {
        continue;
      }
      matches.add(toRow(u));
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

  private static List<User> queryCandidates(String brand) {
    String fields = 'Id, Name, Username, Email, Profile.Name, CreatedDate';
    if (hasVerifiedField()) {
      fields += ', HasUserVerifiedEmail';
    }
    String base =
      'SELECT ' +
      fields +
      ' FROM User WHERE IsActive = true AND Email != null AND TEKCO_Brand__c = :brand';
    String tail = ' ORDER BY Name LIMIT ' + QUERY_CEILING;

    if (hasVerifiedField()) {
      // Filtering at source is cheaper, but HasUserVerifiedEmail is not
      // documented as filterable. If the org rejects the predicate, fall
      // back to filtering the same rows in memory.
      try {
        return Database.query(
          base + ' AND HasUserVerifiedEmail = false' + tail
        );
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

  private static Boolean isUnverified(User u, Set<Id> unverifiedIds) {
    if (unverifiedIds != null) {
      return unverifiedIds.contains(u.Id);
    }
    if (!hasVerifiedField()) {
      // No signal available at all: keep the user rather than hide work.
      return true;
    }
    Object flag = u.get('HasUserVerifiedEmail');
    return flag != true;
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

  private static UserRow toRow(User u) {
    UserRow row = new UserRow();
    row.id = u.Id;
    row.name = u.Name;
    row.username = u.Username;
    row.email = u.Email;
    row.profileName = u.Profile == null ? null : u.Profile.Name;
    row.createdDate = u.CreatedDate;
    row.hasInvalidSuffix =
      u.Email != null && u.Email.endsWithIgnoreCase('.invalid');
    return row;
  }
}
