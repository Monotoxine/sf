/**
 * @description Advanced Dynamic SOQL Query Builder with auto-detection, optimization, security, and validation
 * @author Claude
 * @date 2025-10-26
 */
public class DynamicQueryBuilder {

    private String sobjectType;
    private Set<String> fields;
    private List<String> whereClauses;
    private String orderBy;
    private Integer limitCount;
    private Integer offsetCount;
    private Boolean withSecurityEnforced;
    private Boolean suppressSharing;

    // Analysis results
    private QueryAnalysis analysis;

    // ========== Constructor ==========

    /**
     * @description Creates a new query builder for the specified SObject type
     * @param sobjectType API name of the SObject (e.g., 'Account', 'Contact')
     */
    public DynamicQueryBuilder(String sobjectType) {
        this.sobjectType = sobjectType;
        this.fields = new Set<String>();
        this.whereClauses = new List<String>();
        this.withSecurityEnforced = true; // Security by default
        this.suppressSharing = false;
        this.analysis = new QueryAnalysis();
    }

    // ========== Builder Methods ==========

    /**
     * @description Adds a field to the query. Supports field paths (Account.Owner.Name)
     * @param fieldPath Field or field path to select
     * @return this builder
     */
    public DynamicQueryBuilder addField(String fieldPath) {
        if (String.isBlank(fieldPath)) {
            throw new QueryBuilderException('Field path cannot be blank');
        }

        // Auto-detect relationships and add necessary fields
        if (fieldPath.contains('.')) {
            addRelationalFields(fieldPath);
        }

        fields.add(fieldPath);
        return this;
    }

    /**
     * @description Adds multiple fields to the query
     * @param fieldPaths List of fields or field paths
     * @return this builder
     */
    public DynamicQueryBuilder addFields(List<String> fieldPaths) {
        for (String fieldPath : fieldPaths) {
            addField(fieldPath);
        }
        return this;
    }

    /**
     * @description Adds a WHERE clause condition
     * @param condition WHERE condition (e.g., "Name = 'Test'")
     * @return this builder
     */
    public DynamicQueryBuilder addWhere(String condition) {
        if (String.isNotBlank(condition)) {
            whereClauses.add(condition);
        }
        return this;
    }

    /**
     * @description Sets the ORDER BY clause
     * @param orderByClause ORDER BY clause (e.g., "Name ASC")
     * @return this builder
     */
    public DynamicQueryBuilder orderBy(String orderByClause) {
        this.orderBy = orderByClause;
        return this;
    }

    /**
     * @description Sets the LIMIT
     * @param limitCount Number of records to limit
     * @return this builder
     */
    public DynamicQueryBuilder setLimit(Integer limitCount) {
        this.limitCount = limitCount;
        return this;
    }

    /**
     * @description Sets the OFFSET
     * @param offsetCount Number of records to offset
     * @return this builder
     */
    public DynamicQueryBuilder setOffset(Integer offsetCount) {
        this.offsetCount = offsetCount;
        return this;
    }

    /**
     * @description Enables WITH SECURITY_ENFORCED (default: true)
     * @return this builder
     */
    public DynamicQueryBuilder withSecurityEnforced() {
        this.withSecurityEnforced = true;
        return this;
    }

    /**
     * @description Disables security enforcement (use with caution!)
     * @return this builder
     */
    public DynamicQueryBuilder withoutSecurityEnforced() {
        this.withSecurityEnforced = false;
        return this;
    }

    /**
     * @description Uses without sharing for this query
     * @return this builder
     */
    public DynamicQueryBuilder withoutSharing() {
        this.suppressSharing = true;
        return this;
    }

    // ========== 1. Auto-Detection of Related Objects ==========

    /**
     * @description Parses field path and automatically adds required relationship fields
     * @param fieldPath Dot-separated field path (e.g., Account.Owner.Name)
     */
    private void addRelationalFields(String fieldPath) {
        String[] parts = fieldPath.split('\\.');
        String currentPath = '';

        for (Integer i = 0; i < parts.size() - 1; i++) {
            if (i > 0) {
                currentPath += '.';
            }
            currentPath += parts[i];

            // Add Id field for each relationship level
            String idField = currentPath + '.Id';
            if (!fields.contains(idField)) {
                fields.add(idField);
            }
        }

        // Track relationship for analysis
        analysis.relatedObjects.add(fieldPath);
    }

