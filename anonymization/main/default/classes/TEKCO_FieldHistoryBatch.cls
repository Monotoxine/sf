/**
 * @description Deletes the field-history rows of the configured fields on one object. Serves
 *              both chains: a run scoped by criteria and a run scoped by an explicit ID list
 *              differ only in how the parent records are selected.
 */
public without sharing class TEKCO_FieldHistoryBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE   = 2000;

    private String objectApiName;
    private TEKCO_AnonymizationRunContext ctx;

    private Integer      recordsDeleted = 0;
    private Integer      recordsFailed  = 0;
    private List<String> errors         = new List<String>();
    private Boolean      aborted        = false;

    public TEKCO_FieldHistoryBatch(String objectApiName, TEKCO_AnonymizationRunContext ctx) {
        this.objectApiName = objectApiName;
        this.ctx           = ctx;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationGuard.assertSandboxOrClose(ctx.auditLogId, ctx.bypassSnapshot)) {
            aborted = true;
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        if (!TEKCO_AnonymizationOrgConfigService.hasObject(objectApiName)) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        String historyObjectName = TEKCO_AnonymizationScopeQueryBuilder.historyObjectNameFor(objectApiName);
        String parentIdFieldName = TEKCO_AnonymizationScopeQueryBuilder.historyParentIdFieldFor(objectApiName);

        if (!TEKCO_AnonymizationOrgConfigService.hasObject(historyObjectName)) {
            errors.add('Field history not enabled for object, skipped: ' + objectApiName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            List<Id> recordIds = ctx.recordIdsFor(objectApiName);

            String soqlQuery = ctx.byId
                ? TEKCO_AnonymizationScopeQueryBuilder.buildHistoryByIdScopeQuery(
                      historyObjectName, parentIdFieldName, historyFieldNames(), 'recordIds'
                  )
                : TEKCO_AnonymizationScopeQueryBuilder.buildHistoryScopeQuery(
                      objectApiName,
                      historyObjectName,
                      parentIdFieldName,
                      historyFieldNames(),
                      ctx.selectedBrands,
                      ctx.recordTypeSelection(),
                      historyConfigs(),
                      ctx.additionalFilterFor(objectApiName)
                  );

            if (soqlQuery == null) {
                errors.add('No history fields configured for object, skipped: ' + objectApiName);
                return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
            }

            return Database.getQueryLocator(soqlQuery);
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }
    }

    private List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs() {
        return TEKCO_AnonymizationConfigSelector.loadFieldConfigsByDevNames(
            ctx.historyConfigDevNamesFor(objectApiName)
        );
    }

    private Set<String> historyFieldNames() {
        Set<String> fieldApiNames = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : historyConfigs()) {
            if (String.isNotBlank(fieldConfig.TEKCO_FieldApiName__c)) {
                fieldApiNames.add(fieldConfig.TEKCO_FieldApiName__c);
            }
        }
        return fieldApiNames;
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        TEKCO_FieldHistoryDeleteService.DeleteOutcome outcome =
            TEKCO_FieldHistoryDeleteService.deleteHistoryRecords(scope);

        recordsDeleted += outcome.recordsDeleted;
        recordsFailed  += outcome.recordsFailed;
        for (String e : outcome.errors) {
            if (errors.size() < TEKCO_AnonymizationRunContext.MAX_CAPTURED_ERRORS) errors.add(e);
        }
    }

    public void finish(Database.BatchableContext bc) {
        if (aborted) return;

        ctx.addErrors(errors);
        ctx.addHistoryDeleted(recordsDeleted);
        ctx.addFailed(recordsFailed);
        TEKCO_AnonymizationChainRunner.startNext(ctx);
    }
}
