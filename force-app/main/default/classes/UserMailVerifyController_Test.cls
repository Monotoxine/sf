@IsTest
private class UserMailVerifyController_Test {
  private static User grantedUser() {
    User u = UserMailVerifyTestUtil.buildUser(
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

    UserMailVerifyTestUtil.applySettings(3, 50, 10, 'UMV_Ctl_Access');
    return u;
  }

  @IsTest
  static void refusesAnUnauthorizedCaller() {
    User plain = UserMailVerifyTestUtil.buildUser(
      'umvna',
      'na@umv-test.example.com'
    );
    insert plain;
    UserMailVerifyTestUtil.applySettings(
      200,
      50,
      10,
      'UMV_NonExistent_PermSet'
    );

    Boolean refused = false;
    System.runAs(plain) {
      UserMailVerifyAccess.clearCache();
      try {
        UserMailVerifyController.getUnverifiedUsers(
          UserMailVerifyTestUtil.TEST_BRAND
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

    UserMailVerifyController.Settings settings;
    System.runAs(granted) {
      UserMailVerifyAccess.clearCache();
      settings = UserMailVerifyController.getSettings();
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
      UserMailVerifyAccess.clearCache();
      try {
        UserMailVerifyController.launchVerification(new List<Id>());
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
    List<User> users = UserMailVerifyTestUtil.insertUsers(4);
    List<Id> ids = new List<Id>(new Map<Id, User>(users).keySet());

    String message;
    System.runAs(granted) {
      UserMailVerifyAccess.clearCache();
      try {
        UserMailVerifyController.launchVerification(ids);
      } catch (Exception e) {
        message = e.getMessage();
      }
    }

    Assert.isNotNull(
      message,
      'The cap must be enforced server-side, not only in the component.'
    );
    Assert.isTrue(
      message.contains('limited to 3'),
      'The error must name the cap so the administrator knows what to do: ' +
      message
    );
  }

  @IsTest
  static void refusesToActOnTheCallersOwnUser() {
    User granted = grantedUser();

    String message;
    System.runAs(granted) {
      UserMailVerifyAccess.clearCache();
      try {
        UserMailVerifyController.launchPasswordReset(
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
  static void queuesTheRequestedUsers() {
    User granted = grantedUser();
    UserMailVerifyTestUtil.installSpy();
    List<User> users = UserMailVerifyTestUtil.insertUsers(2);
    List<Id> ids = new List<Id>(new Map<Id, User>(users).keySet());

    UserMailVerifyController.LaunchResult result;
    Test.startTest();
    System.runAs(granted) {
      UserMailVerifyAccess.clearCache();
      result = UserMailVerifyController.launchVerification(ids);
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
