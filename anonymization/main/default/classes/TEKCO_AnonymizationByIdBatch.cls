/**
 * @description Field-level anonymization of one object, for a run launched from a list of IDs.
 *              Identical transformation to TEKCO_AnonymizationBatch — only the record scope
 *              differs, and both go through the same field selection.
 */
// Deliberately 'without sharing': anonymization must reach every record in the requested list.
// Running with sharing would silently skip records the launching user cannot see, leaving PII
// in place with no error.
public without sharing class TEKCO_AnonymizationByIdBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE = 200;

    private String objectApiName;
    private TEKCO_AnonymizationRunContext ctx;

    /** Only developer names cross chunk boundaries — CMDT rows in stateful fields blew the heap. */
    private List<String>    validFieldConfigDevNames = new List<String>();
    private Map<Id, String> recordTypeDevNameById    = new Map<Id, String>();

    private Integer      recordsProcessed = 0;
    private Integer      recordsFailed    = 0;
    private List<String> errors           = new List<String>();
    private Boolean      aborted          = false;

    public TEKCO_AnonymizationByIdBatch(String objectApiName, TEKCO_AnonymizationRunContext ctx) {
        this.objectApiName = objectApiName;
        this.ctx           = ctx;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(ctx.auditLogId, ctx.bypassSnapshot)) {
            aborted = true;
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            List<String> devNames = ctx.configDevNamesFor(objectApiName);
            List<TEKCO_AnonymizationFieldConfig__mdt> startConfigs = devNames.isEmpty()
                ? TEKCO_AnonymizationBatchUtils.loadFieldConfigs(objectApiName)
                : TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(devNames);

            TEKCO_AnonymizationScopeQueryBuilder.FieldSelection selection =
                TEKCO_AnonymizationScopeQueryBuilder.buildFieldSelection(
                    objectApiName, startConfigs, TEKCO_AnonymizationBatchUtils.buildPatternMap()
                );
            errors.addAll(selection.errors);
            validFieldConfigDevNames = selection.validConfigDevNames;

            if (selection.validConfigs.isEmpty()) {
                return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
            }

            if (selection.needsRecordTypeId) {
                for (RecordType rt : [
                    SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = :objectApiName
                ]) {
                    recordTypeDevNameById.put(rt.Id, rt.DeveloperName);
                }
            }

            // Must be a local of this exact name: the produced query binds ':recordIds'.
            List<Id> recordIds = ctx.recordIdsFor(objectApiName);

            return Database.getQueryLocator(
                TEKCO_AnonymizationScopeQueryBuilder.buildByIdScopeQuery(
                    objectApiName, selection.fields, 'recordIds'
                )
            );
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        TEKCO_AnonymizationExecuteService.ExecuteResult result =
            TEKCO_AnonymizationExecuteService.executeFieldAnonymization(
                scope,
                TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(validFieldConfigDevNames),
                TEKCO_AnonymizationBatchUtils.buildPatternMap(),
                recordTypeDevNameById
            );
        recordsProcessed += result.recordsProcessed;
        recordsFailed    += result.recordsFailed;
        errors.addAll(result.errors);
    }

    public void finish(Database.BatchableContext bc) {
        if (aborted) return;

        ctx.addErrors(errors);
        ctx.addProcessed(recordsProcessed);
        ctx.addFailed(recordsFailed);
        TEKCO_AnonymizationChainRunner.startNext(ctx);
    }
}
