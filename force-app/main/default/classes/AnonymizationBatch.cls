/**
 * AnonymizationBatch
 * Batch Apex that anonymizes one Salesforce object at a time.
 * Chains automatically to the next object when done.
 *
 * Double sandbox guard:
 *   1. AnonymizationController checks before enqueuing (LWC entry point)
 *   2. This batch checks again in start() before any DML
 *
 * Governor limit protections:
 *   - Only queries the specific fields needed (no SELECT *)
 *   - Database.update with allOrNone=false for partial success
 *   - Database.Stateful to accumulate counters across chunks
 *   - Configurable batch size (default 200)
 */
public class AnonymizationBatch implements Database.Batchable<SObject>, Database.Stateful {

    // ─── State (preserved across chunks via Database.Stateful) ───────────────
    private String objectApiName;
    private List<Anon_Object_Config__mdt> fieldConfigs;
    private Map<String, Anon_Pattern__mdt> patternsByType;
    private Id auditLogId;
    private Integer batchSize;

    private Integer recordsProcessed = 0;
    private Integer recordsFailed    = 0;
    private List<String> errors      = new List<String>();

    // For chaining: ordered list of remaining object names after this one
    private List<String> remainingObjectNames;
    private String brandFilter;

    // ─── Constructor ─────────────────────────────────────────────────────────

    public AnonymizationBatch(
        String objectApiName,
        List<Anon_Object_Config__mdt> fieldConfigs,
        Map<String, Anon_Pattern__mdt> patternsByType,
        Id auditLogId,
        List<String> remainingObjectNames,
        String brandFilter,
        Integer batchSize
    ) {
        this.objectApiName        = objectApiName;
        this.fieldConfigs         = fieldConfigs;
        this.patternsByType       = patternsByType;
        this.auditLogId           = auditLogId;
        this.remainingObjectNames = remainingObjectNames != null ? remainingObjectNames : new List<String>();
        this.brandFilter          = brandFilter;
        this.batchSize            = (batchSize != null && batchSize > 0) ? batchSize : 200;
    }

    // ─── Batchable Interface ──────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // DOUBLE GUARD: abort before any DML if not sandbox
        AnonymizationSandboxGuard.assertIsSandbox();

        // Build field set: always include Id + ExternalId fields used by patterns
        Set<String> fieldSet = new Set<String>{ 'Id' };
        for (Anon_Object_Config__mdt cfg : fieldConfigs) {
            if (cfg.Pattern_Type__c != 'KEEP') {
                fieldSet.add(cfg.Field_API_Name__c);
            }
            // Also include the ExternalId field if referenced by the pattern
            Anon_Pattern__mdt pattern = patternsByType.get(cfg.Pattern_Type__c);
            if (pattern != null && String.isNotBlank(pattern.External_Id_Field__c)) {
                fieldSet.add(pattern.External_Id_Field__c);
            }
        }

        String query = 'SELECT ' + String.join(new List<String>(fieldSet), ', ')
                     + ' FROM ' + objectApiName;

        return Database.getQueryLocator(query);
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        List<SObject> toUpdate = new List<SObject>();

        for (SObject record : scope) {
            Boolean modified = false;

            for (Anon_Object_Config__mdt cfg : fieldConfigs) {
                // Skip KEEP pattern — no change needed
                if (cfg.Pattern_Type__c == 'KEEP') continue;

                Anon_Pattern__mdt pattern = patternsByType.get(cfg.Pattern_Type__c);
                if (pattern == null || !pattern.Is_Active__c) continue;

                // Optional condition check (e.g., only for portal users)
                if (!meetsCondition(record, cfg)) continue;

                String currentValue = (String) record.get(cfg.Field_API_Name__c);
                String newValue = AnonymizationPatternService.applyPattern(
                    cfg.Pattern_Type__c,
                    currentValue,
                    record,
                    pattern
                );

                if (newValue != null && newValue != currentValue) {
                    record.put(cfg.Field_API_Name__c, newValue);
                    modified = true;
                }
            }

            if (modified) {
                toUpdate.add(record);
            }
        }

        if (toUpdate.isEmpty()) return;

