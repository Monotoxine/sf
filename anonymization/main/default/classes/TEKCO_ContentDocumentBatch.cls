/**
 * @author
 * @description Phase 2 of the anonymization chain: deletes ContentDocument records
 *              linked to records of the target object, filtered by brand and/or Record Type
 *              as configured in TEKCO_AnonymizationFieldConfig__mdt
 *              (TEKCO_PatternType__c = 'DELETE_CONTENT_DOCUMENT')
 */
public class TEKCO_ContentDocumentBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer DEFAULT_BATCH_SIZE  = 200;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    private String                                        objectApiName;
    private String                                        recordTypeDvName;

    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     remainingContentDocConfigs;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     historyConfigs;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    private Map<String, List<String>>                     parentFiltersByObject;
    private Map<String, String>                           additionalFiltersByObject;

    private Set<Id>                                       relevantChildIds;

    private Integer recordsDeleted = 0;
    private Integer recordsFailed  = 0;
    private List<String> errors    = new List<String>();

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


    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationSandboxGuard.assertIsSandbox();

        List<String> parentFilter = parentFiltersByObject.get(objectApiName);
        String parentObjectApiName    = (parentFilter != null && parentFilter.size() > 0) ? parentFilter.get(0) : null;
        String parentLookupField      = (parentFilter != null && parentFilter.size() > 1) ? parentFilter.get(1) : null;
        String parentRecordTypeDvName = (parentFilter != null && parentFilter.size() > 2) ? parentFilter.get(2) : null;

        String additionalFilter = additionalFiltersByObject.get(objectApiName);
        String innerFilter = '';
        if (String.isNotBlank(parentObjectApiName)) {
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
                TEKCO_AnonymizationAuditService.finalize(auditLogId, recordsFailed, errors);
            }
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) {}
            TEKCO_AnonymizationAuditService.closeFailed(auditLogId, recordsFailed, errors, e.getMessage());
        }
    }


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

}
