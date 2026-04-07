/**
 * FieldHistoryBatch
 * Phase 3 of the anonymization chain: deletes field history records for
 * fields where TEKCO_AnonymizationFieldConfig__mdt.Delete_History__c = true.
 *
 * History object naming:
 *   Standard object  → ObjectNameHistory      (e.g. AccountHistory)
 *   Custom object    → ObjectName__History    (e.g. MyObject__History)
 *
 * Parent ID field:
 *   Standard object  → ObjectNameId           (e.g. AccountId)
 *   Custom object    → ParentId
 *
 * One batch instance per object. Chains to the next object's FieldHistoryBatch
 * until all history configs are processed, then finalizes the audit log.
 */
public class FieldHistoryBatch implements Database.Batchable<SObject>, Database.Stateful {

    private String                                       objectApiName;
    private List<TEKCO_AnonymizationFieldConfig__mdt>    objectHistoryConfigs; // configs for THIS object
    private List<String>                                 selectedBrands;
    private Id                                           auditLogId;
    private List<TEKCO_AnonymizationFieldConfig__mdt>    remainingHistoryConfigs; // configs for NEXT objects
    private AnonymizationBypassService.BypassSnapshot    bypassSnapshot;

    private Integer recordsDeleted = 0;
    private Integer recordsFailed  = 0;
    private List<String> errors    = new List<String>();

    private static final Integer DEFAULT_BATCH_SIZE = 200;

    // ── Constructor ───────────────────────────────────────────────────────────

    public FieldHistoryBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> objectHistoryConfigs,
        List<String> selectedBrands,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs,
        AnonymizationBypassService.BypassSnapshot bypassSnapshot
    ) {
        this.objectApiName           = objectApiName;
        this.objectHistoryConfigs    = objectHistoryConfigs    != null ? objectHistoryConfigs    : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.selectedBrands          = selectedBrands          != null ? selectedBrands          : new List<String>();
        this.auditLogId              = auditLogId;
        this.remainingHistoryConfigs = remainingHistoryConfigs != null ? remainingHistoryConfigs : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.bypassSnapshot          = bypassSnapshot;
    }

    // ── Batchable Interface ───────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        AnonymizationSandboxGuard.assertIsSandbox();

        String historyObject  = getHistoryObjectName(objectApiName);
        String parentIdField  = getParentIdField(objectApiName);

        // Collect field names to delete history for
        Set<String> fieldNames = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt cfg : objectHistoryConfigs) {
            if (String.isNotBlank(cfg.Field_API_Name__c)) fieldNames.add(cfg.Field_API_Name__c);
        }
        // Escape field names for SOQL IN clause
        List<String> escapedFields = new List<String>();
        for (String f : fieldNames) escapedFields.add('\'' + String.escapeSingleQuotes(f) + '\'');

        String soql = 'SELECT Id FROM ' + historyObject
                    + ' WHERE Field IN (' + String.join(escapedFields, ',') + ')'
                    + ' AND ' + parentIdField
                    + '   IN (SELECT Id FROM ' + objectApiName;

        if (!selectedBrands.isEmpty()) {
            soql += ' WHERE TEKCO_Brand__c IN :selectedBrands';
        }

        soql += ')';

        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Database.DeleteResult[] results = Database.delete(scope, false);
        for (Database.DeleteResult r : results) {
            if (r.isSuccess()) {
                recordsDeleted++;
            } else {
                recordsFailed++;
                if (errors.size() < 50) {
                    List<String> msgs = new List<String>();
                    for (Database.Error err : r.getErrors()) msgs.add(err.getMessage());
                    errors.add(String.join(msgs, '; '));
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (!remainingHistoryConfigs.isEmpty()) {
            // More objects have history to delete
            String nextObj = remainingHistoryConfigs[0].Object_API_Name__c;
            List<TEKCO_AnonymizationFieldConfig__mdt> nextObjConfigs = popConfigsForObject(nextObj);
            Database.executeBatch(
                new FieldHistoryBatch(nextObj, nextObjConfigs, selectedBrands, auditLogId,
                                      remainingHistoryConfigs, bypassSnapshot),
                DEFAULT_BATCH_SIZE
            );
        } else {
            // End of entire chain — restore bypass settings
            AnonymizationBypassService.restore(bypassSnapshot);
            updateAuditLog();
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Returns the history SObject API name for a given object.
     * Standard: Account → AccountHistory
     * Custom:   MyObj__c → MyObj__History
     */
    @TestVisible
    private static String getHistoryObjectName(String objectApiName) {
        if (objectApiName.endsWith('__c')) {
            return objectApiName.replace('__c', '__History');
        }
        return objectApiName + 'History';
    }

    /**
     * Returns the parent ID field name on the history object.
     * Standard: Account → AccountId
     * Custom:   MyObj__c → ParentId
     */
    @TestVisible
    private static String getParentIdField(String objectApiName) {
        if (objectApiName.endsWith('__c')) {
            return 'ParentId';
        }
        return objectApiName + 'Id';
    }

    private List<TEKCO_AnonymizationFieldConfig__mdt> popConfigsForObject(String objectName) {
        List<TEKCO_AnonymizationFieldConfig__mdt> forObj    = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> remaining = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt cfg : remainingHistoryConfigs) {
            if (cfg.Object_API_Name__c == objectName) forObj.add(cfg);
            else remaining.add(cfg);
        }
        remainingHistoryConfigs = remaining;
        return forObj;
    }

    private void updateAuditLog() {
        if (auditLogId == null) return;
        try {
            update new Anonymization_Audit_Log__c(
                Id               = auditLogId,
                Status__c        = recordsFailed > 0 ? 'Partial' : 'Success',
                End_Time__c      = Datetime.now(),
                Error_Message__c = errors.isEmpty() ? null : String.join(errors, '\n')
            );
        } catch (Exception e) {}
    }
}
