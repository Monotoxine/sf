/**
 * @description Anonymization pattern service for patterns based on the Salesforce Record ID
 *              instead of an external identifier (SAP ID, etc.).
 *
 * Contains three patterns grouped in one service class. Each is a public inner class
 * implementing IAnonymizationStrategy so it can be referenced directly in
 * Anon_Field_Config__mdt.Strategy_Class_Name__c using dot notation:
 *
 *   TEKCO_AnonymizationPatternService.NameFirstLetterSfId
 *   TEKCO_AnonymizationPatternService.EmailPlusSfId
 *   TEKCO_AnonymizationPatternService.EmailPlusSfIdSubdomain
 *
 * ─── Why Salesforce ID instead of External ID? ────────────────────────────────
 * External IDs (e.g. SAP_External_ID__c) may be null when records have not been
 * synchronised with an external system. The Salesforce Record ID (record.Id) is
 * always present and unique, making it a safe fallback identifier for deterministic
 * anonymization output.
 *
 * @author  Data Anonymization System — TEKCO patterns
 * @since   API v65.0
 */
public without sharing class TEKCO_AnonymizationPatternService {

    // ── NAME_FIRST_LETTER_SFID ────────────────────────────────────────────────

    /**
     * @description Pattern: NAME_FIRST_LETTER_SFID
     *
     * Replaces a name field with its first letter followed by the Salesforce Record ID.
     * Mirrors AnonymizeFirstLetterPlusExternalId but uses record.Id instead of an
     * external identifier, so it works even when no SAP / external ID is populated.
     *
     * Output format:  {FirstLetter}{SalesforceRecordId}
     *
     * Examples:
     *   FirstName "Jean-Pierre", record.Id "001Qy000003ABCDEF" → "J001Qy000003ABCDEF"
     *   LastName  "Dupont",      record.Id "001Qy000003ABCDEF" → "D001Qy000003ABCDEF"
     *
     * Metadata config:
     *   Strategy_Class_Name__c  TEKCO_AnonymizationPatternService.NameFirstLetterSfId
     *   Strategy_Param_1__c     (unused)
     *   Strategy_Param_2__c     (unused)
     *
     * Edge cases:
     *   - Null/empty field value → first letter placeholder is 'X'.
     *   - Null record Id (should never happen in practice) → returns first letter alone.
     */
    public class NameFirstLetterSfId implements IAnonymizationStrategy {

        public String anonymize(AnonymizationContext ctx) {
            String val    = ctx.getCurrentValue();
            String sfId   = ctx.record.Id != null ? String.valueOf(ctx.record.Id) : null;

            String firstLetter = String.isNotBlank(val) ? val.substring(0, 1).toUpperCase() : 'X';
            return firstLetter + (String.isNotBlank(sfId) ? sfId : '');
        }
    }

    // ── EMAIL_PLUS_SFID ───────────────────────────────────────────────────────

    /**
     * @description Pattern: EMAIL_PLUS_SFID
     *
     * Replaces an email address with a deterministic generic address built from
     * the Salesforce Record ID. Mirrors AnonymizeEmailGeneric but uses record.Id
     * instead of an external identifier.
     *
     * Output format:  {param2}+{SalesforceRecordId}@{param1}
     *
     * Examples (configured via metadata params):
     *   param1 = "airliquide.com", param2 = "sf_sap", record.Id = "001Qy000003ABCDEF"
     *   → "sf_sap+001Qy000003ABCDEF@airliquide.com"
     *
     * Metadata config:
     *   Strategy_Class_Name__c  TEKCO_AnonymizationPatternService.EmailPlusSfId
     *   Strategy_Param_1__c     Email domain (required). Example: "airliquide.com"
     *   Strategy_Param_2__c     Email prefix (optional, defaults to "anon"). Example: "sf_sap"
     *
     * Edge cases:
     *   - Missing param1   → falls back to "example.com".
     *   - Null record Id   → uses "unknown" to produce a valid non-null address.
     */
    public class EmailPlusSfId implements IAnonymizationStrategy {

        private static final String DEFAULT_DOMAIN = 'example.com';
        private static final String DEFAULT_PREFIX  = 'anon';

        public String anonymize(AnonymizationContext ctx) {
            String domain = String.isNotBlank(ctx.param1) ? ctx.param1 : DEFAULT_DOMAIN;
            String prefix = String.isNotBlank(ctx.param2) ? ctx.param2 : DEFAULT_PREFIX;
            String sfId   = ctx.record.Id != null ? String.valueOf(ctx.record.Id) : 'unknown';

            return prefix + '+' + sfId + '@' + domain;
        }
    }

    // ── EMAIL_PLUS_SFID_SUBDOMAIN ─────────────────────────────────────────────

    /**
     * @description Pattern: EMAIL_PLUS_SFID_SUBDOMAIN
     *
     * Variant of EMAIL_PLUS_SFID where the email domain is prefixed with a subdomain
     * derived from the Salesforce Record ID prefix (first 3 chars = object key prefix).
     * Useful to visually distinguish emails by object type in test data.
     *
     * Output format:  {param2}+{SalesforceRecordId}@{IdPrefix}.{param1}
     *
     * Examples:
     *   param1 = "airliquide.com", param2 = "sf_sap", record.Id = "001Qy000003ABCDEF"
     *   → "sf_sap+001Qy000003ABCDEF@001.airliquide.com"
     *
     *   With param3 override via param1 = "sandbox.airliquide.com" (full subdomain already):
     *   Admins who prefer a fixed subdomain can set param1 directly to the full domain
     *   including subdomain (e.g. "sandbox.airliquide.com") and use EmailPlusSfId instead.
     *
     * Metadata config:
     *   Strategy_Class_Name__c  TEKCO_AnonymizationPatternService.EmailPlusSfIdSubdomain
     *   Strategy_Param_1__c     Root domain (required). Example: "airliquide.com"
     *                           The object key prefix is prepended automatically.
     *   Strategy_Param_2__c     Email prefix (optional, defaults to "anon"). Example: "sf_sap"
     *
     * Edge cases:
     *   - Missing param1   → falls back to "example.com".
     *   - Null record Id   → subdomain becomes "xxx", address is still valid.
     */
    public class EmailPlusSfIdSubdomain implements IAnonymizationStrategy {

        private static final String DEFAULT_DOMAIN = 'example.com';
        private static final String DEFAULT_PREFIX  = 'anon';

        public String anonymize(AnonymizationContext ctx) {
            String domain = String.isNotBlank(ctx.param1) ? ctx.param1 : DEFAULT_DOMAIN;
            String prefix = String.isNotBlank(ctx.param2) ? ctx.param2 : DEFAULT_PREFIX;
            String sfId   = ctx.record.Id != null ? String.valueOf(ctx.record.Id) : 'xxx000000000000000';

            // Extract Salesforce object key prefix (first 3 characters of the 18-char ID)
            String objectKeyPrefix = sfId.length() >= 3 ? sfId.substring(0, 3) : 'xxx';

            return prefix + '+' + sfId + '@' + objectKeyPrefix + '.' + domain;
        }
    }
}
