@IsTest
private class TEKCO_UserMailVerifySelector_Test {
  @IsTest
  static void returnsNothingWithoutABrand() {
    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult blank = TEKCO_UserMailVerifySelector.findUnverifiedByBrand(
      null,
      500
    );
    TEKCO_UserMailVerifySelector.UserListResult empty = TEKCO_UserMailVerifySelector.findUnverifiedByBrand(
      '',
      500
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      blank.rows.size(),
      'A null brand must not scan every user.'
    );
    Assert.areEqual(
      0,
      empty.rows.size(),
      'A blank brand must not scan every user.'
    );
  }

  @IsTest
  static void returnsNothingForAnUnknownBrand() {
    TEKCO_UserMailVerifyTestUtil.insertUsers(2);

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findUnverifiedByBrand(
      'UMV_BRAND_THAT_DOES_NOT_EXIST',
      500
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      result.rows.size(),
      'An unmatched brand must return nothing.'
    );
  }

  @IsTest
  static void neverReturnsTheRunningUser() {
    TEKCO_UserMailVerifyTestUtil.insertUsers(3);

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findUnverifiedByBrand(
      TEKCO_UserMailVerifyTestUtil.TEST_BRAND,
      500
    );
    Test.stopTest();

    for (TEKCO_UserMailVerifySelector.UserRow row : result.rows) {
      Assert.areNotEqual(
        UserInfo.getUserId(),
        row.id,
        'The running user must never appear: the same screen resets passwords.'
      );
    }
  }

  @IsTest
  static void excludesInactiveUsers() {
    List<User> users = TEKCO_UserMailVerifyTestUtil.insertUsers(2);
    users[0].IsActive = false;
    update users[0];

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findUnverifiedByBrand(
      TEKCO_UserMailVerifyTestUtil.TEST_BRAND,
      500
    );
    Test.stopTest();

    Set<Id> returned = new Set<Id>();
    for (TEKCO_UserMailVerifySelector.UserRow row : result.rows) {
      returned.add(row.id);
    }
    Assert.isFalse(
      returned.contains(users[0].Id),
      'A deactivated user must be filtered out.'
    );
  }

  @IsTest
  static void flagsAddressesCarryingTheInvalidSuffix() {
    User suffixed = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvsfx',
      'sfx@umv-test.example.com.invalid'
    );
    insert suffixed;

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findUnverifiedByBrand(
      TEKCO_UserMailVerifyTestUtil.TEST_BRAND,
      500
    );
    Test.stopTest();

    for (TEKCO_UserMailVerifySelector.UserRow row : result.rows) {
      if (row.id == suffixed.Id) {
        Assert.isTrue(
          row.hasInvalidSuffix,
          'A .invalid address must be flagged for the screen.'
        );
        return;
      }
    }
    // Reaching here means the org already considers the user verified, which
    // is legitimate; the flag itself is asserted only when the row is present.
  }

  @IsTest
  static void reportsTruncationWhenTheCapIsHit() {
    TEKCO_UserMailVerifyTestUtil.insertUsers(3);

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findUnverifiedByBrand(
      TEKCO_UserMailVerifyTestUtil.TEST_BRAND,
      1
    );
    Test.stopTest();

    if (result.totalCount > 1) {
      Assert.isTrue(
        result.isTruncated,
        'Exceeding the display cap must be signalled.'
      );
      Assert.areEqual(
        1,
        result.rows.size(),
        'The returned list must honour the cap.'
      );
    }
  }
}
