/**
 * AnonymizationPatternService
 * Applies anonymization patterns defined in TEKCO_AnonymizationPattern__mdt.
 *
 * Pattern types:
 *   NAME_FIRST_LETTER              - First letter + ExternalId
 *   PHONE_MASK                     - First 4 chars + zeros
 *   EMAIL_PLUS_EXTERNALID          - base+ExternalId@domain
 *   EMAIL_PLUS_EXTERNALID_SUBDOMAIN- base+ExternalId+orgSubdomain@domain
 *   SSN_SEQUENTIAL                 - Sequential digits to configured length
 *   LOREM_IPSUM                    - Fixed lorem ipsum text
 *   KEEP                           - No change
 *   ADDRESS_STREET_RANDOM          - Street number + random 1-20
 *   DELETE_CONTENT_DOCUMENT        - Handled by dedicated batch (skip here)
 *   EMAIL_MESSAGE_LOREM            - Handled by dedicated batch (skip here)
 */
public class AnonymizationPatternService {

    public static final String LOREM_TEXT =
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' +
        'Morbi diam diam, vestibulum non aliquam in, dictum quis eros.';

    // Cached org subdomain — computed once per transaction
    private static String orgSubdomain {
        get {
            if (orgSubdomain == null) {
                try {
                    String host = URL.getOrgDomainUrl().getHost();
                    // host is like "mycompany--uat1.sandbox.my.salesforce.com"
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
     * Main dispatcher — routes to the correct algorithm.
     * Returns null for special patterns (DELETE_CONTENT_DOCUMENT, EMAIL_MESSAGE_LOREM)
     * which are handled by their own batch classes.
     *
     * @param patternType  DeveloperName of TEKCO_AnonymizationPattern__mdt record
     * @param currentValue Current field value (String, null-safe)
     * @param record       SObject being processed (to read ExternalId)
     * @param pattern      The TEKCO_AnonymizationPattern__mdt config
     * @return             Anonymized value, or null to skip this field
     */
    public static String applyPattern(
        String patternType,
        String currentValue,
        SObject record,
        TEKCO_AnonymizationPattern__mdt pattern
    ) {
        if (String.isBlank(patternType)) return currentValue;

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
                return applySsnSequential(pattern);
            }
            when 'LOREM_IPSUM' {
                return LOREM_TEXT;
            }
            when 'ADDRESS_STREET_RANDOM' {
                return applyAddressStreetRandom(currentValue);
            }
            when 'KEEP' {
                return currentValue;
            }
            when 'DELETE_CONTENT_DOCUMENT', 'EMAIL_MESSAGE_LOREM' {
                return null; // handled by dedicated batches
            }
            when else {
                return currentValue;
            }
        }
    }

    // ── Pattern Implementations ───────────────────────────────────────────────

    /**
     * NAME_FIRST_LETTER: first letter of value + ExternalId value
     * Ex: "Jean" + "EXT001" → "JEXT001"
     */
    private static String applyNameFirstLetter(
        String currentValue,
        SObject record,
        TEKCO_AnonymizationPattern__mdt pattern
    ) {
        if (String.isBlank(currentValue)) return currentValue;
        String firstLetter = currentValue.substring(0, 1).toUpperCase();
        String extId = getExternalId(record, pattern);
        return firstLetter + (String.isBlank(extId) ? 'ANON' : extId);
    }

    /**
     * PHONE_MASK: keep first 4 chars, replace rest with zeros
     * Ex: "+33123456789" → "+33100000000"
     */
    private static String applyPhoneMask(String currentValue) {
        if (String.isBlank(currentValue)) return currentValue;
        String cleaned = currentValue.trim();
        Integer total = cleaned.length();
        if (total <= 4) return cleaned;
        return cleaned.substring(0, 4) + '0'.repeat(total - 4);
    }

    /**
     * EMAIL_PLUS_EXTERNALID / EMAIL_PLUS_EXTERNALID_SUBDOMAIN
     * Ex: "sf_sap@airliquide.com" + "EXT001" → "sf_sap+EXT001@airliquide.com"
     * With subdomain: "sf_sap+EXT001+myorg--uat1@airliquide.com"
     */
    private static String applyEmailPlusExternalId(
        String currentValue,
        SObject record,
        TEKCO_AnonymizationPattern__mdt pattern,
        Boolean appendSubdomain
    ) {
        String extId = getExternalId(record, pattern);
        if (String.isBlank(extId)) extId = 'ANON';

        String baseEmail = String.isNotBlank(pattern.Base_Email__c)
            ? pattern.Base_Email__c
            : currentValue;

        if (String.isBlank(baseEmail)) return currentValue;

        Integer atIdx = baseEmail.indexOf('@');
        if (atIdx < 0) return currentValue;

        String localPart = baseEmail.substring(0, atIdx);
        String domain    = baseEmail.substring(atIdx);

        String alias = appendSubdomain
            ? localPart + '+' + extId + '+' + orgSubdomain + domain
            : localPart + '+' + extId + domain;

        return alias;
    }

    /**
     * SSN_SEQUENTIAL: sequential digits cycling 1-9 to configured length
     * Ex: length 13 → "1234567891234"
     */
    private static String applySsnSequential(TEKCO_AnonymizationPattern__mdt pattern) {
        Integer length = (pattern.SSN_Length__c != null)
            ? Integer.valueOf(pattern.SSN_Length__c)
            : 15;
        String result = '';
        for (Integer i = 0; i < length; i++) {
            result += String.valueOf(Math.mod(i, 9) + 1);
        }
        return result;
    }

    /**
     * ADDRESS_STREET_RANDOM: find the first number anywhere in the string, add random 1-20
     * Ex: "123 Rue de la Paix"   → "137 Rue de la Paix"
     * Ex: "Rue de la Paix 123"   → "Rue de la Paix 137"
     * Ex: "Allée 12 des Fleurs"  → "Allée 26 des Fleurs"
     * If no number found, return value unchanged.
     */
    private static String applyAddressStreetRandom(String currentValue) {
        if (String.isBlank(currentValue)) return currentValue;
        Matcher m = Pattern.compile('(\\d+)').matcher(currentValue);
        if (!m.find()) return currentValue;
        Integer streetNumber = Integer.valueOf(m.group(1));
        Integer randomAdd    = Integer.valueOf(Math.random() * 20) + 1;
        // replaceFirst replaces only the first numeric sequence found
        return currentValue.replaceFirst('\\d+', String.valueOf(streetNumber + randomAdd));
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static String getExternalId(SObject record, TEKCO_AnonymizationPattern__mdt pattern) {
        if (record == null || String.isBlank(pattern.External_Id_Field__c)) return '';
        try {
            Object val = record.get(pattern.External_Id_Field__c);
            return val != null ? String.valueOf(val) : '';
        } catch (Exception e) {
            return '';
        }
    }
}
