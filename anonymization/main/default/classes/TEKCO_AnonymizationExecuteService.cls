/**
 * @description Shared field-anonymization execute logic for Phase 1 batches.
 *              Both TEKCO_AnonymizationBatch and TEKCO_AnonymizationByIdBatch apply the same
 *              record-level patterns — only the QueryLocator scope differs between them.
 */
public class TEKCO_AnonymizationExecuteService {

    private static final String  PATTERN_EMAIL_LOREM = 'EMAIL_MESSAGE_LOREM';
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    public class ExecuteResult {
        public Integer      recordsProcessed = 0;
        public Integer      recordsFailed    = 0;
        public List<String> errors           = new List<String>();
    }

    public static ExecuteResult executeFieldAnonymization(
        List<SObject> scope,
        List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigs,
        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType,
        Map<Id, String> recordTypeDevNameById
    ) {
        ExecuteResult result = new ExecuteResult();
        List<SObject> recordsToUpdate = new List<SObject>();
        List<SObject> recordsToDelete = new List<SObject>();

        for (SObject record : scope) {
            Boolean isModified   = false;
            Boolean shouldDelete = false;

            for (TEKCO_AnonymizationFieldConfig__mdt fc : fieldConfigs) {
                String patternType = fc.TEKCO_PatternType__c;

                if (patternType == PATTERN_EMAIL_LOREM) {
                    String emailStatus = (String) record.get('Status');
                    if (emailStatus == '5') {
                        String currentValue;
                        try { currentValue = (String) record.get(fc.TEKCO_FieldApiName__c); }
                        catch (Exception e) { continue; }
                        if (String.isNotBlank(currentValue)) {
                            record.put(fc.TEKCO_FieldApiName__c, TEKCO_AnonymizationPatternService.LOREM_TEXT);
                            isModified = true;
                        }
                    } else {
                        shouldDelete = true;
                    }
                    continue;
                }

                if (String.isNotBlank(fc.TEKCO_RecordTypeDeveloperName__c)) {
                    Id recordTypeId = (Id) record.get('RecordTypeId');
                    String rtDvName = recordTypeId != null ? recordTypeDevNameById.get(recordTypeId) : null;
                    if (rtDvName == null || rtDvName != fc.TEKCO_RecordTypeDeveloperName__c) continue;
                }

                TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(patternType);
                if (pattern == null || !pattern.TEKCO_IsActive__c) continue;

                String currentValue;
                try { currentValue = (String) record.get(fc.TEKCO_FieldApiName__c); }
                catch (Exception e) { continue; }

                String newValue = TEKCO_AnonymizationPatternService.applyPattern(
                    patternType, currentValue, record, pattern
                );

                if (newValue != null && newValue != currentValue) {
                    record.put(fc.TEKCO_FieldApiName__c, newValue);
                    isModified = true;
                }
            }

            if (shouldDelete)    recordsToDelete.add(record);
            else if (isModified) recordsToUpdate.add(record);
        }

        if (!recordsToUpdate.isEmpty()) {
            for (Database.SaveResult sr : Database.update(recordsToUpdate, false)) {
                if (sr.isSuccess()) {
                    result.recordsProcessed++;
                } else {
                    result.recordsFailed++;
                    if (result.errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> msgs = new List<String>();
                        for (Database.Error e : sr.getErrors()) msgs.add(e.getMessage());
                        result.errors.add(TEKCO_AnonymizationBatchUtils.cap(sr.getId() + ': ' + String.join(msgs, '; ')));
                    }
                }
            }
        }

        if (!recordsToDelete.isEmpty()) {
            for (Database.DeleteResult dr : Database.delete(recordsToDelete, false)) {
                if (dr.isSuccess()) {
                    result.recordsProcessed++;
                } else {
                    result.recordsFailed++;
                    if (result.errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> msgs = new List<String>();
                        for (Database.Error e : dr.getErrors()) msgs.add(e.getMessage());
                        result.errors.add(TEKCO_AnonymizationBatchUtils.cap('Delete ' + dr.getId() + ': ' + String.join(msgs, '; ')));
                    }
                }
            }
        }

        return result;
    }

}