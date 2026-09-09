@IsTest
private class TEKCO_UserMailVerifyController_Test {
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

  private static List<User> insertUsers(Integer count) {
    List<User> users = new List<User>();
    for (Integer i = 0; i < count; i++) {
      users.add(buildUser('umvc' + i, 'umvc' + i + '@umv-test.example.com'));
    }
    insert users;
    return users;
  }

  private static User testUser() {
    User u = buildUser('umvctl', 'ctl@umv-test.example.com');
    insert u;
    TEKCO_UserMailVerifySelector.sandboxOverride = true;
    return u;
  }

  @IsTest
  static void exposesTheConfiguredCaps() {
    User granted = testUser();

    TEKCO_UserMailVerifyController.Settings settings;
    System.runAs(granted) {
      settings = TEKCO_UserMailVerifyController.getSettings();
    }

    Assert.areEqual(
      TEKCO_UserMailVerifyConstants.MAX_USERS_PER_RUN,
      settings.maxUsersPerRun,
      'The screen must receive the configured cap.'
    );
  }

  @IsTest
  static void rejectsAnEmptySelection() {
    User granted = testUser();

    Boolean rejected = false;
    System.runAs(granted) {
      try {
        TEKCO_UserMailVerifyController.launchVerification(new List<Id>());
      } catch (Exception e) {
        rejected = true;
      }
    }

    Assert.isTrue(
      rejected,
      'An empty selection must be rejected before anything is queued.'
    );
  }

  @IsTest
  static void enforcesThePerRunCapServerSide() {
    User granted = testUser();

    List<Id> ids = new List<Id>();
    for (
      Integer i = 0; i <= TEKCO_UserMailVerifyConstants.MAX_USERS_PER_RUN; i++
    ) {
      ids.add(Id.valueOf('005' + String.valueOf(i + 1).leftPad(12, '0')));
    }

    String message;
    System.runAs(granted) {
      try {
        TEKCO_UserMailVerifyController.launchVerification(ids);
      } catch (Exception e) {
        message = e.getMessage();
      }
    }

    Assert.isNotNull(
      message,
      'The cap must be enforced server-side, not only in the component.'
    );
    Assert.isTrue(
      message.contains(
        'limited to ' + TEKCO_UserMailVerifyConstants.MAX_USERS_PER_RUN
      ),
      'The error must name the cap so the administrator knows what to do: ' +
      message
    );
  }

  @IsTest
  static void refusesToActOnTheCallersOwnUser() {
    User granted = testUser();

    String message;
    System.runAs(granted) {
      try {
        TEKCO_UserMailVerifyController.launchPasswordReset(
          new List<Id>{ granted.Id }
        );
      } catch (Exception e) {
        message = e.getMessage();
      }
    }

    Assert.isNotNull(
      message,
      'Resetting your own password from this screen must be refused.'
    );
  }

  @IsTest
  static void refusesPasswordResetOutsideASandbox() {
    User granted = testUser();
    TEKCO_UserMailVerifySelector.sandboxOverride = false;
    List<User> users = insertUsers(1);
    List<Id> ids = new List<Id>(new Map<Id, User>(users).keySet());

    String message;
    System.runAs(granted) {
      try {
        TEKCO_UserMailVerifyController.launchPasswordReset(ids);
      } catch (Exception e) {
        message = e.getMessage();
      }
    }

    Assert.isNotNull(
      message,
      'Hiding the button is not a control: the controller must refuse too.'
    );
    Assert.isTrue(
      message.contains('sandboxes only'),
      'The refusal must say why, so the administrator does not hunt for a bug: ' +
      message
    );
  }

  @IsTest
  static void reportsWhetherTheOrgIsASandbox() {
    User granted = testUser();
    TEKCO_UserMailVerifySelector.sandboxOverride = false;

    TEKCO_UserMailVerifyController.Settings settings;
    System.runAs(granted) {
      settings = TEKCO_UserMailVerifyController.getSettings();
    }

    Assert.isFalse(
      settings.isSandbox,
      'The screen needs this flag to decide whether to offer the reset button.'
    );
  }

  @IsTest
  static void queuesTheRequestedUsers() {
    User granted = testUser();
    List<User> users = insertUsers(2);
    List<Id> ids = new List<Id>(new Map<Id, User>(users).keySet());

    TEKCO_UserMailVerifyController.LaunchResult result;
    Test.startTest();
    System.runAs(granted) {
      result = TEKCO_UserMailVerifyController.launchVerification(ids);
    }
    Test.stopTest();

    Assert.areEqual(
      2,
      result.queuedCount,
      'The queued count must match the selection.'
    );
    Assert.isNotNull(
      result.jobId,
      'The job id must be returned for traceability.'
    );
  }
}
