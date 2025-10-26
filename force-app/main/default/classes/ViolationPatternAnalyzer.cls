/**
 * @description Analyse les patterns de violations de données pour identifier les problèmes récurrents
 * et suggérer des corrections automatiques intelligentes
 * @author Claude
 * @date 2025-10-26
 */
public with sharing class ViolationPatternAnalyzer {

    /**
     * @description Résultat d'analyse de pattern
     */
    public class PatternAnalysisResult {
        public String fieldName { get; set; }
        public String violationType { get; set; }
        public Integer frequency { get; set; }
        public Decimal percentage { get; set; }
        public List<String> commonValues { get; set; }
        public String suggestedFix { get; set; }
        public Decimal confidence { get; set; }
        public Map<String, Integer> valueDistribution { get; set; }

        public PatternAnalysisResult() {
            this.commonValues = new List<String>();
            this.valueDistribution = new Map<String, Integer>();
        }
    }

    /**
     * @description Configuration d'analyse
     */
    public class AnalysisConfig {
        public Integer minFrequency { get; set; }
        public Decimal minConfidence { get; set; }
        public Integer topValuesCount { get; set; }
        public Boolean includeNullValues { get; set; }

        public AnalysisConfig() {
            this.minFrequency = 5;
            this.minConfidence = 0.7;
            this.topValuesCount = 10;
            this.includeNullValues = true;
        }
    }

    /**
     * @description Analyse les violations pour un objet spécifique
     * @param sobjectType Type d'objet à analyser
     * @param fieldName Nom du champ à analyser
     * @param config Configuration d'analyse
     * @return Résultat de l'analyse
     */
    public static PatternAnalysisResult analyzeField(String sobjectType, String fieldName, AnalysisConfig config) {
        if (config == null) {
            config = new AnalysisConfig();
        }

        PatternAnalysisResult result = new PatternAnalysisResult();
        result.fieldName = fieldName;

        // Récupérer les données du champ
        String query = 'SELECT ' + fieldName + ', COUNT(Id) cnt FROM ' + sobjectType +
                      ' GROUP BY ' + fieldName + ' ORDER BY COUNT(Id) DESC LIMIT ' + config.topValuesCount;

        List<AggregateResult> aggregates = Database.query(query);

        Integer totalRecords = 0;
        Integer nullCount = 0;

        // Analyser la distribution des valeurs
        for (AggregateResult ar : aggregates) {
            Object value = ar.get(fieldName);
            Integer count = (Integer)ar.get('cnt');
            totalRecords += count;

            if (value == null) {
                nullCount = count;
                if (config.includeNullValues) {
                    result.valueDistribution.put('NULL', count);
                }
            } else {
                String valueStr = String.valueOf(value);
                result.valueDistribution.put(valueStr, count);
                result.commonValues.add(valueStr);
            }
        }

        // Calculer le total exact
        String countQuery = 'SELECT COUNT(Id) total FROM ' + sobjectType;
        Integer exactTotal = (Integer)Database.query(countQuery)[0].get('total');

        result.frequency = exactTotal;

        // Détecter le type de violation
        result.violationType = detectViolationType(fieldName, result.valueDistribution, nullCount, exactTotal);

        // Calculer la confiance et suggérer une correction
        calculateConfidenceAndSuggestion(result, nullCount, exactTotal, config);

        return result;
    }

    /**
     * @description Analyse les violations sur plusieurs champs
     * @param sobjectType Type d'objet
     * @param fieldNames Liste des champs à analyser
     * @param config Configuration
     * @return Map de résultats par champ
     */
    public static Map<String, PatternAnalysisResult> analyzeMultipleFields(
        String sobjectType,
        List<String> fieldNames,
        AnalysisConfig config
    ) {
        Map<String, PatternAnalysisResult> results = new Map<String, PatternAnalysisResult>();

        for (String fieldName : fieldNames) {
            try {
                PatternAnalysisResult result = analyzeField(sobjectType, fieldName, config);
                results.put(fieldName, result);
            } catch (Exception e) {
                // Log l'erreur mais continue avec les autres champs
                System.debug(LoggingLevel.ERROR, 'Error analyzing field ' + fieldName + ': ' + e.getMessage());
            }
        }

        return results;
    }

    /**
     * @description Détecte le type de violation basé sur la distribution des données
     */
    private static String detectViolationType(
        String fieldName,
        Map<String, Integer> distribution,
        Integer nullCount,
        Integer total
    ) {
        Decimal nullPercentage = total > 0 ? (Decimal)nullCount / total : 0;

        // Violation : trop de valeurs null
        if (nullPercentage > 0.5) {
            return 'HIGH_NULL_RATE';
        }

        // Violation : données manquantes
        if (nullPercentage > 0.1 && nullPercentage <= 0.5) {
            return 'MISSING_DATA';
        }

        // Violation : valeur unique dominante (probablement une erreur)
        if (!distribution.isEmpty()) {
            Integer maxCount = 0;
            for (Integer count : distribution.values()) {
                if (count > maxCount) {
                    maxCount = count;
                }
            }

            Decimal dominancePercentage = total > 0 ? (Decimal)maxCount / total : 0;
            if (dominancePercentage > 0.8) {
                return 'DOMINANT_VALUE';
            }
        }

        // Violation : faible diversité (peu de valeurs distinctes)
        if (distribution.size() < 3 && total > 100) {
            return 'LOW_DIVERSITY';
        }

        // Violation : dispersion élevée (trop de valeurs uniques)
        if (distribution.size() > total * 0.5 && total > 10) {
            return 'HIGH_DISPERSION';
        }

        return 'UNKNOWN';
    }

    /**
     * @description Calcule la confiance et suggère une correction
     */
    private static void calculateConfidenceAndSuggestion(
        PatternAnalysisResult result,
        Integer nullCount,
        Integer total,
        AnalysisConfig config
    ) {
        result.percentage = total > 0 ? ((Decimal)nullCount / total) * 100 : 0;

        if (result.violationType == 'HIGH_NULL_RATE' || result.violationType == 'MISSING_DATA') {
            // Suggérer la valeur la plus commune (non-null)
            if (!result.commonValues.isEmpty()) {
                String mostCommonValue = result.commonValues[0];
                Integer mostCommonCount = result.valueDistribution.get(mostCommonValue);

                result.suggestedFix = 'Replace NULL with "' + mostCommonValue + '"';
                result.confidence = total > 0 ? (Decimal)mostCommonCount / (total - nullCount) : 0;
            } else {
                result.suggestedFix = 'Set default value';
                result.confidence = 0.5;
            }
        } else if (result.violationType == 'DOMINANT_VALUE') {
            // Valeur dominante - peut être correcte, vérifier les outliers
            result.suggestedFix = 'Review outlier values for potential errors';
            result.confidence = 0.6;
        } else if (result.violationType == 'LOW_DIVERSITY') {
            result.suggestedFix = 'Consider consolidating to common values: ' + String.join(result.commonValues, ', ');
            result.confidence = 0.7;
        } else if (result.violationType == 'HIGH_DISPERSION') {
            result.suggestedFix = 'Consider implementing validation rules to reduce value diversity';
            result.confidence = 0.8;
        } else {
            result.suggestedFix = 'No clear pattern detected';
            result.confidence = 0.3;
        }

        // Ajuster la confiance basée sur la fréquence
        if (total < config.minFrequency) {
            result.confidence *= 0.5; // Réduit la confiance pour les petits échantillons
        }
    }

    /**
     * @description Analyse les patterns temporels de violations
     * @param sobjectType Type d'objet
     * @param fieldName Champ à analyser
     * @param dateField Champ de date pour l'analyse temporelle
     * @param daysBack Nombre de jours à analyser
     * @return Map de résultats par période
     */
    public static Map<String, PatternAnalysisResult> analyzeTemporalPatterns(
        String sobjectType,
        String fieldName,
        String dateField,
        Integer daysBack
    ) {
        Map<String, PatternAnalysisResult> results = new Map<String, PatternAnalysisResult>();

        String query = 'SELECT DAY_ONLY(' + dateField + ') day, ' + fieldName + ', COUNT(Id) cnt ' +
                      'FROM ' + sobjectType + ' ' +
                      'WHERE ' + dateField + ' = LAST_N_DAYS:' + daysBack + ' ' +
                      'GROUP BY DAY_ONLY(' + dateField + '), ' + fieldName;

        List<AggregateResult> aggregates = Database.query(query);

        // Grouper par jour
        Map<Date, Map<String, Integer>> dailyDistributions = new Map<Date, Map<String, Integer>>();

        for (AggregateResult ar : aggregates) {
            Date day = (Date)ar.get('day');
            Object value = ar.get(fieldName);
            Integer count = (Integer)ar.get('cnt');

            if (!dailyDistributions.containsKey(day)) {
                dailyDistributions.put(day, new Map<String, Integer>());
            }

            String valueStr = value != null ? String.valueOf(value) : 'NULL';
            dailyDistributions.get(day).put(valueStr, count);
        }

        // Créer un résultat pour chaque jour
        for (Date day : dailyDistributions.keySet()) {
            PatternAnalysisResult result = new PatternAnalysisResult();
            result.fieldName = fieldName;
            result.valueDistribution = dailyDistributions.get(day);

            Integer total = 0;
            for (Integer count : result.valueDistribution.values()) {
                total += count;
            }
            result.frequency = total;

            results.put(String.valueOf(day), result);
        }

        return results;
    }

    /**
     * @description Identifie les règles de validation manquantes
     * @param sobjectType Type d'objet
     * @param fieldName Champ à analyser
     * @return Liste de règles suggérées
     */
    public static List<String> suggestValidationRules(String sobjectType, String fieldName) {
        List<String> suggestions = new List<String>();

        AnalysisConfig config = new AnalysisConfig();
        PatternAnalysisResult result = analyzeField(sobjectType, fieldName, config);

        if (result.violationType == 'HIGH_NULL_RATE' || result.violationType == 'MISSING_DATA') {
            suggestions.add('Add required field validation: ISBLANK(' + fieldName + ')');
        }

        if (result.violationType == 'LOW_DIVERSITY' && !result.commonValues.isEmpty()) {
            suggestions.add('Add picklist values: ' + String.join(result.commonValues, ', '));
        }

        if (result.violationType == 'HIGH_DISPERSION') {
            suggestions.add('Add format validation or consider using picklist');
        }

        // Suggestions basées sur le type de champ
        Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(sobjectType);
        if (sobjType != null) {
            Schema.DescribeSObjectResult describe = sobjType.getDescribe();
            Map<String, Schema.SObjectField> fields = describe.fields.getMap();

            if (fields.containsKey(fieldName)) {
                Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();
                Schema.DisplayType fieldType = fieldDescribe.getType();

                if (fieldType == Schema.DisplayType.EMAIL) {
                    suggestions.add('Add email format validation: NOT(REGEX(' + fieldName + ', "[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}"))');
                } else if (fieldType == Schema.DisplayType.PHONE) {
                    suggestions.add('Add phone format validation');
                } else if (fieldType == Schema.DisplayType.URL) {
                    suggestions.add('Add URL format validation');
                }
            }
        }

        return suggestions;
    }

    /**
     * @description Compare les patterns entre deux périodes
     * @param sobjectType Type d'objet
     * @param fieldName Champ à analyser
     * @param dateField Champ de date
     * @param period1Days Période 1 (jours)
     * @param period2Days Période 2 (jours)
     * @return Résultat de comparaison
     */
    public static Map<String, Object> comparePatterns(
        String sobjectType,
        String fieldName,
        String dateField,
        Integer period1Days,
        Integer period2Days
    ) {
        Map<String, Object> comparison = new Map<String, Object>();

        // Analyser période 1 (plus récente)
        Map<String, PatternAnalysisResult> period1 = analyzeTemporalPatterns(
            sobjectType, fieldName, dateField, period1Days
        );

        // Analyser période 2 (plus ancienne)
        Map<String, PatternAnalysisResult> period2 = analyzeTemporalPatterns(
            sobjectType, fieldName, dateField, period2Days
        );

        comparison.put('period1', period1);
        comparison.put('period2', period2);

        // Calculer les tendances
        Integer period1Total = 0;
        Integer period2Total = 0;

        for (PatternAnalysisResult result : period1.values()) {
            period1Total += result.frequency;
        }

        for (PatternAnalysisResult result : period2.values()) {
            period2Total += result.frequency;
        }

        Decimal trend = period2Total > 0 ?
            ((Decimal)(period1Total - period2Total) / period2Total) * 100 : 0;

        comparison.put('trend', trend);
        comparison.put('period1Total', period1Total);
        comparison.put('period2Total', period2Total);

        return comparison;
    }
}
