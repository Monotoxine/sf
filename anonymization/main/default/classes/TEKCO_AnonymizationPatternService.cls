/**
 * @author TEKCO Team, 07/04/2026
 * @description Applies anonymization patterns defined in TEKCO_AnonymizationPattern__mdt.
 *              Routes to the correct algorithm based on the pattern type.
 *
 * Pattern types:
 *   NAME_FIRST_LETTER               - First letter + ExternalId
 *   PHONE_MASK                      - First 4 chars + zeros
 *   EMAIL_PLUS_EXTERNALID           - base+ExternalId@domain
 *   EMAIL_PLUS_EXTERNALID_SUBDOMAIN - base+ExternalId@domain.country.sandbox
 *   SSN_SEQUENTIAL                  - Sequential digits to configured length
 *   LOREM_IPSUM                     - Fixed lorem ipsum text
 *   ADDRESS_STREET_RANDOM           - Street number + random 1-20
 *   DELETE_CONTENT_DOCUMENT         - Handled by dedicated batch (skip here)
 *   EMAIL_MESSAGE_LOREM             - Draft → lorem ipsum on the field; non-Draft → record deleted (handled in batch)
 */
public class TEKCO_AnonymizationPatternService {

    public static final String LOREM_TEXT =
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' +
        'Morbi diam diam, vestibulum non aliquam in, dictum quis eros.';

    private static final String PATTERN_ANON_FALLBACK = 'ANON';
    private static final Integer PHONE_MASK_KEEP_CHARS = 4;
    private static final Integer ADDRESS_RANDOM_MAX    = 20;
    private static final Integer SSN_DEFAULT_LENGTH    = 15;

    // Cached org subdomain — computed once per transaction
    private static String orgSubdomain {
        get {
            if (orgSubdomain == null) {
                try {
                    String host = URL.getOrgDomainUrl().getHost();
                    orgSubdomain = host.substringBefore('.');
                } catch (Exception e) {
                    orgSubdomain = 'sandbox';
                }
            }
            return orgSubdomain;
        }
        set;
    }

    /**
     * @description Main dispatcher — routes to the correct anonymization algorithm.
     *              Returns null for special patterns (DELETE_CONTENT_DOCUMENT, EMAIL_MESSAGE_LOREM)
     *              which are handled by their own batch classes.
     * @param patternType  DeveloperName of the TEKCO_AnonymizationPattern__mdt record.
     * @param currentValue Current field value (null-safe).
     * @param record       SObject being processed (used to read ExternalId).
     * @param pattern      The TEKCO_AnonymizationPattern__mdt configuration record.
     * @return             Anonymized value, or null to signal that this field should be skipped.
     */
    public static String applyPattern(
        String patternType,
        String currentValue,
        SObject record,
        TEKCO_AnonymizationPattern__mdt pattern
    ) {
        if (String.isBlank(patternType)) return currentValue;
        // Never anonymize an empty field — keep it as-is
        if (String.isBlank(currentValue)) return currentValue;

        switch on patternType {
            when 'NAME_FIRST_LETTER' {
                return applyNameFirstLetter(currentValue, record, pattern);
            }
            when 'PHONE_MASK' {
                return applyPhoneMask(currentValue);
            }
            when 'EMAIL_PLUS_EXTERNALID' {
                return applyEmailPlusExternalId(currentValue, record, pattern, false);
            }
            when 'EMAIL_PLUS_EXTERNALID_SUBDOMAIN' {
                return applyEmailPlusExternalId(currentValue, record, pattern, true);
            }
            when 'SSN_SEQUENTIAL' {
                return applySsnSequential(currentValue, pattern);
            }
            when 'LOREM_IPSUM' {
                return LOREM_TEXT;
            }
            when 'ADDRESS_STREET_RANDOM' {
                return applyAddressStreetRandom(currentValue);
            }
            when 'DELETE_CONTENT_DOCUMENT' {
                return null; // handled by TEKCO_ContentDocumentBatch
            }
            when 'EMAIL_MESSAGE_LOREM' {
                return null; // handled directly in TEKCO_AnonymizationBatch (Draft→update, else→delete)
            }
            when else {
                return currentValue;
            }
        }
    }

    // ── Pattern Implementations ───────────────────────────────────────────────

    /**
     * @description NAME_FIRST_LETTER: first letter of value concatenated with the ExternalId value.
     *              Example: "Jean" + "EXT001" → "JEXT001"
     * @param currentValue Current field value.
     * @param record       SObject being processed.
     * @param pattern      Pattern configuration record.
     * @return             Anonymized value.
     */
    private static String applyNameFirstLetter(
        String currentValue,
        SObject record,
        TEKCO_AnonymizationPattern__mdt pattern
    ) {
        if (String.isBlank(currentValue)) return currentValue;
        String firstLetter = currentValue.substring(0, 1).toUpperCase();
        String externalId = getExternalId(record, pattern);
        return firstLetter + (String.isBlank(externalId) ? PATTERN_ANON_FALLBACK : externalId);
    }

    /**
     * @description PHONE_MASK: keeps the first 4 characters and replaces the rest with zeros.
     *              Example: "+33123456789" → "+33100000000"
     * @param currentValue Current field value.
     * @return             Masked phone number.
     */
    private static String applyPhoneMask(String currentValue) {
        if (String.isBlank(currentValue)) return currentValue;
        String cleanedValue = currentValue.trim();
        Integer totalLength = cleanedValue.length();
        if (totalLength <= PHONE_MASK_KEEP_CHARS) return cleanedValue;
        return cleanedValue.substring(0, PHONE_MASK_KEEP_CHARS)
            + '0'.repeat(totalLength - PHONE_MASK_KEEP_CHARS);
    }

