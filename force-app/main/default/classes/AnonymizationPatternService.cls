/**
 * AnonymizationPatternService
 * Pure static service that applies anonymization patterns to field values.
 * Each method matches a Pattern_Type__c value from Anon_Pattern__mdt.
 *
 * Patterns supported:
 *   NAME_FIRST_LETTER       - First letter of value + ExternalId
 *   PHONE_MASK              - First 4 chars + zeros to original length
 *   EMAIL_PLUS_EXTERNALID   - base+ExternalId@domain
 *   SSN_SEQUENTIAL          - Sequential digits 1234... to configured length
 *   LOREM_IPSUM             - Fixed lorem ipsum text
 *   ADDRESS_STREET_RANDOM   - Extract street number + add random 1-20
 *   KEEP                    - No change
 */
public class AnonymizationPatternService {

    public static final String LOREM_TEXT =
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' +
        'Morbi diam diam, vestibulum non aliquam in, dictum quis eros.';

    /**
     * Main dispatcher. Routes to the correct pattern method.
     *
     * @param patternType  Value of Pattern_Type__c on Anon_Pattern__mdt
     * @param currentValue Current field value as String (null-safe)
     * @param record       The SObject being processed (to read ExternalId)
     * @param pattern      The Anon_Pattern__mdt config record
     * @return             The anonymized value, or null to leave unchanged
     */
    public static String applyPattern(
        String patternType,
        String currentValue,
        SObject record,
        Anon_Pattern__mdt pattern
    ) {
        if (patternType == null) return currentValue;

        switch on patternType {
            when 'NAME_FIRST_LETTER' {
                return applyNameFirstLetter(currentValue, record, pattern);
            }
            when 'PHONE_MASK' {
                return applyPhoneMask(currentValue);
            }
            when 'EMAIL_PLUS_EXTERNALID' {
                return applyEmailPlusExternalId(currentValue, record, pattern);
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
            when else {
                return currentValue;
            }
        }
    }

    // ─── Pattern Implementations ──────────────────────────────────────────────

    /**
     * NAME_FIRST_LETTER
     * Ex: "Jean" + ExternalId "EXT001" → "JEXT001"
     */
    private static String applyNameFirstLetter(
        String currentValue,
        SObject record,
        Anon_Pattern__mdt pattern
    ) {
        if (String.isBlank(currentValue)) return currentValue;

        String firstLetter = currentValue.substring(0, 1).toUpperCase();
        String externalId = getExternalId(record, pattern);
        return firstLetter + (String.isBlank(externalId) ? 'ANON' : externalId);
    }

    /**
     * PHONE_MASK
     * Keep first 4 chars, replace the rest with zeros.
     * Ex: "+33123456789" (12 chars) → "+33100000000"
     * Ex: "+33612345678" (12 chars) → "+33600000000"
     */
    private static String applyPhoneMask(String currentValue) {
        if (String.isBlank(currentValue)) return currentValue;

        String cleaned = currentValue.trim();
        Integer totalLength = cleaned.length();
        if (totalLength <= 4) return cleaned;

        String prefix = cleaned.substring(0, 4);
        Integer zerosNeeded = totalLength - 4;
        String zeros = '0'.repeat(zerosNeeded);
        return prefix + zeros;
    }

    /**
     * EMAIL_PLUS_EXTERNALID
     * Ex: "sf_sap@airliquide.com" + ExternalId "EXT001"
     *   → "sf_sap+EXT001@airliquide.com"
     *
     * If Base_Email__c is configured, uses that as the base instead of current value.
     */
    private static String applyEmailPlusExternalId(
        String currentValue,
        SObject record,
        Anon_Pattern__mdt pattern
    ) {
        String externalId = getExternalId(record, pattern);
        if (String.isBlank(externalId)) externalId = 'ANON';

        // Use Base_Email__c if configured, else derive from current value
        String baseEmail = String.isNotBlank(pattern.Base_Email__c)
            ? pattern.Base_Email__c
            : currentValue;

        if (String.isBlank(baseEmail)) return currentValue;

        // Split base email into local and domain parts
        Integer atIndex = baseEmail.indexOf('@');
        if (atIndex < 0) return currentValue;

        String localPart = baseEmail.substring(0, atIndex);
        String domain = baseEmail.substring(atIndex); // includes @

        return localPart + '+' + externalId + domain;
    }

    /**
     * SSN_SEQUENTIAL
     * Generates "123456789012..." to SSN_Length__c digits.
     * Cycles 1-9 then repeats.
     * Ex: length 13 → "1234567891234"
     */
    private static String applySsnSequential(Anon_Pattern__mdt pattern) {
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
     * ADDRESS_STREET_RANDOM
     * Finds the leading number in the street, adds a random value between 1 and 20.
     * Ex: "123 Rue de la Paix" → "137 Rue de la Paix" (added 14)
     * If no number found, returns original value unchanged.
     */
    private static String applyAddressStreetRandom(String currentValue) {
        if (String.isBlank(currentValue)) return currentValue;

        String trimmed = currentValue.trim();

        // Extract leading number
        Integer i = 0;
        while (i < trimmed.length() && trimmed.substring(i, i + 1).isNumeric()) {
            i++;
        }

        if (i == 0) return currentValue; // No leading number found

        Integer streetNumber = Integer.valueOf(trimmed.substring(0, i));
        String remainder = trimmed.substring(i);

        // Random between 1 and 20
        Integer randomAdd = Integer.valueOf(Math.random() * 20) + 1;
        Integer newNumber = streetNumber + randomAdd;

        return String.valueOf(newNumber) + remainder;
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    /**
     * Safely reads the ExternalId from the SObject using the field name
     * configured in pattern.External_Id_Field__c.
     */
    private static String getExternalId(SObject record, Anon_Pattern__mdt pattern) {
        if (record == null || String.isBlank(pattern.External_Id_Field__c)) {
            return '';
        }
        try {
            Object val = record.get(pattern.External_Id_Field__c);
            return val != null ? String.valueOf(val) : '';
        } catch (Exception e) {
            return '';
        }
    }
}
