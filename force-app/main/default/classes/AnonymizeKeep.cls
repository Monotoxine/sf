/**
 * @description Strategy: KEEP
 *
 * Returns the current field value unchanged. Use this strategy for fields
 * that must be preserved as-is (e.g. City, PostalCode, Country) so that
 * downstream systems can still route or classify records correctly.
 *
 * Having an explicit KEEP strategy (rather than simply omitting the field
 * from the config) serves two purposes:
 *   1. Documents the conscious decision to not anonymize this field.
 *   2. Allows the LWC preview to include the field in the scope table with
 *      a clear "Keep" label, so the admin can see the full picture.
 *
 * Metadata params: none.
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public without sharing class AnonymizeKeep implements IAnonymizationStrategy {

    public String anonymize(AnonymizationContext ctx) {
        return ctx.getCurrentValue();
    }
}
