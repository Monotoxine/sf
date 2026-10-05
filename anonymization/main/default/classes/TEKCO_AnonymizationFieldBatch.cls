/**
 * @description Field-level anonymization of one object
 */
public without sharing class TEKCO_AnonymizationFieldBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE = 200;

    private String objectApiName;
    private TEKCO_AnonymizationRunContext ctx;

    private List<String>    validFieldConfigDevNames = new List<String>();
    private Map<Id, String> recordTypeDevNameById    = new Map<Id, String>();

    private Integer      recordsProcessed = 0;
    private Integer      recordsFailed    = 0;
    private List<String> errors           = new List<String>();
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

            List<String> selectedBrands = ctx.selectedBrands;
            List<Id>     recordIds      = ctx.recordIdsFor(objectApiName);

            String soqlQuery = ctx.byId
                ? TEKCO_AnonymizationScopeQueryBuilder.buildByIdScopeQuery(
                      objectApiName, selection.fields, 'recordIds'
                  )
                : TEKCO_AnonymizationScopeQueryBuilder.buildFieldScopeQuery(
                      objectApiName,
                      selection.fields,
                      selectedBrands,
                      ctx.recordTypeSelection(),
                      startConfigs,
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
        if (aborted) return;

        ctx.addErrors(errors);
        ctx.addProcessed(recordsProcessed);
        ctx.addFailed(recordsFailed);
        TEKCO_AnonymizationChainRunner.startNext(ctx);
    }
}
