/**
 * Two test methods, split only by a platform limit: a test transaction accepts
 * a single System.enqueueJob, and both entry points queue a run.
 *
 * The phases themselves are executed directly rather than queued, which is
 * what lets one method walk all three. Chaining is a no-op under test, so a
 * queued run only ever covers its first chunk.
 *
 * What is asserted is limited on purpose. Sends, resets and notifications used
 * to run through an injectable interface, which let a test double count them.
 * That seam was removed, so only database side effects remain observable.
 */
@IsTest
private class TEKCO_UserMailVerify_QBL_Test {
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
  static void everyPhaseRunsAndOnlySuffixedAddressesChange() {
    User suffixed = buildUser('umvq1', 'q1@umv-test.example.com.invalid');
    User clean = buildUser('umvq2', 'q2@umv-test.example.com');
    insert new List<User>{ suffixed, clean };

    List<Id> both = new List<Id>{ suffixed.Id, clean.Id };
    List<Id> one = new List<Id>{ clean.Id };

    Test.startTest();
    TEKCO_UserMailVerify_QBL.forPhase(
        TEKCO_UserMailVerify_QBL.Phase.STRIP_INVALID,
        both,
        50
      )
      .execute(null);
    TEKCO_UserMailVerify_QBL.forPhase(
        TEKCO_UserMailVerify_QBL.Phase.VERIFY,
        one,
        50
      )
      .execute(null);
    TEKCO_UserMailVerify_QBL.forPhase(
        TEKCO_UserMailVerify_QBL.Phase.RESET,
        one,
        10
      )
      .execute(null);
    TEKCO_UserMailVerify_QBL.startVerification(one);
    Test.stopTest();

    Map<Id, User> reloaded = new Map<Id, User>(
      [SELECT Id, Email FROM User WHERE Id IN :both]
    );
    Assert.isFalse(
      reloaded.get(suffixed.Id).Email.endsWith('.invalid'),
      'Sending a link to a .invalid address delivers nothing, so the run has ' +
      'to clean it first.'
    );
    Assert.areEqual(
      clean.Email,
      reloaded.get(clean.Id).Email,
      'An address without the suffix must not be touched.'
    );
  }

  @IsTest
  static void aResetStartsByCleaningTheInvalidSuffix() {
    User suffixed = buildUser('umvq3', 'q3@umv-test.example.com.invalid');
    insert suffixed;

    Test.startTest();
    TEKCO_UserMailVerify_QBL.startPasswordReset(new List<Id>{ suffixed.Id });
    Test.stopTest();

    User reloaded = [SELECT Email FROM User WHERE Id = :suffixed.Id];
    Assert.isFalse(
      reloaded.Email.endsWith('.invalid'),
      'Credentials sent to a .invalid address are lost, and so is the ' +
      'verification completing the reset performs.'
    );
  }
}