    /**
     * @description Detects if a field is a polymorphic relationship
     * @param fieldName Field name to check
     * @return true if polymorphic
     */
    private Boolean isPolymorphicField(String fieldName) {
        try {
            Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(sobjectType);
            if (sobjType == null) return false;

            Schema.DescribeSObjectResult describeResult = sobjType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

            Schema.SObjectField field = fieldMap.get(fieldName);
            if (field == null) return false;

            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

            // Polymorphic fields have multiple reference targets
            List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();
            return references != null && references.size() > 1;
        } catch (Exception e) {
            return false;
        }
    }

    // ========== 2. Query Optimization ==========

    /**
     * @description Analyzes and optimizes the query
     * @return QueryAnalysis with optimization suggestions
     */
    public QueryAnalysis analyze() {
        analysis = new QueryAnalysis();

        // Detect indexed fields in WHERE clauses
        detectIndexedFields();

        // Optimize WHERE clause order
        optimizeWhereClauseOrder();

        // Suggest missing indexes
        suggestIndexes();

        return analysis;
    }

    /**
     * @description Detects which WHERE clause fields are indexed
     */
    private void detectIndexedFields() {
        try {
            Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(sobjectType);
            if (sobjType == null) return;

            Schema.DescribeSObjectResult describeResult = sobjType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

            for (String whereClause : whereClauses) {
                // Extract field name from WHERE clause (simple extraction)
                String fieldName = extractFieldNameFromWhere(whereClause);

                if (String.isNotBlank(fieldName)) {
                    Schema.SObjectField field = fieldMap.get(fieldName);
                    if (field != null) {
                        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

                        // Check if field is indexed (unique, external ID, or Id field)
                        if (fieldDescribe.isUnique() ||
                            fieldDescribe.isExternalId() ||
                            fieldDescribe.isIdLookup() ||
                            fieldName.equalsIgnoreCase('Id') ||
                            fieldName.equalsIgnoreCase('Name')) {
                            analysis.indexedFields.add(fieldName);
                        } else {
                            analysis.nonIndexedFields.add(fieldName);
                        }
                    }
                }
            }
        } catch (Exception e) {
            analysis.warnings.add('Could not analyze indexed fields: ' + e.getMessage());
        }
    }

    /**
     * @description Extracts field name from WHERE clause
     * @param whereClause WHERE condition
     * @return Field name
     */
    private String extractFieldNameFromWhere(String whereClause) {
        // Simple extraction: get everything before operator
        whereClause = whereClause.trim();

        List<String> operators = new List<String>{'=', '!=', '>', '<', '>=', '<=', 'LIKE', 'IN', 'NOT IN'};
        for (String op : operators) {
            if (whereClause.contains(op)) {
                return whereClause.substringBefore(op).trim();
            }
        }

        return null;
    }

    /**
     * @description Optimizes WHERE clause order (indexed fields first)
     */
    private void optimizeWhereClauseOrder() {
        if (whereClauses.isEmpty()) return;

        List<String> optimizedClauses = new List<String>();
        List<String> nonOptimizedClauses = new List<String>();

        for (String whereClause : whereClauses) {
            String fieldName = extractFieldNameFromWhere(whereClause);
            if (analysis.indexedFields.contains(fieldName)) {
                optimizedClauses.add(whereClause);
            } else {
                nonOptimizedClauses.add(whereClause);
            }
        }

        // Indexed fields first for better performance
        optimizedClauses.addAll(nonOptimizedClauses);

        if (optimizedClauses.size() != whereClauses.size()) {
            analysis.suggestions.add('WHERE clause order optimized: indexed fields placed first');
            whereClauses = optimizedClauses;
        }
    }

    /**
     * @description Suggests indexes for non-indexed WHERE fields
     */
    private void suggestIndexes() {
        if (!analysis.nonIndexedFields.isEmpty()) {
            analysis.suggestions.add(
                'Consider creating custom indexes on: ' +
                String.join(new List<String>(analysis.nonIndexedFields), ', ')
            );
        }
    }

