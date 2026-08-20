/**
 * @author
 * @description Phase 3 of the anonymization chain: deletes field history records for
 *              fields where TEKCO_AnonymizationFieldConfig__mdt.TEKCO_DeleteHistory__c = true
 */
// Deliberately 'without sharing': anonymization must reach every record matching the
// configured scope. Running with sharing would silently skip records the launching
// user cannot see, leaving PII in place with no error.
public without sharing class TEKCO_FieldHistoryBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE   = 2000;
    private static final Integer MAX_CAPTURED_ERRORS  = 50;

    private String                                        objectApiName;
    private List<String>                                  objectHistoryConfigDevNames;
    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<String>                                  remainingHistoryConfigDevNames;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    private Map<String, String>                           additionalFiltersByObject;

    private Integer recordsDeleted                   = 0;
    private Integer recordsFailed                    = 0;
    private Integer accumulatedRecordsProcessed      = 0;
    private Integer accumulatedRecordsFailed         = 0;
    private Integer accumulatedDocumentsDeleted      = 0;
    private Integer accumulatedHistoryRecordsDeleted = 0;
    /** Set when the sandbox guard trips in start(); finish() must not re-finalize
     *  the audit log that assertSandboxOrClose() already closed as Failed. */
    private Boolean aborted = false;
    private List<String> errors                      = new List<String>();
    private List<String> accumulatedErrors           = new List<String>();

    public TEKCO_FieldHistoryBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> objectHistoryConfigs,
        List<String> selectedBrands,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed,
        Integer accumulatedRecordsFailed,
        Integer accumulatedDocumentsDeleted,
        Integer accumulatedHistoryRecordsDeleted,
        Map<String, String> additionalFiltersByObject
    ) {
        this.objectApiName                = objectApiName;
        this.objectHistoryConfigDevNames    = TEKCO_AnonymizationBatchUtils.toDevNames(objectHistoryConfigs);
        this.selectedBrands                 = selectedBrands != null ? selectedBrands : new List<String>();
        this.auditLogId                     = auditLogId;
        this.remainingHistoryConfigDevNames = TEKCO_AnonymizationBatchUtils.toDevNames(remainingHistoryConfigs);
        this.bypassSnapshot                   = bypassSnapshot;
        this.accumulatedErrors                = accumulatedErrors                != null ? accumulatedErrors                : new List<String>();
        this.accumulatedRecordsProcessed      = accumulatedRecordsProcessed      != null ? accumulatedRecordsProcessed      : 0;
        this.accumulatedRecordsFailed         = accumulatedRecordsFailed         != null ? accumulatedRecordsFailed         : 0;
        this.accumulatedDocumentsDeleted      = accumulatedDocumentsDeleted      != null ? accumulatedDocumentsDeleted      : 0;
        this.accumulatedHistoryRecordsDeleted = accumulatedHistoryRecordsDeleted != null ? accumulatedHistoryRecordsDeleted : 0;
        this.additionalFiltersByObject        = additionalFiltersByObject != null
            ? additionalFiltersByObject : new Map<String, String>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(auditLogId, bypassSnapshot)) {
            aborted = true;
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        if (!TEKCO_AnonymizationOrgConfigService.hasObject(objectApiName)) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        String historyObjectName = TEKCO_AnonymizationBatchUtils.computeHistoryObjectName(objectApiName);
        String parentIdFieldName = TEKCO_AnonymizationBatchUtils.computeParentIdFieldName(objectApiName);

        if (!TEKCO_AnonymizationOrgConfigService.hasObject(historyObjectName)) {
            errors.add('Field history not enabled for object, skipped: ' + objectApiName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            Set<String> historyFieldNames = new Set<String>();
            for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig :
                    TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(objectHistoryConfigDevNames)) {
                if (String.isNotBlank(fieldConfig.TEKCO_FieldApiName__c)) {
                    historyFieldNames.add(fieldConfig.TEKCO_FieldApiName__c);
                }
            }

            String soqlQuery = TEKCO_AnonymizationScopeQueryBuilder.buildHistoryScopeQuery(
                objectApiName,
                historyObjectName,
                parentIdFieldName,
                historyFieldNames,
                selectedBrands,
                additionalFiltersByObject.get(objectApiName)
            );

            // No targeted field would produce 'Field IN ()' — invalid SOQL. The By ID chain
            // already skipped in that case; this one used to report a parse error instead.
            if (soqlQuery == null) {
                errors.add('No history fields configured for object, skipped: ' + objectApiName);
                return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
            }

            return Database.getQueryLocator(soqlQuery);
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        TEKCO_FieldHistoryDeleteService.DeleteOutcome outcome =
            TEKCO_FieldHistoryDeleteService.deleteHistoryRecords(scope);

        recordsDeleted += outcome.recordsDeleted;
        recordsFailed  += outcome.recordsFailed;
        for (String e : outcome.errors) {
            if (errors.size() < MAX_CAPTURED_ERRORS) errors.add(e);
        }
    }

    public void finish(Database.BatchableContext bc) {
        // The sandbox guard already closed the audit log as Failed — do not overwrite it.
        if (aborted) return;

        for (String e : errors) {
            if (accumulatedErrors.size() < TEKCO_AnonymizationBatch.MAX_ACCUMULATED_ERRORS) {
                accumulatedErrors.add(e);
            }
        }
        Integer totalHistoryDeleted = accumulatedHistoryRecordsDeleted + recordsDeleted;
        Integer totalFailed         = accumulatedRecordsFailed         + recordsFailed;
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(remainingHistoryConfigDevNames);
        try {
            if (!remainingHistoryConfigs.isEmpty()) {
                String nextObjectApiName = remainingHistoryConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> nextObjectConfigs =
                    TEKCO_AnonymizationBatchUtils.popConfigsForObject(nextObjectApiName, remainingHistoryConfigs);
                Database.executeBatch(
                    new TEKCO_FieldHistoryBatch(
                        nextObjectApiName,
                        nextObjectConfigs,
                        selectedBrands,
                        auditLogId,
                        remainingHistoryConfigs,
                        bypassSnapshot,
                        accumulatedErrors,
                        accumulatedRecordsProcessed,
                        totalFailed,
                        accumulatedDocumentsDeleted,
                        totalHistoryDeleted,
                        additionalFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(
                    auditLogId, accumulatedRecordsProcessed, totalFailed,
                    accumulatedDocumentsDeleted, totalHistoryDeleted, accumulatedErrors
                );
                return;
            }
            TEKCO_AnonymizationAuditService.markRunning(
                auditLogId, accumulatedRecordsProcessed, totalFailed, accumulatedErrors
            );
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) {
                System.debug(LoggingLevel.ERROR, 'Bypass restore failed; flags may remain enabled: ' + restoreEx.getMessage());
            }
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, accumulatedRecordsProcessed, totalFailed,
                accumulatedDocumentsDeleted, totalHistoryDeleted, accumulatedErrors, e.getMessage()
            );
        }
    }


}
