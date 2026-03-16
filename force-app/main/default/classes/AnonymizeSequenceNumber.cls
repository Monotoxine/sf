/**
 * @description Strategy: SEQUENCE_NUMBER
 *
 * Replaces a sensitive numeric identifier (SSN, IBAN, account number, etc.)
 * with a repeating digit sequence of a configurable length.
 *
 * The sequence repeats digits 1–9 cyclically: 123456789123456789...
 * This produces a value that:
 *   - matches the required length (controlled by metadata param)
 *   - is obviously fake (no real person has SSN "123456789")
 *   - passes basic length/format validation in downstream systems
 *
 * Example (from specification for ACCCO_SocialSecurityNumber__pc):
 *   param1 = "15"  → "123456789123456"
 *   param1 = "13"  → "1234567891234"
 *
 * Metadata params:
 *   param1  Desired output length as an integer string (required).
 *           If blank or non-numeric, falls back to the original field length,
 *           then to 15 as a last resort.
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public without sharing class AnonymizeSequenceNumber implements IAnonymizationStrategy {

    private static final Integer DEFAULT_LENGTH = 15;
    private static final String  DIGIT_SEQUENCE = '123456789';

    public String anonymize(AnonymizationContext ctx) {
        Integer targetLength = resolveLength(ctx);

        String result = '';
        for (Integer i = 0; i < targetLength; i++) {
            result += DIGIT_SEQUENCE.substring(Math.mod(i, DIGIT_SEQUENCE.length()),
                                               Math.mod(i, DIGIT_SEQUENCE.length()) + 1);
        }
        return result;
    }

    private Integer resolveLength(AnonymizationContext ctx) {
        if (String.isNotBlank(ctx.param1)) {
            try {
                Integer len = Integer.valueOf(ctx.param1.trim());
                if (len > 0) {
                    return len;
                }
            } catch (TypeException e) {
                // param1 is not a valid integer — fall through to original length
            }
        }
        String currentVal = ctx.getCurrentValue();
        if (String.isNotBlank(currentVal)) {
            return currentVal.length();
        }
        return DEFAULT_LENGTH;
    }
}
