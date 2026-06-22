/**
 * @description AuraEnabled controller for the tekcoAnonymizationById LWC.
 *              Accepts a list of raw Salesforce IDs, resolves each to its SObject type
 *              via Id.getSObjectType(), validates against active CMDT configurations,
 *              and launches the TEKCO_AnonymizationByIdBatch chain.
 */
public with sharing class TEKCO_AnonymizationByIdController {

    private static final String PATTERN_DELETE_CD = 'DELETE_CONTENT_DOCUMENT';

    /**
     * Resolves raw ID strings to SObject types and checks CMDT configuration coverage.
     * Returns a summary: counts per object, invalid/unconfigured IDs.
     * Cacheable=false because it reflects live CMDT state.
     */
    @AuraEnabled(cacheable=false)
    public static ResolveResultDTO resolveIds(List<String> rawIds) {
        ResolveResultDTO result = new ResolveResultDTO();
        result.objectCounts = new List<ObjectCountDTO>();
        result.invalidIds   = new List<String>();
        result.totalValid   = 0;

        if (rawIds == null || rawIds.isEmpty()) return result;

        Set<String> configuredObjects = getConfiguredObjectNames();
        Map<String, Integer> countsByObject = new Map<String, Integer>();

        for (String rawId : rawIds) {
            String trimmed = rawId.trim();
            if (String.isBlank(trimmed)) continue;
            try {
                Id sfId     = (Id) trimmed;
                String obj  = sfId.getSObjectType().getDescribe().getName();
                if (configuredObjects.contains(obj.toLowerCase())) {
                    Integer current = countsByObject.get(obj);
                    countsByObject.put(obj, current != null ? current + 1 : 1);
                    result.totalValid++;
                } else {
                    result.invalidIds.add(trimmed + ' (' + obj + ' — not configured)');
                }
            } catch (Exception e) {
                result.invalidIds.add(trimmed + ' (invalid ID)');
            }
        }

        for (String obj : countsByObject.keySet()) {
            ObjectCountDTO dto  = new ObjectCountDTO();
            dto.objectApiName   = obj;
            dto.recordCount     = countsByObject.get(obj);
            result.objectCounts.add(dto);
        }
        return result;
    }

    /**
     * Validates permission, groups IDs by SObject type, loads CMDT field configs,
     * activates bypass, creates audit log, and starts the batch chain.
     */
    @AuraEnabled
    public static Id startAnonymizationByIds(List<String> rawIds) {
        if (!FeatureManagement.checkPermission('TEKCO_AnonymizeData')) {
            throw new AuraHandledException(
                'Permission denied: the "TEKCO Anonymize Data" custom permission is required.'
            );
        }

        TEKCO_AnonymizationPatternService.assertIsSandbox();

        if (rawIds == null || rawIds.isEmpty()) {
            throw new AuraHandledException('No IDs provided.');
        }

        // Group valid IDs by SObject type
        Map<String, List<Id>> idsByObject = new Map<String, List<Id>>();
        List<String> parseErrors          = new List<String>();

        for (String rawId : rawIds) {
            String trimmed = rawId.trim();
            if (String.isBlank(trimmed)) continue;
            try {
                Id sfId    = (Id) trimmed;
                String obj = sfId.getSObjectType().getDescribe().getName();
                if (!idsByObject.containsKey(obj)) idsByObject.put(obj, new List<Id>());
                idsByObject.get(obj).add(sfId);
            } catch (Exception e) {
                parseErrors.add(trimmed);
            }
        }

        if (idsByObject.isEmpty()) {
            throw new AuraHandledException(
                'No valid Salesforce IDs found.'
                + (parseErrors.isEmpty() ? '' : ' Invalid: ' + String.join(parseErrors, ', '))
            );
        }

        List<String> objectsToProcess = new List<String>(idsByObject.keySet());

        // Load CMDT configs only for the identified objects
        List<TEKCO_AnonymizationFieldConfig__mdt> allFieldConfigs = [
            SELECT TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c, TEKCO_PatternType__c,
                   TEKCO_IsActive__c, TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_ObjectApiName__c IN :objectsToProcess
        ];

        if (allFieldConfigs.isEmpty()) {
            throw new AuraHandledException(
                'No active anonymization configurations found for: '
                + String.join(objectsToProcess, ', ')
            );
        }

        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType = buildPatternMap();

        // Separate configs into field-update, content-doc, and history groups
        Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>> configsByObject =
            new Map<String, List<TEKCO_AnonymizationFieldConfig__mdt>>();
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        Map<String, List<Id>> contentDocIdsByObject  = new Map<String, List<Id>>();
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        Map<String, List<Id>> historyIdsByObject = new Map<String, List<Id>>();

        for (TEKCO_AnonymizationFieldConfig__mdt fc : allFieldConfigs) {
            String obj = fc.TEKCO_ObjectApiName__c;

            if (fc.TEKCO_PatternType__c == PATTERN_DELETE_CD) {
                contentDocConfigs.add(fc);
                if (!contentDocIdsByObject.containsKey(obj)) {
                    contentDocIdsByObject.put(obj, idsByObject.get(obj));
                }
                continue;
            }

            if (!configsByObject.containsKey(obj)) {
                configsByObject.put(obj, new List<TEKCO_AnonymizationFieldConfig__mdt>());
            }
            configsByObject.get(obj).add(fc);

            if (fc.TEKCO_DeleteHistory__c && !historyIdsByObject.containsKey(obj)) {
                historyIdsByObject.put(obj, idsByObject.get(obj));
            }
            if (fc.TEKCO_DeleteHistory__c) {
                historyConfigs.add(fc);
            }
        }

        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot =
            TEKCO_AnonymizationBypassService.activate();

        Integer totalIds = 0;
        for (List<Id> ids : idsByObject.values()) totalIds += ids.size();

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
            for (String obj : fieldObjects) remainingObjectIds.put(obj, idsByObject.get(obj));

            batchJobId = Database.executeBatch(
                new TEKCO_AnonymizationByIdBatch(
                    firstObj,
                    idsByObject.get(firstObj),
                    configsByObject.get(firstObj),
                    patternsByType,
                    auditLog.Id,
                    remainingObjectIds,
                    contentDocConfigs,
                    contentDocIdsByObject,
                    historyConfigs,
                    historyIdsByObject,
                    bypassSnapshot,
                    new List<String>(),
                    0
                ),
                TEKCO_AnonymizationByIdBatch.DEFAULT_BATCH_SIZE
            );
        } else if (!contentDocConfigs.isEmpty()) {
            TEKCO_AnonymizationFieldConfig__mdt firstConfig = contentDocConfigs.remove(0);
            String firstObj = firstConfig.TEKCO_ObjectApiName__c;
            batchJobId = Database.executeBatch(
                new TEKCO_ContentDocumentByIdBatch(
                    firstObj,
                    contentDocIdsByObject.get(firstObj),
                    auditLog.Id,
                    contentDocConfigs,
                    contentDocIdsByObject,
                    historyConfigs,
                    historyIdsByObject,
                    bypassSnapshot,
                    new List<String>(),
                    0
                ),
                TEKCO_ContentDocumentByIdBatch.DEFAULT_BATCH_SIZE
            );
        } else {
            TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            update new TEKCO_AnonymizationAuditLog__c(
                Id              = auditLog.Id,
                TEKCO_Status__c = 'Success',
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
    public static List<TEKCO_AnonymizationAuditLog__c> getAuditLogs() {
        return [
            SELECT Name, TEKCO_ObjectApiName__c, TEKCO_BrandFilter__c, TEKCO_Status__c,
                   TEKCO_RecordsProcessed__c, TEKCO_RecordsFailed__c, TEKCO_StartTime__c,
                   TEKCO_EndTime__c, TEKCO_JobId__c, TEKCO_TriggeredBy__r.Name, TEKCO_ErrorMessage__c
            FROM TEKCO_AnonymizationAuditLog__c
            WHERE TEKCO_BrandFilter__c LIKE 'BY_ID%'
            ORDER BY TEKCO_StartTime__c DESC
            LIMIT 20
        ];
    }

    // ── Private helpers ──────────────────────────────────────────────────────

    private static Set<String> getConfiguredObjectNames() {
        Set<String> result = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : [
            SELECT TEKCO_ObjectApiName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true AND TEKCO_ObjectApiName__c != null
        ]) {
            result.add(fc.TEKCO_ObjectApiName__c.toLowerCase());
        }
        return result;
    }

    private static Map<String, TEKCO_AnonymizationPattern__mdt> buildPatternMap() {
        Map<String, TEKCO_AnonymizationPattern__mdt> result =
            new Map<String, TEKCO_AnonymizationPattern__mdt>();
        for (TEKCO_AnonymizationPattern__mdt p : [
            SELECT DeveloperName, TEKCO_Description__c, TEKCO_BaseEmail__c,
                   TEKCO_ExternalIdField__c, TEKCO_SsnLength__c, TEKCO_IsActive__c
            FROM TEKCO_AnonymizationPattern__mdt
            WHERE TEKCO_IsActive__c = true
        ]) {
            result.put(p.DeveloperName, p);
        }
        return result;
    }

    // ── DTOs ─────────────────────────────────────────────────────────────────

    public class ResolveResultDTO {
        @AuraEnabled public List<ObjectCountDTO> objectCounts;
        @AuraEnabled public List<String>         invalidIds;
        @AuraEnabled public Integer              totalValid;
    }

    public class ObjectCountDTO {
        @AuraEnabled public String  objectApiName;
        @AuraEnabled public Integer recordCount;
    }
}