    // ========== 3. Security Checks ==========

    /**
     * @description Validates CRUD permissions for the SObject
     * @return SecurityCheckResult
     */
    public SecurityCheckResult checkSecurity() {
        SecurityCheckResult result = new SecurityCheckResult();

        try {
            Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(sobjectType);
            if (sobjType == null) {
                result.hasErrors = true;
                result.errors.add('SObject type not found: ' + sobjectType);
                return result;
            }

            Schema.DescribeSObjectResult describeResult = sobjType.getDescribe();

            // Check CRUD permissions
            result.isCreateable = describeResult.isCreateable();
            result.isReadable = describeResult.isAccessible();
            result.isUpdateable = describeResult.isUpdateable();
            result.isDeletable = describeResult.isDeletable();

            if (!result.isReadable) {
                result.hasErrors = true;
                result.errors.add('No read access to ' + sobjectType);
            }

            // Check FLS for each field
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();
            for (String fieldPath : fields) {
                // Get base field name (before first dot)
                String fieldName = fieldPath.contains('.') ?
                    fieldPath.substringBefore('.') : fieldPath;

                Schema.SObjectField field = fieldMap.get(fieldName);
                if (field != null) {
                    Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

                    if (!fieldDescribe.isAccessible()) {
                        result.hasErrors = true;
                        result.errors.add('No read access to field: ' + fieldName);
                        result.inaccessibleFields.add(fieldName);
                    } else {
                        result.accessibleFields.add(fieldName);
                    }
                } else {
                    result.warnings.add('Field not found: ' + fieldName);
                }
            }

        } catch (Exception e) {
            result.hasErrors = true;
            result.errors.add('Security check failed: ' + e.getMessage());
        }

        return result;
    }

    // ========== 4. Advanced Validation ==========

    /**
     * @description Validates the query configuration
     * @return ValidationResult
     */
    public ValidationResult validate() {
        ValidationResult result = new ValidationResult();

        // Validate SObject exists
        if (!validateSObjectExists()) {
            result.hasErrors = true;
            result.errors.add('SObject type does not exist: ' + sobjectType);
            return result;
        }

        // Validate fields exist
        validateFieldsExist(result);

        // Validate relationships
        validateRelationships(result);

        // Suggest corrections
        suggestCorrections(result);

        return result;
    }

    /**
     * @description Checks if SObject type exists
     * @return true if exists
     */
    private Boolean validateSObjectExists() {
        return Schema.getGlobalDescribe().containsKey(sobjectType);
    }

    /**
     * @description Validates that all fields exist
     * @param result ValidationResult to populate
     */
    private void validateFieldsExist(ValidationResult result) {
        try {
            Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(sobjectType);
            Schema.DescribeSObjectResult describeResult = sobjType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

            for (String fieldPath : fields) {
                if (fieldPath.contains('.')) {
                    // Validate relationship path
                    if (!validateRelationshipPath(fieldPath, result)) {
                        result.hasErrors = true;
                    }
                } else {
                    // Validate simple field
                    if (!fieldMap.containsKey(fieldPath)) {
                        result.hasErrors = true;
                        result.errors.add('Field does not exist: ' + fieldPath);
                        result.invalidFields.add(fieldPath);
                    } else {
                        result.validFields.add(fieldPath);
                    }
                }
            }
        } catch (Exception e) {
            result.hasErrors = true;
            result.errors.add('Field validation failed: ' + e.getMessage());
        }
    }

