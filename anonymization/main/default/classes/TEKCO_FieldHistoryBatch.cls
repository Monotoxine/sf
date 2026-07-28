/**
 * @author
 * @description Phase 3 of the anonymization chain: deletes field history records for
 *              fields where TEKCO_AnonymizationFieldConfig__mdt.TEKCO_DeleteHistory__c = true
 */
public class TEKCO_FieldHistoryBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE  = 2000;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    private String                                        objectApiName;
    private List<String>                                  objectHistoryConfigDevNames;
    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<String>                                  remainingHistoryConfigDevNames;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    private Map<String, List<String>>                     parentFiltersByObject;
    private Map<String, String>                           additionalFiltersByObject;

    private Integer recordsDeleted                   = 0;
    private Integer recordsFailed                    = 0;
    private Integer accumulatedRecordsProcessed      = 0;
    private Integer accumulatedDocumentsDeleted      = 0;
    private Integer accumulatedHistoryRecordsDeleted = 0;
    private List<String> errors                      = new List<String>();
    private List<String> accumulatedErrors           = new List<String>();

    public TEKCO_FieldHistoryBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> objectHistoryConfigs,
        List<String> selectedBrands,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed,
        Integer accumulatedDocumentsDeleted,
        Integer accumulatedHistoryRecordsDeleted,
        Map<String, List<String>> parentFiltersByObject,
        Map<String, String> additionalFiltersByObject
    ) {
        this.objectApiName                = objectApiName;
        this.objectHistoryConfigDevNames  = toDevNames(objectHistoryConfigs);
        this.selectedBrands               = selectedBrands != null ? selectedBrands : new List<String>();
        this.auditLogId                   = auditLogId;
        this.remainingHistoryConfigDevNames = toDevNames(remainingHistoryConfigs);
        this.bypassSnapshot                   = bypassSnapshot;
        this.accumulatedErrors                = accumulatedErrors                != null ? accumulatedErrors                : new List<String>();
        this.accumulatedRecordsProcessed      = accumulatedRecordsProcessed      != null ? accumulatedRecordsProcessed      : 0;
        this.accumulatedDocumentsDeleted      = accumulatedDocumentsDeleted      != null ? accumulatedDocumentsDeleted      : 0;
        this.accumulatedHistoryRecordsDeleted = accumulatedHistoryRecordsDeleted != null ? accumulatedHistoryRecordsDeleted : 0;
        this.parentFiltersByObject            = parentFiltersByObject != null
            ? parentFiltersByObject : new Map<String, List<String>>();
        this.additionalFiltersByObject        = additionalFiltersByObject != null
            ? additionalFiltersByObject : new Map<String, String>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationOrgConfigService.assertIsSandbox();

        try { Schema.describeSObjects(new List<String>{ objectApiName }); }
        catch (Exception e) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        String historyObjectName = computeHistoryObjectName(objectApiName);
        String parentIdFieldName = computeParentIdFieldName(objectApiName);

        try { Schema.describeSObjects(new List<String>{ historyObjectName }); }
        catch (Exception e) {
            errors.add('Field history not enabled for object, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        try {

        List<TEKCO_AnonymizationFieldConfig__mdt> objectHistoryConfigs =
            TEKCO_AnonymizationBatch.loadFieldConfigsByDevNames(objectHistoryConfigDevNames);

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
                TEKCO_AnonymizationOrgConfigService.OrgConfig orgCfg = TEKCO_AnonymizationOrgConfigService.getConfig();
                if (orgCfg.usesBrandObject()
                        && String.isNotBlank(orgCfg.brandLookupFieldOnRecord)
                        && TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, orgCfg.brandLookupFieldOnRecord)) {
                    List<String> escaped = new List<String>();
                    for (String b : selectedBrands) escaped.add('\'' + String.escapeSingleQuotes(b) + '\'');
                    childConditions.add(orgCfg.brandLookupFieldOnRecord + '.' + orgCfg.brandCodeField
                        + ' IN (' + String.join(escaped, ', ') + ')');
                } else if (TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, 'tekco_brand__c')) {
                    childConditions.add('TEKCO_Brand__c IN :selectedBrands');
                } else if (TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, 'tekco_country__c')) {
                    List<String> countryValues = TEKCO_AnonymizationOrgConfigService.getCountriesForBrands(selectedBrands);
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
        Integer totalHistoryDeleted = accumulatedHistoryRecordsDeleted + recordsDeleted;
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs =
            TEKCO_AnonymizationBatch.loadFieldConfigsByDevNames(remainingHistoryConfigDevNames);
        try {
            if (!remainingHistoryConfigs.isEmpty()) {
                String nextObjectApiName = remainingHistoryConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> nextObjectConfigs =
                    TEKCO_AnonymizationBatchUtils.popConfigsForObject(nextObjectApiName, remainingHistoryConfigs);
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
                        accumulatedDocumentsDeleted,
                        totalHistoryDeleted,
                        parentFiltersByObject,
                        additionalFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(
                    auditLogId, accumulatedRecordsProcessed, recordsFailed,
                    accumulatedDocumentsDeleted, totalHistoryDeleted, accumulatedErrors
                );
            }
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) { }
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, accumulatedRecordsProcessed, recordsFailed,
                accumulatedDocumentsDeleted, totalHistoryDeleted, accumulatedErrors, e.getMessage()
            );
        }
    }


    private static String computeHistoryObjectName(String objectApiName) {
        return TEKCO_AnonymizationBatchUtils.computeHistoryObjectName(objectApiName);
    }

    private static String computeParentIdFieldName(String objectApiName) {
        return TEKCO_AnonymizationBatchUtils.computeParentIdFieldName(objectApiName);
    }

    private static List<String> toDevNames(List<TEKCO_AnonymizationFieldConfig__mdt> configs) {
        List<String> names = new List<String>();
        if (configs == null) return names;
        for (TEKCO_AnonymizationFieldConfig__mdt c : configs) {
            if (String.isNotBlank(c.DeveloperName)) names.add(c.DeveloperName);
        }
        return names;
    }

}
