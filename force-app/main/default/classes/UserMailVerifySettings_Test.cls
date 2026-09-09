@IsTest
private class UserMailVerifySettings_Test {
  @IsTest
  static void fallsBackToDefaultsWhenRecordIsEmpty() {
    UserMailVerifySettings.testOverride = new User_Mail_Verify_Setting__mdt();
    UserMailVerifySettings.clearCache();

    UserMailVerifySettings settings = UserMailVerifySettings.getInstance();

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
      'UserMailVerify_Run_Complete',
      settings.notificationTypeName,
      'Missing notification type name must fall back to the shipped one.'
    );
  }

  @IsTest
  static void clampsResetChunkToThePlatformLimit() {
    UserMailVerifySettings.testOverride = new User_Mail_Verify_Setting__mdt(
      Chunk_Size_Reset__c = 500
    );
    UserMailVerifySettings.clearCache();

    Assert.areEqual(
      UserMailVerifySettings.RESET_HARD_LIMIT,
      UserMailVerifySettings.getInstance().chunkSizeReset,
      'System.resetPassword allows 10 calls per transaction; configuration must not exceed it.'
    );
  }

  @IsTest
  static void ignoresZeroAndNegativeValues() {
    UserMailVerifySettings.testOverride = new User_Mail_Verify_Setting__mdt(
      Max_Users_Per_Run__c = 0,
      Chunk_Size_Verify__c = -5
    );
    UserMailVerifySettings.clearCache();

    UserMailVerifySettings settings = UserMailVerifySettings.getInstance();
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
    UserMailVerifySettings.testOverride = new User_Mail_Verify_Setting__mdt(
      Access_Permission_Set__c = '   '
    );
    UserMailVerifySettings.clearCache();

    Assert.isNull(
      UserMailVerifySettings.getInstance().accessPermissionSet,
      'A blank permission set name must not be treated as a real name.'
    );
  }
}