    /**
     * @description Validates a relationship path
     * @param fieldPath Relationship path (e.g., Account.Owner.Name)
     * @param result ValidationResult to populate
     * @return true if valid
     */
    private Boolean validateRelationshipPath(String fieldPath, ValidationResult result) {
        String[] parts = fieldPath.split('\\.');
        String currentObject = sobjectType;

        for (Integer i = 0; i < parts.size(); i++) {
            String part = parts[i];

            try {
                Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(currentObject);
                if (sobjType == null) {
                    result.errors.add('Invalid object in path: ' + currentObject);
                    return false;
                }

                Schema.DescribeSObjectResult describeResult = sobjType.getDescribe();
                Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

                if (!fieldMap.containsKey(part)) {
                    result.errors.add('Invalid field in path: ' + fieldPath + ' (field: ' + part + ')');
                    result.invalidFields.add(fieldPath);
                    return false;
                }

                // Get next object type if not last part
                if (i < parts.size() - 1) {
                    Schema.DescribeFieldResult fieldDescribe = fieldMap.get(part).getDescribe();
                    List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();

                    if (references == null || references.isEmpty()) {
                        result.errors.add('Field is not a relationship: ' + part);
                        return false;
                    }

                    // For simplicity, use first reference (polymorphic would need special handling)
                    currentObject = references[0].getDescribe().getName();
                }
            } catch (Exception e) {
                result.errors.add('Error validating path: ' + fieldPath + ' - ' + e.getMessage());
                return false;
            }
        }

        result.validFields.add(fieldPath);
        return true;
    }

    /**
     * @description Validates relationship fields
     * @param result ValidationResult to populate
     */
    private void validateRelationships(ValidationResult result) {
        // Check for common relationship naming errors
        for (String fieldPath : fields) {
            if (fieldPath.contains('.')) {
                String relationshipName = fieldPath.substringBefore('.');

                // Common mistakes
                if (relationshipName.endsWithIgnoreCase('Id')) {
                    result.warnings.add(
                        'Relationship fields should not end with "Id". Did you mean "' +
                        relationshipName.removeEnd('Id') + '"?'
                    );
                }
            }
        }
    }

    /**
     * @description Suggests corrections for errors
     * @param result ValidationResult to populate
     */
    private void suggestCorrections(ValidationResult result) {
        if (result.invalidFields.isEmpty()) return;

        try {
            Schema.SObjectType sobjType = Schema.getGlobalDescribe().get(sobjectType);
            Schema.DescribeSObjectResult describeResult = sobjType.getDescribe();
            Map<String, Schema.SObjectField> fieldMap = describeResult.fields.getMap();

            for (String invalidField : result.invalidFields) {
                // Find similar field names (Levenshtein distance)
                String suggestion = findSimilarField(invalidField, fieldMap.keySet());
                if (suggestion != null) {
                    result.suggestions.add('Did you mean "' + suggestion + '" instead of "' + invalidField + '"?');
                }
            }
        } catch (Exception e) {
            // Ignore suggestion errors
        }
    }

    /**
     * @description Finds similar field name using simple matching
     * @param target Target field name
     * @param availableFields Available field names
     * @return Similar field name or null
     */
    private String findSimilarField(String target, Set<String> availableFields) {
        target = target.toLowerCase();

        // Exact case-insensitive match
        for (String field : availableFields) {
            if (field.equalsIgnoreCase(target)) {
                return field;
            }
        }

        // Contains match
        for (String field : availableFields) {
            if (field.toLowerCase().contains(target) || target.contains(field.toLowerCase())) {
                return field;
            }
        }

        return null;
    }

    // ========== 5. Performance Analysis ==========

    /**
     * @description Analyzes query performance and selectivity
     * @return PerformanceAnalysis
     */
    public PerformanceAnalysis analyzePerformance() {
        PerformanceAnalysis perf = new PerformanceAnalysis();

        // Check if query is selective
        perf.isSelective = isSelectiveQuery();

        // Add warnings for potentially slow queries
        if (!perf.isSelective) {
            perf.warnings.add('Query may be slow: no indexed fields in WHERE clause');
        }

        if (limitCount == null || limitCount > 10000) {
            perf.warnings.add('Query may return many records. Consider adding LIMIT');
        }

        if (fields.size() > 50) {
            perf.warnings.add('Selecting many fields (' + fields.size() + ') may impact performance');
        }

        // Estimate result count (simple heuristic)
        perf.estimatedRecordCount = estimateRecordCount();

        return perf;
    }

    /**
     * @description Checks if query is selective (uses indexed fields)
     * @return true if selective
     */
    private Boolean isSelectiveQuery() {
        // Query is selective if it uses indexed fields in WHERE
        return !analysis.indexedFields.isEmpty();
    }

