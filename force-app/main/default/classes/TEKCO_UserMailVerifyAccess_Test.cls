@IsTest
private class TEKCO_UserMailVerifyAccess_Test {
  @IsTest
  static void deniesAUserWithoutThePermissionSet() {
    User plain = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvden',
      'den@umv-test.example.com'
    );
    insert plain;

    TEKCO_UserMailVerifyTestUtil.applySettings(
      200,
      50,
      10,
      'UMV_NonExistent_PermSet'
    );

    Boolean denied = false;
    System.runAs(plain) {
      TEKCO_UserMailVerifyAccess.clearCache();
      try {
        TEKCO_UserMailVerifyAccess.assertAuthorized();
      } catch (TEKCO_UserMailVerifyAccess.AccessDeniedException e) {
        denied = true;
      }
    }

    Assert.isTrue(
      denied,
      'A user holding neither the permission set nor Modify All Data must be refused: ' +
      'Apex called from LWC runs in system mode, so the tab being hidden is not a control.'
    );
  }

  @IsTest
  static void grantsAUserAssignedToTheConfiguredPermissionSet() {
    User granted = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvok',
      'ok@umv-test.example.com'
    );
    insert granted;

    PermissionSet permSet = new PermissionSet(
      Name = 'UMV_Test_Access',
      Label = 'UMV Test Access'
    );
    insert permSet;
    insert new PermissionSetAssignment(
      AssigneeId = granted.Id,
      PermissionSetId = permSet.Id
    );

    TEKCO_UserMailVerifyTestUtil.applySettings(200, 50, 10, 'UMV_Test_Access');

    Boolean authorized = false;
    System.runAs(granted) {
      TEKCO_UserMailVerifyAccess.clearCache();
      authorized = TEKCO_UserMailVerifyAccess.isAuthorized();
    }

    Assert.isTrue(
      authorized,
      'An assignment to the configured permission set must grant access.'
    );
  }

  @IsTest
  static void blankConfigurationDoesNotOpenAccessUp() {
    User plain = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvblk',
      'blk@umv-test.example.com'
    );
    insert plain;

    TEKCO_UserMailVerifyTestUtil.applySettings(200, 50, 10, null);

    Boolean authorized = true;
    System.runAs(plain) {
      TEKCO_UserMailVerifyAccess.clearCache();
      authorized = TEKCO_UserMailVerifyAccess.isAuthorized();
    }

    Assert.isFalse(
      authorized,
      'An unconfigured permission set name must fall back to Modify All Data only, ' +
      'never to open access.'
    );
  }
}
