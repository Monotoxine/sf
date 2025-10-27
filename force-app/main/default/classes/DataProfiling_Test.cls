/**
 * @description Tests pour le système Data Profiling
 * @author Claude
 * @date 2025-10-26
 */
@IsTest
private class DataProfiling_Test {

    @TestSetup
    static void setup() {
        List<Account> accounts = new List<Account>();

        // Données avec distribution variée
        for (Integer i = 0; i < 50; i++) {
            accounts.add(new Account(
                Name = 'Account ' + i,
                Industry = i < 30 ? 'Technology' : 'Finance',
                AnnualRevenue = i * 10000,
                NumberOfEmployees = i * 5
            ));
        }

        // Quelques NULL
        for (Integer i = 0; i < 10; i++) {
            accounts.add(new Account(
                Name = 'Null Test ' + i,
                Industry = null,
                AnnualRevenue = null
            ));
        }

        // Outliers
        accounts.add(new Account(
            Name = 'Outlier',
            Industry = 'Technology',
            AnnualRevenue = 10000000,
            NumberOfEmployees = 10000
        ));

        insert accounts;
    }

    @IsTest
    static void testProfileField() {
        Test.startTest();

        DataProfiler.FieldProfile profile = DataProfiler.profileField('Account', 'Industry');

        Test.stopTest();

        System.assertNotEquals(null, profile, 'Profile should not be null');
        System.assertEquals('Industry', profile.fieldName, 'Field name should match');
        System.assert(profile.totalRecords > 0, 'Should have total records');
        System.assertNotEquals(null, profile.qualityScore, 'Should have quality score');
    }

    @IsTest
    static void testProfileObject() {
        Test.startTest();

        Map<String, DataProfiler.FieldProfile> profiles =
            DataProfiler.profileObject('Account', new List<String>{'Industry', 'AnnualRevenue'});

        Test.stopTest();

        System.assertEquals(2, profiles.size(), 'Should profile 2 fields');
        System.assert(profiles.containsKey('Industry'), 'Should contain Industry');
        System.assert(profiles.containsKey('AnnualRevenue'), 'Should contain AnnualRevenue');
    }

    @IsTest
    static void testDetectOutliersIQR() {
        Test.startTest();

        OutlierDetector.OutlierResult result =
            OutlierDetector.detectIQR('Account', 'AnnualRevenue', 1.5);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('IQR', result.method, 'Method should be IQR');
        System.assert(result.totalRecords > 0, 'Should have records');
    }

    @IsTest
    static void testDetectOutliersStdDev() {
        Test.startTest();

        OutlierDetector.OutlierResult result =
            OutlierDetector.detectStdDev('Account', 'AnnualRevenue', 3);

        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertEquals('Standard Deviation', result.method, 'Method should be StdDev');
    }

    @IsTest
    static void testSuggestRules() {
        Test.startTest();

        List<RuleSuggestionEngine.RuleSuggestion> suggestions =
            RuleSuggestionEngine.suggestRules('Account', 'Industry');

        Test.stopTest();

        System.assertNotEquals(null, suggestions, 'Suggestions should not be null');
    }

    @IsTest
    static void testSuggestForObject() {
        Test.startTest();

        Map<String, List<RuleSuggestionEngine.RuleSuggestion>> suggestions =
            RuleSuggestionEngine.suggestForObject('Account', new List<String>{'Industry', 'AnnualRevenue'});

        Test.stopTest();

        System.assertNotEquals(null, suggestions, 'Suggestions should not be null');
    }
}
