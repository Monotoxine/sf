/**
 * @description Suggère automatiquement des règles de qualité basées sur l'analyse des données
 * @author Claude
 * @date 2025-10-26
 */
public with sharing class RuleSuggestionEngine {

    public class RuleSuggestion {
        public String ruleName { get; set; }
        public String ruleType { get; set; }
        public String formula { get; set; }
        public String reason { get; set; }
        public Decimal confidence { get; set; }
        public String severity { get; set; }

        public RuleSuggestion(String name, String type, Decimal confidence) {
            this.ruleName = name;
            this.ruleType = type;
            this.confidence = confidence;
            this.severity = 'Warning';
        }
    }

    /**
     * @description Suggère des règles basées sur le profil de données
     */
    public static List<RuleSuggestion> suggestRules(String sobjectType, String fieldName) {
        List<RuleSuggestion> suggestions = new List<RuleSuggestion>();

        // Profiler le champ
        DataProfiler.FieldProfile profile = DataProfiler.profileField(sobjectType, fieldName);

        // Règle REQUIRED si trop de NULL
        if (profile.nullPercentage > 30) {
            RuleSuggestion rule = new RuleSuggestion(
                fieldName + '_Required',
                'REQUIRED',
                0.9
            );
            rule.formula = 'ISBLANK(' + fieldName + ')';
            rule.reason = 'High NULL rate: ' + profile.nullPercentage.setScale(2) + '%';
            rule.severity = 'Error';
            suggestions.add(rule);
        }

        // Règle PICKLIST si faible diversité
        if (profile.distinctValues > 0 && profile.distinctValues <= 10 && profile.totalRecords > 50) {
            RuleSuggestion rule = new RuleSuggestion(
                fieldName + '_ValidValues',
                'PICKLIST',
                0.85
            );
            rule.formula = 'NOT(ISPICKVAL(' + fieldName + ', ...))';
            rule.reason = 'Only ' + profile.distinctValues + ' distinct values found';
            suggestions.add(rule);
        }

        // Règle RANGE si statistiques numériques disponibles
        if (profile.mean != null && profile.stdDev != null) {
            Decimal lowerBound = profile.mean - (3 * profile.stdDev);
            Decimal upperBound = profile.mean + (3 * profile.stdDev);

            RuleSuggestion rule = new RuleSuggestion(
                fieldName + '_Range',
                'RANGE',
                0.75
            );
            rule.formula = fieldName + ' < ' + lowerBound + ' || ' + fieldName + ' > ' + upperBound;
            rule.reason = 'Values should be within 3 standard deviations';
            suggestions.add(rule);
        }

        return suggestions;
    }

    /**
     * @description Suggère des règles pour un objet complet
     */
    public static Map<String, List<RuleSuggestion>> suggestForObject(String sobjectType, List<String> fieldNames) {
        Map<String, List<RuleSuggestion>> allSuggestions = new Map<String, List<RuleSuggestion>>();

        for (String fieldName : fieldNames) {
            try {
                List<RuleSuggestion> suggestions = suggestRules(sobjectType, fieldName);
                if (!suggestions.isEmpty()) {
                    allSuggestions.put(fieldName, suggestions);
                }
            } catch (Exception e) {
                System.debug('Error suggesting rules for ' + fieldName + ': ' + e.getMessage());
            }
        }

        return allSuggestions;
    }
}