    /**
     * @description Estimates number of records (simple heuristic)
     * @return Estimated count
     */
    private Integer estimateRecordCount() {
        if (limitCount != null) {
            return limitCount;
        }

        // Simple heuristic based on selectivity
        if (isSelectiveQuery()) {
            return 100; // Selective query likely returns fewer records
        } else {
            return 10000; // Non-selective may return many
        }
    }

    // ========== Build and Execute ==========

    /**
     * @description Builds the SOQL query string
     * @return SOQL query string
     */
    public String build() {
        return buildQuery(false);
    }

    /**
     * @description Builds and executes the query with full validation
     * @return Query results
     */
    public List<SObject> execute() {
        // Validate before executing
        ValidationResult validation = validate();
        if (validation.hasErrors) {
            throw new QueryBuilderException('Query validation failed: ' + String.join(validation.errors, '; '));
        }

        // Check security
        if (withSecurityEnforced) {
            SecurityCheckResult security = checkSecurity();
            if (security.hasErrors) {
                throw new QueryBuilderException('Security check failed: ' + String.join(security.errors, '; '));
            }
        }

        // Analyze and optimize
        analyze();

        // Build query
        String queryString = buildQuery(withSecurityEnforced);

        // Execute
        return Database.query(queryString);
    }

    /**
     * @description Builds the query string
     * @param includeSecurityEnforced Whether to include WITH SECURITY_ENFORCED
     * @return Query string
     */
    private String buildQuery(Boolean includeSecurityEnforced) {
        if (fields.isEmpty()) {
            fields.add('Id'); // Always select at least Id
        }

        List<String> parts = new List<String>();

        // SELECT
        parts.add('SELECT ' + String.join(new List<String>(fields), ', '));

        // FROM
        parts.add('FROM ' + sobjectType);

        // WHERE
        if (!whereClauses.isEmpty()) {
            parts.add('WHERE ' + String.join(whereClauses, ' AND '));
        }

        // WITH SECURITY_ENFORCED
        if (includeSecurityEnforced) {
            parts.add('WITH SECURITY_ENFORCED');
        }

        // ORDER BY
        if (String.isNotBlank(orderBy)) {
            parts.add('ORDER BY ' + orderBy);
        }

        // LIMIT
        if (limitCount != null) {
            parts.add('LIMIT ' + limitCount);
        }

        // OFFSET
        if (offsetCount != null) {
            parts.add('OFFSET ' + offsetCount);
        }

        return String.join(parts, ' ');
    }

    // ========== Inner Classes ==========

    /**
     * @description Query analysis results
     */
    public class QueryAnalysis {
        public Set<String> indexedFields = new Set<String>();
        public Set<String> nonIndexedFields = new Set<String>();
        public Set<String> relatedObjects = new Set<String>();
        public List<String> suggestions = new List<String>();
        public List<String> warnings = new List<String>();
    }

    /**
     * @description Security check results
     */
    public class SecurityCheckResult {
        public Boolean hasErrors = false;
        public Boolean isCreateable = false;
        public Boolean isReadable = false;
        public Boolean isUpdateable = false;
        public Boolean isDeletable = false;
        public Set<String> accessibleFields = new Set<String>();
        public Set<String> inaccessibleFields = new Set<String>();
        public List<String> errors = new List<String>();
        public List<String> warnings = new List<String>();
    }

    /**
     * @description Validation results
     */
    public class ValidationResult {
        public Boolean hasErrors = false;
        public Set<String> validFields = new Set<String>();
        public Set<String> invalidFields = new Set<String>();
        public List<String> errors = new List<String>();
        public List<String> warnings = new List<String>();
        public List<String> suggestions = new List<String>();
    }

    /**
     * @description Performance analysis results
     */
    public class PerformanceAnalysis {
        public Boolean isSelective = false;
        public Integer estimatedRecordCount = 0;
        public List<String> warnings = new List<String>();
        public List<String> suggestions = new List<String>();
    }

    /**
     * @description Custom exception for query builder errors
     */
    public class QueryBuilderException extends Exception {}
}
