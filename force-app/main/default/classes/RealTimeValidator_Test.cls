/**
 * @description Tests pour le système Real-Time Validation
 * Couvre RealTimeValidator et DataQualityTriggerHandler
 * @author Claude
 * @date 2025-10-26
 */
@IsTest
private class RealTimeValidator_Test {

    /**
     * @description Setup des données de test
     */
    @TestSetup
    static void setup() {
        // Créer des comptes de test
        List<Account> accounts = new List<Account>();

        for (Integer i = 0; i < 10; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Industry = 'Technology',
                Website = 'https://example.com'
            ));
        }

        insert accounts;
    }

    // ========== RealTimeValidator Tests ==========

    @IsTest
    static void testValidation Rule_Required() {
        Account acc = new Account(Name = null);

        RealTimeValidator.ValidationRule rule = new RealTimeValidator.ValidationRule(
            'Name_Required',
            'Name',
            'REQUIRED'
        );
        rule.errorMessage = 'Name is required';
        rule.severity = 'Error';

        Test.startTest();

        List<SObject> records = new List<SObject>{acc};
        List<RealTimeValidator.ValidationRule> rules = new List<RealTimeValidator.ValidationRule>{rule};

        RealTimeValidator.ValidationResult result =
            RealTimeValidator.validateRecords(records, rules);

        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Validation should fail');
        System.assertEquals(1, result.violationsFound, 'Should find 1 violation');
        System.assertEquals(1, result.violations.size(), 'Should have 1 violation');
        System.assertEquals('Name', result.violations[0].fieldName, 'Violation should be on Name field');
    }

    @IsTest
    static void testValidationRule_Format_Email() {
        Account acc = new Account(
            Name = 'Test',
            Website = 'invalid-email'
        );
        insert acc;

        RealTimeValidator.ValidationRule rule = new RealTimeValidator.ValidationRule(
            'Website_Format',
            'Website',
            'FORMAT'
        );
        rule.regexPattern = '^https?://.*';
        rule.errorMessage = 'Invalid URL format';
        rule.severity = 'Warning';

        Test.startTest();

        List<SObject> records = [SELECT Id, Website FROM Account WHERE Id = :acc.Id];
        List<RealTimeValidator.ValidationRule> rules = new List<RealTimeValidator.ValidationRule>{rule};

        RealTimeValidator.ValidationResult result =
            RealTimeValidator.validateRecords(records, rules);

        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Validation should fail');
        System.assertEquals(1, result.violationsFound, 'Should find 1 violation');
    }

    @IsTest
    static void testValidationRule_Range() {
        Account acc = new Account(
            Name = 'Test',
            AnnualRevenue = 50000
        );
        insert acc;

        RealTimeValidator.ValidationRule rule = new RealTimeValidator.ValidationRule(
            'Revenue_Range',
            'AnnualRevenue',
            'RANGE'
        );
        rule.minValue = 100000;
        rule.maxValue = 10000000;
        rule.errorMessage = 'Revenue must be between 100K and 10M';
        rule.severity = 'Warning';

        Test.startTest();

        List<SObject> records = [SELECT Id, AnnualRevenue FROM Account WHERE Id = :acc.Id];
        List<RealTimeValidator.ValidationRule> rules = new List<RealTimeValidator.ValidationRule>{rule};

        RealTimeValidator.ValidationResult result =
            RealTimeValidator.validateRecords(records, rules);

        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Validation should fail');
        System.assertEquals(1, result.violationsFound, 'Should find 1 violation');
    }

    @IsTest
    static void testValidationRule_Custom() {
        Account acc = new Account(
            Name = 'Test',
            Industry = 'Technology'
        );
        insert acc;

        RealTimeValidator.ValidationRule rule = new RealTimeValidator.ValidationRule(
            'Custom_Rule',
            'Industry',
            'CUSTOM'
        );
        rule.formula = 'Industry == "Banking"';
        rule.errorMessage = 'Industry should be Banking';
        rule.severity = 'Info';

        Test.startTest();

        List<SObject> records = [SELECT Id, Industry FROM Account WHERE Id = :acc.Id];
        List<RealTimeValidator.ValidationRule> rules = new List<RealTimeValidator.ValidationRule>{rule};

        RealTimeValidator.ValidationResult result =
            RealTimeValidator.validateRecords(records, rules);

        Test.stopTest();

        // La formule retourne true si Industry == "Banking", donc ici false (pas de violation)
        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testValidateRecords_MultipleRules() {
        Account acc = new Account(
            Name = null,
            Website = 'invalid'
        );

        List<RealTimeValidator.ValidationRule> rules = new List<RealTimeValidator.ValidationRule>{
            new RealTimeValidator.ValidationRule('Name_Required', 'Name', 'REQUIRED'),
            new RealTimeValidator.ValidationRule('Website_Format', 'Website', 'FORMAT')
        };
        rules[1].regexPattern = '^https?://.*';

        Test.startTest();

        RealTimeValidator.ValidationResult result =
            RealTimeValidator.validateRecords(new List<SObject>{acc}, rules);

        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Validation should fail');
        System.assertEquals(2, result.violationsFound, 'Should find 2 violations');
    }

    @IsTest
    static void testValidateAsync() {
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 5];

        RealTimeValidator.ValidationRule rule = new RealTimeValidator.ValidationRule(
            'Name_Required',
            'Name',
            'REQUIRED'
        );

        Test.startTest();

        Id jobId = RealTimeValidator.validateAsync(
            accounts,
            new List<RealTimeValidator.ValidationRule>{rule},
            'Account'
        );

        Test.stopTest();

        System.assertNotEquals(null, jobId, 'Job ID should not be null');
    }

    @IsTest
    static void testValidateAndFix() {
        // Créer un compte avec null
        Account acc = new Account(Name = 'Test', Industry = null);
        insert acc;

        // Créer une règle REQUIRED
        RealTimeValidator.ValidationRule rule = new RealTimeValidator.ValidationRule(
            'Industry_Required',
            'Industry',
            'REQUIRED'
        );

        List<Account> accounts = [SELECT Id, Industry FROM Account WHERE Id = :acc.Id];

        Test.startTest();

        RealTimeValidator.ValidationResult result =
            RealTimeValidator.validateAndFix(
                accounts,
                new List<RealTimeValidator.ValidationRule>{rule},
                true
            );

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testCreateStandardRules() {
        Test.startTest();

        List<RealTimeValidator.ValidationRule> rules =
            RealTimeValidator.createStandardRules('Account');

        Test.stopTest();

        System.assertNotEquals(null, rules, 'Rules should not be null');
        System.assertNotEquals(0, rules.size(), 'Should create standard rules');

        // Vérifier qu'il y a une règle pour Name (requis)
        Boolean hasNameRule = false;
        for (RealTimeValidator.ValidationRule rule : rules) {
            if (rule.fieldName == 'Name' && rule.validationType == 'REQUIRED') {
                hasNameRule = true;
                break;
            }
        }
        System.assertEquals(true, hasNameRule, 'Should have Name required rule');
    }

    @IsTest
    static void testGetViolationSummary() {
        RealTimeValidator.ValidationResult result = new RealTimeValidator.ValidationResult();

        RealTimeValidator.ValidationRule rule1 = new RealTimeValidator.ValidationRule('R1', 'F1', 'REQUIRED');
        rule1.severity = 'Error';

        RealTimeValidator.ValidationRule rule2 = new RealTimeValidator.ValidationRule('R2', 'F2', 'FORMAT');
        rule2.severity = 'Warning';

        RealTimeValidator.ValidationRule rule3 = new RealTimeValidator.ValidationRule('R3', 'F3', 'RANGE');
        rule3.severity = 'Critical';

        result.violations.add(new RealTimeValidator.ValidationViolation(null, rule1));
        result.violations.add(new RealTimeValidator.ValidationViolation(null, rule2));
        result.violations.add(new RealTimeValidator.ValidationViolation(null, rule3));

        Test.startTest();

        Map<String, Integer> summary = RealTimeValidator.getViolationSummary(result);

        Test.stopTest();

        System.assertEquals(0, summary.get('Info'), 'Should have 0 Info');
        System.assertEquals(1, summary.get('Warning'), 'Should have 1 Warning');
        System.assertEquals(1, summary.get('Error'), 'Should have 1 Error');
        System.assertEquals(1, summary.get('Critical'), 'Should have 1 Critical');
    }

    @IsTest
    static void testValidationRule() {
        RealTimeValidator.ValidationRule rule = new RealTimeValidator.ValidationRule(
            'Test_Rule',
            'TestField',
            'REQUIRED'
        );

        System.assertEquals('Test_Rule', rule.ruleName, 'Rule name should match');
        System.assertEquals('TestField', rule.fieldName, 'Field name should match');
        System.assertEquals('REQUIRED', rule.validationType, 'Validation type should match');
        System.assertEquals('Error', rule.severity, 'Default severity should be Error');

        rule.errorMessage = 'Test error';
        rule.severity = 'Warning';
        rule.minValue = 0;
        rule.maxValue = 100;
        rule.regexPattern = '^test$';

        System.assertEquals('Test error', rule.errorMessage, 'Error message should match');
        System.assertEquals('Warning', rule.severity, 'Severity should be updated');
        System.assertEquals(0, rule.minValue, 'Min value should match');
        System.assertEquals(100, rule.maxValue, 'Max value should match');
        System.assertEquals('^test$', rule.regexPattern, 'Regex pattern should match');
    }

    @IsTest
    static void testValidationResult() {
        RealTimeValidator.ValidationResult result = new RealTimeValidator.ValidationResult();

        System.assertEquals(true, result.isValid, 'Default isValid should be true');
        System.assertEquals(0, result.recordsValidated, 'Default recordsValidated should be 0');
        System.assertEquals(0, result.violationsFound, 'Default violationsFound should be 0');
        System.assertNotEquals(null, result.violations, 'Violations list should not be null');
        System.assertEquals(0, result.violations.size(), 'Violations list should be empty');

        result.isValid = false;
        result.recordsValidated = 10;
        result.violationsFound = 5;

        System.assertEquals(false, result.isValid, 'Should update isValid');
        System.assertEquals(10, result.recordsValidated, 'Should update recordsValidated');
        System.assertEquals(5, result.violationsFound, 'Should update violationsFound');
    }

    @IsTest
    static void testValidationViolation() {
        RealTimeValidator.ValidationRule rule = new RealTimeValidator.ValidationRule(
            'Test_Rule',
            'TestField',
            'REQUIRED'
        );
        rule.errorMessage = 'Test error';
        rule.severity = 'Critical';

        Account acc = new Account(Name = 'Test');
        insert acc;

        RealTimeValidator.ValidationViolation violation =
            new RealTimeValidator.ValidationViolation(acc.Id, rule);

        System.assertEquals(acc.Id, violation.recordId, 'Record ID should match');
        System.assertEquals('Test_Rule', violation.ruleName, 'Rule name should match');
        System.assertEquals('TestField', violation.fieldName, 'Field name should match');
        System.assertEquals('REQUIRED', violation.violationType, 'Violation type should match');
        System.assertEquals('Test error', violation.errorMessage, 'Error message should match');
        System.assertEquals('Critical', violation.severity, 'Severity should match');

        violation.actualValue = 'actual';
        violation.expectedValue = 'expected';

        System.assertEquals('actual', violation.actualValue, 'Actual value should match');
        System.assertEquals('expected', violation.expectedValue, 'Expected value should match');
    }

    // ========== DataQualityTriggerHandler Tests ==========

    @IsTest
    static void testTriggerHandler_Config() {
        DataQualityTriggerHandler.HandlerConfig config = new DataQualityTriggerHandler.HandlerConfig();

        System.assertEquals(true, config.validateOnInsert, 'Default validateOnInsert should be true');
        System.assertEquals(true, config.validateOnUpdate, 'Default validateOnUpdate should be true');
        System.assertEquals(false, config.autoFixEnabled, 'Default autoFixEnabled should be false');
        System.assertEquals(true, config.publishEvents, 'Default publishEvents should be true');
        System.assertEquals(false, config.asyncValidation, 'Default asyncValidation should be false');

        config.validateOnInsert = false;
        config.autoFixEnabled = true;

        System.assertEquals(false, config.validateOnInsert, 'Should update validateOnInsert');
        System.assertEquals(true, config.autoFixEnabled, 'Should update autoFixEnabled');
    }

    @IsTest
    static void testTriggerHandler_CreateDefault() {
        Test.startTest();

        DataQualityTriggerHandler handler = DataQualityTriggerHandler.createDefault('Account');

        Test.stopTest();

        System.assertNotEquals(null, handler, 'Handler should not be null');
    }

    @IsTest
    static void testTriggerHandler_RegisterRules() {
        RealTimeValidator.ValidationRule rule = new RealTimeValidator.ValidationRule(
            'Test_Rule',
            'Name',
            'REQUIRED'
        );

        Test.startTest();

        DataQualityTriggerHandler.registerValidationRules(
            'Account',
            new List<RealTimeValidator.ValidationRule>{rule}
        );

        Test.stopTest();

        // Les règles sont enregistrées dans une variable statique
        // Pas de moyen direct de vérifier, mais on peut créer un handler et voir s'il les utilise
    }

    @IsTest
    static void testTriggerHandler_DisableEnable() {
        Test.startTest();

        DataQualityTriggerHandler.disableForObject('Account');
        // Vérifier que la désactivation fonctionne (pas de validation)

        DataQualityTriggerHandler.enableForObject('Account');
        // Vérifier que la réactivation fonctionne

        Test.stopTest();

        // Ces méthodes modifient des variables statiques
        // Difficile de tester directement sans trigger réel
    }

    @IsTest
    static void testTriggerHandler_Instance() {
        DataQualityTriggerHandler.HandlerConfig config = new DataQualityTriggerHandler.HandlerConfig();
        config.validateOnInsert = true;

        DataQualityTriggerHandler handler = new DataQualityTriggerHandler(config);

        Test.startTest();

        handler.disable();
        // Handler est maintenant désactivé

        handler.enable();
        // Handler est réactivé

        Test.stopTest();

        System.assertNotEquals(null, handler, 'Handler should exist');
    }

    @IsTest
    static void testTriggerContext_Enum() {
        DataQualityTriggerHandler.TriggerContext beforeInsert =
            DataQualityTriggerHandler.TriggerContext.BEFORE_INSERT;
        DataQualityTriggerHandler.TriggerContext beforeUpdate =
            DataQualityTriggerHandler.TriggerContext.BEFORE_UPDATE;
        DataQualityTriggerHandler.TriggerContext afterInsert =
            DataQualityTriggerHandler.TriggerContext.AFTER_INSERT;

        System.assertNotEquals(null, beforeInsert, 'BEFORE_INSERT should exist');
        System.assertNotEquals(null, beforeUpdate, 'BEFORE_UPDATE should exist');
        System.assertNotEquals(null, afterInsert, 'AFTER_INSERT should exist');
    }

    // ========== Integration Tests ==========

    @IsTest
    static void testEndToEndValidation() {
        // Créer des règles de validation
        List<RealTimeValidator.ValidationRule> rules = new List<RealTimeValidator.ValidationRule>{
            new RealTimeValidator.ValidationRule('Name_Required', 'Name', 'REQUIRED')
        };

        // Enregistrer les règles
        DataQualityTriggerHandler.registerValidationRules('Account', rules);

        // Créer un compte invalide
        Account invalidAcc = new Account(Name = null);

        Test.startTest();

        // Valider directement
        RealTimeValidator.ValidationResult result =
            RealTimeValidator.validateRecords(new List<SObject>{invalidAcc}, rules);

        // Vérifier le résumé
        Map<String, Integer> summary = RealTimeValidator.getViolationSummary(result);

        Test.stopTest();

        System.assertEquals(false, result.isValid, 'Validation should fail');
        System.assertEquals(1, result.violationsFound, 'Should find 1 violation');
        System.assertNotEquals(null, summary, 'Summary should not be null');
    }

    @IsTest
    static void testValidationWithMultipleRecords() {
        List<Account> accounts = new List<Account>();

        // Mix de valid et invalid
        accounts.add(new Account(Name = 'Valid Account'));
        accounts.add(new Account(Name = null)); // Invalid
        accounts.add(new Account(Name = 'Another Valid'));

        RealTimeValidator.ValidationRule rule = new RealTimeValidator.ValidationRule(
            'Name_Required',
            'Name',
            'REQUIRED'
        );

        Test.startTest();

        RealTimeValidator.ValidationResult result =
            RealTimeValidator.validateRecords(accounts, new List<RealTimeValidator.ValidationRule>{rule});

        Test.stopTest();

        System.assertEquals(3, result.recordsValidated, 'Should validate 3 records');
        System.assertEquals(1, result.violationsFound, 'Should find 1 violation');
        System.assertEquals(1, result.violations.size(), 'Should have 1 violation');
    }

    @IsTest
    static void testValidationWithNoRules() {
        List<Account> accounts = [SELECT Id, Name FROM Account LIMIT 5];

        Test.startTest();

        RealTimeValidator.ValidationResult result =
            RealTimeValidator.validateRecords(accounts, new List<RealTimeValidator.ValidationRule>());

        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Should be valid with no rules');
        System.assertEquals(0, result.violationsFound, 'Should find no violations');
    }

    @IsTest
    static void testValidationWithNullRecords() {
        Test.startTest();

        RealTimeValidator.ValidationResult result =
            RealTimeValidator.validateRecords(null, new List<RealTimeValidator.ValidationRule>());

        Test.stopTest();

        System.assertEquals(true, result.isValid, 'Should be valid with null records');
        System.assertEquals(0, result.recordsValidated, 'Should validate 0 records');
    }

    @IsTest
    static void testStandardRulesForDifferentObjects() {
        Test.startTest();

        List<RealTimeValidator.ValidationRule> accountRules =
            RealTimeValidator.createStandardRules('Account');

        List<RealTimeValidator.ValidationRule> contactRules =
            RealTimeValidator.createStandardRules('Contact');

        Test.stopTest();

        System.assertNotEquals(null, accountRules, 'Account rules should not be null');
        System.assertNotEquals(null, contactRules, 'Contact rules should not be null');
    }
}
