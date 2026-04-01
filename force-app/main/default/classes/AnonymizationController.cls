/**
 * AnonymizationController
 * @AuraEnabled controller for the dataAnonymizationAdmin LWC.
 *
 * Brands: read directly from the TEKCO_Brand__c picklist on Account via Schema describe.
 * Objects: derived from active TEKCO_AnonymizationFieldConfig__mdt records.
 * Permission guard: Anonymize_Data custom permission.
 * Sandbox guard: double-checked at controller + batch level.
 */
public with sharing class AnonymizationController {

    // ── Read Methods ─────────────────────────────────────────────────────────

    /**
     * Returns all active picklist values from Account.TEKCO_Brand__c.
     * No CMT configuration needed — reads directly from the field schema.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getBrands() {
        List<String> brands = new List<String>();
        try {
            Schema.DescribeFieldResult fieldDesc =
                Schema.SObjectType.Account.fields.getMap()
                    .get('TEKCO_Brand__c')
                    .getDescribe();

            for (Schema.PicklistEntry entry : fieldDesc.getPicklistValues()) {
                if (entry.isActive()) {
                    brands.add(entry.getValue());
                }
            }
        } catch (Exception e) {
            throw new AuraHandledException(
                'Could not load Brand picklist. Check that TEKCO_Brand__c exists on Account. Error: ' + e.getMessage()
            );
        }
        brands.sort();
        return brands;
    }

    /**
     * Returns distinct object API names from active TEKCO_AnonymizationFieldConfig__mdt records.
     * These implicitly define the anonymization scope.
     */
    @AuraEnabled(cacheable=true)
    public static List<String> getObjects() {
        Set<String> objects = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt cfg : [
            SELECT Object_API_Name__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE Is_Active__c = true
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
     * Returns field configs for a given object, enriched with pattern description.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldConfigDTO> getFieldConfigs(String objectApiName) {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs;
        if (String.isBlank(objectApiName)) {
            configs = [
                SELECT Object_API_Name__c, Field_API_Name__c, Pattern_Type__c, Is_Active__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE Is_Active__c = true
                ORDER BY Object_API_Name__c, Field_API_Name__c
            ];
        } else {
            configs = [
                SELECT Object_API_Name__c, Field_API_Name__c, Pattern_Type__c, Is_Active__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE Is_Active__c = true
                  AND Object_API_Name__c = :objectApiName
                ORDER BY Field_API_Name__c
            ];
        }

        Map<String, TEKCO_AnonymizationPattern__mdt> patterns = getPatternMap();
        List<FieldConfigDTO> result = new List<FieldConfigDTO>();

        for (TEKCO_AnonymizationFieldConfig__mdt cfg : configs) {
            FieldConfigDTO dto = new FieldConfigDTO();
            dto.objectApiName = cfg.Object_API_Name__c;
            dto.fieldApiName  = cfg.Field_API_Name__c;
            dto.patternType   = cfg.Pattern_Type__c;
            TEKCO_AnonymizationPattern__mdt pattern = patterns.get(cfg.Pattern_Type__c);
            dto.patternDescription = (pattern != null && String.isNotBlank(pattern.Description__c))
                ? pattern.Description__c
                : cfg.Pattern_Type__c;
            result.add(dto);
        }
        return result;
    }

    /**
     * Returns an approximate record count for a given object + brand filter.
     * selectedBrands empty = no filter applied.
     */
    @AuraEnabled(cacheable=false)
    public static Integer getRecordCount(String objectApiName, List<String> selectedBrands) {
        if (String.isBlank(objectApiName)) return 0;
        try {
            String soql = 'SELECT COUNT(Id) cnt FROM ' + objectApiName;
            if (selectedBrands != null && !selectedBrands.isEmpty()) {
                soql += ' WHERE TEKCO_Brand__c IN :selectedBrands';
            }
            List<AggregateResult> result = Database.query(soql);
            return Integer.valueOf(result[0].get('cnt'));
        } catch (Exception e) {
            return -1;
        }
    }

    /**
     * Returns the last 20 audit log records.
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

    // ── Write Methods ─────────────────────────────────────────────────────────

    /**
     * Launches the anonymization batch.
     * @param selectedBrands  Brand values to filter records (empty = all brands)
     * @param selectedObjects Object API names to process (empty = all configured)
     * @return                Anonymization_Audit_Log__c Id
     */
    @AuraEnabled
    public static Id startAnonymization(List<String> selectedBrands, List<String> selectedObjects) {
        if (!FeatureManagement.checkPermission('Anonymize_Data')) {
            throw new AuraHandledException(
                'Permission denied: the "Anonymize Data" custom permission is required.'
            );
        }

        AnonymizationSandboxGuard.assertIsSandbox();

        if (selectedObjects == null || selectedObjects.isEmpty()) {
            selectedObjects = getObjects();
        }
        if (selectedObjects.isEmpty()) {
            throw new AuraHandledException('No active field configurations found. Check TEKCO_AnonymizationFieldConfig__mdt records.');
        }

        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType = getPatternMap();

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

        String firstObject = selectedObjects.remove(0);
        List<TEKCO_AnonymizationFieldConfig__mdt> firstConfigs = loadFieldConfigs(firstObject);

        Id jobId = Database.executeBatch(
            new AnonymizationBatch(
                firstObject,
                firstConfigs,
                patternsByType,
                selectedBrands,
                auditLog.Id,
                selectedObjects
            ),
            200
        );

        auditLog.Job_Id__c = String.valueOf(jobId);
        update auditLog;

        return auditLog.Id;
    }

    // ── Internal Helpers ──────────────────────────────────────────────────────

    private static Map<String, TEKCO_AnonymizationPattern__mdt> getPatternMap() {
        Map<String, TEKCO_AnonymizationPattern__mdt> result = new Map<String, TEKCO_AnonymizationPattern__mdt>();
        for (TEKCO_AnonymizationPattern__mdt p : [
            SELECT DeveloperName, Description__c, Base_Email__c,
                   External_Id_Field__c, SSN_Length__c, Is_Active__c
            FROM TEKCO_AnonymizationPattern__mdt
            WHERE Is_Active__c = true
        ]) {
            result.put(p.DeveloperName, p);
        }
        return result;
    }

    private static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigs(String objectName) {
        return [
            SELECT Object_API_Name__c, Field_API_Name__c, Pattern_Type__c, Is_Active__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE Object_API_Name__c = :objectName
              AND Is_Active__c = true
        ];
    }

    // ── DTOs ──────────────────────────────────────────────────────────────────

    public class FieldConfigDTO {
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String fieldApiName;
        @AuraEnabled public String patternType;
        @AuraEnabled public String patternDescription;
    }
}
