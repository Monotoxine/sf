/**
 * @description AuraEnabled controller for the "By ID" tab of tekcoDataAnonymizationAdmin LWC.
 */
public with sharing class TEKCO_AnonymizationByIdController {

    private static final String PATTERN_DELETE_CD  = 'DELETE_CONTENT_DOCUMENT';
    private static final String MODE_EXTERNAL_ID   = 'EXTERNAL_ID';

    @AuraEnabled(cacheable=false)
    public static ResolveResultDTO resolveIds(
        List<String> rawIds,
        String resolveMode,
        String targetObject,
        String externalIdField
    ) {
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
        if (!FeatureManagement.checkPermission('TEKCO_AnonymizeData')) {
            throw new AuraHandledException(
                'Permission denied: the "TEKCO Anonymize Data" custom permission is required.'
            );
        }
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

        List<String> objectsToProcess = new List<String>(allIdsByObject.keySet());

        List<TEKCO_AnonymizationFieldConfig__mdt> scopedConfigs = [
            SELECT TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c, TEKCO_PatternType__c,
                   TEKCO_IsActive__c, TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_ObjectApiName__c IN :objectsToProcess
        ];

        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByObject =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        Map<String, List<Id>> contentDocIdsByObject  = new Map<String, List<Id>>();
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        Map<String, List<Id>> historyIdsByObject = new Map<String, List<Id>>();

        for (TEKCO_AnonymizationFieldConfig__mdt fc : scopedConfigs) {
            String obj      = fc.TEKCO_ObjectApiName__c;
            String fieldKey = obj + '.' + fc.TEKCO_FieldApiName__c + '.'
                + (fc.TEKCO_RecordTypeDeveloperName__c != null ? fc.TEKCO_RecordTypeDeveloperName__c : '');

            if (excludedFieldKeys.contains(fieldKey)) continue;

            if (fc.TEKCO_PatternType__c == PATTERN_DELETE_CD) {
                contentDocConfigs.add(fc);
                if (!contentDocIdsByObject.containsKey(obj)) {
                    contentDocIdsByObject.put(obj, allIdsByObject.get(obj));
                }
                continue;
            }

            if (!configsByObject.containsKey(obj)) {
                configsByObject.put(obj, new List<TEKCO_AnonymizationFieldConfig__mdt>());
            }
            configsByObject.get(obj).add(fc);

            if (fc.TEKCO_DeleteHistory__c && !noHistoryFieldKeys.contains(fieldKey)) {
                historyConfigs.add(fc);
                if (!historyIdsByObject.containsKey(obj)) {
                    historyIdsByObject.put(obj, allIdsByObject.get(obj));
                }
            }
        }

        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType = buildPatternMap();
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot =
            TEKCO_AnonymizationBypassService.activate();

        Integer totalIds = 0;
        for (List<Id> ids : allIdsByObject.values()) totalIds += ids.size();

        TEKCO_AnonymizationAuditLog__c auditLog = new TEKCO_AnonymizationAuditLog__c(
            TEKCO_TriggeredBy__c   = UserInfo.getUserId(),
            TEKCO_BrandFilter__c   = 'BY_ID (' + totalIds + ' record(s))',
            TEKCO_ObjectApiName__c = String.join(objectsToProcess, ', '),
            TEKCO_Status__c        = 'Running',
            TEKCO_StartTime__c     = Datetime.now()
        );
        insert auditLog;

        Id batchJobId;

        List<String> fieldObjects = new List<String>();
        for (String obj : objectsToProcess) {
            if (configsByObject.containsKey(obj)) fieldObjects.add(obj);
        }

        if (!fieldObjects.isEmpty()) {
            String firstObj = fieldObjects.remove(0);
            Map<String, List<Id>> remainingObjectIds = new Map<String, List<Id>>();
            for (String obj : fieldObjects) remainingObjectIds.put(obj, allIdsByObject.get(obj));

            batchJobId = Database.executeBatch(
                new TEKCO_AnonymizationByIdBatch(
                    firstObj, allIdsByObject.get(firstObj), configsByObject.get(firstObj),
                    patternsByType, auditLog.Id, remainingObjectIds,
                    contentDocConfigs, contentDocIdsByObject,
                    historyConfigs, historyIdsByObject,
                    bypassSnapshot, new List<String>(), 0
                ),
                TEKCO_AnonymizationByIdBatch.DEFAULT_BATCH_SIZE
            );
        } else if (!contentDocConfigs.isEmpty()) {
            TEKCO_AnonymizationFieldConfig__mdt firstConfig = contentDocConfigs.remove(0);
            String firstObj = firstConfig.TEKCO_ObjectApiName__c;
            batchJobId = Database.executeBatch(
                new TEKCO_ContentDocumentByIdBatch(
                    firstObj, contentDocIdsByObject.get(firstObj), auditLog.Id,
                    contentDocConfigs, contentDocIdsByObject,
                    historyConfigs, historyIdsByObject,
                    bypassSnapshot, new List<String>(), 0, 0
                ),
                TEKCO_ContentDocumentByIdBatch.DEFAULT_BATCH_SIZE
            );
        } else {
            TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            update new TEKCO_AnonymizationAuditLog__c(
                Id               = auditLog.Id,
                TEKCO_Status__c  = 'Success',
                TEKCO_EndTime__c = Datetime.now(),
                TEKCO_ErrorMessage__c = 'No active field configurations found for provided records.'
            );
            return auditLog.Id;
        }

        auditLog.TEKCO_JobId__c = String.valueOf(batchJobId);
        update auditLog;
        return auditLog.Id;
    }

    @AuraEnabled(cacheable=false)
    public static List<TEKCO_AnonymizationAuditLog__c> getAuditLogsByid() {
        return [
            SELECT Name, TEKCO_ObjectApiName__c, TEKCO_BrandFilter__c, TEKCO_Status__c,
                   TEKCO_RecordsProcessed__c, TEKCO_RecordsFailed__c,
                   TEKCO_DocumentsDeleted__c, TEKCO_HistoryRecordsDeleted__c,
                   TEKCO_StartTime__c, TEKCO_EndTime__c, TEKCO_JobId__c,
                   TEKCO_TriggeredBy__r.Name, TEKCO_ErrorMessage__c
            FROM TEKCO_AnonymizationAuditLog__c
            WHERE TEKCO_BrandFilter__c LIKE 'BY_ID%'
            ORDER BY TEKCO_StartTime__c DESC
            LIMIT 20
        ];
    }

    @AuraEnabled(cacheable=true)
    public static List<Map<String, String>> getDirectObjects() {
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

        String extraFields = TEKCO_AnonymizationOrgConfigService.getConfig().externalIdFields;
        if (String.isNotBlank(extraFields)) {
            for (String f : extraFields.split(',')) {
                String trimmed = f.trim();
                if (String.isNotBlank(trimmed)
                        && TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, trimmed.toLowerCase())) {
                    fields.add(trimmed);
                }
            }
        }

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
        try { Schema.describeSObjects(new List<String>{ objectApiName }); }
        catch (Exception e) {
            if (invalidOut != null) invalidOut.add(objectApiName + ' — object not found in org');
            return result;
        }
        try {
            List<SObject> records = Database.query(
                'SELECT Id FROM ' + objectApiName
                + ' WHERE ' + fieldApiName + ' IN :rawValues'
            );
            List<Id> ids = new List<Id>();
            for (SObject r : records) ids.add(r.Id);
            if (!ids.isEmpty()) result.put(objectApiName, ids);
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
        try { Schema.describeSObjects(new List<String>{ childObjectApiName }); }
        catch (Exception e) { return new List<Id>(); }
        List<Id> childIds = new List<Id>();
        try {
            List<SObject> children = Database.query(
                'SELECT Id FROM ' + childObjectApiName
                + ' WHERE ' + parentLookupField + ' IN :parentIds'
            );
            for (SObject child : children) childIds.add(child.Id);
        } catch (Exception e) { }
        return childIds;
    }

    private static Map<String, TEKCO_AnonymizationPattern__mdt> buildPatternMap() {
        return TEKCO_AnonymizationBatchUtils.buildPatternMap();
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
