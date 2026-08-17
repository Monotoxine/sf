/**
 * @author
 * @description Applies anonymization patterns defined in TEKCO_AnonymizationPattern__mdt.
 *              Routes to the correct algorithm based on the pattern type.
 *
 * Pattern types:
 *   NAME_FIRST_LETTER               - First letter + ExternalId → TEKCO_FunctionalId__c → Salesforce Id
 *   NAME_FIRST_LETTER_SFID          - First letter + Salesforce record Id
 *   EMAIL_PLUS_EXTERNALID           - base+ExternalId@domain
 *   EMAIL_PLUS_EXTERNALID_SUBDOMAIN - base+ExternalId@domain.country.sandbox
 *   EMAIL_PLUS_SFID                 - base+SalesforceId@domain
 *   EMAIL_PLUS_SFID_SUBDOMAIN       - base+SalesforceId@domain.country.sandbox
 *   SSN_SEQUENTIAL                  - Sequential digits to configured length
 *   ADDRESS_STREET_RANDOM           - Street number + random 1-20
 *   KEEP                            - No-op: field value is left unchanged
 *   REGEX                           - Configurable find/replace via TEKCO_RegexFind__c / TEKCO_RegexReplace__c
 *   DELETE_CONTENT_DOCUMENT         - Handled by dedicated batch (Phase 2)
 *   EMAIL_MESSAGE_LOREM             - Draft → lorem ipsum on the field; non-Draft → record deleted (handled in batch)
 */
public class TEKCO_AnonymizationPatternService {

    public static final String LOREM_TEXT =
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' +
        'Morbi diam diam, vestibulum non aliquam in, dictum quis eros.';

    private static final Integer ADDRESS_RANDOM_MAX    = 20;
    private static final Integer SSN_DEFAULT_LENGTH    = 15;

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

    public static String applyPattern(
        String patternType,
        String currentValue,
        SObject record,
        TEKCO_AnonymizationPattern__mdt pattern
    ) {
        if (String.isBlank(patternType)) return currentValue;
        if (String.isBlank(currentValue)) return currentValue;

        switch on patternType {
            when 'NAME_FIRST_LETTER' {
                return applyNameFirstLetter(currentValue, record, pattern);
            }
            when 'NAME_FIRST_LETTER_SFID' {
                if (String.isBlank(currentValue)) return currentValue;
                return currentValue.substring(0, 1).toUpperCase() + getSalesforceId(record);
            }
            when 'EMAIL_PLUS_EXTERNALID' {
                return applyEmailPlusExternalId(currentValue, record, pattern, false);
            }
            when 'EMAIL_PLUS_EXTERNALID_SUBDOMAIN' {
                return applyEmailPlusExternalId(currentValue, record, pattern, true);
            }
            when 'EMAIL_PLUS_SFID' {
                return applyEmailPlusExternalId(currentValue, record, pattern, false);
            }
            when 'EMAIL_PLUS_SFID_SUBDOMAIN' {
                return applyEmailPlusExternalId(currentValue, record, pattern, true);
            }
            when 'SSN_SEQUENTIAL' {
                return applySsnSequential(currentValue, pattern);
            }
            when 'ADDRESS_STREET_RANDOM' {
                return applyAddressStreetRandom(currentValue);
            }
            when 'DELETE_CONTENT_DOCUMENT' {
                return null; // handled by TEKCO_ContentDocumentBatch
            }
            when 'EMAIL_MESSAGE_LOREM' {
                return null; // handled by TEKCO_AnonymizationBatch
            }
            when else {
                return applyRegex(currentValue, pattern);
            }
        }
    }

    /**
     * @description NAME_FIRST_LETTER: first letter of value concatenated with a resolved identifier.
     *              Fallback chain: ExternalId field → TEKCO_FunctionalId__c → Salesforce record Id.
     *              Example: "Jean" + "EXT001" → "JEXT001"
     */
    private static String applyNameFirstLetter(
        String currentValue,
        SObject record,
        TEKCO_AnonymizationPattern__mdt pattern
    ) {
        if (String.isBlank(currentValue)) return currentValue;
        String firstLetter = currentValue.substring(0, 1).toUpperCase();
        return firstLetter + resolveNameIdentifier(record, pattern);
    }

