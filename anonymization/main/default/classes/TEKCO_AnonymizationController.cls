/**
 * @author 
 * @description AuraEnabled controller for the tekcoDataAnonymizationAdmin LWC
 */
public with sharing class TEKCO_AnonymizationController {

    private static final String PATTERN_TYPE_DELETE_CONTENT_DOCUMENT = 'DELETE_CONTENT_DOCUMENT'; // FIX ME to be removed ?not done automatically
    private static final Integer DEFAULT_BATCH_SIZE = 200;

    /**
     * @description Returns all active values from the TEKCO_Brands global picklist value set.
     *              Apex has no direct API for global value sets — values are sourced via
     *              Account.TEKCO_Brand__c which is bound to the TEKCO_Brands global value set.
     * @return Sorted list of active brand values
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getBrands() {
        List<String> brandValues = new List<String>();
        try {
            Schema.DescribeFieldResult fieldDescriptor =
                Schema.SObjectType.Account.fields.getMap()
                    .get('tekco_brand__c')
                    .getDescribe();
            for (Schema.PicklistEntry entry : fieldDescriptor.getPicklistValues()) {
                if (entry.isActive()) brandValues.add(entry.getValue());
            }
        } catch (Exception e) {
            throw new AuraHandledException(
                'Could not load TEKCO_Brands picklist values. Verify that Account.TEKCO_Brand__c uses the TEKCO_Brands global value set. Error: '
                + e.getMessage()
            );
        }
        brandValues.sort();
        return brandValues;
    }

    /**
     * @description Returns object options for the LWC picker from configured values in TEKCO_AnonymizationFieldConfig__mdt
     * @return Sorted list of {label, value} maps
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getObjects() {
        Map<String, String> parentByObject = new Map<String, String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : [
            SELECT TEKCO_ObjectApiName__c, TEKCO_ParentObjectApiName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_ObjectApiName__c != null
        ]) {
            String obj    = fc.TEKCO_ObjectApiName__c;
            String parent = fc.TEKCO_ParentObjectApiName__c;
            if (!parentByObject.containsKey(obj)
                    || (String.isBlank(parentByObject.get(obj)) && String.isNotBlank(parent))) {
                parentByObject.put(obj, parent);
            }
        }

        List<String> sortedObjects = new List<String>(parentByObject.keySet());
        sortedObjects.sort();

        List<Map<String, String>> options = new List<Map<String, String>>();
        for (String obj : sortedObjects) {
            String parent = parentByObject.get(obj);
            String label  = String.isNotBlank(parent) ? obj + ' (' + parent + ')' : obj;
            options.add(new Map<String, String>{ 'label' => label, 'value' => obj });
        }
        return options;
    }

    /**
     * @description Returns the distinct object API names (values only) for internal use
     * @return Sorted list of object API names
     */
    private static List<String> getObjectApiNames() {
        Set<String> objectApiNameSet = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : [
            SELECT TEKCO_ObjectApiName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_ObjectApiName__c != null
        ]) {
            objectApiNameSet.add(fc.TEKCO_ObjectApiName__c);
        }
        List<String> result = new List<String>(objectApiNameSet);
        result.sort();
        return result;
    }

    /**
     * @description Returns Record Type options for a given object.
     *              Returns an empty list if no object is selected.
     * @param objectApiName API name of the object to scope to
     * @return Sorted list of {label, value} maps
     */
    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getRecordTypes(String objectApiName) {
        if (String.isBlank(objectApiName)) return new List<Map<String, String>>();

        List<String> sortedRts = new List<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt cfg : [
            SELECT TEKCO_RecordTypeDeveloperName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_ObjectApiName__c = :objectApiName
              AND TEKCO_RecordTypeDeveloperName__c != null
        ]) {
            if (!sortedRts.contains(cfg.TEKCO_RecordTypeDeveloperName__c)) {
                sortedRts.add(cfg.TEKCO_RecordTypeDeveloperName__c);
            }
        }
        sortedRts.sort();

        List<Map<String, String>> options = new List<Map<String, String>>();
        for (String rt : sortedRts) {
            options.add(new Map<String, String>{
                'label' => rt + ' (' + objectApiName + ')',
                'value' => rt
            });
        }
        return options;
    }

    /**
     * @description Returns field configs for a given object (or all objects if blank),
     *              optionally filtered by Record Type, enriched with pattern description.
     * @param objectApiName       API name of the object to filter by, or blank for all objects.
     * @param selectedRecordTypes Record Type Developer Names to filter by (empty = all).
     * @return List of FieldConfigDTO enriched with pattern description.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldConfigDTO> getFieldConfigs(
        String objectApiName,
        List<String> selectedRecordTypes
    ) {
        List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigRecords;
        if (String.isBlank(objectApiName)) {
            fieldConfigRecords = [
                SELECT
                    TEKCO_ObjectApiName__c,
                    TEKCO_FieldApiName__c,
                    TEKCO_PatternType__c,
                    TEKCO_IsActive__c,
                    TEKCO_RecordTypeDeveloperName__c,
                    TEKCO_DeleteHistory__c,
                    TEKCO_ParentObjectApiName__c,
                    TEKCO_ParentLookupFieldApiName__c,
                    TEKCO_ParentRecordTypeDeveloperName__c,
                    TEKCO_AdditionalFilter__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE TEKCO_IsActive__c = true
                ORDER BY TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c
            ];
        } else {
            fieldConfigRecords = [
                SELECT
                    TEKCO_ObjectApiName__c,
                    TEKCO_FieldApiName__c,
                    TEKCO_PatternType__c,
                    TEKCO_IsActive__c,
                    TEKCO_RecordTypeDeveloperName__c,
                    TEKCO_DeleteHistory__c,
                    TEKCO_ParentObjectApiName__c,
                    TEKCO_ParentLookupFieldApiName__c,
                    TEKCO_ParentRecordTypeDeveloperName__c,
                    TEKCO_AdditionalFilter__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE TEKCO_IsActive__c = true
                    AND TEKCO_ObjectApiName__c = :objectApiName
                ORDER BY TEKCO_FieldApiName__c
            ];
        }

        Set<String> rtFilter = (selectedRecordTypes != null && !selectedRecordTypes.isEmpty())
            ? new Set<String>(selectedRecordTypes)
            : null;

        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType = buildPatternMap();
        List<FieldConfigDTO> fieldConfigDtos = new List<FieldConfigDTO>();

        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : fieldConfigRecords) {
            if (rtFilter != null
                    && String.isNotBlank(fieldConfig.TEKCO_RecordTypeDeveloperName__c)
                    && !rtFilter.contains(fieldConfig.TEKCO_RecordTypeDeveloperName__c)) {
                continue;
            }

            FieldConfigDTO fieldConfigDto          = new FieldConfigDTO();
            fieldConfigDto.objectApiName                  = fieldConfig.TEKCO_ObjectApiName__c;
            fieldConfigDto.fieldApiName                   = fieldConfig.TEKCO_FieldApiName__c;
            fieldConfigDto.patternType                    = fieldConfig.TEKCO_PatternType__c;
            fieldConfigDto.recordTypeDeveloperName        = fieldConfig.TEKCO_RecordTypeDeveloperName__c;
            fieldConfigDto.deleteHistory                  = fieldConfig.TEKCO_DeleteHistory__c;
            fieldConfigDto.parentObjectApiName            = fieldConfig.TEKCO_ParentObjectApiName__c;
            fieldConfigDto.parentLookupFieldApiName       = fieldConfig.TEKCO_ParentLookupFieldApiName__c;
            fieldConfigDto.parentRecordTypeDeveloperName  = fieldConfig.TEKCO_ParentRecordTypeDeveloperName__c;
            fieldConfigDto.additionalFilter               = fieldConfig.TEKCO_AdditionalFilter__c;

            TEKCO_AnonymizationPattern__mdt patternRecord = patternsByType.get(fieldConfig.TEKCO_PatternType__c);
            fieldConfigDto.patternDescription = (patternRecord != null
                    && String.isNotBlank(patternRecord.TEKCO_Description__c))
                ? patternRecord.TEKCO_Description__c
                : fieldConfig.TEKCO_PatternType__c;

            fieldConfigDtos.add(fieldConfigDto);
        }
        return fieldConfigDtos;
    }

    /**
     * @description Returns an approximate record count for a given object, brand, and record type filter.
     * @param objectApiName      API name of the object to count.
     * @param selectedBrands     Brand values to filter by (empty = all brands).
     * @param selectedRecordType Record Type Developer Name to filter by (blank = all record types).
     * @return Record count, or -1 if the count could not be retrieved.
     */
    @AuraEnabled(cacheable=false)
    public static Integer getRecordCount(
        String objectApiName,
        List<String> selectedBrands,
        String selectedRecordType
    ) {
        if (String.isBlank(objectApiName)) return 0;
        try {
            List<String> conditions = new List<String>();
            if (selectedBrands != null && !selectedBrands.isEmpty()) {
                conditions.add('TEKCO_Brand__c IN :selectedBrands');
            }
            if (String.isNotBlank(selectedRecordType)) {
                conditions.add(
                    'RecordType.DeveloperName = \''
                    + String.escapeSingleQuotes(selectedRecordType)
                    + '\''
                );
            }
            String soqlQuery = 'SELECT COUNT(Id) cnt FROM ' + objectApiName;
            if (!conditions.isEmpty()) {
                soqlQuery += ' WHERE ' + String.join(conditions, ' AND ');
            }
            List<AggregateResult> queryResults = Database.query(soqlQuery);
            return Integer.valueOf(queryResults[0].get('cnt'));
        } catch (Exception e) {
            return -1;
        }
    }

    /**
     * @description Returns the last 20 audit log records ordered by start time descending.
     * @return List of TEKCO_AnonymizationAuditLog__c records.
     */
    @AuraEnabled(cacheable=false)
    public static List<TEKCO_AnonymizationAuditLog__c> getAuditLogs() {
        return [
            SELECT
                Name,
                TEKCO_ObjectApiName__c,
                TEKCO_BrandFilter__c,
                TEKCO_Status__c,
                TEKCO_RecordsProcessed__c,
                TEKCO_RecordsFailed__c,
                TEKCO_StartTime__c,
                TEKCO_EndTime__c,
                TEKCO_JobId__c,
                TEKCO_TriggeredBy__r.Name,
                TEKCO_ErrorMessage__c
            FROM TEKCO_AnonymizationAuditLog__c
            ORDER BY TEKCO_StartTime__c DESC
            LIMIT 20
        ];
    }

    /**
     * @description Launches the anonymization batch chain
     *              Requires TEKCO_AnonymizeData custom permission and a sandbox org
     *              Activates bypass settings before the chain starts and restores them at the end
     * @return                     Id of the created TEKCO_AnonymizationAuditLog__c record
     */
    @AuraEnabled
    public static Id startAnonymization(
        List<String> selectedBrands,
        List<String> selectedObjects,
        List<String> excludedFields,
        List<String> selectedRecordTypes,
        List<String> disabledHistoryFields
    ) {
        if (!FeatureManagement.checkPermission('TEKCO_AnonymizeData')) {
            throw new AuraHandledException(
                'Permission denied: the "TEKCO Anonymize Data" custom permission is required.'
            );
        }

        TEKCO_AnonymizationSandboxGuard.assertIsSandbox();

        if (selectedObjects == null || selectedObjects.isEmpty()) {
            selectedObjects = getObjectApiNames();
        }
        if (selectedObjects.isEmpty()) {
            throw new AuraHandledException(
                'No active field configurations found. Check TEKCO_AnonymizationFieldConfig__mdt records.'
            );
        }

        Set<String> excludedFieldKeys = new Set<String>();
        if (excludedFields != null) excludedFieldKeys.addAll(excludedFields);

        Set<String> disabledHistoryFieldKeys = new Set<String>();
        if (disabledHistoryFields != null) disabledHistoryFieldKeys.addAll(disabledHistoryFields);

        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot =
            TEKCO_AnonymizationBypassService.activate();

        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType = buildPatternMap();

        List<TEKCO_AnonymizationFieldConfig__mdt> allFieldConfigs = [
            SELECT
                TEKCO_ObjectApiName__c,
                TEKCO_FieldApiName__c,
                TEKCO_PatternType__c,
                TEKCO_IsActive__c,
                TEKCO_RecordTypeDeveloperName__c,
                TEKCO_DeleteHistory__c,
                TEKCO_ParentObjectApiName__c,
                TEKCO_ParentLookupFieldApiName__c,
                TEKCO_ParentRecordTypeDeveloperName__c,
                TEKCO_AdditionalFilter__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
                AND TEKCO_ObjectApiName__c IN :selectedObjects
        ];

        if (selectedRecordTypes != null && !selectedRecordTypes.isEmpty()) {
            Set<String> rtFilter = new Set<String>(selectedRecordTypes);
            List<TEKCO_AnonymizationFieldConfig__mdt> filteredConfigs =
                new List<TEKCO_AnonymizationFieldConfig__mdt>();
            for (TEKCO_AnonymizationFieldConfig__mdt fc : allFieldConfigs) {
                if (String.isBlank(fc.TEKCO_RecordTypeDeveloperName__c)
                        || rtFilter.contains(fc.TEKCO_RecordTypeDeveloperName__c)) {
                    filteredConfigs.add(fc);
                }
            }
            allFieldConfigs = filteredConfigs;
        }

        // Bucket 1: regular field anonymization grouped by object (respecting exclusions)
        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByObject =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();

        // Bucket 2: ContentDocument deletion — full CMT configs (RT-aware, one batch per config)
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();

        // Bucket 3: field history deletion configs
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();

        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : allFieldConfigs) {
            String fieldKey = fieldConfig.TEKCO_ObjectApiName__c + '.' + fieldConfig.TEKCO_FieldApiName__c;

            if (fieldConfig.TEKCO_PatternType__c == PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                if (!excludedFieldKeys.contains(fieldKey)) {
                    contentDocConfigs.add(fieldConfig);
                }
                continue;
            }

            if (excludedFieldKeys.contains(fieldKey)) continue;

            if (!configsByObject.containsKey(fieldConfig.TEKCO_ObjectApiName__c)) {
                configsByObject.put(
                    fieldConfig.TEKCO_ObjectApiName__c,
                    new List<TEKCO_AnonymizationFieldConfig__mdt>()
                );
            }
            configsByObject.get(fieldConfig.TEKCO_ObjectApiName__c).add(fieldConfig);

            if (fieldConfig.TEKCO_DeleteHistory__c) {
                String historyKey = fieldConfig.TEKCO_ObjectApiName__c + '.' + fieldConfig.TEKCO_FieldApiName__c;
                if (!disabledHistoryFieldKeys.contains(historyKey)) {
                    historyConfigs.add(fieldConfig);
                }
            }
        }

        // Ordered list of objects to anonymize (respects selectedObjects order)
        List<String> objectsToProcess = new List<String>();
        for (String objectApiName : selectedObjects) {
            if (configsByObject.containsKey(objectApiName)) objectsToProcess.add(objectApiName);
        }

        // Build parent filter map: childObjectApiName → [parentObject, parentLookup, parentRT]
        Map<String, List<String>> parentFiltersByObject = new Map<String, List<String>>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : allFieldConfigs) {
            String obj = fc.TEKCO_ObjectApiName__c;
            if (!parentFiltersByObject.containsKey(obj)
                    && String.isNotBlank(fc.TEKCO_ParentObjectApiName__c)
                    && String.isNotBlank(fc.TEKCO_ParentLookupFieldApiName__c)) {
                parentFiltersByObject.put(obj, new List<String>{
                    fc.TEKCO_ParentObjectApiName__c,
                    fc.TEKCO_ParentLookupFieldApiName__c,
                    fc.TEKCO_ParentRecordTypeDeveloperName__c != null
                        ? fc.TEKCO_ParentRecordTypeDeveloperName__c : ''
                });
            }
        }

        // Build additional filter map: objectApiName → raw WHERE fragment
        Map<String, String> additionalFiltersByObject = new Map<String, String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : allFieldConfigs) {
            String obj = fc.TEKCO_ObjectApiName__c;
            if (!additionalFiltersByObject.containsKey(obj)
                    && String.isNotBlank(fc.TEKCO_AdditionalFilter__c)) {
                additionalFiltersByObject.put(obj, fc.TEKCO_AdditionalFilter__c);
            }
        }

        String brandLabel = (selectedBrands == null || selectedBrands.isEmpty())
            ? 'ALL'
            : String.join(selectedBrands, ', ');

        TEKCO_AnonymizationAuditLog__c auditLog = new TEKCO_AnonymizationAuditLog__c(
            TEKCO_TriggeredBy__c    = UserInfo.getUserId(),
            TEKCO_BrandFilter__c    = brandLabel,
            TEKCO_ObjectApiName__c = String.join(selectedObjects, ', '),
            TEKCO_Status__c          = 'Running',
            TEKCO_StartTime__c      = Datetime.now()
        );
        insert auditLog;

        Id batchJobId;

        if (!objectsToProcess.isEmpty()) {
            // Phase 1: regular field anonymization
            String firstObjectApiName = objectsToProcess.remove(0);
            List<TEKCO_AnonymizationFieldConfig__mdt> firstObjectConfigs =
                configsByObject.get(firstObjectApiName);
            batchJobId = Database.executeBatch(
                new TEKCO_AnonymizationBatch(
                    firstObjectApiName,
                    firstObjectConfigs,
                    patternsByType,
                    selectedBrands,
                    auditLog.Id,
                    objectsToProcess,
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
            batchJobId = Database.executeBatch(
                new TEKCO_ContentDocumentBatch(
                    firstContentDocConfig,
                    selectedBrands,
                    auditLog.Id,
                    contentDocConfigs,
                    historyConfigs,
                    bypassSnapshot,
                    parentFiltersByObject,
                    additionalFiltersByObject
                ),
                DEFAULT_BATCH_SIZE
            );
        } else {
            TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            update new TEKCO_AnonymizationAuditLog__c(
                Id              = auditLog.Id,
                TEKCO_Status__c = 'Success',
                TEKCO_EndTime__c = Datetime.now(),
                TEKCO_ErrorMessage__c = 'No active field configurations found for selected scope.'
            );
            return auditLog.Id;
        }

        auditLog.TEKCO_JobId__c = String.valueOf(batchJobId);
        update auditLog;

        return auditLog.Id;
    }

    private static Map<String, TEKCO_AnonymizationPattern__mdt> buildPatternMap() {
        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType =
            new Map<String, TEKCO_AnonymizationPattern__mdt>();
        for (TEKCO_AnonymizationPattern__mdt patternRecord : [
            SELECT
                DeveloperName,
                TEKCO_Description__c,
                TEKCO_BaseEmail__c,
                TEKCO_ExternalIdField__c,
                TEKCO_SsnLength__c,
                TEKCO_IsActive__c
            FROM TEKCO_AnonymizationPattern__mdt
            WHERE TEKCO_IsActive__c = true
        ]) {
            patternsByType.put(patternRecord.DeveloperName, patternRecord);
        }
        return patternsByType;
    }

    /**
     * @description Data transfer object for field configuration display in the LWC.
     */
    public class FieldConfigDTO {
        @AuraEnabled public String  objectApiName;
        @AuraEnabled public String  fieldApiName;
        @AuraEnabled public String  patternType;
        @AuraEnabled public String  patternDescription;
        @AuraEnabled public String  recordTypeDeveloperName;
        @AuraEnabled public Boolean deleteHistory;
        @AuraEnabled public String  parentObjectApiName;
        @AuraEnabled public String  parentLookupFieldApiName;
        @AuraEnabled public String  parentRecordTypeDeveloperName;
        @AuraEnabled public String  additionalFilter;
    }
}
