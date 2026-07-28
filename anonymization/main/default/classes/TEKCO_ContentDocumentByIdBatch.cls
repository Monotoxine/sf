/**
 * @description Phase 2 of the by-ID anonymization chain.
 *              Deletes ContentDocument, Attachment and ServiceReport records linked to the
 *              explicit parent IDs. Mirrors TEKCO_ContentDocumentBatch.execute() exactly;
 *              only start() differs — it filters by explicit parent IDs instead of brand/RT.
 */
// Deliberately 'without sharing': anonymization must reach every record matching the
// configured scope. Running with sharing would silently skip records the launching
// user cannot see, leaving PII in place with no error.
public without sharing class TEKCO_ContentDocumentByIdBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Kept low deliberately: each parent can own many ContentDocuments/Attachments,
    // and every one of them counts against the 10 000-row DML ceiling for the chunk.
    public static final Integer DEFAULT_BATCH_SIZE   = 100;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    private String                                       objectApiName;
    private List<Id>                                     parentIds;
    private Id                                           auditLogId;
    // DeveloperNames only — re-queried in finish() before chaining to keep serialized state small.
    private List<String>                                 remainingContentDocConfigDevNames;
    private Map<String, List<Id>>                        contentDocIdsByObject;
    private List<String>                                 historyConfigDevNames;
    private Map<String, List<Id>>                        historyIdsByObject;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;

    private Integer recordsDeleted               = 0;
    private Integer recordsFailed                = 0;
    private Integer accumulatedRecordsProcessed  = 0;
    private Integer accumulatedRecordsFailed     = 0;
    private Integer accumulatedDocumentsDeleted  = 0;
    private List<String> errors                  = new List<String>();
    private List<String> accumulatedErrors       = new List<String>();

    public TEKCO_ContentDocumentByIdBatch(
        String objectApiName,
        List<Id> parentIds,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingContentDocConfigs,
        Map<String, List<Id>> contentDocIdsByObject,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs,
        Map<String, List<Id>> historyIdsByObject,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed,
        Integer accumulatedRecordsFailed,
        Integer accumulatedDocumentsDeleted
    ) {
        this.objectApiName               = objectApiName;
        this.parentIds                   = parentIds                   != null ? parentIds                   : new List<Id>();
        this.auditLogId                  = auditLogId;
        this.remainingContentDocConfigDevNames = TEKCO_AnonymizationBatchUtils.toDevNames(remainingContentDocConfigs);
        this.contentDocIdsByObject       = contentDocIdsByObject       != null ? contentDocIdsByObject       : new Map<String, List<Id>>();
        this.historyConfigDevNames       = TEKCO_AnonymizationBatchUtils.toDevNames(historyConfigs);
        this.historyIdsByObject          = historyIdsByObject          != null ? historyIdsByObject          : new Map<String, List<Id>>();
        this.bypassSnapshot              = bypassSnapshot;
        this.accumulatedErrors           = accumulatedErrors           != null ? accumulatedErrors           : new List<String>();
        this.accumulatedRecordsProcessed = accumulatedRecordsProcessed != null ? accumulatedRecordsProcessed : 0;
        this.accumulatedRecordsFailed    = accumulatedRecordsFailed    != null ? accumulatedRecordsFailed    : 0;
        this.accumulatedDocumentsDeleted = accumulatedDocumentsDeleted != null ? accumulatedDocumentsDeleted : 0;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(auditLogId, bypassSnapshot)) {
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }
        return Database.getQueryLocator(
            'SELECT Id FROM ' + objectApiName + ' WHERE Id IN :parentIds'
        );
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
        for (String e : errors) {
            if (accumulatedErrors.size() < TEKCO_AnonymizationBatch.MAX_ACCUMULATED_ERRORS) {
                accumulatedErrors.add(e);
            }
        }
        Integer totalDocsDeleted = accumulatedDocumentsDeleted + recordsDeleted;
        Integer totalFailed      = accumulatedRecordsFailed    + recordsFailed;
        // Re-query CMDT lists here — only devNames were carried through execute() chunks.
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingContentDocConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(remainingContentDocConfigDevNames);
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(historyConfigDevNames);

        try {
            if (!remainingContentDocConfigs.isEmpty()) {
                TEKCO_AnonymizationFieldConfig__mdt nextConfig = remainingContentDocConfigs.remove(0);
                String nextObj = nextConfig.TEKCO_ObjectApiName__c;
                Database.executeBatch(
                    new TEKCO_ContentDocumentByIdBatch(
                        nextObj, contentDocIdsByObject.get(nextObj), auditLogId,
                        remainingContentDocConfigs, contentDocIdsByObject,
                        historyConfigs, historyIdsByObject,
                        bypassSnapshot, accumulatedErrors, accumulatedRecordsProcessed, totalFailed, totalDocsDeleted
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!historyConfigs.isEmpty()) {
                String firstHistObj = historyConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> firstHistConfigs =
                    TEKCO_AnonymizationBatchUtils.popConfigsForObject(firstHistObj, historyConfigs);
                Database.executeBatch(
                    new TEKCO_FieldHistoryByIdBatch(
                        firstHistObj, firstHistConfigs, historyIdsByObject.get(firstHistObj),
                        auditLogId, historyConfigs, historyIdsByObject,
                        bypassSnapshot, accumulatedErrors, accumulatedRecordsProcessed, totalFailed, totalDocsDeleted, 0
                    ),
                    TEKCO_FieldHistoryByIdBatch.DEFAULT_BATCH_SIZE
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
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Bypass restore failed; flags may remain enabled: ' + ex.getMessage());
            }
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, accumulatedRecordsProcessed, totalFailed,
                totalDocsDeleted, 0, accumulatedErrors, e.getMessage()
            );
        }
    }

}