    /**
     * @description Resolves the identifier to append for NAME_FIRST_LETTER.
     *              1. TEKCO_ExternalIdField__c value (if configured and non-blank)
     *              2. Org-configured functional ID field (e.g. TEKCO_FunctionalId__c or ALH_FunctionalId__c)
     *              3. Salesforce record Id as last resort
     */
    private static String resolveNameIdentifier(SObject record, TEKCO_AnonymizationPattern__mdt pattern) {
        String externalId = getExternalId(record, pattern);
        if (String.isNotBlank(externalId)) return externalId;

        String functionalIdField = TEKCO_AnonymizationOrgConfigService.getConfig().functionalIdField;
        if (String.isNotBlank(functionalIdField)) {
            try {
                Object functionalId = record.get(functionalIdField);
                if (functionalId != null && String.isNotBlank(String.valueOf(functionalId))) {
                    return String.valueOf(functionalId);
                }
            } catch (Exception e) {}
        }

        return getSalesforceId(record);
    }

    /**
     * @description EMAIL_PLUS_EXTERNALID / EMAIL_PLUS_EXTERNALID_SUBDOMAIN:
     *              Inserts ExternalId as a plus-alias. The SUBDOMAIN variant also appends
     *              a org-derived suffix after the domain.
     *              Example: "sf_sap@airliquide.com" + "EXT001" → "sf_sap+EXT001@airliquide.com"
     *              With subdomain (org = "airliquidehhc-fr--mmedlej.sandbox.my.salesforce.com"):
     *                → "sf_sap+EXT001@airliquide.com.fr.mmedlej"
     */
    private static String applyEmailPlusExternalId(
        String currentValue,
        SObject record,
        TEKCO_AnonymizationPattern__mdt pattern,
        Boolean appendSubdomain
    ) {
        if (String.isBlank(currentValue)) return currentValue;

        String externalId = getExternalId(record, pattern);
        if (String.isBlank(externalId)) externalId = getSalesforceId(record);

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
     * @description REGEX: applies a configurable find/replace regex to the field value.
     *              If TEKCO_RegexFind__c is blank, replaces the entire value with TEKCO_RegexReplace__c.
     *              If the regex is invalid, returns the original value unchanged.
     */
    private static String applyRegex(String currentValue, TEKCO_AnonymizationPattern__mdt pattern) {
        String replacement = pattern.TEKCO_RegexReplace__c != null ? pattern.TEKCO_RegexReplace__c : '';
        if (String.isBlank(pattern.TEKCO_RegexFind__c) && String.isBlank(replacement)) {
            return currentValue;
        }
        if (String.isBlank(pattern.TEKCO_RegexFind__c)) {
            return replacement;
        }
        try {
            return System.Pattern.compile(pattern.TEKCO_RegexFind__c)
                                .matcher(currentValue)
                                .replaceAll(replacement);
        } catch (Exception e) {
            return currentValue;
        }
    }

       /**
     * @description ADDRESS_STREET_RANDOM: finds the first numeric sequence anywhere in the string
     *              and adds a random value between 1 and 20 to it.
     *              Example: "123 Rue de la Paix"  → "137 Rue de la Paix"
     *              Example: "Allée 12 des Fleurs" → "Allée 26 des Fleurs"
     *              If no number is found, returns value unchanged.
     */
    private static String applyAddressStreetRandom(String currentValue) {
        if (String.isBlank(currentValue)) return currentValue;
        Matcher numMatcher = Pattern.compile('(\\d+)').matcher(currentValue);
        if (!numMatcher.find()) return currentValue;
        Integer streetNumber;
        try {
            streetNumber = Integer.valueOf(numMatcher.group(1));
        } catch (Exception e) {
            return currentValue;
        }
        Integer randomOffset = Integer.valueOf(Math.random() * ADDRESS_RANDOM_MAX) + 1;
        return currentValue.replaceFirst('\\d+', String.valueOf(streetNumber + randomOffset));
    }

    private static String getExternalId(SObject record, TEKCO_AnonymizationPattern__mdt pattern) {
        if (record == null || String.isBlank(pattern.TEKCO_ExternalIdField__c)) return '';
        try {
            Object fieldValue = record.get(pattern.TEKCO_ExternalIdField__c);
            if (fieldValue == null) return '';
            String externalId = String.valueOf(fieldValue);
            // Reject base64, BOM chars, slashes, equals — anything unsafe in name or email fields.
            // Callers fall back to functional ID → Salesforce record Id when this returns ''.
            if (!System.Pattern.compile('^[a-zA-Z0-9_\\-]+$').matcher(externalId).matches()) return '';
            return externalId;
        } catch (Exception e) {
            return '';
        }
    }

    private static String getSalesforceId(SObject record) {
        if (record == null) return '';
        try {
            Object idValue = record.get('Id');
            return idValue != null ? String.valueOf(idValue) : '';
        } catch (Exception e) {
            return '';
        }
    }

}