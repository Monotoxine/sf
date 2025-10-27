/**
 * @description Système de prédiction de valeurs basé sur des algorithmes ML/statistiques
 * Utilise des techniques comme K-Nearest Neighbors, Naive Bayes, et analyse de corrélation
 * @author Claude
 * @date 2025-10-26
 */
public with sharing class ValuePredictor {

    /**
     * @description Résultat de prédiction
     */
    public class PredictionResult {
        public Object predictedValue { get; set; }
        public Decimal confidence { get; set; }
        public String algorithm { get; set; }
        public Map<Object, Decimal> alternatives { get; set; }
        public String reasoning { get; set; }

        public PredictionResult() {
            this.alternatives = new Map<Object, Decimal>();
        }
    }

    /**
     * @description Configuration de prédiction
     */
    public class PredictionConfig {
        public String algorithm { get; set; }  // KNN, NAIVE_BAYES, CORRELATION, AVERAGE
        public Integer kNeighbors { get; set; }
        public List<String> features { get; set; }
        public Decimal minConfidence { get; set; }

        public PredictionConfig() {
            this.algorithm = 'KNN';
            this.kNeighbors = 5;
            this.features = new List<String>();
            this.minConfidence = 0.6;
        }
    }

    /**
     * @description Entraînement du modèle (données de référence)
     */
    public class TrainingData {
        public String sobjectType { get; set; }
        public String targetField { get; set; }
        public List<String> featureFields { get; set; }
        public List<SObject> samples { get; set; }

        public TrainingData(String sobjectType, String targetField, List<String> featureFields) {
            this.sobjectType = sobjectType;
            this.targetField = targetField;
            this.featureFields = featureFields;
            this.samples = new List<SObject>();
        }
    }

    /**
     * @description Prédit une valeur manquante basée sur K-Nearest Neighbors
     * @param record Enregistrement avec valeur manquante
     * @param trainingData Données d'entraînement
     * @param config Configuration
     * @return Résultat de prédiction
     */
    public static PredictionResult predictKNN(
        SObject record,
        TrainingData trainingData,
        PredictionConfig config
    ) {
        PredictionResult result = new PredictionResult();
        result.algorithm = 'K-Nearest Neighbors';

        if (trainingData.samples.isEmpty()) {
            result.confidence = 0;
            result.reasoning = 'No training data available';
            return result;
        }

        // Calculer les distances avec tous les échantillons
        List<DistanceScore> distances = new List<DistanceScore>();

        for (SObject sample : trainingData.samples()) {
            Decimal distance = calculateDistance(record, sample, trainingData.featureFields);
            Object targetValue = sample.get(trainingData.targetField);

            if (targetValue != null) {
                distances.add(new DistanceScore(targetValue, distance));
            }
        }

        // Trier par distance (plus proche en premier)
        distances.sort();

        // Prendre les K plus proches voisins
        Integer k = Math.min(config.kNeighbors, distances.size());
        Map<Object, Integer> valueCounts = new Map<Object, Integer>();
        Decimal totalDistance = 0;

        for (Integer i = 0; i < k; i++) {
            Object value = distances[i].value;
            Decimal distance = distances[i].distance;

            if (!valueCounts.containsKey(value)) {
                valueCounts.put(value, 0);
            }
            valueCounts.put(value, valueCounts.get(value) + 1);
            totalDistance += distance;
        }

        // Trouver la valeur la plus fréquente
        Integer maxCount = 0;
        Object mostFrequent = null;

        for (Object value : valueCounts.keySet()) {
            Integer count = valueCounts.get(value);
            if (count > maxCount) {
                maxCount = count;
                mostFrequent = value;
            }
        }

        result.predictedValue = mostFrequent;
        result.confidence = k > 0 ? (Decimal)maxCount / k : 0;

        // Calculer les alternatives
        for (Object value : valueCounts.keySet()) {
            Decimal probability = k > 0 ? (Decimal)valueCounts.get(value) / k : 0;
            result.alternatives.put(value, probability);
        }

        result.reasoning = 'Based on ' + k + ' nearest neighbors, ' + maxCount + ' have value "' +
                          String.valueOf(mostFrequent) + '"';

        return result;
    }

    /**
     * @description Prédit une valeur basée sur Naive Bayes
     * @param record Enregistrement avec valeur manquante
     * @param trainingData Données d'entraînement
     * @param featureName Feature à utiliser pour la prédiction
     * @return Résultat de prédiction
     */
    public static PredictionResult predictNaiveBayes(
        SObject record,
        TrainingData trainingData,
        String featureName
    ) {
        PredictionResult result = new PredictionResult();
        result.algorithm = 'Naive Bayes';

        if (trainingData.samples.isEmpty()) {
            result.confidence = 0;
            result.reasoning = 'No training data available';
            return result;
        }

        Object featureValue = record.get(featureName);
        if (featureValue == null) {
            result.confidence = 0;
            result.reasoning = 'Feature value is null';
            return result;
        }

        // Calculer P(target|feature) pour chaque valeur cible
        Map<Object, Integer> targetCounts = new Map<Object, Integer>();
        Map<Object, Integer> featureGivenTarget = new Map<Object, Integer>();
        Integer totalSamples = 0;

        for (SObject sample : trainingData.samples) {
            Object targetValue = sample.get(trainingData.targetField);
            Object sampleFeature = sample.get(featureName);

            if (targetValue != null) {
                totalSamples++;

                if (!targetCounts.containsKey(targetValue)) {
                    targetCounts.put(targetValue, 0);
                }
                targetCounts.put(targetValue, targetCounts.get(targetValue) + 1);

                if (sampleFeature == featureValue) {
                    if (!featureGivenTarget.containsKey(targetValue)) {
                        featureGivenTarget.put(targetValue, 0);
                    }
                    featureGivenTarget.put(targetValue, featureGivenTarget.get(targetValue) + 1);
                }
            }
        }

        // Calculer les probabilités
        Decimal maxProbability = 0;
        Object bestTarget = null;

        for (Object targetValue : targetCounts.keySet()) {
            Decimal priorProbability = (Decimal)targetCounts.get(targetValue) / totalSamples;
            Integer featureCount = featureGivenTarget.containsKey(targetValue) ?
                                  featureGivenTarget.get(targetValue) : 0;
            Decimal likelihood = (Decimal)featureCount / targetCounts.get(targetValue);

            Decimal posterior = priorProbability * likelihood;

            result.alternatives.put(targetValue, posterior);

            if (posterior > maxProbability) {
                maxProbability = posterior;
                bestTarget = targetValue;
            }
        }

        result.predictedValue = bestTarget;
        result.confidence = maxProbability;
        result.reasoning = 'P(' + String.valueOf(bestTarget) + '|' + featureName + '=' +
                          String.valueOf(featureValue) + ') = ' + maxProbability.setScale(2);

        return result;
    }

    /**
     * @description Prédit une valeur numérique basée sur la corrélation
     * @param record Enregistrement avec valeur manquante
     * @param trainingData Données d'entraînement
     * @param correlatedField Champ corrélé à utiliser
     * @return Résultat de prédiction
     */
    public static PredictionResult predictByCorrelation(
        SObject record,
        TrainingData trainingData,
        String correlatedField
    ) {
        PredictionResult result = new PredictionResult();
        result.algorithm = 'Correlation-Based';

        Object correlatedValue = record.get(correlatedField);
        if (correlatedValue == null) {
            result.confidence = 0;
            result.reasoning = 'Correlated field value is null';
            return result;
        }

        // Calculer la régression linéaire simple : Y = a + bX
        List<Decimal> xValues = new List<Decimal>();
        List<Decimal> yValues = new List<Decimal>();

        for (SObject sample : trainingData.samples) {
            Object x = sample.get(correlatedField);
            Object y = sample.get(trainingData.targetField);

            if (x != null && y != null) {
                try {
                    xValues.add(Decimal.valueOf(String.valueOf(x)));
                    yValues.add(Decimal.valueOf(String.valueOf(y)));
                } catch (Exception e) {
                    // Ignorer les valeurs non-numériques
                }
            }
        }

        if (xValues.isEmpty() || yValues.isEmpty()) {
            result.confidence = 0;
            result.reasoning = 'Insufficient numeric data';
            return result;
        }

        // Calculer les moyennes
        Decimal xMean = calculateMean(xValues);
        Decimal yMean = calculateMean(yValues);

        // Calculer les coefficients de régression
        Decimal numerator = 0;
        Decimal denominator = 0;

        for (Integer i = 0; i < xValues.size(); i++) {
            Decimal xDiff = xValues[i] - xMean;
            Decimal yDiff = yValues[i] - yMean;
            numerator += xDiff * yDiff;
            denominator += xDiff * xDiff;
        }

        if (denominator == 0) {
            result.confidence = 0;
            result.reasoning = 'No variance in correlated field';
            return result;
        }

        Decimal slope = numerator / denominator;
        Decimal intercept = yMean - (slope * xMean);

        // Prédire la valeur
        Decimal xInput = Decimal.valueOf(String.valueOf(correlatedValue));
        Decimal predicted = intercept + (slope * xInput);

        result.predictedValue = predicted.setScale(2);

        // Calculer R² pour la confiance
        Decimal correlation = calculateCorrelation(xValues, yValues);
        result.confidence = Math.abs(correlation);

        result.reasoning = 'Linear regression: Y = ' + intercept.setScale(2) + ' + ' +
                          slope.setScale(2) + 'X (R² = ' + result.confidence.setScale(2) + ')';

        return result;
    }

    /**
     * @description Prédit une valeur basée sur la moyenne des valeurs similaires
     * @param record Enregistrement avec valeur manquante
     * @param trainingData Données d'entraînement
     * @return Résultat de prédiction
     */
    public static PredictionResult predictByAverage(
        SObject record,
        TrainingData trainingData
    ) {
        PredictionResult result = new PredictionResult();
        result.algorithm = 'Average-Based';

        List<Decimal> values = new List<Decimal>();

        for (SObject sample : trainingData.samples) {
            Object value = sample.get(trainingData.targetField);
            if (value != null) {
                try {
                    values.add(Decimal.valueOf(String.valueOf(value)));
                } catch (Exception e) {
                    // Ignorer les valeurs non-numériques
                }
            }
        }

        if (values.isEmpty()) {
            result.confidence = 0;
            result.reasoning = 'No numeric values found';
            return result;
        }

        Decimal mean = calculateMean(values);
        Decimal stdDev = calculateStandardDeviation(values, mean);

        result.predictedValue = mean.setScale(2);
        result.confidence = stdDev > 0 ? Math.min(1.0, 10.0 / stdDev) : 0.5;
        result.reasoning = 'Mean of ' + values.size() + ' samples (σ = ' + stdDev.setScale(2) + ')';

        return result;
    }

    /**
     * @description Prédit une valeur en utilisant plusieurs algorithmes et retourne le meilleur
     * @param record Enregistrement avec valeur manquante
     * @param trainingData Données d'entraînement
     * @param config Configuration
     * @return Meilleur résultat de prédiction
     */
    public static PredictionResult predictEnsemble(
        SObject record,
        TrainingData trainingData,
        PredictionConfig config
    ) {
        List<PredictionResult> predictions = new List<PredictionResult>();

        // KNN
        try {
            PredictionResult knnResult = predictKNN(record, trainingData, config);
            if (knnResult.confidence >= config.minConfidence) {
                predictions.add(knnResult);
            }
        } catch (Exception e) {
            System.debug('KNN failed: ' + e.getMessage());
        }

        // Naive Bayes (pour chaque feature)
        for (String feature : trainingData.featureFields) {
            try {
                PredictionResult nbResult = predictNaiveBayes(record, trainingData, feature);
                if (nbResult.confidence >= config.minConfidence) {
                    predictions.add(nbResult);
                }
            } catch (Exception e) {
                System.debug('Naive Bayes failed for ' + feature + ': ' + e.getMessage());
            }
        }

        // Correlation (pour chaque feature numérique)
        for (String feature : trainingData.featureFields) {
            try {
                PredictionResult corrResult = predictByCorrelation(record, trainingData, feature);
                if (corrResult.confidence >= config.minConfidence) {
                    predictions.add(corrResult);
                }
            } catch (Exception e) {
                System.debug('Correlation failed for ' + feature + ': ' + e.getMessage());
            }
        }

        // Average
        try {
            PredictionResult avgResult = predictByAverage(record, trainingData);
            if (avgResult.confidence >= config.minConfidence) {
                predictions.add(avgResult);
            }
        } catch (Exception e) {
            System.debug('Average failed: ' + e.getMessage());
        }

        // Retourner le résultat avec la meilleure confiance
        PredictionResult best = new PredictionResult();
        best.confidence = 0;
        best.algorithm = 'Ensemble (no valid predictions)';

        for (PredictionResult pred : predictions) {
            if (pred.confidence > best.confidence) {
                best = pred;
            }
        }

        return best;
    }

    /**
     * @description Classe helper pour stocker les distances
     */
    private class DistanceScore implements Comparable {
        public Object value;
        public Decimal distance;

        public DistanceScore(Object value, Decimal distance) {
            this.value = value;
            this.distance = distance;
        }

        public Integer compareTo(Object other) {
            DistanceScore otherScore = (DistanceScore)other;
            if (this.distance < otherScore.distance) return -1;
            if (this.distance > otherScore.distance) return 1;
            return 0;
        }
    }

    /**
     * @description Calcule la distance euclidienne entre deux enregistrements
     */
    private static Decimal calculateDistance(SObject record1, SObject record2, List<String> features) {
        Decimal sumSquares = 0;
        Integer validFeatures = 0;

        for (String feature : features) {
            Object value1 = record1.get(feature);
            Object value2 = record2.get(feature);

            if (value1 != null && value2 != null) {
                try {
                    Decimal num1 = Decimal.valueOf(String.valueOf(value1));
                    Decimal num2 = Decimal.valueOf(String.valueOf(value2));
                    Decimal diff = num1 - num2;
                    sumSquares += diff * diff;
                    validFeatures++;
                } catch (Exception e) {
                    // Valeur non-numérique, utiliser distance 0 ou 1
                    if (String.valueOf(value1) != String.valueOf(value2)) {
                        sumSquares += 1;
                    }
                    validFeatures++;
                }
            }
        }

        return validFeatures > 0 ? Math.sqrt(sumSquares) : 999999;
    }

    /**
     * @description Calcule la moyenne d'une liste de valeurs
     */
    private static Decimal calculateMean(List<Decimal> values) {
        if (values.isEmpty()) return 0;

        Decimal sum = 0;
        for (Decimal value : values) {
            sum += value;
        }
        return sum / values.size();
    }

    /**
     * @description Calcule l'écart-type
     */
    private static Decimal calculateStandardDeviation(List<Decimal> values, Decimal mean) {
        if (values.isEmpty()) return 0;

        Decimal sumSquares = 0;
        for (Decimal value : values) {
            Decimal diff = value - mean;
            sumSquares += diff * diff;
        }

        return Math.sqrt(sumSquares / values.size());
    }

    /**
     * @description Calcule le coefficient de corrélation de Pearson
     */
    private static Decimal calculateCorrelation(List<Decimal> xValues, List<Decimal> yValues) {
        if (xValues.size() != yValues.size() || xValues.isEmpty()) {
            return 0;
        }

        Decimal xMean = calculateMean(xValues);
        Decimal yMean = calculateMean(yValues);

        Decimal numerator = 0;
        Decimal xDenominator = 0;
        Decimal yDenominator = 0;

        for (Integer i = 0; i < xValues.size(); i++) {
            Decimal xDiff = xValues[i] - xMean;
            Decimal yDiff = yValues[i] - yMean;
            numerator += xDiff * yDiff;
            xDenominator += xDiff * xDiff;
            yDenominator += yDiff * yDiff;
        }

        Decimal denominator = Math.sqrt(xDenominator * yDenominator);
        return denominator > 0 ? numerator / denominator : 0;
    }
}
