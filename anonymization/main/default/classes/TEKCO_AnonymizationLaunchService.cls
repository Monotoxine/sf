/**
 * @description 
 */
public with sharing class TEKCO_AnonymizationLaunchService {

    private static final String PATTERN_DELETE_CONTENT_DOCUMENT = 'DELETE_CONTENT_DOCUMENT';

    public class LaunchRequest {
        /** false = scoped by criteria, true = scoped by an explicit ID list. */
        public Boolean byId = false;
        /** Objects to process, in the order they should be processed. */
        public List<String> objectApiNames = new List<String>();
        /** By Criteria only. Empty = every brand. */
        public List<String> selectedBrands = new List<String>();
        /** By Criteria only. Null or empty = every record type. */
        public List<String> selectedRecordTypes;
        /** By ID only. */
        public Map<String, List<Id>> recordIdsByObject = new Map<String, List<Id>>();
        /** Config keys the user unticked — see TEKCO_AnonymizationConfigSelector.configKey(). */
        public Set<String> excludedFieldKeys = new Set<String>();
        public Set<String> disabledHistoryFieldKeys = new Set<String>();
        /** Audit log display values. */
        public String brandFilterLabel;
        public String objectsLabel;
        /** Thrown when the resolved scope turns out to have nothing to do. */
        public String nothingToDoMessage;
    }

    public static Id launch(LaunchRequest request) {
        TEKCO_AnonymizationGuard.assertNoRunInProgress();

        List<TEKCO_AnonymizationFieldConfig__mdt> scopedConfigs = loadScopedConfigs(request);

        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByObject =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> retainedByObject =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();

        for (TEKCO_AnonymizationFieldConfig__mdt config : scopedConfigs) {
            String objectApiName = config.TEKCO_ObjectApiName__c;
            String fieldKey      = TEKCO_AnonymizationConfigSelector.configKey(config);

            if (request.excludedFieldKeys.contains(fieldKey)) continue;

            if (!request.byId) {
                if (!retainedByObject.containsKey(objectApiName)) {
                    retainedByObject.put(
                        objectApiName, new List<TEKCO_AnonymizationFieldConfig__mdt>()
                    );
                }
                retainedByObject.get(objectApiName).add(config);
            }

            if (config.TEKCO_PatternType__c == PATTERN_DELETE_CONTENT_DOCUMENT) {
                contentDocConfigs.add(config);
                continue;
            }

            if (!configsByObject.containsKey(objectApiName)) {
                configsByObject.put(objectApiName, new List<TEKCO_AnonymizationFieldConfig__mdt>());
            }
            configsByObject.get(objectApiName).add(config);

            if (config.TEKCO_DeleteHistory__c
                    && !request.disabledHistoryFieldKeys.contains(fieldKey)) {
                historyConfigs.add(config);
            }
        }

        Map<String, String> additionalFiltersByObject = new Map<String, String>();
        List<TEKCO_AnonymizationFieldConfig__mdt> retainedFilterConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (String objectApiName : retainedByObject.keySet()) {
            List<TEKCO_AnonymizationFieldConfig__mdt> retained =
                retainedByObject.get(objectApiName);
            String combined =
                TEKCO_AnonymizationScopeQueryBuilder.combineAdditionalFilters(retained);
            if (combined != null) {
                additionalFiltersByObject.put(objectApiName, combined);
                retainedFilterConfigs.addAll(retained);
            }
        }

        List<String> fieldObjects = new List<String>();
        Map<String, List<String>> configDevNamesByObject = new Map<String, List<String>>();
        for (String objectApiName : request.objectApiNames) {
            if (!configsByObject.containsKey(objectApiName)) continue;
            fieldObjects.add(objectApiName);
            configDevNamesByObject.put(
                objectApiName,
                TEKCO_AnonymizationConfigSelector.toDevNames(configsByObject.get(objectApiName))
            );
        }

        Map<String, List<String>> historyDevNamesByObject = new Map<String, List<String>>();
        for (TEKCO_AnonymizationFieldConfig__mdt historyConfig : historyConfigs) {
            String objectApiName = historyConfig.TEKCO_ObjectApiName__c;
            if (!historyDevNamesByObject.containsKey(objectApiName)) {
                historyDevNamesByObject.put(objectApiName, new List<String>());
            }
            historyDevNamesByObject.get(objectApiName).add(historyConfig.DeveloperName);
        }

        if (fieldObjects.isEmpty() && contentDocConfigs.isEmpty()) {
            throw new AuraHandledException(request.nothingToDoMessage);
        }

        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot =
            TEKCO_AnonymizationBypassService.activate();

        try {
            TEKCO_AnonymizationAuditLog__c auditLog = new TEKCO_AnonymizationAuditLog__c(
                TEKCO_TriggeredBy__c   = UserInfo.getUserId(),
                TEKCO_BrandFilter__c   = request.brandFilterLabel,
                TEKCO_ObjectApiName__c = request.objectsLabel,
                TEKCO_Status__c        = 'Running',
                TEKCO_RunMode__c       = request.byId ? 'BY_ID' : 'BY_CRITERIA',
                TEKCO_StartTime__c     = Datetime.now()
            );
            insert auditLog;

            TEKCO_AnonymizationRunContext ctx = buildContext(
                request, auditLog.Id, bypassSnapshot, scopedConfigs,
                configDevNamesByObject, historyDevNamesByObject, additionalFiltersByObject,
                retainedFilterConfigs
            );
            planSteps(ctx, fieldObjects, contentDocConfigs, historyDevNamesByObject);

            Id batchJobId = TEKCO_AnonymizationChainRunner.startNext(ctx);
            if (batchJobId != null) {
                auditLog.TEKCO_JobId__c = String.valueOf(batchJobId);
                update auditLog;
            }
            return auditLog.Id;
        } catch (Exception e) {
            restoreQuietly(bypassSnapshot);
            throw e;
        }
    }

    private static List<TEKCO_AnonymizationFieldConfig__mdt> loadScopedConfigs(
        LaunchRequest request
    ) {
        List<String> objectApiNames = request.objectApiNames;
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = [
            SELECT DeveloperName, MasterLabel, TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c,
                   TEKCO_PatternType__c, TEKCO_IsActive__c, TEKCO_RecordTypeDeveloperName__c,
                   TEKCO_DeleteHistory__c, TEKCO_AdditionalFilter__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true AND TEKCO_ObjectApiName__c IN :objectApiNames
        ];

        if (request.selectedRecordTypes == null || request.selectedRecordTypes.isEmpty()) {
            return configs;
        }
        Set<String> recordTypeFilter = new Set<String>(request.selectedRecordTypes);
        List<TEKCO_AnonymizationFieldConfig__mdt> kept =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt config : configs) {
            Set<String> covered = TEKCO_AnonymizationConfigSelector.recordTypesOf(config);
            if (covered.isEmpty()) {
                kept.add(config);
                continue;
            }
            covered.retainAll(recordTypeFilter);
            if (!covered.isEmpty()) kept.add(config);
        }
        return kept;
    }

    private static TEKCO_AnonymizationRunContext buildContext(
        LaunchRequest request,
        Id auditLogId,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<TEKCO_AnonymizationFieldConfig__mdt> scopedConfigs,
        Map<String, List<String>> configDevNamesByObject,
        Map<String, List<String>> historyDevNamesByObject,
        Map<String, String> additionalFiltersByObject,
        List<TEKCO_AnonymizationFieldConfig__mdt> filterConfigs
    ) {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        ctx.auditLogId                    = auditLogId;
        ctx.byId                          = request.byId;
        ctx.bypassSnapshot                = bypassSnapshot;
        ctx.selectedBrands                = request.selectedBrands;
        ctx.selectedRecordTypes           = request.selectedRecordTypes != null
            ? request.selectedRecordTypes
            : new List<String>();
        ctx.recordIdsByObject             = request.recordIdsByObject;
        ctx.configDevNamesByObject        = configDevNamesByObject;
        ctx.historyConfigDevNamesByObject = historyDevNamesByObject;
        ctx.additionalFiltersByObject     = additionalFiltersByObject;
        ctx.addErrors(TEKCO_AnonymizationGuard.validatePatternTypes(scopedConfigs));
        ctx.addErrors(TEKCO_AnonymizationGuard.validateAdditionalFilters(filterConfigs));
        return ctx;
    }

    private static void planSteps(
        TEKCO_AnonymizationRunContext ctx,
        List<String> fieldObjects,
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs,
        Map<String, List<String>> historyDevNamesByObject
    ) {
        for (String objectApiName : fieldObjects) {
            ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_FIELD, objectApiName);
        }
        for (TEKCO_AnonymizationFieldConfig__mdt contentDocConfig : contentDocConfigs) {
            ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_CD, contentDocConfig.DeveloperName);
        }
        for (String objectApiName : historyDevNamesByObject.keySet()) {
            ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_HISTORY, objectApiName);
        }
    }

    private static void restoreQuietly(
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot
    ) {
        try {
            TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Bypass restore failed; flags may remain enabled: ' + e.getMessage()
            );
        }
    }
}
