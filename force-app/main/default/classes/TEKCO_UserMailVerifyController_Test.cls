@IsTest
private class TEKCO_UserMailVerifyController_Test {
  private static User grantedUser() {
    User u = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvctl',
      'ctl@umv-test.example.com'
    );
    insert u;

    PermissionSet permSet = new PermissionSet(
      Name = 'UMV_Ctl_Access',
      Label = 'UMV Controller Access'
    );
    insert permSet;
    insert new PermissionSetAssignment(
      AssigneeId = u.Id,
      PermissionSetId = permSet.Id
    );

    TEKCO_UserMailVerifyTestUtil.useAccessPermissionSet('UMV_Ctl_Access');
    // Reset is sandbox-only; the tests that exercise it assume one.
    TEKCO_UserMailVerifySelector.sandboxOverride = true;
    return u;
  }

  @IsTest
  static void refusesAnUnauthorizedCaller() {
    User plain = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvna',
      'na@umv-test.example.com'
    );
    insert plain;
    TEKCO_UserMailVerifyTestUtil.useAccessPermissionSet(
      'UMV_NonExistent_PermSet'
    );

    Boolean refused = false;
    System.runAs(plain) {
      TEKCO_UserMailVerifyAccess.clearCache();
      try {
        TEKCO_UserMailVerifyController.getUsers(
          new List<String>{ TEKCO_UserMailVerifyTestUtil.testBrand() },
          TEKCO_UserMailVerifySelector.FILTER_UNVERIFIED,
          TEKCO_UserMailVerifySelector.SUFFIX_ALL
        );
      } catch (Exception e) {
        refused = true;
      }
    }

    Assert.isTrue(
      refused,
      'The controller must refuse a caller without the permission set.'
    );
  }

  @IsTest
  static void exposesTheConfiguredCaps() {
    User granted = grantedUser();

    TEKCO_UserMailVerifyController.Settings settings;
    System.runAs(granted) {
      TEKCO_UserMailVerifyAccess.clearCache();
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
    User granted = grantedUser();

    Boolean rejected = false;
    System.runAs(granted) {
      TEKCO_UserMailVerifyAccess.clearCache();
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
    User granted = grantedUser();

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
      TEKCO_UserMailVerifyAccess.clearCache();
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
    User granted = grantedUser();

    String message;
    System.runAs(granted) {
      TEKCO_UserMailVerifyAccess.clearCache();
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
    User granted = grantedUser();
    TEKCO_UserMailVerifySelector.sandboxOverride = false;
    List<User> users = TEKCO_UserMailVerifyTestUtil.insertUsers(1);
    List<Id> ids = new List<Id>(new Map<Id, User>(users).keySet());

    String message;
    System.runAs(granted) {
      TEKCO_UserMailVerifyAccess.clearCache();
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
    User granted = grantedUser();
    TEKCO_UserMailVerifySelector.sandboxOverride = false;

    TEKCO_UserMailVerifyController.Settings settings;
    System.runAs(granted) {
      TEKCO_UserMailVerifyAccess.clearCache();
      settings = TEKCO_UserMailVerifyController.getSettings();
    }

    Assert.isFalse(
      settings.isSandbox,
      'The screen needs this flag to decide whether to offer the reset button.'
    );
  }

  @IsTest
  static void queuesTheRequestedUsers() {
    User granted = grantedUser();
    TEKCO_UserMailVerifyTestUtil.installSpy();
    List<User> users = TEKCO_UserMailVerifyTestUtil.insertUsers(2);
    List<Id> ids = new List<Id>(new Map<Id, User>(users).keySet());

    TEKCO_UserMailVerifyController.LaunchResult result;
    Test.startTest();
    System.runAs(granted) {
      TEKCO_UserMailVerifyAccess.clearCache();
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