        // allOrNone = false: partial failures don't roll back the entire chunk
        Database.SaveResult[] results = Database.update(toUpdate, false);
        for (Database.SaveResult result : results) {
            if (result.isSuccess()) {
                recordsProcessed++;
            } else {
                recordsFailed++;
                if (errors.size() < 50) { // cap error list to avoid heap issues
                    List<String> msgs = new List<String>();
                    for (Database.Error err : result.getErrors()) {
                        msgs.add(err.getMessage());
                    }
                    errors.add(result.getId() + ': ' + String.join(msgs, '; '));
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        // Update audit log for this object
        updateAuditLog();

        // Chain to next object if any
        if (!remainingObjectNames.isEmpty()) {
            String nextObject = remainingObjectNames.remove(0);
            List<Anon_Object_Config__mdt> nextConfigs = loadFieldConfigs(nextObject, brandFilter);

            if (!nextConfigs.isEmpty()) {
                Integer nextBatchSize = Integer.valueOf(nextConfigs[0].Batch_Size__c != null
                    ? nextConfigs[0].Batch_Size__c : 200);

                AnonymizationBatch nextBatch = new AnonymizationBatch(
                    nextObject,
                    nextConfigs,
                    patternsByType,
                    auditLogId,
                    remainingObjectNames,
                    brandFilter,
                    nextBatchSize
                );
                Database.executeBatch(nextBatch, nextBatchSize);
            } else {
                // No config for next object, skip and continue chain
                new AnonymizationBatch(
                    nextObject,
                    new List<Anon_Object_Config__mdt>(),
                    patternsByType,
                    auditLogId,
                    remainingObjectNames,
                    brandFilter,
                    200
                ).finish(null);
            }
        } else {
            // All objects processed — mark audit log complete
            finalizeAuditLog();
        }
    }

    // ─── Private Helpers ──────────────────────────────────────────────────────

    /**
     * Checks optional condition: if Condition_Field__c is set, the record's
     * field value must equal Condition_Value__c.
     */
    private Boolean meetsCondition(SObject record, Anon_Object_Config__mdt cfg) {
        if (String.isBlank(cfg.Condition_Field__c)) return true;
        try {
            Object fieldVal = record.get(cfg.Condition_Field__c);
            return String.valueOf(fieldVal) == cfg.Condition_Value__c;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * Loads Anon_Object_Config__mdt records for a given object + brand.
     */
    private static List<Anon_Object_Config__mdt> loadFieldConfigs(String objectName, String brand) {
        if (String.isBlank(brand)) {
            return [
                SELECT Object_API_Name__c, Field_API_Name__c, Pattern_Type__c,
                       Brand__c, Is_Active__c, Order__c, Batch_Size__c,
                       Condition_Field__c, Condition_Value__c
                FROM Anon_Object_Config__mdt
                WHERE Object_API_Name__c = :objectName
                  AND Is_Active__c = true
                ORDER BY Order__c ASC NULLS LAST
            ];
        } else {
            return [
                SELECT Object_API_Name__c, Field_API_Name__c, Pattern_Type__c,
                       Brand__c, Is_Active__c, Order__c, Batch_Size__c,
                       Condition_Field__c, Condition_Value__c
                FROM Anon_Object_Config__mdt
                WHERE Object_API_Name__c = :objectName
                  AND Is_Active__c = true
                  AND (Brand__c = :brand OR Brand__c = 'ALL')
                ORDER BY Order__c ASC NULLS LAST
            ];
        }
    }

    private void updateAuditLog() {
        if (auditLogId == null) return;
        try {
            Anonymization_Audit_Log__c log = new Anonymization_Audit_Log__c(
                Id               = auditLogId,
                Records_Processed__c = recordsProcessed,
                Records_Failed__c    = recordsFailed,
                Status__c            = recordsFailed > 0 ? 'Partial' : 'Running',
                Error_Message__c     = errors.isEmpty() ? null : String.join(errors, '\n')
            );
            update log;
        } catch (Exception e) {
            // Log update failure must not break the chain
        }
    }

    private void finalizeAuditLog() {
        if (auditLogId == null) return;
        try {
            Anonymization_Audit_Log__c log = new Anonymization_Audit_Log__c(
                Id               = auditLogId,
                Status__c        = recordsFailed > 0 ? 'Partial' : 'Success',
                End_Time__c      = Datetime.now(),
                Error_Message__c = errors.isEmpty() ? null : String.join(errors, '\n')
            );
            update log;
        } catch (Exception e) {
            // Silent — audit log failure must not surface as a user error
        }
    }
}
