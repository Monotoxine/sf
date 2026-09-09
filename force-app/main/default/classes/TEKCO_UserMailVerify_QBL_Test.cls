/**
 * What is asserted here is limited on purpose.
 *
 * Sends, resets and notifications used to run through an injectable interface,
 * which let a test double count them: three users gave three links, a completed
 * run notified once rather than once per chunk, a failure was counted and its
 * message reached the summary. That seam was removed, so those assertions went
 * with it.
 *
 * What survives asserts database side effects, which are observable without it.
 * Restoring the interface is what brings the rest back.
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
  static void cleanupPhaseRemovesTheInvalidSuffix() {
    User suffixed = buildUser('umvq1', 'q1@umv-test.example.com.invalid');
    insert suffixed;

    Test.startTest();
    System.enqueueJob(
      TEKCO_UserMailVerify_QBL.forPhase(
        TEKCO_UserMailVerify_QBL.Phase.STRIP_INVALID,
        new List<Id>{ suffixed.Id },
        50
      )
    );
    Test.stopTest();

    User reloaded = [SELECT Email FROM User WHERE Id = :suffixed.Id];
    Assert.isFalse(
      reloaded.Email.endsWith('.invalid'),
      'The suffix must be removed before anything is sent.'
    );
  }

  @IsTest
  static void aVerificationStartsByCleaningTheInvalidSuffix() {
    User suffixed = buildUser('umvq2', 'q2@umv-test.example.com.invalid');
    insert suffixed;

    Test.startTest();
    TEKCO_UserMailVerify_QBL.startVerification(new List<Id>{ suffixed.Id });
    Test.stopTest();

    User reloaded = [SELECT Email FROM User WHERE Id = :suffixed.Id];
    Assert.isFalse(
      reloaded.Email.endsWith('.invalid'),
      'Sending a link to a .invalid address delivers nothing, so the run has ' +
      'to clean it first.'
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

  @IsTest
  static void cleanAddressesAreLeftAlone() {
    User clean = buildUser('umvq4', 'q4@umv-test.example.com');
    insert clean;

    Test.startTest();
    System.enqueueJob(
      TEKCO_UserMailVerify_QBL.forPhase(
        TEKCO_UserMailVerify_QBL.Phase.STRIP_INVALID,
        new List<Id>{ clean.Id },
        50
      )
    );
    Test.stopTest();

    User reloaded = [SELECT Email FROM User WHERE Id = :clean.Id];
    Assert.areEqual(
      clean.Email,
      reloaded.Email,
      'An address without the suffix must not be touched.'
    );
  }
}
