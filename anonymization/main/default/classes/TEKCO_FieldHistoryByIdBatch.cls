/**
 * @description Phase 3 of the by-ID anonymization chain.
 *              Deletes field history records for the given record IDs where
 *              TEKCO_AnonymizationFieldConfig__mdt.TEKCO_DeleteHistory__c = true.
 *              Mirrors TEKCO_FieldHistoryBatch but filters by explicit parent IDs.
 */
public class TEKCO_FieldHistoryByIdBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE   = 2000;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    private String                                       objectApiName;
    private List<TEKCO_AnonymizationFieldConfig__mdt>    objectHistoryConfigs;
    private List<Id>                                     recordIds;
    private Id                                           auditLogId;
    private List<TEKCO_AnonymizationFieldConfig__mdt>    remainingHistoryConfigs;
    private Map<String, List<Id>>                        historyIdsByObject;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;

    private Integer recordsDeleted               = 0;
    private Integer recordsFailed                = 0;
    private Integer accumulatedRecordsProcessed  = 0;
    private List<String> errors                  = new List<String>();
    private List<String> accumulatedErrors       = new List<String>();

    public TEKCO_FieldHistoryByIdBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> objectHistoryConfigs,
        List<Id> recordIds,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs,
        Map<String, List<Id>> historyIdsByObject,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed
    ) {
        this.objectApiName          = objectApiName;
        this.objectHistoryConfigs   = objectHistoryConfigs   != null ? objectHistoryConfigs   : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.recordIds              = recordIds              != null ? recordIds              : new List<Id>();
        this.auditLogId             = auditLogId;
        this.remainingHistoryConfigs = remainingHistoryConfigs != null ? remainingHistoryConfigs : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.historyIdsByObject     = historyIdsByObject     != null ? historyIdsByObject     : new Map<String, List<Id>>();
        this.bypassSnapshot         = bypassSnapshot;
        this.accumulatedErrors           = accumulatedErrors     != null ? accumulatedErrors     : new List<String>();
        this.accumulatedRecordsProcessed = accumulatedRecordsProcessed != null ? accumulatedRecordsProcessed : 0;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationOrgConfigService.assertIsSandbox();

        String historyObjectName = computeHistoryObjectName(objectApiName);
        String parentIdFieldName = computeParentIdFieldName(objectApiName);

        if (Schema.getGlobalDescribe().get(historyObjectName) == null) {
            errors.add('Field history not enabled for object, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        Set<String> fieldApiNames = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : objectHistoryConfigs) {
            if (String.isNotBlank(fc.TEKCO_FieldApiName__c)) fieldApiNames.add(fc.TEKCO_FieldApiName__c);
        }

        List<String> escapedFields = new List<String>();
        for (String fn : fieldApiNames) {
            escapedFields.add('\'' + String.escapeSingleQuotes(fn) + '\'');
        }

        return Database.getQueryLocator(
            'SELECT Id FROM ' + historyObjectName
            + ' WHERE Field IN (' + String.join(escapedFields, ', ') + ')'
            + ' AND ' + parentIdFieldName + ' IN :recordIds'
        );
    }

    // Identical to TEKCO_FieldHistoryBatch.execute()
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Database.DeleteResult[] deleteResults = Database.delete(scope, false);
        for (Database.DeleteResult dr : deleteResults) {
            if (dr.isSuccess()) {
                recordsDeleted++;
            } else {
                recordsFailed++;
                if (errors.size() < MAX_CAPTURED_ERRORS) {
                    List<String> msgs = new List<String>();
                    for (Database.Error e : dr.getErrors()) msgs.add(e.getMessage());
                    errors.add(String.join(msgs, '; '));
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        accumulatedErrors.addAll(errors);
        Integer totalProcessed = accumulatedRecordsProcessed + recordsDeleted;

        try {
            if (!remainingHistoryConfigs.isEmpty()) {
                String nextObj = remainingHistoryConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> nextConfigs = popConfigsForObject(nextObj);
                Database.executeBatch(
                    new TEKCO_FieldHistoryByIdBatch(
                        nextObj, nextConfigs, historyIdsByObject.get(nextObj),
                        auditLogId, remainingHistoryConfigs, historyIdsByObject,
                        bypassSnapshot, accumulatedErrors, totalProcessed
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(
                    auditLogId, totalProcessed, recordsFailed, accumulatedErrors
                );
            }
        } catch (Exception e) {
            try { TEKCO_AnonymizationBypassService.restore(bypassSnapshot); } catch (Exception ex) {}
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, totalProcessed, recordsFailed, accumulatedErrors, e.getMessage()
            );
        }
    }

    private static String computeHistoryObjectName(String objectApiName) {
        return TEKCO_AnonymizationBatchUtils.computeHistoryObjectName(objectApiName);
    }

    private static String computeParentIdFieldName(String objectApiName) {
        return TEKCO_AnonymizationBatchUtils.computeParentIdFieldName(objectApiName);
    }

    private List<TEKCO_AnonymizationFieldConfig__mdt> popConfigsForObject(String obj) {
        return TEKCO_AnonymizationBatchUtils.popConfigsForObject(obj, remainingHistoryConfigs);
    }
}
