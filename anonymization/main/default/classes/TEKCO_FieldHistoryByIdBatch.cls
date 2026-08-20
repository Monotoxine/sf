/**
 * @description Phase 3 of the by-ID anonymization chain.
 *              Deletes field history records for the given record IDs where
 *              TEKCO_AnonymizationFieldConfig__mdt.TEKCO_DeleteHistory__c = true.
 *              Mirrors TEKCO_FieldHistoryBatch but filters by explicit parent IDs.
 */
// Deliberately 'without sharing': anonymization must reach every record matching the
// configured scope. Running with sharing would silently skip records the launching
// user cannot see, leaving PII in place with no error.
public without sharing class TEKCO_FieldHistoryByIdBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE   = 2000;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    private String                                       objectApiName;
    // DeveloperNames only — re-queried locally in start() and finish() to keep serialized state small.
    private List<String>                                 objectHistoryConfigDevNames;
    private List<Id>                                     recordIds;
    private Id                                           auditLogId;
    private List<String>                                 remainingHistoryConfigDevNames;
    private Map<String, List<Id>>                        historyIdsByObject;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;

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

    public TEKCO_FieldHistoryByIdBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> objectHistoryConfigs,
        List<Id> recordIds,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs,
        Map<String, List<Id>> historyIdsByObject,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed,
        Integer accumulatedRecordsFailed,
        Integer accumulatedDocumentsDeleted,
        Integer accumulatedHistoryRecordsDeleted
    ) {
        this.objectApiName                    = objectApiName;
        this.objectHistoryConfigDevNames      = TEKCO_AnonymizationBatchUtils.toDevNames(objectHistoryConfigs);
        this.recordIds                        = recordIds              != null ? recordIds              : new List<Id>();
        this.auditLogId                       = auditLogId;
        this.remainingHistoryConfigDevNames   = TEKCO_AnonymizationBatchUtils.toDevNames(remainingHistoryConfigs);
        this.historyIdsByObject               = historyIdsByObject     != null ? historyIdsByObject     : new Map<String, List<Id>>();
        this.bypassSnapshot                   = bypassSnapshot;
        this.accumulatedErrors                = accumulatedErrors                != null ? accumulatedErrors                : new List<String>();
        this.accumulatedRecordsProcessed      = accumulatedRecordsProcessed      != null ? accumulatedRecordsProcessed      : 0;
        this.accumulatedRecordsFailed         = accumulatedRecordsFailed         != null ? accumulatedRecordsFailed         : 0;
        this.accumulatedDocumentsDeleted      = accumulatedDocumentsDeleted      != null ? accumulatedDocumentsDeleted      : 0;
        this.accumulatedHistoryRecordsDeleted = accumulatedHistoryRecordsDeleted != null ? accumulatedHistoryRecordsDeleted : 0;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(auditLogId, bypassSnapshot)) {
            aborted = true;
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        String historyObjectName = TEKCO_AnonymizationBatchUtils.computeHistoryObjectName(objectApiName);
        String parentIdFieldName = TEKCO_AnonymizationBatchUtils.computeParentIdFieldName(objectApiName);

        try { Schema.describeSObjects(new List<String>{ historyObjectName }); }
        catch (Exception e) {
            errors.add('Field history not enabled for object, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        try {
            // Re-query locally — only devNames were carried through serialization.
            List<TEKCO_AnonymizationFieldConfig__mdt> objectHistoryConfigs =
                TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(objectHistoryConfigDevNames);

            Set<String> fieldApiNames = new Set<String>();
            for (TEKCO_AnonymizationFieldConfig__mdt fc : objectHistoryConfigs) {
                if (String.isNotBlank(fc.TEKCO_FieldApiName__c)) fieldApiNames.add(fc.TEKCO_FieldApiName__c);
            }

            // No fields to target would produce 'Field IN ()' — invalid SOQL. Skip instead.
            if (fieldApiNames.isEmpty()) {
                errors.add('No history fields configured for object, skipped: ' + objectApiName);
                return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
            }

            List<String> escapedFields = new List<String>();
            for (String fn : fieldApiNames) {
                escapedFields.add('\'' + String.escapeSingleQuotes(fn) + '\'');
            }

            return Database.getQueryLocator(
                'SELECT Id FROM ' + historyObjectName
                + ' WHERE Field IN (' + String.join(escapedFields, ', ') + ')'
                + ' AND ' + parentIdFieldName + ' IN :recordIds'
            );
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
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
        // Re-query CMDT list here — only devNames were carried through execute() chunks.
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(remainingHistoryConfigDevNames);

        try {
            if (!remainingHistoryConfigs.isEmpty()) {
                String nextObj = remainingHistoryConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> nextConfigs =
                    TEKCO_AnonymizationBatchUtils.popConfigsForObject(nextObj, remainingHistoryConfigs);
                Database.executeBatch(
                    new TEKCO_FieldHistoryByIdBatch(
                        nextObj, nextConfigs, historyIdsByObject.get(nextObj),
                        auditLogId, remainingHistoryConfigs, historyIdsByObject,
                        bypassSnapshot, accumulatedErrors, accumulatedRecordsProcessed, totalFailed,
                        accumulatedDocumentsDeleted, totalHistoryDeleted
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
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Bypass restore failed; flags may remain enabled: ' + ex.getMessage());
            }
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, accumulatedRecordsProcessed, totalFailed,
                accumulatedDocumentsDeleted, totalHistoryDeleted, accumulatedErrors, e.getMessage()
            );
        }
    }

}
