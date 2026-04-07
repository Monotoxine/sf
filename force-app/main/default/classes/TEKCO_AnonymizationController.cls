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
                Object_API_Name__c,
                Pattern_Type__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE Is_Active__c = true
        ]) {
            if (String.isNotBlank(fieldConfig.Object_API_Name__c)
                    && fieldConfig.Pattern_Type__c != PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                objectApiNameSet.add(fieldConfig.Object_API_Name__c);
            }
        }
        List<String> objectApiNames = new List<String>(objectApiNameSet);
        objectApiNames.sort();
        return objectApiNames;
    }

    /**
     * @description Returns field configs for a given object (or all objects if blank),
     *              enriched with pattern description for display in the LWC.
     * @param objectApiName API name of the object to filter by, or blank for all objects.
     * @return List of FieldConfigDTO enriched with pattern description.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldConfigDTO> getFieldConfigs(String objectApiName) {
        List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigRecords;
        if (String.isBlank(objectApiName)) {
            fieldConfigRecords = [
                SELECT
                    Object_API_Name__c,
                    Field_API_Name__c,
                    Pattern_Type__c,
                    Is_Active__c,
                    Record_Type_Developer_Name__c,
                    Delete_History__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE Is_Active__c = true
                    AND Pattern_Type__c != :PATTERN_TYPE_DELETE_CONTENT_DOCUMENT
                ORDER BY Object_API_Name__c, Field_API_Name__c
            ];
        } else {
            fieldConfigRecords = [
                SELECT
                    Object_API_Name__c,
                    Field_API_Name__c,
                    Pattern_Type__c,
                    Is_Active__c,
                    Record_Type_Developer_Name__c,
                    Delete_History__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE Is_Active__c = true
                    AND Pattern_Type__c != :PATTERN_TYPE_DELETE_CONTENT_DOCUMENT
                    AND Object_API_Name__c = :objectApiName
                ORDER BY Field_API_Name__c
            ];
        }

        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType = buildPatternMap();
        List<FieldConfigDTO> fieldConfigDtos = new List<FieldConfigDTO>();

        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : fieldConfigRecords) {
            FieldConfigDTO fieldConfigDto        = new FieldConfigDTO();
            fieldConfigDto.objectApiName         = fieldConfig.Object_API_Name__c;
            fieldConfigDto.fieldApiName          = fieldConfig.Field_API_Name__c;
            fieldConfigDto.patternType           = fieldConfig.Pattern_Type__c;
            fieldConfigDto.recordTypeDeveloperName = fieldConfig.Record_Type_Developer_Name__c;
            fieldConfigDto.deleteHistory         = fieldConfig.Delete_History__c;

            TEKCO_AnonymizationPattern__mdt patternRecord = patternsByType.get(fieldConfig.Pattern_Type__c);
            fieldConfigDto.patternDescription = (patternRecord != null
                    && String.isNotBlank(patternRecord.Description__c))
                ? patternRecord.Description__c
                : fieldConfig.Pattern_Type__c;

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
     * @return List of Anonymization_Audit_Log__c records.
     */
    @AuraEnabled(cacheable=false)
    public static List<Anonymization_Audit_Log__c> getAuditLogs() {
        return [
            SELECT
                Name,
                Object_API_Name__c,
                Brand_Filter__c,
                Status__c,
                Records_Processed__c,
                Records_Failed__c,
                Start_Time__c,
                End_Time__c,
                Job_Id__c,
                Triggered_By__r.Name,
                Error_Message__c
            FROM Anonymization_Audit_Log__c
            ORDER BY Start_Time__c DESC
            LIMIT 20
        ];
    }

    // ── Write Methods ─────────────────────────────────────────────────────────

    /**
     * @description Launches the anonymization batch chain.
     *              Requires TEKCO_AnonymizeData custom permission and a sandbox org.
     *              Activates bypass settings before the chain starts and restores them at the end.
     * @param selectedBrands  Brand values to filter records (empty = all brands).
     * @param selectedObjects Object API names to process (empty = all configured objects).
     * @param excludedFields  Fields to skip in this run, format "ObjectApiName.FieldApiName".
     * @return                Id of the created Anonymization_Audit_Log__c record.
     */
    @AuraEnabled
    public static Id startAnonymization(
        List<String> selectedBrands,
        List<String> selectedObjects,
        List<String> excludedFields
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
                Object_API_Name__c,
                Field_API_Name__c,
                Pattern_Type__c,
                Is_Active__c,
                Record_Type_Developer_Name__c,
                Delete_History__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE Is_Active__c = true
                AND Object_API_Name__c IN :selectedObjects
        ];

        // Bucket 1: regular field anonymization grouped by object (respecting exclusions)
        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByObject =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();

        // Bucket 2: objects needing ContentDocument deletion
        Set<String> contentDocObjectSet = new Set<String>();

        // Bucket 3: field history deletion configs
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();

        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : allFieldConfigs) {
            String fieldKey = fieldConfig.Object_API_Name__c + '.' + fieldConfig.Field_API_Name__c;

            if (fieldConfig.Pattern_Type__c == PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                contentDocObjectSet.add(fieldConfig.Object_API_Name__c);
                continue;
            }

            if (excludedFieldKeys.contains(fieldKey)) continue;

            if (!configsByObject.containsKey(fieldConfig.Object_API_Name__c)) {
                configsByObject.put(
                    fieldConfig.Object_API_Name__c,
                    new List<TEKCO_AnonymizationFieldConfig__mdt>()
                );
            }
            configsByObject.get(fieldConfig.Object_API_Name__c).add(fieldConfig);

            if (fieldConfig.Delete_History__c) {
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

        Anonymization_Audit_Log__c auditLog = new Anonymization_Audit_Log__c(
            Triggered_By__c    = UserInfo.getUserId(),
            Brand_Filter__c    = brandLabel,
            Object_API_Name__c = String.join(selectedObjects, ', '),
            Status__c          = 'Running',
            Start_Time__c      = Datetime.now()
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

        auditLog.Job_Id__c = String.valueOf(batchJobId);
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
                Description__c,
                Base_Email__c,
                External_Id_Field__c,
                SSN_Length__c,
                Is_Active__c
            FROM TEKCO_AnonymizationPattern__mdt
            WHERE Is_Active__c = true
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
