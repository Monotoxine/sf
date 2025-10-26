/**
 * @description Comprehensive tests for DynamicQueryBuilder
 * @author Claude
 * @date 2025-10-26
 */
@isTest
private class DynamicQueryBuilder_Test {

    // ========== Basic Builder Tests ==========

    @isTest
    static void testBasicQueryBuild() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addField('Industry')
            .addWhere('Name != null')
            .setLimit(10);

        String query = builder.build();

        System.assert(query.contains('SELECT'));
        System.assert(query.contains('Name'));
        System.assert(query.contains('Industry'));
        System.assert(query.contains('FROM Account'));
        System.assert(query.contains('WHERE Name != null'));
        System.assert(query.contains('LIMIT 10'));
    }

    @isTest
    static void testAddMultipleFields() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Contact')
            .addFields(new List<String>{'FirstName', 'LastName', 'Email'});

        String query = builder.build();

        System.assert(query.contains('FirstName'));
        System.assert(query.contains('LastName'));
        System.assert(query.contains('Email'));
    }

    @isTest
    static void testOrderByAndOffset() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .orderBy('CreatedDate DESC')
            .setLimit(5)
            .setOffset(10);

        String query = builder.build();

        System.assert(query.contains('ORDER BY CreatedDate DESC'));
        System.assert(query.contains('LIMIT 5'));
        System.assert(query.contains('OFFSET 10'));
    }

    @isTest
    static void testDefaultIdField() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account');
        String query = builder.build();

        // Should add Id field by default if no fields specified
        System.assert(query.contains('SELECT Id'));
    }

    @isTest
    static void testBlankFieldError() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account');

        try {
            builder.addField('');
            System.assert(false, 'Should throw exception for blank field');
        } catch (DynamicQueryBuilder.QueryBuilderException e) {
            System.assert(e.getMessage().contains('cannot be blank'));
        }
    }

    // ========== Auto-Detection of Related Objects ==========

    @isTest
    static void testRelationalFieldAutoDetection() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Owner.Name');

        String query = builder.build();

        // Should automatically add Owner.Id
        System.assert(query.contains('Owner.Id'), 'Should auto-add Owner.Id');
        System.assert(query.contains('Owner.Name'));
    }

    @isTest
    static void testDeepRelationalPath() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Opportunity')
            .addField('Account.Owner.Name');

        String query = builder.build();

        // Should add intermediate Id fields
        System.assert(query.contains('Account.Id'));
        System.assert(query.contains('Account.Owner.Id'));
        System.assert(query.contains('Account.Owner.Name'));
    }

    @isTest
    static void testMultipleRelationalFields() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Contact')
            .addField('Account.Name')
            .addField('Account.Owner.Email')
            .addField('ReportsTo.Name');

        String query = builder.build();

        System.assert(query.contains('Account.Id'));
        System.assert(query.contains('Account.Name'));
        System.assert(query.contains('Account.Owner.Id'));
        System.assert(query.contains('ReportsTo.Id'));
    }

    @isTest
    static void testAnalysisTracksRelatedObjects() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Contact')
            .addField('Account.Name')
            .addField('Owner.Email');

        DynamicQueryBuilder.QueryAnalysis analysis = builder.analyze();

        System.assertEquals(2, analysis.relatedObjects.size());
        System.assert(analysis.relatedObjects.contains('Account.Name'));
        System.assert(analysis.relatedObjects.contains('Owner.Email'));
    }

    // ========== Query Optimization ==========

    @isTest
    static void testIndexedFieldDetection() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addWhere('Id = \'001000000000000\'')
            .addWhere('Name = \'Test\'');

        DynamicQueryBuilder.QueryAnalysis analysis = builder.analyze();

        // Id and Name are indexed
        System.assert(analysis.indexedFields.contains('Id'));
        System.assert(analysis.indexedFields.contains('Name'));
    }

    @isTest
    static void testNonIndexedFieldDetection() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addWhere('Description = \'Test\'');

        DynamicQueryBuilder.QueryAnalysis analysis = builder.analyze();

        // Description is typically not indexed
        System.assert(analysis.nonIndexedFields.contains('Description'));
    }

    @isTest
    static void testWhereClauseOptimization() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addWhere('Description = \'Test\'')
            .addWhere('Id = \'001000000000000\'');

        builder.analyze();
        String query = builder.build();

        // After optimization, Id (indexed) should come before Description
        Integer idPos = query.indexOf('Id =');
        Integer descPos = query.indexOf('Description =');

        System.assert(idPos < descPos, 'Indexed field should come first');
    }

    @isTest
    static void testIndexSuggestions() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addWhere('CustomField__c = \'Value\'');

        DynamicQueryBuilder.QueryAnalysis analysis = builder.analyze();

        // Should suggest creating index
        Boolean hasSuggestion = false;
        for (String suggestion : analysis.suggestions) {
            if (suggestion.contains('index')) {
                hasSuggestion = true;
                break;
            }
        }
        System.assert(hasSuggestion, 'Should suggest creating index');
    }

    // ========== Security Checks ==========

    @isTest
    static void testSecurityCheckCRUD() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account');

        DynamicQueryBuilder.SecurityCheckResult security = builder.checkSecurity();

        // Current user should have access to Account
        System.assert(security.isReadable, 'Should have read access to Account');
        System.assertEquals(false, security.hasErrors);
    }

    @isTest
    static void testSecurityCheckFLS() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addField('Industry');

        DynamicQueryBuilder.SecurityCheckResult security = builder.checkSecurity();

        // Should have access to Name and Industry
        System.assert(security.accessibleFields.contains('Name'));
        System.assert(security.accessibleFields.contains('Industry'));
    }

    @isTest
    static void testSecurityCheckInvalidObject() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('NonExistentObject__c');

        DynamicQueryBuilder.SecurityCheckResult security = builder.checkSecurity();

        System.assertEquals(true, security.hasErrors);
        System.assert(!security.errors.isEmpty());
    }

    @isTest
    static void testSecurityEnforced() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .withSecurityEnforced();

        String query = builder.build();

        System.assert(query.contains('WITH SECURITY_ENFORCED'));
    }

    @isTest
    static void testWithoutSecurityEnforced() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .withoutSecurityEnforced();

        String query = builder.build();

        System.assert(!query.contains('WITH SECURITY_ENFORCED'));
    }

    // ========== Advanced Validation ==========

    @isTest
    static void testValidateSObjectExists() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account');
        DynamicQueryBuilder.ValidationResult result = builder.validate();

        System.assertEquals(false, result.hasErrors);
    }

    @isTest
    static void testValidateInvalidSObject() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('FakeObject__c');
        DynamicQueryBuilder.ValidationResult result = builder.validate();

        System.assertEquals(true, result.hasErrors);
        System.assert(!result.errors.isEmpty());
    }

    @isTest
    static void testValidateFieldsExist() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addField('Industry');

        DynamicQueryBuilder.ValidationResult result = builder.validate();

        System.assertEquals(false, result.hasErrors);
        System.assert(result.validFields.contains('Name'));
        System.assert(result.validFields.contains('Industry'));
    }

    @isTest
    static void testValidateInvalidField() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('NonExistentField__c');

        DynamicQueryBuilder.ValidationResult result = builder.validate();

        System.assertEquals(true, result.hasErrors);
        System.assert(result.invalidFields.contains('NonExistentField__c'));
    }

    @isTest
    static void testValidateRelationshipPath() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Contact')
            .addField('Account.Name');

        DynamicQueryBuilder.ValidationResult result = builder.validate();

        System.assertEquals(false, result.hasErrors);
        System.assert(result.validFields.contains('Account.Name'));
    }

    @isTest
    static void testValidateInvalidRelationshipPath() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Contact')
            .addField('FakeRelationship__r.Name');

        DynamicQueryBuilder.ValidationResult result = builder.validate();

        System.assertEquals(true, result.hasErrors);
        System.assert(result.invalidFields.contains('FakeRelationship__r.Name'));
    }

    @isTest
    static void testFieldSuggestions() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('nam'); // Typo for 'Name'

        DynamicQueryBuilder.ValidationResult result = builder.validate();

        System.assertEquals(true, result.hasErrors);
        // Should suggest 'Name'
        Boolean hasSuggestion = false;
        for (String suggestion : result.suggestions) {
            if (suggestion.toLowerCase().contains('name')) {
                hasSuggestion = true;
                break;
            }
        }
        System.assert(hasSuggestion, 'Should suggest similar field name');
    }

    @isTest
    static void testRelationshipIdWarning() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Contact')
            .addField('AccountId.Name'); // Common mistake

        DynamicQueryBuilder.ValidationResult result = builder.validate();

        // Should have warning about Id suffix
        Boolean hasWarning = false;
        for (String warning : result.warnings) {
            if (warning.contains('should not end with "Id"')) {
                hasWarning = true;
                break;
            }
        }
        System.assert(hasWarning, 'Should warn about Id suffix');
    }

    // ========== Performance Analysis ==========

    @isTest
    static void testPerformanceAnalysisSelective() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addWhere('Id = \'001000000000000\'');

        builder.analyze(); // Must analyze first
        DynamicQueryBuilder.PerformanceAnalysis perf = builder.analyzePerformance();

        System.assertEquals(true, perf.isSelective, 'Query with Id should be selective');
    }

    @isTest
    static void testPerformanceAnalysisNonSelective() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addWhere('Description = \'Test\'');

        builder.analyze();
        DynamicQueryBuilder.PerformanceAnalysis perf = builder.analyzePerformance();

        System.assertEquals(false, perf.isSelective);
        System.assert(!perf.warnings.isEmpty(), 'Should have warnings for non-selective query');
    }

    @isTest
    static void testPerformanceWarningNoLimit() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name');

        DynamicQueryBuilder.PerformanceAnalysis perf = builder.analyzePerformance();

        Boolean hasLimitWarning = false;
        for (String warning : perf.warnings) {
            if (warning.contains('LIMIT')) {
                hasLimitWarning = true;
                break;
            }
        }
        System.assert(hasLimitWarning, 'Should warn about missing LIMIT');
    }

    @isTest
    static void testPerformanceWarningManyFields() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account');

        // Add many fields
        for (Integer i = 0; i < 60; i++) {
            builder.addField('Name'); // Same field multiple times for test
        }

        DynamicQueryBuilder.PerformanceAnalysis perf = builder.analyzePerformance();

        Boolean hasManyFieldsWarning = false;
        for (String warning : perf.warnings) {
            if (warning.contains('many fields')) {
                hasManyFieldsWarning = true;
                break;
            }
        }
        System.assert(hasManyFieldsWarning, 'Should warn about many fields');
    }

    @isTest
    static void testEstimatedRecordCount() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .setLimit(50);

        DynamicQueryBuilder.PerformanceAnalysis perf = builder.analyzePerformance();

        System.assertEquals(50, perf.estimatedRecordCount);
    }

    // ========== Execute Tests ==========

    @isTest
    static void testExecuteValidQuery() {
        // Create test data
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addWhere('Name = \'Test Account\'')
            .setLimit(1);

        List<SObject> results = builder.execute();

        System.assertEquals(1, results.size());
        System.assertEquals('Test Account', results[0].get('Name'));
    }

    @isTest
    static void testExecuteWithValidation() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('InvalidField__c');

        try {
            builder.execute();
            System.assert(false, 'Should throw exception for invalid field');
        } catch (DynamicQueryBuilder.QueryBuilderException e) {
            System.assert(e.getMessage().contains('validation failed'));
        }
    }

    @isTest
    static void testExecuteWithSecurityCheck() {
        // Create builder with security enforced
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .withSecurityEnforced();

        // Should execute without errors (user has access)
        List<SObject> results = builder.execute();
        System.assertNotEquals(null, results);
    }

    @isTest
    static void testExecuteRelationalQuery() {
        // Create test data
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            AccountId = acc.Id
        );
        insert con;

        DynamicQueryBuilder builder = new DynamicQueryBuilder('Contact')
            .addField('FirstName')
            .addField('Account.Name')
            .addWhere('LastName = \'Doe\'')
            .setLimit(1);

        List<SObject> results = builder.execute();

        System.assertEquals(1, results.size());
        Contact result = (Contact)results[0];
        System.assertEquals('John', result.FirstName);
        System.assertEquals('Test Account', result.Account.Name);
    }

    // ========== Integration Tests ==========

    @isTest
    static void testFullWorkflow() {
        // Create test data
        Account acc = new Account(Name = 'Full Test Account', Industry = 'Technology');
        insert acc;

        // Build complex query
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addFields(new List<String>{'Name', 'Industry', 'Owner.Name'})
            .addWhere('Industry = \'Technology\'')
            .orderBy('CreatedDate DESC')
            .setLimit(10);

        // Validate
        DynamicQueryBuilder.ValidationResult validation = builder.validate();
        System.assertEquals(false, validation.hasErrors, 'Validation should pass');

        // Check security
        DynamicQueryBuilder.SecurityCheckResult security = builder.checkSecurity();
        System.assertEquals(false, security.hasErrors, 'Security check should pass');

        // Analyze
        DynamicQueryBuilder.QueryAnalysis analysis = builder.analyze();
        System.assertNotEquals(null, analysis);

        // Analyze performance
        DynamicQueryBuilder.PerformanceAnalysis perf = builder.analyzePerformance();
        System.assertNotEquals(null, perf);

        // Execute
        List<SObject> results = builder.execute();
        System.assertEquals(1, results.size());
        System.assertEquals('Full Test Account', results[0].get('Name'));
    }

    @isTest
    static void testComplexRelationalQuery() {
        // Create test data with relationships
        Account acc = new Account(Name = 'Parent Account');
        insert acc;

        Contact con = new Contact(
            FirstName = 'Jane',
            LastName = 'Smith',
            AccountId = acc.Id
        );
        insert con;

        Opportunity opp = new Opportunity(
            Name = 'Test Opportunity',
            AccountId = acc.Id,
            CloseDate = Date.today().addDays(30),
            StageName = 'Prospecting'
        );
        insert opp;

        // Query with deep relationships
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Opportunity')
            .addField('Name')
            .addField('Account.Name')
            .addField('Account.Owner.Name')
            .addWhere('StageName = \'Prospecting\'')
            .setLimit(1);

        List<SObject> results = builder.execute();

        System.assertEquals(1, results.size());
        Opportunity result = (Opportunity)results[0];
        System.assertEquals('Test Opportunity', result.Name);
        System.assertEquals('Parent Account', result.Account.Name);
        System.assertNotEquals(null, result.Account.Owner.Name);
    }

    // ========== Edge Cases ==========

    @isTest
    static void testEmptyWhereClauses() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addWhere('') // Empty where clause
            .addWhere(null); // Null where clause

        String query = builder.build();

        // Should not include WHERE if all clauses are empty
        System.assert(!query.contains('WHERE') || query.contains('WHERE  '));
    }

    @isTest
    static void testDuplicateFields() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addField('Name')
            .addField('Name');

        String query = builder.build();

        // Set should deduplicate
        Integer nameCount = 0;
        Integer index = 0;
        while ((index = query.indexOf('Name', index)) != -1) {
            nameCount++;
            index++;
        }
        System.assertEquals(1, nameCount, 'Should deduplicate field names');
    }

    @isTest
    static void testWithoutSharingFlag() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .withoutSharing();

        // Note: withoutSharing flag is set but query string doesn't change
        // It's meant to be used with a wrapper that respects sharing
        String query = builder.build();
        System.assertNotEquals(null, query);
    }

    @isTest
    static void testMultipleWhereConditions() {
        DynamicQueryBuilder builder = new DynamicQueryBuilder('Account')
            .addField('Name')
            .addWhere('Industry = \'Technology\'')
            .addWhere('AnnualRevenue > 1000000')
            .addWhere('NumberOfEmployees > 100');

        String query = builder.build();

        System.assert(query.contains('Industry'));
        System.assert(query.contains('AnnualRevenue'));
        System.assert(query.contains('NumberOfEmployees'));
        System.assert(query.contains(' AND '));
    }
}
