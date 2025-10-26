/**
 * @description Framework de trigger pour validation de qualité de données en temps réel
 * Utilise le pattern Trigger Handler pour centraliser la logique de validation
 * @author Claude
 * @date 2025-10-26
 */
public virtual class DataQualityTriggerHandler {

    private Boolean skipValidation = false;
    private static Set<String> disabledObjects = new Set<String>();
    private static Map<String, List<RealTimeValidator.ValidationRule>> rulesByObject =
        new Map<String, List<RealTimeValidator.ValidationRule>>();

    /**
     * @description Context du trigger
     */
    public enum TriggerContext {
        BEFORE_INSERT,
        BEFORE_UPDATE,
        BEFORE_DELETE,
        AFTER_INSERT,
        AFTER_UPDATE,
        AFTER_DELETE,
        AFTER_UNDELETE
    }

    /**
     * @description Configuration du handler
     */
    public class HandlerConfig {
        public Boolean validateOnInsert { get; set; }
        public Boolean validateOnUpdate { get; set; }
        public Boolean autoFixEnabled { get; set; }
        public Boolean publishEvents { get; set; }
        public Boolean asyncValidation { get; set; }

        public HandlerConfig() {
            this.validateOnInsert = true;
            this.validateOnUpdate = true;
            this.autoFixEnabled = false;
            this.publishEvents = true;
            this.asyncValidation = false;
        }
    }

    private HandlerConfig config;

    /**
     * @description Constructeur
     */
    public DataQualityTriggerHandler() {
        this.config = new HandlerConfig();
    }

    /**
     * @description Constructeur avec configuration
     */
    public DataQualityTriggerHandler(HandlerConfig configuration) {
        this.config = configuration;
    }

    /**
     * @description Point d'entrée principal pour les triggers
     * @param context Context du trigger
     */
    public void run(TriggerContext context) {
        // Vérifier si la validation est désactivée
        if (skipValidation || isDisabled()) {
            return;
        }

        // Exécuter la logique selon le context
        if (context == TriggerContext.BEFORE_INSERT && config.validateOnInsert) {
            beforeInsert(Trigger.new);
        } else if (context == TriggerContext.BEFORE_UPDATE && config.validateOnUpdate) {
            beforeUpdate(Trigger.new, Trigger.oldMap);
        } else if (context == TriggerContext.AFTER_INSERT && config.validateOnInsert) {
            afterInsert(Trigger.new);
        } else if (context == TriggerContext.AFTER_UPDATE && config.validateOnUpdate) {
            afterUpdate(Trigger.new, Trigger.oldMap);
        }
    }

    /**
     * @description Logique before insert
     */
    protected virtual void beforeInsert(List<SObject> newRecords) {
        validateRecords(newRecords, 'BEFORE_INSERT');
    }

    /**
     * @description Logique before update
     */
    protected virtual void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        // Ne valider que les enregistrements modifiés
        List<SObject> modifiedRecords = getModifiedRecords(newRecords, oldRecordsMap);
        validateRecords(modifiedRecords, 'BEFORE_UPDATE');
    }

    /**
     * @description Logique after insert
     */
    protected virtual void afterInsert(List<SObject> newRecords) {
        if (config.asyncValidation) {
            validateRecordsAsync(newRecords);
        }
    }

    /**
     * @description Logique after update
     */
    protected virtual void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        if (config.asyncValidation) {
            List<SObject> modifiedRecords = getModifiedRecords(newRecords, oldRecordsMap);
            validateRecordsAsync(modifiedRecords);
        }
    }

    /**
     * @description Valide les enregistrements de manière synchrone
     */
    private void validateRecords(List<SObject> records, String context) {
        if (records == null || records.isEmpty()) {
            return;
        }

        String sobjectType = records[0].getSObjectType().getDescribe().getName();
        List<RealTimeValidator.ValidationRule> rules = getValidationRules(sobjectType);

        if (rules.isEmpty()) {
            return;
        }

        if (config.autoFixEnabled) {
            RealTimeValidator.ValidationResult result =
                RealTimeValidator.validateAndFix(records, rules, true);

            // Publier les événements pour les violations non corrigées
            if (config.publishEvents && !result.violations.isEmpty()) {
                publishViolationEvents(result.violations);
            }
        } else {
            RealTimeValidator.ValidationResult result =
                RealTimeValidator.validateRecords(records, rules);

            if (!result.isValid) {
                // Ajouter des erreurs aux enregistrements en contexte before
                if (context.startsWith('BEFORE')) {
                    addErrorsToRecords(records, result.violations);
                }

                // Publier les événements
                if (config.publishEvents) {
                    publishViolationEvents(result.violations);
                }
            }
        }
    }

    /**
     * @description Valide les enregistrements de manière asynchrone
     */
    private void validateRecordsAsync(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return;
        }

        String sobjectType = records[0].getSObjectType().getDescribe().getName();
        List<RealTimeValidator.ValidationRule> rules = getValidationRules(sobjectType);

        if (!rules.isEmpty()) {
            RealTimeValidator.validateAsync(records, rules, sobjectType);
        }
    }

    /**
     * @description Obtient les enregistrements modifiés
     */
    private List<SObject> getModifiedRecords(List<SObject> newRecords, Map<Id, SObject> oldRecordsMap) {
        List<SObject> modified = new List<SObject>();

        String sobjectType = newRecords[0].getSObjectType().getDescribe().getName();
        List<RealTimeValidator.ValidationRule> rules = getValidationRules(sobjectType);

        // Créer un set des champs à surveiller
        Set<String> fieldsToWatch = new Set<String>();
        for (RealTimeValidator.ValidationRule rule : rules) {
            fieldsToWatch.add(rule.fieldName);
        }

        for (SObject newRecord : newRecords) {
            SObject oldRecord = oldRecordsMap.get(newRecord.Id);

            // Vérifier si un des champs surveillés a changé
            Boolean hasChanged = false;
            for (String fieldName : fieldsToWatch) {
                Object newValue = newRecord.get(fieldName);
                Object oldValue = oldRecord != null ? oldRecord.get(fieldName) : null;

                if (newValue != oldValue) {
                    hasChanged = true;
                    break;
                }
            }

            if (hasChanged) {
                modified.add(newRecord);
            }
        }

        return modified;
    }

    /**
     * @description Ajoute des erreurs aux enregistrements
     */
    private void addErrorsToRecords(List<SObject> records, List<RealTimeValidator.ValidationViolation> violations) {
        Map<Id, List<RealTimeValidator.ValidationViolation>> violationsByRecord =
            new Map<Id, List<RealTimeValidator.ValidationViolation>>();

        for (RealTimeValidator.ValidationViolation violation : violations) {
            if (!violationsByRecord.containsKey(violation.recordId)) {
                violationsByRecord.put(violation.recordId, new List<RealTimeValidator.ValidationViolation>());
            }
            violationsByRecord.get(violation.recordId).add(violation);
        }

        for (SObject record : records) {
            if (violationsByRecord.containsKey(record.Id)) {
                List<RealTimeValidator.ValidationViolation> recordViolations = violationsByRecord.get(record.Id);

                for (RealTimeValidator.ValidationViolation violation : recordViolations) {
                    String errorMsg = violation.errorMessage != null ?
                        violation.errorMessage :
                        'Validation failed for ' + violation.fieldName;

                    // Ajouter l'erreur au champ ou à l'enregistrement
                    try {
                        record.addError(violation.fieldName, errorMsg);
                    } catch (Exception e) {
                        record.addError(errorMsg);
                    }
                }
            }
        }
    }

    /**
     * @description Publie des événements de violation
     */
    private void publishViolationEvents(List<RealTimeValidator.ValidationViolation> violations) {
        List<DataQualityEvent__e> events = new List<DataQualityEvent__e>();

        for (RealTimeValidator.ValidationViolation violation : violations) {
            DataQualityEvent__e event = new DataQualityEvent__e(
                RecordId__c = String.valueOf(violation.recordId),
                SObjectType__c = violation.recordId.getSObjectType().getDescribe().getName(),
                ViolationType__c = violation.violationType,
                FieldName__c = violation.fieldName,
                ErrorMessage__c = violation.errorMessage,
                Severity__c = violation.severity
            );

            events.add(event);
        }

        if (!events.isEmpty()) {
            EventBus.publish(events);
        }
    }

    /**
     * @description Récupère les règles de validation pour un objet
     */
    private List<RealTimeValidator.ValidationRule> getValidationRules(String sobjectType) {
        if (rulesByObject.containsKey(sobjectType)) {
            return rulesByObject.get(sobjectType);
        }

        // Créer des règles standard si aucune règle n'est définie
        List<RealTimeValidator.ValidationRule> rules = RealTimeValidator.createStandardRules(sobjectType);
        rulesByObject.put(sobjectType, rules);

        return rules;
    }

    /**
     * @description Enregistre des règles de validation pour un objet
     * @param sobjectType Type d'objet
     * @param rules Règles de validation
     */
    public static void registerValidationRules(String sobjectType, List<RealTimeValidator.ValidationRule> rules) {
        rulesByObject.put(sobjectType, rules);
    }

    /**
     * @description Désactive la validation pour un objet spécifique
     * @param sobjectType Type d'objet
     */
    public static void disableForObject(String sobjectType) {
        disabledObjects.add(sobjectType);
    }

    /**
     * @description Réactive la validation pour un objet spécifique
     * @param sobjectType Type d'objet
     */
    public static void enableForObject(String sobjectType) {
        disabledObjects.remove(sobjectType);
    }

    /**
     * @description Vérifie si la validation est désactivée pour l'objet actuel
     */
    private Boolean isDisabled() {
        if (Trigger.new != null && !Trigger.new.isEmpty()) {
            String sobjectType = Trigger.new[0].getSObjectType().getDescribe().getName();
            return disabledObjects.contains(sobjectType);
        }
        return false;
    }

    /**
     * @description Désactive temporairement la validation
     */
    public void disable() {
        this.skipValidation = true;
    }

    /**
     * @description Réactive la validation
     */
    public void enable() {
        this.skipValidation = false;
    }

    /**
     * @description Crée un handler par défaut pour un objet
     * @param sobjectType Type d'objet
     * @return Handler configuré
     */
    public static DataQualityTriggerHandler createDefault(String sobjectType) {
        HandlerConfig config = new HandlerConfig();
        config.validateOnInsert = true;
        config.validateOnUpdate = true;
        config.autoFixEnabled = false;
        config.publishEvents = true;
        config.asyncValidation = false;

        DataQualityTriggerHandler handler = new DataQualityTriggerHandler(config);

        // Enregistrer les règles standard
        List<RealTimeValidator.ValidationRule> rules = RealTimeValidator.createStandardRules(sobjectType);
        registerValidationRules(sobjectType, rules);

        return handler;
    }

    /**
     * @description Exemple d'utilisation dans un trigger
     */
    public static void exampleTriggerUsage() {
        // Dans un trigger Account:
        // trigger AccountTrigger on Account (before insert, before update, after insert, after update) {
        //     DataQualityTriggerHandler handler = DataQualityTriggerHandler.createDefault('Account');
        //
        //     if (Trigger.isBefore && Trigger.isInsert) {
        //         handler.run(DataQualityTriggerHandler.TriggerContext.BEFORE_INSERT);
        //     } else if (Trigger.isBefore && Trigger.isUpdate) {
        //         handler.run(DataQualityTriggerHandler.TriggerContext.BEFORE_UPDATE);
        //     } else if (Trigger.isAfter && Trigger.isInsert) {
        //         handler.run(DataQualityTriggerHandler.TriggerContext.AFTER_INSERT);
        //     } else if (Trigger.isAfter && Trigger.isUpdate) {
        //         handler.run(DataQualityTriggerHandler.TriggerContext.AFTER_UPDATE);
        //     }
        // }
    }
}
