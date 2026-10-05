/**
 * @description Deletes the ContentDocuments linked to a set of parent records. Serves both
 *              chains: a run scoped by criteria and a run scoped by an explicit ID list differ
 *              only in which parents they read.
 *
 */
public without sharing class TEKCO_ContentDocumentBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static Integer batchSizeFor(Boolean byId) {
        return byId == true ? 100 : 500;
    }

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
        if (!TEKCO_AnonymizationOrgConfigService.hasObject(objectApiName)) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            List<Id> recordIds = ctx.recordIdsFor(objectApiName);

            String soqlQuery = ctx.byId
                ? TEKCO_AnonymizationScopeQueryBuilder.buildByIdScopeQuery(
                      objectApiName, new Set<String>{ 'Id' }, 'recordIds'
                  )
                : TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery(
                      objectApiName,
                      ctx.selectedBrands,
                      TEKCO_AnonymizationConfigSelector.recordTypesOf(config),
                      ctx.recordTypeSelection(),
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
