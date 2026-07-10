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
        TEKCO_AnonymizationOrgConfigService.assertIsSandbox();

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
                if (String.isNotBlank(fieldApiName)) {
                    fieldApiNames.add(fieldApiName);
                }

                if (patternType == PATTERN_EMAIL_LOREM) {
                    fieldApiNames.add('Status');
                }

                TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(patternType);
                if (pattern != null && String.isNotBlank(pattern.TEKCO_ExternalIdField__c)
                        && objectFieldMap.containsKey(pattern.TEKCO_ExternalIdField__c.toLowerCase())) {
                    fieldApiNames.add(pattern.TEKCO_ExternalIdField__c);
                }
                if (patternType == 'NAME_FIRST_LETTER' || patternType == 'NAME_FIRST_LETTER_SFID') {
                    String funcField = TEKCO_AnonymizationOrgConfigService.getConfig().functionalIdField;
                    if (String.isNotBlank(funcField) && objectFieldMap.containsKey(funcField.toLowerCase())) {
                        fieldApiNames.add(funcField);
                    }
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

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        TEKCO_AnonymizationExecuteService.ExecuteResult result =
            TEKCO_AnonymizationExecuteService.executeFieldAnonymization(
                scope, fieldConfigs, patternsByType, recordTypeDevNameById
            );
        recordsProcessed += result.recordsProcessed;
        recordsFailed    += result.recordsFailed;
        errors.addAll(result.errors);
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
                        bypassSnapshot, accumulatedErrors, totalProcessed, 0
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
                        bypassSnapshot, accumulatedErrors, totalProcessed, 0, 0
                    ),
                    TEKCO_FieldHistoryByIdBatch.DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(
                    auditLogId, totalProcessed, recordsFailed, 0, 0, accumulatedErrors
                );
                return;
            }
            TEKCO_AnonymizationAuditService.markRunning(
                auditLogId, totalProcessed, recordsFailed, accumulatedErrors
            );
        } catch (Exception e) {
            try { TEKCO_AnonymizationBypassService.restore(bypassSnapshot); } catch (Exception ex) {}
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, totalProcessed, recordsFailed, 0, 0, accumulatedErrors, e.getMessage()
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
        return TEKCO_AnonymizationBatchUtils.popConfigsForObject(obj, historyConfigs);
    }
}
