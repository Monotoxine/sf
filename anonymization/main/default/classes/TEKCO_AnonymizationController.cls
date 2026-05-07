/**
 * @author 
 * @description AuraEnabled controller for the tekcoDataAnonymizationAdmin LWC
 */
public with sharing class TEKCO_AnonymizationController {

    private static final String PATTERN_TYPE_DELETE_CONTENT_DOCUMENT  = 'DELETE_CONTENT_DOCUMENT';

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getBrands() {
        List<Map<String, String>> brandOptions = new List<Map<String, String>>();
        try {
            Schema.DescribeFieldResult fieldDescriptor =
                Schema.SObjectType.Account.fields.getMap()
                    .get('tekco_brand__c')
                    .getDescribe();
            for (Schema.PicklistEntry entry : fieldDescriptor.getPicklistValues()) {
                if (entry.isActive()) {
                    brandOptions.add(new Map<String, String>{
                        'label' => entry.getLabel(),
                        'value' => entry.getValue()
                    });
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException(
                'Could not load TEKCO_Brands picklist values. Verify that Account.TEKCO_Brand__c uses the TEKCO_Brands global value set. Error: '
                + e.getMessage()
            );
        }
        return brandOptions;
    }

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

    private static List<String> getObjectApiNames() {
        List<String> result = new List<String>();
        for (Map<String, String> opt : getObjects()) {
            result.add(opt.get('value'));
        }
        return result;
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getRecordTypes(List<String> selectedObjects) {
        if (selectedObjects == null || selectedObjects.isEmpty()) return new List<Map<String, String>>();
        Map<String, String> lowerToOriginal = new Map<String, String>();
        Map<String, Set<String>> rtsByObject = new Map<String, Set<String>>();
        for (String obj : selectedObjects) {
            String lower = obj.toLowerCase();
            lowerToOriginal.put(lower, obj);
            rtsByObject.put(lower, new Set<String>());
        }

        for (TEKCO_AnonymizationFieldConfig__mdt cfg : [
            SELECT TEKCO_RecordTypeDeveloperName__c, TEKCO_ObjectApiName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_ObjectApiName__c IN :selectedObjects
              AND TEKCO_RecordTypeDeveloperName__c != null
        ]) {
            Set<String> rts = rtsByObject.get(cfg.TEKCO_ObjectApiName__c.toLowerCase());
            if (rts != null) rts.add(cfg.TEKCO_RecordTypeDeveloperName__c);
        }

        List<Map<String, String>> options = new List<Map<String, String>>();
        for (String obj : selectedObjects) {
            List<String> sortedRts = new List<String>(rtsByObject.get(obj.toLowerCase()));
            sortedRts.sort();
            for (String rt : sortedRts) {
                options.add(new Map<String, String>{
                    'label' => rt + ' (' + obj + ')',
                    'value' => rt
                });
            }
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<FieldConfigDTO> getFieldConfigs(List<String> selectedObjects) {
        List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigRecords;
        if (selectedObjects == null || selectedObjects.isEmpty()) {
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
                  AND TEKCO_ObjectApiName__c IN :selectedObjects
                ORDER BY TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c
            ];
        }

        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType = buildPatternMap();
        List<FieldConfigDTO> fieldConfigDtos = new List<FieldConfigDTO>();

        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : fieldConfigRecords) {
            FieldConfigDTO fieldConfigDto                 = new FieldConfigDTO();
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

    @AuraEnabled(cacheable=false)
    public static List<PreviewCountDTO> getPreviewCounts(
        List<String> selectedBrands,
        List<String> selectedObjects,
        List<String> selectedRecordTypes
    ) {
        List<String> objectsToCount = (selectedObjects != null && !selectedObjects.isEmpty())
            ? selectedObjects
            : getObjectApiNames();

        List<String> countryValues = (selectedBrands != null && !selectedBrands.isEmpty())
            ? TEKCO_AnonymizationPatternService.getCountriesForBrands(selectedBrands)
            : new List<String>();

        List<TEKCO_AnonymizationFieldConfig__mdt> allConfigs = [
            SELECT TEKCO_ObjectApiName__c, TEKCO_PatternType__c, TEKCO_RecordTypeDeveloperName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_ObjectApiName__c IN :objectsToCount
        ];

        Map<String, Integer> totalByObject      = new Map<String, Integer>();
        Map<String, Integer> contentDocByObject = new Map<String, Integer>();
        Map<String, String> objectByRt = new Map<String, String>();

        for (TEKCO_AnonymizationFieldConfig__mdt fc : allConfigs) {
            String obj = fc.TEKCO_ObjectApiName__c;
            totalByObject.put(obj, (totalByObject.get(obj) != null ? totalByObject.get(obj) : 0) + 1);
            if (fc.TEKCO_PatternType__c == PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                contentDocByObject.put(obj, (contentDocByObject.get(obj) != null ? contentDocByObject.get(obj) : 0) + 1);
            }
            if (String.isNotBlank(fc.TEKCO_RecordTypeDeveloperName__c)
                    && !objectByRt.containsKey(fc.TEKCO_RecordTypeDeveloperName__c)) {
                objectByRt.put(fc.TEKCO_RecordTypeDeveloperName__c, obj);
            }
        }

        Map<String, String> rtFilterByObject = new Map<String, String>();
        if (selectedRecordTypes != null && !selectedRecordTypes.isEmpty()) {
            for (String rt : selectedRecordTypes) {
                String obj = objectByRt.get(rt);
                if (obj != null && !rtFilterByObject.containsKey(obj)) {
                    rtFilterByObject.put(obj, rt);
                }
            }
        }

        Map<String, Boolean> hasBrand      = new Map<String, Boolean>();
        Map<String, Boolean> hasCountry    = new Map<String, Boolean>();
        Map<String, Boolean> hasRecordType = new Map<String, Boolean>();
        for (String obj : objectsToCount) {
            hasBrand.put(obj,      TEKCO_AnonymizationPatternService.hasField(obj, 'tekco_brand__c'));
            hasCountry.put(obj,    TEKCO_AnonymizationPatternService.hasField(obj, 'tekco_country__c'));
            hasRecordType.put(obj, TEKCO_AnonymizationPatternService.hasField(obj, 'recordtypeid'));
        }

        Integer queriesRemaining = Limits.getLimitQueries() - Limits.getQueries();
        if (objectsToCount.size() > queriesRemaining) {
            throw new AuraHandledException(
                'Preview requires ' + objectsToCount.size() + ' queries but only '
                + queriesRemaining + ' remain in this transaction. Select fewer objects.'
            );
        }

        List<PreviewCountDTO> results = new List<PreviewCountDTO>();
        for (String objectApiName : objectsToCount) {
            PreviewCountDTO dto    = new PreviewCountDTO();
            dto.objectApiName      = objectApiName;
            Integer total          = totalByObject.get(objectApiName) != null ? totalByObject.get(objectApiName) : 0;
            Integer contentDoc     = contentDocByObject.get(objectApiName) != null ? contentDocByObject.get(objectApiName) : 0;
            dto.isContentDocOnly   = total > 0 && total == contentDoc;

            try {
                List<String> conditions = new List<String>();
                if (selectedBrands != null && !selectedBrands.isEmpty()) {
                    if (hasBrand.get(objectApiName) == true) {
                        conditions.add('TEKCO_Brand__c IN :selectedBrands');
                    } else if (hasCountry.get(objectApiName) == true && !countryValues.isEmpty()) {
                        conditions.add('TEKCO_Country__c IN :countryValues');
                    }
                }
                String applicableRt = rtFilterByObject.get(objectApiName);
                if (String.isNotBlank(applicableRt) && hasRecordType.get(objectApiName) == true) {
                    conditions.add(
                        'RecordType.DeveloperName = \''
                        + String.escapeSingleQuotes(applicableRt) + '\''
                    );
                }
                String whereClause = conditions.isEmpty()
                    ? '' : ' WHERE ' + String.join(conditions, ' AND ');
                dto.count = Database.countQuery('SELECT COUNT() FROM ' + objectApiName + whereClause);
            } catch (Exception e) {
                dto.count = -1;
            }
            results.add(dto);
        }
        return results;
    }


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

        TEKCO_AnonymizationPatternService.assertIsSandbox();

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

        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByObject =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        Map<String, List<String>> parentFiltersByObject  = new Map<String, List<String>>();
        Map<String, String>       additionalFiltersByObject = new Map<String, String>();

        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : allFieldConfigs) {
            String obj      = fieldConfig.TEKCO_ObjectApiName__c;
            String fieldKey = obj + '.' + fieldConfig.TEKCO_FieldApiName__c;

            if (!parentFiltersByObject.containsKey(obj)
                    && String.isNotBlank(fieldConfig.TEKCO_ParentObjectApiName__c)
                    && String.isNotBlank(fieldConfig.TEKCO_ParentLookupFieldApiName__c)) {
                parentFiltersByObject.put(obj, new List<String>{
                    fieldConfig.TEKCO_ParentObjectApiName__c,
                    fieldConfig.TEKCO_ParentLookupFieldApiName__c,
                    fieldConfig.TEKCO_ParentRecordTypeDeveloperName__c != null
                        ? fieldConfig.TEKCO_ParentRecordTypeDeveloperName__c : ''
                });
            }
            if (!additionalFiltersByObject.containsKey(obj)
                    && String.isNotBlank(fieldConfig.TEKCO_AdditionalFilter__c)) {
                additionalFiltersByObject.put(obj, fieldConfig.TEKCO_AdditionalFilter__c);
            }

            if (fieldConfig.TEKCO_PatternType__c == PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                if (!excludedFieldKeys.contains(fieldKey)) contentDocConfigs.add(fieldConfig);
                continue;
            }

            if (excludedFieldKeys.contains(fieldKey)) continue;

            if (!configsByObject.containsKey(obj)) {
                configsByObject.put(obj, new List<TEKCO_AnonymizationFieldConfig__mdt>());
            }
            configsByObject.get(obj).add(fieldConfig);

            if (fieldConfig.TEKCO_DeleteHistory__c
                    && !disabledHistoryFieldKeys.contains(fieldKey)) {
                historyConfigs.add(fieldConfig);
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
                    new List<String>(),
                    0,
                    parentFiltersByObject,
                    additionalFiltersByObject
                ),
                TEKCO_AnonymizationBatch.DEFAULT_BATCH_SIZE
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
                    new List<String>(),
                    0,
                    parentFiltersByObject,
                    additionalFiltersByObject
                ),
                TEKCO_ContentDocumentBatch.DEFAULT_BATCH_SIZE
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

      public class PreviewCountDTO {
        @AuraEnabled public String  objectApiName;
        @AuraEnabled public Integer count;
        @AuraEnabled public Boolean isContentDocOnly;
    }
    
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
