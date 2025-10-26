/**
 * @description Système de correction automatique intelligente basé sur l'analyse de patterns
 * @author Claude
 * @date 2025-10-26
 */
public with sharing class SmartAutoFix {

    /**
     * @description Résultat d'une correction automatique
     */
    public class FixResult {
        public Boolean success { get; set; }
        public Integer recordsAnalyzed { get; set; }
        public Integer recordsFixed { get; set; }
        public Integer recordsFailed { get; set; }
        public List<String> errors { get; set; }
        public String fixStrategy { get; set; }
        public Decimal confidence { get; set; }
        public Map<String, Integer> appliedFixes { get; set; }

        public FixResult() {
            this.success = false;
            this.recordsAnalyzed = 0;
            this.recordsFixed = 0;
            this.recordsFailed = 0;
            this.errors = new List<String>();
            this.appliedFixes = new Map<String, Integer>();
        }
    }

    /**
     * @description Configuration de correction automatique
     */
    public class AutoFixConfig {
        public Decimal minConfidence { get; set; }
        public Boolean dryRun { get; set; }
        public Integer batchSize { get; set; }
        public Boolean autoApprove { get; set; }
        public List<String> allowedFixTypes { get; set; }

        public AutoFixConfig() {
            this.minConfidence = 0.7;
            this.dryRun = false;
            this.batchSize = 200;
            this.autoApprove = false;
            this.allowedFixTypes = new List<String>{
                'NULL_TO_DEFAULT',
                'STANDARDIZE_FORMAT',
                'TRIM_WHITESPACE',
                'CASE_NORMALIZATION'
            };
        }
    }

    /**
     * @description Suggestion de correction
     */
    public class FixSuggestion {
        public String fieldName { get; set; }
        public String fixType { get; set; }
        public Object suggestedValue { get; set; }
        public String reasoning { get; set; }
        public Decimal confidence { get; set; }
        public Integer affectedRecords { get; set; }

        public FixSuggestion(String fieldName, String fixType, Object value, Decimal confidence) {
            this.fieldName = fieldName;
            this.fixType = fixType;
            this.suggestedValue = value;
            this.confidence = confidence;
        }
    }

    /**
     * @description Applique des corrections automatiques basées sur l'analyse de patterns
     * @param sobjectType Type d'objet à corriger
     * @param fieldName Champ à corriger
     * @param config Configuration de correction
     * @return Résultat de la correction
     */
    public static FixResult autoFix(String sobjectType, String fieldName, AutoFixConfig config) {
        if (config == null) {
            config = new AutoFixConfig();
        }

        FixResult result = new FixResult();

        try {
            // Analyser les patterns de violation
            ViolationPatternAnalyzer.AnalysisConfig analysisConfig = new ViolationPatternAnalyzer.AnalysisConfig();
            ViolationPatternAnalyzer.PatternAnalysisResult pattern =
                ViolationPatternAnalyzer.analyzeField(sobjectType, fieldName, analysisConfig);

            result.confidence = pattern.confidence;
            result.fixStrategy = pattern.violationType;

            // Vérifier si la confiance est suffisante
            if (pattern.confidence < config.minConfidence) {
                result.errors.add('Confidence too low: ' + pattern.confidence + ' < ' + config.minConfidence);
                return result;
            }

            // Déterminer la stratégie de correction
            FixSuggestion suggestion = determineFixStrategy(pattern, sobjectType, fieldName);

            if (suggestion == null || !config.allowedFixTypes.contains(suggestion.fixType)) {
                result.errors.add('No suitable fix strategy found or not allowed');
                return result;
            }

            // Récupérer les enregistrements à corriger
            List<SObject> recordsToFix = getRecordsToFix(sobjectType, fieldName, suggestion);
            result.recordsAnalyzed = recordsToFix.size();

            if (recordsToFix.isEmpty()) {
                result.success = true;
                return result;
            }

            // Mode dry run : ne pas appliquer les corrections
            if (config.dryRun) {
                result.recordsFixed = recordsToFix.size();
                result.success = true;
                result.appliedFixes.put(suggestion.fixType, recordsToFix.size());
                return result;
            }

            // Appliquer les corrections
            result = applyFixes(recordsToFix, fieldName, suggestion, config);

        } catch (Exception e) {
            result.success = false;
            result.errors.add('Error during auto-fix: ' + e.getMessage());
        }

        return result;
    }

    /**
     * @description Applique des corrections sur plusieurs champs
     * @param sobjectType Type d'objet
     * @param fieldNames Liste des champs
     * @param config Configuration
     * @return Map de résultats par champ
     */
    public static Map<String, FixResult> autoFixMultipleFields(
        String sobjectType,
        List<String> fieldNames,
        AutoFixConfig config
    ) {
        Map<String, FixResult> results = new Map<String, FixResult>();

        for (String fieldName : fieldNames) {
            try {
                FixResult result = autoFix(sobjectType, fieldName, config);
                results.put(fieldName, result);
            } catch (Exception e) {
                FixResult errorResult = new FixResult();
                errorResult.errors.add('Error fixing field ' + fieldName + ': ' + e.getMessage());
                results.put(fieldName, errorResult);
            }
        }

        return results;
    }

    /**
     * @description Détermine la stratégie de correction basée sur l'analyse
     */
    private static FixSuggestion determineFixStrategy(
        ViolationPatternAnalyzer.PatternAnalysisResult pattern,
        String sobjectType,
        String fieldName
    ) {
        FixSuggestion suggestion = null;

        if (pattern.violationType == 'HIGH_NULL_RATE' || pattern.violationType == 'MISSING_DATA') {
            // Remplacer les NULL par la valeur la plus commune
            if (!pattern.commonValues.isEmpty()) {
                String mostCommonValue = pattern.commonValues[0];
                suggestion = new FixSuggestion(fieldName, 'NULL_TO_DEFAULT', mostCommonValue, pattern.confidence);
                suggestion.reasoning = 'Most common non-null value found in ' +
                    pattern.valueDistribution.get(mostCommonValue) + ' records';
            }
        } else if (pattern.violationType == 'LOW_DIVERSITY') {
            // Normaliser vers les valeurs communes
            if (!pattern.commonValues.isEmpty()) {
                suggestion = new FixSuggestion(fieldName, 'STANDARDIZE_FORMAT', pattern.commonValues[0], pattern.confidence);
                suggestion.reasoning = 'Standardize to most common format';
            }
        }

        // Détection de problèmes de formatage spécifiques
        Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(sobjectType);
        if (sobjType != null) {
            Schema.DescribeSObjectResult describe = sobjType.getDescribe();
            Map<String, Schema.SObjectField> fields = describe.fields.getMap();

            if (fields.containsKey(fieldName)) {
                Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();
                Schema.DisplayType fieldType = fieldDescribe.getType();

                // Suggestions spécifiques au type de champ
                if (fieldType == Schema.DisplayType.STRING || fieldType == Schema.DisplayType.TEXTAREA) {
                    // Détecter les espaces inutiles
                    if (hasWhitespaceIssues(pattern)) {
                        suggestion = new FixSuggestion(fieldName, 'TRIM_WHITESPACE', null, 0.9);
                        suggestion.reasoning = 'Remove leading/trailing whitespace';
                    }
                }
            }
        }

        return suggestion;
    }

    /**
     * @description Vérifie s'il y a des problèmes d'espaces dans les valeurs
     */
    private static Boolean hasWhitespaceIssues(ViolationPatternAnalyzer.PatternAnalysisResult pattern) {
        for (String value : pattern.valueDistribution.keySet()) {
            if (value != null && (value.startsWith(' ') || value.endsWith(' '))) {
                return true;
            }
        }
        return false;
    }

    /**
     * @description Récupère les enregistrements à corriger
     */
    private static List<SObject> getRecordsToFix(
        String sobjectType,
        String fieldName,
        FixSuggestion suggestion
    ) {
        String query = 'SELECT Id, ' + fieldName + ' FROM ' + sobjectType;

        if (suggestion.fixType == 'NULL_TO_DEFAULT') {
            query += ' WHERE ' + fieldName + ' = null LIMIT 10000';
        } else if (suggestion.fixType == 'TRIM_WHITESPACE') {
            query += ' WHERE ' + fieldName + ' != null LIMIT 10000';
        } else {
            query += ' LIMIT 10000';
        }

        return Database.query(query);
    }

    /**
     * @description Applique les corrections sur les enregistrements
     */
    private static FixResult applyFixes(
        List<SObject> records,
        String fieldName,
        FixSuggestion suggestion,
        AutoFixConfig config
    ) {
        FixResult result = new FixResult();
        result.recordsAnalyzed = records.size();

        List<SObject> recordsToUpdate = new List<SObject>();

        for (SObject record : records) {
            try {
                Boolean needsUpdate = false;
                Object currentValue = record.get(fieldName);

                if (suggestion.fixType == 'NULL_TO_DEFAULT' && currentValue == null) {
                    record.put(fieldName, suggestion.suggestedValue);
                    needsUpdate = true;
                } else if (suggestion.fixType == 'TRIM_WHITESPACE' && currentValue != null) {
                    String strValue = String.valueOf(currentValue);
                    String trimmedValue = strValue.trim();
                    if (strValue != trimmedValue) {
                        record.put(fieldName, trimmedValue);
                        needsUpdate = true;
                    }
                } else if (suggestion.fixType == 'STANDARDIZE_FORMAT' && currentValue != null) {
                    record.put(fieldName, suggestion.suggestedValue);
                    needsUpdate = true;
                } else if (suggestion.fixType == 'CASE_NORMALIZATION' && currentValue != null) {
                    String strValue = String.valueOf(currentValue);
                    record.put(fieldName, strValue.toUpperCase());
                    needsUpdate = true;
                }

                if (needsUpdate) {
                    recordsToUpdate.add(record);
                }
            } catch (Exception e) {
                result.errors.add('Error processing record ' + record.Id + ': ' + e.getMessage());
            }
        }

        // Mettre à jour par lots
        if (!recordsToUpdate.isEmpty()) {
            Integer batchStart = 0;
            while (batchStart < recordsToUpdate.size()) {
                Integer batchEnd = Math.min(batchStart + config.batchSize, recordsToUpdate.size());
                List<SObject> batch = new List<SObject>();

                for (Integer i = batchStart; i < batchEnd; i++) {
                    batch.add(recordsToUpdate[i]);
                }

                Database.SaveResult[] saveResults = Database.update(batch, false);

                for (Integer i = 0; i < saveResults.size(); i++) {
                    if (saveResults[i].isSuccess()) {
                        result.recordsFixed++;
                        if (!result.appliedFixes.containsKey(suggestion.fixType)) {
                            result.appliedFixes.put(suggestion.fixType, 0);
                        }
                        result.appliedFixes.put(suggestion.fixType, result.appliedFixes.get(suggestion.fixType) + 1);
                    } else {
                        result.recordsFailed++;
                        for (Database.Error error : saveResults[i].getErrors()) {
                            result.errors.add('Update failed: ' + error.getMessage());
                        }
                    }
                }

                batchStart = batchEnd;
            }
        }

        result.success = result.recordsFixed > 0;
        return result;
    }

    /**
     * @description Génère des suggestions de correction sans les appliquer
     * @param sobjectType Type d'objet
     * @param fieldNames Liste des champs à analyser
     * @return Liste de suggestions
     */
    public static List<FixSuggestion> generateSuggestions(String sobjectType, List<String> fieldNames) {
        List<FixSuggestion> suggestions = new List<FixSuggestion>();

        ViolationPatternAnalyzer.AnalysisConfig config = new ViolationPatternAnalyzer.AnalysisConfig();

        for (String fieldName : fieldNames) {
            try {
                ViolationPatternAnalyzer.PatternAnalysisResult pattern =
                    ViolationPatternAnalyzer.analyzeField(sobjectType, fieldName, config);

                FixSuggestion suggestion = determineFixStrategy(pattern, sobjectType, fieldName);

                if (suggestion != null && suggestion.confidence >= 0.5) {
                    // Compter les enregistrements affectés
                    List<SObject> affectedRecords = getRecordsToFix(sobjectType, fieldName, suggestion);
                    suggestion.affectedRecords = affectedRecords.size();

                    suggestions.add(suggestion);
                }
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Error generating suggestion for ' + fieldName + ': ' + e.getMessage());
            }
        }

        return suggestions;
    }

    /**
     * @description Applique une suggestion spécifique
     * @param sobjectType Type d'objet
     * @param suggestion Suggestion à appliquer
     * @param config Configuration
     * @return Résultat de l'application
     */
    public static FixResult applySuggestion(
        String sobjectType,
        FixSuggestion suggestion,
        AutoFixConfig config
    ) {
        if (config == null) {
            config = new AutoFixConfig();
        }

        FixResult result = new FixResult();

        try {
            List<SObject> recordsToFix = getRecordsToFix(sobjectType, suggestion.fieldName, suggestion);
            result.recordsAnalyzed = recordsToFix.size();

            if (recordsToFix.isEmpty()) {
                result.success = true;
                return result;
            }

            if (config.dryRun) {
                result.recordsFixed = recordsToFix.size();
                result.success = true;
                result.appliedFixes.put(suggestion.fixType, recordsToFix.size());
                return result;
            }

            result = applyFixes(recordsToFix, suggestion.fieldName, suggestion, config);

        } catch (Exception e) {
            result.success = false;
            result.errors.add('Error applying suggestion: ' + e.getMessage());
        }

        return result;
    }

    /**
     * @description Valide une suggestion avant application
     * @param sobjectType Type d'objet
     * @param suggestion Suggestion à valider
     * @return True si la suggestion est valide et sûre
     */
    public static Boolean validateSuggestion(String sobjectType, FixSuggestion suggestion) {
        if (suggestion == null || suggestion.confidence < 0.5) {
            return false;
        }

        // Vérifier que le champ existe et est accessible
        Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(sobjectType);
        if (sobjType == null) {
            return false;
        }

        Schema.DescribeSObjectResult describe = sobjType.getDescribe();
        Map<String, Schema.SObjectField> fields = describe.fields.getMap();

        if (!fields.containsKey(suggestion.fieldName)) {
            return false;
        }

        Schema.DescribeFieldResult fieldDescribe = fields.get(suggestion.fieldName).getDescribe();

        // Vérifier que le champ est modifiable
        if (!fieldDescribe.isUpdateable()) {
            return false;
        }

        return true;
    }
}
