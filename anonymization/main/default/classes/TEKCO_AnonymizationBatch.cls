/**
 * @description Field-level anonymization of one object, for a run launched from criteria
 *              (brands, objects, record types).
 *
 *              What to run next is not decided here: the run's plan lives in
 *              TEKCO_AnonymizationRunContext and TEKCO_AnonymizationChainRunner starts the next
 *              step. This class knows about one object and nothing else.
 */
// Deliberately 'without sharing': anonymization must reach every record matching the
// configured scope. Running with sharing would silently skip records the launching
// user cannot see, leaving PII in place with no error.
public without sharing class TEKCO_AnonymizationBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE = 200;

    private String objectApiName;
    private TEKCO_AnonymizationRunContext ctx;

    /**
     * Only developer names are kept across chunks. Carrying the CMDT rows themselves in stateful
     * fields is what used to blow the heap; execute() reloads them through the per-transaction
     * cache in TEKCO_AnonymizationBatchUtils.
     */
    private List<String>    validFieldConfigDevNames = new List<String>();
    private Map<Id, String> recordTypeDevNameById    = new Map<Id, String>();

    private Integer      recordsProcessed = 0;
    private Integer      recordsFailed    = 0;
    private List<String> errors           = new List<String>();
    /** Set when the sandbox guard trips in start(); finish() must not re-finalize the audit
     *  log that assertSandboxOrClose() already closed as Failed. */
    private Boolean      aborted          = false;

    public TEKCO_AnonymizationBatch(String objectApiName, TEKCO_AnonymizationRunContext ctx) {
        this.objectApiName = objectApiName;
        this.ctx           = ctx;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(ctx.auditLogId, ctx.bypassSnapshot)) {
            aborted = true;
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            // The controller already applied the user's exclusions and record-type selection to
            // these developer names. Reloading everything active would resurrect the fields the
            // user unchecked.
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
                for (RecordType recordType : [
                    SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = :objectApiName
                ]) {
                    recordTypeDevNameById.put(recordType.Id, recordType.DeveloperName);
                }
            }

            // Local, not read from ctx inline: buildFieldScopeQuery may emit a
            // ':selectedBrands' bind for EmailMessage, and Apex resolves binds against the scope
            // that calls getQueryLocator() — a variable of that exact name has to exist here.
            List<String> selectedBrands = ctx.selectedBrands;

            return Database.getQueryLocator(
                TEKCO_AnonymizationScopeQueryBuilder.buildFieldScopeQuery(
                    objectApiName,
                    selection.fields,
                    selectedBrands,
                    ctx.additionalFilterFor(objectApiName),
                    selection.hasEmailMessageLorem
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
        // The sandbox guard already closed the audit log as Failed — do not overwrite it.
        if (aborted) return;

        ctx.addErrors(errors);
        ctx.addProcessed(recordsProcessed);
        ctx.addFailed(recordsFailed);
        TEKCO_AnonymizationChainRunner.startNext(ctx);
    }
}
