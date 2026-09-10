@IsTest
private class TEKCO_UserMailVerifyService_Test {
 
  private static User buildUser(String alias, String email) {
    User u = Test_UserHelper.createMinimumAccessUser(alias, false);
    u.Email = email;
    return u;
  }

  @IsTest
  static void coversEveryServiceAction() {
    User target = buildUser('umvsvc', 'svc@test.example.com');
    insert target;

    Test.startTest();
    TEKCO_UserMailVerifyService.ActionOutcome sent = TEKCO_UserMailVerifyService.sendVerification(
      target.Id,
      target.Username,
      null
    );
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
