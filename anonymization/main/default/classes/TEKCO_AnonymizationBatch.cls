/**
 * @author
 * @description Chain order: TEKCO_AnonymizationBatch → TEKCO_ContentDocumentBatch → TEKCO_FieldHistoryBatch
 */
public class TEKCO_AnonymizationBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE = 200;
    private static final Integer MAX_ACCUMULATED_ERRORS = 200;
    private static final String PATTERN_TYPE_EMAIL_MESSAGE_LOREM = 'EMAIL_MESSAGE_LOREM';

    private String                                        objectApiName;
    // fieldConfigs and patternsByType are received in the constructor and used in start(),
    // then nulled out so they are not serialized between execute() chunks (heap/stateful fix).
    // execute() re-queries them locally via loadFieldConfigsByDevNames() and buildPatternMap().
    private List<TEKCO_AnonymizationFieldConfig__mdt>     fieldConfigs;
    private Map<String, TEKCO_AnonymizationPattern__mdt>  patternsByType;
    // DeveloperNames of the valid field configs determined in start(); replaces fieldConfigs in execute().
    private List<String>                                  validFieldConfigDevNames = new List<String>();
    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<String>                                  remainingObjects;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     contentDocConfigs;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     historyConfigs;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;

    private Map<String, List<String>>                     parentFiltersByObject;
    private Map<String, String>                           additionalFiltersByObject;
    private Map<Id, String>                               recordTypeDevNameById =
        new Map<Id, String>();

    private Integer recordsProcessed        = 0;
    private Integer recordsFailed           = 0;
    private Integer accumulatedRecordsProcessed = 0;
    private List<String> errors             = new List<String>();
    private List<String> accumulatedErrors  = new List<String>();


    public TEKCO_AnonymizationBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigs,
        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType,
        List<String> selectedBrands,
        Id auditLogId,
        List<String> remainingObjects,
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed,
        Map<String, List<String>> parentFiltersByObject,
        Map<String, String> additionalFiltersByObject
    ) {
        this.objectApiName        = objectApiName;
        this.fieldConfigs         = fieldConfigs;
        this.patternsByType       = patternsByType;
        this.selectedBrands       = selectedBrands    != null ? selectedBrands    : new List<String>();
        this.auditLogId           = auditLogId;
        this.remainingObjects  = remainingObjects  != null ? remainingObjects  : new List<String>();
        this.contentDocConfigs = contentDocConfigs != null ? contentDocConfigs
            : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.historyConfigs    = historyConfigs    != null ? historyConfigs
            : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.bypassSnapshot             = bypassSnapshot;
        this.accumulatedErrors          = accumulatedErrors != null ? accumulatedErrors : new List<String>();
        this.accumulatedRecordsProcessed = accumulatedRecordsProcessed != null ? accumulatedRecordsProcessed : 0;
        this.parentFiltersByObject = parentFiltersByObject != null
            ? parentFiltersByObject : new Map<String, List<String>>();
        this.additionalFiltersByObject = additionalFiltersByObject != null
            ? additionalFiltersByObject : new Map<String, String>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationOrgConfigService.assertIsSandbox();

        Schema.DescribeSObjectResult sObjectDescribe;
        try {
            sObjectDescribe = Schema.describeSObjects(new List<String>{ objectApiName })[0];
        } catch (Exception e) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        try {
            Set<String> fieldApiNames    = new Set<String>{ 'Id' };
            Boolean needsRecordTypeId    = false;
            Boolean hasEmailMessageLorem = false;

            Map<String, Schema.SObjectField> objectFieldMap =
                sObjectDescribe.fields.getMap();
            List<TEKCO_AnonymizationFieldConfig__mdt> validFieldConfigs =
                new List<TEKCO_AnonymizationFieldConfig__mdt>();

            // Use constructor-provided configs (first run) or fall back to a fresh query.
            List<TEKCO_AnonymizationFieldConfig__mdt> startConfigs =
                this.fieldConfigs != null ? this.fieldConfigs : loadFieldConfigs(objectApiName);
            Map<String, TEKCO_AnonymizationPattern__mdt> startPatterns =
                this.patternsByType != null ? this.patternsByType : buildPatternMap();

            for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : startConfigs) {
                String patternType  = fieldConfig.TEKCO_PatternType__c;
                String fieldApiName = fieldConfig.TEKCO_FieldApiName__c;

                if (String.isNotBlank(fieldApiName)
                        && !objectFieldMap.containsKey(fieldApiName.toLowerCase())) {
                    errors.add('Field not found on ' + objectApiName + ', skipped: ' + fieldApiName);
                    continue;
                }

                validFieldConfigs.add(fieldConfig);
                if (String.isNotBlank(fieldApiName)) {
                    fieldApiNames.add(fieldApiName);
                }

                if (patternType == PATTERN_TYPE_EMAIL_MESSAGE_LOREM) {
                    hasEmailMessageLorem = true;
                    fieldApiNames.add('Status');
                }

                TEKCO_AnonymizationPattern__mdt pattern = startPatterns.get(patternType);
                if (pattern != null && String.isNotBlank(pattern.TEKCO_ExternalIdField__c)
                        && objectFieldMap.containsKey(pattern.TEKCO_ExternalIdField__c.toLowerCase())) {
                    fieldApiNames.add(pattern.TEKCO_ExternalIdField__c);
                }
                if (patternType == 'NAME_FIRST_LETTER' || patternType == 'NAME_FIRST_LETTER_SFID') {
                    String funcField = TEKCO_AnonymizationOrgConfigService.getConfig().functionalIdField;
                    if (String.isNotBlank(funcField) && objectFieldMap.containsKey(funcField.toLowerCase())) {
                        fieldApiNames.add(funcField);
                    }
                }
                if (String.isNotBlank(fieldConfig.TEKCO_RecordTypeDeveloperName__c)) {
                    needsRecordTypeId = true;
                }
            }

            // Store only DeveloperNames — lightweight strings survive serialization cheaply.
            validFieldConfigDevNames = new List<String>();
            for (TEKCO_AnonymizationFieldConfig__mdt fc : validFieldConfigs) {
                if (String.isNotBlank(fc.DeveloperName)) {
                    validFieldConfigDevNames.add(fc.DeveloperName);
                }
            }
            // Null out heavy CMDT objects so they are not serialized between execute() chunks.
            this.fieldConfigs  = null;
            this.patternsByType = null;

            if (needsRecordTypeId) {
                fieldApiNames.add('RecordTypeId');
                for (RecordType recordType : [
                    SELECT Id, DeveloperName
                    FROM RecordType
                    WHERE SobjectType = :objectApiName
                ]) {
                    recordTypeDevNameById.put(recordType.Id, recordType.DeveloperName);
                }
            }

            String soqlQuery = 'SELECT ' + String.join(new List<String>(fieldApiNames), ', ')
                + ' FROM ' + objectApiName;

            List<String> parentFilter         = parentFiltersByObject.get(objectApiName);
            String parentObjectApiName    = (parentFilter != null && parentFilter.size() > 0) ? parentFilter.get(0) : null;
            String parentLookupField      = (parentFilter != null && parentFilter.size() > 1) ? parentFilter.get(1) : null;
            String parentRecordTypeDvName = (parentFilter != null && parentFilter.size() > 2) ? parentFilter.get(2) : null;
            String additionalFilter       = additionalFiltersByObject.get(objectApiName);

            List<String> topConditions = new List<String>();

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
                topConditions.add(parentLookupField + ' IN (' + parentSubquery + ')');
            } else if (!selectedBrands.isEmpty()) {
                TEKCO_AnonymizationOrgConfigService.OrgConfig orgCfg = TEKCO_AnonymizationOrgConfigService.getConfig();
                if (orgCfg.usesBrandObject() && String.isNotBlank(orgCfg.brandLookupFieldOnRecord)
                        && TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, orgCfg.brandLookupFieldOnRecord)) {
                    List<String> escaped = new List<String>();
                    for (String b : selectedBrands) escaped.add('\'' + String.escapeSingleQuotes(b) + '\'');
                    topConditions.add(orgCfg.brandLookupFieldOnRecord + '.' + orgCfg.brandCodeField
                        + ' IN (' + String.join(escaped, ', ') + ')');
                } else if (hasEmailMessageLorem) {
                    topConditions.add('Parent.TEKCO_Brand__c IN :selectedBrands');
                } else if (TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, 'tekco_brand__c')) {
                    topConditions.add('TEKCO_Brand__c IN :selectedBrands');
                } else if (TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, 'tekco_country__c')) {
                    List<String> countryValues = TEKCO_AnonymizationOrgConfigService.getCountriesForBrands(selectedBrands);
                    if (!countryValues.isEmpty()) {
                        topConditions.add('TEKCO_Country__c IN :countryValues');
                    }
                }
            }

            if (String.isNotBlank(additionalFilter)) {
                topConditions.add(additionalFilter);
            }

            if (!topConditions.isEmpty()) {
                soqlQuery += ' WHERE ' + String.join(topConditions, ' AND ');
            }

            return Database.getQueryLocator(soqlQuery);
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        // Re-query CMDT each chunk — they are cached by the platform, cost is negligible.
        // fieldConfigs and patternsByType were nulled in start() to avoid stateful serialization cost.
        List<TEKCO_AnonymizationFieldConfig__mdt> localFieldConfigs =
            loadFieldConfigsByDevNames(validFieldConfigDevNames);
        Map<String, TEKCO_AnonymizationPattern__mdt> localPatterns = buildPatternMap();

        TEKCO_AnonymizationExecuteService.ExecuteResult result =
            TEKCO_AnonymizationExecuteService.executeFieldAnonymization(
                scope, localFieldConfigs, localPatterns, recordTypeDevNameById
            );
        recordsProcessed += result.recordsProcessed;
        recordsFailed    += result.recordsFailed;
        errors.addAll(result.errors);
    }

    public void finish(Database.BatchableContext bc) {
        for (String e : errors) {
            if (accumulatedErrors.size() < MAX_ACCUMULATED_ERRORS) accumulatedErrors.add(e);
        }
        Integer totalProcessed = accumulatedRecordsProcessed + recordsProcessed;
        try {
            if (!remainingObjects.isEmpty()) {
                String nextObjectApiName = remainingObjects.remove(0);
                List<TEKCO_AnonymizationFieldConfig__mdt> nextObjectConfigs =
                    loadFieldConfigs(nextObjectApiName);
                Database.executeBatch(
                    new TEKCO_AnonymizationBatch(
                        nextObjectApiName,
                        nextObjectConfigs,
                        patternsByType,
                        selectedBrands,
                        auditLogId,
                        remainingObjects,
                        contentDocConfigs,
                        historyConfigs,
                        bypassSnapshot,
                        accumulatedErrors,
                        totalProcessed,
                        parentFiltersByObject,
                        additionalFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!contentDocConfigs.isEmpty()) {
                TEKCO_AnonymizationFieldConfig__mdt firstContentDocConfig = contentDocConfigs.remove(0);
                Database.executeBatch(
                    new TEKCO_ContentDocumentBatch(
                        firstContentDocConfig,
                        selectedBrands,
                        auditLogId,
                        contentDocConfigs,
                        historyConfigs,
                        bypassSnapshot,
                        accumulatedErrors,
                        totalProcessed,
                        0,
                        parentFiltersByObject,
                        additionalFiltersByObject
                    ),
                    TEKCO_ContentDocumentBatch.DEFAULT_BATCH_SIZE
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
                        accumulatedErrors,
                        totalProcessed,
                        0,
                        0,
                        parentFiltersByObject,
                        additionalFiltersByObject
                    ),
                    TEKCO_FieldHistoryBatch.DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(auditLogId, totalProcessed, recordsFailed, 0, 0, accumulatedErrors);
                return;
            }
            TEKCO_AnonymizationAuditService.markRunning(auditLogId, totalProcessed, recordsFailed, accumulatedErrors);
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) {  }
            TEKCO_AnonymizationAuditService.closeFailed(auditLogId, totalProcessed, recordsFailed, 0, 0, accumulatedErrors, e.getMessage());
        }
    }


    private static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigs(
        String objectApiName
    ) {
        return [
            SELECT
                DeveloperName,
                TEKCO_ObjectApiName__c,
                TEKCO_FieldApiName__c,
                TEKCO_PatternType__c,
                TEKCO_IsActive__c,
                TEKCO_RecordTypeDeveloperName__c,
                TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_ObjectApiName__c = :objectApiName
                AND TEKCO_IsActive__c = true
        ];
    }

    public static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigsByDevNames(
        List<String> devNames
    ) {
        if (devNames == null || devNames.isEmpty()) {
            return new List<TEKCO_AnonymizationFieldConfig__mdt>();
        }
        return [
            SELECT
                DeveloperName,
                TEKCO_ObjectApiName__c,
                TEKCO_FieldApiName__c,
                TEKCO_PatternType__c,
                TEKCO_IsActive__c,
                TEKCO_RecordTypeDeveloperName__c,
                TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE DeveloperName IN :devNames
        ];
    }

    public static Map<String, TEKCO_AnonymizationPattern__mdt> buildPatternMap() {
        Map<String, TEKCO_AnonymizationPattern__mdt> result =
            new Map<String, TEKCO_AnonymizationPattern__mdt>();
        for (TEKCO_AnonymizationPattern__mdt p : [
            SELECT
                DeveloperName,
                TEKCO_Description__c,
                TEKCO_ExternalIdField__c,
                TEKCO_BaseEmail__c,
                TEKCO_SsnLength__c,
                TEKCO_IsActive__c,
                TEKCO_RegexFind__c,
                TEKCO_RegexReplace__c
            FROM TEKCO_AnonymizationPattern__mdt
            WHERE TEKCO_IsActive__c = true
        ]) {
            result.put(p.DeveloperName, p);
        }
        return result;
    }

    private List<TEKCO_AnonymizationFieldConfig__mdt> popHistoryConfigsForObject(String objectApiName) {
        return TEKCO_AnonymizationBatchUtils.popConfigsForObject(objectApiName, historyConfigs);
    }

}
