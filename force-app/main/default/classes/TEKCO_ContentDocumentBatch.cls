/**
 * @author TEKCO Team, 07/04/2026
 * @description Phase 2 of the anonymization chain: deletes all ContentDocument records
 *              linked to records of the target object (filtered by brand).
 *
 *              Triggered automatically from TEKCO_AnonymizationBatch.finish() for each object
 *              that has a TEKCO_AnonymizationFieldConfig__mdt entry with
 *              TEKCO_PatternType__c = 'DELETE_CONTENT_DOCUMENT'.
 *
 *              Chain: TEKCO_ContentDocumentBatch (per object) → TEKCO_FieldHistoryBatch
 */
public class TEKCO_ContentDocumentBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer DEFAULT_BATCH_SIZE  = 200;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    private String                                        objectApiName;
    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<String>                                  remainingContentDocObjects;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     historyConfigs;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    private Map<String, List<String>>                     parentFiltersByObject;

    // Populated in start() when a parent filter is active; bound in the QueryLocator string
    private Set<Id>                                       relevantChildIds;

    private Integer recordsDeleted = 0;
    private Integer recordsFailed  = 0;
    private List<String> errors    = new List<String>();

    // ── Constructor ───────────────────────────────────────────────────────────

    /**
     * @description Constructs the batch with context for one object's ContentDocument deletion.
     * @param objectApiName               API name of the object whose documents to delete.
     * @param selectedBrands              Brand values to filter parent records (empty = all).
     * @param auditLogId                  Id of the TEKCO_AnonymizationAuditLog__c record.
     * @param remainingContentDocObjects  Objects still needing ContentDocument deletion.
     * @param historyConfigs              Field configs needing history deletion (Phase 3).
     * @param bypassSnapshot              Bypass state snapshot to restore at chain end.
     * @param parentFiltersByObject       Map of child object → [parentObject, parentLookup, parentRT].
     */
    public TEKCO_ContentDocumentBatch(
        String objectApiName,
        List<String> selectedBrands,
        Id auditLogId,
        List<String> remainingContentDocObjects,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        Map<String, List<String>> parentFiltersByObject
    ) {
        this.objectApiName              = objectApiName;
        this.selectedBrands             = selectedBrands             != null
            ? selectedBrands : new List<String>();
        this.auditLogId                 = auditLogId;
        this.remainingContentDocObjects = remainingContentDocObjects != null
            ? remainingContentDocObjects : new List<String>();
        this.historyConfigs             = historyConfigs             != null
            ? historyConfigs : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.bypassSnapshot             = bypassSnapshot;
        this.parentFiltersByObject      = parentFiltersByObject != null
            ? parentFiltersByObject : new Map<String, List<String>>();
    }

    // ── Batchable Interface ───────────────────────────────────────────────────

    /**
     * @description Queries ContentDocumentLink records linked to the target object's records.
     *              Each distinct ContentDocumentId represents a file to be deleted.
     * @param bc Batch context provided by the platform.
     * @return   QueryLocator for the ContentDocumentLink records.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationSandboxGuard.assertIsSandbox();

        List<String> parentFilter = parentFiltersByObject.get(objectApiName);
        String parentObjectApiName    = (parentFilter != null && parentFilter.size() > 0) ? parentFilter.get(0) : null;
        String parentLookupField      = (parentFilter != null && parentFilter.size() > 1) ? parentFilter.get(1) : null;
        String parentRecordTypeDvName = (parentFilter != null && parentFilter.size() > 2) ? parentFilter.get(2) : null;

        String innerFilter = '';
        if (String.isNotBlank(parentObjectApiName)) {
            // Salesforce forbids nested subqueries (2 levels deep), so we resolve child IDs
            // upfront with two preparatory SOQL calls in start() (runs once per batch).
            List<String> parentConditions = new List<String>();
            if (!selectedBrands.isEmpty()) {
                parentConditions.add('TEKCO_Brand__c IN :selectedBrands');
            }
            if (String.isNotBlank(parentRecordTypeDvName)) {
                parentConditions.add(
                    'RecordType.DeveloperName = \'' + String.escapeSingleQuotes(parentRecordTypeDvName) + '\''
                );
            }
            String parentQuery = 'SELECT Id FROM ' + parentObjectApiName;
            if (!parentConditions.isEmpty()) {
                parentQuery += ' WHERE ' + String.join(parentConditions, ' AND ');
            }
            Set<Id> parentIds = new Map<Id, SObject>(Database.query(parentQuery)).keySet();
            this.relevantChildIds = new Map<Id, SObject>(
                Database.query('SELECT Id FROM ' + objectApiName
                    + ' WHERE ' + parentLookupField + ' IN :parentIds')
            ).keySet();
            innerFilter = ' WHERE Id IN :relevantChildIds';
        } else if (!selectedBrands.isEmpty()) {
            innerFilter = ' WHERE TEKCO_Brand__c IN :selectedBrands';
        }

        String soqlQuery = 'SELECT ContentDocumentId FROM ContentDocumentLink'
            + ' WHERE LinkedEntityId IN (SELECT Id FROM ' + objectApiName + innerFilter + ')';

        return Database.getQueryLocator(soqlQuery);
    }

    /**
     * @description Collects unique ContentDocument IDs from the link records and deletes them.
     * @param bc    Batch context provided by the platform.
     * @param scope ContentDocumentLink records to process in this chunk.
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id> contentDocumentIds = new Set<Id>();
        for (SObject contentDocumentLink : scope) {
            Id contentDocumentId = (Id) contentDocumentLink.get('ContentDocumentId');
            if (contentDocumentId != null) contentDocumentIds.add(contentDocumentId);
        }
        if (contentDocumentIds.isEmpty()) return;

        List<ContentDocument> contentDocumentsToDelete = new List<ContentDocument>();
        for (Id contentDocumentId : contentDocumentIds) {
            contentDocumentsToDelete.add(new ContentDocument(Id = contentDocumentId));
        }

        Database.DeleteResult[] deleteResults = Database.delete(contentDocumentsToDelete, false);
        for (Database.DeleteResult deleteResult : deleteResults) {
            if (deleteResult.isSuccess()) {
                recordsDeleted++;
            } else {
                recordsFailed++;
                if (errors.size() < MAX_CAPTURED_ERRORS) {
                    List<String> errorMessages = new List<String>();
                    for (Database.Error dmlError : deleteResult.getErrors()) {
                        errorMessages.add(dmlError.getMessage());
                    }
                    errors.add(String.join(errorMessages, '; '));
                }
            }
        }
    }

    /**
     * @description Chains to the next object's ContentDocumentBatch, or starts Phase 3,
     *              or finalizes the run if all phases are complete.
     *              Wrapped in try/catch so any error closes the audit log as Failed
     *              instead of leaving it stuck in Running status.
     * @param bc Batch context provided by the platform.
     */
    public void finish(Database.BatchableContext bc) {
        try {
            if (!remainingContentDocObjects.isEmpty()) {
                String nextObjectApiName = remainingContentDocObjects.remove(0);
                Database.executeBatch(
                    new TEKCO_ContentDocumentBatch(
                        nextObjectApiName,
                        selectedBrands,
                        auditLogId,
                        remainingContentDocObjects,
                        historyConfigs,
                        bypassSnapshot,
                        parentFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!historyConfigs.isEmpty()) {
                String firstHistoryObject = historyConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> firstObjectHistoryConfigs =
                    popHistoryConfigsForObject(firstHistoryObject);
                Database.executeBatch(
                    new TEKCO_FieldHistoryBatch(
                        firstHistoryObject,
                        firstObjectHistoryConfigs,
                        selectedBrands,
                        auditLogId,
                        historyConfigs,
                        bypassSnapshot,
                        parentFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                updateAuditLog();
            }
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) { /* silent */ }
            closeAuditLogAsFailed(e.getMessage());
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private List<TEKCO_AnonymizationFieldConfig__mdt> popHistoryConfigsForObject(
        String objectApiName
    ) {
        List<TEKCO_AnonymizationFieldConfig__mdt> configsForObject =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : historyConfigs) {
            if (fieldConfig.TEKCO_ObjectApiName__c == objectApiName) {
                configsForObject.add(fieldConfig);
            } else {
                remainingConfigs.add(fieldConfig);
            }
        }
        historyConfigs = remainingConfigs;
        return configsForObject;
    }

    private void updateAuditLog() {
        if (auditLogId == null) return;
        try {
            update new TEKCO_AnonymizationAuditLog__c(
                Id                    = auditLogId,
                TEKCO_Status__c       = recordsFailed > 0 ? 'Partial' : 'Success',
                TEKCO_EndTime__c      = Datetime.now(),
                TEKCO_ErrorMessage__c = errors.isEmpty() ? null : String.join(errors, '\n')
            );
        } catch (Exception e) {
            // Silent — audit log failure must not break the batch chain
        }
    }

    private void closeAuditLogAsFailed(String chainError) {
        if (auditLogId == null) return;
        try {
            String errorMsg = (errors.isEmpty() ? '' : String.join(errors, '\n') + '\n')
                + 'Chain error in finish(): ' + chainError;
            update new TEKCO_AnonymizationAuditLog__c(
                Id                    = auditLogId,
                TEKCO_Status__c       = 'Failed',
                TEKCO_EndTime__c      = Datetime.now(),
                TEKCO_ErrorMessage__c = errorMsg
            );
        } catch (Exception e) { /* silent */ }
    }
}
