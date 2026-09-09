@IsTest
private class TEKCO_UserMailVerifySettings_Test {
  @IsTest
  static void fallsBackToDefaultsWhenRecordIsEmpty() {
    TEKCO_UserMailVerifySettings.testOverride = new TEKCO_User_Mail_Verify_Setting__mdt();
    TEKCO_UserMailVerifySettings.clearCache();

    TEKCO_UserMailVerifySettings settings = TEKCO_UserMailVerifySettings.getInstance();

    Assert.areEqual(
      200,
      settings.maxUsersPerRun,
      'Missing config must fall back to a default.'
    );
    Assert.areEqual(
      50,
      settings.chunkSizeVerify,
      'Missing config must fall back to a default.'
    );
    Assert.areEqual(
      10,
      settings.chunkSizeReset,
      'Missing config must fall back to a default.'
    );
    Assert.areEqual(
      'TEKCO_UserMailVerify_Run_Complete',
      settings.notificationTypeName,
      'Missing notification type name must fall back to the shipped one.'
    );
  }

  @IsTest
  static void clampsResetChunkToThePlatformLimit() {
    TEKCO_UserMailVerifySettings.testOverride = new TEKCO_User_Mail_Verify_Setting__mdt(
      TEKCO_Chunk_Size_Reset__c = 500
    );
    TEKCO_UserMailVerifySettings.clearCache();

    Assert.areEqual(
      TEKCO_UserMailVerifySettings.RESET_HARD_LIMIT,
      TEKCO_UserMailVerifySettings.getInstance().chunkSizeReset,
      'System.resetPassword allows 10 calls per transaction; configuration must not exceed it.'
    );
  }

  @IsTest
  static void ignoresZeroAndNegativeValues() {
    TEKCO_UserMailVerifySettings.testOverride = new TEKCO_User_Mail_Verify_Setting__mdt(
      TEKCO_Max_Users_Per_Run__c = 0,
      TEKCO_Chunk_Size_Verify__c = -5
    );
    TEKCO_UserMailVerifySettings.clearCache();

    TEKCO_UserMailVerifySettings settings = TEKCO_UserMailVerifySettings.getInstance();
    Assert.areEqual(
      200,
      settings.maxUsersPerRun,
      'Zero must not disable every run.'
    );
    Assert.areEqual(
      50,
      settings.chunkSizeVerify,
      'A negative chunk size must not be used.'
    );
  }

  @IsTest
  static void blankPermissionSetResolvesToNull() {
    TEKCO_UserMailVerifySettings.testOverride = new TEKCO_User_Mail_Verify_Setting__mdt(
      TEKCO_Access_Permission_Set__c = '   '
    );
    TEKCO_UserMailVerifySettings.clearCache();

    Assert.isNull(
      TEKCO_UserMailVerifySettings.getInstance().accessPermissionSet,
      'A blank permission set name must not be treated as a real name.'
    );
  }
}
