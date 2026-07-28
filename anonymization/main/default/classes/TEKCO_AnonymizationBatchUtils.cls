/**
 * @description Shared utilities for the anonymization batch chain.
 *              Eliminates duplication of history-object helpers, popConfigsForObject,
 *              toDevNames, and cap across the batch classes and their By-ID mirrors.
 */
public inherited sharing class TEKCO_AnonymizationBatchUtils {

    private static final Integer MAX_ERROR_MSG_LENGTH = 200;
    private static final String  ANONYMIZE_PERMISSION = 'TEKCO_AnonymizeData';

    /**
     * Gate for every @AuraEnabled entry point. The anonymization UI reads and destroys PII
     * across arbitrary objects, so read-only endpoints are gated too — not just the ones
     * that launch a batch.
     */
    public static void assertCanAnonymize() {
        if (!FeatureManagement.checkPermission(ANONYMIZE_PERMISSION)) {
            throw new AuraHandledException(
                'Permission denied: the "TEKCO Anonymize Data" custom permission is required.'
            );
        }
    }

    /**
     * Object API names reaching dynamic SOQL must be one the tool is configured for.
     * Client-supplied names are otherwise concatenated straight into a query.
     * Returns the canonical configured name, or throws.
     */
    private static Map<String, String> configuredObjectsByLower;

    public static String requireConfiguredObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required.');
        }
        if (configuredObjectsByLower == null) {
            configuredObjectsByLower = new Map<String, String>();
            for (TEKCO_AnonymizationFieldConfig__mdt fc : [
                SELECT TEKCO_ObjectApiName__c
                FROM TEKCO_AnonymizationFieldConfig__mdt
                WHERE TEKCO_IsActive__c = true AND TEKCO_ObjectApiName__c != null
            ]) {
                configuredObjectsByLower.put(
                    fc.TEKCO_ObjectApiName__c.toLowerCase(), fc.TEKCO_ObjectApiName__c
                );
            }
        }
        String canonical = configuredObjectsByLower.get(objectApiName.toLowerCase());
        if (canonical == null) {
            throw new AuraHandledException(
                'Object is not configured for anonymization: ' + objectApiName
            );
        }
        return canonical;
    }

    /**
     * Field API names reaching dynamic SOQL must exist on the object.
     * Returns the supplied name when valid, otherwise throws.
     */
    public static String requireFieldOnObject(String objectApiName, String fieldApiName) {
        if (String.isBlank(fieldApiName)) {
            throw new AuraHandledException('Field API name is required.');
        }
        if (!TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, fieldApiName)) {
            throw new AuraHandledException(
                'Field does not exist on ' + objectApiName + ': ' + fieldApiName
            );
        }
        return fieldApiName;
    }

    /**
     * Field configs whose TEKCO_PatternType__c has no matching active
     * TEKCO_AnonymizationPattern__mdt are skipped silently by
     * TEKCO_AnonymizationExecuteService (the `pattern == null` continue) — the field is
     * never anonymized and nothing reports it. Surfaced at launch instead, as warnings
     * seeded into the audit log so the run still processes the valid configs.
     *
     * DELETE_CONTENT_DOCUMENT and EMAIL_MESSAGE_LOREM are handled by dedicated batches and
     * need no pattern record.
     */
    public static List<String> validatePatternTypes(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        List<String> warnings = new List<String>();
        if (configs == null || configs.isEmpty()) return warnings;

        Set<String> handledElsewhere = new Set<String>{
            'DELETE_CONTENT_DOCUMENT', 'EMAIL_MESSAGE_LOREM'
        };
        Map<String, TEKCO_AnonymizationPattern__mdt> active = buildPatternMap();

        Set<String> reported = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            String patternType = fc.TEKCO_PatternType__c;
            if (String.isBlank(patternType) || handledElsewhere.contains(patternType)) continue;
            if (active.containsKey(patternType)) continue;
            if (!reported.add(patternType)) continue;
            warnings.add(cap(
                'Config warning: pattern type "' + patternType + '" has no active '
                + 'TEKCO_AnonymizationPattern__mdt record. Fields using it will be left unchanged '
                + '(e.g. ' + fc.TEKCO_ObjectApiName__c + '.' + fc.TEKCO_FieldApiName__c + ').'
            ));
        }
        return warnings;
    }

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

    /**
     * Sandbox guard for batch start(). assertIsSandbox() throwing out of start() would abort the
     * job with the audit log stuck on "Running" and every bypass flag left enabled for the running
     * user. Returns false when the guard trips, having already closed the log and restored bypass.
     */
    public static Boolean assertSandboxOrClose(
        Id auditLogId,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot
    ) {
        try {
            TEKCO_AnonymizationOrgConfigService.assertIsSandbox();
            return true;
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Bypass restore failed; flags may remain enabled: ' + ex.getMessage());
            }
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, 0, 0, 0, 0, new List<String>(), e.getMessage()
            );
            return false;
        }
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
