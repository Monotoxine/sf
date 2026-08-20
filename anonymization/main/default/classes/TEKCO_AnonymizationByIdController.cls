/**
 * @description AuraEnabled controller for the "By ID" tab of tekcoDataAnonymizationAdmin LWC.
 */
public with sharing class TEKCO_AnonymizationByIdController {

    private static final String PATTERN_DELETE_CD  = 'DELETE_CONTENT_DOCUMENT';
    private static final String MODE_EXTERNAL_ID   = 'EXTERNAL_ID';

    /**
     * Ceiling on how many records one By ID run may resolve, parents and children together.
     *
     * The child resolution below is unbounded by nature: a handful of pasted parent IDs can pull
     * in an arbitrary number of children, and every resolved Id is then carried in the batch's
     * serialized state from chunk to chunk. Without a ceiling that is a silent scalability wall —
     * the run simply fails somewhere in the middle. Above this, the user is asked to narrow the
     * list, or to use the By Criteria tab, which streams through a QueryLocator instead.
     */
    private static final Integer MAX_BY_ID_RECORDS = 50000;

    @AuraEnabled(cacheable=false)
    public static ResolveResultDTO resolveIds(
        List<String> rawIds,
        String resolveMode,
        String targetObject,
        String externalIdField
    ) {
        TEKCO_AnonymizationBatchUtils.assertCanAnonymize();

        ResolveResultDTO result = new ResolveResultDTO();
        result.directObjects   = new List<ObjectScopeDTO>();
        result.childObjects    = new List<ObjectScopeDTO>();
        result.invalidIds      = new List<String>();
        result.brands          = new List<String>();
        result.totalValid      = 0;

        if (rawIds == null || rawIds.isEmpty()) return result;

        Map<String, List<Id>> directIdsByObject;
        if (resolveMode == MODE_EXTERNAL_ID
                && String.isNotBlank(targetObject)
                && String.isNotBlank(externalIdField)) {
            directIdsByObject = resolveByExternalIds(rawIds, targetObject, externalIdField, result.invalidIds);
        } else {
            directIdsByObject = parseAndGroupIds(rawIds, result.invalidIds);
        }

        List<TEKCO_AnonymizationFieldConfig__mdt> allConfigs = loadAllActiveConfigs();
        Set<String> configuredObjects = getConfiguredObjectNames(allConfigs);

        // Validate direct objects against configured ones
        for (String obj : new List<String>(directIdsByObject.keySet())) {
            List<Id> ids = directIdsByObject.get(obj);
            if (configuredObjects.contains(obj.toLowerCase())) {
                ObjectScopeDTO dto  = new ObjectScopeDTO();
                dto.objectApiName   = obj;
                dto.recordCount     = ids.size();
                dto.sourceLabel     = 'direct';
                result.directObjects.add(dto);
                result.totalValid  += ids.size();
            } else {
                for (Id id : ids) result.invalidIds.add(String.valueOf(id) + ' (' + obj + ' — not configured)');
            }
        }

        // child objects
        Map<String, ChildRelationInfo> childRelByObject = buildChildRelationMap(allConfigs);
        for (String childObj : childRelByObject.keySet()) {
            ChildRelationInfo rel = childRelByObject.get(childObj);
            List<Id> parentIds = directIdsByObject.get(rel.parentObjectApiName);
            if (parentIds == null || parentIds.isEmpty()) continue;

            List<Id> childIds = resolveChildIds(childObj, rel.parentLookupField, parentIds);
            if (!childIds.isEmpty()) {
                ObjectScopeDTO dto  = new ObjectScopeDTO();
                dto.objectApiName   = childObj;
                dto.recordCount     = childIds.size();
                dto.sourceLabel     = 'via ' + rel.parentObjectApiName + '.' + rel.parentLookupField;
                result.childObjects.add(dto);
                result.totalValid  += childIds.size();
            }
        }

        // collect distinct brands from direct records
        Set<String> brandSet = new Set<String>();
        TEKCO_AnonymizationOrgConfigService.OrgConfig orgCfg = TEKCO_AnonymizationOrgConfigService.getConfig();
        for (String obj : directIdsByObject.keySet()) {
            List<Id> ids = directIdsByObject.get(obj);
            try {
                if (orgCfg.usesBrandObject()
                        && String.isNotBlank(orgCfg.brandLookupFieldOnRecord)
                        && String.isNotBlank(orgCfg.brandCodeField)) {
                    String relName = orgCfg.brandLookupFieldOnRecord;
                    for (SObject r : Database.query(
                        'SELECT ' + relName + '.' + orgCfg.brandCodeField
                        + ' FROM ' + obj + ' WHERE Id IN :ids'
                    )) {
                        SObject rel = (SObject) r.getSObject(relName);
                        if (rel != null) {
                            Object val = rel.get(orgCfg.brandCodeField);
                            if (val != null) brandSet.add(String.valueOf(val));
                        }
                    }
                } else if (!orgCfg.usesBrandObject()
                        && TEKCO_AnonymizationOrgConfigService.hasField(obj, 'tekco_brand__c')) {
                    for (SObject r : Database.query(
                        'SELECT TEKCO_Brand__c FROM ' + obj
                        + ' WHERE Id IN :ids AND TEKCO_Brand__c != null'
                    )) {
                        brandSet.add((String) r.get('TEKCO_Brand__c'));
                    }
                }
            } catch (Exception e) {  }
        }
        List<String> brandList = new List<String>(brandSet);
        brandList.sort();
        result.brands = brandList;

        return result;
    }

    @AuraEnabled
    public static Id startAnonymizationByIds(
        List<String> rawIds,
        String resolveMode,
        String targetObject,
        String externalIdField,
        List<String> excludedFields,
        List<String> noHistoryFields
    ) {
        TEKCO_AnonymizationBatchUtils.assertCanAnonymize();
        TEKCO_AnonymizationOrgConfigService.assertIsSandbox();

        if (rawIds == null || rawIds.isEmpty()) {
            throw new AuraHandledException('No IDs provided.');
        }

        Set<String> excludedFieldKeys  = new Set<String>();
        if (excludedFields  != null) excludedFieldKeys.addAll(excludedFields);
        Set<String> noHistoryFieldKeys = new Set<String>();
        if (noHistoryFields != null) noHistoryFieldKeys.addAll(noHistoryFields);

        List<String> parseErrors = new List<String>();
        Map<String, List<Id>> directIdsByObject;
        if (resolveMode == MODE_EXTERNAL_ID
                && String.isNotBlank(targetObject)
                && String.isNotBlank(externalIdField)) {
            directIdsByObject = resolveByExternalIds(rawIds, targetObject, externalIdField, parseErrors);
        } else {
            directIdsByObject = parseAndGroupIds(rawIds, parseErrors);
        }

        if (directIdsByObject.isEmpty()) {
            throw new AuraHandledException('No valid Salesforce IDs found.'
                + (parseErrors.isEmpty() ? '' : ' Invalid: ' + String.join(parseErrors, ', ')));
        }

        List<TEKCO_AnonymizationFieldConfig__mdt> allConfigs = loadAllActiveConfigs();
        Set<String> configuredObjects = getConfiguredObjectNames(allConfigs);
        Map<String, ChildRelationInfo> childRelByObject = buildChildRelationMap(allConfigs);

        Map<String, List<Id>> allIdsByObject = new Map<String, List<Id>>();

        for (String obj : directIdsByObject.keySet()) {
            if (configuredObjects.contains(obj.toLowerCase())) {
                allIdsByObject.put(obj, directIdsByObject.get(obj));
            }
        }

        for (String childObj : childRelByObject.keySet()) {
            ChildRelationInfo rel = childRelByObject.get(childObj);
            List<Id> parentIds = directIdsByObject.get(rel.parentObjectApiName);
            if (parentIds == null || parentIds.isEmpty()) continue;
            List<Id> childIds = resolveChildIds(childObj, rel.parentLookupField, parentIds);
            if (!childIds.isEmpty()) {
                if (!allIdsByObject.containsKey(childObj)) allIdsByObject.put(childObj, new List<Id>());
                allIdsByObject.get(childObj).addAll(childIds);
            }
        }

        if (allIdsByObject.isEmpty()) {
            throw new AuraHandledException(
                'No active anonymization configurations found for the provided records.'
            );
        }

        Integer resolvedCount = 0;
        for (List<Id> ids : allIdsByObject.values()) resolvedCount += ids.size();
        if (resolvedCount > MAX_BY_ID_RECORDS) {
            throw new AuraHandledException(
                resolvedCount + ' records resolved (parents and children), maximum '
                + MAX_BY_ID_RECORDS + '. Narrow the ID list, or use the By Criteria tab for a '
                + 'scope of this size.'
            );
        }

        List<String> objectsToProcess = new List<String>(allIdsByObject.keySet());

        List<TEKCO_AnonymizationFieldConfig__mdt> scopedConfigs = [
            SELECT DeveloperName, TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c, TEKCO_PatternType__c,
                   TEKCO_IsActive__c, TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_ObjectApiName__c IN :objectsToProcess
        ];

        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByObject =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();

        for (TEKCO_AnonymizationFieldConfig__mdt fc : scopedConfigs) {
            String obj      = fc.TEKCO_ObjectApiName__c;
            String fieldKey = obj + '.' + fc.TEKCO_FieldApiName__c + '.'
                + (fc.TEKCO_RecordTypeDeveloperName__c != null ? fc.TEKCO_RecordTypeDeveloperName__c : '');

            if (excludedFieldKeys.contains(fieldKey)) continue;

            if (fc.TEKCO_PatternType__c == PATTERN_DELETE_CD) {
                contentDocConfigs.add(fc);
                continue;
            }

            if (!configsByObject.containsKey(obj)) {
                configsByObject.put(obj, new List<TEKCO_AnonymizationFieldConfig__mdt>());
            }
            configsByObject.get(obj).add(fc);

            if (fc.TEKCO_DeleteHistory__c && !noHistoryFieldKeys.contains(fieldKey)) {
                historyConfigs.add(fc);
            }
        }

        // Carries the user's exclusions across the chain: every batch reloads its configs from
        // these developer names instead of reloading everything active.
        Map<String, List<String>> configDevNamesByObject = new Map<String, List<String>>();
        for (String obj : configsByObject.keySet()) {
            configDevNamesByObject.put(
                obj, TEKCO_AnonymizationBatchUtils.toDevNames(configsByObject.get(obj))
            );
        }

        Map<String, List<String>> historyDevNamesByObject = new Map<String, List<String>>();
        for (TEKCO_AnonymizationFieldConfig__mdt historyConfig : historyConfigs) {
            String obj = historyConfig.TEKCO_ObjectApiName__c;
            if (!historyDevNamesByObject.containsKey(obj)) {
                historyDevNamesByObject.put(obj, new List<String>());
            }
            historyDevNamesByObject.get(obj).add(historyConfig.DeveloperName);
        }

        // Raised only once the scope is known to be valid, and put back by the guard below or
        // by TEKCO_AnonymizationChainRunner at the end of the chain.
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot =
            TEKCO_AnonymizationBypassService.activate();

        List<String> fieldObjects = new List<String>();
        for (String obj : objectsToProcess) {
            if (configsByObject.containsKey(obj)) fieldObjects.add(obj);
        }

        if (fieldObjects.isEmpty() && contentDocConfigs.isEmpty()) {
            TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            throw new AuraHandledException(
                'No active field configurations found for the provided records.'
            );
        }

        Integer totalIds = 0;
        for (List<Id> ids : allIdsByObject.values()) totalIds += ids.size();

        TEKCO_AnonymizationAuditLog__c auditLog = new TEKCO_AnonymizationAuditLog__c(
            TEKCO_TriggeredBy__c   = UserInfo.getUserId(),
            TEKCO_BrandFilter__c   = 'BY_ID (' + totalIds + ' record(s))',
            TEKCO_ObjectApiName__c = String.join(objectsToProcess, ', '),
            TEKCO_Status__c        = 'Running',
            TEKCO_RunMode__c       = 'BY_ID',
            TEKCO_StartTime__c     = Datetime.now()
        );
        insert auditLog;

        // Same context and same runner as the By Criteria chain — only the scope differs:
        // recordIdsByObject instead of brands and per-object filters.
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        ctx.auditLogId                    = auditLog.Id;
        ctx.byId                          = true;
        ctx.bypassSnapshot                = bypassSnapshot;
        ctx.recordIdsByObject             = allIdsByObject;
        ctx.configDevNamesByObject        = configDevNamesByObject;
        ctx.historyConfigDevNamesByObject = historyDevNamesByObject;
        ctx.addErrors(TEKCO_AnonymizationBatchUtils.validatePatternTypes(scopedConfigs));

        for (String obj : fieldObjects) {
            ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_FIELD, obj);
        }
        for (TEKCO_AnonymizationFieldConfig__mdt contentDocConfig : contentDocConfigs) {
            ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_CD, contentDocConfig.DeveloperName);
        }
        for (String obj : historyDevNamesByObject.keySet()) {
            ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_HISTORY, obj);
        }

        Id batchJobId = TEKCO_AnonymizationChainRunner.startNext(ctx);
        if (batchJobId != null) {
            auditLog.TEKCO_JobId__c = String.valueOf(batchJobId);
            update auditLog;
        }

        return auditLog.Id;
    }

    /**
     * Runs scoped by ID list. Same backward-compatible fallback as getAuditLogs(): a blank
     * TEKCO_RunMode__c means the log predates the field, and only the 'BY_ID (...)' label put
     * in the brand filter identified it.
     */
    @AuraEnabled(cacheable=false)
    public static List<TEKCO_AnonymizationAuditLog__c> getAuditLogsByid() {
        TEKCO_AnonymizationBatchUtils.assertCanAnonymize();
        return [
            SELECT Name, TEKCO_ObjectApiName__c, TEKCO_BrandFilter__c, TEKCO_Status__c,
                   TEKCO_RecordsProcessed__c, TEKCO_RecordsFailed__c,
                   TEKCO_DocumentsDeleted__c, TEKCO_HistoryRecordsDeleted__c,
                   TEKCO_StartTime__c, TEKCO_EndTime__c, TEKCO_JobId__c, TEKCO_RunMode__c,
                   TEKCO_TriggeredBy__r.Name, TEKCO_ErrorMessage__c
            FROM TEKCO_AnonymizationAuditLog__c
            WHERE (TEKCO_RunMode__c = 'BY_ID'
                   OR (TEKCO_RunMode__c = null AND TEKCO_BrandFilter__c LIKE 'BY_ID%'))
            ORDER BY TEKCO_StartTime__c DESC
            LIMIT 20
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getDirectObjects() {
        TEKCO_AnonymizationBatchUtils.assertCanAnonymize();
        Set<String> seen = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : [
            SELECT TEKCO_ObjectApiName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_ObjectApiName__c != null
              AND (TEKCO_ParentObjectApiName__c = null OR TEKCO_ParentObjectApiName__c = '')
        ]) {
            seen.add(fc.TEKCO_ObjectApiName__c);
        }
        List<String> sorted = new List<String>(seen);
        sorted.sort();
        List<Map<String, String>> options = new List<Map<String, String>>();
        for (String obj : sorted) {
            options.add(new Map<String, String>{ 'label' => obj, 'value' => obj });
        }
        return options;
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getExternalIdFieldsForObject(String objectApiName) {
        TEKCO_AnonymizationBatchUtils.assertCanAnonymize();
        if (String.isBlank(objectApiName)) return new List<String>();

        Set<String> patternTypesForObj = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : [
            SELECT TEKCO_PatternType__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_ObjectApiName__c = :objectApiName
              AND TEKCO_IsActive__c = true
        ]) {
            if (String.isNotBlank(fc.TEKCO_PatternType__c)) patternTypesForObj.add(fc.TEKCO_PatternType__c);
        }

        Set<String> fields = new Set<String>();
        for (TEKCO_AnonymizationPattern__mdt p : [
            SELECT TEKCO_ExternalIdField__c
            FROM TEKCO_AnonymizationPattern__mdt
            WHERE DeveloperName IN :patternTypesForObj
              AND TEKCO_IsActive__c = true
              AND TEKCO_ExternalIdField__c != null
        ]) {
            if (TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, p.TEKCO_ExternalIdField__c.toLowerCase())) {
                fields.add(p.TEKCO_ExternalIdField__c);
            }
        }

        fields.addAll(TEKCO_AnonymizationOrgConfigService.getExternalIdFieldsOn(objectApiName));

        List<String> result = new List<String>(fields);
        result.sort();
        return result;
    }

    private static Map<String, List<Id>> resolveByExternalIds(
        List<String> rawValues,
        String objectApiName,
        String fieldApiName,
        List<String> invalidOut
    ) {
        Map<String, List<Id>> result = new Map<String, List<Id>>();
        // Both names are concatenated into dynamic SOQL below and come from client input —
        // reject anything that is not a configured object with a real field on it.
        String canonicalObject = TEKCO_AnonymizationBatchUtils.requireConfiguredObject(objectApiName);
        TEKCO_AnonymizationBatchUtils.requireFieldOnObject(canonicalObject, fieldApiName);
        try {
            List<SObject> records = Database.query(
                'SELECT Id FROM ' + canonicalObject
                + ' WHERE ' + fieldApiName + ' IN :rawValues'
            );
            List<Id> ids = new List<Id>();
            for (SObject r : records) ids.add(r.Id);
            if (!ids.isEmpty()) result.put(canonicalObject, ids);
        } catch (Exception e) {
            if (invalidOut != null) {
                invalidOut.add(objectApiName + '.' + fieldApiName + ' — ' + e.getMessage());
            }
        }
        return result;
    }

    private static Map<String, List<Id>> parseAndGroupIds(
        List<String> rawIds, List<String> invalidOut
    ) {
        Map<String, List<Id>> result = new Map<String, List<Id>>();
        for (String rawId : rawIds) {
            String trimmed = rawId.trim();
            if (String.isBlank(trimmed)) continue;
            try {
                Id sfId    = (Id) trimmed;
                String obj = sfId.getSObjectType().getDescribe().getName();
                if (!result.containsKey(obj)) result.put(obj, new List<Id>());
                result.get(obj).add(sfId);
            } catch (Exception e) {
                if (invalidOut != null) invalidOut.add(trimmed + ' (invalid ID)');
            }
        }
        return result;
    }

    private static List<TEKCO_AnonymizationFieldConfig__mdt> loadAllActiveConfigs() {
        return [
            SELECT TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c, TEKCO_PatternType__c,
                   TEKCO_IsActive__c, TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c,
                   TEKCO_ParentObjectApiName__c, TEKCO_ParentLookupFieldApiName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_ObjectApiName__c != null
        ];
    }

    private static Set<String> getConfiguredObjectNames(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        Set<String> result = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            result.add(fc.TEKCO_ObjectApiName__c.toLowerCase());
        }
        return result;
    }

    private static Map<String, ChildRelationInfo> buildChildRelationMap(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        Map<String, ChildRelationInfo> result = new Map<String, ChildRelationInfo>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            if (String.isBlank(fc.TEKCO_ParentObjectApiName__c)
                    || String.isBlank(fc.TEKCO_ParentLookupFieldApiName__c)) continue;
            String childObj = fc.TEKCO_ObjectApiName__c;
            if (result.containsKey(childObj)) continue;
            ChildRelationInfo rel  = new ChildRelationInfo();
            rel.parentObjectApiName = fc.TEKCO_ParentObjectApiName__c;
            rel.parentLookupField   = fc.TEKCO_ParentLookupFieldApiName__c;
            result.put(childObj, rel);
        }
        return result;
    }

    private static List<Id> resolveChildIds(
        String childObjectApiName, String parentLookupField, List<Id> parentIds
    ) {
        return resolveChildIds(childObjectApiName, parentLookupField, parentIds, null);
    }

    /** @param maxRows null = the whole child set (a run); a value = a bounded read (the preview). */
    private static List<Id> resolveChildIds(
        String childObjectApiName, String parentLookupField, List<Id> parentIds, Integer maxRows
    ) {
        try { Schema.describeSObjects(new List<String>{ childObjectApiName }); }
        catch (Exception e) { return new List<Id>(); }
        List<Id> childIds = new List<Id>();
        try {
            List<SObject> children = Database.query(
                'SELECT Id FROM ' + childObjectApiName
                + ' WHERE ' + parentLookupField + ' IN :parentIds'
                + (maxRows == null ? '' : ' LIMIT ' + maxRows)
            );
            for (SObject child : children) childIds.add(child.Id);
        } catch (Exception e) { }
        return childIds;
    }

    /**
     * Before/after sample of what a By ID run would write on one object, without any DML.
     *
     * The ID list is resolved exactly as startAnonymizationByIds() resolves it — same parsing,
     * same external-ID mode, same parent-to-child hop — then only the first few resolved records
     * are read. A 50 000-record list previews as cheaply as a five-record one.
     */
    @AuraEnabled(cacheable=false)
    public static TEKCO_AnonymizationPreviewService.PreviewSampleDTO previewSampleByIds(
        List<String> rawIds,
        String resolveMode,
        String targetObject,
        String externalIdField,
        String objectApiName,
        List<String> excludedFields,
        Integer sampleSize
    ) {
        TEKCO_AnonymizationBatchUtils.assertCanAnonymize();
        if (rawIds == null || rawIds.isEmpty() || String.isBlank(objectApiName)) {
            throw new AuraHandledException('Provide at least one ID and an object to preview.');
        }
        try {
            List<String> ignoredErrors = new List<String>();
            Map<String, List<Id>> directIdsByObject =
                (resolveMode == MODE_EXTERNAL_ID
                        && String.isNotBlank(targetObject)
                        && String.isNotBlank(externalIdField))
                    ? resolveByExternalIds(rawIds, targetObject, externalIdField, ignoredErrors)
                    : parseAndGroupIds(rawIds, ignoredErrors);

            List<Id> idsForObject = idsForPreview(directIdsByObject, objectApiName);

            return TEKCO_AnonymizationPreviewService.previewByIds(
                objectApiName, idsForObject, excludedFields, sampleSize
            );
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException('Preview failed: ' + e.getMessage());
        }
    }

    /**
     * Ids of objectApiName within the resolved scope: the pasted ids when it is a direct object,
     * otherwise the children reached through the configured parent lookup. Bounded to the
     * preview sample ceiling so the child query never fans out.
     */
    private static List<Id> idsForPreview(
        Map<String, List<Id>> directIdsByObject, String objectApiName
    ) {
        for (String obj : directIdsByObject.keySet()) {
            if (obj.equalsIgnoreCase(objectApiName)) return directIdsByObject.get(obj);
        }

        Map<String, ChildRelationInfo> childRelByObject = buildChildRelationMap(loadAllActiveConfigs());
        for (String childObj : childRelByObject.keySet()) {
            if (!childObj.equalsIgnoreCase(objectApiName)) continue;
            ChildRelationInfo rel = childRelByObject.get(childObj);
            List<Id> parentIds = directIdsByObject.get(rel.parentObjectApiName);
            if (parentIds == null || parentIds.isEmpty()) return new List<Id>();
            return resolveChildIds(
                childObj, rel.parentLookupField, parentIds,
                TEKCO_AnonymizationPreviewService.MAX_SAMPLE_SIZE
            );
        }
        return new List<Id>();
    }

    private class ChildRelationInfo {
        String parentObjectApiName;
        String parentLookupField;
    }

    public class ResolveResultDTO {
        @AuraEnabled public List<ObjectScopeDTO> directObjects;
        @AuraEnabled public List<ObjectScopeDTO> childObjects;
        @AuraEnabled public List<String>         invalidIds;
        @AuraEnabled public List<String>         brands;
        @AuraEnabled public Integer              totalValid;
    }

    public class ObjectScopeDTO {
        @AuraEnabled public String  objectApiName;
        @AuraEnabled public Integer recordCount;
        @AuraEnabled public String  sourceLabel;
    }
}