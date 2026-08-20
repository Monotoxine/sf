/**
 * @description Deletes the ContentDocuments linked to the records of one object, for a run
 *              launched from criteria. Driven by one DELETE_CONTENT_DOCUMENT field config, which
 *              may narrow the scope to a single record type.
 */
// Deliberately 'without sharing': see TEKCO_AnonymizationBatch.
public without sharing class TEKCO_ContentDocumentBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE  = 500;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

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
        if (!TEKCO_AnonymizationOrgConfigService.hasObject(objectApiName)) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            return Database.getQueryLocator(
                TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery(
                    objectApiName,
                    ctx.selectedBrands,
                    config.TEKCO_RecordTypeDeveloperName__c,
                    ctx.additionalFilterFor(objectApiName)
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
