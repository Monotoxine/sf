/**
 * @author TEKCO Team, 07/04/2026
 * @description Phase 2 of the anonymization chain: deletes ContentDocument records
 *              linked to records of the target object, filtered by brand and/or Record Type
 *              as configured in TEKCO_AnonymizationFieldConfig__mdt
 *              (TEKCO_PatternType__c = 'DELETE_CONTENT_DOCUMENT').
 *
 *              One batch instance per CMT config — multiple configs for the same object
 *              with different Record Types each get their own batch run.
 *
 *              Chain: TEKCO_ContentDocumentBatch (per config) → TEKCO_FieldHistoryBatch
 */
public class TEKCO_ContentDocumentBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer DEFAULT_BATCH_SIZE  = 200;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    // Extracted from the current CMT config
    private String                                        objectApiName;
    private String                                        recordTypeDvName;

    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     remainingContentDocConfigs;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     historyConfigs;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    private Map<String, List<String>>                     parentFiltersByObject;
    private Map<String, String>                           additionalFiltersByObject;

    // Populated in start() when a parent filter is active; bound in the QueryLocator string
    private Set<Id>                                       relevantChildIds;

    private Integer recordsDeleted = 0;
    private Integer recordsFailed  = 0;
    private List<String> errors    = new List<String>();

    // ── Constructor ───────────────────────────────────────────────────────────

    /**
     * @description Constructs the batch for one DELETE_CONTENT_DOCUMENT CMT config.
     * @param currentConfig              The CMT config driving this batch (object + RT).
     * @param selectedBrands             Brand values to filter parent records (empty = all).
     * @param auditLogId                 Id of the TEKCO_AnonymizationAuditLog__c record.
     * @param remainingContentDocConfigs Remaining configs still needing ContentDocument deletion.
     * @param historyConfigs             Field configs needing history deletion (Phase 3).
     * @param bypassSnapshot             Bypass state snapshot to restore at chain end.
     * @param parentFiltersByObject      Map of child object → [parentObject, parentLookup, parentRT].
     * @param additionalFiltersByObject  Map of object → raw WHERE fragment for extra filtering.
     */
    public TEKCO_ContentDocumentBatch(
        TEKCO_AnonymizationFieldConfig__mdt currentConfig,
        List<String> selectedBrands,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingContentDocConfigs,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        Map<String, List<String>> parentFiltersByObject,
        Map<String, String> additionalFiltersByObject
    ) {
        this.objectApiName              = currentConfig?.TEKCO_ObjectApiName__c;
        this.recordTypeDvName           = currentConfig?.TEKCO_RecordTypeDeveloperName__c;
        this.selectedBrands             = selectedBrands             != null
            ? selectedBrands : new List<String>();
        this.auditLogId                 = auditLogId;
        this.remainingContentDocConfigs = remainingContentDocConfigs != null
            ? remainingContentDocConfigs : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.historyConfigs             = historyConfigs             != null
            ? historyConfigs : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.bypassSnapshot             = bypassSnapshot;
        this.parentFiltersByObject      = parentFiltersByObject != null
            ? parentFiltersByObject : new Map<String, List<String>>();
        this.additionalFiltersByObject  = additionalFiltersByObject != null
            ? additionalFiltersByObject : new Map<String, String>();
    }

    // ── Batchable Interface ───────────────────────────────────────────────────

    /**
     * @description Queries ContentDocumentLink records linked to the target object's records,
     *              scoped by brand, Record Type from the CMT config, and optional parent filter.
     * @param bc Batch context provided by the platform.
     * @return   QueryLocator for the ContentDocumentLink records.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationSandboxGuard.assertIsSandbox();

        List<String> parentFilter = parentFiltersByObject.get(objectApiName);
        String parentObjectApiName    = (parentFilter != null && parentFilter.size() > 0) ? parentFilter.get(0) : null;
        String parentLookupField      = (parentFilter != null && parentFilter.size() > 1) ? parentFilter.get(1) : null;
        String parentRecordTypeDvName = (parentFilter != null && parentFilter.size() > 2) ? parentFilter.get(2) : null;

        String additionalFilter = additionalFiltersByObject.get(objectApiName);
        String innerFilter = '';
        if (String.isNotBlank(parentObjectApiName)) {
            // Nested subqueries are forbidden — resolve child IDs upfront (runs once in start())
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
            // Also apply child RT + additional filter when resolving child IDs
            List<String> childConditions = new List<String>{
                parentLookupField + ' IN :parentIds'
            };
            if (String.isNotBlank(recordTypeDvName)) {
                childConditions.add('RecordType.DeveloperName = \''
                    + String.escapeSingleQuotes(recordTypeDvName) + '\'');
            }
            if (String.isNotBlank(additionalFilter)) {
                childConditions.add(additionalFilter);
            }
            String childQuery = 'SELECT Id FROM ' + objectApiName
                + ' WHERE ' + String.join(childConditions, ' AND ');
            this.relevantChildIds = new Map<Id, SObject>(Database.query(childQuery)).keySet();
            innerFilter = ' WHERE Id IN :relevantChildIds';
        } else {
            // Direct filter on the child object
            List<String> conditions = new List<String>();
            if (!selectedBrands.isEmpty() && hasBrandField(objectApiName)) {
                conditions.add('TEKCO_Brand__c IN :selectedBrands');
            }
            if (String.isNotBlank(recordTypeDvName)) {
                conditions.add(
                    'RecordType.DeveloperName = \'' + String.escapeSingleQuotes(recordTypeDvName) + '\''
                );
            }
            if (String.isNotBlank(additionalFilter)) {
                conditions.add(additionalFilter);
            }
            if (!conditions.isEmpty()) {
                innerFilter = ' WHERE ' + String.join(conditions, ' AND ');
            }
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
                        parentFiltersByObject,
                        additionalFiltersByObject
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
                        parentFiltersByObject,
                        additionalFiltersByObject
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

    private static Boolean hasBrandField(String objectApiName) {
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        return sot != null
            && sot.getDescribe().fields.getMap().containsKey('tekco_brand__c');
    }

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
