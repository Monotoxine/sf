@IsTest
private class TEKCO_UserMailVerifyQueueable_Test {
  @IsTest
  static void verificationPhaseSendsOneLinkPerUser() {
    TEKCO_UserMailVerifyTestUtil.useAccessPermissionSet('UMV_Test_Access');
    TEKCO_UserMailVerifyTestUtil.PerformerSpy spy = TEKCO_UserMailVerifyTestUtil.installSpy();
    List<User> users = TEKCO_UserMailVerifyTestUtil.insertUsers(3);

    Test.startTest();
    System.enqueueJob(
      TEKCO_UserMailVerifyQueueable.forPhase(
        TEKCO_UserMailVerifyQueueable.Phase.VERIFY,
        new List<Id>(new Map<Id, User>(users).keySet()),
        50
      )
    );
    Test.stopTest();

    Assert.areEqual(
      3,
      spy.verified.size(),
      'Every selected user must receive a verification link.'
    );
  }

  @IsTest
  static void cleanupPhaseRemovesTheSuffixBeforeAnythingIsSent() {
    TEKCO_UserMailVerifyTestUtil.useAccessPermissionSet('UMV_Test_Access');
    TEKCO_UserMailVerifyTestUtil.PerformerSpy spy = TEKCO_UserMailVerifyTestUtil.installSpy();
    User suffixed = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvq1',
      'q1@umv-test.example.com.invalid'
    );
    insert suffixed;

    Test.startTest();
    System.enqueueJob(
      TEKCO_UserMailVerifyQueueable.forPhase(
        TEKCO_UserMailVerifyQueueable.Phase.STRIP_INVALID,
        new List<Id>{ suffixed.Id },
        50
      )
    );
    Test.stopTest();

    User reloaded = [SELECT Email FROM User WHERE Id = :suffixed.Id];
    Assert.isFalse(
      reloaded.Email.endsWith('.invalid'),
      'The suffix must be removed.'
    );
    Assert.areEqual(
      0,
      spy.verified.size(),
      'No link may be generated during cleanup: the new address is not committed yet.'
    );
  }

  @IsTest
  static void resetPhaseNotifiesOnceWhenTheRunCompletes() {
    TEKCO_UserMailVerifyTestUtil.useAccessPermissionSet('UMV_Test_Access');
    TEKCO_UserMailVerifyTestUtil.PerformerSpy spy = TEKCO_UserMailVerifyTestUtil.installSpy();
    List<User> users = TEKCO_UserMailVerifyTestUtil.insertUsers(2);

    Test.startTest();
    System.enqueueJob(
      TEKCO_UserMailVerifyQueueable.forPhase(
        TEKCO_UserMailVerifyQueueable.Phase.RESET,
        new List<Id>(new Map<Id, User>(users).keySet()),
        10
      )
    );
    Test.stopTest();

    Assert.areEqual(2, spy.reset.size(), 'Every selected user must be reset.');
    Assert.areEqual(
      1,
      spy.notificationTitles.size(),
      'A completed run must notify exactly once, not once per chunk.'
    );
    Assert.isTrue(
      spy.notificationTitles[0].startsWithIgnoreCase('Password reset'),
      'The notification must name the action that ran.'
    );
  }

  @IsTest
  static void failuresAreCountedAndReportedInTheSummary() {
    TEKCO_UserMailVerifyTestUtil.useAccessPermissionSet('UMV_Test_Access');
    TEKCO_UserMailVerifyTestUtil.PerformerSpy spy = TEKCO_UserMailVerifyTestUtil.installSpy();
    spy.throwOnVerify = true;
    List<User> users = TEKCO_UserMailVerifyTestUtil.insertUsers(2);

    Test.startTest();
    System.enqueueJob(
      TEKCO_UserMailVerifyQueueable.forPhase(
        TEKCO_UserMailVerifyQueueable.Phase.VERIFY,
        new List<Id>(new Map<Id, User>(users).keySet()),
        50
      )
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      spy.notificationTitles.size(),
      'A run that fails everywhere must still report back.'
    );
    Assert.isTrue(
      spy.notificationTitles[0].contains('failure'),
      'The title must make failures visible without opening the body.'
    );
    Assert.isTrue(
      spy.notificationBodies[0].contains('simulated'),
      'The body must carry the underlying error so it can be acted on.'
    );
  }

  @IsTest
  static void processesOnlyOneChunkPerTransaction() {
    TEKCO_UserMailVerifyTestUtil.useAccessPermissionSet('UMV_Test_Access');
    TEKCO_UserMailVerifyTestUtil.PerformerSpy spy = TEKCO_UserMailVerifyTestUtil.installSpy();
    List<User> users = TEKCO_UserMailVerifyTestUtil.insertUsers(5);

    Test.startTest();
    System.enqueueJob(
      TEKCO_UserMailVerifyQueueable.forPhase(
        TEKCO_UserMailVerifyQueueable.Phase.VERIFY,
        new List<Id>(new Map<Id, User>(users).keySet()),
        2
      )
    );
    Test.stopTest();

    // Chaining is disabled under test, so exactly one chunk runs. This is
    // what keeps System.resetPassword under its 10-per-transaction cap.
    Assert.areEqual(
      2,
      spy.verified.size(),
      'A transaction must process one chunk only.'
    );
    Assert.areEqual(
      0,
      spy.notificationTitles.size(),
      'An unfinished run must not notify: the summary belongs to the last link.'
    );
  }
}
