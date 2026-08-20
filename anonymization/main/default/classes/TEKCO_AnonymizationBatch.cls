/**
 * @author
 * @description Chain order: TEKCO_AnonymizationBatch → TEKCO_ContentDocumentBatch → TEKCO_FieldHistoryBatch
 */
// Deliberately 'without sharing': anonymization must reach every record matching the
// configured scope. Running with sharing would silently skip records the launching
// user cannot see, leaving PII in place with no error.
public without sharing class TEKCO_AnonymizationBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE      = 200;
    public static final Integer MAX_ACCUMULATED_ERRORS  = 200;

    private String                                        objectApiName;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     fieldConfigs;
    private Map<String, TEKCO_AnonymizationPattern__mdt>  patternsByType;
    private List<String>                                  validFieldConfigDevNames = new List<String>();
    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<String>                                  remainingObjects;
    private List<String>                                  contentDocConfigDevNames;
    private List<String>                                  historyConfigDevNames;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;

    /**
     * Config DeveloperNames per object, as filtered by the controller (user exclusions and
     * record-type selection applied). finish() loads the next object's configs from here —
     * reloading everything active would silently resurrect the fields the user unchecked.
     */
    private Map<String, List<String>>                     configDevNamesByObject;
    private Map<String, String>                           additionalFiltersByObject;
    private Map<Id, String>                               recordTypeDevNameById =
        new Map<Id, String>();

    private Integer recordsProcessed        = 0;
    private Integer recordsFailed           = 0;
    private Integer accumulatedRecordsProcessed = 0;
    private Integer accumulatedRecordsFailed    = 0;
    /** Set when the sandbox guard trips in start(); finish() must not re-finalize
     *  the audit log that assertSandboxOrClose() already closed as Failed. */
    private Boolean aborted = false;
    private List<String> errors             = new List<String>();
    private List<String> accumulatedErrors  = new List<String>();


    public TEKCO_AnonymizationBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigs,
        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType,
        List<String> selectedBrands,
        Id auditLogId,
        List<String> remainingObjects,
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed,
        Integer accumulatedRecordsFailed,
        Map<String, List<String>> configDevNamesByObject,
        Map<String, String> additionalFiltersByObject
    ) {
        this.objectApiName        = objectApiName;
        this.fieldConfigs         = fieldConfigs;
        this.patternsByType       = patternsByType;
        this.selectedBrands       = selectedBrands    != null ? selectedBrands    : new List<String>();
        this.auditLogId           = auditLogId;
        this.remainingObjects  = remainingObjects  != null ? remainingObjects  : new List<String>();
        this.contentDocConfigDevNames = TEKCO_AnonymizationBatchUtils.toDevNames(contentDocConfigs);
        this.historyConfigDevNames    = TEKCO_AnonymizationBatchUtils.toDevNames(historyConfigs);
        this.bypassSnapshot             = bypassSnapshot;
        this.accumulatedErrors          = accumulatedErrors != null ? accumulatedErrors : new List<String>();
        this.accumulatedRecordsProcessed = accumulatedRecordsProcessed != null ? accumulatedRecordsProcessed : 0;
        this.accumulatedRecordsFailed    = accumulatedRecordsFailed    != null ? accumulatedRecordsFailed    : 0;
        this.configDevNamesByObject = configDevNamesByObject != null
            ? configDevNamesByObject : new Map<String, List<String>>();
        this.additionalFiltersByObject = additionalFiltersByObject != null
            ? additionalFiltersByObject : new Map<String, String>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(auditLogId, bypassSnapshot)) {
            aborted = true;
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            List<TEKCO_AnonymizationFieldConfig__mdt> startConfigs =
                this.fieldConfigs != null
                    ? this.fieldConfigs
                    : TEKCO_AnonymizationBatchUtils.loadFieldConfigs(objectApiName);
            Map<String, TEKCO_AnonymizationPattern__mdt> startPatterns =
                this.patternsByType != null
                    ? this.patternsByType
                    : TEKCO_AnonymizationBatchUtils.buildPatternMap();

            TEKCO_AnonymizationScopeQueryBuilder.FieldSelection selection =
                TEKCO_AnonymizationScopeQueryBuilder.buildFieldSelection(
                    objectApiName, startConfigs, startPatterns
                );
            errors.addAll(selection.errors);

            validFieldConfigDevNames = selection.validConfigDevNames;
            // Configs and patterns are deliberately dropped from the stateful fields: carrying
            // the CMDT rows across chunks is what used to blow the heap. execute() re-queries
            // them by developer name, through the per-transaction cache in BatchUtils.
            this.fieldConfigs   = null;
            this.patternsByType = null;

            if (selection.validConfigs.isEmpty()) {
                return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
            }

            if (selection.needsRecordTypeId) {
                for (RecordType recordType : [
                    SELECT Id, DeveloperName
                    FROM RecordType
                    WHERE SobjectType = :objectApiName
                ]) {
                    recordTypeDevNameById.put(recordType.Id, recordType.DeveloperName);
                }
            }

            return Database.getQueryLocator(
                TEKCO_AnonymizationScopeQueryBuilder.buildFieldScopeQuery(
                    objectApiName,
                    selection.fields,
                    selectedBrands,
                    additionalFiltersByObject.get(objectApiName),
                    selection.hasEmailMessageLorem
                )
            );
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<TEKCO_AnonymizationFieldConfig__mdt> localFieldConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(validFieldConfigDevNames);
        Map<String, TEKCO_AnonymizationPattern__mdt> localPatterns = TEKCO_AnonymizationBatchUtils.buildPatternMap();

        TEKCO_AnonymizationExecuteService.ExecuteResult result =
            TEKCO_AnonymizationExecuteService.executeFieldAnonymization(
                scope, localFieldConfigs, localPatterns, recordTypeDevNameById
            );
        recordsProcessed += result.recordsProcessed;
        recordsFailed    += result.recordsFailed;
        errors.addAll(result.errors);
    }

    public void finish(Database.BatchableContext bc) {
        // The sandbox guard already closed the audit log as Failed — do not overwrite it.
        if (aborted) return;

        for (String e : errors) {
            if (accumulatedErrors.size() < MAX_ACCUMULATED_ERRORS) {
                accumulatedErrors.add(TEKCO_AnonymizationBatchUtils.cap(e));
            }
        }
        Integer totalProcessed = accumulatedRecordsProcessed + recordsProcessed;
        Integer totalFailed    = accumulatedRecordsFailed    + recordsFailed;
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(contentDocConfigDevNames);
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(historyConfigDevNames);
        try {
            if (!remainingObjects.isEmpty()) {
                String nextObjectApiName = remainingObjects.remove(0);
                // The controller filtered these configs (user exclusions, record types).
                // Reloading everything active would resurrect the unchecked fields.
                List<String> nextDevNames = configDevNamesByObject.get(nextObjectApiName);
                List<TEKCO_AnonymizationFieldConfig__mdt> nextObjectConfigs =
                    (nextDevNames != null && !nextDevNames.isEmpty())
                        ? TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(nextDevNames)
                        : TEKCO_AnonymizationBatchUtils.loadFieldConfigs(nextObjectApiName);
                Database.executeBatch(
                    new TEKCO_AnonymizationBatch(
                        nextObjectApiName,
                        nextObjectConfigs,
                        patternsByType,
                        selectedBrands,
                        auditLogId,
                        remainingObjects,
                        contentDocConfigs,
                        historyConfigs,
                        bypassSnapshot,
                        accumulatedErrors,
                        totalProcessed,
                        totalFailed,
                        configDevNamesByObject,
                        additionalFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!contentDocConfigs.isEmpty()) {
                TEKCO_AnonymizationFieldConfig__mdt firstContentDocConfig = contentDocConfigs.remove(0);
                Database.executeBatch(
                    new TEKCO_ContentDocumentBatch(
                        firstContentDocConfig,
                        selectedBrands,
                        auditLogId,
                        contentDocConfigs,
                        historyConfigs,
                        bypassSnapshot,
                        accumulatedErrors,
                        totalProcessed,
                        totalFailed,
                        0,
                        additionalFiltersByObject
                    ),
                    TEKCO_ContentDocumentBatch.DEFAULT_BATCH_SIZE
                );
            } else if (!historyConfigs.isEmpty()) {
                String firstHistoryObject = historyConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> firstObjectHistoryConfigs =
                    TEKCO_AnonymizationBatchUtils.popConfigsForObject(firstHistoryObject, historyConfigs);
                Database.executeBatch(
                    new TEKCO_FieldHistoryBatch(
                        firstHistoryObject,
                        firstObjectHistoryConfigs,
                        selectedBrands,
                        auditLogId,
                        historyConfigs,
                        bypassSnapshot,
                        accumulatedErrors,
                        totalProcessed,
                        totalFailed,
                        0,
                        0,
                        additionalFiltersByObject
                    ),
                    TEKCO_FieldHistoryBatch.DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(auditLogId, totalProcessed, totalFailed, 0, 0, accumulatedErrors);
                return;
            }
            TEKCO_AnonymizationAuditService.markRunning(auditLogId, totalProcessed, totalFailed, accumulatedErrors);
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) {
                System.debug(LoggingLevel.ERROR, 'Bypass restore failed; flags may remain enabled: ' + restoreEx.getMessage());
            }
            TEKCO_AnonymizationAuditService.closeFailed(auditLogId, totalProcessed, totalFailed, 0, 0, accumulatedErrors, e.getMessage());
        }
    }


}
