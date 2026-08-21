/**
 * @description Turns a resolved scope into a running chain. Everything the two entry points did
 *              identically once they knew what to touch: load the configs, split them into the
 *              three phases, apply the user's exclusions, build the step plan, raise the bypass,
 *              open the audit log and hand over to TEKCO_AnonymizationChainRunner.
 *
 *              The controllers keep what genuinely distinguishes them — resolving the scope. By
 *              Criteria validates a list of objects; By ID parses an ID list, resolves external
 *              IDs, walks parent-to-child links and bounds the result. Everything after that was
 *              44 strictly identical lines across the two, which is how the two chains kept
 *              drifting apart in the first place.
 */
public with sharing class TEKCO_AnonymizationLaunchService {

    private static final String PATTERN_DELETE_CONTENT_DOCUMENT = 'DELETE_CONTENT_DOCUMENT';

    /** A scope that has already been resolved and validated by the caller. */
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
        // Both tabs come through here, so the concurrency check cannot be forgotten on one of
        // them. Two runs at once corrupt the bypass snapshot — see the method's own comment.
        TEKCO_AnonymizationGuard.assertNoRunInProgress();

        List<TEKCO_AnonymizationFieldConfig__mdt> scopedConfigs = loadScopedConfigs(request);

        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByObject =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        // The additional filter belongs to the CONFIG, and an object's scope is the OR of the
        // filters of the configs still retained. Two consequences, both wanted:
        //
        //   - two configs on one object no longer fight. Address.Street carries one filter for
        //     ACCCO_IndividualPerson and another for ACCCO_Patient; the object used to keep only
        //     whichever arrived first — in an unspecified order — so one of the two populations
        //     was never anonymized, silently, on a run reporting Success. Both terms now apply.
        //   - unticking a field removes its term from the OR, which can only NARROW the scope.
        //     The previous shape had to read the filter before the exclusion check or unticking
        //     one field dropped the object's only filter and WIDENED the run. That trap is now a
        //     property of the model rather than a comment to respect.
        //
        // A retained config with NO filter means "no restriction" and dominates the OR: the
        // object is read unfiltered, as it would have been before.
        //
        // By Criteria only. A By ID run named its records explicitly; narrowing them further
        // with a configured filter would silently drop records the user asked for.
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
                // Only the filters that actually reach a query are worth validating: those the
                // combination discarded restrict nothing.
                retainedFilterConfigs.addAll(retained);
            }
        }

        // Field phase objects, in the caller's order, restricted to those that still have a
        // config after the exclusions.
        List<String> fieldObjects = new List<String>();
        // Carries the user's exclusions and record-type filtering across the whole chain: every
        // batch reloads its configs from these developer names instead of reloading everything
        // active, which would resurrect the fields the user unchecked.
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

        // Checked before the bypass is raised, so a refused launch never leaves the org's
        // automation disabled.
        if (fieldObjects.isEmpty() && contentDocConfigs.isEmpty()) {
            throw new AuraHandledException(request.nothingToDoMessage);
        }

        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot =
            TEKCO_AnonymizationBypassService.activate();

        // From here the bypass is up. Anything that throws before the chain owns it must put it
        // back — insert auditLog is a real failure point, STORAGE_LIMIT_EXCEEDED being the one
        // this org has already hit. Leaving the flags raised would disable triggers and outbound
        // synchronization for the running user with nothing to switch them back.
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

    /**
     * Active configs for the scope. The record-type narrowing applies to By Criteria only — a
     * By ID run names its records directly and has no record-type selection.
     */
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
            // A config with no record type applies to every record type, so it always survives.
            Set<String> covered = TEKCO_AnonymizationConfigSelector.recordTypesOf(config);
            if (covered.isEmpty()) {
                kept.add(config);
                continue;
            }
            // A rule covering several populations survives as soon as ONE of them was selected.
            // The records of the populations that were NOT selected are excluded by the scope
            // query, which carries the same selection — see
            // TEKCO_AnonymizationScopeQueryBuilder.recordTypeCondition().
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
        // Carried all the way to the queries. Keeping it at the launch service, as a rule filter
        // only, is what let a rule covering two populations be applied to both when the user had
        // selected one.
        ctx.selectedRecordTypes           = request.selectedRecordTypes != null
            ? request.selectedRecordTypes
            : new List<String>();
        ctx.recordIdsByObject             = request.recordIdsByObject;
        ctx.configDevNamesByObject        = configDevNamesByObject;
        ctx.historyConfigDevNamesByObject = historyDevNamesByObject;
        ctx.additionalFiltersByObject     = additionalFiltersByObject;
        // Configs whose pattern type resolves to nothing would be skipped silently at execute()
        // time — surface them at launch as warnings seeded into the audit trail.
        ctx.addErrors(TEKCO_AnonymizationGuard.validatePatternTypes(scopedConfigs));
        // Same idea for a malformed additional filter: it would only surface hours later, as a
        // whole object skipped in the middle of the chain.
        ctx.addErrors(TEKCO_AnonymizationGuard.validateAdditionalFilters(filterConfigs));
        return ctx;
    }

    /** Fields first, then ContentDocuments, then history — the order the chain must follow. */
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
