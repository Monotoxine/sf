/**
 * Entry point for the tekcoUserMailVerify Lightning Web Component.
 *
 * Every method starts with the permission check: Apex reached from a component
 * runs in system mode, so hiding the tab is not an access control.
 *
 * The per-run cap is enforced here rather than in the component. A client-side
 * check only shapes the UI; it is trivially bypassed by calling the controller
 * directly.
 */
public with sharing class TEKCO_UserMailVerifyController {
  public class Settings {
    @AuraEnabled
    public Integer maxUsersPerRun;
    @AuraEnabled
    public Integer maxRowsDisplayed;
  }

  public class LaunchResult {
    @AuraEnabled
    public Integer queuedCount;
    @AuraEnabled
    public String jobId;
  }

  @AuraEnabled(cacheable=true)
  public static Settings getSettings() {
    try {
      TEKCO_UserMailVerifyAccess.assertAuthorized();
      TEKCO_UserMailVerifySettings config = TEKCO_UserMailVerifySettings.getInstance();
      Settings result = new Settings();
      result.maxUsersPerRun = config.maxUsersPerRun;
      result.maxRowsDisplayed = config.maxRowsDisplayed;
      return result;
    } catch (Exception e) {
      throw asAuraException(e);
    }
  }

  /**
   * Deliberately not cacheable: the list changes as soon as an action runs,
   * and a stale cache here would show work that is already done.
   */
  @AuraEnabled
  public static TEKCO_UserMailVerifySelector.UserListResult getUnverifiedUsers(
    String brand
  ) {
    try {
      TEKCO_UserMailVerifyAccess.assertAuthorized();
      return TEKCO_UserMailVerifySelector.findUnverifiedByBrand(
        brand,
        TEKCO_UserMailVerifySettings.getInstance().maxRowsDisplayed
      );
    } catch (Exception e) {
      throw asAuraException(e);
    }
  }

  @AuraEnabled
  public static LaunchResult launchVerification(List<Id> userIds) {
    try {
      TEKCO_UserMailVerifyAccess.assertAuthorized();
      validateSelection(userIds);
      return toResult(
        TEKCO_UserMailVerifyQueueable.startVerification(userIds),
        userIds.size()
      );
    } catch (Exception e) {
      throw asAuraException(e);
    }
  }

  @AuraEnabled
  public static LaunchResult launchPasswordReset(List<Id> userIds) {
    try {
      TEKCO_UserMailVerifyAccess.assertAuthorized();
      validateSelection(userIds);
      return toResult(
        TEKCO_UserMailVerifyQueueable.startPasswordReset(userIds),
        userIds.size()
      );
    } catch (Exception e) {
      throw asAuraException(e);
    }
  }

  private static void validateSelection(List<Id> userIds) {
    if (userIds == null || userIds.isEmpty()) {
      throw new IllegalArgumentException('Select at least one user.');
    }
    Integer cap = TEKCO_UserMailVerifySettings.getInstance().maxUsersPerRun;
    if (userIds.size() > cap) {
      throw new IllegalArgumentException(
        'You selected ' +
          userIds.size() +
          ' users but a single run is limited to ' +
          cap +
          '. Narrow the selection and run again.'
      );
    }
    if (new Set<Id>(userIds).contains(UserInfo.getUserId())) {
      throw new IllegalArgumentException(
        'You cannot run this action on your own user.'
      );
    }
  }

  private static LaunchResult toResult(Id jobId, Integer queuedCount) {
    LaunchResult result = new LaunchResult();
    result.jobId = jobId;
    result.queuedCount = queuedCount;
    return result;
  }

  /**
   * AuraHandledException hides the original message unless it is set
   * explicitly, which would leave the component showing "Script-thrown
   * exception" for every failure.
   */
  private static AuraHandledException asAuraException(Exception e) {
    AuraHandledException wrapped = new AuraHandledException(e.getMessage());
    wrapped.setMessage(e.getMessage());
    return wrapped;
  }
}
