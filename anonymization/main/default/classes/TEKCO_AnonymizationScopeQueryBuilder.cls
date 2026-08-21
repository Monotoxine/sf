/**
 * @description Pure, side-effect-free helpers that decide WHAT a run reads: which fields to
 *              select and which records are in scope.
 *
 *              Extracted from the batches' start() on purpose. Every critical bug found in the
 *              code review lived in that scope-building code, and none of it was reachable by a
 *              test without executing a whole batch. Everything here returns a value and touches
 *              no state, so it can be asserted directly.
 *
 *              Shared by both chains (By Criteria and By ID) and by the preview, so what the
 *              preview reads is what a run reads.
 */
public inherited sharing class TEKCO_AnonymizationScopeQueryBuilder {

    private static final String PATTERN_EMAIL_LOREM   = 'EMAIL_MESSAGE_LOREM';
    private static final String PATTERN_DELETE_CD     = 'DELETE_CONTENT_DOCUMENT';
    private static final String PATTERN_NAME_FIRST    = 'NAME_FIRST_LETTER';
    private static final String PATTERN_NAME_FIRST_SF = 'NAME_FIRST_LETTER_SFID';

    /** Everything start() needs to know before building its query. */
    public class FieldSelection {
        public Set<String>  fields               = new Set<String>{ 'Id' };
        public List<String> validConfigDevNames  = new List<String>();
        /** Transient: batches must store only validConfigDevNames in stateful fields. */
        public List<TEKCO_AnonymizationFieldConfig__mdt> validConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        public Boolean      needsRecordTypeId    = false;
        public Boolean      hasEmailMessageLorem = false;
        public List<String> errors               = new List<String>();
    }

    /**
     * Fields to SELECT for the field-anonymization phase, and the configs that survive
     * validation against the object's real schema.
     *
     * DELETE_CONTENT_DOCUMENT configs are skipped: a dedicated batch handles them in both
     * chains. Previously only the By ID chain skipped them, so By Criteria carried
     * blank-field configs through the execute loop for nothing.
     */
    public static FieldSelection buildFieldSelection(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs,
        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType
    ) {
        FieldSelection selection = new FieldSelection();
        Map<String, Schema.SObjectField> objectFieldMap =
            TEKCO_AnonymizationOrgConfigService.getFieldMap(objectApiName);
        if (objectFieldMap == null) {
            selection.errors.add('Object not found in org, skipped: ' + objectApiName);
            return selection;
        }
        if (configs == null) return selection;

        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            String patternType  = fc.TEKCO_PatternType__c;
            String fieldApiName = fc.TEKCO_FieldApiName__c;

            if (patternType == PATTERN_DELETE_CD) continue;

            if (String.isNotBlank(fieldApiName)
                    && !objectFieldMap.containsKey(fieldApiName.toLowerCase())) {
                selection.errors.add('Field not found on ' + objectApiName + ', skipped: ' + fieldApiName);
                continue;
            }

            selection.validConfigs.add(fc);
            if (String.isNotBlank(fc.DeveloperName)) selection.validConfigDevNames.add(fc.DeveloperName);
            if (String.isNotBlank(fieldApiName))     selection.fields.add(fieldApiName);

            if (patternType == PATTERN_EMAIL_LOREM) {
                selection.hasEmailMessageLorem = true;
                selection.fields.add('Status');
            }

            TEKCO_AnonymizationPattern__mdt pattern =
                patternsByType == null ? null : patternsByType.get(patternType);
            if (pattern != null && String.isNotBlank(pattern.TEKCO_ExternalIdField__c)
                    && objectFieldMap.containsKey(pattern.TEKCO_ExternalIdField__c.toLowerCase())) {
                selection.fields.add(pattern.TEKCO_ExternalIdField__c);
            }

            if (patternType == PATTERN_NAME_FIRST || patternType == PATTERN_NAME_FIRST_SF) {
                String funcField = TEKCO_AnonymizationOrgConfigService.getConfig().functionalIdField;
                if (String.isNotBlank(funcField) && objectFieldMap.containsKey(funcField.toLowerCase())) {
                    selection.fields.add(funcField);
                }
            }

            if (TEKCO_AnonymizationConfigSelector.isRecordTypeScoped(fc)) {
                selection.needsRecordTypeId = true;
            }
        }

        // The external ID field named on a pattern belongs to the standard TEKCO schema and is
        // absent from some orgs, which key on their own. Those must be selected or the fallback
        // in TEKCO_AnonymizationPatternService.getExternalId() has nothing to read.
        selection.fields.addAll(
            TEKCO_AnonymizationOrgConfigService.getExternalIdFieldsOn(objectApiName)
        );

        if (selection.needsRecordTypeId) selection.fields.add('RecordTypeId');

        return selection;
    }

    // ─── History object naming ───────────────────────────────────────────────
    //
    // Pure derivations, kept next to the history query builders that consume them rather than
    // in a general-purpose helper: naming a history object is part of deciding what to read.

    private static final String CUSTOM_OBJECT_SUFFIX = '__c';

    /** Account -> AccountHistory ; My_Object__c -> My_Object__History */
    public static String historyObjectNameFor(String objectApiName) {
        return objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX)
            ? objectApiName.replace(CUSTOM_OBJECT_SUFFIX, '__History')
            : objectApiName + 'History';
    }

    /** Account -> AccountId ; My_Object__c -> ParentId */
    public static String historyParentIdFieldFor(String objectApiName) {
        return objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX) ? 'ParentId' : objectApiName + 'Id';
    }

    // ─── Scope queries ───────────────────────────────────────────────────────
    //
    // These return SOQL strings; Database.getQueryLocator() stays in the batches. That is
    // deliberate and not an oversight: the emitted queries carry bind variables (:selectedBrands,
    // :recordIds, :parentIds) that Apex resolves against the CALLING scope, i.e. the batch's own
    // fields. Building the string here and binding there keeps the two concerns apart while
    // leaving the binds working — and keeps the strings assertable in a test.

    /** Locator that matches nothing, for the skip paths. */
    public static final String EMPTY_LOCATOR_QUERY = 'SELECT Id FROM User WHERE Id = null';

    /**
     * By Criteria field phase.
     *
     * @param hasEmailMessageLorem enables the EmailMessage fallback: that object carries no brand
     *        field of its own, so when no brand condition can be built for it the scope goes
     *        through the parent Case. Guarded on the field existing — it does not in every org.
     *        Emits the bind :selectedBrands, which the caller must expose.
     */
    public static String buildFieldScopeQuery(
        String objectApiName,
        Set<String> fields,
        List<String> selectedBrands,
        List<String> selectedRecordTypes,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs,
        String additionalFilter,
        Boolean hasEmailMessageLorem
    ) {
        List<String> conditions = new List<String>();

        if (selectedBrands != null && !selectedBrands.isEmpty()) {
            String brandCondition = TEKCO_AnonymizationOrgConfigService.buildBrandCondition(
                objectApiName, selectedBrands
            );
            if (brandCondition != null) {
                conditions.add(brandCondition);
            } else if (hasEmailMessageLorem == true
                    && TEKCO_AnonymizationOrgConfigService.hasField('Case', 'TEKCO_Brand__c')) {
                conditions.add('Parent.TEKCO_Brand__c IN :selectedBrands');
            }
        }
        conditions.add(recordTypeCondition(objectApiName, selectedRecordTypes, configs));
        conditions.add(additionalFilter);

        return selectClause(fields) + ' FROM ' + objectApiName + whereClause(conditions);
    }

    /**
     * The user's record-type selection, as a SOQL condition.
     *
     * A scope filter like the brand one: it decides which records a run reads. Every scope query
     * applies it, and so does the preview count and the before/after sample, from this one
     * definition — they used to disagree, the preview honouring the selection while the run
     * ignored it entirely.
     *
     * @return null when there is nothing to add: no selection, an object with no RecordTypeId,
     *         or a selection naming only record types this object does not declare.
     */
    public static String recordTypeCondition(
        String objectApiName,
        List<String> selectedRecordTypes,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        if (selectedRecordTypes == null || selectedRecordTypes.isEmpty()) return null;
        if (!TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, 'recordtypeid')) return null;
        if (configs == null || configs.isEmpty()) return null;

        // Only the record types this object actually declares — a Case record type must not end
        // up filtering an Account query.
        Set<String> declared = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            declared.addAll(TEKCO_AnonymizationConfigSelector.recordTypesOf(fc));
        }
        Set<String> kept = new Set<String>();
        for (String rt : selectedRecordTypes) {
            if (declared.contains(rt)) kept.add(rt);
        }
        String inClause = escapedInClause(kept);
        return inClause == null ? null : 'RecordType.DeveloperName IN (' + inClause + ')';
    }

    /**
     * The additional-filter condition for one object, from the rules still retained on it.
     *
     * The filter belongs to the RULE, so an object's scope is the OR of its retained rules'
     * filters. A retained rule carrying NO filter means "no restriction" and returns null: that
     * rule applies to every record of the object, and restricting the query would drop records
     * it is configured to anonymize.
     *
     * Parenthesised as a whole, always. whereClause() joins conditions with AND, and AND binds
     * tighter than OR in SOQL: an unwrapped "(x) OR (y)" next to a brand condition would read
     * "(brand AND x) OR y" and reach records outside the brand filter. A single term is wrapped
     * too — a lone filter is free to contain its own OR.
     *
     * Both the launch and the before/after sample call this, so the sample cannot describe a
     * scope the run does not have.
     */
    public static String combineAdditionalFilters(
        List<TEKCO_AnonymizationFieldConfig__mdt> retainedConfigs
    ) {
        if (retainedConfigs == null || retainedConfigs.isEmpty()) return null;

        Set<String> terms = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt config : retainedConfigs) {
            if (config == null) continue;
            if (String.isBlank(config.TEKCO_AdditionalFilter__c)) return null;
            terms.add('(' + config.TEKCO_AdditionalFilter__c + ')');
        }
        if (terms.isEmpty()) return null;

        // Sorted so the same configuration always produces the same query — a query that varies
        // between runs is impossible to compare in a debug log.
        List<String> sorted = new List<String>(terms);
        sorted.sort();
        return '(' + String.join(sorted, ' OR ') + ')';
    }

    /**
     * By ID field phase — and any other "these exact records" scope.
     * @param idBindName name of the batch field holding the Ids, emitted as a bind.
     */
    public static String buildByIdScopeQuery(
        String objectApiName, Set<String> fields, String idBindName
    ) {
        return selectClause(fields) + ' FROM ' + objectApiName + ' WHERE Id IN :' + idBindName;
    }

    /** By Criteria ContentDocument phase: the parent records whose files are to be removed. */
    public static String buildContentDocScopeQuery(
        String objectApiName,
        List<String> selectedBrands,
        Set<String> recordTypeDevNames,
        List<String> selectedRecordTypes,
        String additionalFilter
    ) {
        List<String> conditions = new List<String>();
        conditions.add(
            TEKCO_AnonymizationOrgConfigService.buildBrandCondition(objectApiName, selectedBrands)
        );
        // The rule's own coverage, then the user's selection on top: a rule covering two
        // populations must not delete the files of the one that was not selected.
        Set<String> effective = new Set<String>(recordTypeDevNames);
        if (selectedRecordTypes != null && !selectedRecordTypes.isEmpty() && !effective.isEmpty()) {
            effective.retainAll(new Set<String>(selectedRecordTypes));
        }
        String recordTypeIn = escapedInClause(effective);
        if (recordTypeIn != null) {
            conditions.add('RecordType.DeveloperName IN (' + recordTypeIn + ')');
        } else if (selectedRecordTypes != null && !selectedRecordTypes.isEmpty()
                && recordTypeDevNames != null && recordTypeDevNames.isEmpty()) {
            // Rule covering every record type, run narrowed to a selection: bound it.
            String selectedIn = escapedInClause(new Set<String>(selectedRecordTypes));
            if (selectedIn != null) {
                conditions.add('RecordType.DeveloperName IN (' + selectedIn + ')');
            }
        }
        conditions.add(additionalFilter);

        return 'SELECT Id FROM ' + objectApiName + whereClause(conditions);
    }

    /**
     * By Criteria history phase: history rows of the targeted fields, on the parent records
     * matching the run's scope.
     *
     * @return null when no field is targeted. Building it anyway would emit 'Field IN ()', which
     *         is invalid SOQL: the By Criteria batch used to do exactly that and reported the
     *         resulting parse error as a run failure, while the By ID batch skipped cleanly.
     */
    public static String buildHistoryScopeQuery(
        String objectApiName,
        String historyObjectName,
        String parentIdFieldName,
        Set<String> historyFieldNames,
        List<String> selectedBrands,
        List<String> selectedRecordTypes,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs,
        String additionalFilter
    ) {
        String fieldInClause = escapedInClause(historyFieldNames);
        if (fieldInClause == null) return null;

        List<String> parentConditions = new List<String>();
        parentConditions.add(
            TEKCO_AnonymizationOrgConfigService.buildBrandCondition(objectApiName, selectedBrands)
        );
        parentConditions.add(recordTypeCondition(objectApiName, selectedRecordTypes, configs));
        parentConditions.add(additionalFilter);

        return 'SELECT Id FROM ' + historyObjectName
            + ' WHERE Field IN (' + fieldInClause + ')'
            + ' AND ' + parentIdFieldName
            + ' IN (SELECT Id FROM ' + objectApiName + whereClause(parentConditions) + ')';
    }

    /**
     * By ID history phase. Same null contract as buildHistoryScopeQuery.
     * @param idBindName name of the batch field holding the parent Ids, emitted as a bind.
     */
    public static String buildHistoryByIdScopeQuery(
        String historyObjectName,
        String parentIdFieldName,
        Set<String> historyFieldNames,
        String idBindName
    ) {
        String fieldInClause = escapedInClause(historyFieldNames);
        if (fieldInClause == null) return null;

        return 'SELECT Id FROM ' + historyObjectName
            + ' WHERE Field IN (' + fieldInClause + ')'
            + ' AND ' + parentIdFieldName + ' IN :' + idBindName;
    }

    /** Quoted, escaped, sorted literal list; null when there is nothing to put in the IN. */
    private static String escapedInClause(Set<String> values) {
        if (values == null || values.isEmpty()) return null;
        List<String> sorted = new List<String>(values);
        sorted.sort();
        List<String> escaped = new List<String>();
        for (String value : sorted) {
            escaped.add('\'' + String.escapeSingleQuotes(value) + '\'');
        }
        return String.join(escaped, ', ');
    }

    /** SELECT clause from a field set, in a stable order so queries are comparable in tests. */
    public static String selectClause(Set<String> fields) {
        List<String> sorted = new List<String>(fields);
        sorted.sort();
        return 'SELECT ' + String.join(sorted, ', ');
    }

    /** Appends ' WHERE a AND b' when there is at least one condition, nothing otherwise. */
    public static String whereClause(List<String> conditions) {
        List<String> kept = new List<String>();
        for (String c : conditions) {
            if (String.isNotBlank(c)) kept.add(c);
        }
        return kept.isEmpty() ? '' : ' WHERE ' + String.join(kept, ' AND ');
    }
}
