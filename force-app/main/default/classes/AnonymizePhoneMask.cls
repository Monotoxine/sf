/**
 * @description Strategy: PHONE_MASK
 *
 * Keeps the first 4 characters of a phone number and replaces all remaining
 * characters with '0', preserving the original length.
 *
 * Examples (from specification):
 *   "+33123456789" (12 chars) → "+33100000000"
 *   "+33612345678" (12 chars) → "+33600000000"
 *
 * Works for any phone format (with or without country code, with or without
 * separators) because it operates on character position, not phone structure.
 *
 * Metadata params: none required.
 *
 * Edge cases:
 *   - Null/empty value  → returned as-is (no change).
 *   - Value shorter than 4 chars → returned as-is (cannot meaningfully mask).
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public without sharing class AnonymizePhoneMask implements IAnonymizationStrategy {

    private static final Integer PREFIX_LENGTH = 4;

    public String anonymize(AnonymizationContext ctx) {
        String val = ctx.getCurrentValue();
        if (String.isBlank(val) || val.length() <= PREFIX_LENGTH) {
            return val;
        }

        String prefix  = val.substring(0, PREFIX_LENGTH);
        Integer padLen = val.length() - PREFIX_LENGTH;
        String  zeros  = '0'.repeat(padLen);

        return prefix + zeros;
    }
}
