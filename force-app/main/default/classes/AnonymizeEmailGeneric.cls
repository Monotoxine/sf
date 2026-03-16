/**
 * @description Strategy: EMAIL_GENERIC
 *
 * Replaces an email address with a deterministic generic address built from
 * the record's external ID. The output is always valid RFC 5321 syntax.
 *
 * Output format:  {param2}+{ExternalID}@{param1}
 *
 * Examples (from specification — configured via metadata params):
 *   param1 = "airliquide.com", param2 = "sf_sap", ExternalID = "12345678"
 *   → "sf_sap+12345678@airliquide.com"
 *
 * Metadata params:
 *   param1  Email domain (required). Example: "airliquide.com"
 *   param2  Email prefix (optional, defaults to "anon"). Example: "sf_sap"
 *
 * Edge cases:
 *   - Missing param1  → uses "example.com" as a safe fallback.
 *   - Missing ExternalID → uses "unknown" to produce a valid (non-null) address.
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public without sharing class AnonymizeEmailGeneric implements IAnonymizationStrategy {

    private static final String DEFAULT_DOMAIN = 'example.com';
    private static final String DEFAULT_PREFIX = 'anon';

    public String anonymize(AnonymizationContext ctx) {
        String domain  = String.isNotBlank(ctx.param1) ? ctx.param1 : DEFAULT_DOMAIN;
        String prefix  = String.isNotBlank(ctx.param2) ? ctx.param2 : DEFAULT_PREFIX;
        String extId   = String.isNotBlank(ctx.getExternalId()) ? ctx.getExternalId() : 'unknown';

        return prefix + '+' + extId + '@' + domain;
    }
}
