/**
 * @description Queueable class to chain Data Quality batches
 * @author Claude
 * @date 2025-10-26
 */
public class DataQualityBatchChainer implements Queueable, Database.AllowsCallouts {

    private List<DataQualityRule> rules;
    private Integer currentIndex;
    private DataQualityMetrics previousMetrics;

    /**
     * @description Constructor
     */
    public DataQualityBatchChainer(List<DataQualityRule> rules, Integer currentIndex, DataQualityMetrics previousMetrics) {
        this.rules = rules;
        this.currentIndex = currentIndex;
        this.previousMetrics = previousMetrics;
    }

    /**
     * @description Execute method
     */
    public void execute(QueueableContext context) {
        if (currentIndex >= rules.size()) {
            DataQualityLogger.info('All batches completed', String.valueOf(context.getJobId()));
            return;
        }

        DataQualityRule nextRule = rules[currentIndex];

        DataQualityLogger.info('Chaining batch for rule: ' + nextRule.ruleName, String.valueOf(context.getJobId()));

        // Check dependencies
        if (!dependenciesMet(nextRule)) {
            DataQualityLogger.warn('Dependencies not met for rule: ' + nextRule.ruleName, String.valueOf(context.getJobId()));
            // Skip to next rule
            currentIndex++;
            if (currentIndex < rules.size()) {
                System.enqueueJob(new DataQualityBatchChainer(rules, currentIndex, previousMetrics));
            }
            return;
        }

        // Execute next batch
        try {
            GenericDataQualityBatch batch = new GenericDataQualityBatch(new List<DataQualityRule>{ nextRule });
            Integer batchSize = batch.calculateBatchSize(nextRule);

            Database.executeBatch(batch, batchSize);

        } catch (Exception e) {
            DataQualityLogger.error(e, String.valueOf(context.getJobId()));

            // Continue to next rule even if this one fails
            currentIndex++;
            if (currentIndex < rules.size()) {
                System.enqueueJob(new DataQualityBatchChainer(rules, currentIndex, previousMetrics));
            }
        }
    }

    /**
     * @description Checks if dependencies are met for a rule
     */
    private Boolean dependenciesMet(DataQualityRule rule) {
        if (rule.dependsOn == null || rule.dependsOn.isEmpty()) {
            return true;
        }

        // Check if all dependent objects have been processed
        for (String dependency : rule.dependsOn) {
            Boolean processed = false;

            for (Integer i = 0; i < currentIndex; i++) {
                if (rules[i].sobjectType == dependency) {
                    processed = true;
                    break;
                }
            }

            if (!processed) {
                return false;
            }
        }

        return true;
    }
}
