/**
 * @description Phase 3 delete logic, called from TEKCO_FieldHistoryBatch.
 */
public inherited sharing class TEKCO_FieldHistoryDeleteService {


    public class DeleteOutcome {
        public Integer      recordsDeleted = 0;
        public Integer      recordsFailed  = 0;
        public List<String> errors         = new List<String>();
    }

    /** Keeps the history rows whose field is anonymized on their parent's record type. */
    public static List<SObject> rowsCoveredByConfigs(
        List<SObject> rows,
        String objectApiName,
        String parentIdFieldName,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        Map<String, List<Set<String>>> recordTypesByField = new Map<String, List<Set<String>>>();
        Boolean needsRecordTypes = false;
        for (TEKCO_AnonymizationFieldConfig__mdt config : configs) {
            if (String.isBlank(config.TEKCO_FieldApiName__c)) continue;
            String field = config.TEKCO_FieldApiName__c.toLowerCase();
            if (!recordTypesByField.containsKey(field)) recordTypesByField.put(field, new List<Set<String>>());
            Set<String> covered = TEKCO_AnonymizationConfigSelector.recordTypesOf(config);
            recordTypesByField.get(field).add(covered);
            if (!covered.isEmpty()) needsRecordTypes = true;
        }

        Map<Id, String> recordTypeByParentId = needsRecordTypes
            ? parentRecordTypes(rows, objectApiName, parentIdFieldName)
            : new Map<Id, String>();

        List<SObject> kept = new List<SObject>();
        for (SObject row : rows) {
            String field = String.valueOf(row.get('Field'));
            List<Set<String>> rules = field == null ? null : recordTypesByField.get(field.toLowerCase());
            if (rules == null) continue;
            String parentRecordType = recordTypeByParentId.get((Id) row.get(parentIdFieldName));
            for (Set<String> covered : rules) {
                if (covered.isEmpty() || covered.contains(parentRecordType)) {
                    kept.add(row);
                    break;
                }
            }
        }
        return kept;
    }

    private static Map<Id, String> parentRecordTypes(
        List<SObject> rows, String objectApiName, String parentIdFieldName
    ) {
        Map<Id, String> recordTypeByParentId = new Map<Id, String>();
        if (!TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, 'recordtypeid')) {
            return recordTypeByParentId;
        }
        Set<Id> parentIds = new Set<Id>();
        for (SObject row : rows) {
            Id parentId = (Id) row.get(parentIdFieldName);
            if (parentId != null) parentIds.add(parentId);
        }
        if (parentIds.isEmpty()) return recordTypeByParentId;
        for (SObject parent : Database.queryWithBinds(
            'SELECT Id, RecordType.DeveloperName FROM ' + objectApiName + ' WHERE Id IN :parentIds',
            new Map<String, Object>{ 'parentIds' => parentIds },
            AccessLevel.SYSTEM_MODE
        )) {
            SObject recordType = parent.getSObject('RecordType');
            if (recordType != null) {
                recordTypeByParentId.put(parent.Id, (String) recordType.get('DeveloperName'));
            }
        }
        return recordTypeByParentId;
    }

    public static DeleteOutcome deleteHistoryRecords(List<SObject> scope) {
        DeleteOutcome outcome = new DeleteOutcome();
        if (scope == null || scope.isEmpty()) return outcome;

        for (Database.DeleteResult deleteResult : Database.delete(scope, false)) {
            if (deleteResult.isSuccess()) {
                outcome.recordsDeleted++;
            } else {
                outcome.recordsFailed++;
                if (outcome.errors.size() < TEKCO_AnonymizationRunContext.MAX_CAPTURED_ERRORS) {
                    List<String> messages = new List<String>();
                    for (Database.Error dmlError : deleteResult.getErrors()) {
                        messages.add(dmlError.getMessage());
                    }
                    outcome.errors.add(
                        TEKCO_AnonymizationRunContext.cap(String.join(messages, '; '))
                    );
                }
            }
        }
        return outcome;
    }
}
