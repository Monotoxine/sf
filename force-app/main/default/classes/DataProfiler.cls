/**
 * @description Analyse statistique approfondie des données pour profiling
 * @author Claude
 * @date 2025-10-26
 */
public with sharing class DataProfiler {

    /**
     * @description Profil de données d'un champ
     */
    public class FieldProfile {
        public String fieldName { get; set; }
        public String fieldType { get; set; }
        public Integer totalRecords { get; set; }
        public Integer nullCount { get; set; }
        public Integer distinctValues { get; set; }
        public Decimal nullPercentage { get; set; }
        public Decimal uniquenessRatio { get; set; }

        // Statistiques numériques
        public Decimal minValue { get; set; }
        public Decimal maxValue { get; set; }
        public Decimal mean { get; set; }
        public Decimal median { get; set; }
        public Decimal stdDev { get; set; }

        // Distribution
        public Map<Object, Integer> valueDistribution { get; set; }
        public List<Object> topValues { get; set; }

        // Qualité
        public Decimal qualityScore { get; set; }
        public List<String> issues { get; set; }
        public List<String> recommendations { get; set; }

        public FieldProfile() {
            this.valueDistribution = new Map<Object, Integer>();
            this.topValues = new List<Object>();
            this.issues = new List<String>();
            this.recommendations = new List<String>();
        }
    }

    /**
     * @description Profile un champ spécifique
     */
    public static FieldProfile profileField(String sobjectType, String fieldName) {
        FieldProfile profile = new FieldProfile();
        profile.fieldName = fieldName;

        // Compter le total
        String countQuery = 'SELECT COUNT() total FROM ' + sobjectType;
        Integer total = (Integer)Database.query(countQuery)[0].get('total');
        profile.totalRecords = total;

        // Distribution des valeurs
        String query = 'SELECT ' + fieldName + ', COUNT(Id) cnt FROM ' + sobjectType +
                      ' GROUP BY ' + fieldName + ' ORDER BY COUNT(Id) DESC LIMIT 100';

        List<AggregateResult> results = Database.query(query);

        Integer nullCount = 0;
        List<Decimal> numericValues = new List<Decimal>();

        for (AggregateResult ar : results) {
            Object value = ar.get(fieldName);
            Integer count = (Integer)ar.get('cnt');

            if (value == null) {
                nullCount = count;
            } else {
                profile.valueDistribution.put(value, count);
                profile.topValues.add(value);

                // Collecter les valeurs numériques
                try {
                    numericValues.add(Decimal.valueOf(String.valueOf(value)));
                } catch (Exception e) {
                    // Non-numérique, ignorer
                }
            }
        }

        profile.nullCount = nullCount;
        profile.distinctValues = results.size() - (nullCount > 0 ? 1 : 0);
        profile.nullPercentage = total > 0 ? ((Decimal)nullCount / total) * 100 : 0;
        profile.uniquenessRatio = total > 0 ? (Decimal)profile.distinctValues / total : 0;

        // Statistiques numériques
        if (!numericValues.isEmpty()) {
            calculateNumericStats(profile, numericValues);
        }

        // Score de qualité
        calculateQualityScore(profile);

        // Recommandations
        generateRecommendations(profile);

        return profile;
    }

    /**
     * @description Calcule les statistiques numériques
     */
    private static void calculateNumericStats(FieldProfile profile, List<Decimal> values) {
        if (values.isEmpty()) return;

        // Min/Max
        profile.minValue = values[0];
        profile.maxValue = values[0];
        Decimal sum = 0;

        for (Decimal value : values) {
            if (value < profile.minValue) profile.minValue = value;
            if (value > profile.maxValue) profile.maxValue = value;
            sum += value;
        }

        // Moyenne
        profile.mean = sum / values.size();

        // Écart-type
        Decimal sumSquares = 0;
        for (Decimal value : values) {
            Decimal diff = value - profile.mean;
            sumSquares += diff * diff;
        }
        profile.stdDev = Math.sqrt(sumSquares / values.size());

        // Médiane
        values.sort();
        Integer middle = values.size() / 2;
        if (Math.mod(values.size(), 2) == 0) {
            profile.median = (values[middle - 1] + values[middle]) / 2;
        } else {
            profile.median = values[middle];
        }
    }

    /**
     * @description Calcule le score de qualité (0-100)
     */
    private static void calculateQualityScore(FieldProfile profile) {
        Decimal score = 100;

        // Pénalité pour NULL
        if (profile.nullPercentage > 50) {
            score -= 40;
            profile.issues.add('High NULL rate: ' + profile.nullPercentage.setScale(2) + '%');
        } else if (profile.nullPercentage > 20) {
            score -= 20;
            profile.issues.add('Moderate NULL rate: ' + profile.nullPercentage.setScale(2) + '%');
        } else if (profile.nullPercentage > 10) {
            score -= 10;
        }

        // Pénalité pour faible diversité
        if (profile.uniquenessRatio < 0.1 && profile.distinctValues > 1) {
            score -= 20;
            profile.issues.add('Low diversity: only ' + profile.distinctValues + ' distinct values');
        }

        // Pénalité pour dispersion élevée
        if (profile.uniquenessRatio > 0.8 && profile.totalRecords > 100) {
            score -= 15;
            profile.issues.add('High dispersion: ' + (profile.uniquenessRatio * 100).setScale(2) + '% unique');
        }

        profile.qualityScore = Math.max(0, score);
    }

    /**
     * @description Génère des recommandations
     */
    private static void generateRecommendations(FieldProfile profile) {
        if (profile.nullPercentage > 20) {
            profile.recommendations.add('Consider making field required or set default value');
        }

        if (profile.distinctValues > 0 && profile.distinctValues < 10) {
            profile.recommendations.add('Convert to picklist with values: ' +
                String.join((List<String>)profile.topValues, ', '));
        }

        if (profile.uniquenessRatio > 0.9) {
            profile.recommendations.add('Consider using this field as unique identifier');
        }

        if (profile.stdDev != null && profile.mean != null && profile.mean > 0) {
            Decimal cv = (profile.stdDev / profile.mean) * 100;
            if (cv > 50) {
                profile.recommendations.add('High variability detected (CV=' + cv.setScale(2) + '%), consider data validation');
            }
        }
    }

    /**
     * @description Profile tous les champs d'un objet
     */
    public static Map<String, FieldProfile> profileObject(String sobjectType, List<String> fieldNames) {
        Map<String, FieldProfile> profiles = new Map<String, FieldProfile>();

        for (String fieldName : fieldNames) {
            try {
                FieldProfile profile = profileField(sobjectType, fieldName);
                profiles.put(fieldName, profile);
            } catch (Exception e) {
                System.debug('Error profiling field ' + fieldName + ': ' + e.getMessage());
            }
        }

        return profiles;
    }
}
