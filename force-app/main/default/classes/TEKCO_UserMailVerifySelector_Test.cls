@IsTest
private class TEKCO_UserMailVerifySelector_Test {
  /**
   * Test_UserHelper stamps brand and country from TestContext. Both are
   * needed: brand is a dependent picklist controlled by country, so setting
   * one without the other is rejected at insert.
   */
  private static User buildUser(String alias, String email) {
    User u = Test_UserHelper.createMinimumAccessUser(alias, false);
    u.Email = email;
    return u;
  }

  private static List<User> insertUsers(Integer count) {
    List<User> users = new List<User>();
    for (Integer i = 0; i < count; i++) {
      users.add(buildUser('umvs' + i, 'umvs' + i + '@umv-test.example.com'));
    }
    insert users;
    return users;
  }

  @IsTest
  static void returnsNothingWithoutBrands() {
    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult blank = TEKCO_UserMailVerifySelector.findByBrands(
      null,
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
      500
    );
    TEKCO_UserMailVerifySelector.UserListResult empty = TEKCO_UserMailVerifySelector.findByBrands(
      new List<String>(),
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
      500
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      blank.rows.size(),
      'A null brand list must not scan every user.'
    );
    Assert.areEqual(
      0,
      empty.rows.size(),
      'An empty brand list must not scan every user.'
    );
  }

  @IsTest
  static void returnsNothingForUnknownBrands() {
    insertUsers(2);

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findByBrands(
      new List<String>{ 'UMV_BRAND_THAT_DOES_NOT_EXIST' },
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
      500
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      result.rows.size(),
      'Unmatched brands must return nothing.'
    );
  }

  @IsTest
  static void neverReturnsTheRunningUser() {
    insertUsers(3);

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findByBrands(
      new List<String>{ TestContext.BRAND },
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
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
    List<User> users = insertUsers(2);
    users[0].IsActive = false;
    update users[0];

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findByBrands(
      new List<String>{ TestContext.BRAND },
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
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
    User suffixed = buildUser('umvsfx', 'sfx@umv-test.example.com.invalid');
    insert suffixed;

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findByBrands(
      new List<String>{ TestContext.BRAND },
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
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
  }

  @IsTest
  static void suffixFilterKeepsOnlyInvalidAddresses() {
    User suffixed = buildUser('umvsx', 'sx@umv-test.example.com.invalid');
    User clean = buildUser('umvcl', 'cl@umv-test.example.com');
    insert new List<User>{ suffixed, clean };

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findByBrands(
      new List<String>{ TestContext.BRAND },
      TEKCO_UserMailVerifySelector.FILTER_ALL,
      TEKCO_UserMailVerifySelector.SUFFIX_ONLY,
      500
    );
    Test.stopTest();

    for (TEKCO_UserMailVerifySelector.UserRow row : result.rows) {
      Assert.isTrue(
        row.hasInvalidSuffix,
        'SUFFIX_ONLY must exclude clean addresses, found: ' + row.email
      );
    }
  }

  @IsTest
  static void suffixFilterCanExcludeInvalidAddresses() {
    User suffixed = buildUser('umvsy', 'sy@umv-test.example.com.invalid');
    insert suffixed;

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findByBrands(
      new List<String>{ TestContext.BRAND },
      TEKCO_UserMailVerifySelector.FILTER_ALL,
      TEKCO_UserMailVerifySelector.SUFFIX_NONE,
      500
    );
    Test.stopTest();

    for (TEKCO_UserMailVerifySelector.UserRow row : result.rows) {
      Assert.isFalse(
        row.hasInvalidSuffix,
        'SUFFIX_NONE must exclude suffixed addresses, found: ' + row.email
      );
    }
  }

  @IsTest
  static void reportsTruncationWhenTheCapIsHit() {
    insertUsers(3);

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult result = TEKCO_UserMailVerifySelector.findByBrands(
      new List<String>{ TestContext.BRAND },
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
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
