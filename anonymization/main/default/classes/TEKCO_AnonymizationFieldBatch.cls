/**
 * @description Field-level anonymization of one object. Serves both chains: a run scoped by
 *              criteria (brands, objects, record types) and a run scoped by an explicit ID list
 *              differ only in which records they read — the transformation, the guards, the
 *              counters and the chaining are the same.
 *
 *              Merged from TEKCO_AnonymizationBatch and TEKCO_AnonymizationByIdBatch, which had
 *              drifted apart repeatedly: the heap fix, the error cap and the error truncation
 *              landed on one side only (bc367b5), the DELETE_CONTENT_DOCUMENT skip on the other
 *              (3e893d2). Keeping one class makes that family of bug impossible rather than
 *              merely unlikely.
 *
 *              What to run next is not decided here: the plan lives in
 *              TEKCO_AnonymizationRunContext and TEKCO_AnonymizationChainRunner starts the next
 *              step. This class knows about one object and nothing else.
 */
// Deliberately 'without sharing': anonymization must reach every record in the configured
// scope. Running with sharing would silently skip records the launching user cannot see,
// leaving PII in place with no error.
public without sharing class TEKCO_AnonymizationFieldBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE = 200;

    private String objectApiName;
    private TEKCO_AnonymizationRunContext ctx;

    /**
     * Only developer names are kept across chunks. Carrying the CMDT rows themselves in stateful
     * fields is what used to blow the heap; execute() reloads them through the per-transaction
     * cache in TEKCO_AnonymizationConfigSelector.
     */
    private List<String>    validFieldConfigDevNames = new List<String>();
    private Map<Id, String> recordTypeDevNameById    = new Map<Id, String>();

    private Integer      recordsProcessed = 0;
    private Integer      recordsFailed    = 0;
    private List<String> errors           = new List<String>();
    /** Set when the sandbox guard trips in start(); finish() must not re-finalize the audit
     *  log that assertSandboxOrClose() already closed as Failed. */
    private Boolean      aborted          = false;

    public TEKCO_AnonymizationFieldBatch(String objectApiName, TEKCO_AnonymizationRunContext ctx) {
        this.objectApiName = objectApiName;
        this.ctx           = ctx;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationGuard.assertSandboxOrClose(ctx.auditLogId, ctx.bypassSnapshot)) {
            aborted = true;
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            // The controller already applied the user's exclusions and record-type selection to
            // these developer names. Reloading everything active would resurrect the fields the
            // user unchecked.
            List<String> devNames = ctx.configDevNamesFor(objectApiName);
            List<TEKCO_AnonymizationFieldConfig__mdt> startConfigs = devNames.isEmpty()
                ? TEKCO_AnonymizationConfigSelector.loadFieldConfigs(objectApiName)
                : TEKCO_AnonymizationConfigSelector.loadFieldConfigsByDevNames(devNames);

            TEKCO_AnonymizationScopeQueryBuilder.FieldSelection selection =
                TEKCO_AnonymizationScopeQueryBuilder.buildFieldSelection(
                    objectApiName, startConfigs, TEKCO_AnonymizationConfigSelector.buildPatternMap()
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

            // Both bind names must exist as locals in THIS scope: Database.getQueryLocator
            // resolves ':name' against the scope that calls it, and the query built below names
            // exactly one of them. An unused local is harmless; a missing one is a runtime error.
            List<String> selectedBrands = ctx.selectedBrands;
            List<Id>     recordIds      = ctx.recordIdsFor(objectApiName);

            // The mode is read from ctx.byId, never inferred from recordIds being non-empty:
            // only the By ID controller fills that map, but the intent stays explicit.
            String soqlQuery = ctx.byId
                ? TEKCO_AnonymizationScopeQueryBuilder.buildByIdScopeQuery(
                      objectApiName, selection.fields, 'recordIds'
                  )
                : TEKCO_AnonymizationScopeQueryBuilder.buildFieldScopeQuery(
                      objectApiName,
                      selection.fields,
                      selectedBrands,
                      ctx.additionalFilterFor(objectApiName),
                      selection.hasEmailMessageLorem
                  );

            return Database.getQueryLocator(soqlQuery);
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        TEKCO_AnonymizationExecuteService.ExecuteResult result =
            TEKCO_AnonymizationExecuteService.executeFieldAnonymization(
                scope,
                TEKCO_AnonymizationConfigSelector.loadFieldConfigsByDevNames(validFieldConfigDevNames),
                TEKCO_AnonymizationConfigSelector.buildPatternMap(),
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
