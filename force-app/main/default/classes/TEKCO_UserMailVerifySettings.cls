/**
 * Typed access to the TEKCO_User_Mail_Verify_Setting__mdt "Default" record.
 *
 * Every value falls back to a safe built-in default so that a missing or
 * partially filled custom metadata record can never break the feature.
 */
public with sharing class TEKCO_UserMailVerifySettings {
  /** System.resetPassword is capped at 10 calls per transaction. Not configurable upwards. */
  public static final Integer RESET_HARD_LIMIT = 10;

  private static final Integer DEFAULT_MAX_USERS_PER_RUN = 200;
  private static final Integer DEFAULT_CHUNK_SIZE_VERIFY = 50;
  private static final Integer DEFAULT_CHUNK_SIZE_RESET = 10;
  private static final Integer DEFAULT_MAX_ROWS_DISPLAYED = 500;
  private static final String DEFAULT_NOTIFICATION_TYPE = 'TEKCO_UserMailVerify_Run_Complete';

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
  private static TEKCO_User_Mail_Verify_Setting__mdt testOverride;

  private static TEKCO_UserMailVerifySettings cached;

  public static TEKCO_UserMailVerifySettings getInstance() {
    if (cached == null) {
      cached = new TEKCO_UserMailVerifySettings(load());
    }
    return cached;
  }

  @TestVisible
  private static void clearCache() {
    cached = null;
  }

  private static TEKCO_User_Mail_Verify_Setting__mdt load() {
    if (testOverride != null) {
      return testOverride;
    }
    List<TEKCO_User_Mail_Verify_Setting__mdt> records = [
      SELECT
        TEKCO_Max_Users_Per_Run__c,
        TEKCO_Chunk_Size_Verify__c,
        TEKCO_Chunk_Size_Reset__c,
        TEKCO_Max_Rows_Displayed__c,
        TEKCO_Access_Permission_Set__c,
        TEKCO_Notification_Type_Name__c
      FROM TEKCO_User_Mail_Verify_Setting__mdt
      WHERE DeveloperName = 'Default'
      LIMIT 1
    ];
    return records.isEmpty()
      ? new TEKCO_User_Mail_Verify_Setting__mdt()
      : records[0];
  }

  private TEKCO_UserMailVerifySettings(
    TEKCO_User_Mail_Verify_Setting__mdt record
  ) {
    this.maxUsersPerRun = positiveOr(
      record.TEKCO_Max_Users_Per_Run__c,
      DEFAULT_MAX_USERS_PER_RUN
    );
    this.chunkSizeVerify = positiveOr(
      record.TEKCO_Chunk_Size_Verify__c,
      DEFAULT_CHUNK_SIZE_VERIFY
    );
    this.maxRowsDisplayed = positiveOr(
      record.TEKCO_Max_Rows_Displayed__c,
      DEFAULT_MAX_ROWS_DISPLAYED
    );

    // Clamped, not merely defaulted: a configuration mistake here would make
    // every chunk past the tenth reset fail at runtime.
    Integer configuredReset = positiveOr(
      record.TEKCO_Chunk_Size_Reset__c,
      DEFAULT_CHUNK_SIZE_RESET
    );
    this.chunkSizeReset = Math.min(configuredReset, RESET_HARD_LIMIT);

    this.accessPermissionSet = String.isBlank(
        record.TEKCO_Access_Permission_Set__c
      )
      ? null
      : record.TEKCO_Access_Permission_Set__c.trim();
    this.notificationTypeName = String.isBlank(
        record.TEKCO_Notification_Type_Name__c
      )
      ? DEFAULT_NOTIFICATION_TYPE
      : record.TEKCO_Notification_Type_Name__c.trim();
  }

  private static Integer positiveOr(Decimal configured, Integer fallback) {
    return (configured == null ||
      configured <= 0)
      ? fallback
      : Integer.valueOf(configured);
  }
}
