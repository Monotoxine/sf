/**
 * @author
 * @description Phase 3 of the anonymization chain: deletes field history records for
 *              fields where TEKCO_AnonymizationFieldConfig__mdt.TEKCO_DeleteHistory__c = true
 */
public class TEKCO_FieldHistoryBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer DEFAULT_BATCH_SIZE  = 200;
    private static final Integer MAX_CAPTURED_ERRORS = 50;
    private static final String  CUSTOM_OBJECT_SUFFIX = '__c';

    private String                                        objectApiName;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     objectHistoryConfigs;
    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     remainingHistoryConfigs;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    private Map<String, List<String>>                     parentFiltersByObject;
    private Map<String, String>                           additionalFiltersByObject;

    private Set<Id>                                       relevantChildIds;

    private Integer recordsDeleted = 0;
    private Integer recordsFailed  = 0;
    private List<String> errors    = new List<String>();

    public TEKCO_FieldHistoryBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> objectHistoryConfigs,
        List<String> selectedBrands,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        Map<String, List<String>> parentFiltersByObject,
        Map<String, String> additionalFiltersByObject
    ) {
        this.objectApiName           = objectApiName;
        this.objectHistoryConfigs    = objectHistoryConfigs    != null
            ? objectHistoryConfigs : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.selectedBrands          = selectedBrands          != null
            ? selectedBrands : new List<String>();
        this.auditLogId              = auditLogId;
        this.remainingHistoryConfigs = remainingHistoryConfigs != null
            ? remainingHistoryConfigs : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.bypassSnapshot          = bypassSnapshot;
        this.parentFiltersByObject   = parentFiltersByObject != null
            ? parentFiltersByObject : new Map<String, List<String>>();
        this.additionalFiltersByObject = additionalFiltersByObject != null
            ? additionalFiltersByObject : new Map<String, String>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationSandboxGuard.assertIsSandbox();

        String historyObjectName = computeHistoryObjectName(objectApiName);
        String parentIdFieldName = computeParentIdFieldName(objectApiName);

        Set<String> fieldApiNames = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : objectHistoryConfigs) {
            if (String.isNotBlank(fieldConfig.TEKCO_FieldApiName__c)) {
                fieldApiNames.add(fieldConfig.TEKCO_FieldApiName__c);
            }
        }

        List<String> escapedFieldNames = new List<String>();
        for (String fieldName : fieldApiNames) {
            escapedFieldNames.add('\'' + String.escapeSingleQuotes(fieldName) + '\'');
        }

        List<String> parentFilter = parentFiltersByObject.get(objectApiName);
        String parentObjectApiName    = (parentFilter != null && parentFilter.size() > 0) ? parentFilter.get(0) : null;
        String parentLookupField      = (parentFilter != null && parentFilter.size() > 1) ? parentFilter.get(1) : null;
        String parentRecordTypeDvName = (parentFilter != null && parentFilter.size() > 2) ? parentFilter.get(2) : null;

        String fieldPrefix = ' WHERE Field IN (' + String.join(escapedFieldNames, ',') + ')'
            + ' AND ' + parentIdFieldName;

        String soqlQuery;
        String additionalFilter = additionalFiltersByObject.get(objectApiName);

        if (String.isNotBlank(parentObjectApiName)) {
            // Resolve child IDs upfront to avoid forbidden nested subqueries
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
            String childQuery = 'SELECT Id FROM ' + objectApiName
                + ' WHERE ' + parentLookupField + ' IN :parentIds';
            if (String.isNotBlank(additionalFilter)) {
                childQuery += ' AND ' + additionalFilter;
            }
            this.relevantChildIds = new Map<Id, SObject>(Database.query(childQuery)).keySet();
            soqlQuery = 'SELECT Id FROM ' + historyObjectName
                + fieldPrefix + ' IN :relevantChildIds';
        } else {
            List<String> childConditions = new List<String>();
            if (!selectedBrands.isEmpty() && hasBrandField(objectApiName)) {
                childConditions.add('TEKCO_Brand__c IN :selectedBrands');
            }
            if (String.isNotBlank(additionalFilter)) {
                childConditions.add(additionalFilter);
            }
            String childWhere = childConditions.isEmpty()
                ? ''
                : ' WHERE ' + String.join(childConditions, ' AND ');
            soqlQuery = 'SELECT Id FROM ' + historyObjectName + fieldPrefix
                + ' IN (SELECT Id FROM ' + objectApiName + childWhere + ')';
        }

        return Database.getQueryLocator(soqlQuery);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Database.DeleteResult[] deleteResults = Database.delete(scope, false);
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
            if (!remainingHistoryConfigs.isEmpty()) {
                String nextObjectApiName = remainingHistoryConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> nextObjectConfigs =
                    popConfigsForObject(nextObjectApiName);
                Database.executeBatch(
                    new TEKCO_FieldHistoryBatch(
                        nextObjectApiName,
                        nextObjectConfigs,
                        selectedBrands,
                        auditLogId,
                        remainingHistoryConfigs,
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
            } catch (Exception restoreEx) { /* silent */ }
            TEKCO_AnonymizationAuditService.closeFailed(auditLogId, recordsFailed, errors, e.getMessage());
        }
    }


    private static Boolean hasBrandField(String objectApiName) {
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        return sot != null
            && sot.getDescribe().fields.getMap().containsKey('tekco_brand__c');
    }

    /**
     * @description Returns the history SObject API name for a given object
     * @param objectApiName API name of the parent object.
     * @return              API name of the corresponding history object.
     */
    @TestVisible
    private static String computeHistoryObjectName(String objectApiName) {
        if (objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX)) {
            return objectApiName.replace(CUSTOM_OBJECT_SUFFIX, '__History');
        }
        return objectApiName + 'History';
    }

    /**
     * @description Returns the parent ID field name on the history object
     * @param objectApiName API name of the parent object.
     * @return              API name of the parent ID field on the history object.
     */
    @TestVisible
    private static String computeParentIdFieldName(String objectApiName) {
        if (objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX)) {
            return 'ParentId';
        }
        return objectApiName + 'Id';
    }

    private List<TEKCO_AnonymizationFieldConfig__mdt> popConfigsForObject(String objectApiName) {
        List<TEKCO_AnonymizationFieldConfig__mdt> configsForObject =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : remainingHistoryConfigs) {
            if (fieldConfig.TEKCO_ObjectApiName__c == objectApiName) {
                configsForObject.add(fieldConfig);
            } else {
                remainingConfigs.add(fieldConfig);
            }
        }
        remainingHistoryConfigs = remainingConfigs;
        return configsForObject;
    }

}
