/**
 * Entry point for the tekcoUserMailVerify Lightning Web Component.
 */
public with sharing class TEKCO_UserMailVerifyController {
  public class Settings {
    @AuraEnabled
    public Integer maxUsersPerRun;
    @AuraEnabled
    public Integer maxRowsDisplayed;
    @AuraEnabled
    public Boolean isSandbox;
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
      Settings result = new Settings();
      result.maxUsersPerRun = TEKCO_UserMailVerifyConstants.MAX_USERS_PER_RUN;
      result.maxRowsDisplayed = TEKCO_UserMailVerifyConstants.MAX_ROWS_DISPLAYED;
      result.isSandbox = TEKCO_UserMailVerifySelector.isSandbox();
      return result;
    } catch (Exception e) {
      throw asAuraException(e);
    }
  }

  @AuraEnabled(cacheable=true)
  public static List<TEKCO_UserMailVerifySelector.BrandOption> getBrands() {
    try {
      return TEKCO_UserMailVerifySelector.getBrandOptions();
    } catch (Exception e) {
      throw asAuraException(e);
    }
  }

  @AuraEnabled
  public static TEKCO_UserMailVerifySelector.UserListResult getUsers(
    List<String> brands,
    String verificationFilter,
    String suffixFilter
  ) {
    try {
      return TEKCO_UserMailVerifySelector.findByBrands(
        brands,
        verificationFilter,
        suffixFilter,
        TEKCO_UserMailVerifyConstants.MAX_ROWS_DISPLAYED
      );
    } catch (Exception e) {
      throw asAuraException(e);
    }
  }

  @AuraEnabled
  public static LaunchResult launchVerification(List<Id> userIds) {
    try {
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
      assertResetAllowed();
      validateSelection(userIds);
      return toResult(
        TEKCO_UserMailVerifyQueueable.startPasswordReset(userIds),
        userIds.size()
      );
    } catch (Exception e) {
      throw asAuraException(e);
    }
  }

  private static void assertResetAllowed() {
    if (!TEKCO_UserMailVerifySelector.isSandbox()) {
      throw new IllegalArgumentException(
        'Password reset is available in sandboxes only. In production, users ' +
        'sign in through SSO and have no Salesforce password to set.'
      );
    }
  }

  private static void validateSelection(List<Id> userIds) {
    if (userIds == null || userIds.isEmpty()) {
      throw new IllegalArgumentException('Select at least one user.');
    }
    Integer cap = TEKCO_UserMailVerifyConstants.MAX_USERS_PER_RUN;
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

  private static AuraHandledException asAuraException(Exception e) {
    AuraHandledException wrapped = new AuraHandledException(e.getMessage());
    wrapped.setMessage(e.getMessage());
    return wrapped;
  }
}
