/**
 * @description Strategy: LOREM_IPSUM
 *
 * Replaces a free-text field with a standard Lorem Ipsum placeholder.
 * The replacement text can be overridden per-field via metadata param1.
 *
 * Use for fields like Description, Notes, Comments, Biography, etc.
 *
 * Default output (from specification):
 *   "Lorem ipsum dolor sit amet, consectetur adipiscing elit.
 *    Morbi diam diam, vestibulum non aliquam in, dictum quis eros."
 *
 * Metadata params:
 *   param1  Custom replacement text (optional). When provided, this exact text
 *           is used instead of the default Lorem Ipsum. Useful to override per
 *           field (e.g. use a shorter placeholder for short text fields).
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public without sharing class AnonymizeLoremIpsum implements IAnonymizationStrategy {

    private static final String DEFAULT_TEXT =
        'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' +
        'Morbi diam diam, vestibulum non aliquam in, dictum quis eros.';

    public String anonymize(AnonymizationContext ctx) {
        return String.isNotBlank(ctx.param1) ? ctx.param1 : DEFAULT_TEXT;
    }
}
