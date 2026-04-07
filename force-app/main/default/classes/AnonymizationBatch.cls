/**
 * AnonymizationBatch
 * Phase 1 of the anonymization chain: field-level value updates.
 *
 * Chain order:
 *   AnonymizationBatch → ContentDocumentBatch → FieldHistoryBatch
 *
 * Brand filter  : WHERE TEKCO_Brand__c IN :selectedBrands
 * RecordType filter: per-field, from TEKCO_AnonymizationFieldConfig__mdt.Record_Type_Developer_Name__c
 * Double sandbox guard at controller + start() level.
 */
public class AnonymizationBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ── Stateful fields ───────────────────────────────────────────────────────
    private String                                        objectApiName;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     fieldConfigs;
    private Map<String, TEKCO_AnonymizationPattern__mdt>  patternsByType;
    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<String>                                  remainingObjects;

    // Passed through to next phases
    private List<String>                                  contentDocObjects;
    private List<TEKCO_AnonymizationFieldConfig__mdt>     historyConfigs;
    private AnonymizationBypassService.BypassSnapshot     bypassSnapshot;

    // RecordType Id → DeveloperName map, populated in start()
    private Map<Id, String>                               recordTypeDevNameById = new Map<Id, String>();

    private Integer recordsProcessed = 0;
    private Integer recordsFailed    = 0;
    private List<String> errors      = new List<String>();

    private static final Integer DEFAULT_BATCH_SIZE = 200;

    // ── Constructor ───────────────────────────────────────────────────────────

    public AnonymizationBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigs,
        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType,
        List<String> selectedBrands,
        Id auditLogId,
        List<String> remainingObjects,
        List<String> contentDocObjects,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs,
        AnonymizationBypassService.BypassSnapshot bypassSnapshot
    ) {
        this.objectApiName     = objectApiName;
        this.fieldConfigs      = fieldConfigs;
        this.patternsByType    = patternsByType;
        this.selectedBrands    = selectedBrands    != null ? selectedBrands    : new List<String>();
        this.auditLogId        = auditLogId;
        this.remainingObjects  = remainingObjects  != null ? remainingObjects  : new List<String>();
        this.contentDocObjects = contentDocObjects != null ? contentDocObjects : new List<String>();
        this.historyConfigs    = historyConfigs    != null ? historyConfigs    : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.bypassSnapshot    = bypassSnapshot;
    }

    // ── Batchable Interface ───────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        AnonymizationSandboxGuard.assertIsSandbox();

        // Build SELECT field list — only query what is needed
        Set<String> fieldSet = new Set<String>{ 'Id' };
        Boolean needsRecordType = false;

        for (TEKCO_AnonymizationFieldConfig__mdt cfg : fieldConfigs) {
            String pType = cfg.Pattern_Type__c;
            if (pType == 'DELETE_CONTENT_DOCUMENT' || pType == 'EMAIL_MESSAGE_LOREM' || pType == 'KEEP') continue;

            fieldSet.add(cfg.Field_API_Name__c);

            TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(pType);
            if (pattern != null && String.isNotBlank(pattern.External_Id_Field__c)) {
                fieldSet.add(pattern.External_Id_Field__c);
            }
            if (String.isNotBlank(cfg.Record_Type_Developer_Name__c)) {
                needsRecordType = true;
            }
        }

        if (needsRecordType) {
            fieldSet.add('RecordTypeId');
            for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = :objectApiName]) {
                recordTypeDevNameById.put(rt.Id, rt.DeveloperName);
            }
        }

        String soql = 'SELECT ' + String.join(new List<String>(fieldSet), ', ')
                    + ' FROM ' + objectApiName;

        if (!selectedBrands.isEmpty()) {
            soql += ' WHERE TEKCO_Brand__c IN :selectedBrands';
        }

        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<SObject> toUpdate = new List<SObject>();

        for (SObject record : scope) {
            Boolean modified = false;

            for (TEKCO_AnonymizationFieldConfig__mdt cfg : fieldConfigs) {
                String pType = cfg.Pattern_Type__c;
                if (pType == 'KEEP' || pType == 'DELETE_CONTENT_DOCUMENT' || pType == 'EMAIL_MESSAGE_LOREM') continue;

                // RecordType filter
                if (String.isNotBlank(cfg.Record_Type_Developer_Name__c)) {
                    Id rtId = (Id) record.get('RecordTypeId');
                    String rtDevName = rtId != null ? recordTypeDevNameById.get(rtId) : null;
                    if (rtDevName == null || rtDevName != cfg.Record_Type_Developer_Name__c) continue;
                }

                TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(pType);
                if (pattern == null || !pattern.Is_Active__c) continue;

                String currentValue;
                try {
                    currentValue = (String) record.get(cfg.Field_API_Name__c);
                } catch (Exception e) {
                    continue;
                }

                String newValue = AnonymizationPatternService.applyPattern(pType, currentValue, record, pattern);

                if (newValue != null && newValue != currentValue) {
                    record.put(cfg.Field_API_Name__c, newValue);
                    modified = true;
                }
            }

            if (modified) toUpdate.add(record);
        }

        if (toUpdate.isEmpty()) return;

        Database.SaveResult[] results = Database.update(toUpdate, false);
        for (Database.SaveResult r : results) {
            if (r.isSuccess()) {
                recordsProcessed++;
            } else {
                recordsFailed++;
                if (errors.size() < 50) {
                    List<String> msgs = new List<String>();
                    for (Database.Error err : r.getErrors()) msgs.add(err.getMessage());
                    errors.add(r.getId() + ': ' + String.join(msgs, '; '));
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        updateAuditLog('Running');

        if (!remainingObjects.isEmpty()) {
            // More objects to anonymize — chain to next
            String nextObj = remainingObjects.remove(0);
            List<TEKCO_AnonymizationFieldConfig__mdt> nextConfigs = loadFieldConfigs(nextObj);
            Database.executeBatch(
                new AnonymizationBatch(nextObj, nextConfigs, patternsByType, selectedBrands,
                                       auditLogId, remainingObjects, contentDocObjects,
                                       historyConfigs, bypassSnapshot),
                DEFAULT_BATCH_SIZE
            );
        } else if (!contentDocObjects.isEmpty()) {
            // Phase 2: ContentDocument deletion
            String firstObj = contentDocObjects.remove(0);
            Database.executeBatch(
                new ContentDocumentBatch(firstObj, selectedBrands, auditLogId,
                                         contentDocObjects, historyConfigs, bypassSnapshot),
                DEFAULT_BATCH_SIZE
            );
        } else if (!historyConfigs.isEmpty()) {
            // Phase 3: Field history deletion
            String firstObj = historyConfigs[0].Object_API_Name__c;
            List<TEKCO_AnonymizationFieldConfig__mdt> objHistoryConfigs = popHistoryConfigsForObject(firstObj);
            Database.executeBatch(
                new FieldHistoryBatch(firstObj, objHistoryConfigs, selectedBrands, auditLogId,
                                      historyConfigs, bypassSnapshot),
                DEFAULT_BATCH_SIZE
            );
        } else {
            AnonymizationBypassService.restore(bypassSnapshot);
            updateAuditLog('Final');
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigs(String objectName) {
        return [
            SELECT Object_API_Name__c, Field_API_Name__c, Pattern_Type__c,
                   Is_Active__c, Record_Type_Developer_Name__c, Delete_History__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE Object_API_Name__c = :objectName
              AND Is_Active__c = true
        ];
    }

    private List<TEKCO_AnonymizationFieldConfig__mdt> popHistoryConfigsForObject(String objectName) {
        List<TEKCO_AnonymizationFieldConfig__mdt> forObj = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> remaining = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt cfg : historyConfigs) {
            if (cfg.Object_API_Name__c == objectName) {
                forObj.add(cfg);
            } else {
                remaining.add(cfg);
            }
        }
        historyConfigs = remaining;
        return forObj;
    }

    private void updateAuditLog(String phase) {
        if (auditLogId == null) return;
        try {
            Boolean isFinal = phase == 'Final';
            Anonymization_Audit_Log__c log = new Anonymization_Audit_Log__c(
                Id                   = auditLogId,
                Records_Processed__c = recordsProcessed,
                Records_Failed__c    = recordsFailed,
                Status__c            = isFinal ? (recordsFailed > 0 ? 'Partial' : 'Success') : 'Running',
                End_Time__c          = isFinal ? Datetime.now() : null,
                Error_Message__c     = errors.isEmpty() ? null : String.join(errors, '\n')
            );
            update log;
        } catch (Exception e) {
            // Silent — audit log failure must not break the chain
        }
    }
}
