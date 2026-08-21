/**
 * @description Selector layer: every Custom Metadata query the tool makes lives here, with the
 *              per-transaction caching that makes them affordable.
 *
 *              Split out of the former TEKCO_AnonymizationBatchUtils, which had grown three
 *              unrelated jobs — data access, security gates and string helpers — behind a name
 *              that described none of them and was imported by eleven classes.
 *
 *              Concentrating the SOQL here is what makes the caching possible at all: the batch
 *              chain deliberately keeps no CMDT rows in stateful fields (that caused heap and
 *              serialization failures), so every execute() reloads them. A multi-thousand-chunk
 *              run would otherwise repeat the same queries tens of thousands of times.
 */
public inherited sharing class TEKCO_AnonymizationConfigSelector {

    // Statics reset per transaction, so each chunk pays each query once instead of per call.
    private static Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByDevNamesCache =
        new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();
    private static Map<String, TEKCO_AnonymizationPattern__mdt> patternMapCache;
    private static Map<String, String> configuredObjectsCache;

    /** Active field configs for one object. */
    public static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigs(String objectApiName) {
        return [
            SELECT DeveloperName, TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c,
                   TEKCO_PatternType__c, TEKCO_IsActive__c,
                   TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_ObjectApiName__c = :objectApiName AND TEKCO_IsActive__c = true
        ];
    }

    /**
     * Field configs by developer name. This is the hot path: the chain carries only developer
     * names across chunks and reloads the rows here on every execute().
     */
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

    /** Active patterns, keyed by developer name — the dispatch key the pattern service reads. */
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

    /**
     * Canonical object API names the tool is configured for, keyed lowercase.
     * TEKCO_AnonymizationGuard uses this to reject anything else before it reaches dynamic SOQL.
     */
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

    /**
     * The identity of one field configuration: its DeveloperName.
     *
     * The key travels to the LWC on the field DTO, comes back as excludedFields /
     * disabledHistoryFields, and is compared here to decide what to skip. The client never
     * builds it — it echoes back what the server sent — so there is no format for the two sides
     * to disagree about.
     *
     * IT USED TO BE Object.Field.RecordType, built independently on each side. Two problems,
     * both real: the format was a hand-kept contract whose breach was silent (untick a field,
     * see it excluded, watch the run anonymize it anyway), and it COLLIDED. Address.Street is
     * carried by two configs that differ only by their additional filter, so both produced
     * `Address.Street.` and unticking either unticked both. A DeveloperName is unique by
     * construction and cannot collide.
     */
    public static String configKey(TEKCO_AnonymizationFieldConfig__mdt config) {
        if (config == null) return '';
        return config.DeveloperName;
    }

    /**
     * Developer names of a config list, so callers keep lightweight strings in stateful batch
     * fields instead of full SObjects.
     */
    public static List<String> toDevNames(List<TEKCO_AnonymizationFieldConfig__mdt> configs) {
        List<String> names = new List<String>();
        if (configs == null) return names;
        for (TEKCO_AnonymizationFieldConfig__mdt c : configs) {
            if (String.isNotBlank(c.DeveloperName)) names.add(c.DeveloperName);
        }
        return names;
    }
}
