/**
 * @description Deletes the field-history rows of the configured fields on an explicit list of
 *              records, for a run launched from IDs.
 */
// Deliberately 'without sharing': see TEKCO_AnonymizationBatch.
public without sharing class TEKCO_FieldHistoryByIdBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE   = 2000;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    private String objectApiName;
    private TEKCO_AnonymizationRunContext ctx;

    private Integer      recordsDeleted = 0;
    private Integer      recordsFailed  = 0;
    private List<String> errors         = new List<String>();
    private Boolean      aborted        = false;

    public TEKCO_FieldHistoryByIdBatch(String objectApiName, TEKCO_AnonymizationRunContext ctx) {
        this.objectApiName = objectApiName;
        this.ctx           = ctx;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(ctx.auditLogId, ctx.bypassSnapshot)) {
            aborted = true;
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        // Same guard as the By Criteria twin. Without it a missing object yields a missing
        // history object, and the run is reported as 'field history not enabled' when the
        // object itself is what is absent.
        if (!TEKCO_AnonymizationOrgConfigService.hasObject(objectApiName)) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        String historyObjectName = TEKCO_AnonymizationBatchUtils.computeHistoryObjectName(objectApiName);
        String parentIdFieldName = TEKCO_AnonymizationBatchUtils.computeParentIdFieldName(objectApiName);

        if (!TEKCO_AnonymizationOrgConfigService.hasObject(historyObjectName)) {
            errors.add('Field history not enabled for object, skipped: ' + objectApiName);
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }

        try {
            // Re-queried from developer names: only those cross chunk boundaries.
            Set<String> historyFieldNames = new Set<String>();
            for (TEKCO_AnonymizationFieldConfig__mdt fc :
                    TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(
                        ctx.historyConfigDevNamesFor(objectApiName)
                    )) {
                if (String.isNotBlank(fc.TEKCO_FieldApiName__c)) {
                    historyFieldNames.add(fc.TEKCO_FieldApiName__c);
                }
            }

            String soqlQuery = TEKCO_AnonymizationScopeQueryBuilder.buildHistoryByIdScopeQuery(
                historyObjectName, parentIdFieldName, historyFieldNames, 'recordIds'
            );
            if (soqlQuery == null) {
                errors.add('No history fields configured for object, skipped: ' + objectApiName);
                return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
            }

            // Must be a local of this exact name: the produced query binds ':recordIds'.
            List<Id> recordIds = ctx.recordIdsFor(objectApiName);

            return Database.getQueryLocator(soqlQuery);
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator(TEKCO_AnonymizationScopeQueryBuilder.EMPTY_LOCATOR_QUERY);
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        TEKCO_FieldHistoryDeleteService.DeleteOutcome outcome =
            TEKCO_FieldHistoryDeleteService.deleteHistoryRecords(scope);

        recordsDeleted += outcome.recordsDeleted;
        recordsFailed  += outcome.recordsFailed;
        for (String e : outcome.errors) {
            if (errors.size() < MAX_CAPTURED_ERRORS) errors.add(e);
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
