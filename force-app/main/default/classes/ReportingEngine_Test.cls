/**
 * @description Tests pour le Reporting Engine
 * @author Claude
 * @date 2025-10-26
 */
@IsTest
private class ReportingEngine_Test {

    @TestSetup
    static void setup() {
        List<Account> accounts = new List<Account>();

        for (Integer i = 0; i < 20; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Industry = i < 15 ? 'Technology' : null,
                AnnualRevenue = i * 50000
            ));
        }

        insert accounts;
    }

    @IsTest
    static void testGenerateReport() {
        Test.startTest();

        ReportGenerator.DataQualityReport report =
            ReportGenerator.generateReport('Account', new List<String>{'Industry', 'AnnualRevenue'});

        Test.stopTest();

        System.assertNotEquals(null, report, 'Report should not be null');
        System.assertEquals('Account Data Quality Report', report.reportName, 'Report name should match');
        System.assertNotEquals(null, report.overallQualityScore, 'Should have overall score');
        System.assert(report.totalRecords > 0, 'Should have total records');
    }

    @IsTest
    static void testExportHTML() {
        ReportGenerator.DataQualityReport report =
            ReportGenerator.generateReport('Account', new List<String>{'Industry'});

        Test.startTest();

        String html = ReportGenerator.exportHTML(report);

        Test.stopTest();

        System.assertNotEquals(null, html, 'HTML should not be null');
        System.assert(html.contains('<html>'), 'Should contain HTML tag');
        System.assert(html.contains(report.reportName), 'Should contain report name');
    }

    @IsTest
    static void testExportJSON() {
        ReportGenerator.DataQualityReport report =
            ReportGenerator.generateReport('Account', new List<String>{'Industry'});

        Test.startTest();

        String json = ReportGenerator.exportJSON(report);

        Test.stopTest();

        System.assertNotEquals(null, json, 'JSON should not be null');
        System.assert(json.contains('reportName'), 'Should contain reportName');
    }

    @IsTest
    static void testExportProfilesCSV() {
        Map<String, DataProfiler.FieldProfile> profiles =
            DataProfiler.profileObject('Account', new List<String>{'Industry'});

        Test.startTest();

        String csv = CSVExporter.exportProfilesCSV(profiles);

        Test.stopTest();

        System.assertNotEquals(null, csv, 'CSV should not be null');
        System.assert(csv.contains('Field Name'), 'Should contain header');
    }

    @IsTest
    static void testExportSuggestionsCSV() {
        Map<String, List<RuleSuggestionEngine.RuleSuggestion>> suggestions =
            RuleSuggestionEngine.suggestForObject('Account', new List<String>{'Industry'});

        Test.startTest();

        String csv = CSVExporter.exportSuggestionsCSV(suggestions);

        Test.stopTest();

        System.assertNotEquals(null, csv, 'CSV should not be null');
    }

    @IsTest
    static void testExportReportCSV() {
        ReportGenerator.DataQualityReport report =
            ReportGenerator.generateReport('Account', new List<String>{'Industry'});

        Test.startTest();

        String csv = CSVExporter.exportReportCSV(report);

        Test.stopTest();

        System.assertNotEquals(null, csv, 'CSV should not be null');
        System.assert(csv.contains('DATA QUALITY REPORT'), 'Should contain title');
    }

    @IsTest
    static void testCreateCSVFile() {
        String csv = 'Name,Value\nTest,123\n';

        Test.startTest();

        Id cvId = CSVExporter.createCSVFile(csv, 'test-report');

        Test.stopTest();

        System.assertNotEquals(null, cvId, 'ContentVersion ID should not be null');

        ContentVersion cv = [SELECT Title, FileExtension FROM ContentVersion WHERE Id = :cvId];
        System.assertEquals('test-report', cv.Title, 'Title should match');
    }
}
