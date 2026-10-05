public inherited sharing class TEKCO_AnonymizationConfigSelector {

    private static Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByDevNamesCache =
        new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();
    private static Map<String, TEKCO_AnonymizationPattern__mdt> patternMapCache;
    private static Map<String, String> configuredObjectsCache;

    public static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigs(String objectApiName) {
        return [
            SELECT DeveloperName, TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c,
                   TEKCO_PatternType__c, TEKCO_IsActive__c,
                   TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_ObjectApiName__c = :objectApiName AND TEKCO_IsActive__c = true
        ];
    }

    public static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigsByDevNames(
        List<String> devNames
    ) {
        if (devNames == null || devNames.isEmpty()) {
            return new List<TEKCO_AnonymizationFieldConfig__mdt>();
        }
        String cacheKey = String.join(devNames, '|');
        if (configsByDevNamesCache.containsKey(cacheKey)) {
            return configsByDevNamesCache.get(cacheKey);
        }
        List<TEKCO_AnonymizationFieldConfig__mdt> result = [
            SELECT DeveloperName, TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c,
                   TEKCO_PatternType__c, TEKCO_IsActive__c,
                   TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE DeveloperName IN :devNames
        ];
        configsByDevNamesCache.put(cacheKey, result);
        return result;
    }

    public static Map<String, TEKCO_AnonymizationPattern__mdt> buildPatternMap() {
        if (patternMapCache != null) return patternMapCache;
        Map<String, TEKCO_AnonymizationPattern__mdt> result =
            new Map<String, TEKCO_AnonymizationPattern__mdt>();
        for (TEKCO_AnonymizationPattern__mdt p : [
            SELECT DeveloperName, TEKCO_Description__c, TEKCO_ExternalIdField__c,
                   TEKCO_BaseEmail__c, TEKCO_SsnLength__c, TEKCO_IsActive__c,
                   TEKCO_RegexFind__c, TEKCO_RegexReplace__c
            FROM TEKCO_AnonymizationPattern__mdt WHERE TEKCO_IsActive__c = true
        ]) {
            result.put(p.DeveloperName, p);
        }
        patternMapCache = result;
        return result;
    }

    public static Map<String, String> configuredObjectsByLower() {
        if (configuredObjectsCache != null) return configuredObjectsCache;
        Map<String, String> result = new Map<String, String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : [
            SELECT TEKCO_ObjectApiName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true AND TEKCO_ObjectApiName__c != null
        ]) {
            result.put(fc.TEKCO_ObjectApiName__c.toLowerCase(), fc.TEKCO_ObjectApiName__c);
        }
        configuredObjectsCache = result;
        return result;
    }

    public static String configKey(TEKCO_AnonymizationFieldConfig__mdt config) {
        if (config == null) return '';
        return config.DeveloperName;
    }

    public static Set<String> recordTypesOf(TEKCO_AnonymizationFieldConfig__mdt config) {
        Set<String> recordTypes = new Set<String>();
        if (config == null || String.isBlank(config.TEKCO_RecordTypeDeveloperName__c)) {
            return recordTypes;
        }
        for (String name : config.TEKCO_RecordTypeDeveloperName__c.split(',')) {
            String trimmed = name.trim();
            if (String.isNotBlank(trimmed)) recordTypes.add(trimmed);
        }
        return recordTypes;
    }

    public static Boolean isRecordTypeScoped(TEKCO_AnonymizationFieldConfig__mdt config) {
        return !recordTypesOf(config).isEmpty();
    }

    public static List<String> toDevNames(List<TEKCO_AnonymizationFieldConfig__mdt> configs) {
        List<String> names = new List<String>();
        if (configs == null) return names;
        for (TEKCO_AnonymizationFieldConfig__mdt c : configs) {
            if (String.isNotBlank(c.DeveloperName)) names.add(c.DeveloperName);
        }
        return names;
    }
}
