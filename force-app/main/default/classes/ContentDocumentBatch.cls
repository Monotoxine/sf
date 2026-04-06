/**
 * ContentDocumentBatch
 * Phase 2 of the anonymization chain: deletes all ContentDocument records
 * linked to records of the target object (filtered by brand).
 *
 * Triggered automatically from AnonymizationBatch.finish() for each object
 * that has a TEKCO_AnonymizationFieldConfig__mdt entry with
 * Pattern_Type__c = 'DELETE_CONTENT_DOCUMENT'.
 *
 * Chain: ContentDocumentBatch (per object) → FieldHistoryBatch
 */
public class ContentDocumentBatch implements Database.Batchable<SObject>, Database.Stateful {

    private String                                       objectApiName;
    private List<String>                                 selectedBrands;
    private Id                                           auditLogId;
    private List<String>                                 remainingContentDocObjects;
    private List<TEKCO_AnonymizationFieldConfig__mdt>    historyConfigs;

    private Integer recordsDeleted = 0;
    private Integer recordsFailed  = 0;
    private List<String> errors    = new List<String>();

    private static final Integer DEFAULT_BATCH_SIZE = 200;

    // ── Constructor ───────────────────────────────────────────────────────────

    public ContentDocumentBatch(
        String objectApiName,
        List<String> selectedBrands,
        Id auditLogId,
        List<String> remainingContentDocObjects,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs
    ) {
        this.objectApiName              = objectApiName;
        this.selectedBrands             = selectedBrands             != null ? selectedBrands             : new List<String>();
        this.auditLogId                 = auditLogId;
        this.remainingContentDocObjects = remainingContentDocObjects != null ? remainingContentDocObjects : new List<String>();
        this.historyConfigs             = historyConfigs             != null ? historyConfigs             : new List<TEKCO_AnonymizationFieldConfig__mdt>();
    }

    // ── Batchable Interface ───────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        AnonymizationSandboxGuard.assertIsSandbox();

        // Query ContentDocumentLink for all records of the target object
        // (optionally filtered by brand). Each distinct ContentDocumentId
        // is a file to be deleted.
        String soql = 'SELECT ContentDocumentId FROM ContentDocumentLink'
                    + ' WHERE LinkedEntityId IN (SELECT Id FROM ' + objectApiName;

        if (!selectedBrands.isEmpty()) {
            soql += ' WHERE TEKCO_Brand__c IN :selectedBrands';
        }

        soql += ')';

        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        // Collect unique ContentDocument IDs from the links
        Set<Id> docIds = new Set<Id>();
        for (SObject link : scope) {
            Id docId = (Id) link.get('ContentDocumentId');
            if (docId != null) docIds.add(docId);
        }
        if (docIds.isEmpty()) return;

        List<ContentDocument> docs = new List<ContentDocument>();
        for (Id docId : docIds) {
            docs.add(new ContentDocument(Id = docId));
        }

        Database.DeleteResult[] results = Database.delete(docs, false);
        for (Database.DeleteResult r : results) {
            if (r.isSuccess()) {
                recordsDeleted++;
            } else {
                recordsFailed++;
                if (errors.size() < 50) {
                    List<String> msgs = new List<String>();
                    for (Database.Error err : r.getErrors()) msgs.add(err.getMessage());
                    errors.add(String.join(msgs, '; '));
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!remainingContentDocObjects.isEmpty()) {
            // More objects need ContentDocument deletion
            String nextObj = remainingContentDocObjects.remove(0);
            Database.executeBatch(
                new ContentDocumentBatch(nextObj, selectedBrands, auditLogId,
                                         remainingContentDocObjects, historyConfigs),
                DEFAULT_BATCH_SIZE
            );
        } else if (!historyConfigs.isEmpty()) {
            // Phase 3: Field history deletion
            String firstObj = historyConfigs[0].Object_API_Name__c;
            List<TEKCO_AnonymizationFieldConfig__mdt> objConfigs = popHistoryConfigsForObject(firstObj);
            Database.executeBatch(
                new FieldHistoryBatch(firstObj, objConfigs, selectedBrands, auditLogId, historyConfigs),
                DEFAULT_BATCH_SIZE
            );
        } else {
            updateAuditLog();
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private List<TEKCO_AnonymizationFieldConfig__mdt> popHistoryConfigsForObject(String objectName) {
        List<TEKCO_AnonymizationFieldConfig__mdt> forObj    = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> remaining = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt cfg : historyConfigs) {
            if (cfg.Object_API_Name__c == objectName) forObj.add(cfg);
            else remaining.add(cfg);
        }
        historyConfigs = remaining;
        return forObj;
    }

    private void updateAuditLog() {
        if (auditLogId == null) return;
        try {
            update new Anonymization_Audit_Log__c(
                Id        = auditLogId,
                Status__c = recordsFailed > 0 ? 'Partial' : 'Success',
                End_Time__c = Datetime.now(),
                Error_Message__c = errors.isEmpty() ? null : String.join(errors, '\n')
            );
        } catch (Exception e) {}
    }
}
