/**
 * @description Strategy: FIRST_LETTER_PLUS_EXTERNAL_ID
 *
 * Replaces a name field with its first letter followed by the record's external ID.
 *
 * Examples (from specification):
 *   FirstName "Jean-Pierre" + ExternalID "12345678" → "J12345678"
 *   LastName  "Dupont"      + ExternalID "12345678" → "D12345678"
 *
 * Metadata params: none required.
 *
 * Edge cases:
 *   - Empty/null field value  → uses "X" as the first letter placeholder.
 *   - Null external ID        → returns the first letter alone.
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public without sharing class AnonymizeFirstLetterPlusExternalId implements IAnonymizationStrategy {

    public String anonymize(AnonymizationContext ctx) {
        String val    = ctx.getCurrentValue();
        String extId  = ctx.getExternalId();

        String firstLetter = (String.isNotBlank(val)) ? val.substring(0, 1).toUpperCase() : 'X';
        return firstLetter + (String.isNotBlank(extId) ? extId : '');
    }
}
