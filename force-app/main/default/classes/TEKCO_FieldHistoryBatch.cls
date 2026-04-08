/**
 * @author TEKCO Team, 07/04/2026
 * @description Phase 3 of the anonymization chain: deletes field history records for
 *              fields where TEKCO_AnonymizationFieldConfig__mdt.TEKCO_DeleteHistory__c = true.
 *
 *              History object naming convention:
 *                Standard object → ObjectNameHistory     (e.g. AccountHistory)
 *                Custom object   → ObjectName__History   (e.g. MyObject__History)
 *
 *              Parent ID field convention:
 *                Standard object → ObjectNameId          (e.g. AccountId)
 *                Custom object   → ParentId
 *
 *              One batch instance per object. Chains to the next object's TEKCO_FieldHistoryBatch
 *              until all history configs are processed, then finalizes the audit log.
 */
public class TEKCO_FieldHistoryBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer DEFAULT_BATCH_SIZE  = 200;
    private static final Integer MAX_CAPTURED_ERRORS = 50;
    private static final String  CUSTOM_OBJECT_SUFFIX = '__c';

    private String                                        objectApiName;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     objectHistoryConfigs;
    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     remainingHistoryConfigs;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    private Map<String, List<String>>                     parentFiltersByObject;

    // Populated in start() when a parent filter is active; bound in the QueryLocator string
    private Set<Id>                                       relevantChildIds;

    private Integer recordsDeleted = 0;
    private Integer recordsFailed  = 0;
    private List<String> errors    = new List<String>();

    // ── Constructor ───────────────────────────────────────────────────────────

    /**
     * @description Constructs the batch with context to delete history for one object.
     * @param objectApiName          API name of the object whose history to delete.
     * @param objectHistoryConfigs   Field configs with TEKCO_DeleteHistory__c = true for this object.
     * @param selectedBrands         Brand values to filter parent records (empty = all).
     * @param auditLogId             Id of the TEKCO_AnonymizationAuditLog__c record.
     * @param remainingHistoryConfigs Field configs for subsequent objects still to process.
     * @param bypassSnapshot         Bypass state snapshot to restore at chain end.
     * @param parentFiltersByObject  Map of child object → [parentObject, parentLookup, parentRT].
     */
    public TEKCO_FieldHistoryBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> objectHistoryConfigs,
        List<String> selectedBrands,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingHistoryConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        Map<String, List<String>> parentFiltersByObject
    ) {
        this.objectApiName           = objectApiName;
        this.objectHistoryConfigs    = objectHistoryConfigs    != null
            ? objectHistoryConfigs : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.selectedBrands          = selectedBrands          != null
            ? selectedBrands : new List<String>();
        this.auditLogId              = auditLogId;
        this.remainingHistoryConfigs = remainingHistoryConfigs != null
            ? remainingHistoryConfigs : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.bypassSnapshot          = bypassSnapshot;
        this.parentFiltersByObject   = parentFiltersByObject != null
            ? parentFiltersByObject : new Map<String, List<String>>();
    }

    // ── Batchable Interface ───────────────────────────────────────────────────

    /**
     * @description Builds the dynamic SOQL query to select history records for the
     *              configured fields, filtering parent records by brand where applicable.
     * @param bc Batch context provided by the platform.
     * @return   QueryLocator for the history records to delete.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationSandboxGuard.assertIsSandbox();

        String historyObjectName = computeHistoryObjectName(objectApiName);
        String parentIdFieldName = computeParentIdFieldName(objectApiName);

        Set<String> fieldApiNames = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : objectHistoryConfigs) {
            if (String.isNotBlank(fieldConfig.TEKCO_FieldApiName__c)) {
                fieldApiNames.add(fieldConfig.TEKCO_FieldApiName__c);
            }
        }

        List<String> escapedFieldNames = new List<String>();
        for (String fieldName : fieldApiNames) {
            escapedFieldNames.add('\'' + String.escapeSingleQuotes(fieldName) + '\'');
        }

        List<String> parentFilter = parentFiltersByObject.get(objectApiName);
        String parentObjectApiName    = (parentFilter != null && parentFilter.size() > 0) ? parentFilter.get(0) : null;
        String parentLookupField      = (parentFilter != null && parentFilter.size() > 1) ? parentFilter.get(1) : null;
        String parentRecordTypeDvName = (parentFilter != null && parentFilter.size() > 2) ? parentFilter.get(2) : null;

        String fieldPrefix = ' WHERE Field IN (' + String.join(escapedFieldNames, ',') + ')'
            + ' AND ' + parentIdFieldName;

        String soqlQuery;
        if (String.isNotBlank(parentObjectApiName)) {
            // Resolve child IDs upfront to avoid forbidden nested subqueries
            List<String> parentConditions = new List<String>();
            if (!selectedBrands.isEmpty()) {
                parentConditions.add('TEKCO_Brand__c IN :selectedBrands');
            }
            if (String.isNotBlank(parentRecordTypeDvName)) {
                parentConditions.add(
                    'RecordType.DeveloperName = \'' + String.escapeSingleQuotes(parentRecordTypeDvName) + '\''
                );
            }
            String parentQuery = 'SELECT Id FROM ' + parentObjectApiName;
            if (!parentConditions.isEmpty()) {
                parentQuery += ' WHERE ' + String.join(parentConditions, ' AND ');
            }
            Set<Id> parentIds = new Map<Id, SObject>(Database.query(parentQuery)).keySet();
            this.relevantChildIds = new Map<Id, SObject>(
                Database.query('SELECT Id FROM ' + objectApiName
                    + ' WHERE ' + parentLookupField + ' IN :parentIds')
            ).keySet();
            soqlQuery = 'SELECT Id FROM ' + historyObjectName
                + fieldPrefix + ' IN :relevantChildIds';
        } else {
            soqlQuery = 'SELECT Id FROM ' + historyObjectName + fieldPrefix
                + ' IN (SELECT Id FROM ' + objectApiName
                + (selectedBrands.isEmpty() ? '' : ' WHERE TEKCO_Brand__c IN :selectedBrands')
                + ')';
        }

        return Database.getQueryLocator(soqlQuery);
    }

    /**
     * @description Deletes the history records in the current scope.
     * @param bc    Batch context provided by the platform.
     * @param scope History records to delete in this chunk.
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Database.DeleteResult[] deleteResults = Database.delete(scope, false);
        for (Database.DeleteResult deleteResult : deleteResults) {
            if (deleteResult.isSuccess()) {
                recordsDeleted++;
            } else {
                recordsFailed++;
                if (errors.size() < MAX_CAPTURED_ERRORS) {
                    List<String> errorMessages = new List<String>();
                    for (Database.Error dmlError : deleteResult.getErrors()) {
                        errorMessages.add(dmlError.getMessage());
                    }
                    errors.add(String.join(errorMessages, '; '));
                }
            }
        }
    }

    /**
     * @description Chains to the next object's TEKCO_FieldHistoryBatch, or finalizes the run.
     * @param bc Batch context provided by the platform.
     */
    public void finish(Database.BatchableContext bc) {
        if (!remainingHistoryConfigs.isEmpty()) {
            String nextObjectApiName = remainingHistoryConfigs[0].TEKCO_ObjectApiName__c;
            List<TEKCO_AnonymizationFieldConfig__mdt> nextObjectConfigs =
                popConfigsForObject(nextObjectApiName);
            Database.executeBatch(
                new TEKCO_FieldHistoryBatch(
                    nextObjectApiName,
                    nextObjectConfigs,
                    selectedBrands,
                    auditLogId,
                    remainingHistoryConfigs,
                    bypassSnapshot,
                    parentFiltersByObject
                ),
                DEFAULT_BATCH_SIZE
            );
        } else {
            TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            updateAuditLog();
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * @description Returns the history SObject API name for a given object.
     *              Standard: Account → AccountHistory
     *              Custom:   MyObj__c → MyObj__History
     * @param objectApiName API name of the parent object.
     * @return              API name of the corresponding history object.
     */
    @TestVisible
    private static String computeHistoryObjectName(String objectApiName) {
        if (objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX)) {
            return objectApiName.replace(CUSTOM_OBJECT_SUFFIX, '__History');
        }
        return objectApiName + 'History';
    }

    /**
     * @description Returns the parent ID field name on the history object.
     *              Standard: Account → AccountId
     *              Custom:   MyObj__c → ParentId
     * @param objectApiName API name of the parent object.
     * @return              API name of the parent ID field on the history object.
     */
    @TestVisible
    private static String computeParentIdFieldName(String objectApiName) {
        if (objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX)) {
            return 'ParentId';
        }
        return objectApiName + 'Id';
    }

    private List<TEKCO_AnonymizationFieldConfig__mdt> popConfigsForObject(String objectApiName) {
        List<TEKCO_AnonymizationFieldConfig__mdt> configsForObject =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : remainingHistoryConfigs) {
            if (fieldConfig.TEKCO_ObjectApiName__c == objectApiName) {
                configsForObject.add(fieldConfig);
            } else {
                remainingConfigs.add(fieldConfig);
            }
        }
        remainingHistoryConfigs = remainingConfigs;
        return configsForObject;
    }

    private void updateAuditLog() {
        if (auditLogId == null) return;
        try {
            update new TEKCO_AnonymizationAuditLog__c(
                Id               = auditLogId,
                TEKCO_Status__c        = recordsFailed > 0 ? 'Partial' : 'Success',
                TEKCO_EndTime__c      = Datetime.now(),
                TEKCO_ErrorMessage__c = errors.isEmpty() ? null : String.join(errors, '\n')
            );
        } catch (Exception e) {
            // Silent — audit log failure must not break the batch chain
        }
    }
}
