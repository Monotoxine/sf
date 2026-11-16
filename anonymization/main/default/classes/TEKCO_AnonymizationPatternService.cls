/**
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
public inherited sharing class TEKCO_AnonymizationPatternService {

    public static final String LOREM_TEXT =
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' +
        'Morbi diam diam, vestibulum non aliquam in, dictum quis eros.';

    private static final Integer ADDRESS_RANDOM_MAX    = 20;
    private static final Integer SSN_DEFAULT_LENGTH    = 15;

    private static final System.Pattern EXTERNAL_ID_FORMAT =
        System.Pattern.compile('^[a-zA-Z0-9_\\-]+$');

    private static final System.Pattern LEADING_NUMBER =
        System.Pattern.compile('(\\d+)');

    private static Map<String, System.Pattern> compiledPatterns =
        new Map<String, System.Pattern>();

    private static Map<Integer, String> ssnSequenceByLength = new Map<Integer, String>();

    private static System.Pattern compiled(String regex) {
        System.Pattern result = compiledPatterns.get(regex);
        if (result == null) {
            result = System.Pattern.compile(regex);
            compiledPatterns.put(regex, result);
        }
        return result;
    }

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
            when 'KEEP' {
                return currentValue;
            }
            when 'DELETE_CONTENT_DOCUMENT' {
                return null; // handled by TEKCO_ContentDocumentBatch
            }
            when 'EMAIL_MESSAGE_LOREM' {
                return null; // handled by TEKCO_AnonymizationFieldBatch
            }
            when else {
                return applyRegex(currentValue, pattern);
            }
        }
    }

    /** NAME_FIRST_LETTER: first letter + external ID, functional ID or Salesforce Id. */
    private static String applyNameFirstLetter(
        String currentValue,
        SObject record,
        TEKCO_AnonymizationPattern__mdt pattern
    ) {
        if (String.isBlank(currentValue)) return currentValue;
        String firstLetter = currentValue.substring(0, 1).toUpperCase();
        return firstLetter + resolveNameIdentifier(record, pattern);
    }

    /** Identifier for NAME_FIRST_LETTER: external ID, then functional ID, then Salesforce Id. */
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

    /** EMAIL_PLUS_EXTERNALID(_SUBDOMAIN): inserts the external ID as a plus-alias. */
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
            return localPart + '+' + externalId + domain + '.' + orgSuffix();
        }
        return localPart + '+' + externalId + domain;
    }

    private static String cachedOrgSuffix;

    private static String orgSuffix() {
        if (cachedOrgSuffix == null) cachedOrgSuffix = parseOrgSuffix(orgSubdomain);
        return cachedOrgSuffix;
    }

    /** Parses the org subdomain into a short "country.sandbox" suffix. */
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

    /** SSN_SEQUENTIAL: digits cycling 1–9, same length as the original value. */
    private static String applySsnSequential(String currentValue, TEKCO_AnonymizationPattern__mdt pattern) {
        Integer targetLength = String.isNotBlank(currentValue)
            ? currentValue.trim().length()
            : (pattern.TEKCO_SsnLength__c != null
                ? Integer.valueOf(pattern.TEKCO_SsnLength__c)
                : SSN_DEFAULT_LENGTH);
        String cached = ssnSequenceByLength.get(targetLength);
        if (cached != null) return cached;

        List<String> digits = new List<String>();
        for (Integer index = 0; index < targetLength; index++) {
            digits.add(String.valueOf(Math.mod(index, 9) + 1));
        }
        String result = String.join(digits, '');
        ssnSequenceByLength.put(targetLength, result);
        return result;
    }

    /** REGEX: configurable find/replace; the value is unchanged if the regex is invalid. */
    private static String applyRegex(String currentValue, TEKCO_AnonymizationPattern__mdt pattern) {
        String replacement = pattern.TEKCO_RegexReplace__c != null ? pattern.TEKCO_RegexReplace__c : '';
        if (String.isBlank(pattern.TEKCO_RegexFind__c) && String.isBlank(replacement)) {
            return currentValue;
        }
        if (String.isBlank(pattern.TEKCO_RegexFind__c)) {
            return replacement;
        }
        try {
            return compiled(pattern.TEKCO_RegexFind__c).matcher(currentValue).replaceAll(replacement);
        } catch (Exception e) {
            return currentValue;
        }
    }

    /** ADDRESS_STREET_RANDOM: adds 1 to 20 to the first number in the value. */
    private static String applyAddressStreetRandom(String currentValue) {
        if (String.isBlank(currentValue)) return currentValue;
        Matcher numMatcher = LEADING_NUMBER.matcher(currentValue);
        if (!numMatcher.find()) return currentValue;
        Integer streetNumber;
        try {
            streetNumber = Integer.valueOf(numMatcher.group(1));
        } catch (Exception e) {
            return currentValue;
        }
        Integer randomOffset = Integer.valueOf(Math.random() * ADDRESS_RANDOM_MAX) + 1;
        return currentValue.substring(0, numMatcher.start())
            + String.valueOf(streetNumber + randomOffset)
            + currentValue.substring(numMatcher.end());
    }

    private static final String SFID_FIELD = 'Id';

    /** External ID from the pattern's field, then from the org config's external ID fields. */
    private static String getExternalId(SObject record, TEKCO_AnonymizationPattern__mdt pattern) {
        if (record == null) return '';
        String declared = pattern.TEKCO_ExternalIdField__c;

        String fromPattern = readExternalId(record, declared);
        if (String.isNotBlank(fromPattern)) return fromPattern;

        if (String.isBlank(declared) || SFID_FIELD.equalsIgnoreCase(declared)) return '';

        for (String fieldName : TEKCO_AnonymizationOrgConfigService.getExternalIdFieldsOn(
                                    String.valueOf(record.getSObjectType()))) {
            String fromOrgConfig = readExternalId(record, fieldName);
            if (String.isNotBlank(fromOrgConfig)) return fromOrgConfig;
        }
        return '';
    }

    /** Reads one candidate external ID field; returns '' when blank or unsafe. */
    private static String readExternalId(SObject record, String fieldApiName) {
        if (String.isBlank(fieldApiName)) return '';
        try {
            Object fieldValue = record.get(fieldApiName);
            if (fieldValue == null) return '';
            String externalId = String.valueOf(fieldValue);
            if (!EXTERNAL_ID_FORMAT.matcher(externalId).matches()) return '';
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