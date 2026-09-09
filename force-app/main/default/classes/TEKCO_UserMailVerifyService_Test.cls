/**
 * One test method on purpose.
 *
 * Coverage counts lines executed, not methods, and every platform call in the
 * service is wrapped in try/catch: the outcome is recorded whether the call
 * succeeds or not, so a single pass walks all of them.
 */
@IsTest
private class TEKCO_UserMailVerifyService_Test {
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

  @IsTest
  static void coversEveryServiceAction() {
    User suffixed = buildUser('umvinv', 'inv@umv-test.example.com.invalid');
    User clean = buildUser('umvcln', 'cln@umv-test.example.com');
    insert new List<User>{ suffixed, clean };

    Test.startTest();
    List<TEKCO_UserMailVerifyService.ActionOutcome> stripped = TEKCO_UserMailVerifyService.stripInvalidSuffix(
      new List<Id>{ suffixed.Id, clean.Id }
    );
    List<TEKCO_UserMailVerifyService.ActionOutcome> nothing = TEKCO_UserMailVerifyService.stripInvalidSuffix(
      new List<Id>()
    );
    TEKCO_UserMailVerifyService.ActionOutcome sent = TEKCO_UserMailVerifyService.sendVerification(
      clean.Id,
      clean.Username,
      null
    );
    // notifyUser = false: a test must not depend on mail going out.
    TEKCO_UserMailVerifyService.ActionOutcome reset = TEKCO_UserMailVerifyService.resetPassword(
      clean.Id,
      clean.Username,
      false
    );
    TEKCO_UserMailVerifyService.notifyCompletion(
      UserInfo.getUserId(),
      'Title',
      'Body'
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      stripped.size(),
      'Only the suffixed address should be touched.'
    );
    Assert.isTrue(stripped[0].success, 'The update should succeed.');
    Assert.areEqual(
      0,
      nothing.size(),
      'An empty selection must not produce outcomes.'
    );

    Map<Id, User> reloaded = new Map<Id, User>(
      [
        SELECT Id, Email
        FROM User
        WHERE Id IN :new List<Id>{ suffixed.Id, clean.Id }
      ]
    );
    Assert.isFalse(
      reloaded.get(suffixed.Id).Email.endsWith('.invalid'),
      'The suffix must be gone.'
    );
    Assert.areEqual(
      'cln@umv-test.example.com',
      reloaded.get(clean.Id).Email,
      'A clean address must be left untouched.'
    );

    // Whether the platform accepts these depends on org configuration, so the
    // assertion is on the contract: an outcome comes back, never an exception.
    Assert.isNotNull(sent, 'sendVerification must always report an outcome.');
    Assert.isNotNull(reset, 'resetPassword must always report an outcome.');

    Assert.areEqual(
      'short',
      TEKCO_UserMailVerifyService.truncate('short', 100),
      'A value under the cap must come back untouched.'
    );
    Assert.areEqual(
      10,
      TEKCO_UserMailVerifyService.truncate('0123456789abcdef', 10).length(),
      'A longer value must be cut to the cap.'
    );
  }
}