    /**
     * @description EMAIL_PLUS_EXTERNALID / EMAIL_PLUS_EXTERNALID_SUBDOMAIN:
     *              Inserts ExternalId as a plus-alias. The SUBDOMAIN variant also appends
     *              a org-derived suffix after the domain.
     *              Example: "sf_sap@airliquide.com" + "EXT001" → "sf_sap+EXT001@airliquide.com"
     *              With subdomain (org = "airliquidehhc-fr--mmedlej.sandbox.my.salesforce.com"):
     *                → "sf_sap+EXT001@airliquide.com.fr.mmedlej"
     * @param currentValue    Current field value.
     * @param record          SObject being processed.
     * @param pattern         Pattern configuration record.
     * @param appendSubdomain Whether to append the org-derived domain suffix.
     * @return                Anonymized email address.
     */
    private static String applyEmailPlusExternalId(
        String currentValue,
        SObject record,
        TEKCO_AnonymizationPattern__mdt pattern,
        Boolean appendSubdomain
    ) {
        String externalId = getExternalId(record, pattern);
        if (String.isBlank(externalId)) externalId = PATTERN_ANON_FALLBACK;

        String baseEmail = String.isNotBlank(pattern.TEKCO_BaseEmail__c)
            ? pattern.TEKCO_BaseEmail__c
            : currentValue;

        if (String.isBlank(baseEmail)) return currentValue;

        Integer atIndex = baseEmail.indexOf('@');
        if (atIndex < 0) return currentValue;

        String localPart = baseEmail.substring(0, atIndex);
        String domain    = baseEmail.substring(atIndex);

        if (appendSubdomain) {
            return localPart + '+' + externalId + domain + '.' + parseOrgSuffix(orgSubdomain);
        }
        return localPart + '+' + externalId + domain;
    }

    /**
     * @description Parses the org subdomain into a short "country.sandbox" suffix.
     *              "airliquidehhc-fr--mmedlej" → "fr.mmedlej"
     *              Falls back to the raw subdomain if the expected format is not found.
     */
    private static String parseOrgSuffix(String subdomain) {
        if (String.isBlank(subdomain)) return subdomain;
        if (subdomain.contains('--')) {
            String[] parts    = subdomain.split('--');
            String sandboxName = parts[1];
            String orgPart     = parts[0];
            String country     = orgPart.contains('-')
                ? orgPart.substringAfterLast('-')
                : orgPart;
            return country + '.' + sandboxName;
        }
        return subdomain;
    }

    /**
     * @description SSN_SEQUENTIAL: generates sequential digits cycling 1–9.
     *              Length is taken from the actual value so the anonymized SSN is the same
     *              length as the original. Falls back to TEKCO_SsnLength__c, then to the
     *              default constant, so the field is never left blank.
     *              Example: "1234567890123" (13 chars) → "1234567891234" (13 chars)
     * @param currentValue Current field value (already guaranteed non-blank by the caller).
     * @param pattern      Pattern configuration record containing TEKCO_SsnLength__c.
     * @return             Sequential SSN string of the same length as the original.
     */
    private static String applySsnSequential(String currentValue, TEKCO_AnonymizationPattern__mdt pattern) {
        Integer targetLength = String.isNotBlank(currentValue)
            ? currentValue.trim().length()
            : (pattern.TEKCO_SsnLength__c != null
                ? Integer.valueOf(pattern.TEKCO_SsnLength__c)
                : SSN_DEFAULT_LENGTH);
        String result = '';
        for (Integer index = 0; index < targetLength; index++) {
            result += String.valueOf(Math.mod(index, 9) + 1);
        }
        return result;
    }

    /**
     * @description ADDRESS_STREET_RANDOM: finds the first numeric sequence anywhere in the string
     *              and adds a random value between 1 and 20 to it.
     *              Example: "123 Rue de la Paix"  → "137 Rue de la Paix"
     *              Example: "Allée 12 des Fleurs" → "Allée 26 des Fleurs"
     *              If no number is found, returns value unchanged.
     * @param currentValue Current field value.
     * @return             Address with the street number offset by a random amount.
     */
    private static String applyAddressStreetRandom(String currentValue) {
        if (String.isBlank(currentValue)) return currentValue;
        Matcher numMatcher = Pattern.compile('(\\d+)').matcher(currentValue);
        if (!numMatcher.find()) return currentValue;
        Integer streetNumber = Integer.valueOf(numMatcher.group(1));
        Integer randomOffset = Integer.valueOf(Math.random() * ADDRESS_RANDOM_MAX) + 1;
        return currentValue.replaceFirst('\\d+', String.valueOf(streetNumber + randomOffset));
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * @description Reads the external ID field value from the record as configured in the pattern.
     * @param record  SObject being processed.
     * @param pattern Pattern configuration record containing TEKCO_ExternalIdField__c.
     * @return        External ID value as String, or empty string if unavailable.
     */
    private static String getExternalId(SObject record, TEKCO_AnonymizationPattern__mdt pattern) {
        if (record == null || String.isBlank(pattern.TEKCO_ExternalIdField__c)) return '';
        try {
            Object fieldValue = record.get(pattern.TEKCO_ExternalIdField__c);
            return fieldValue != null ? String.valueOf(fieldValue) : '';
        } catch (Exception e) {
            return '';
        }
    }
}
