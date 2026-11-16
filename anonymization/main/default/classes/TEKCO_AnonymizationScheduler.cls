/**
 * @description Launches a By Criteria run on a schedule; the second constructor narrows its scope.
 */
public with sharing class TEKCO_AnonymizationScheduler implements Schedulable {

    @TestVisible private static final String STATUS_REFUSED = 'Refused';

    private final List<String> recordTypes;
    private final List<String> objects;
    private final List<String> brands;

    public TEKCO_AnonymizationScheduler() {
        this(null, null, null);
    }

    public TEKCO_AnonymizationScheduler(
        List<String> recordTypes, List<String> objects, List<String> brands
    ) {
        this.recordTypes = recordTypes;
        this.objects     = objects;
        this.brands      = brands;
    }

    public void execute(SchedulableContext context) {
        try {
            lockAgainstSameTimeSchedules();
        } catch (Exception e) {
            recordRefusal('another scheduled run held the lock (' + e.getMessage() + ')');
            return;
        }

        Savepoint beforeLaunch = Database.setSavepoint();
        try {
            TEKCO_AnonymizationController.startAnonymization(
                brands,
                objects,
                null,   // excludedFields
                recordTypes,
                null    // history handled as configured
            );
        } catch (Exception e) {
            Database.rollback(beforeLaunch);
            recordRefusal(e.getMessage());
        }
    }

    /** Locks the org-wide bypass settings row until this transaction commits. */
    private static void lockAgainstSameTimeSchedules() {
        List<TEKCO_BypassSettings__c> orgDefault = [
            SELECT Id FROM TEKCO_BypassSettings__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
            LIMIT 1 FOR UPDATE
        ];
        if (orgDefault.isEmpty()) {
            System.debug(LoggingLevel.WARN, 'TEKCO_AnonymizationScheduler: no org-wide '
                + 'TEKCO_BypassSettings__c row to lock; same-time schedules are not serialized.');
        }
    }

    private void recordRefusal(String reason) {
        try {
            Datetime now = Datetime.now();
            insert new TEKCO_AnonymizationAuditLog__c(
                TEKCO_TriggeredBy__c   = UserInfo.getUserId(),
                TEKCO_BrandFilter__c   = labelFor(brands),
                TEKCO_ObjectApiName__c = labelFor(objects),
                TEKCO_RunMode__c       = 'BY_CRITERIA',
                TEKCO_Status__c        = STATUS_REFUSED,
                TEKCO_StartTime__c     = now,
                TEKCO_EndTime__c       = now,
                TEKCO_ErrorMessage__c  = TEKCO_AnonymizationRunContext.cap(
                    'Scheduled run not started: ' + reason
                )
            );
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'TEKCO_AnonymizationScheduler: run not started — ' + reason
                + ' (and the refusal could not be logged: ' + e.getMessage() + ')'
            );
        }
    }

    private static String labelFor(List<String> values) {
        return values == null || values.isEmpty() ? 'ALL' : String.join(values, ', ');
    }
}
