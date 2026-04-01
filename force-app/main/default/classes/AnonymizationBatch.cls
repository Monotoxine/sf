/**
 * AnonymizationBatch
 * Processes one Salesforce object per batch execution.
 * Chains to the next object on finish().
 *
 * Brand filter: added as a dynamic WHERE clause on TEKCO_Brand__c
 * so only records belonging to the selected brands are anonymized.
 *
 * Double sandbox guard:
 *   1. AnonymizationController checks before enqueuing
 *   2. start() checks again before any DML
 */
public class AnonymizationBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ── State (preserved across chunks) ──────────────────────────────────────
    private String objectApiName;
    private List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigs;
    private Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType;
    private List<String> selectedBrands;
    private Id auditLogId;
    private List<String> remainingObjects;

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
        List<String> remainingObjects
    ) {
        this.objectApiName   = objectApiName;
        this.fieldConfigs    = fieldConfigs;
        this.patternsByType  = patternsByType;
        this.selectedBrands  = selectedBrands != null ? selectedBrands : new List<String>();
        this.auditLogId      = auditLogId;
        this.remainingObjects = remainingObjects != null ? remainingObjects : new List<String>();
    }

    // ── Batchable Interface ───────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        AnonymizationSandboxGuard.assertIsSandbox();

        // Build SELECT field list — only query what is needed
        Set<String> fieldSet = new Set<String>{ 'Id' };
        for (TEKCO_AnonymizationFieldConfig__mdt cfg : fieldConfigs) {
            String pType = cfg.Pattern_Type__c;
            // Skip special patterns handled by dedicated batches
            if (pType == 'DELETE_CONTENT_DOCUMENT' || pType == 'EMAIL_MESSAGE_LOREM' || pType == 'KEEP') {
                continue;
            }
            fieldSet.add(cfg.Field_API_Name__c);
            TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(pType);
            if (pattern != null && String.isNotBlank(pattern.External_Id_Field__c)) {
                fieldSet.add(pattern.External_Id_Field__c);
            }
        }

        String soql = 'SELECT ' + String.join(new List<String>(fieldSet), ', ')
                    + ' FROM ' + objectApiName;

        // Apply brand filter if brands were selected and field exists on object
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
                if (pType == 'KEEP' || pType == 'DELETE_CONTENT_DOCUMENT' || pType == 'EMAIL_MESSAGE_LOREM') {
                    continue;
                }

                TEKCO_AnonymizationPattern__mdt pattern = patternsByType.get(pType);
                if (pattern == null || !pattern.Is_Active__c) continue;

                String currentValue;
                try {
                    currentValue = (String) record.get(cfg.Field_API_Name__c);
                } catch (Exception e) {
                    continue;
                }

                String newValue = AnonymizationPatternService.applyPattern(
                    pType, currentValue, record, pattern
                );

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
                    for (Database.Error err : r.getErrors()) {
                        msgs.add(err.getMessage());
                    }
                    errors.add(r.getId() + ': ' + String.join(msgs, '; '));
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        updateAuditLog(false);

        if (!remainingObjects.isEmpty()) {
            String nextObj = remainingObjects.remove(0);
            List<TEKCO_AnonymizationFieldConfig__mdt> nextConfigs = loadFieldConfigs(nextObj);

            if (!nextConfigs.isEmpty()) {
                Database.executeBatch(
                    new AnonymizationBatch(nextObj, nextConfigs, patternsByType, selectedBrands, auditLogId, remainingObjects),
                    DEFAULT_BATCH_SIZE
                );
            } else {
                // No config for this object — skip and continue chain
                new AnonymizationBatch(nextObj, new List<TEKCO_AnonymizationFieldConfig__mdt>(), patternsByType, selectedBrands, auditLogId, remainingObjects)
                    .finish(null);
            }
        } else {
            updateAuditLog(true);
        }
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static List<TEKCO_AnonymizationFieldConfig__mdt> loadFieldConfigs(String objectName) {
        return [
            SELECT Object_API_Name__c, Field_API_Name__c, Pattern_Type__c, Is_Active__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE Object_API_Name__c = :objectName
              AND Is_Active__c = true
        ];
    }

    private void updateAuditLog(Boolean isFinal) {
        if (auditLogId == null) return;
        try {
            Anonymization_Audit_Log__c log = new Anonymization_Audit_Log__c(
                Id                   = auditLogId,
                Records_Processed__c = recordsProcessed,
                Records_Failed__c    = recordsFailed,
                Status__c            = isFinal
                    ? (recordsFailed > 0 ? 'Partial' : 'Success')
                    : 'Running',
                End_Time__c          = isFinal ? Datetime.now() : null,
                Error_Message__c     = errors.isEmpty() ? null : String.join(errors, '\n')
            );
            update log;
        } catch (Exception e) {
            // Silent — audit log failure must not break the chain
        }
    }
}
