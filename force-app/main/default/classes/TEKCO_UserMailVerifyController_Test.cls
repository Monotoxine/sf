@IsTest
private class TEKCO_UserMailVerifyController_Test {
  /** Reset is sandbox-only, so the tests that exercise it assume one. */
  private static User testUser() {
    User u = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvctl',
      'ctl@umv-test.example.com'
    );
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
      3,
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

    // Synthetic ids: the cap is checked before any query, so no user needs to
    // exist. Inserting MAX_USERS_PER_RUN + 1 real users would be gratuitous.
    List<Id> ids = new List<Id>();
    for (
      Integer i = 0; i <= TEKCO_UserMailVerifyConstants.MAX_USERS_PER_RUN; i++
    ) {
      // Padded to 15 characters: an 18-character id would need a valid
      // checksum suffix, and a 12-digit literal overflows an Apex Integer.
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
    List<User> users = TEKCO_UserMailVerifyTestUtil.insertUsers(1);
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
    List<User> users = TEKCO_UserMailVerifyTestUtil.insertUsers(2);
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
