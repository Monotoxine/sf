/**
 * @author TEKCO Team, 07/04/2026
 * @description AuraEnabled controller for the tekcoDataAnonymizationAdmin LWC.
 *
 *              Brands:    read directly from the TEKCO_Brand__c picklist on Account via Schema describe.
 *              Objects:   derived from active TEKCO_AnonymizationFieldConfig__mdt records.
 *              Permission guard: TEKCO_AnonymizeData custom permission.
 *              Sandbox guard:    double-checked at controller + batch level.
 */
public with sharing class TEKCO_AnonymizationController {

    private static final String PATTERN_TYPE_DELETE_CONTENT_DOCUMENT = 'DELETE_CONTENT_DOCUMENT';
    private static final Integer DEFAULT_BATCH_SIZE = 200;

    // ── Read Methods ─────────────────────────────────────────────────────────

    /**
     * @description Returns all active picklist values from Account.TEKCO_Brand__c.
     * @return Sorted list of active brand values.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getBrands() {
        List<String> brandValues = new List<String>();
        try {
            Schema.DescribeFieldResult fieldDescriptor =
                Schema.SObjectType.Account.fields.getMap()
                    .get('TEKCO_Brand__c')
                    .getDescribe();
            for (Schema.PicklistEntry entry : fieldDescriptor.getPicklistValues()) {
                if (entry.isActive()) brandValues.add(entry.getValue());
            }
        } catch (Exception e) {
            throw new AuraHandledException(
                'Could not load Brand picklist. Check that TEKCO_Brand__c exists on Account. Error: '
                + e.getMessage()
            );
        }
        brandValues.sort();
        return brandValues;
    }

    /**
     * @description Returns distinct object API names from active TEKCO_AnonymizationFieldConfig__mdt.
     *              Excludes objects that only have DELETE_CONTENT_DOCUMENT entries (not user-selectable).
     * @return Sorted list of object API names.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getObjects() {
        Set<String> objectApiNameSet = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : [
            SELECT
                TEKCO_ObjectApiName__c,
                TEKCO_PatternType__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
        ]) {
            if (String.isNotBlank(fieldConfig.TEKCO_ObjectApiName__c)
                    && fieldConfig.TEKCO_PatternType__c != PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                objectApiNameSet.add(fieldConfig.TEKCO_ObjectApiName__c);
            }
        }
        List<String> objectApiNames = new List<String>(objectApiNameSet);
        objectApiNames.sort();
        return objectApiNames;
    }

    /**
     * @description Returns distinct Record Type Developer Names from active FieldConfig records,
     *              optionally scoped to a given object.
     *              Blank TEKCO_RecordTypeDeveloperName__c entries are excluded (they apply to all RTs).
     * @param objectApiName API name of the object to scope to, or blank for all objects.
     * @return Sorted list of Record Type Developer Names.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getRecordTypes(String objectApiName) {
        Set<String> recordTypeSet = new Set<String>();
        List<TEKCO_AnonymizationFieldConfig__mdt> configs;
        if (String.isBlank(objectApiName)) {
            configs = [
                SELECT TEKCO_RecordTypeDeveloperName__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE TEKCO_IsActive__c = true
                    AND TEKCO_RecordTypeDeveloperName__c != null
            ];
        } else {
            configs = [
                SELECT TEKCO_RecordTypeDeveloperName__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE TEKCO_IsActive__c = true
                    AND TEKCO_ObjectApiName__c = :objectApiName
                    AND TEKCO_RecordTypeDeveloperName__c != null
            ];
        }
        for (TEKCO_AnonymizationFieldConfig__mdt config : configs) {
            recordTypeSet.add(config.TEKCO_RecordTypeDeveloperName__c);
        }
        List<String> recordTypes = new List<String>(recordTypeSet);
        recordTypes.sort();
        return recordTypes;
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
                    TEKCO_DeleteHistory__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE TEKCO_IsActive__c = true
                    AND TEKCO_PatternType__c != :PATTERN_TYPE_DELETE_CONTENT_DOCUMENT
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
                    TEKCO_DeleteHistory__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE TEKCO_IsActive__c = true
                    AND TEKCO_PatternType__c != :PATTERN_TYPE_DELETE_CONTENT_DOCUMENT
                    AND TEKCO_ObjectApiName__c = :objectApiName
                ORDER BY TEKCO_FieldApiName__c
            ];
        }

        // In-memory RT filter: keep configs with no RT (applies to all) OR matching a selected RT
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
            fieldConfigDto.objectApiName           = fieldConfig.TEKCO_ObjectApiName__c;
            fieldConfigDto.fieldApiName            = fieldConfig.TEKCO_FieldApiName__c;
            fieldConfigDto.patternType             = fieldConfig.TEKCO_PatternType__c;
            fieldConfigDto.recordTypeDeveloperName = fieldConfig.TEKCO_RecordTypeDeveloperName__c;
            fieldConfigDto.deleteHistory           = fieldConfig.TEKCO_DeleteHistory__c;

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
     * @description Returns an approximate record count for a given object + brand filter.
     * @param objectApiName  API name of the object to count.
     * @param selectedBrands Brand values to filter by (empty = all brands).
     * @return Record count, or -1 if the count could not be retrieved.
     */
    @AuraEnabled(cacheable=false)
    public static Integer getRecordCount(String objectApiName, List<String> selectedBrands) {
        if (String.isBlank(objectApiName)) return 0;
        try {
            String soqlQuery = 'SELECT COUNT(Id) cnt FROM ' + objectApiName;
            if (selectedBrands != null && !selectedBrands.isEmpty()) {
                soqlQuery += ' WHERE TEKCO_Brand__c IN :selectedBrands';
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

    // ── Write Methods ─────────────────────────────────────────────────────────

    /**
     * @description Launches the anonymization batch chain.
     *              Requires TEKCO_AnonymizeData custom permission and a sandbox org.
     *              Activates bypass settings before the chain starts and restores them at the end.
     * @param selectedBrands      Brand values to filter records (empty = all brands).
     * @param selectedObjects     Object API names to process (empty = all configured objects).
     * @param excludedFields      Fields to skip in this run, format "ObjectApiName.FieldApiName".
     * @param selectedRecordTypes Record Type Developer Names to restrict to (empty = all RTs).
     * @return                    Id of the created TEKCO_AnonymizationAuditLog__c record.
     */
    @AuraEnabled
    public static Id startAnonymization(
        List<String> selectedBrands,
        List<String> selectedObjects,
        List<String> excludedFields,
        List<String> selectedRecordTypes
    ) {
        if (!FeatureManagement.checkPermission('TEKCO_AnonymizeData')) {
            throw new AuraHandledException(
                'Permission denied: the "TEKCO Anonymize Data" custom permission is required.'
            );
        }

        TEKCO_AnonymizationSandboxGuard.assertIsSandbox();

        if (selectedObjects == null || selectedObjects.isEmpty()) {
            selectedObjects = getObjects();
        }
        if (selectedObjects.isEmpty()) {
            throw new AuraHandledException(
                'No active field configurations found. Check TEKCO_AnonymizationFieldConfig__mdt records.'
            );
        }

        Set<String> excludedFieldKeys = new Set<String>();
        if (excludedFields != null) excludedFieldKeys.addAll(excludedFields);

        // Activate trigger bypass for the running user (restored at end of batch chain)
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
                TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
                AND TEKCO_ObjectApiName__c IN :selectedObjects
        ];

        // Record Type filter: keep configs with no RT (applies to all) OR matching a selected RT
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

        // Bucket 2: objects needing ContentDocument deletion
        Set<String> contentDocObjectSet = new Set<String>();

        // Bucket 3: field history deletion configs
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();

        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : allFieldConfigs) {
            String fieldKey = fieldConfig.TEKCO_ObjectApiName__c + '.' + fieldConfig.TEKCO_FieldApiName__c;

            if (fieldConfig.TEKCO_PatternType__c == PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                contentDocObjectSet.add(fieldConfig.TEKCO_ObjectApiName__c);
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
                historyConfigs.add(fieldConfig);
            }
        }

        // Ordered list of objects to anonymize (respects selectedObjects order)
        List<String> objectsToProcess = new List<String>();
        for (String objectApiName : selectedObjects) {
            if (configsByObject.containsKey(objectApiName)) objectsToProcess.add(objectApiName);
        }

        List<String> contentDocObjects = new List<String>(contentDocObjectSet);

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

        String firstObjectApiName = objectsToProcess.remove(0);
        List<TEKCO_AnonymizationFieldConfig__mdt> firstObjectConfigs =
            configsByObject.get(firstObjectApiName);

        Id batchJobId = Database.executeBatch(
            new TEKCO_AnonymizationBatch(
                firstObjectApiName,
                firstObjectConfigs,
                patternsByType,
                selectedBrands,
                auditLog.Id,
                objectsToProcess,
                contentDocObjects,
                historyConfigs,
                bypassSnapshot
            ),
            DEFAULT_BATCH_SIZE
        );

        auditLog.TEKCO_JobId__c = String.valueOf(batchJobId);
        update auditLog;

        return auditLog.Id;
    }

    // ── Internal Helpers ──────────────────────────────────────────────────────

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

    // ── DTOs ──────────────────────────────────────────────────────────────────

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
    }
}
