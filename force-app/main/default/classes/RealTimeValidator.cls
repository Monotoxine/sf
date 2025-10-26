/**
 * @description Validation en temps réel avec traitement async via Queueable
 * Publie des Platform Events pour notifier des violations de qualité de données
 * @author Claude
 * @date 2025-10-26
 */
public with sharing class RealTimeValidator implements Queueable {

    private List<SObject> recordsToValidate;
    private List<ValidationRule> rules;
    private String sobjectType;

    /**
     * @description Règle de validation personnalisée
     */
    public class ValidationRule {
        public String ruleName { get; set; }
        public String fieldName { get; set; }
        public String validationType { get; set; }  // REQUIRED, FORMAT, RANGE, CUSTOM
        public String formula { get; set; }
        public String errorMessage { get; set; }
        public String severity { get; set; }  // Info, Warning, Error, Critical
        public Object minValue { get; set; }
        public Object maxValue { get; set; }
        public String regexPattern { get; set; }

        public ValidationRule(String name, String field, String type) {
            this.ruleName = name;
            this.fieldName = field;
            this.validationType = type;
            this.severity = 'Error';
        }
    }

    /**
     * @description Résultat de validation
     */
    public class ValidationResult {
        public Boolean isValid { get; set; }
        public List<ValidationViolation> violations { get; set; }
        public Integer recordsValidated { get; set; }
        public Integer violationsFound { get; set; }

        public ValidationResult() {
            this.isValid = true;
            this.violations = new List<ValidationViolation>();
            this.recordsValidated = 0;
            this.violationsFound = 0;
        }
    }

    /**
     * @description Violation de validation
     */
    public class ValidationViolation {
        public Id recordId { get; set; }
        public String ruleName { get; set; }
        public String fieldName { get; set; }
        public String violationType { get; set; }
        public String errorMessage { get; set; }
        public String severity { get; set; }
        public Object actualValue { get; set; }
        public Object expectedValue { get; set; }

        public ValidationViolation(Id recordId, ValidationRule rule) {
            this.recordId = recordId;
            this.ruleName = rule.ruleName;
            this.fieldName = rule.fieldName;
            this.violationType = rule.validationType;
            this.errorMessage = rule.errorMessage;
            this.severity = rule.severity;
        }
    }

    /**
     * @description Constructeur pour Queueable
     */
    public RealTimeValidator(List<SObject> records, List<ValidationRule> validationRules, String objectType) {
        this.recordsToValidate = records;
        this.rules = validationRules;
        this.sobjectType = objectType;
    }

    /**
     * @description Exécution Queueable pour validation async
     */
    public void execute(QueueableContext context) {
        if (recordsToValidate == null || recordsToValidate.isEmpty()) {
            return;
        }

        ValidationResult result = validateRecords(recordsToValidate, rules);

        // Publier les événements de violation
        if (!result.violations.isEmpty()) {
            publishViolationEvents(result.violations);
        }
    }

    /**
     * @description Valide une liste d'enregistrements de manière synchrone
     * @param records Enregistrements à valider
     * @param validationRules Règles de validation
     * @return Résultat de validation
     */
    public static ValidationResult validateRecords(List<SObject> records, List<ValidationRule> validationRules) {
        ValidationResult result = new ValidationResult();

        if (records == null || records.isEmpty() || validationRules == null || validationRules.isEmpty()) {
            return result;
        }

        for (SObject record : records) {
            result.recordsValidated++;

            for (ValidationRule rule : validationRules) {
                ValidationViolation violation = validateRecord(record, rule);

                if (violation != null) {
                    result.violations.add(violation);
                    result.violationsFound++;
                    result.isValid = false;
                }
            }
        }

        return result;
    }

    /**
     * @description Valide un enregistrement contre une règle
     * @param record Enregistrement à valider
     * @param rule Règle de validation
     * @return Violation ou null si valide
     */
    private static ValidationViolation validateRecord(SObject record, ValidationRule rule) {
        Object fieldValue = record.get(rule.fieldName);

        Boolean isViolation = false;
        ValidationViolation violation = null;

        if (rule.validationType == 'REQUIRED') {
            if (fieldValue == null || String.valueOf(fieldValue).trim() == '') {
                isViolation = true;
                violation = new ValidationViolation(record.Id, rule);
                violation.actualValue = fieldValue;
                violation.expectedValue = 'Non-null value';
            }
        } else if (rule.validationType == 'FORMAT' && rule.regexPattern != null) {
            if (fieldValue != null) {
                String strValue = String.valueOf(fieldValue);
                Pattern p = Pattern.compile(rule.regexPattern);
                Matcher m = p.matcher(strValue);

                if (!m.matches()) {
                    isViolation = true;
                    violation = new ValidationViolation(record.Id, rule);
                    violation.actualValue = fieldValue;
                    violation.expectedValue = 'Format matching: ' + rule.regexPattern;
                }
            }
        } else if (rule.validationType == 'RANGE') {
            if (fieldValue != null) {
                try {
                    Decimal numValue = Decimal.valueOf(String.valueOf(fieldValue));

                    if (rule.minValue != null) {
                        Decimal minVal = Decimal.valueOf(String.valueOf(rule.minValue));
                        if (numValue < minVal) {
                            isViolation = true;
                        }
                    }

                    if (rule.maxValue != null) {
                        Decimal maxVal = Decimal.valueOf(String.valueOf(rule.maxValue));
                        if (numValue > maxVal) {
                            isViolation = true;
                        }
                    }

                    if (isViolation) {
                        violation = new ValidationViolation(record.Id, rule);
                        violation.actualValue = fieldValue;
                        violation.expectedValue = 'Between ' + rule.minValue + ' and ' + rule.maxValue;
                    }
                } catch (Exception e) {
                    // Valeur non-numérique pour RANGE
                }
            }
        } else if (rule.validationType == 'CUSTOM' && rule.formula != null) {
            // Évaluer une formule personnalisée
            isViolation = evaluateCustomFormula(record, rule.formula);

            if (isViolation) {
                violation = new ValidationViolation(record.Id, rule);
                violation.actualValue = fieldValue;
                violation.expectedValue = 'Formula: ' + rule.formula;
            }
        }

        return violation;
    }

    /**
     * @description Évalue une formule personnalisée
     * @param record Enregistrement
     * @param formula Formule à évaluer
     * @return True si violation détectée
     */
    private static Boolean evaluateCustomFormula(SObject record, String formula) {
        try {
            // Utiliser le FormulaEvaluator si disponible
            FormulaTokenizer tokenizer = new FormulaTokenizer(formula);
            List<FormulaToken> tokens = tokenizer.tokenize();

            FormulaParser parser = new FormulaParser(tokens);
            FormulaNode ast = parser.parse();

            FormulaEvaluator evaluator = new FormulaEvaluator();
            Object result = evaluator.evaluate(ast, record);

            // Si le résultat est true, c'est une violation
            if (result instanceof Boolean) {
                return (Boolean)result;
            }

            return false;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Error evaluating formula: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Publie des événements de violation sur la plateforme
     * @param violations Liste des violations
     */
    private static void publishViolationEvents(List<ValidationViolation> violations) {
        List<DataQualityEvent__e> events = new List<DataQualityEvent__e>();

        for (ValidationViolation violation : violations) {
            DataQualityEvent__e event = new DataQualityEvent__e(
                RecordId__c = String.valueOf(violation.recordId),
                SObjectType__c = violation.recordId.getSObjectType().getDescribe().getName(),
                ViolationType__c = violation.violationType,
                FieldName__c = violation.fieldName,
                ErrorMessage__c = violation.errorMessage != null ?
                    violation.errorMessage :
                    'Validation failed for ' + violation.fieldName,
                Severity__c = violation.severity
            );

            events.add(event);
        }

        if (!events.isEmpty()) {
            List<Database.SaveResult> results = EventBus.publish(events);

            // Log les erreurs de publication
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    for (Database.Error error : results[i].getErrors()) {
                        System.debug(LoggingLevel.ERROR, 'Error publishing event: ' + error.getMessage());
                    }
                }
            }
        }
    }

    /**
     * @description Valide des enregistrements de manière asynchrone
     * @param records Enregistrements à valider
     * @param validationRules Règles de validation
     * @param sobjectType Type d'objet
     * @return ID du job Queueable
     */
    public static Id validateAsync(List<SObject> records, List<ValidationRule> validationRules, String sobjectType) {
        RealTimeValidator validator = new RealTimeValidator(records, validationRules, sobjectType);
        return System.enqueueJob(validator);
    }

    /**
     * @description Valide et corrige automatiquement si possible
     * @param records Enregistrements à valider
     * @param validationRules Règles de validation
     * @param autoFix Activer la correction automatique
     * @return Résultat de validation avec corrections
     */
    public static ValidationResult validateAndFix(
        List<SObject> records,
        List<ValidationRule> validationRules,
        Boolean autoFix
    ) {
        ValidationResult result = validateRecords(records, validationRules);

        if (autoFix && !result.violations.isEmpty()) {
            // Grouper les violations par champ
            Map<String, List<ValidationViolation>> violationsByField = new Map<String, List<ValidationViolation>>();

            for (ValidationViolation violation : result.violations) {
                if (!violationsByField.containsKey(violation.fieldName)) {
                    violationsByField.put(violation.fieldName, new List<ValidationViolation>());
                }
                violationsByField.get(violation.fieldName).add(violation);
            }

            // Tenter de corriger chaque champ
            for (String fieldName : violationsByField.keySet()) {
                List<ValidationViolation> fieldViolations = violationsByField.get(fieldName);

                // Utiliser SmartAutoFix pour corriger
                SmartAutoFix.AutoFixConfig config = new SmartAutoFix.AutoFixConfig();
                config.dryRun = false;
                config.minConfidence = 0.7;

                String sobjectType = fieldViolations[0].recordId.getSObjectType().getDescribe().getName();

                try {
                    SmartAutoFix.FixResult fixResult = SmartAutoFix.autoFix(sobjectType, fieldName, config);

                    // Mettre à jour les statistiques
                    if (fixResult.success) {
                        result.violationsFound -= fixResult.recordsFixed;
                    }
                } catch (Exception e) {
                    System.debug(LoggingLevel.ERROR, 'Error auto-fixing field ' + fieldName + ': ' + e.getMessage());
                }
            }
        }

        return result;
    }

    /**
     * @description Crée des règles de validation standards pour un objet
     * @param sobjectType Type d'objet
     * @return Liste de règles de validation
     */
    public static List<ValidationRule> createStandardRules(String sobjectType) {
        List<ValidationRule> rules = new List<ValidationRule>();

        Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(sobjectType);
        if (sobjType == null) {
            return rules;
        }

        Schema.DescribeSObjectResult describe = sobjType.getDescribe();
        Map<String, Schema.SObjectField> fields = describe.fields.getMap();

        for (String fieldName : fields.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fields.get(fieldName).getDescribe();

            // Règle REQUIRED pour les champs requis
            if (!fieldDescribe.isNillable() && fieldDescribe.isCreateable()) {
                ValidationRule rule = new ValidationRule(
                    fieldName + '_Required',
                    fieldName,
                    'REQUIRED'
                );
                rule.errorMessage = fieldName + ' is required';
                rule.severity = 'Error';
                rules.add(rule);
            }

            // Règle FORMAT pour les emails
            if (fieldDescribe.getType() == Schema.DisplayType.EMAIL) {
                ValidationRule rule = new ValidationRule(
                    fieldName + '_EmailFormat',
                    fieldName,
                    'FORMAT'
                );
                rule.regexPattern = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$';
                rule.errorMessage = 'Invalid email format';
                rule.severity = 'Warning';
                rules.add(rule);
            }

            // Règle FORMAT pour les URLs
            if (fieldDescribe.getType() == Schema.DisplayType.URL) {
                ValidationRule rule = new ValidationRule(
                    fieldName + '_URLFormat',
                    fieldName,
                    'FORMAT'
                );
                rule.regexPattern = '^https?://.*';
                rule.errorMessage = 'Invalid URL format';
                rule.severity = 'Warning';
                rules.add(rule);
            }

            // Règle FORMAT pour les téléphones
            if (fieldDescribe.getType() == Schema.DisplayType.PHONE) {
                ValidationRule rule = new ValidationRule(
                    fieldName + '_PhoneFormat',
                    fieldName,
                    'FORMAT'
                );
                rule.regexPattern = '^[+]?[(]?[0-9]{1,4}[)]?[-\\s\\.]?[(]?[0-9]{1,4}[)]?[-\\s\\.]?[0-9]{1,9}$';
                rule.errorMessage = 'Invalid phone format';
                rule.severity = 'Warning';
                rules.add(rule);
            }
        }

        return rules;
    }

    /**
     * @description Obtient un résumé des violations par sévérité
     * @param result Résultat de validation
     * @return Map de compteurs par sévérité
     */
    public static Map<String, Integer> getViolationSummary(ValidationResult result) {
        Map<String, Integer> summary = new Map<String, Integer>{
            'Info' => 0,
            'Warning' => 0,
            'Error' => 0,
            'Critical' => 0
        };

        for (ValidationViolation violation : result.violations) {
            String severity = violation.severity != null ? violation.severity : 'Error';
            if (summary.containsKey(severity)) {
                summary.put(severity, summary.get(severity) + 1);
            }
        }

        return summary;
    }
}
