/**
 * Typed access to the User_Mail_Verify_Setting__mdt "Default" record.
 *
 * Every value falls back to a safe built-in default so that a missing or
 * partially filled custom metadata record can never break the feature.
 */
public with sharing class UserMailVerifySettings {
  /** System.resetPassword is capped at 10 calls per transaction. Not configurable upwards. */
  public static final Integer RESET_HARD_LIMIT = 10;

  private static final Integer DEFAULT_MAX_USERS_PER_RUN = 200;
  private static final Integer DEFAULT_CHUNK_SIZE_VERIFY = 50;
  private static final Integer DEFAULT_CHUNK_SIZE_RESET = 10;
  private static final Integer DEFAULT_MAX_ROWS_DISPLAYED = 500;
  private static final String DEFAULT_NOTIFICATION_TYPE = 'UserMailVerify_Run_Complete';

  @AuraEnabled
  public Integer maxUsersPerRun { get; private set; }
  @AuraEnabled
  public Integer chunkSizeVerify { get; private set; }
  @AuraEnabled
  public Integer chunkSizeReset { get; private set; }
  @AuraEnabled
  public Integer maxRowsDisplayed { get; private set; }
  public String accessPermissionSet { get; private set; }
  public String notificationTypeName { get; private set; }

  /** Injection point for tests; bypasses the custom metadata lookup. */
  @TestVisible
  private static User_Mail_Verify_Setting__mdt testOverride;

  private static UserMailVerifySettings cached;

  public static UserMailVerifySettings getInstance() {
    if (cached == null) {
      cached = new UserMailVerifySettings(load());
    }
    return cached;
  }

  @TestVisible
  private static void clearCache() {
    cached = null;
  }

  private static User_Mail_Verify_Setting__mdt load() {
    if (testOverride != null) {
      return testOverride;
    }
    List<User_Mail_Verify_Setting__mdt> records = [
      SELECT
        Max_Users_Per_Run__c,
        Chunk_Size_Verify__c,
        Chunk_Size_Reset__c,
        Max_Rows_Displayed__c,
        Access_Permission_Set__c,
        Notification_Type_Name__c
      FROM User_Mail_Verify_Setting__mdt
      WHERE DeveloperName = 'Default'
      LIMIT 1
    ];
    return records.isEmpty() ? new User_Mail_Verify_Setting__mdt() : records[0];
  }

  private UserMailVerifySettings(User_Mail_Verify_Setting__mdt record) {
    this.maxUsersPerRun = positiveOr(
      record.Max_Users_Per_Run__c,
      DEFAULT_MAX_USERS_PER_RUN
    );
    this.chunkSizeVerify = positiveOr(
      record.Chunk_Size_Verify__c,
      DEFAULT_CHUNK_SIZE_VERIFY
    );
    this.maxRowsDisplayed = positiveOr(
      record.Max_Rows_Displayed__c,
      DEFAULT_MAX_ROWS_DISPLAYED
    );

    // Clamped, not merely defaulted: a configuration mistake here would make
    // every chunk past the tenth reset fail at runtime.
    Integer configuredReset = positiveOr(
      record.Chunk_Size_Reset__c,
      DEFAULT_CHUNK_SIZE_RESET
    );
    this.chunkSizeReset = Math.min(configuredReset, RESET_HARD_LIMIT);

    this.accessPermissionSet = String.isBlank(record.Access_Permission_Set__c)
      ? null
      : record.Access_Permission_Set__c.trim();
    this.notificationTypeName = String.isBlank(record.Notification_Type_Name__c)
      ? DEFAULT_NOTIFICATION_TYPE
      : record.Notification_Type_Name__c.trim();
  }

  private static Integer positiveOr(Decimal configured, Integer fallback) {
    return (configured == null ||
      configured <= 0)
      ? fallback
      : Integer.valueOf(configured);
  }
}
