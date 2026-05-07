/**
 * @author
 * @description Phase 3 of the anonymization chain: deletes field history records for
 *              fields where TEKCO_AnonymizationFieldConfig__mdt.TEKCO_DeleteHistory__c = true
 */
public class TEKCO_FieldHistoryBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE  = 2000;
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

    private Integer recordsDeleted              = 0;
    private Integer recordsFailed               = 0;
    private Integer accumulatedRecordsProcessed = 0;
    private List<String> errors                 = new List<String>();
    private List<String> accumulatedErrors      = new List<String>();

    public TEKCO_FieldHistoryBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> objectHistoryConfigs,
        List<String> selectedBrands,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed,
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
        this.bypassSnapshot              = bypassSnapshot;
        this.accumulatedErrors           = accumulatedErrors != null ? accumulatedErrors : new List<String>();
        this.accumulatedRecordsProcessed = accumulatedRecordsProcessed != null ? accumulatedRecordsProcessed : 0;
        this.parentFiltersByObject   = parentFiltersByObject != null
            ? parentFiltersByObject : new Map<String, List<String>>();
        this.additionalFiltersByObject = additionalFiltersByObject != null
            ? additionalFiltersByObject : new Map<String, String>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationPatternService.assertIsSandbox();

        if (Schema.getGlobalDescribe().get(objectApiName) == null) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        String historyObjectName = computeHistoryObjectName(objectApiName);
        String parentIdFieldName = computeParentIdFieldName(objectApiName);

        if (Schema.getGlobalDescribe().get(historyObjectName) == null) {
            errors.add('Field history not enabled for object, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        try {

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
            List<String> parentConditions = new List<String>();
            if (!selectedBrands.isEmpty()) {
                parentConditions.add('TEKCO_Brand__c IN :selectedBrands');
            }
            if (String.isNotBlank(parentRecordTypeDvName)) {
                parentConditions.add(
                    'RecordType.DeveloperName = \'' + String.escapeSingleQuotes(parentRecordTypeDvName) + '\''
                );
            }
            String parentSubquery = 'SELECT Id FROM ' + parentObjectApiName;
            if (!parentConditions.isEmpty()) {
                parentSubquery += ' WHERE ' + String.join(parentConditions, ' AND ');
            }
            List<String> childConditions = new List<String>{
                parentLookupField + ' IN (' + parentSubquery + ')'
            };
            if (String.isNotBlank(additionalFilter)) {
                childConditions.add(additionalFilter);
            }
            soqlQuery = 'SELECT Id FROM ' + historyObjectName
                + fieldPrefix + ' IN (SELECT Id FROM ' + objectApiName
                + ' WHERE ' + String.join(childConditions, ' AND ') + ')';
        } else {
            List<String> childConditions = new List<String>();
            if (!selectedBrands.isEmpty()) {
                if (TEKCO_AnonymizationPatternService.hasField(objectApiName, 'tekco_brand__c')) {
                    childConditions.add('TEKCO_Brand__c IN :selectedBrands');
                } else if (TEKCO_AnonymizationPatternService.hasField(objectApiName, 'tekco_country__c')) {
                    List<String> countryValues = TEKCO_AnonymizationPatternService.getCountriesForBrands(selectedBrands);
                    if (!countryValues.isEmpty()) {
                        childConditions.add('TEKCO_Country__c IN :countryValues');
                    }
                }
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
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }
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
        accumulatedErrors.addAll(errors);
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
                        accumulatedErrors,
                        accumulatedRecordsProcessed,
                        parentFiltersByObject,
                        additionalFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(auditLogId, accumulatedRecordsProcessed, recordsFailed, accumulatedErrors);
            }
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) { }
            TEKCO_AnonymizationAuditService.closeFailed(auditLogId, accumulatedRecordsProcessed, recordsFailed, accumulatedErrors, e.getMessage());
        }
    }


    @TestVisible
    private static String computeHistoryObjectName(String objectApiName) {
        if (objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX)) {
            return objectApiName.replace(CUSTOM_OBJECT_SUFFIX, '__History');
        }
        return objectApiName + 'History';
    }

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
