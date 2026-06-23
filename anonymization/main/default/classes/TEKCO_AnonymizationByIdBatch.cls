/**
 * @description Phase 1 of the by-ID anonymization chain.
 *              Applies field-level patterns to an explicit set of record IDs for one SObject,
 *              then chains to TEKCO_ContentDocumentByIdBatch and TEKCO_FieldHistoryByIdBatch.
 *
 *              Chain: TEKCO_AnonymizationByIdBatch (per object)
 *                  → TEKCO_ContentDocumentByIdBatch (per object with DELETE_CONTENT_DOCUMENT)
 *                  → TEKCO_FieldHistoryByIdBatch (per object with TEKCO_DeleteHistory__c)
 */
public class TEKCO_AnonymizationByIdBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE   = 2000;
    private static final Integer MAX_CAPTURED_ERRORS = 50;
    private static final String  PATTERN_DELETE_CD   = 'DELETE_CONTENT_DOCUMENT';
    private static final String  PATTERN_EMAIL_LOREM = 'EMAIL_MESSAGE_LOREM';

    private String                                       objectApiName;
    private List<Id>                                     recordIds;
    private List<TEKCO_AnonymizationFieldConfig__mdt>    fieldConfigs;
    private Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType;
    private Id                                           auditLogId;
    private Map<String, List<Id>>                        remainingObjectIds;
    private List<TEKCO_AnonymizationFieldConfig__mdt>    contentDocConfigs;
    private Map<String, List<Id>>                        contentDocIdsByObject;
    private List<TEKCO_AnonymizationFieldConfig__mdt>    historyConfigs;
    private Map<String, List<Id>>                        historyIdsByObject;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;

    private Map<Id, String> recordTypeDevNameById   = new Map<Id, String>();
    private Integer recordsProcessed                = 0;
    private Integer recordsFailed                   = 0;
    private Integer accumulatedRecordsProcessed     = 0;
    private List<String> errors                     = new List<String>();
    private List<String> accumulatedErrors          = new List<String>();

    public TEKCO_AnonymizationByIdBatch(
        String objectApiName,
        List<Id> recordIds,
        List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigs,
        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType,
        Id auditLogId,
        Map<String, List<Id>> remainingObjectIds,
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs,
        Map<String, List<Id>> contentDocIdsByObject,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs,
        Map<String, List<Id>> historyIdsByObject,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed
    ) {
        this.objectApiName              = objectApiName;
        this.recordIds                  = recordIds             != null ? recordIds             : new List<Id>();
        this.fieldConfigs               = fieldConfigs;
        this.patternsByType             = patternsByType;
        this.auditLogId                 = auditLogId;
        this.remainingObjectIds         = remainingObjectIds    != null ? remainingObjectIds    : new Map<String, List<Id>>();
        this.contentDocConfigs          = contentDocConfigs     != null ? contentDocConfigs     : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.contentDocIdsByObject      = contentDocIdsByObject != null ? contentDocIdsByObject : new Map<String, List<Id>>();
        this.historyConfigs             = historyConfigs        != null ? historyConfigs        : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.historyIdsByObject         = historyIdsByObject    != null ? historyIdsByObject    : new Map<String, List<Id>>();
        this.bypassSnapshot             = bypassSnapshot;
        this.accumulatedErrors          = accumulatedErrors     != null ? accumulatedErrors     : new List<String>();
        this.accumulatedRecordsProcessed = accumulatedRecordsProcessed != null ? accumulatedRecordsProcessed : 0;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationPatternService.assertIsSandbox();

        Schema.SObjectType sObjectType = Schema.getGlobalDescribe().get(objectApiName);
        if (sObjectType == null) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        try {
            Set<String> fieldApiNames    = new Set<String>{ 'Id' };
            Boolean needsRecordTypeId    = false;

            Map<String, Schema.SObjectField> objectFieldMap =
                sObjectType.getDescribe().fields.getMap();
            List<TEKCO_AnonymizationFieldConfig__mdt> validFieldConfigs =
                new List<TEKCO_AnonymizationFieldConfig__mdt>();

            for (TEKCO_AnonymizationFieldConfig__mdt fc : fieldConfigs) {
                String patternType  = fc.TEKCO_PatternType__c;
                String fieldApiName = fc.TEKCO_FieldApiName__c;

                // DELETE_CONTENT_DOCUMENT is handled by TEKCO_ContentDocumentByIdBatch
                if (patternType == PATTERN_DELETE_CD) continue;

                if (String.isNotBlank(fieldApiName)
                        && !objectFieldMap.containsKey(fieldApiName.toLowerCase())) {
                    errors.add('Field not found on ' + objectApiName + ', skipped: ' + fieldApiName);
                    continue;
                }

                validFieldConfigs.add(fc);
                fieldApiNames.add(fieldApiName);

                if (patternType == PATTERN_EMAIL_LOREM) {
                    fieldApiNames.add('Status');
                }

                TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(patternType);
                if (pattern != null && String.isNotBlank(pattern.TEKCO_ExternalIdField__c)
                        && objectFieldMap.containsKey(pattern.TEKCO_ExternalIdField__c.toLowerCase())) {
                    fieldApiNames.add(pattern.TEKCO_ExternalIdField__c);
                }
                if ((patternType == 'NAME_FIRST_LETTER' || patternType == 'NAME_FIRST_LETTER_SFID')
                        && objectFieldMap.containsKey('tekco_functionalid__c')) {
                    fieldApiNames.add('TEKCO_FunctionalId__c');
                }
                if (String.isNotBlank(fc.TEKCO_RecordTypeDeveloperName__c)) {
                    needsRecordTypeId = true;
                }
            }
            fieldConfigs = validFieldConfigs;

            if (needsRecordTypeId) {
                fieldApiNames.add('RecordTypeId');
                for (RecordType rt : [
                    SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = :objectApiName
                ]) {
                    recordTypeDevNameById.put(rt.Id, rt.DeveloperName);
                }
            }

            return Database.getQueryLocator(
                'SELECT ' + String.join(new List<String>(fieldApiNames), ', ')
                + ' FROM ' + objectApiName
                + ' WHERE Id IN :recordIds'
            );
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }
    }

    // Identical logic to TEKCO_AnonymizationBatch.execute() — no brand/parent filtering needed
    // because scope is already restricted to the explicit recordIds list via the QueryLocator.
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<SObject> recordsToUpdate = new List<SObject>();
        List<SObject> recordsToDelete = new List<SObject>();

        for (SObject record : scope) {
            Boolean isModified   = false;
            Boolean shouldDelete = false;

            for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : fieldConfigs) {
                String patternType = fieldConfig.TEKCO_PatternType__c;

                if (patternType == PATTERN_EMAIL_LOREM) {
                    String emailStatus = (String) record.get('Status');
                    if (emailStatus == '5') {
                        String currentValue;
                        try {
                            currentValue = (String) record.get(fieldConfig.TEKCO_FieldApiName__c);
                        } catch (Exception e) { continue; }
                        if (String.isNotBlank(currentValue)) {
                            record.put(fieldConfig.TEKCO_FieldApiName__c,
                                TEKCO_AnonymizationPatternService.LOREM_TEXT);
                            isModified = true;
                        }
                    } else {
                        shouldDelete = true;
                    }
                    continue;
                }

                if (String.isNotBlank(fieldConfig.TEKCO_RecordTypeDeveloperName__c)) {
                    Id recordTypeId = (Id) record.get('RecordTypeId');
                    String recordTypeDeveloperName = recordTypeId != null
                        ? recordTypeDevNameById.get(recordTypeId) : null;
                    if (recordTypeDeveloperName == null
                            || recordTypeDeveloperName != fieldConfig.TEKCO_RecordTypeDeveloperName__c) {
                        continue;
                    }
                }

                TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(patternType);
                if (pattern == null || !pattern.TEKCO_IsActive__c) continue;

                String currentValue;
                try {
                    currentValue = (String) record.get(fieldConfig.TEKCO_FieldApiName__c);
                } catch (Exception e) { continue; }

                String newValue = TEKCO_AnonymizationPatternService.applyPattern(
                    patternType, currentValue, record, pattern
                );

                if (newValue != null && newValue != currentValue) {
                    record.put(fieldConfig.TEKCO_FieldApiName__c, newValue);
                    isModified = true;
                }
            }

            if (shouldDelete) {
                recordsToDelete.add(record);
            } else if (isModified) {
                recordsToUpdate.add(record);
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = Database.update(recordsToUpdate, false);
            for (Database.SaveResult sr : saveResults) {
                if (sr.isSuccess()) {
                    recordsProcessed++;
                } else {
                    recordsFailed++;
                    if (errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> msgs = new List<String>();
                        for (Database.Error e : sr.getErrors()) msgs.add(e.getMessage());
                        errors.add(sr.getId() + ': ' + String.join(msgs, '; '));
                    }
                }
            }
        }

        if (!recordsToDelete.isEmpty()) {
            Database.DeleteResult[] deleteResults = Database.delete(recordsToDelete, false);
            for (Database.DeleteResult dr : deleteResults) {
                if (dr.isSuccess()) {
                    recordsProcessed++;
                } else {
                    recordsFailed++;
                    if (errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> msgs = new List<String>();
                        for (Database.Error e : dr.getErrors()) msgs.add(e.getMessage());
                        errors.add('Delete ' + dr.getId() + ': ' + String.join(msgs, '; '));
                    }
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        accumulatedErrors.addAll(errors);
        Integer totalProcessed = accumulatedRecordsProcessed + recordsProcessed;

        try {
            if (!remainingObjectIds.isEmpty()) {
                String nextObj = new List<String>(remainingObjectIds.keySet())[0];
                List<Id> nextIds = remainingObjectIds.remove(nextObj);
                List<TEKCO_AnonymizationFieldConfig__mdt> nextConfigs = loadFieldConfigs(nextObj);
                Database.executeBatch(
                    new TEKCO_AnonymizationByIdBatch(
                        nextObj, nextIds, nextConfigs, patternsByType, auditLogId,
                        remainingObjectIds, contentDocConfigs, contentDocIdsByObject,
                        historyConfigs, historyIdsByObject, bypassSnapshot,
                        accumulatedErrors, totalProcessed
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!contentDocConfigs.isEmpty()) {
                TEKCO_AnonymizationFieldConfig__mdt firstConfig = contentDocConfigs.remove(0);
                String firstObj = firstConfig.TEKCO_ObjectApiName__c;
                Database.executeBatch(
                    new TEKCO_ContentDocumentByIdBatch(
                        firstObj, contentDocIdsByObject.get(firstObj), auditLogId,
                        contentDocConfigs, contentDocIdsByObject,
                        historyConfigs, historyIdsByObject,
                        bypassSnapshot, accumulatedErrors, totalProcessed
                    ),
                    TEKCO_ContentDocumentByIdBatch.DEFAULT_BATCH_SIZE
                );
            } else if (!historyConfigs.isEmpty()) {
                String firstHistObj = historyConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> firstHistConfigs =
                    popHistoryConfigsForObject(firstHistObj);
                Database.executeBatch(
                    new TEKCO_FieldHistoryByIdBatch(
                        firstHistObj, firstHistConfigs, historyIdsByObject.get(firstHistObj),
                        auditLogId, historyConfigs, historyIdsByObject,
                        bypassSnapshot, accumulatedErrors, totalProcessed
                    ),
                    TEKCO_FieldHistoryByIdBatch.DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(
                    auditLogId, totalProcessed, recordsFailed, accumulatedErrors
                );
                return;
            }
            TEKCO_AnonymizationAuditService.markRunning(
                auditLogId, totalProcessed, recordsFailed, accumulatedErrors
            );
        } catch (Exception e) {
            try { TEKCO_AnonymizationBypassService.restore(bypassSnapshot); } catch (Exception ex) {}
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, totalProcessed, recordsFailed, accumulatedErrors, e.getMessage()
            );
        }
    }

    private static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigs(String objectApiName) {
        return [
            SELECT TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c, TEKCO_PatternType__c,
                   TEKCO_IsActive__c, TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_ObjectApiName__c = :objectApiName AND TEKCO_IsActive__c = true
        ];
    }

    private List<TEKCO_AnonymizationFieldConfig__mdt> popHistoryConfigsForObject(String obj) {
        List<TEKCO_AnonymizationFieldConfig__mdt> forObj    = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> remaining = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : historyConfigs) {
            if (fc.TEKCO_ObjectApiName__c == obj) forObj.add(fc);
            else remaining.add(fc);
        }
        historyConfigs = remaining;
        return forObj;
    }
}
