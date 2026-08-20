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

            if (String.isNotBlank(fc.TEKCO_RecordTypeDeveloperName__c)) {
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
