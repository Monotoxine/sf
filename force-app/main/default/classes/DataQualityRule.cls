/**
 * @description Configuration class for Data Quality Rules
 * @author Claude
 * @date 2025-10-26
 */
public class DataQualityRule {

    public String ruleName { get; set; }
    public String sobjectType { get; set; }
    public String whereClause { get; set; }
    public String fieldToUpdate { get; set; }
    public Object valueToSet { get; set; }
    public String validationLogic { get; set; } // Apex code to execute
    public Integer priority { get; set; } // Lower = higher priority
    public Integer complexity { get; set; } // 1-10, affects batch size
    public List<String> dependsOn { get; set; } // Other sObject types this depends on

    public DataQualityRule() {
        this.priority = 5;
        this.complexity = 1;
        this.dependsOn = new List<String>();
    }

    /**
     * @description Factory method for creating rules
     */
    public static DataQualityRule create(String name, String sObjectType) {
        DataQualityRule rule = new DataQualityRule();
        rule.ruleName = name;
        rule.sobjectType = sObjectType;
        return rule;
    }

    /**
     * @description Sets WHERE clause for filtering records
     */
    public DataQualityRule withWhere(String whereClause) {
        this.whereClause = whereClause;
        return this;
    }

    /**
     * @description Sets field to update
     */
    public DataQualityRule updateField(String fieldName, Object value) {
        this.fieldToUpdate = fieldName;
        this.valueToSet = value;
        return this;
    }

    /**
     * @description Sets priority (lower = higher priority)
     */
    public DataQualityRule withPriority(Integer priority) {
        this.priority = priority;
        return this;
    }

    /**
     * @description Sets complexity (1-10)
     */
    public DataQualityRule withComplexity(Integer complexity) {
        this.complexity = Math.max(1, Math.min(10, complexity));
        return this;
    }

    /**
     * @description Adds dependency on another sObject
     */
    public DataQualityRule dependsOn(String sObjectType) {
        this.dependsOn.add(sObjectType);
        return this;
    }
}
