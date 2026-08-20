/**
 * @description Everything the tool refuses, in one place.
 *
 *              Five gates, all of them the last line of defence for an admin tool that reads and
 *              destroys PII across arbitrary objects:
 *                - the custom permission, checked on every @AuraEnabled entry point
 *                - object and field names, before they are concatenated into dynamic SOQL
 *                - pattern types that resolve to nothing, surfaced at launch instead of silently
 *                  skipping fields at execute() time
 *                - the sandbox check, in the form a batch start() can survive
 *
 *              Split out of the former TEKCO_AnonymizationBatchUtils. Its name said "batch", but
 *              these gates are called mostly from the controllers — which is precisely how a
 *              grab-bag hides what it does.
 */
public inherited sharing class TEKCO_AnonymizationGuard {

    private static final String ANONYMIZE_PERMISSION = 'TEKCO_AnonymizeData';

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
     *
     * Note this validates against the configuration, not against the org's schema: an object
     * configured but absent from this org still passes here, and the batches guard that
     * separately with TEKCO_AnonymizationOrgConfigService.hasObject().
     */
    public static String requireConfiguredObject(String objectApiName) {
        if (String.isBlank(objectApiName)) {
            throw new AuraHandledException('Object API name is required.');
        }
        String canonical =
            TEKCO_AnonymizationConfigSelector.configuredObjectsByLower().get(objectApiName.toLowerCase());
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
        Map<String, TEKCO_AnonymizationPattern__mdt> active =
            TEKCO_AnonymizationConfigSelector.buildPatternMap();

        Set<String> reported = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            String patternType = fc.TEKCO_PatternType__c;
            if (String.isBlank(patternType) || handledElsewhere.contains(patternType)) continue;
            if (active.containsKey(patternType)) continue;
            if (!reported.add(patternType)) continue;
            warnings.add(TEKCO_AnonymizationRunContext.cap(
                'Config warning: pattern type "' + patternType + '" has no active '
                + 'TEKCO_AnonymizationPattern__mdt record. Fields using it will be left unchanged '
                + '(e.g. ' + fc.TEKCO_ObjectApiName__c + '.' + fc.TEKCO_FieldApiName__c + ').'
            ));
        }
        return warnings;
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
                System.debug(
                    LoggingLevel.ERROR,
                    'Bypass restore failed; flags may remain enabled: ' + ex.getMessage()
                );
            }
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, 0, 0, 0, 0, new List<String>(), e.getMessage()
            );
            return false;
        }
    }
}
