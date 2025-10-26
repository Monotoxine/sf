/**
 * @description Tests pour le système Smart Auto-Fix
 * Couvre ViolationPatternAnalyzer, SmartAutoFix, et ValuePredictor
 * @author Claude
 * @date 2025-10-26
 */
@IsTest
private class SmartAutoFix_Test {

    /**
     * @description Setup des données de test
     */
    @TestSetup
    static void setup() {
        // Créer des comptes avec différents patterns de données
        List<Account> accounts = new List<Account>();

        // Pattern 1: NULL values (haute fréquence)
        for (Integer i = 0; i < 50; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Industry = null,
                Description = null
            ));
        }

        // Pattern 2: Valeurs communes
        for (Integer i = 50; i < 80; i++) {
            accounts.add(new Account(
                Name = 'Tech Company ' + i,
                Industry = 'Technology',
                Description = 'Technology company'
            ));
        }

        // Pattern 3: Whitespace issues
        for (Integer i = 80; i < 90; i++) {
            accounts.add(new Account(
                Name = '  Whitespace Account ' + i + '  ',
                Industry = 'Technology  ',
                Description = '  Description with spaces  '
            ));
        }

        // Pattern 4: Low diversity
        for (Integer i = 90; i < 100; i++) {
            accounts.add(new Account(
                Name = 'Standard ' + i,
                Industry = 'Technology',
                Description = 'Standard description'
            ));
        }

        insert accounts;
    }

    // ========== ViolationPatternAnalyzer Tests ==========

    @IsTest
    static void testAnalyzeField_HighNullRate() {
        Test.startTest();

        ViolationPatternAnalyzer.AnalysisConfig config = new ViolationPatternAnalyzer.AnalysisConfig();
        config.minFrequency = 1;
        config.includeNullValues = true;

        ViolationPatternAnalyzer.PatternAnalysisResult result =
            ViolationPatternAnalyzer.analyzeField('Account', 'Industry', config);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Industry', result.fieldName, 'Field name should be Industry');
        System.assert(
            result.violationType == 'HIGH_NULL_RATE' || result.violationType == 'MISSING_DATA',
            'Should detect null-related violation: ' + result.violationType
        );
        System.assertNotEquals(null, result.suggestedFix, 'Should suggest a fix');
    }

    @IsTest
    static void testAnalyzeField_DominantValue() {
        Test.startTest();

        ViolationPatternAnalyzer.AnalysisConfig config = new ViolationPatternAnalyzer.AnalysisConfig();

        ViolationPatternAnalyzer.PatternAnalysisResult result =
            ViolationPatternAnalyzer.analyzeField('Account', 'Industry', config);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(!result.commonValues.isEmpty(), 'Should have common values');
    }

    @IsTest
    static void testAnalyzeMultipleFields() {
        Test.startTest();

        ViolationPatternAnalyzer.AnalysisConfig config = new ViolationPatternAnalyzer.AnalysisConfig();
        List<String> fields = new List<String>{'Industry', 'Description'};

        Map<String, ViolationPatternAnalyzer.PatternAnalysisResult> results =
            ViolationPatternAnalyzer.analyzeMultipleFields('Account', fields, config);

        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should analyze 2 fields');
        System.assert(results.containsKey('Industry'), 'Should contain Industry');
        System.assert(results.containsKey('Description'), 'Should contain Description');
    }

    @IsTest
    static void testSuggestValidationRules() {
        Test.startTest();

        List<String> suggestions =
            ViolationPatternAnalyzer.suggestValidationRules('Account', 'Industry');

        Test.stopTest();

        System.assertNotEquals(null, suggestions, 'Suggestions should not be null');
        // Peut être vide si les données ne nécessitent pas de règles
    }

    @IsTest
    static void testAnalyzeTemporalPatterns() {
        Test.startTest();

        Map<String, ViolationPatternAnalyzer.PatternAnalysisResult> results =
            ViolationPatternAnalyzer.analyzeTemporalPatterns('Account', 'Industry', 'CreatedDate', 30);

        Test.stopTest();

        System.assertNotEquals(null, results, 'Results should not be null');
        // Peut être vide selon la période
    }

    @IsTest
    static void testComparePatterns() {
        Test.startTest();

        Map<String, Object> comparison =
            ViolationPatternAnalyzer.comparePatterns('Account', 'Industry', 'CreatedDate', 7, 30);

        Test.stopTest();

        System.assertNotEquals(null, comparison, 'Comparison should not be null');
        System.assert(comparison.containsKey('trend'), 'Should contain trend');
        System.assert(comparison.containsKey('period1Total'), 'Should contain period1Total');
        System.assert(comparison.containsKey('period2Total'), 'Should contain period2Total');
    }

    @IsTest
    static void testAnalysisConfig() {
        ViolationPatternAnalyzer.AnalysisConfig config = new ViolationPatternAnalyzer.AnalysisConfig();

        System.assertEquals(5, config.minFrequency, 'Default minFrequency should be 5');
        System.assertEquals(0.7, config.minConfidence, 'Default minConfidence should be 0.7');
        System.assertEquals(10, config.topValuesCount, 'Default topValuesCount should be 10');
        System.assertEquals(true, config.includeNullValues, 'Default includeNullValues should be true');

        config.minFrequency = 10;
        config.minConfidence = 0.8;

        System.assertEquals(10, config.minFrequency, 'Should update minFrequency');
        System.assertEquals(0.8, config.minConfidence, 'Should update minConfidence');
    }

    // ========== SmartAutoFix Tests ==========

    @IsTest
    static void testAutoFix_NullToDefault() {
        Test.startTest();

        SmartAutoFix.AutoFixConfig config = new SmartAutoFix.AutoFixConfig();
        config.minConfidence = 0.1; // Très bas pour test
        config.dryRun = true; // Test en mode dry run

        SmartAutoFix.FixResult result = SmartAutoFix.autoFix('Account', 'Industry', config);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.fixStrategy, 'Should have a fix strategy');
    }

    @IsTest
    static void testAutoFix_TrimWhitespace() {
        // Créer des comptes avec whitespace
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 10; i++) {
            accounts.add(new Account(
                Name = '  Test  ',
                Industry = 'Technology'
            ));
        }
        insert accounts;

        Test.startTest();

        SmartAutoFix.AutoFixConfig config = new SmartAutoFix.AutoFixConfig();
        config.minConfidence = 0.1;
        config.dryRun = false;
        config.allowedFixTypes = new List<String>{'TRIM_WHITESPACE'};

        SmartAutoFix.FixResult result = SmartAutoFix.autoFix('Account', 'Name', config);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testAutoFixMultipleFields() {
        Test.startTest();

        SmartAutoFix.AutoFixConfig config = new SmartAutoFix.AutoFixConfig();
        config.dryRun = true;
        config.minConfidence = 0.1;

        List<String> fields = new List<String>{'Industry', 'Description'};
        Map<String, SmartAutoFix.FixResult> results =
            SmartAutoFix.autoFixMultipleFields('Account', fields, config);

        Test.stopTest();

        System.assertEquals(2, results.size(), 'Should fix 2 fields');
        System.assert(results.containsKey('Industry'), 'Should contain Industry');
        System.assert(results.containsKey('Description'), 'Should contain Description');
    }

    @IsTest
    static void testGenerateSuggestions() {
        Test.startTest();

        List<String> fields = new List<String>{'Industry', 'Description'};
        List<SmartAutoFix.FixSuggestion> suggestions =
            SmartAutoFix.generateSuggestions('Account', fields);

        Test.stopTest();

        System.assertNotEquals(null, suggestions, 'Suggestions should not be null');
        // Peut être vide selon les patterns détectés
    }

    @IsTest
    static void testApplySuggestion() {
        // Créer un compte avec null
        Account acc = new Account(Name = 'Test', Industry = null);
        insert acc;

        SmartAutoFix.FixSuggestion suggestion = new SmartAutoFix.FixSuggestion(
            'Industry',
            'NULL_TO_DEFAULT',
            'Technology',
            0.8
        );

        Test.startTest();

        SmartAutoFix.AutoFixConfig config = new SmartAutoFix.AutoFixConfig();
        config.dryRun = true;

        SmartAutoFix.FixResult result =
            SmartAutoFix.applySuggestion('Account', suggestion, config);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    @IsTest
    static void testValidateSuggestion() {
        SmartAutoFix.FixSuggestion validSuggestion = new SmartAutoFix.FixSuggestion(
            'Industry',
            'NULL_TO_DEFAULT',
            'Technology',
            0.8
        );

        SmartAutoFix.FixSuggestion invalidSuggestion = new SmartAutoFix.FixSuggestion(
            'InvalidField',
            'NULL_TO_DEFAULT',
            'Value',
            0.8
        );

        Test.startTest();

        Boolean isValid = SmartAutoFix.validateSuggestion('Account', validSuggestion);
        Boolean isInvalid = SmartAutoFix.validateSuggestion('Account', invalidSuggestion);

        Test.stopTest();

        System.assertEquals(true, isValid, 'Valid suggestion should be validated');
        System.assertEquals(false, isInvalid, 'Invalid suggestion should not be validated');
    }

    @IsTest
    static void testAutoFixConfig() {
        SmartAutoFix.AutoFixConfig config = new SmartAutoFix.AutoFixConfig();

        System.assertEquals(0.7, config.minConfidence, 'Default minConfidence should be 0.7');
        System.assertEquals(false, config.dryRun, 'Default dryRun should be false');
        System.assertEquals(200, config.batchSize, 'Default batchSize should be 200');
        System.assertEquals(false, config.autoApprove, 'Default autoApprove should be false');
        System.assertNotEquals(null, config.allowedFixTypes, 'Should have default fix types');

        config.minConfidence = 0.9;
        config.dryRun = true;

        System.assertEquals(0.9, config.minConfidence, 'Should update minConfidence');
        System.assertEquals(true, config.dryRun, 'Should update dryRun');
    }

    @IsTest
    static void testFixResult() {
        SmartAutoFix.FixResult result = new SmartAutoFix.FixResult();

        System.assertEquals(false, result.success, 'Default success should be false');
        System.assertEquals(0, result.recordsAnalyzed, 'Default recordsAnalyzed should be 0');
        System.assertEquals(0, result.recordsFixed, 'Default recordsFixed should be 0');
        System.assertEquals(0, result.recordsFailed, 'Default recordsFailed should be 0');
        System.assertNotEquals(null, result.errors, 'Errors list should not be null');
        System.assertNotEquals(null, result.appliedFixes, 'AppliedFixes map should not be null');
    }

    @IsTest
    static void testFixSuggestion() {
        SmartAutoFix.FixSuggestion suggestion = new SmartAutoFix.FixSuggestion(
            'TestField',
            'NULL_TO_DEFAULT',
            'TestValue',
            0.85
        );

        System.assertEquals('TestField', suggestion.fieldName, 'Field name should match');
        System.assertEquals('NULL_TO_DEFAULT', suggestion.fixType, 'Fix type should match');
        System.assertEquals('TestValue', suggestion.suggestedValue, 'Suggested value should match');
        System.assertEquals(0.85, suggestion.confidence, 'Confidence should match');
    }

    // ========== ValuePredictor Tests ==========

    @IsTest
    static void testPredictKNN() {
        // Créer des données d'entraînement
        List<Account> trainingAccounts = [
            SELECT Id, Name, Industry, AnnualRevenue, NumberOfEmployees
            FROM Account
            WHERE Industry != null
            LIMIT 50
        ];

        ValuePredictor.TrainingData trainingData = new ValuePredictor.TrainingData(
            'Account',
            'Industry',
            new List<String>{'AnnualRevenue', 'NumberOfEmployees'}
        );
        trainingData.samples = trainingAccounts;

        // Record à prédire
        Account testRecord = new Account(
            Name = 'Test',
            AnnualRevenue = 1000000,
            NumberOfEmployees = 50
        );

        Test.startTest();

        ValuePredictor.PredictionConfig config = new ValuePredictor.PredictionConfig();
        config.kNeighbors = 3;

        ValuePredictor.PredictionResult result =
            ValuePredictor.predictKNN(testRecord, trainingData, config);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('K-Nearest Neighbors', result.algorithm, 'Algorithm should be KNN');
        System.assertNotEquals(null, result.reasoning, 'Should have reasoning');
    }

    @IsTest
    static void testPredictNaiveBayes() {
        List<Account> trainingAccounts = [
            SELECT Id, Name, Industry, Type
            FROM Account
            WHERE Industry != null
            LIMIT 50
        ];

        ValuePredictor.TrainingData trainingData = new ValuePredictor.TrainingData(
            'Account',
            'Industry',
            new List<String>{'Type'}
        );
        trainingData.samples = trainingAccounts;

        Account testRecord = new Account(
            Name = 'Test',
            Type = 'Customer - Direct'
        );

        Test.startTest();

        ValuePredictor.PredictionResult result =
            ValuePredictor.predictNaiveBayes(testRecord, trainingData, 'Type');

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Naive Bayes', result.algorithm, 'Algorithm should be Naive Bayes');
    }

    @IsTest
    static void testPredictByCorrelation() {
        // Créer des comptes avec corrélation numérique
        List<Account> accounts = new List<Account>();
        for (Integer i = 1; i <= 20; i++) {
            accounts.add(new Account(
                Name = 'Corr Test ' + i,
                Industry = 'Technology',
                AnnualRevenue = i * 100000,
                NumberOfEmployees = i * 10
            ));
        }
        insert accounts;

        List<Account> trainingAccounts = [
            SELECT Id, AnnualRevenue, NumberOfEmployees
            FROM Account
            WHERE AnnualRevenue != null AND NumberOfEmployees != null
            LIMIT 50
        ];

        ValuePredictor.TrainingData trainingData = new ValuePredictor.TrainingData(
            'Account',
            'NumberOfEmployees',
            new List<String>{'AnnualRevenue'}
        );
        trainingData.samples = trainingAccounts;

        Account testRecord = new Account(
            Name = 'Test',
            AnnualRevenue = 500000
        );

        Test.startTest();

        ValuePredictor.PredictionResult result =
            ValuePredictor.predictByCorrelation(testRecord, trainingData, 'AnnualRevenue');

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Correlation-Based', result.algorithm, 'Algorithm should be Correlation-Based');
    }

    @IsTest
    static void testPredictByAverage() {
        List<Account> trainingAccounts = [
            SELECT Id, AnnualRevenue
            FROM Account
            WHERE AnnualRevenue != null
            LIMIT 50
        ];

        ValuePredictor.TrainingData trainingData = new ValuePredictor.TrainingData(
            'Account',
            'AnnualRevenue',
            new List<String>{}
        );
        trainingData.samples = trainingAccounts;

        Account testRecord = new Account(Name = 'Test');

        Test.startTest();

        ValuePredictor.PredictionResult result =
            ValuePredictor.predictByAverage(testRecord, trainingData);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Average-Based', result.algorithm, 'Algorithm should be Average-Based');
    }

    @IsTest
    static void testPredictEnsemble() {
        List<Account> trainingAccounts = [
            SELECT Id, Industry, Type, AnnualRevenue
            FROM Account
            WHERE Industry != null
            LIMIT 50
        ];

        ValuePredictor.TrainingData trainingData = new ValuePredictor.TrainingData(
            'Account',
            'Industry',
            new List<String>{'Type', 'AnnualRevenue'}
        );
        trainingData.samples = trainingAccounts;

        Account testRecord = new Account(
            Name = 'Test',
            Type = 'Customer - Direct',
            AnnualRevenue = 1000000
        );

        Test.startTest();

        ValuePredictor.PredictionConfig config = new ValuePredictor.PredictionConfig();
        config.minConfidence = 0.1; // Bas pour test

        ValuePredictor.PredictionResult result =
            ValuePredictor.predictEnsemble(testRecord, trainingData, config);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.algorithm, 'Should have an algorithm');
    }

    @IsTest
    static void testPredictionConfig() {
        ValuePredictor.PredictionConfig config = new ValuePredictor.PredictionConfig();

        System.assertEquals('KNN', config.algorithm, 'Default algorithm should be KNN');
        System.assertEquals(5, config.kNeighbors, 'Default kNeighbors should be 5');
        System.assertNotEquals(null, config.features, 'Features list should not be null');
        System.assertEquals(0.6, config.minConfidence, 'Default minConfidence should be 0.6');

        config.algorithm = 'NAIVE_BAYES';
        config.kNeighbors = 10;

        System.assertEquals('NAIVE_BAYES', config.algorithm, 'Should update algorithm');
        System.assertEquals(10, config.kNeighbors, 'Should update kNeighbors');
    }

    @IsTest
    static void testTrainingData() {
        ValuePredictor.TrainingData trainingData = new ValuePredictor.TrainingData(
            'Account',
            'Industry',
            new List<String>{'Type', 'AnnualRevenue'}
        );

        System.assertEquals('Account', trainingData.sobjectType, 'SObject type should match');
        System.assertEquals('Industry', trainingData.targetField, 'Target field should match');
        System.assertEquals(2, trainingData.featureFields.size(), 'Should have 2 features');
        System.assertNotEquals(null, trainingData.samples, 'Samples should not be null');
        System.assertEquals(0, trainingData.samples.size(), 'Should start with 0 samples');
    }

    @IsTest
    static void testPredictionResult() {
        ValuePredictor.PredictionResult result = new ValuePredictor.PredictionResult();

        System.assertEquals(null, result.predictedValue, 'Default predicted value should be null');
        System.assertEquals(null, result.confidence, 'Default confidence should be null');
        System.assertEquals(null, result.algorithm, 'Default algorithm should be null');
        System.assertNotEquals(null, result.alternatives, 'Alternatives map should not be null');
        System.assertEquals(null, result.reasoning, 'Default reasoning should be null');

        result.predictedValue = 'Technology';
        result.confidence = 0.85;
        result.algorithm = 'KNN';

        System.assertEquals('Technology', result.predictedValue, 'Should update predicted value');
        System.assertEquals(0.85, result.confidence, 'Should update confidence');
        System.assertEquals('KNN', result.algorithm, 'Should update algorithm');
    }

    @IsTest
    static void testPredictWithEmptyTrainingData() {
        ValuePredictor.TrainingData emptyData = new ValuePredictor.TrainingData(
            'Account',
            'Industry',
            new List<String>{}
        );

        Account testRecord = new Account(Name = 'Test');
        ValuePredictor.PredictionConfig config = new ValuePredictor.PredictionConfig();

        Test.startTest();

        ValuePredictor.PredictionResult knnResult =
            ValuePredictor.predictKNN(testRecord, emptyData, config);

        ValuePredictor.PredictionResult nbResult =
            ValuePredictor.predictNaiveBayes(testRecord, emptyData, 'Type');

        ValuePredictor.PredictionResult avgResult =
            ValuePredictor.predictByAverage(testRecord, emptyData);

        Test.stopTest();

        System.assertEquals(0, knnResult.confidence, 'KNN should have 0 confidence with no data');
        System.assertEquals(0, nbResult.confidence, 'NB should have 0 confidence with no data');
        System.assertEquals(0, avgResult.confidence, 'Average should have 0 confidence with no data');
    }

    @IsTest
    static void testPredictWithNullValues() {
        List<Account> trainingAccounts = [SELECT Id, Industry FROM Account LIMIT 10];

        ValuePredictor.TrainingData trainingData = new ValuePredictor.TrainingData(
            'Account',
            'Industry',
            new List<String>{'Type'}
        );
        trainingData.samples = trainingAccounts;

        Account testRecord = new Account(Name = 'Test', Type = null);

        Test.startTest();

        ValuePredictor.PredictionResult result =
            ValuePredictor.predictNaiveBayes(testRecord, trainingData, 'Type');

        Test.stopTest();

        System.assertEquals(0, result.confidence, 'Should have 0 confidence with null feature');
    }

    // ========== Integration Tests ==========

    @IsTest
    static void testEndToEndWorkflow() {
        Test.startTest();

        // 1. Analyser les patterns
        ViolationPatternAnalyzer.AnalysisConfig analysisConfig = new ViolationPatternAnalyzer.AnalysisConfig();
        analysisConfig.minConfidence = 0.1;

        ViolationPatternAnalyzer.PatternAnalysisResult pattern =
            ViolationPatternAnalyzer.analyzeField('Account', 'Industry', analysisConfig);

        // 2. Générer des suggestions
        List<SmartAutoFix.FixSuggestion> suggestions =
            SmartAutoFix.generateSuggestions('Account', new List<String>{'Industry'});

        // 3. Appliquer auto-fix en dry run
        SmartAutoFix.AutoFixConfig fixConfig = new SmartAutoFix.AutoFixConfig();
        fixConfig.dryRun = true;
        fixConfig.minConfidence = 0.1;

        SmartAutoFix.FixResult fixResult = SmartAutoFix.autoFix('Account', 'Industry', fixConfig);

        Test.stopTest();

        System.assertNotEquals(null, pattern, 'Pattern analysis should not be null');
        System.assertNotEquals(null, suggestions, 'Suggestions should not be null');
        System.assertNotEquals(null, fixResult, 'Fix result should not be null');
    }

    @IsTest
    static void testPatternAnalysisWithPrediction() {
        // Créer des comptes avec pattern clair
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 30; i++) {
            accounts.add(new Account(
                Name = 'Prediction Test ' + i,
                Industry = 'Technology',
                AnnualRevenue = i * 50000,
                NumberOfEmployees = i * 5
            ));
        }
        insert accounts;

        Test.startTest();

        // Analyser le pattern
        ViolationPatternAnalyzer.AnalysisConfig analysisConfig = new ViolationPatternAnalyzer.AnalysisConfig();
        ViolationPatternAnalyzer.PatternAnalysisResult pattern =
            ViolationPatternAnalyzer.analyzeField('Account', 'Industry', analysisConfig);

        // Utiliser la prédiction pour un nouveau record
        List<Account> trainingData = [
            SELECT Id, Industry, AnnualRevenue, NumberOfEmployees
            FROM Account
            WHERE Industry != null
            LIMIT 50
        ];

        ValuePredictor.TrainingData training = new ValuePredictor.TrainingData(
            'Account',
            'Industry',
            new List<String>{'AnnualRevenue', 'NumberOfEmployees'}
        );
        training.samples = trainingData;

        Account newAccount = new Account(
            Name = 'New',
            AnnualRevenue = 500000,
            NumberOfEmployees = 50
        );

        ValuePredictor.PredictionConfig predConfig = new ValuePredictor.PredictionConfig();
        ValuePredictor.PredictionResult prediction =
            ValuePredictor.predictKNN(newAccount, training, predConfig);

        Test.stopTest();

        System.assertNotEquals(null, pattern, 'Pattern should not be null');
        System.assertNotEquals(null, prediction, 'Prediction should not be null');
    }
}
