@IsTest
private class TEKCO_UserMailVerifyAccess_Test {
  @IsTest
  static void deniesAUserWithoutThePermissionSet() {
    User plain = TEKCO_UserMailVerifyTestUtil.buildUser(
      'umvden',
      'den@umv-test.example.com'
    );
    insert plain;

    TEKCO_UserMailVerifyTestUtil.useAccessPermissionSet(
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

    TEKCO_UserMailVerifyTestUtil.useAccessPermissionSet('UMV_Test_Access');

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
  static void defaultsToTheShippedPermissionSetName() {
    Assert.areEqual(
      TEKCO_UserMailVerifyConstants.ACCESS_PERMISSION_SET,
      TEKCO_UserMailVerifyConstants.accessPermissionSet(),
      'Without a test override, the check must use the shipped constant.'
    );
  }
}
