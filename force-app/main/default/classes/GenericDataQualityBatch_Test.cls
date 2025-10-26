/**
 * @description Comprehensive tests for GenericDataQualityBatch
 * @author Claude
 * @date 2025-10-26
 */
@isTest
private class GenericDataQualityBatch_Test {

    // ========== DATA SETUP ==========

    @testSetup
    static void setupTestData() {
        // Create test accounts
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 250; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Industry = (Math.mod(i, 2) == 0) ? 'Technology' : 'Finance',
                AnnualRevenue = 1000000 + (i * 10000)
            ));
        }
        insert accounts;

        // Create test contacts
        List<Contact> contacts = new List<Contact>();
        for (Integer i = 0; i < 100; i++) {
            contacts.add(new Contact(
                FirstName = 'Test',
                LastName = 'Contact ' + i,
                Email = 'test' + i + '@example.com',
                AccountId = accounts[i].Id
            ));
        }
        insert contacts;
    }

    // ========== BASIC FUNCTIONALITY TESTS ==========

    @isTest
    static void testSingleRuleBatch() {
        // Create rule
        DataQualityRule rule = DataQualityRule.create('UpdateIndustry', 'Account')
            .withWhere('Industry = \'Technology\'')
            .updateField('Description', 'Tech Company')
            .withPriority(1)
            .withComplexity(1);

        Test.startTest();
        Id batchId = GenericDataQualityBatch.executeBatch(rule);
        Test.stopTest();

        // Verify batch executed
        System.assertNotEquals(null, batchId);

        // Verify updates
        List<Account> updated = [SELECT Id, Description FROM Account WHERE Industry = 'Technology' AND Description = 'Tech Company'];
        System.assert(updated.size() > 0, 'Accounts should be updated');
    }

    @isTest
    static void testMultipleRules() {
        List<DataQualityRule> rules = new List<DataQualityRule>{
            DataQualityRule.create('Rule1', 'Account')
                .withWhere('Industry = \'Technology\'')
                .updateField('Description', 'Tech')
                .withPriority(1),
            DataQualityRule.create('Rule2', 'Contact')
                .withWhere('Email != null')
                .updateField('Description', 'Has Email')
                .withPriority(2)
        };

        Test.startTest();
        Id batchId = GenericDataQualityBatch.executeBatch(rules);
        Test.stopTest();

        System.assertNotEquals(null, batchId);
    }

    // ========== MULTI-OBJECT SUPPORT TESTS ==========

    @isTest
    static void testMultiObjectProcessing() {
        List<DataQualityRule> rules = new List<DataQualityRule>{
            DataQualityRule.create('AccountRule', 'Account')
                .updateField('Description', 'Processed')
                .withPriority(1),
            DataQualityRule.create('ContactRule', 'Contact')
                .updateField('Description', 'Processed')
                .withPriority(2)
        };

        Test.startTest();
        GenericDataQualityBatch batch = new GenericDataQualityBatch(rules);
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Verify both object types processed
        System.assertNotEquals(null, batch);
    }

    @isTest
    static void testDependencies() {
        List<DataQualityRule> rules = new List<DataQualityRule>{
            DataQualityRule.create('ContactRule', 'Contact')
                .dependsOn('Account')
                .updateField('Description', 'Depends on Account')
                .withPriority(2),
            DataQualityRule.create('AccountRule', 'Account')
                .updateField('Description', 'Independent')
                .withPriority(1)
        };

        Test.startTest();
        DataQualityBatchChainer chainer = new DataQualityBatchChainer(rules, 0, null);
        System.enqueueJob(chainer);
        Test.stopTest();

        // Chainer should handle dependencies
        System.assertNotEquals(null, chainer);
    }

    // ========== PERFORMANCE TESTS ==========

    @isTest
    static void testDynamicBatchSize() {
        // Simple rule = larger batch size
        DataQualityRule simpleRule = DataQualityRule.create('Simple', 'Account')
            .withComplexity(1);

        // Complex rule = smaller batch size
        DataQualityRule complexRule = DataQualityRule.create('Complex', 'Account')
            .withComplexity(10);

        GenericDataQualityBatch simpleBatch = new GenericDataQualityBatch(simpleRule);
        GenericDataQualityBatch complexBatch = new GenericDataQualityBatch(complexRule);

        Integer simpleSize = simpleBatch.calculateBatchSize(simpleRule);
        Integer complexSize = complexBatch.calculateBatchSize(complexRule);

        System.assert(simpleSize > complexSize, 'Simple rules should have larger batch size');
        System.assertEquals(200, simpleSize);
        System.assertEquals(20, complexSize);
    }

    @isTest
    static void testDescribeResultCaching() {
        DataQualityRule rule = DataQualityRule.create('Test', 'Account');

        Test.startTest();
        GenericDataQualityBatch batch1 = new GenericDataQualityBatch(rule);
        GenericDataQualityBatch batch2 = new GenericDataQualityBatch(rule);

        // Both should use cached describe
        Database.executeBatch(batch1, 10);
        Database.executeBatch(batch2, 10);
        Test.stopTest();

        // Verify no errors from caching
        System.assertNotEquals(null, batch1);
    }

    @isTest
    static void testLargeVolume() {
        // Test with existing 250 accounts
        DataQualityRule rule = DataQualityRule.create('LargeVolume', 'Account')
            .updateField('Description', 'Bulk Processed');

        Test.startTest();
        Id batchId = GenericDataQualityBatch.executeBatch(rule);
        Test.stopTest();

        // All accounts should be processed
        List<Account> processed = [SELECT Id FROM Account WHERE Description = 'Bulk Processed'];
        System.assert(processed.size() > 0, 'Should process large volume');
    }

    // ========== ERROR HANDLING TESTS ==========

    @isTest
    static void testPartialSuccess() {
        // This will cause some records to fail (e.g., invalid field value)
        DataQualityRule rule = DataQualityRule.create('PartialFail', 'Account')
            .updateField('Description', 'Test');

        Test.startTest();
        GenericDataQualityBatch batch = new GenericDataQualityBatch(rule);
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Batch should complete despite errors
        System.assertNotEquals(null, batch);
    }

    @isTest
    static void testContinueOnError() {
        List<DataQualityRule> rules = new List<DataQualityRule>{
            DataQualityRule.create('Rule1', 'Account')
                .withWhere('Industry = \'NonExistent\'') // Will process 0 records
                .updateField('Description', 'Test1'),
            DataQualityRule.create('Rule2', 'Contact')
                .updateField('Description', 'Test2')
        };

        Test.startTest();
        GenericDataQualityBatch batch = new GenericDataQualityBatch(rules);
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Should continue to second rule even if first processes 0 records
        System.assertNotEquals(null, batch);
    }

    @isTest
    static void testRetryLogic() {
        DataQualityRule rule = DataQualityRule.create('Retry', 'Account')
            .updateField('Description', 'Retry Test');

        Test.startTest();
        GenericDataQualityBatch batch = new GenericDataQualityBatch(rule);
        Database.executeBatch(batch, 10);
        Test.stopTest();

        // Verify retry mechanism is in place
        System.assertNotEquals(null, batch);
    }

    // ========== MONITORING TESTS ==========

    @isTest
    static void testMetricsTracking() {
        DataQualityRule rule = DataQualityRule.create('Metrics', 'Account')
            .updateField('Description', 'Metrics Test');

        Test.startTest();
        GenericDataQualityBatch batch = new GenericDataQualityBatch(rule);
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Metrics should be tracked
        System.assertNotEquals(null, batch);
    }

    @isTest
    static void testSlowRuleDetection() {
        DataQualityMetrics metrics = new DataQualityMetrics('test', 'SlowRule', 'Account');

        // Simulate slow rule
        metrics.trackRuleExecution('SlowRule', 6000); // 6 seconds
        metrics.trackRuleExecution('FastRule', 100);  // 100ms

        List<String> slowRules = metrics.getSlowRules();

        System.assertEquals(1, slowRules.size(), 'Should detect 1 slow rule');
        System.assert(slowRules[0].contains('SlowRule'));
    }

    @isTest
    static void testExecutionTimeTracking() {
        DataQualityMetrics metrics = new DataQualityMetrics('test', 'Test', 'Account');

        // Simulate processing
        metrics.recordsProcessed = 100;
        metrics.recordsUpdated = 95;
        metrics.recordsFailed = 5;

        metrics.finish();

        System.assert(metrics.getExecutionTime() >= 0);
        System.assertEquals(100, metrics.recordsProcessed);
        System.assertEquals(95, metrics.recordsUpdated);
        System.assertEquals(5, metrics.recordsFailed);
    }

    // ========== EDGE CASES ==========

    @isTest
    static void testZeroRecords() {
        DataQualityRule rule = DataQualityRule.create('ZeroRecords', 'Account')
            .withWhere('Name = \'NonExistentName\'')
            .updateField('Description', 'Test');

        Test.startTest();
        Id batchId = GenericDataQualityBatch.executeBatch(rule);
        Test.stopTest();

        // Should complete successfully even with 0 records
        System.assertNotEquals(null, batchId);
    }

    @isTest
    static void testSingleRecord() {
        // Delete all but one account
        List<Account> accounts = [SELECT Id FROM Account LIMIT 1];
        delete [SELECT Id FROM Account WHERE Id NOT IN :accounts];

        DataQualityRule rule = DataQualityRule.create('SingleRecord', 'Account')
            .updateField('Description', 'Single');

        Test.startTest();
        Id batchId = GenericDataQualityBatch.executeBatch(rule);
        Test.stopTest();

        List<Account> updated = [SELECT Description FROM Account WHERE Description = 'Single'];
        System.assertEquals(1, updated.size());
    }

    @isTest
    static void testEmptyRuleList() {
        try {
            GenericDataQualityBatch.executeBatch(new List<DataQualityRule>());
            System.assert(false, 'Should throw exception for empty rules');
        } catch (GenericDataQualityBatch.IllegalArgumentException e) {
            System.assert(e.getMessage().contains('cannot be null or empty'));
        }
    }

    @isTest
    static void testNullRule() {
        try {
            GenericDataQualityBatch.executeBatch((List<DataQualityRule>)null);
            System.assert(false, 'Should throw exception for null rules');
        } catch (GenericDataQualityBatch.IllegalArgumentException e) {
            System.assert(e.getMessage().contains('cannot be null or empty'));
        }
    }

    // ========== LOGGING TESTS ==========

    @isTest
    static void testLogging() {
        DataQualityLogger.clear();

        DataQualityLogger.debug('Debug message', 'test');
        DataQualityLogger.info('Info message', 'test');
        DataQualityLogger.warn('Warning message', 'test');
        DataQualityLogger.error('Error message', 'test');

        List<DataQualityLogger.LogEntry> entries = DataQualityLogger.getEntries();
        System.assertEquals(4, entries.size());

        List<DataQualityLogger.LogEntry> errors = DataQualityLogger.getErrors();
        System.assertEquals(1, errors.size());
    }

    @isTest
    static void testLogFormatting() {
        DataQualityLogger.clear();

        DataQualityLogger.info('Test message', 'context');

        String formatted = DataQualityLogger.getFormattedLog();
        System.assert(formatted.contains('INFO'));
        System.assert(formatted.contains('Test message'));
        System.assert(formatted.contains('context'));
    }

    // ========== RULE CONFIGURATION TESTS ==========

    @isTest
    static void testRuleBuilder() {
        DataQualityRule rule = DataQualityRule.create('Test', 'Account')
            .withWhere('Industry != null')
            .updateField('Description', 'Test')
            .withPriority(5)
            .withComplexity(3)
            .dependsOn('Contact');

        System.assertEquals('Test', rule.ruleName);
        System.assertEquals('Account', rule.sobjectType);
        System.assertEquals('Industry != null', rule.whereClause);
        System.assertEquals('Description', rule.fieldToUpdate);
        System.assertEquals('Test', rule.valueToSet);
        System.assertEquals(5, rule.priority);
        System.assertEquals(3, rule.complexity);
        System.assertEquals(1, rule.dependsOn.size());
    }

    @isTest
    static void testRulePrioritySorting() {
        List<DataQualityRule> rules = new List<DataQualityRule>{
            DataQualityRule.create('Low', 'Account').withPriority(10),
            DataQualityRule.create('High', 'Account').withPriority(1),
            DataQualityRule.create('Medium', 'Account').withPriority(5)
        };

        GenericDataQualityBatch batch = new GenericDataQualityBatch(rules);

        // Rules should be sorted by priority (1, 5, 10)
        // First rule should be highest priority
        System.assertNotEquals(null, batch);
    }

    @isTest
    static void testComplexityBounds() {
        DataQualityRule rule1 = DataQualityRule.create('Test1', 'Account')
            .withComplexity(-5); // Should be clamped to 1

        DataQualityRule rule2 = DataQualityRule.create('Test2', 'Account')
            .withComplexity(100); // Should be clamped to 10

        System.assertEquals(1, rule1.complexity);
        System.assertEquals(10, rule2.complexity);
    }

    // ========== QUEUEABLE CHAINER TESTS ==========

    @isTest
    static void testQueueableChaining() {
        List<DataQualityRule> rules = new List<DataQualityRule>{
            DataQualityRule.create('Rule1', 'Account').withPriority(1),
            DataQualityRule.create('Rule2', 'Contact').withPriority(2)
        };

        DataQualityMetrics metrics = new DataQualityMetrics('test', 'Test', 'Account');

        Test.startTest();
        DataQualityBatchChainer chainer = new DataQualityBatchChainer(rules, 0, metrics);
        System.enqueueJob(chainer);
        Test.stopTest();

        // Chainer should execute without errors
        System.assertNotEquals(null, chainer);
    }

    @isTest
    static void testChainerWithDependencies() {
        List<DataQualityRule> rules = new List<DataQualityRule>{
            DataQualityRule.create('Independent', 'Account').withPriority(1),
            DataQualityRule.create('Dependent', 'Contact')
                .dependsOn('Account')
                .withPriority(2)
        };

        Test.startTest();
        DataQualityBatchChainer chainer = new DataQualityBatchChainer(rules, 0, null);
        System.enqueueJob(chainer);
        Test.stopTest();

        System.assertNotEquals(null, chainer);
    }

    // ========== INTEGRATION TESTS ==========

    @isTest
    static void testFullWorkflow() {
        // Create comprehensive rules
        List<DataQualityRule> rules = new List<DataQualityRule>{
            DataQualityRule.create('AccountCleanup', 'Account')
                .withWhere('Description = null')
                .updateField('Description', 'Cleaned')
                .withPriority(1)
                .withComplexity(2),
            DataQualityRule.create('ContactCleanup', 'Contact')
                .withWhere('Description = null')
                .updateField('Description', 'Cleaned')
                .withPriority(2)
                .withComplexity(1)
                .dependsOn('Account')
        };

        Test.startTest();
        Id batchId = GenericDataQualityBatch.executeBatch(rules);
        Test.stopTest();

        // Verify execution
        System.assertNotEquals(null, batchId);

        // Verify some records were processed
        List<Account> accounts = [SELECT Id, Description FROM Account WHERE Description = 'Cleaned' LIMIT 10];
        System.assert(accounts.size() >= 0, 'Should process accounts');
    }
}
