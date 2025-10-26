/**
 * @description Détection d'outliers statistiques dans les données
 * @author Claude
 * @date 2025-10-26
 */
public with sharing class OutlierDetector {

    public class OutlierResult {
        public List<SObject> outliers { get; set; }
        public Decimal threshold { get; set; }
        public String method { get; set; }
        public Integer totalRecords { get; set; }
        public Integer outliersFound { get; set; }

        public OutlierResult() {
            this.outliers = new List<SObject>();
        }
    }

    /**
     * @description Détecte les outliers avec la méthode IQR (Interquartile Range)
     */
    public static OutlierResult detectIQR(String sobjectType, String fieldName, Decimal factor) {
        OutlierResult result = new OutlierResult();
        result.method = 'IQR';

        String query = 'SELECT Id, ' + fieldName + ' FROM ' + sobjectType +
                      ' WHERE ' + fieldName + ' != null ORDER BY ' + fieldName;

        List<SObject> records = Database.query(query);
        result.totalRecords = records.size();

        if (records.size() < 4) return result;

        // Calculer Q1 et Q3
        Integer q1Index = records.size() / 4;
        Integer q3Index = (records.size() * 3) / 4;

        Decimal q1 = getDecimalValue(records[q1Index], fieldName);
        Decimal q3 = getDecimalValue(records[q3Index], fieldName);
        Decimal iqr = q3 - q1;

        Decimal lowerBound = q1 - (factor * iqr);
        Decimal upperBound = q3 + (factor * iqr);

        result.threshold = iqr;

        for (SObject record : records) {
            Decimal value = getDecimalValue(record, fieldName);
            if (value < lowerBound || value > upperBound) {
                result.outliers.add(record);
            }
        }

        result.outliersFound = result.outliers.size();
        return result;
    }

    /**
     * @description Détecte les outliers avec écart-type
     */
    public static OutlierResult detectStdDev(String sobjectType, String fieldName, Decimal numStdDevs) {
        OutlierResult result = new OutlierResult();
        result.method = 'Standard Deviation';

        String query = 'SELECT Id, ' + fieldName + ' FROM ' + sobjectType +
                      ' WHERE ' + fieldName + ' != null';

        List<SObject> records = Database.query(query);
        result.totalRecords = records.size();

        if (records.isEmpty()) return result;

        // Calculer moyenne et écart-type
        Decimal sum = 0;
        List<Decimal> values = new List<Decimal>();

        for (SObject record : records) {
            Decimal value = getDecimalValue(record, fieldName);
            values.add(value);
            sum += value;
        }

        Decimal mean = sum / values.size();

        Decimal sumSquares = 0;
        for (Decimal value : values) {
            Decimal diff = value - mean;
            sumSquares += diff * diff;
        }

        Decimal stdDev = Math.sqrt(sumSquares / values.size());
        result.threshold = stdDev;

        Decimal lowerBound = mean - (numStdDevs * stdDev);
        Decimal upperBound = mean + (numStdDevs * stdDev);

        for (SObject record : records) {
            Decimal value = getDecimalValue(record, fieldName);
            if (value < lowerBound || value > upperBound) {
                result.outliers.add(record);
            }
        }

        result.outliersFound = result.outliers.size();
        return result;
    }

    private static Decimal getDecimalValue(SObject record, String fieldName) {
        Object value = record.get(fieldName);
        return value != null ? Decimal.valueOf(String.valueOf(value)) : 0;
    }
}
