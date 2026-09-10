@IsTest
private class TEKCO_UserMailVerifySelector_Test {

  private static User buildUser(String alias, String email) {
    User u = Test_UserHelper.createMinimumAccessUser(alias, false);
    u.Email = email;
    return u;
  }

  private static TEKCO_UserMailVerifySelector.UserListResult find(
    List<String> brands,
    String verificationFilter,
    String suffixFilter,
    Integer maxRows
  ) {
    return TEKCO_UserMailVerifySelector.findByBrands(
      brands,
      verificationFilter,
      suffixFilter,
      maxRows
    );
  }

  @IsTest
  static void coversEveryFilterCombination() {
    List<String> brand = new List<String>{ TestContext.BRAND };
    List<String> unknown = new List<String>{ 'UMV_BRAND_THAT_DOES_NOT_EXIST' };

    User suffixed = buildUser('umvsfx', 'sfx@test.example.com.invalid');
    User clean = buildUser('umvcln', 'cln@test.example.com');
    User inactive = buildUser('umvina', 'ina@test.example.com');
    insert new List<User>{ suffixed, clean, inactive };
    inactive.IsActive = false;
    update inactive;

    Test.startTest();
    TEKCO_UserMailVerifySelector.UserListResult blank = find(
      null,
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
      500
    );
    TEKCO_UserMailVerifySelector.UserListResult empty = find(
      new List<String>(),
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
      500
    );
    TEKCO_UserMailVerifySelector.UserListResult noMatch = find(
      unknown,
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
      500
    );
    TEKCO_UserMailVerifySelector.UserListResult unverified = find(
      brand,
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
      500
    );
    TEKCO_UserMailVerifySelector.UserListResult verified = find(
      brand,
      TEKCO_UserMailVerifySelector.FILTER_VERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
      500
    );
    TEKCO_UserMailVerifySelector.UserListResult suffixOnly = find(
      brand,
      TEKCO_UserMailVerifySelector.FILTER_ALL,
      TEKCO_UserMailVerifySelector.SUFFIX_ONLY,
      500
    );
    TEKCO_UserMailVerifySelector.UserListResult suffixNone = find(
      brand,
      TEKCO_UserMailVerifySelector.FILTER_ALL,
      TEKCO_UserMailVerifySelector.SUFFIX_NONE,
      500
    );
    TEKCO_UserMailVerifySelector.UserListResult uncapped = find(
      brand,
      TEKCO_UserMailVerifySelector.FILTER_ALL,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
      null
    );
    TEKCO_UserMailVerifySelector.UserListResult capped = find(
      brand,
      TEKCO_UserMailVerifySelector.FILTER_ALL,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL,
      1
    );

    List<TEKCO_UserMailVerifySelector.BrandOption> options = TEKCO_UserMailVerifySelector.getBrandOptions();
    Boolean realOrgFlag = TEKCO_UserMailVerifySelector.isSandbox();
    TEKCO_UserMailVerifySelector.sandboxOverride = true;
    Boolean overridden = TEKCO_UserMailVerifySelector.isSandbox();
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
    Assert.areEqual(
      0,
      noMatch.rows.size(),
      'Unmatched brands must return nothing.'
    );

    Set<Id> unverifiedIds = idsOf(unverified);
    Assert.isFalse(
      unverifiedIds.contains(inactive.Id),
      'A deactivated user must be filtered out.'
    );
    Assert.isFalse(
      unverifiedIds.contains(UserInfo.getUserId()),
      'The running user must never appear: the same screen resets passwords.'
    );

    for (TEKCO_UserMailVerifySelector.UserRow row : verified.rows) {
      Assert.isTrue(
        row.isVerified == true,
        'FILTER_VERIFIED must keep verified addresses only: ' + row.email
      );
    }
    for (TEKCO_UserMailVerifySelector.UserRow row : suffixOnly.rows) {
      Assert.isTrue(
        row.hasInvalidSuffix,
        'SUFFIX_ONLY must exclude clean addresses, found: ' + row.email
      );
    }
    for (TEKCO_UserMailVerifySelector.UserRow row : suffixNone.rows) {
      Assert.isFalse(
        row.hasInvalidSuffix,
        'SUFFIX_NONE must exclude suffixed addresses, found: ' + row.email
      );
    }
    Assert.isTrue(
      idsOf(suffixOnly).contains(suffixed.Id),
      'A .invalid address must be flagged and kept by SUFFIX_ONLY.'
    );

    Assert.isFalse(
      uncapped.isTruncated,
      'Without a cap nothing can be truncated.'
    );
    if (capped.totalCount > 1) {
      Assert.isTrue(
        capped.isTruncated,
        'Exceeding the display cap must be signalled.'
      );
      Assert.areEqual(
        1,
        capped.rows.size(),
        'The returned list must honour the cap.'
      );
    }

    Assert.isNotNull(options, 'The brand picker must always get a list.');
    Assert.isNotNull(realOrgFlag, 'The org flag must resolve to a value.');
    Assert.isTrue(overridden, 'The test override must win over the org value.');
  }

  private static Set<Id> idsOf(
    TEKCO_UserMailVerifySelector.UserListResult result
  ) {
    Set<Id> ids = new Set<Id>();
    for (TEKCO_UserMailVerifySelector.UserRow row : result.rows) {
      ids.add(row.id);
    }
    return ids;
  }
}
