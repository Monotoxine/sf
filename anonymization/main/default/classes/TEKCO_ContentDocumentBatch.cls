/**
 * @author
 * @description Phase 2 of the anonymization chain: deletes ContentDocument records and
 *              Attachment records linked to records of the target object, filtered by brand
 *              and/or Record Type as configured in TEKCO_AnonymizationFieldConfig__mdt
 *              (TEKCO_PatternType__c = 'DELETE_CONTENT_DOCUMENT')
 */
// Deliberately 'without sharing': anonymization must reach every record matching the
// configured scope. Running with sharing would silently skip records the launching
// user cannot see, leaving PII in place with no error.
public without sharing class TEKCO_ContentDocumentBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Each parent can own many ContentDocuments/Attachments, all counting against the
    // 10 000-row DML ceiling for the chunk. The delete service bounds its deletes to the
    // remaining budget and reports the shortfall, so an overflow no longer kills the job —
    // it surfaces as "re-run to remove the remainder" in the audit log.
    public static final Integer DEFAULT_BATCH_SIZE   = 500;
    private static final Integer MAX_CAPTURED_ERRORS  = 50;

    private String                                        objectApiName;
    private String                                        recordTypeDvName;

    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<String>                                  remainingContentDocConfigDevNames;
    private List<String>                                  historyConfigDevNames;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    private Map<String, String>                           additionalFiltersByObject;

    private Integer recordsDeleted               = 0;
    private Integer recordsFailed                = 0;
    private Integer accumulatedRecordsProcessed  = 0;
    private Integer accumulatedRecordsFailed     = 0;
    private Integer accumulatedDocumentsDeleted  = 0;
    /** Set when the sandbox guard trips in start(); finish() must not re-finalize
     *  the audit log that assertSandboxOrClose() already closed as Failed. */
    private Boolean aborted = false;
    private List<String> errors                  = new List<String>();
    private List<String> accumulatedErrors       = new List<String>();

    public TEKCO_ContentDocumentBatch(
        TEKCO_AnonymizationFieldConfig__mdt currentConfig,
        List<String> selectedBrands,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingContentDocConfigs,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed,
        Integer accumulatedRecordsFailed,
        Integer accumulatedDocumentsDeleted,
        Map<String, String> additionalFiltersByObject
    ) {
        this.objectApiName              = currentConfig?.TEKCO_ObjectApiName__c;
        this.recordTypeDvName           = currentConfig?.TEKCO_RecordTypeDeveloperName__c;
        this.selectedBrands             = selectedBrands             != null
            ? selectedBrands : new List<String>();
        this.auditLogId                 = auditLogId;
        this.remainingContentDocConfigDevNames = TEKCO_AnonymizationBatchUtils.toDevNames(remainingContentDocConfigs);
        this.historyConfigDevNames             = TEKCO_AnonymizationBatchUtils.toDevNames(historyConfigs);
        this.bypassSnapshot              = bypassSnapshot;
        this.accumulatedErrors           = accumulatedErrors           != null ? accumulatedErrors           : new List<String>();
        this.accumulatedRecordsProcessed = accumulatedRecordsProcessed != null ? accumulatedRecordsProcessed : 0;
        this.accumulatedRecordsFailed    = accumulatedRecordsFailed    != null ? accumulatedRecordsFailed    : 0;
        this.accumulatedDocumentsDeleted = accumulatedDocumentsDeleted != null ? accumulatedDocumentsDeleted : 0;
        this.additionalFiltersByObject   = additionalFiltersByObject != null
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

        try {
            return Database.getQueryLocator(
                TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery(
                    objectApiName,
                    selectedBrands,
                    recordTypeDvName,
                    additionalFiltersByObject.get(objectApiName)
                )
            );
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id> parentIds = new Set<Id>();
        for (SObject record : scope) parentIds.add(record.Id);

        TEKCO_ContentDocumentDeleteService.DeleteOutcome outcome =
            TEKCO_ContentDocumentDeleteService.deleteForParentIds(parentIds);

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
        Integer totalDocsDeleted = accumulatedDocumentsDeleted + recordsDeleted;
        Integer totalFailed      = accumulatedRecordsFailed    + recordsFailed;
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingContentDocConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(remainingContentDocConfigDevNames);
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(historyConfigDevNames);
        try {
            if (!remainingContentDocConfigs.isEmpty()) {
                TEKCO_AnonymizationFieldConfig__mdt nextConfig = remainingContentDocConfigs.remove(0);
                Database.executeBatch(
                    new TEKCO_ContentDocumentBatch(
                        nextConfig,
                        selectedBrands,
                        auditLogId,
                        remainingContentDocConfigs,
                        historyConfigs,
                        bypassSnapshot,
                        accumulatedErrors,
                        accumulatedRecordsProcessed,
                        totalFailed,
                        totalDocsDeleted,
                        additionalFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!historyConfigs.isEmpty()) {
                String firstHistoryObject = historyConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> firstObjectHistoryConfigs =
                    TEKCO_AnonymizationBatchUtils.popConfigsForObject(firstHistoryObject, historyConfigs);
                Database.executeBatch(
                    new TEKCO_FieldHistoryBatch(
                        firstHistoryObject,
                        firstObjectHistoryConfigs,
                        selectedBrands,
                        auditLogId,
                        historyConfigs,
                        bypassSnapshot,
                        accumulatedErrors,
                        accumulatedRecordsProcessed,
                        totalFailed,
                        totalDocsDeleted,
                        0,
                        additionalFiltersByObject
                    ),
                    TEKCO_FieldHistoryBatch.DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(
                    auditLogId, accumulatedRecordsProcessed, totalFailed,
                    totalDocsDeleted, 0, accumulatedErrors
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
                totalDocsDeleted, 0, accumulatedErrors, e.getMessage()
            );
        }
    }



}
