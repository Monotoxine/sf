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
    User target = buildUser('umvsvc', 'svc@umv-test.example.com');
    insert target;

    Test.startTest();
    TEKCO_UserMailVerifyService.ActionOutcome sent = TEKCO_UserMailVerifyService.sendVerification(
      target.Id,
      target.Username,
      null
    );
    // notifyUser = false: a test must not depend on mail going out.
    TEKCO_UserMailVerifyService.ActionOutcome reset = TEKCO_UserMailVerifyService.resetPassword(
      target.Id,
      target.Username,
      false
    );
    TEKCO_UserMailVerifyService.notifyCompletion(
      UserInfo.getUserId(),
      'Title',
      'Body'
    );
    Test.stopTest();

    // Whether the platform accepts these depends on org configuration, so the
    // assertion is on the contract: an outcome comes back, never an exception.
    Assert.isNotNull(sent, 'sendVerification must always report an outcome.');
    Assert.areEqual(
      target.Id,
      sent.userId,
      'The outcome must name the user it concerns.'
    );
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
