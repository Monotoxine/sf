/**
 * @description Shared field-anonymization logic for Phase 1 batches.
 *              TEKCO_AnonymizationFieldBatch applies the same record-level patterns whichever
 *              chain it serves — only the QueryLocator scope differs between them.
 *
 *              The transformation itself (applyPatternsTo) is separated from the DML so the
 *              preview can run it on a sample without writing anything. There is exactly one
 *              implementation: what the preview shows is what a run will do.
 */
public inherited sharing class TEKCO_AnonymizationExecuteService {

    private static final String  PATTERN_EMAIL_LOREM = 'EMAIL_MESSAGE_LOREM';
    private static final Integer MAX_CAPTURED_ERRORS = 50;
    /** EmailMessage.Status picklist value for Draft. Non-draft messages are deleted, not masked. */
    private static final String  EMAIL_STATUS_DRAFT  = '5';

    public class ExecuteResult {
        public Integer      recordsProcessed = 0;
        public Integer      recordsFailed    = 0;
        public List<String> errors           = new List<String>();
    }

    /** What applying the configured patterns did to one record. */
    public class RecordOutcome {
        public Boolean modified = false;
        public Boolean toDelete = false;
    }

    /**
     * Applies every applicable pattern to one record, in place.
     *
     * @param beforeOut when non-null, receives fieldApiName -> value as it was before the
     *                  change, for each field actually modified. Pass null in batch runs:
     *                  capture then costs nothing at all.
     */
    public static RecordOutcome applyPatternsTo(
        SObject record,
        List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigs,
        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType,
        Map<Id, String> recordTypeDevNameById,
        Map<String, String> beforeOut
    ) {
        RecordOutcome outcome = new RecordOutcome();

        for (TEKCO_AnonymizationFieldConfig__mdt fc : fieldConfigs) {
            String patternType = fc.TEKCO_PatternType__c;

            if (patternType == PATTERN_EMAIL_LOREM) {
                String emailStatus = (String) record.get('Status');
                if (emailStatus == EMAIL_STATUS_DRAFT) {
                    String currentValue;
                    try { currentValue = (String) record.get(fc.TEKCO_FieldApiName__c); }
                    catch (Exception e) { continue; }
                    if (String.isNotBlank(currentValue)) {
                        if (beforeOut != null) beforeOut.put(fc.TEKCO_FieldApiName__c, currentValue);
                        record.put(fc.TEKCO_FieldApiName__c, TEKCO_AnonymizationPatternService.LOREM_TEXT);
                        outcome.modified = true;
                    }
                } else {
                    outcome.toDelete = true;
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
                if (beforeOut != null) beforeOut.put(fc.TEKCO_FieldApiName__c, currentValue);
                record.put(fc.TEKCO_FieldApiName__c, newValue);
                outcome.modified = true;
            }
        }
        return outcome;
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
            // null beforeOut: no before/after capture, no heap cost in a run.
            RecordOutcome outcome = applyPatternsTo(
                record, fieldConfigs, patternsByType, recordTypeDevNameById, null
            );
            if (outcome.toDelete)      recordsToDelete.add(record);
            else if (outcome.modified) recordsToUpdate.add(record);
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
