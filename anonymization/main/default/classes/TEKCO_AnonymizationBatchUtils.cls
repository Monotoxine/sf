/**
 * @description Shared utilities for the anonymization batch chain.
 *              Eliminates duplication of history-object helpers, popConfigsForObject,
 *              toDevNames, and cap across the batch classes and their By-ID mirrors.
 */
public class TEKCO_AnonymizationBatchUtils {

    private static final Integer MAX_ERROR_MSG_LENGTH = 200;

    /**
     * Extracts DeveloperNames from a CMDT list so callers store only lightweight strings
     * in stateful batch fields instead of full SObjects.
     */
    public static List<String> toDevNames(List<TEKCO_AnonymizationFieldConfig__mdt> configs) {
        List<String> names = new List<String>();
        if (configs == null) return names;
        for (TEKCO_AnonymizationFieldConfig__mdt c : configs) {
            if (String.isNotBlank(c.DeveloperName)) names.add(c.DeveloperName);
        }
        return names;
    }

    /** Caps an error string at MAX_ERROR_MSG_LENGTH to bound stateful list size. */
    public static String cap(String s) {
        return (s != null && s.length() > MAX_ERROR_MSG_LENGTH)
            ? s.substring(0, MAX_ERROR_MSG_LENGTH)
            : s;
    }

    private static final String CUSTOM_OBJECT_SUFFIX = '__c';

    public static String computeHistoryObjectName(String objectApiName) {
        return objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX)
            ? objectApiName.replace(CUSTOM_OBJECT_SUFFIX, '__History')
            : objectApiName + 'History';
    }

    public static String computeParentIdFieldName(String objectApiName) {
        return objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX) ? 'ParentId' : objectApiName + 'Id';
    }

    public static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigs(String objectApiName) {
        return [
            SELECT DeveloperName, TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c,
                   TEKCO_PatternType__c, TEKCO_IsActive__c,
                   TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_ObjectApiName__c = :objectApiName AND TEKCO_IsActive__c = true
        ];
    }

    public static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigsByDevNames(List<String> devNames) {
        if (devNames == null || devNames.isEmpty()) return new List<TEKCO_AnonymizationFieldConfig__mdt>();
        return [
            SELECT DeveloperName, TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c,
                   TEKCO_PatternType__c, TEKCO_IsActive__c,
                   TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE DeveloperName IN :devNames
        ];
    }

    public static Map<String, TEKCO_AnonymizationPattern__mdt> buildPatternMap() {
        Map<String, TEKCO_AnonymizationPattern__mdt> result = new Map<String, TEKCO_AnonymizationPattern__mdt>();
        for (TEKCO_AnonymizationPattern__mdt p : [
            SELECT DeveloperName, TEKCO_Description__c, TEKCO_ExternalIdField__c,
                   TEKCO_BaseEmail__c, TEKCO_SsnLength__c, TEKCO_IsActive__c,
                   TEKCO_RegexFind__c, TEKCO_RegexReplace__c
            FROM TEKCO_AnonymizationPattern__mdt WHERE TEKCO_IsActive__c = true
        ]) {
            result.put(p.DeveloperName, p);
        }
        return result;
    }

    /**
     * Removes and returns all configs for objectApiName from the supplied list (mutated in place).
     */
    public static List<TEKCO_AnonymizationFieldConfig__mdt> popConfigsForObject(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        List<TEKCO_AnonymizationFieldConfig__mdt> forObj    = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> remaining = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            if (fc.TEKCO_ObjectApiName__c == objectApiName) forObj.add(fc);
            else remaining.add(fc);
        }
        configs.clear();
        configs.addAll(remaining);
        return forObj;
    }
}
