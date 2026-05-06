/**
 * @author
 * @description Chain order: TEKCO_AnonymizationBatch → TEKCO_ContentDocumentBatch → TEKCO_FieldHistoryBatch
 */
public class TEKCO_AnonymizationBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer DEFAULT_BATCH_SIZE    = 200;
    private static final Integer MAX_CAPTURED_ERRORS   = 50;
    private static final String  PATTERN_TYPE_DELETE_CONTENT_DOCUMENT = 'DELETE_CONTENT_DOCUMENT';
    private static final String  PATTERN_TYPE_EMAIL_MESSAGE_LOREM     = 'EMAIL_MESSAGE_LOREM';

    private String                                        objectApiName;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     fieldConfigs;
    private Map<String, TEKCO_AnonymizationPattern__mdt>  patternsByType;
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

    private Integer recordsProcessed = 0;
    private Integer recordsFailed    = 0;
    private List<String> errors      = new List<String>();


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
        this.bypassSnapshot       = bypassSnapshot;
        this.parentFiltersByObject = parentFiltersByObject != null
            ? parentFiltersByObject : new Map<String, List<String>>();
        this.additionalFiltersByObject = additionalFiltersByObject != null
            ? additionalFiltersByObject : new Map<String, String>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationSandboxGuard.assertIsSandbox();

        Boolean hasEmailMessageLorem = false;

        if (Schema.getGlobalDescribe().get(objectApiName) == null) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        try {
        for (TEKCO_AnonymizationFieldConfig__mdt fc : fieldConfigs) {
            if (fc.TEKCO_PatternType__c == PATTERN_TYPE_EMAIL_MESSAGE_LOREM) {
                hasEmailMessageLorem = true;
                break;
            }
        }

        Set<String> fieldApiNames = new Set<String>{ 'Id' };
        Boolean needsRecordTypeId = false;

        // Status required to decide update-vs-delete for EMAIL_MESSAGE_LOREM records
        if (hasEmailMessageLorem) {
            fieldApiNames.add('Status');
        }

        Map<String, Schema.SObjectField> objectFieldMap =
            Schema.getGlobalDescribe().get(objectApiName).getDescribe().fields.getMap();
        List<TEKCO_AnonymizationFieldConfig__mdt> validFieldConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();

        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : fieldConfigs) {
            String patternType = fieldConfig.TEKCO_PatternType__c;
            if (patternType == PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                validFieldConfigs.add(fieldConfig);
                continue;
            }

            String fieldApiName = fieldConfig.TEKCO_FieldApiName__c;
            if (String.isNotBlank(fieldApiName)
                    && !objectFieldMap.containsKey(fieldApiName.toLowerCase())) {
                errors.add('Field not found on ' + objectApiName + ', skipped: ' + fieldApiName);
                continue;
            }

            validFieldConfigs.add(fieldConfig);
            fieldApiNames.add(fieldApiName);

            TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(patternType);
            if (pattern != null && String.isNotBlank(pattern.TEKCO_ExternalIdField__c)
                    && objectFieldMap.containsKey(pattern.TEKCO_ExternalIdField__c.toLowerCase())) {
                fieldApiNames.add(pattern.TEKCO_ExternalIdField__c);
            }
            if ((patternType == 'NAME_FIRST_LETTER' || patternType == 'NAME_FIRST_LETTER_SFID')
                    && objectFieldMap.containsKey('tekco_functionalid__c')) {
                fieldApiNames.add('TEKCO_FunctionalId__c');
            }
            if (String.isNotBlank(fieldConfig.TEKCO_RecordTypeDeveloperName__c)) {
                needsRecordTypeId = true;
            }
        }
        fieldConfigs = validFieldConfigs;

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

        List<String> parentFilter = parentFiltersByObject.get(objectApiName);
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
            if (hasEmailMessageLorem) {
                // EmailMessage has no TEKCO_Brand__c; filter via Parent
                topConditions.add('Parent.TEKCO_Brand__c IN :selectedBrands');
            } else if (hasBrandField(objectApiName)) {
                topConditions.add('TEKCO_Brand__c IN :selectedBrands');
            } else if (hasCountryField(objectApiName)) {
                List<String> countryValues = getCountriesForBrands(selectedBrands);
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
        List<SObject> recordsToUpdate = new List<SObject>();
        List<SObject> recordsToDelete = new List<SObject>();

        for (SObject record : scope) {
            Boolean isModified    = false;
            Boolean shouldDelete  = false;

            for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : fieldConfigs) {
                String patternType = fieldConfig.TEKCO_PatternType__c;
                if (patternType == PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                    continue;
                }

                // EMAIL_MESSAGE_LOREM: Draft → apply lorem, non-Draft → delete the record
                if (patternType == PATTERN_TYPE_EMAIL_MESSAGE_LOREM) {
                    String emailStatus = (String) record.get('Status');
                    if (emailStatus == '5') {
                        String currentValue;
                        try {
                            currentValue = (String) record.get(fieldConfig.TEKCO_FieldApiName__c);
                        } catch (Exception e) { continue; }
                        if (String.isNotBlank(currentValue)) {
                            record.put(fieldConfig.TEKCO_FieldApiName__c,
                                TEKCO_AnonymizationPatternService.LOREM_TEXT);
                            isModified = true;
                        }
                    } else {
                        shouldDelete = true;
                    }
                    continue;
                }

                if (String.isNotBlank(fieldConfig.TEKCO_RecordTypeDeveloperName__c)) {
                    Id recordTypeId = (Id) record.get('RecordTypeId');
                    String recordTypeDeveloperName = recordTypeId != null
                        ? recordTypeDevNameById.get(recordTypeId)
                        : null;
                    if (recordTypeDeveloperName == null
                            || recordTypeDeveloperName != fieldConfig.TEKCO_RecordTypeDeveloperName__c) {
                        continue;
                    }
                }

                TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(patternType);
                if (pattern == null || !pattern.TEKCO_IsActive__c) continue;

                String currentValue;
                try {
                    currentValue = (String) record.get(fieldConfig.TEKCO_FieldApiName__c);
                } catch (Exception e) {
                    continue;
                }

                String newValue = TEKCO_AnonymizationPatternService.applyPattern(
                    patternType,
                    currentValue,
                    record,
                    pattern
                );

                if (newValue != null && newValue != currentValue) {
                    record.put(fieldConfig.TEKCO_FieldApiName__c, newValue);
                    isModified = true;
                }
            }

            // A non-Draft EmailMessage is deleted — do not also attempt to update it
            if (shouldDelete) {
                recordsToDelete.add(record);
            } else if (isModified) {
                recordsToUpdate.add(record);
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = Database.update(recordsToUpdate, false);
            for (Database.SaveResult saveResult : saveResults) {
                if (saveResult.isSuccess()) {
                    recordsProcessed++;
                } else {
                    recordsFailed++;
                    if (errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> errorMessages = new List<String>();
                        for (Database.Error dmlError : saveResult.getErrors()) {
                            errorMessages.add(dmlError.getMessage());
                        }
                        errors.add(saveResult.getId() + ': ' + String.join(errorMessages, '; '));
                    }
                }
            }
        }

        if (!recordsToDelete.isEmpty()) {
            Database.DeleteResult[] deleteResults = Database.delete(recordsToDelete, false);
            for (Database.DeleteResult deleteResult : deleteResults) {
                if (deleteResult.isSuccess()) {
                    recordsProcessed++;
                } else {
                    recordsFailed++;
                    if (errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> errorMessages = new List<String>();
                        for (Database.Error dmlError : deleteResult.getErrors()) {
                            errorMessages.add(dmlError.getMessage());
                        }
                        errors.add('Delete ' + deleteResult.getId() + ': '
                            + String.join(errorMessages, '; '));
                    }
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
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
                TEKCO_AnonymizationAuditService.finalize(auditLogId, recordsProcessed, recordsFailed, errors);
                return;
            }
            TEKCO_AnonymizationAuditService.markRunning(auditLogId, recordsProcessed, recordsFailed, errors);
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) {  }
            TEKCO_AnonymizationAuditService.closeFailed(auditLogId, recordsProcessed, recordsFailed, errors, e.getMessage());
        }
    }

    private static Boolean hasBrandField(String objectApiName) {
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        return sot != null
            && sot.getDescribe().fields.getMap().containsKey('tekco_brand__c');
    }

    private static Boolean hasCountryField(String objectApiName) {
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        return sot != null
            && sot.getDescribe().fields.getMap().containsKey('tekco_country__c');
    }

    private static List<String> getCountriesForBrands(List<String> brands) {
        List<String> countries = new List<String>();
        for (TEKCO_CountryBrandSetting__mdt mapping : [
            SELECT TEKCO_Country__c
            FROM TEKCO_CountryBrandSetting__mdt
            WHERE TEKCO_BrandCode__c IN :brands
              AND TEKCO_Country__c != null
        ]) {
            countries.add(mapping.TEKCO_Country__c);
        }
        return countries;
    }

    private static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigs(
        String objectApiName
    ) {
        return [
            SELECT
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
