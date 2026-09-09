/**
 * Permission guard for the User Mail Verify tab.
 *
 * Apex invoked from a Lightning Web Component runs in system mode. Without an
 * explicit check here, any user able to reach the controller could reset
 * passwords in bulk, whether or not the tab is visible to them. Every
 * @AuraEnabled entry point calls assertAuthorized() as its first statement.
 *
 * Authorisation is granted by an assignment to the permission set named in
 * User_Mail_Verify_Setting__mdt, or by the Modify All Data permission.
 * Profiles surface as permission sets with IsOwnedByProfile = true and are
 * assigned to their users, so a single PermissionSetAssignment query covers
 * both profile-granted and permission-set-granted access.
 */
public with sharing class UserMailVerifyAccess {
  public class AccessDeniedException extends Exception {
  }

  private static Boolean cachedResult;

  public static Boolean isAuthorized() {
    if (cachedResult == null) {
      cachedResult = evaluate();
    }
    return cachedResult;
  }

  public static void assertAuthorized() {
    if (!isAuthorized()) {
      throw new AccessDeniedException(
        'You are not allowed to use User Mail Verify. This tool requires the ' +
        'permission set granting access to the Run Team Tools application.'
      );
    }
  }

  @TestVisible
  private static void clearCache() {
    cachedResult = null;
  }

  private static Boolean evaluate() {
    String permissionSetName = UserMailVerifySettings.getInstance()
      .accessPermissionSet;

    // A blank configuration must not silently open the tool up: fall back to
    // Modify All Data only.
    String nameFilter = String.isBlank(permissionSetName)
      ? '@@none@@'
      : permissionSetName;

    return ![
        SELECT Id
        FROM PermissionSetAssignment
        WHERE
          AssigneeId = :UserInfo.getUserId()
          AND (PermissionSet.Name = :nameFilter
          OR PermissionSet.PermissionsModifyAllData = TRUE)
        LIMIT 1
      ]
      .isEmpty();
  }
}
