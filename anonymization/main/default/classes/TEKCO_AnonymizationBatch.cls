/**
 * @author TEKCO Team, 07/04/2026
 * @description Phase 1 of the anonymization chain: field-level value updates.
 *              Processes all configured fields per object, applies patterns, and updates records.
 *
 *              Chain order: TEKCO_AnonymizationBatch → TEKCO_ContentDocumentBatch → TEKCO_FieldHistoryBatch
 *
 *              Brand filter:      WHERE TEKCO_Brand__c IN :selectedBrands
 *              RecordType filter: per-field, from TEKCO_AnonymizationFieldConfig__mdt.TEKCO_RecordTypeDeveloperName__c
 *              Sandbox guard:     double-checked at controller + start() level.
 */
public class TEKCO_AnonymizationBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer DEFAULT_BATCH_SIZE    = 200;
    private static final Integer MAX_CAPTURED_ERRORS   = 50;
    private static final String  PATTERN_TYPE_DELETE_CONTENT_DOCUMENT = 'DELETE_CONTENT_DOCUMENT';
    private static final String  PATTERN_TYPE_EMAIL_MESSAGE_LOREM     = 'EMAIL_MESSAGE_LOREM';

    // ── Stateful fields ───────────────────────────────────────────────────────

    private String                                        objectApiName;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     fieldConfigs;
    private Map<String, TEKCO_AnonymizationPattern__mdt>  patternsByType;
    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<String>                                  remainingObjects;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     contentDocConfigs;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     historyConfigs;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    // key = child object API name → [parentObjectApiName, parentLookupField, parentRecordTypeDvName]
    private Map<String, List<String>>                     parentFiltersByObject;

    // RecordType Id → DeveloperName map, populated in start()
    private Map<Id, String>                               recordTypeDevNameById =
        new Map<Id, String>();

    private Integer recordsProcessed = 0;
    private Integer recordsFailed    = 0;
    private List<String> errors      = new List<String>();

    // ── Constructor ───────────────────────────────────────────────────────────

    /**
     * @description Constructs the batch with full context to process one object
     *              and pass the remaining work to the next batch in the chain.
     * @param objectApiName     API name of the object to anonymize.
     * @param fieldConfigs      Field configs for this object.
     * @param patternsByType    All active patterns keyed by DeveloperName.
     * @param selectedBrands    Brand values to filter records (empty = all).
     * @param auditLogId        Id of the TEKCO_AnonymizationAuditLog__c record.
     * @param remainingObjects  Objects still to be anonymized after this one.
     * @param contentDocObjects Objects needing ContentDocument deletion (Phase 2).
     * @param historyConfigs    Field configs needing history deletion (Phase 3).
     * @param bypassSnapshot       Bypass state snapshot to restore at chain end.
     * @param parentFiltersByObject Map of child object → [parentObject, parentLookup, parentRT].
     */
    public TEKCO_AnonymizationBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigs,
        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType,
        List<String> selectedBrands,
        Id auditLogId,
        List<String> remainingObjects,
        List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        Map<String, List<String>> parentFiltersByObject
    ) {
        this.objectApiName        = objectApiName;
        this.fieldConfigs         = fieldConfigs;
        this.patternsByType       = patternsByType;
        this.selectedBrands       = selectedBrands    != null ? selectedBrands    : new List<String>();
        this.auditLogId           = auditLogId;
        this.remainingObjects  = remainingObjects  != null ? remainingObjects  : new List<String>();
        this.contentDocConfigs = contentDocConfigs != null ? contentDocConfigs
            : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.historyConfigs    = historyConfigs    != null ? historyConfigs
            : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.bypassSnapshot       = bypassSnapshot;
        this.parentFiltersByObject = parentFiltersByObject != null
            ? parentFiltersByObject : new Map<String, List<String>>();
    }

    // ── Batchable Interface ───────────────────────────────────────────────────

    /**
     * @description Builds the dynamic SOQL query to select records for this object.
     *              Only queries fields required by the configured patterns.
     * @param bc Batch context provided by the platform.
     * @return   QueryLocator for the records to process.
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationSandboxGuard.assertIsSandbox();

        // Detect EMAIL_MESSAGE_LOREM configs — requires Status field + no direct brand filter
        Boolean hasEmailMessageLorem = false;
        for (TEKCO_AnonymizationFieldConfig__mdt fc : fieldConfigs) {
            if (fc.TEKCO_PatternType__c == PATTERN_TYPE_EMAIL_MESSAGE_LOREM) {
                hasEmailMessageLorem = true;
                break;
            }
        }

        Set<String> fieldApiNames = new Set<String>{ 'Id' };
        Boolean needsRecordTypeId = false;

        // Status required to decide update-vs-delete for EMAIL_MESSAGE_LOREM records
        if (hasEmailMessageLorem) {
            fieldApiNames.add('Status');
        }

        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : fieldConfigs) {
            String patternType = fieldConfig.TEKCO_PatternType__c;
            if (patternType == PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                continue;
            }

            fieldApiNames.add(fieldConfig.TEKCO_FieldApiName__c);

            TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(patternType);
            if (pattern != null && String.isNotBlank(pattern.TEKCO_ExternalIdField__c)) {
                fieldApiNames.add(pattern.TEKCO_ExternalIdField__c);
            }
            if (String.isNotBlank(fieldConfig.TEKCO_RecordTypeDeveloperName__c)) {
                needsRecordTypeId = true;
            }
        }

        if (needsRecordTypeId) {
            fieldApiNames.add('RecordTypeId');
            for (RecordType recordType : [
                SELECT Id, DeveloperName
                FROM RecordType
                WHERE SobjectType = :objectApiName
            ]) {
                recordTypeDevNameById.put(recordType.Id, recordType.DeveloperName);
            }
        }

        String soqlQuery = 'SELECT ' + String.join(new List<String>(fieldApiNames), ', ')
            + ' FROM ' + objectApiName;

        List<String> parentFilter = parentFiltersByObject.get(objectApiName);
        String parentObjectApiName    = (parentFilter != null && parentFilter.size() > 0) ? parentFilter.get(0) : null;
        String parentLookupField      = (parentFilter != null && parentFilter.size() > 1) ? parentFilter.get(1) : null;
        String parentRecordTypeDvName = (parentFilter != null && parentFilter.size() > 2) ? parentFilter.get(2) : null;

        if (String.isNotBlank(parentObjectApiName)) {
            // Filter via parent object subquery (child may not have TEKCO_Brand__c)
            List<String> parentConditions = new List<String>();
            if (!selectedBrands.isEmpty()) {
                parentConditions.add('TEKCO_Brand__c IN :selectedBrands');
            }
            if (String.isNotBlank(parentRecordTypeDvName)) {
                parentConditions.add(
                    'RecordType.DeveloperName = \'' + String.escapeSingleQuotes(parentRecordTypeDvName) + '\''
                );
            }
            soqlQuery += ' WHERE ' + parentLookupField
                + ' IN (SELECT Id FROM ' + parentObjectApiName;
            if (!parentConditions.isEmpty()) {
                soqlQuery += ' WHERE ' + String.join(parentConditions, ' AND ');
            }
            soqlQuery += ')';
        } else if (!hasEmailMessageLorem && !selectedBrands.isEmpty()) {
            // EmailMessage has no TEKCO_Brand__c — when EMAIL_MESSAGE_LOREM configs are present
            // and no parent is configured, select all records without a brand filter.
            soqlQuery += ' WHERE TEKCO_Brand__c IN :selectedBrands';
        }

        return Database.getQueryLocator(soqlQuery);
    }

    /**
     * @description Applies configured anonymization patterns to each record in the scope.
     * @param bc    Batch context provided by the platform.
     * @param scope Records to process in this batch chunk.
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<SObject> recordsToUpdate = new List<SObject>();
        List<SObject> recordsToDelete = new List<SObject>();

        for (SObject record : scope) {
            Boolean isModified    = false;
            Boolean shouldDelete  = false;

            for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : fieldConfigs) {
                String patternType = fieldConfig.TEKCO_PatternType__c;
                if (patternType == PATTERN_TYPE_DELETE_CONTENT_DOCUMENT) {
                    continue;
                }

                // EMAIL_MESSAGE_LOREM: Draft → apply lorem, non-Draft → delete the record
                if (patternType == PATTERN_TYPE_EMAIL_MESSAGE_LOREM) {
                    String emailStatus = (String) record.get('Status');
                    if (emailStatus == 'Draft') {
                        String currentValue;
                        try {
                            currentValue = (String) record.get(fieldConfig.TEKCO_FieldApiName__c);
                        } catch (Exception e) { continue; }
                        if (String.isNotBlank(currentValue)) {
                            record.put(fieldConfig.TEKCO_FieldApiName__c,
                                TEKCO_AnonymizationPatternService.LOREM_TEXT);
                            isModified = true;
                        }
                    } else {
                        shouldDelete = true;
                    }
                    continue;
                }

                // RecordType filter — skip if record does not match the required RT
                if (String.isNotBlank(fieldConfig.TEKCO_RecordTypeDeveloperName__c)) {
                    Id recordTypeId = (Id) record.get('RecordTypeId');
                    String recordTypeDeveloperName = recordTypeId != null
                        ? recordTypeDevNameById.get(recordTypeId)
                        : null;
                    if (recordTypeDeveloperName == null
                            || recordTypeDeveloperName != fieldConfig.TEKCO_RecordTypeDeveloperName__c) {
                        continue;
                    }
                }

                TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(patternType);
                if (pattern == null || !pattern.TEKCO_IsActive__c) continue;

                String currentValue;
                try {
                    currentValue = (String) record.get(fieldConfig.TEKCO_FieldApiName__c);
                } catch (Exception e) {
                    continue;
                }

                String newValue = TEKCO_AnonymizationPatternService.applyPattern(
                    patternType,
                    currentValue,
                    record,
                    pattern
                );

                if (newValue != null && newValue != currentValue) {
                    record.put(fieldConfig.TEKCO_FieldApiName__c, newValue);
                    isModified = true;
                }
            }

            // A non-Draft EmailMessage is deleted — do not also attempt to update it
            if (shouldDelete) {
                recordsToDelete.add(record);
            } else if (isModified) {
                recordsToUpdate.add(record);
            }
        }

        if (!recordsToUpdate.isEmpty()) {
            Database.SaveResult[] saveResults = Database.update(recordsToUpdate, false);
            for (Database.SaveResult saveResult : saveResults) {
                if (saveResult.isSuccess()) {
                    recordsProcessed++;
                } else {
                    recordsFailed++;
                    if (errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> errorMessages = new List<String>();
                        for (Database.Error dmlError : saveResult.getErrors()) {
                            errorMessages.add(dmlError.getMessage());
                        }
                        errors.add(saveResult.getId() + ': ' + String.join(errorMessages, '; '));
                    }
                }
            }
        }

        if (!recordsToDelete.isEmpty()) {
            Database.DeleteResult[] deleteResults = Database.delete(recordsToDelete, false);
            for (Database.DeleteResult deleteResult : deleteResults) {
                if (deleteResult.isSuccess()) {
                    recordsProcessed++;
                } else {
                    recordsFailed++;
                    if (errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> errorMessages = new List<String>();
                        for (Database.Error dmlError : deleteResult.getErrors()) {
                            errorMessages.add(dmlError.getMessage());
                        }
                        errors.add('Delete ' + deleteResult.getId() + ': '
                            + String.join(errorMessages, '; '));
                    }
                }
            }
        }
    }

    /**
     * @description Chains to the next batch in the sequence or finalizes the audit log.
     *              Wrapped in try/catch: any exception (governor limit, executeBatch quota, etc.)
     *              closes the audit log as Failed and restores bypass settings so the chain
     *              never gets stuck in Running status.
     * @param bc Batch context provided by the platform.
     */
    public void finish(Database.BatchableContext bc) {
        try {
            if (!remainingObjects.isEmpty()) {
                String nextObjectApiName = remainingObjects.remove(0);
                List<TEKCO_AnonymizationFieldConfig__mdt> nextObjectConfigs =
                    loadFieldConfigs(nextObjectApiName);
                Database.executeBatch(
                    new TEKCO_AnonymizationBatch(
                        nextObjectApiName,
                        nextObjectConfigs,
                        patternsByType,
                        selectedBrands,
                        auditLogId,
                        remainingObjects,
                        contentDocConfigs,
                        historyConfigs,
                        bypassSnapshot,
                        parentFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!contentDocConfigs.isEmpty()) {
                TEKCO_AnonymizationFieldConfig__mdt firstContentDocConfig = contentDocConfigs.remove(0);
                Database.executeBatch(
                    new TEKCO_ContentDocumentBatch(
                        firstContentDocConfig,
                        selectedBrands,
                        auditLogId,
                        contentDocConfigs,
                        historyConfigs,
                        bypassSnapshot,
                        parentFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!historyConfigs.isEmpty()) {
                String firstHistoryObject = historyConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> firstObjectHistoryConfigs =
                    popHistoryConfigsForObject(firstHistoryObject);
                Database.executeBatch(
                    new TEKCO_FieldHistoryBatch(
                        firstHistoryObject,
                        firstObjectHistoryConfigs,
                        selectedBrands,
                        auditLogId,
                        historyConfigs,
                        bypassSnapshot,
                        parentFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                updateAuditLog('Final');
                return;
            }
            // Intermediate update only after executeBatch succeeded — avoids rollback on failure
            updateAuditLog('Running');
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) { /* silent */ }
            closeAuditLogAsFailed(e.getMessage());
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigs(
        String objectApiName
    ) {
        return [
            SELECT
                TEKCO_ObjectApiName__c,
                TEKCO_FieldApiName__c,
                TEKCO_PatternType__c,
                TEKCO_IsActive__c,
                TEKCO_RecordTypeDeveloperName__c,
                TEKCO_DeleteHistory__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_ObjectApiName__c = :objectApiName
                AND TEKCO_IsActive__c = true
        ];
    }

    private List<TEKCO_AnonymizationFieldConfig__mdt> popHistoryConfigsForObject(
        String objectApiName
    ) {
        List<TEKCO_AnonymizationFieldConfig__mdt> configsForObject =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingConfigs =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt fieldConfig : historyConfigs) {
            if (fieldConfig.TEKCO_ObjectApiName__c == objectApiName) {
                configsForObject.add(fieldConfig);
            } else {
                remainingConfigs.add(fieldConfig);
            }
        }
        historyConfigs = remainingConfigs;
        return configsForObject;
    }

    private void updateAuditLog(String phase) {
        if (auditLogId == null) return;
        try {
            Boolean isFinal = phase == 'Final';
            update new TEKCO_AnonymizationAuditLog__c(
                Id                        = auditLogId,
                TEKCO_RecordsProcessed__c = recordsProcessed,
                TEKCO_RecordsFailed__c    = recordsFailed,
                TEKCO_Status__c           = isFinal ? (recordsFailed > 0 ? 'Partial' : 'Success') : 'Running',
                TEKCO_EndTime__c          = isFinal ? Datetime.now() : null,
                TEKCO_ErrorMessage__c     = errors.isEmpty() ? null : String.join(errors, '\n')
            );
        } catch (Exception e) {
            // Silent — audit log failure must not break the batch chain
        }
    }

    private void closeAuditLogAsFailed(String chainError) {
        if (auditLogId == null) return;
        try {
            String errorMsg = (errors.isEmpty() ? '' : String.join(errors, '\n') + '\n')
                + 'Chain error in finish(): ' + chainError;
            update new TEKCO_AnonymizationAuditLog__c(
                Id                        = auditLogId,
                TEKCO_RecordsProcessed__c = recordsProcessed,
                TEKCO_RecordsFailed__c    = recordsFailed,
                TEKCO_Status__c           = 'Failed',
                TEKCO_EndTime__c          = Datetime.now(),
                TEKCO_ErrorMessage__c     = errorMsg
            );
        } catch (Exception e) { /* silent */ }
    }
}
