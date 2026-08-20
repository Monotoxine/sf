/**
 * @description Deletes the ContentDocuments linked to a set of parent records. Serves both
 *              chains: a run scoped by criteria and a run scoped by an explicit ID list differ
 *              only in which parents they read.
 *
 *              Driven by one DELETE_CONTENT_DOCUMENT field config, which names the parent object
 *              and may narrow the By Criteria scope to a single record type.
 *
 *              Merged from TEKCO_ContentDocumentBatch and TEKCO_ContentDocumentByIdBatch: the
 *              object-existence guard and the try/catch had landed on the By Criteria side only,
 *              which left a By ID run able to die in start() — and, finish() never running, to
 *              leave the whole chain stopped on an audit log stuck at Running.
 */
// Deliberately 'without sharing': see TEKCO_AnonymizationFieldBatch.
public without sharing class TEKCO_ContentDocumentBatch implements Database.Batchable<SObject>, Database.Stateful {


    /**
     * Parents per chunk. The two chains have never agreed on this number and this class does not
     * settle it: TEKCO_ContentDocumentDeleteService stops at the remaining DML budget and reports
     * the shortfall, because one parent can own hundreds of files and a chunk can resolve far
     * more than the 10 000-row ceiling. A smaller chunk is less likely to truncate and need a
     * re-run; a larger one is faster. The By ID side was tuned to 100 when that budget guard was
     * introduced (14912ab) and the By Criteria side was left at 500. Picking one deserves its own
     * measurement — this method only makes the disagreement visible in a single place.
     */
    public static Integer batchSizeFor(Boolean byId) {
        return byId == true ? 100 : 500;
    }

    /** Developer name of the DELETE_CONTENT_DOCUMENT config driving this step. */
    private String configDevName;
    private TEKCO_AnonymizationRunContext ctx;

    private Integer      recordsDeleted = 0;
    private Integer      recordsFailed  = 0;
    private List<String> errors         = new List<String>();
    private Boolean      aborted        = false;

    public TEKCO_ContentDocumentBatch(String configDevName, TEKCO_AnonymizationRunContext ctx) {
        this.configDevName = configDevName;
        this.ctx           = ctx;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationGuard.assertSandboxOrClose(ctx.auditLogId, ctx.bypassSnapshot)) {
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
        // schema, so a config for an object this org does not have reaches here.
        if (!TEKCO_AnonymizationOrgConfigService.hasObject(objectApiName)) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            // Must be a local of this exact name: the By ID query binds ':recordIds', and
            // Database.getQueryLocator resolves binds against the scope that calls it.
            List<Id> recordIds = ctx.recordIdsFor(objectApiName);

            String soqlQuery = ctx.byId
                ? TEKCO_AnonymizationScopeQueryBuilder.buildByIdScopeQuery(
                      objectApiName, new Set<String>{ 'Id' }, 'recordIds'
                  )
                : TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery(
                      objectApiName,
                      ctx.selectedBrands,
                      config.TEKCO_RecordTypeDeveloperName__c,
                      ctx.additionalFilterFor(objectApiName)
                  );

            return Database.getQueryLocator(soqlQuery);
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
            if (errors.size() < TEKCO_AnonymizationRunContext.MAX_CAPTURED_ERRORS) errors.add(e);
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
