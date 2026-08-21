/**
 * @description Launches a By Criteria run on a schedule, for wiring the tool into a
 *              post-sandbox-refresh routine rather than clicking through the interface.
 *
 *              Scope: every configured object, every brand — the same thing the interface does
 *              when nothing is narrowed. That is the shape a refresh routine wants; a narrower
 *              scope is a human decision and belongs in the interface.
 *
 *              None of the guards are bypassed. The sandbox check, the custom permission of the
 *              scheduling user and the concurrency check all still apply — a scheduled run is a
 *              run like any other.
 *
 *              WHAT YOU GIVE UP by scheduling: nobody looks at the before/after sample first.
 *              That preview exists because a misconfigured pattern produces a run reported as
 *              Success with the data left intact. Schedule this only against a configuration
 *              that has already been verified interactively at least once.
 *
 *              Example, every night at 2am:
 *                System.schedule(
 *                    'TEKCO Anonymization',
 *                    '0 0 2 * * ?',
 *                    new TEKCO_AnonymizationScheduler()
 *                );
 */
public with sharing class TEKCO_AnonymizationScheduler implements Schedulable {

    public void execute(SchedulableContext context) {
        try {
            // Same entry point as the interface, so a scheduled run cannot drift from a manual
            // one: same validation, same scope resolution, same chain.
            TEKCO_AnonymizationController.startAnonymization(
                null,   // selectedBrands        — every brand
                null,   // selectedObjects       — every configured object
                null,   // excludedFields        — nothing excluded
                null,   // selectedRecordTypes   — every record type
                null    // disabledHistoryFields — history handled as configured
            );
        } catch (Exception e) {
            // A Schedulable that throws leaves nothing an admin can read afterwards. The audit
            // log is only written once a run actually starts, so a refusal — production org,
            // missing permission, another run already in flight — has to be traced here.
            System.debug(
                LoggingLevel.ERROR,
                'TEKCO_AnonymizationScheduler: run not started — ' + e.getMessage()
            );
        }
    }
}
