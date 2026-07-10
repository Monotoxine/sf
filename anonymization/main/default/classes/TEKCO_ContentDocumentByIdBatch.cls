/**
 * @description Phase 2 of the by-ID anonymization chain.
 *              Deletes ContentDocument, Attachment and ServiceReport records linked to the
 *              explicit parent IDs. Mirrors TEKCO_ContentDocumentBatch.execute() exactly;
 *              only start() differs — it filters by explicit parent IDs instead of brand/RT.
 */
public class TEKCO_ContentDocumentByIdBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE   = 500;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    private String                                       objectApiName;
    private List<Id>                                     parentIds;
    private Id                                           auditLogId;
    private List<TEKCO_AnonymizationFieldConfig__mdt>    remainingContentDocConfigs;
    private Map<String, List<Id>>                        contentDocIdsByObject;
    private List<TEKCO_AnonymizationFieldConfig__mdt>    historyConfigs;
    private Map<String, List<Id>>                        historyIdsByObject;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;

    private Integer recordsDeleted               = 0;
    private Integer recordsFailed                = 0;
    private Integer accumulatedRecordsProcessed  = 0;
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
        Integer accumulatedDocumentsDeleted
    ) {
        this.objectApiName               = objectApiName;
        this.parentIds                   = parentIds                   != null ? parentIds                   : new List<Id>();
        this.auditLogId                  = auditLogId;
        this.remainingContentDocConfigs  = remainingContentDocConfigs  != null ? remainingContentDocConfigs  : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.contentDocIdsByObject       = contentDocIdsByObject       != null ? contentDocIdsByObject       : new Map<String, List<Id>>();
        this.historyConfigs              = historyConfigs              != null ? historyConfigs              : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.historyIdsByObject          = historyIdsByObject          != null ? historyIdsByObject          : new Map<String, List<Id>>();
        this.bypassSnapshot              = bypassSnapshot;
        this.accumulatedErrors           = accumulatedErrors           != null ? accumulatedErrors           : new List<String>();
        this.accumulatedRecordsProcessed = accumulatedRecordsProcessed != null ? accumulatedRecordsProcessed : 0;
        this.accumulatedDocumentsDeleted = accumulatedDocumentsDeleted != null ? accumulatedDocumentsDeleted : 0;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationOrgConfigService.assertIsSandbox();
        return Database.getQueryLocator(
            'SELECT Id FROM ' + objectApiName + ' WHERE Id IN :parentIds'
        );
    }

    // Identical to TEKCO_ContentDocumentBatch.execute()
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id> scopeIds = new Set<Id>();
        for (SObject record : scope) scopeIds.add(record.Id);
        if (scopeIds.isEmpty()) return;

        // ServiceReports (must be deleted before ContentDocument)
        try {
            List<SObject> serviceReports = Database.query(
                'SELECT Id FROM ServiceReport WHERE ParentId IN :scopeIds'
            );
            if (!serviceReports.isEmpty()) {
                Database.delete(serviceReports, false);
            }
        } catch (Exception e) {
            // ServiceReport not available in this org — skip
        }

        // ContentDocuments
        List<ContentDocumentLink> cdLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :scopeIds
        ];
        if (!cdLinks.isEmpty()) {
            Set<Id> cdIds = new Set<Id>();
            for (ContentDocumentLink cdl : cdLinks) cdIds.add(cdl.ContentDocumentId);
            List<ContentDocument> toDelete = new List<ContentDocument>();
            for (Id cdId : cdIds) toDelete.add(new ContentDocument(Id = cdId));
            for (Database.DeleteResult dr : Database.delete(toDelete, false)) {
                if (dr.isSuccess()) {
                    recordsDeleted++;
                } else {
                    recordsFailed++;
                    if (errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> msgs = new List<String>();
                        for (Database.Error e : dr.getErrors()) msgs.add(e.getMessage());
                        errors.add(String.join(msgs, '; '));
                    }
                }
            }
        }

        // Attachments
        List<Attachment> attachments = [
            SELECT Id FROM Attachment WHERE ParentId IN :scopeIds
        ];
        if (!attachments.isEmpty()) {
            for (Database.DeleteResult dr : Database.delete(attachments, false)) {
                if (dr.isSuccess()) {
                    recordsDeleted++;
                } else {
                    recordsFailed++;
                    if (errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> msgs = new List<String>();
                        for (Database.Error e : dr.getErrors()) msgs.add(e.getMessage());
                        errors.add(String.join(msgs, '; '));
                    }
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        accumulatedErrors.addAll(errors);
        Integer totalDocsDeleted = accumulatedDocumentsDeleted + recordsDeleted;

        try {
            if (!remainingContentDocConfigs.isEmpty()) {
                TEKCO_AnonymizationFieldConfig__mdt nextConfig = remainingContentDocConfigs.remove(0);
                String nextObj = nextConfig.TEKCO_ObjectApiName__c;
                Database.executeBatch(
                    new TEKCO_ContentDocumentByIdBatch(
                        nextObj, contentDocIdsByObject.get(nextObj), auditLogId,
                        remainingContentDocConfigs, contentDocIdsByObject,
                        historyConfigs, historyIdsByObject,
                        bypassSnapshot, accumulatedErrors, accumulatedRecordsProcessed, totalDocsDeleted
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!historyConfigs.isEmpty()) {
                String firstHistObj = historyConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> firstHistConfigs =
                    popHistoryConfigsForObject(firstHistObj);
                Database.executeBatch(
                    new TEKCO_FieldHistoryByIdBatch(
                        firstHistObj, firstHistConfigs, historyIdsByObject.get(firstHistObj),
                        auditLogId, historyConfigs, historyIdsByObject,
                        bypassSnapshot, accumulatedErrors, accumulatedRecordsProcessed, totalDocsDeleted, 0
                    ),
                    TEKCO_FieldHistoryByIdBatch.DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(
                    auditLogId, accumulatedRecordsProcessed, recordsFailed,
                    totalDocsDeleted, 0, accumulatedErrors
                );
            }
        } catch (Exception e) {
            try { TEKCO_AnonymizationBypassService.restore(bypassSnapshot); } catch (Exception ex) {}
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, accumulatedRecordsProcessed, recordsFailed,
                totalDocsDeleted, 0, accumulatedErrors, e.getMessage()
            );
        }
    }

    private List<TEKCO_AnonymizationFieldConfig__mdt> popHistoryConfigsForObject(String obj) {
        return TEKCO_AnonymizationBatchUtils.popConfigsForObject(obj, historyConfigs);
    }
}
