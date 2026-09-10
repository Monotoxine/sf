/**
 * Two test methods, split only by a platform limit: a test transaction accepts
 * a single System.enqueueJob, and both entry points queue a run.
 *
 * The phases themselves are executed directly rather than queued, which is
 * what lets one method walk both. Chaining is a no-op under test, so a queued
 * run only ever covers its first chunk.
 *
 * What is asserted is limited on purpose. Sends, resets and notifications used
 * to run through an injectable interface, which let a test double count them.
 * That seam was removed, so only database side effects remain observable, and
 * neither phase writes to the database any more.
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
  static void bothPhasesRunAndLeaveTheAddressAlone() {
    User suffixed = buildUser('umvq1', 'q1@umv-test.example.com.invalid');
    User clean = buildUser('umvq2', 'q2@umv-test.example.com');
    insert new List<User>{ suffixed, clean };

    List<Id> both = new List<Id>{ suffixed.Id, clean.Id };

    Test.startTest();
    TEKCO_UserMailVerify_QBL.forPhase(
        TEKCO_UserMailVerify_QBL.Phase.VERIFY,
        both,
        50
      )
      .execute(null);
    TEKCO_UserMailVerify_QBL.forPhase(
        TEKCO_UserMailVerify_QBL.Phase.RESET,
        new List<Id>{ clean.Id },
        10
      )
      .execute(null);
    TEKCO_UserMailVerify_QBL.startVerification(new List<Id>{ clean.Id });
    Test.stopTest();

    Map<Id, User> reloaded = new Map<Id, User>(
      [SELECT Id, Email FROM User WHERE Id IN :both]
    );
    Assert.areEqual(
      suffixed.Email,
      reloaded.get(suffixed.Id).Email,
      'The run must never rewrite an address, suffixed or not.'
    );
    Assert.areEqual(
      clean.Email,
      reloaded.get(clean.Id).Email,
      'The run must never rewrite an address, suffixed or not.'
    );
  }

  @IsTest
  static void aPasswordResetQueuesWithoutError() {
    User target = buildUser('umvq3', 'q3@umv-test.example.com');
    insert target;

    Test.startTest();
    Id jobId = TEKCO_UserMailVerify_QBL.startPasswordReset(
      new List<Id>{ target.Id }
    );
    Test.stopTest();

    Assert.isNotNull(jobId, 'The run must return a job id for traceability.');
  }
}
