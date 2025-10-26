/**
 * @description Génère des rapports de qualité de données dans différents formats
 * @author Claude
 * @date 2025-10-26
 */
public with sharing class ReportGenerator {

    public class DataQualityReport {
        public String reportName { get; set; }
        public String sobjectType { get; set; }
        public DateTime generatedAt { get; set; }
        public Map<String, DataProfiler.FieldProfile> fieldProfiles { get; set; }
        public Map<String, List<RuleSuggestionEngine.RuleSuggestion>> suggestions { get; set; }
        public Decimal overallQualityScore { get; set; }
        public Integer totalRecords { get; set; }
        public List<String> criticalIssues { get; set; }

        public DataQualityReport() {
            this.generatedAt = DateTime.now();
            this.fieldProfiles = new Map<String, DataProfiler.FieldProfile>();
            this.suggestions = new Map<String, List<RuleSuggestionEngine.RuleSuggestion>>();
            this.criticalIssues = new List<String>();
        }
    }

    /**
     * @description Génère un rapport complet
     */
    public static DataQualityReport generateReport(String sobjectType, List<String> fieldNames) {
        DataQualityReport report = new DataQualityReport();
        report.reportName = sobjectType + ' Data Quality Report';
        report.sobjectType = sobjectType;

        // Profiler les champs
        report.fieldProfiles = DataProfiler.profileObject(sobjectType, fieldNames);

        // Générer les suggestions
        report.suggestions = RuleSuggestionEngine.suggestForObject(sobjectType, fieldNames);

        // Calculer le score global
        calculateOverallScore(report);

        // Identifier les problèmes critiques
        identifyCriticalIssues(report);

        return report;
    }

    private static void calculateOverallScore(DataQualityReport report) {
        if (report.fieldProfiles.isEmpty()) {
            report.overallQualityScore = 0;
            return;
        }

        Decimal totalScore = 0;
        Integer count = 0;

        for (DataProfiler.FieldProfile profile : report.fieldProfiles.values()) {
            if (profile.qualityScore != null) {
                totalScore += profile.qualityScore;
                count++;

                if (profile.totalRecords > report.totalRecords) {
                    report.totalRecords = profile.totalRecords;
                }
            }
        }

        report.overallQualityScore = count > 0 ? totalScore / count : 0;
    }

    private static void identifyCriticalIssues(DataQualityReport report) {
        for (String fieldName : report.fieldProfiles.keySet()) {
            DataProfiler.FieldProfile profile = report.fieldProfiles.get(fieldName);

            if (profile.nullPercentage > 50) {
                report.criticalIssues.add(fieldName + ': Critical NULL rate (' + profile.nullPercentage.setScale(1) + '%)');
            }

            if (profile.qualityScore != null && profile.qualityScore < 50) {
                report.criticalIssues.add(fieldName + ': Low quality score (' + profile.qualityScore.setScale(1) + ')');
            }
        }
    }

    /**
     * @description Exporte le rapport en HTML
     */
    public static String exportHTML(DataQualityReport report) {
        String html = '<html><head><style>body{font-family:Arial;}table{border-collapse:collapse;width:100%;}th,td{border:1px solid #ddd;padding:8px;text-align:left;}th{background-color:#4CAF50;color:white;}</style></head><body>';
        html += '<h1>' + report.reportName + '</h1>';
        html += '<p>Generated: ' + report.generatedAt.format() + '</p>';
        html += '<p>Overall Quality Score: <strong>' + report.overallQualityScore.setScale(1) + '%</strong></p>';

        if (!report.criticalIssues.isEmpty()) {
            html += '<h2>Critical Issues</h2><ul>';
            for (String issue : report.criticalIssues) {
                html += '<li>' + issue + '</li>';
            }
            html += '</ul>';
        }

        html += '<h2>Field Profiles</h2><table><tr><th>Field</th><th>Quality Score</th><th>NULL %</th><th>Distinct Values</th><th>Issues</th></tr>';

        for (String fieldName : report.fieldProfiles.keySet()) {
            DataProfiler.FieldProfile profile = report.fieldProfiles.get(fieldName);
            html += '<tr>';
            html += '<td>' + profile.fieldName + '</td>';
            html += '<td>' + (profile.qualityScore != null ? profile.qualityScore.setScale(1) : 'N/A') + '</td>';
            html += '<td>' + profile.nullPercentage.setScale(1) + '%</td>';
            html += '<td>' + profile.distinctValues + '</td>';
            html += '<td>' + String.join(profile.issues, ', ') + '</td>';
            html += '</tr>';
        }

        html += '</table></body></html>';
        return html;
    }

    /**
     * @description Exporte le rapport en JSON
     */
    public static String exportJSON(DataQualityReport report) {
        return JSON.serializePretty(report);
    }
}
