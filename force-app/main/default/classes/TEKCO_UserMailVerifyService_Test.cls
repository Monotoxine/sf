/**
 * The tests that asserted sends and resets went with the injectable interface
 * they relied on. What remains covers the address cleanup, which writes to the
 * database and is observable without a test double.
 */
@IsTest
private class TEKCO_UserMailVerifyService_Test {
  @IsTest
  static void stripsTheInvalidSuffixAndLeavesCleanAddressesAlone() {
    User suffixed = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvinv',
      'inv@umv-test.example.com.invalid'
    );
    User clean = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvcln',
      'cln@umv-test.example.com'
    );
    insert new List<User>{ suffixed, clean };

    Test.startTest();
    List<TEKCO_UserMailVerifyService.ActionOutcome> outcomes = TEKCO_UserMailVerifyService.stripInvalidSuffix(
      new List<Id>{ suffixed.Id, clean.Id }
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      outcomes.size(),
      'Only the suffixed address should be touched.'
    );
    Assert.isTrue(outcomes[0].success, 'The update should succeed.');

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
  }

  @IsTest
  static void stripIsANoOpOnAnEmptySelection() {
    Test.startTest();
    List<TEKCO_UserMailVerifyService.ActionOutcome> outcomes = TEKCO_UserMailVerifyService.stripInvalidSuffix(
      new List<Id>()
    );
    Test.stopTest();

    Assert.areEqual(
      0,
      outcomes.size(),
      'An empty selection must not produce outcomes.'
    );
  }

  @IsTest
  static void truncateKeepsShortValuesIntact() {
    Assert.areEqual(
      'short',
      TEKCO_UserMailVerifyService.truncate('short', 100)
    );
    Assert.areEqual(
      10,
      TEKCO_UserMailVerifyService.truncate('0123456789abcdef', 10).length()
    );
  }
}
