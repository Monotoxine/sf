/**
 * @description Export de données en format CSV
 * @author Claude
 * @date 2025-10-26
 */
public with sharing class CSVExporter {

    /**
     * @description Exporte les résultats de profilage en CSV
     */
    public static String exportProfilesCSV(Map<String, DataProfiler.FieldProfile> profiles) {
        String csv = 'Field Name,Quality Score,Total Records,NULL Count,NULL %,Distinct Values,Uniqueness,Issues\n';

        for (String fieldName : profiles.keySet()) {
            DataProfiler.FieldProfile profile = profiles.get(fieldName);

            csv += escapeCSV(profile.fieldName) + ',';
            csv += (profile.qualityScore != null ? String.valueOf(profile.qualityScore.setScale(2)) : '') + ',';
            csv += profile.totalRecords + ',';
            csv += profile.nullCount + ',';
            csv += profile.nullPercentage.setScale(2) + ',';
            csv += profile.distinctValues + ',';
            csv += (profile.uniquenessRatio != null ? String.valueOf(profile.uniquenessRatio.setScale(2)) : '') + ',';
            csv += escapeCSV(String.join(profile.issues, '; ')) + '\n';
        }

        return csv;
    }

    /**
     * @description Exporte les suggestions de règles en CSV
     */
    public static String exportSuggestionsCSV(Map<String, List<RuleSuggestionEngine.RuleSuggestion>> suggestions) {
        String csv = 'Field Name,Rule Name,Rule Type,Formula,Confidence,Severity,Reason\n';

        for (String fieldName : suggestions.keySet()) {
            List<RuleSuggestionEngine.RuleSuggestion> fieldSuggestions = suggestions.get(fieldName);

            for (RuleSuggestionEngine.RuleSuggestion suggestion : fieldSuggestions) {
                csv += escapeCSV(fieldName) + ',';
                csv += escapeCSV(suggestion.ruleName) + ',';
                csv += escapeCSV(suggestion.ruleType) + ',';
                csv += escapeCSV(suggestion.formula) + ',';
                csv += (suggestion.confidence != null ? String.valueOf(suggestion.confidence.setScale(2)) : '') + ',';
                csv += escapeCSV(suggestion.severity) + ',';
                csv += escapeCSV(suggestion.reason) + '\n';
            }
        }

        return csv;
    }

    /**
     * @description Exporte les outliers en CSV
     */
    public static String exportOutliersCSV(OutlierDetector.OutlierResult result, String fieldName) {
        if (result.outliers.isEmpty()) {
            return 'No outliers found\n';
        }

        String csv = 'Record ID,' + fieldName + '\n';

        for (SObject record : result.outliers) {
            csv += record.Id + ',';
            Object value = record.get(fieldName);
            csv += (value != null ? escapeCSV(String.valueOf(value)) : '') + '\n';
        }

        return csv;
    }

    /**
     * @description Exporte un rapport complet en CSV
     */
    public static String exportReportCSV(ReportGenerator.DataQualityReport report) {
        String csv = 'DATA QUALITY REPORT\n';
        csv += 'Report Name,' + escapeCSV(report.reportName) + '\n';
        csv += 'Generated At,' + report.generatedAt.format() + '\n';
        csv += 'Overall Quality Score,' + report.overallQualityScore.setScale(2) + '%\n';
        csv += 'Total Records,' + report.totalRecords + '\n\n';

        if (!report.criticalIssues.isEmpty()) {
            csv += 'CRITICAL ISSUES\n';
            for (String issue : report.criticalIssues) {
                csv += escapeCSV(issue) + '\n';
            }
            csv += '\n';
        }

        csv += 'FIELD PROFILES\n';
        csv += exportProfilesCSV(report.fieldProfiles);
        csv += '\n';

        csv += 'RULE SUGGESTIONS\n';
        csv += exportSuggestionsCSV(report.suggestions);

        return csv;
    }

    /**
     * @description Échappe les caractères spéciaux CSV
     */
    private static String escapeCSV(String value) {
        if (value == null) {
            return '';
        }

        if (value.contains(',') || value.contains('"') || value.contains('\n')) {
            value = '"' + value.replace('"', '""') + '"';
        }

        return value;
    }

    /**
     * @description Crée un ContentVersion pour télécharger le CSV
     */
    public static Id createCSVFile(String csv, String fileName) {
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName + '.csv';
        cv.VersionData = Blob.valueOf(csv);
        cv.IsMajorVersion = true;

        insert cv;

        return cv.Id;
    }
}
