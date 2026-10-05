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
           
            TEKCO_AnonymizationController.startAnonymization(
                null,   // every brand
                null,   // configured object
                null,   // excludedFields
                null,   // every record type
                null    // history handled as configured
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'TEKCO_AnonymizationScheduler: run not started — ' + e.getMessage()
            );
        }
    }
}
