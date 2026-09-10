/**
 * Fixed values for the User Mail Verify feature.
 */
public with sharing class TEKCO_UserMailVerifyConstants {
  /** DeveloperName of the notification type shipped with the feature. */
  public static final String NOTIFICATION_TYPE = 'TEKCO_UserMailVerify_Run_Complete';

  /** Guards against a mass send by mistake. */
  public static final Integer MAX_USERS_PER_RUN = 200;

  /** Users processed per transaction when sending verification links. */
  public static final Integer CHUNK_SIZE_VERIFY = 50;

  /** System.resetPassword is capped at 10 calls per transaction by the platform.*/
  public static final Integer RESET_HARD_LIMIT = 10;

  /** Rows the tab will display for one brand before truncating. */
  public static final Integer MAX_ROWS_DISPLAYED = 500;
}
