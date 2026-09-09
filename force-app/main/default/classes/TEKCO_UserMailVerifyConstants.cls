/**
 * Fixed values for the User Mail Verify feature.
 *
 * These were held in a custom metadata type at first. That was over-engineering:
 * none of them is expected to change, the reset chunk size cannot legally differ
 * from the platform cap, and the notification type names a component this
 * feature ships itself. A configuration layer for values nobody will edit only
 * bought an extra SOQL query per transaction and a layer of indirection.
 *
 * Changing any of these is a code change, reviewed and deployed like the rest.
 */
public with sharing class TEKCO_UserMailVerifyConstants {
  /** DeveloperName of the notification type shipped with the feature. */
  public static final String NOTIFICATION_TYPE = 'TEKCO_UserMailVerify_Run_Complete';

  /** Blocking cap per run, enforced server-side. Guards against a mass send by mistake. */
  public static final Integer MAX_USERS_PER_RUN = 200;

  /** Users processed per transaction when sending verification links. */
  public static final Integer CHUNK_SIZE_VERIFY = 50;

  /**
   * System.resetPassword is capped at 10 calls per transaction by the platform.
   * This is both the chunk size for a reset run and the ceiling the batch
   * enforces; there is no sane reason for the two to differ.
   */
  public static final Integer RESET_HARD_LIMIT = 10;

  /** Rows the tab will display for one brand before truncating. */
  public static final Integer MAX_ROWS_DISPLAYED = 500;
}
