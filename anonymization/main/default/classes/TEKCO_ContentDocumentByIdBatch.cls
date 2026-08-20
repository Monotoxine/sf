/**
 * @description Deletes the ContentDocuments linked to an explicit list of records, for a run
 *              launched from IDs. Same deletion service as the By Criteria chain; only the
 *              parent scope differs.
 */
// Deliberately 'without sharing': see TEKCO_AnonymizationBatch.
public without sharing class TEKCO_ContentDocumentByIdBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE   = 100;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    /** Developer name of the DELETE_CONTENT_DOCUMENT config driving this step. */
    private String configDevName;
    private TEKCO_AnonymizationRunContext ctx;

    private Integer      recordsDeleted = 0;
    private Integer      recordsFailed  = 0;
    private List<String> errors         = new List<String>();
    private Boolean      aborted        = false;

    public TEKCO_ContentDocumentByIdBatch(String configDevName, TEKCO_AnonymizationRunContext ctx) {
        this.configDevName = configDevName;
        this.ctx           = ctx;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(ctx.auditLogId, ctx.bypassSnapshot)) {
            aborted = true;
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        TEKCO_AnonymizationFieldConfig__mdt config =
            TEKCO_AnonymizationChainRunner.configByDevName(configDevName);
        if (config == null || String.isBlank(config.TEKCO_ObjectApiName__c)) {
            errors.add('ContentDocument config not found, skipped: ' + configDevName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        String objectApiName = config.TEKCO_ObjectApiName__c;
        // requireConfiguredObject() validates a name against the CMDT, not against the org's
        // schema, so a config for an object this org does not have reaches here. Without this
        // guard getQueryLocator() throws, start() dies, finish() never runs, the chain runner is
        // never called — and the audit log sits on Running forever.
        if (!TEKCO_AnonymizationOrgConfigService.hasObject(objectApiName)) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            // Must be a local of this exact name: the produced query binds ':parentIds'.
            List<Id> parentIds = ctx.recordIdsFor(objectApiName);

            return Database.getQueryLocator(
                TEKCO_AnonymizationScopeQueryBuilder.buildByIdScopeQuery(
                    objectApiName, new Set<String>{ 'Id' }, 'parentIds'
                )
            );
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id> parentIds = new Set<Id>();
        for (SObject record : scope) parentIds.add(record.Id);

        TEKCO_ContentDocumentDeleteService.DeleteOutcome outcome =
            TEKCO_ContentDocumentDeleteService.deleteForParentIds(parentIds);

        recordsDeleted += outcome.recordsDeleted;
        recordsFailed  += outcome.recordsFailed;
        for (String e : outcome.errors) {
            if (errors.size() < MAX_CAPTURED_ERRORS) errors.add(e);
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (aborted) return;

        ctx.addErrors(errors);
        ctx.addDocumentsDeleted(recordsDeleted);
        ctx.addFailed(recordsFailed);
        TEKCO_AnonymizationChainRunner.startNext(ctx);
    }
}
