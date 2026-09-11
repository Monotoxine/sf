@IsTest
private class TEKCO_UserMailVerify_QBL_Test {
  private static User buildUser(String alias, String email) {
    User u = Test_UserHelper.createMinimumAccessUser(alias, false);
    u.Email = email;
    return u;
  }

  @IsTest
  static void everyPathRunsAndNoAddressIsRewritten() {
    User suffixed = buildUser('umvq1', 'q1@test.example.com.invalid');
    User clean = buildUser('umvq2', 'q2@test.example.com');
    User third = buildUser('umvq4', 'q4@test.example.com');
    insert new List<User>{ suffixed, clean, third };

    List<Id> all = new List<Id>{ suffixed.Id, clean.Id, third.Id };

    // An id that matches no user: the send fails, which is the only way to
    // reach the failure counter, the error list and the failure block of the
    // completion summary.
    List<Id> missing = new List<Id>{
      Id.valueOf('005' + String.valueOf(1).leftPad(12, '0'))
    };

    Test.startTest();
    // A chunk of one over three users leaves work pending, so execute builds
    // the continuation link and calls chain. Chaining is a no-op under test,
    // so nothing is queued and the single enqueue below stays available.
    TEKCO_UserMailVerify_QBL.forPhase(
        TEKCO_UserMailVerify_QBL.Phase.VERIFY,
        all,
        1
      )
      .execute(null);
    TEKCO_UserMailVerify_QBL.forPhase(
        TEKCO_UserMailVerify_QBL.Phase.RESET,
        new List<Id>{ clean.Id },
        10
      )
      .execute(null);
    TEKCO_UserMailVerify_QBL.forPhase(
        TEKCO_UserMailVerify_QBL.Phase.VERIFY,
        missing,
        50
      )
      .execute(null);
    TEKCO_UserMailVerify_QBL.startVerification(new List<Id>{ clean.Id });
    Test.stopTest();

    Map<Id, User> reloaded = new Map<Id, User>(
      [SELECT Id, Email FROM User WHERE Id IN :all]
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
    User target = buildUser('umvq3', 'q3@test.example.com');
    insert target;

    Test.startTest();
    Id jobId = TEKCO_UserMailVerify_QBL.startPasswordReset(
      new List<Id>{ target.Id }
    );
    Test.stopTest();

    Assert.isNotNull(jobId, 'The run must return a job id for traceability.');
  }
}
