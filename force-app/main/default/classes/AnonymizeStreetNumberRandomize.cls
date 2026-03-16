/**
 * @description Strategy: STREET_NUMBER_RANDOMIZE
 *
 * Preserves the street name but replaces the leading house/building number
 * with a random integer between 1 and 20 (inclusive).
 *
 * Examples (from specification — PersonMailingStreet, BillingStreet):
 *   "42 Rue de la Paix"   → "7 Rue de la Paix"   (random 1–20)
 *   "123 Avenue Montaigne"→ "15 Avenue Montaigne" (random 1–20)
 *
 * Detection logic: the field value is scanned for a leading integer token
 * (digits at the start, possibly followed by a letter suffix like "12b").
 * If no leading number is detected, the value is returned unchanged.
 *
 * Metadata params:
 *   param1  Upper bound for random range (optional, defaults to 20).
 *           Example: "100" to randomize between 1 and 100.
 *   param2  Lower bound for random range (optional, defaults to 1).
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public without sharing class AnonymizeStreetNumberRandomize implements IAnonymizationStrategy {

    private static final Integer DEFAULT_MIN = 1;
    private static final Integer DEFAULT_MAX = 20;

    // Matches: optional leading digits + optional letter suffix + whitespace + rest of street
    private static final Pattern STREET_PATTERN = Pattern.compile('^(\\d+[a-zA-Z]?)(\\s+.*)$');

    public String anonymize(AnonymizationContext ctx) {
        String val = ctx.getCurrentValue();
        if (String.isBlank(val)) {
            return val;
        }

        Integer minVal = resolveParam(ctx.param2, DEFAULT_MIN);
        Integer maxVal = resolveParam(ctx.param1, DEFAULT_MAX);
        if (maxVal < minVal) {
            maxVal = minVal + DEFAULT_MAX;
        }

        Matcher m = STREET_PATTERN.matcher(val.trim());
        if (m.matches()) {
            Integer range    = maxVal - minVal + 1;
            Integer randomNb = minVal + (Integer)(Math.random() * range);
            return String.valueOf(randomNb) + m.group(2);
        }

        // No leading number detected — return unchanged
        return val;
    }

    private Integer resolveParam(String param, Integer defaultVal) {
        if (String.isNotBlank(param)) {
            try {
                return Integer.valueOf(param.trim());
            } catch (TypeException e) {
                // ignore — use default
            }
        }
        return defaultVal;
    }
}
