/**
 * AnonymizationController
 * @AuraEnabled controller for the dataAnonymizationAdmin LWC.
 *
 * Permission guard: all write methods check the "Anonymize_Data" custom permission.
 * Sandbox guard: called before any batch is started.
 */
public with sharing class AnonymizationController {

    // ─── Read Methods (cacheable) ─────────────────────────────────────────────

    /**
     * Returns distinct brand values configured in Anon_Object_Config__mdt.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getBrands() {
        Set<String> brands = new Set<String>();
        for (Anon_Object_Config__mdt cfg : [
            SELECT Brand__c FROM Anon_Object_Config__mdt WHERE Is_Active__c = true
        ]) {
            if (String.isNotBlank(cfg.Brand__c) && cfg.Brand__c != 'ALL') {
                brands.add(cfg.Brand__c);
            }
        }
        List<String> result = new List<String>(brands);
        result.sort();
        return result;
    }

    /**
     * Returns distinct object API names for a given brand (or all if blank).
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getObjects(String brand) {
        Set<String> objects = new Set<String>();
        for (Anon_Object_Config__mdt cfg : [
            SELECT Object_API_Name__c FROM Anon_Object_Config__mdt
            WHERE Is_Active__c = true
              AND (Brand__c = :brand OR Brand__c = 'ALL'
                   OR Brand__c = null OR :brand = null OR :brand = '')
        ]) {
            if (String.isNotBlank(cfg.Object_API_Name__c)) {
                objects.add(cfg.Object_API_Name__c);
            }
        }
        List<String> result = new List<String>(objects);
        result.sort();
        return result;
    }

    /**
     * Returns field configs for a given object + brand, enriched with pattern info.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldConfigDTO> getFieldConfigs(String objectApiName, String brand) {
        List<Anon_Object_Config__mdt> configs = [
            SELECT Object_API_Name__c, Field_API_Name__c, Pattern_Type__c,
                   Brand__c, Is_Active__c, Order__c
            FROM Anon_Object_Config__mdt
            WHERE Is_Active__c = true
              AND (Object_API_Name__c = :objectApiName OR :objectApiName = null OR :objectApiName = '')
              AND (Brand__c = :brand OR Brand__c = 'ALL'
                   OR Brand__c = null OR :brand = null OR :brand = '')
            ORDER BY Object_API_Name__c, Order__c ASC NULLS LAST
        ];

        Map<String, Anon_Pattern__mdt> patterns = getPatternMap();
        List<FieldConfigDTO> result = new List<FieldConfigDTO>();

        for (Anon_Object_Config__mdt cfg : configs) {
            FieldConfigDTO dto = new FieldConfigDTO();
            dto.objectApiName  = cfg.Object_API_Name__c;
            dto.fieldApiName   = cfg.Field_API_Name__c;
            dto.patternType    = cfg.Pattern_Type__c;
            dto.brand          = cfg.Brand__c;

            Anon_Pattern__mdt pattern = patterns.get(cfg.Pattern_Type__c);
            dto.patternDescription = (pattern != null && String.isNotBlank(pattern.Description__c))
                ? pattern.Description__c
                : cfg.Pattern_Type__c;

            result.add(dto);
        }
        return result;
    }

    /**
     * Returns an approximate count of records for a given object.
     * Used for the "preview" panel in the LWC.
     */
    @AuraEnabled(cacheable=false)
    public static Integer getRecordCount(String objectApiName) {
        if (String.isBlank(objectApiName)) return 0;
        try {
            // Dynamic SOQL count — safe: objectApiName comes from CMT (admin-controlled)
            List<AggregateResult> result = Database.query(
                'SELECT COUNT(Id) cnt FROM ' + objectApiName
            );
            return Integer.valueOf(result[0].get('cnt'));
        } catch (Exception e) {
            return -1; // -1 signals "could not count" in the UI
        }
    }

    /**
     * Returns the last 20 audit log records, most recent first.
     */
    @AuraEnabled(cacheable=false)
    public static List<Anonymization_Audit_Log__c> getAuditLogs() {
        return [
            SELECT Name, Object_API_Name__c, Brand_Filter__c, Status__c,
                   Records_Processed__c, Records_Failed__c,
                   Start_Time__c, End_Time__c, Job_Id__c,
                   Triggered_By__r.Name, Error_Message__c
            FROM Anonymization_Audit_Log__c
            ORDER BY Start_Time__c DESC
            LIMIT 20
        ];
    }

    // ─── Write Methods ────────────────────────────────────────────────────────

    /**
     * Launches the anonymization batch for the selected objects/brand.
     * Requires the "Anonymize_Data" custom permission.
     * Blocks if not a sandbox (double guard).
     *
     * @param brand           Brand filter (null = all)
     * @param objectApiNames  List of objects to process (null/empty = all configured)
     * @return                The Anonymization_Audit_Log__c Id
     */
    @AuraEnabled
    public static Id startAnonymization(String brand, List<String> objectApiNames) {
        // 1. Permission check
        if (!FeatureManagement.checkPermission('Anonymize_Data')) {
            throw new AuraHandledException(
                'Permission denied: you need the "Anonymize Data" custom permission.'
            );
        }

        // 2. Sandbox check (first guard — controller level)
        AnonymizationSandboxGuard.assertIsSandbox();

        // 3. Resolve object list from CMT if not specified
        if (objectApiNames == null || objectApiNames.isEmpty()) {
            objectApiNames = getObjects(brand);
        }
        if (objectApiNames.isEmpty()) {
            throw new AuraHandledException('No active anonymization config found for the selected filters.');
        }

        // 4. Load all patterns once (shared across all batches in the chain)
        Map<String, Anon_Pattern__mdt> patternsByType = getPatternMap();

        // 5. Create the audit log record
        Anonymization_Audit_Log__c auditLog = new Anonymization_Audit_Log__c(
            Triggered_By__c  = UserInfo.getUserId(),
            Brand_Filter__c  = String.isNotBlank(brand) ? brand : 'ALL',
            Object_API_Name__c = String.join(objectApiNames, ', '),
            Status__c        = 'Running',
            Start_Time__c    = Datetime.now()
        );
        insert auditLog;

        // 6. Build chained object list and start first batch
        String firstObject = objectApiNames.remove(0); // mutates list → becomes "remaining"
        List<Anon_Object_Config__mdt> firstConfigs = loadFieldConfigs(firstObject, brand);
        Integer firstBatchSize = (firstConfigs.isEmpty() || firstConfigs[0].Batch_Size__c == null)
            ? 200
            : Integer.valueOf(firstConfigs[0].Batch_Size__c);

        AnonymizationBatch batch = new AnonymizationBatch(
            firstObject,
            firstConfigs,
            patternsByType,
            auditLog.Id,
            objectApiNames, // remaining objects
            brand,
            firstBatchSize
        );

        Id jobId = Database.executeBatch(batch, firstBatchSize);

        // 7. Store job ID on audit log
        auditLog.Job_Id__c = String.valueOf(jobId);
        update auditLog;

        return auditLog.Id;
    }

    // ─── Internal Helpers ─────────────────────────────────────────────────────

    private static Map<String, Anon_Pattern__mdt> getPatternMap() {
        Map<String, Anon_Pattern__mdt> result = new Map<String, Anon_Pattern__mdt>();
        for (Anon_Pattern__mdt p : [
            SELECT Pattern_Type__c, Base_Email__c, External_Id_Field__c,
                   SSN_Length__c, Is_Active__c, Description__c
            FROM Anon_Pattern__mdt
            WHERE Is_Active__c = true
        ]) {
            result.put(p.Pattern_Type__c, p);
        }
        return result;
    }

    private static List<Anon_Object_Config__mdt> loadFieldConfigs(String objectName, String brand) {
        return [
            SELECT Object_API_Name__c, Field_API_Name__c, Pattern_Type__c,
                   Brand__c, Is_Active__c, Order__c, Batch_Size__c,
                   Condition_Field__c, Condition_Value__c
            FROM Anon_Object_Config__mdt
            WHERE Object_API_Name__c = :objectName
              AND Is_Active__c = true
              AND (Brand__c = :brand OR Brand__c = 'ALL'
                   OR Brand__c = null OR Brand__c = ''
                   OR :brand = null OR :brand = '')
            ORDER BY Order__c ASC NULLS LAST
        ];
    }

    // ─── DTOs ─────────────────────────────────────────────────────────────────

    public class FieldConfigDTO {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String patternType;
        @AuraEnabled public String patternDescription;
        @AuraEnabled public String brand;
    }
}
