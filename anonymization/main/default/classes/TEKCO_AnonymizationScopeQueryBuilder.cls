/**
 * @description 
 */
public inherited sharing class TEKCO_AnonymizationScopeQueryBuilder {

    private static final String PATTERN_EMAIL_LOREM   = 'EMAIL_MESSAGE_LOREM';
    private static final String PATTERN_DELETE_CD     = 'DELETE_CONTENT_DOCUMENT';
    private static final String PATTERN_NAME_FIRST    = 'NAME_FIRST_LETTER';
    private static final String PATTERN_NAME_FIRST_SF = 'NAME_FIRST_LETTER_SFID';

    public class FieldSelection {
        public Set<String>  fields               = new Set<String>{ 'Id' };
        public List<String> validConfigDevNames  = new List<String>();
        public List<TEKCO_AnonymizationFieldConfig__mdt> validConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        public Boolean      needsRecordTypeId    = false;
        public Boolean      hasEmailMessageLorem = false;
        public List<String> errors               = new List<String>();
    }

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

        selection.fields.addAll(
            TEKCO_AnonymizationOrgConfigService.getExternalIdFieldsOn(objectApiName)
        );

        if (selection.needsRecordTypeId) selection.fields.add('RecordTypeId');

        return selection;
    }

    private static final String CUSTOM_OBJECT_SUFFIX = '__c';

    public static String historyObjectNameFor(String objectApiName) {
        return objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX)
            ? objectApiName.replace(CUSTOM_OBJECT_SUFFIX, '__History')
            : objectApiName + 'History';
    }

    public static String historyParentIdFieldFor(String objectApiName) {
        return objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX) ? 'ParentId' : objectApiName + 'Id';
    }

    public static final String EMPTY_LOCATOR_QUERY = 'SELECT Id FROM User WHERE Id = null';

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

    public static String recordTypeCondition(
        String objectApiName,
        List<String> selectedRecordTypes,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        if (selectedRecordTypes == null || selectedRecordTypes.isEmpty()) return null;
        if (!TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, 'recordtypeid')) return null;
        if (configs == null || configs.isEmpty()) return null;
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
        List<String> sorted = new List<String>(terms);
        sorted.sort();
        return '(' + String.join(sorted, ' OR ') + ')';
    }

    public static String buildByIdScopeQuery(
        String objectApiName, Set<String> fields, String idBindName
    ) {
        return selectClause(fields) + ' FROM ' + objectApiName + ' WHERE Id IN :' + idBindName;
    }

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

        Set<String> effective = new Set<String>(recordTypeDevNames);
        if (selectedRecordTypes != null && !selectedRecordTypes.isEmpty() && !effective.isEmpty()) {
            effective.retainAll(new Set<String>(selectedRecordTypes));
        }
        String recordTypeIn = escapedInClause(effective);
        if (recordTypeIn != null) {
            conditions.add('RecordType.DeveloperName IN (' + recordTypeIn + ')');
        } else if (selectedRecordTypes != null && !selectedRecordTypes.isEmpty()
                && recordTypeDevNames != null && recordTypeDevNames.isEmpty()) {
            String selectedIn = escapedInClause(new Set<String>(selectedRecordTypes));
            if (selectedIn != null) {
                conditions.add('RecordType.DeveloperName IN (' + selectedIn + ')');
            }
        }
        conditions.add(additionalFilter);

        return 'SELECT Id FROM ' + objectApiName + whereClause(conditions);
    }

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

    public static String selectClause(Set<String> fields) {
        List<String> sorted = new List<String>(fields);
        sorted.sort();
        return 'SELECT ' + String.join(sorted, ', ');
    }

    public static String whereClause(List<String> conditions) {
        List<String> kept = new List<String>();
        for (String c : conditions) {
            if (String.isNotBlank(c)) kept.add(c);
        }
        return kept.isEmpty() ? '' : ' WHERE ' + String.join(kept, ' AND ');
    }
}
