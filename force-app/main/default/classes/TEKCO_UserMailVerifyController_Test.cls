/**
 * Two test methods, split only by a platform limit: a test transaction accepts
 * a single System.enqueueJob, and both launch methods queue a run.
 *
 * No System.runAs here. The controller carries no permission check, so running
 * as a low-privilege user only added a way for the code to fail before
 * reaching the lines under test.
 */
@IsTest
private class TEKCO_UserMailVerifyController_Test {
  /**
   * Test_UserHelper stamps brand and country from TestContext. Both are
   * needed: brand is a dependent picklist controlled by country, so setting
   * one without the other is rejected at insert.
   */
  private static List<User> insertUsers(Integer count) {
    List<User> users = new List<User>();
    for (Integer i = 0; i < count; i++) {
      User u = Test_UserHelper.createMinimumAccessUser('umvc' + i, false);
      u.Email = 'umvc' + i + '@umv-test.example.com';
      users.add(u);
    }
    insert users;
    return users;
  }

  private static String messageFrom(List<Id> ids, Boolean reset) {
    try {
      if (reset) {
        TEKCO_UserMailVerifyController.launchPasswordReset(ids);
      } else {
        TEKCO_UserMailVerifyController.launchVerification(ids);
      }
    } catch (Exception e) {
      return e.getMessage();
    }
    return null;
  }

  @IsTest
  static void readsSettingsAndRefusesEveryInvalidSelection() {
    List<User> targets = insertUsers(2);
    List<Id> ids = new List<Id>(new Map<Id, User>(targets).keySet());

    List<Id> overCap = new List<Id>();
    for (
      Integer i = 0; i <= TEKCO_UserMailVerifyConstants.MAX_USERS_PER_RUN; i++
    ) {
      overCap.add(Id.valueOf('005' + String.valueOf(i + 1).leftPad(12, '0')));
    }

    Test.startTest();
    TEKCO_UserMailVerifySelector.sandboxOverride = false;
    TEKCO_UserMailVerifyController.Settings production = TEKCO_UserMailVerifyController.getSettings();
    String resetRefused = messageFrom(ids, true);

    TEKCO_UserMailVerifySelector.sandboxOverride = true;
    TEKCO_UserMailVerifyController.Settings sandbox = TEKCO_UserMailVerifyController.getSettings();
    List<TEKCO_UserMailVerifySelector.BrandOption> brands = TEKCO_UserMailVerifyController.getBrands();
    TEKCO_UserMailVerifySelector.UserListResult listed = TEKCO_UserMailVerifyController.getUsers(
      new List<String>{ TestContext.BRAND },
      TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
      TEKCO_UserMailVerifySelector.SUFFIX_ALL
    );

    String emptyRefused = messageFrom(new List<Id>(), false);
    String capRefused = messageFrom(overCap, false);
    String selfRefused = messageFrom(
      new List<Id>{ UserInfo.getUserId() },
      false
    );

    TEKCO_UserMailVerifyController.LaunchResult queued = TEKCO_UserMailVerifyController.launchVerification(
      ids
    );
    Test.stopTest();

    Assert.areEqual(
      TEKCO_UserMailVerifyConstants.MAX_USERS_PER_RUN,
      sandbox.maxUsersPerRun,
      'The screen must receive the configured cap.'
    );
    Assert.areEqual(
      TEKCO_UserMailVerifyConstants.MAX_ROWS_DISPLAYED,
      sandbox.maxRowsDisplayed,
      'The screen must receive the configured row cap.'
    );
    Assert.isTrue(sandbox.isSandbox, 'The sandbox flag must follow the org.');
    Assert.isFalse(
      production.isSandbox,
      'The screen needs this flag to decide whether to offer the reset button.'
    );

    Assert.isNotNull(brands, 'The brand picker must always get a list.');
    Assert.isNotNull(listed, 'The user list must always come back.');

    // Each refusal is asserted on its own message. A bare "an exception was
    // thrown" would pass on any failure, including one that never reaches the
    // guard being tested.
    Assert.isTrue(
      resetRefused != null && resetRefused.contains('sandboxes only'),
      'Hiding the button is not a control, and the refusal must say why: ' +
      resetRefused
    );
    Assert.isTrue(
      emptyRefused != null && emptyRefused.contains('at least one user'),
      'An empty selection must be rejected before anything is queued: ' +
      emptyRefused
    );
    Assert.isTrue(
      capRefused != null &&
      capRefused.contains(
        'limited to ' + TEKCO_UserMailVerifyConstants.MAX_USERS_PER_RUN
      ),
      'The cap must be enforced server-side and named in the error: ' +
      capRefused
    );
    Assert.isTrue(
      selfRefused != null && selfRefused.contains('your own user'),
      'Acting on your own user from this screen must be refused: ' + selfRefused
    );

    Assert.areEqual(
      2,
      queued.queuedCount,
      'The queued count must match the selection.'
    );
    Assert.isNotNull(
      queued.jobId,
      'The job id must be returned for traceability.'
    );
  }

  @IsTest
  static void queuesAPasswordResetInASandbox() {
    List<User> targets = insertUsers(1);
    List<Id> ids = new List<Id>(new Map<Id, User>(targets).keySet());
    TEKCO_UserMailVerifySelector.sandboxOverride = true;

    Test.startTest();
    TEKCO_UserMailVerifyController.LaunchResult queued = TEKCO_UserMailVerifyController.launchPasswordReset(
      ids
    );
    Test.stopTest();

    Assert.areEqual(
      1,
      queued.queuedCount,
      'The queued count must match the selection.'
    );
    Assert.isNotNull(
      queued.jobId,
      'The job id must be returned for traceability.'
    );
  }
}
