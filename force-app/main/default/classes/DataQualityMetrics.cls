/**
 * @description Metrics tracking for Data Quality batch jobs
 * @author Claude
 * @date 2025-10-26
 */
public class DataQualityMetrics {

    public String batchId { get; set; }
    public String ruleName { get; set; }
    public String sobjectType { get; set; }
    public Long startTime { get; set; }
    public Long endTime { get; set; }
    public Integer recordsProcessed { get; set; }
    public Integer recordsUpdated { get; set; }
    public Integer recordsFailed { get; set; }
    public Integer soqlQueries { get; set; }
    public Integer dmlStatements { get; set; }
    public List<String> errors { get; set; }
    public Map<String, Long> ruleExecutionTimes { get; set; }

    public DataQualityMetrics(String batchId, String ruleName, String sobjectType) {
        this.batchId = batchId;
        this.ruleName = ruleName;
        this.sobjectType = sobjectType;
        this.startTime = System.currentTimeMillis();
        this.recordsProcessed = 0;
        this.recordsUpdated = 0;
        this.recordsFailed = 0;
        this.soqlQueries = Limits.getQueries();
        this.dmlStatements = Limits.getDmlStatements();
        this.errors = new List<String>();
        this.ruleExecutionTimes = new Map<String, Long>();
    }

    /**
     * @description Marks the end of processing
     */
    public void finish() {
        this.endTime = System.currentTimeMillis();
        this.soqlQueries = Limits.getQueries() - this.soqlQueries;
        this.dmlStatements = Limits.getDmlStatements() - this.dmlStatements;
    }

    /**
     * @description Gets execution time in milliseconds
     */
    public Long getExecutionTime() {
        if (endTime == null) {
            return System.currentTimeMillis() - startTime;
        }
        return endTime - startTime;
    }

    /**
     * @description Adds error to metrics
     */
    public void addError(String error) {
        errors.add(error);
        recordsFailed++;
    }

    /**
     * @description Tracks rule execution time
     */
    public void trackRuleExecution(String ruleName, Long executionTime) {
        ruleExecutionTimes.put(ruleName, executionTime);
    }

    /**
     * @description Detects slow rules (> 5 seconds)
     */
    public List<String> getSlowRules() {
        List<String> slowRules = new List<String>();
        for (String rule : ruleExecutionTimes.keySet()) {
            if (ruleExecutionTimes.get(rule) > 5000) {
                slowRules.add(rule + ' (' + ruleExecutionTimes.get(rule) + 'ms)');
            }
        }
        return slowRules;
    }

    /**
     * @description Returns summary string
     */
    public String getSummary() {
        List<String> parts = new List<String>();
        parts.add('Batch: ' + batchId);
        parts.add('Rule: ' + ruleName);
        parts.add('Object: ' + sobjectType);
        parts.add('Execution Time: ' + getExecutionTime() + 'ms');
        parts.add('Records Processed: ' + recordsProcessed);
        parts.add('Records Updated: ' + recordsUpdated);
        parts.add('Records Failed: ' + recordsFailed);
        parts.add('SOQL Queries: ' + soqlQueries);
        parts.add('DML Statements: ' + dmlStatements);

        if (!errors.isEmpty()) {
            parts.add('Errors: ' + errors.size());
        }

        List<String> slowRules = getSlowRules();
        if (!slowRules.isEmpty()) {
            parts.add('Slow Rules: ' + String.join(slowRules, ', '));
        }

        return String.join(parts, ' | ');
    }
}
