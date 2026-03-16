/**
 * @description Batch Apex class that anonymizes all records of a single Salesforce object
 *              according to the field configurations stored in Anon_Field_Config__mdt.
 *
 * ─── SAFETY GUARDRAILS ───────────────────────────────────────────────────────
 *
 *  1. SANDBOX CHECK (DOUBLE GUARD)
 *     The sandbox check runs in BOTH the constructor AND execute(). This ensures
 *     that even if the batch is somehow instantiated without going through the
 *     controller (e.g. via Developer Console), it will abort before any DML.
 *
 *  2. PERMISSION CHECK
 *     The running user must have the Data_Anonymization_Admin custom permission.
 *     Checked in execute() to guard against privilege-escalation scenarios.
 *
 *  3. allOrNothing = false
 *     DML is called with partial-success mode so a single bad record doesn't
 *     roll back the entire batch chunk.
 *
 * ─── CHAINING ────────────────────────────────────────────────────────────────
 *  When multiple objects are included in a run, the finish() method automatically
 *  launches a new DataAnonymizationBatch for the next object in remainingConfigs.
 *  This produces a sequential chain without requiring a separate Queueable.
 *
 * ─── GOVERNOR LIMITS ─────────────────────────────────────────────────────────
 *  - Query: 1 SOQL per start() (getQueryLocator), 0 in execute().
 *  - DML: 1 update per execute() chunk (allOrNothing=false).
 *  - Heap: Strategy instances are re-used within a chunk via a Map cache.
 *  - CPU: Strategy classes are stateless; no heavy computation.
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public without sharing class DataAnonymizationBatch
    implements Database.Batchable<SObject>, Database.Stateful {

    // ── Configuration ──────────────────────────────────────────────────────────

    private final String       objectApiName;
    private final String       brandFilter;
    private final String       brandFieldName;
    private final String       externalIdField;
    private final Integer      batchSize;
    private final String       runGroupId;
    private final List<String> remainingObjectConfigNames; // configs still to process after this one

    /** Field configs loaded once in constructor from metadata. */
    private final List<Anon_Field_Config__mdt> fieldConfigs;

    // ── State (Database.Stateful) ─────────────────────────────────────────────

    private Id      runLogId;
    private Integer recordsProcessed = 0;
    private Integer recordsFailed    = 0;
    private String  errorBuffer      = '';

    // ── Constants ─────────────────────────────────────────────────────────────

    private static final Integer DEFAULT_BATCH_SIZE = 200;
    private static final Integer MAX_ERROR_BUFFER   = 30000; // chars, leaves room below 32 KB limit

    // ── Constructor ───────────────────────────────────────────────────────────

    /**
     * @param objectConfigName    DeveloperName of the Anon_Object_Config__mdt record.
     * @param remainingConfigs    Ordered list of config developer names to process AFTER this one.
     * @param brandFilter         Optional brand/subsidiary filter value. Null = all brands.
     * @param runGroupId          UUID shared across all log entries for this run.
     * @param runLogId            Id of the Anon_Run_Log__c record pre-created for this object.
     */
    public DataAnonymizationBatch(
        String       objectConfigName,
        List<String> remainingConfigs,
        String       brandFilter,
        String       runGroupId,
        Id           runLogId
    ) {
        // ── GUARD 1: Sandbox check (constructor) ─────────────────────────────
        assertSandbox();

        this.brandFilter                = brandFilter;
        this.runGroupId                 = runGroupId;
        this.runLogId                   = runLogId;
        this.remainingObjectConfigNames = remainingConfigs != null
            ? new List<String>(remainingConfigs)
            : new List<String>();

        // Load object config from metadata
        List<Anon_Object_Config__mdt> objConfigs = [
            SELECT Object_API_Name__c, External_ID_Field__c,
                   Brand_Field_API_Name__c, Batch_Size__c, Is_Active__c
            FROM   Anon_Object_Config__mdt
            WHERE  DeveloperName = :objectConfigName
            AND    Is_Active__c  = true
            LIMIT  1
        ];

        if (objConfigs.isEmpty()) {
            throw new DataAnonymizationException(
                'No active Anon_Object_Config__mdt found with DeveloperName: ' + objectConfigName
            );
        }

        Anon_Object_Config__mdt cfg = objConfigs[0];
        this.objectApiName   = cfg.Object_API_Name__c;
        this.externalIdField = cfg.External_ID_Field__c;
        this.brandFieldName  = cfg.Brand_Field_API_Name__c;
        this.batchSize       = (cfg.Batch_Size__c != null && cfg.Batch_Size__c > 0)
                               ? (Integer)cfg.Batch_Size__c
                               : DEFAULT_BATCH_SIZE;

        // Load active field configs for this object, ordered by Execution_Order__c
        this.fieldConfigs = [
            SELECT Field_API_Name__c, Strategy_Class_Name__c,
                   Strategy_Param_1__c, Strategy_Param_2__c,
                   Execution_Order__c, Field_Label__c
            FROM   Anon_Field_Config__mdt
            WHERE  Object_Config_Name__c = :objectConfigName
            AND    Is_Active__c          = true
            ORDER BY Execution_Order__c NULLS LAST, Field_API_Name__c
        ];

        if (this.fieldConfigs.isEmpty()) {
            throw new DataAnonymizationException(
                'No active Anon_Field_Config__mdt records found for object config: ' + objectConfigName
            );
        }
    }

    // ── Batchable: start ──────────────────────────────────────────────────────

    public Database.QueryLocator start(Database.BatchableContext bc) {
        // ── GUARD 2: Sandbox check (start — second layer) ─────────────────────
        assertSandbox();

        // Update log with batch job ID
        if (runLogId != null) {
            update new Anon_Run_Log__c(
                Id            = runLogId,
                Batch_Job_ID__c = String.valueOf(bc.getJobId()),
                Status__c     = 'In Progress'
            );
        }

        // Build the SELECT field list: Id + external ID (if configured) + all fields to anonymize
        Set<String> selectFields = new Set<String>{ 'Id' };
        if (String.isNotBlank(externalIdField)) {
            selectFields.add(externalIdField);
        }
        for (Anon_Field_Config__mdt fc : fieldConfigs) {
            selectFields.add(fc.Field_API_Name__c);
        }

        String soql = 'SELECT ' + String.join(new List<String>(selectFields), ', ')
                    + ' FROM ' + objectApiName;

        if (String.isNotBlank(brandFilter) && String.isNotBlank(brandFieldName)) {
            soql += ' WHERE ' + brandFieldName + ' = \'' + String.escapeSingleQuotes(brandFilter) + '\'';
        }

        return Database.getQueryLocator(soql);
    }

    // ── Batchable: execute ────────────────────────────────────────────────────

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        // ── GUARD 3: Sandbox check (execute — third layer, innermost) ─────────
        assertSandbox();

        // ── GUARD 4: Permission check ─────────────────────────────────────────
        assertPermission();

        // Cache strategy instances per class name to avoid repeated Type.forName calls
        Map<String, IAnonymizationStrategy> strategyCache = new Map<String, IAnonymizationStrategy>();

        List<SObject> toUpdate = new List<SObject>();

        for (SObject record : scope) {
            try {
                for (Anon_Field_Config__mdt fc : fieldConfigs) {
                    IAnonymizationStrategy strategy = resolveStrategy(fc.Strategy_Class_Name__c, strategyCache);
                    AnonymizationContext ctx = new AnonymizationContext(
                        record,
                        fc.Field_API_Name__c,
                        externalIdField,
                        fc.Strategy_Param_1__c,
                        fc.Strategy_Param_2__c
                    );
                    String anonymizedValue = strategy.anonymize(ctx);
                    record.put(fc.Field_API_Name__c, anonymizedValue);
                }
                toUpdate.add(record);
            } catch (Exception e) {
                appendError('Record ' + record.Id + ': ' + e.getMessage());
                recordsFailed++;
            }
        }

        if (!toUpdate.isEmpty()) {
            Database.SaveResult[] results = Database.update(toUpdate, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    recordsProcessed++;
                } else {
                    recordsFailed++;
                    String errMsg = 'Record ' + toUpdate[i].Id + ': ';
                    for (Database.Error err : results[i].getErrors()) {
                        errMsg += err.getMessage() + ' ';
                    }
                    appendError(errMsg.trim());
                }
            }
        }
    }

    // ── Batchable: finish ─────────────────────────────────────────────────────

    public void finish(Database.BatchableContext bc) {
        // Determine final status
        String finalStatus = 'Success';
        if (recordsFailed > 0 && recordsProcessed == 0) {
            finalStatus = 'Failed';
        } else if (recordsFailed > 0) {
            finalStatus = 'Partial';
        }

        // Update audit log
        if (runLogId != null) {
            update new Anon_Run_Log__c(
                Id                  = runLogId,
                Status__c           = finalStatus,
                Records_Processed__c = recordsProcessed,
                Records_Failed__c   = recordsFailed,
                Error_Details__c    = errorBuffer,
                Completion_Date__c  = Datetime.now()
            );
        }

        // Chain next batch if more objects remain
        if (!remainingObjectConfigNames.isEmpty()) {
            String nextConfigName = remainingObjectConfigNames.remove(0);
            // The next log record must already exist (created by the controller before any batch started)
            // Query it by Run_Group_ID__c + Object config name pattern
            List<Anon_Run_Log__c> nextLogs = [
                SELECT Id FROM Anon_Run_Log__c
                WHERE  Run_Group_ID__c   = :runGroupId
                AND    Object_API_Name__c = :resolveObjectApiName(nextConfigName)
                AND    Status__c          = 'In Progress'
                LIMIT  1
            ];
            Id nextLogId = nextLogs.isEmpty() ? null : nextLogs[0].Id;

            Database.executeBatch(
                new DataAnonymizationBatch(
                    nextConfigName,
                    remainingObjectConfigNames,
                    brandFilter,
                    runGroupId,
                    nextLogId
                ),
                batchSize
            );
        }
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    /**
     * @description Enforces that the current org is a sandbox. Throws immediately
     *              if running on production — no DML will ever execute.
     */
    private static void assertSandbox() {
        Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
        if (!org.IsSandbox) {
            throw new DataAnonymizationException(
                '⛔ PRODUCTION ORG DETECTED. Data anonymization is strictly forbidden on production. ' +
                'No records have been modified. Aborting immediately.'
            );
        }
    }

    /**
     * @description Enforces that the running user holds the Data_Anonymization_Admin
     *              custom permission. Throws if the permission is missing.
     */
    private static void assertPermission() {
        if (!FeatureManagement.checkPermission('Data_Anonymization_Admin')) {
            throw new DataAnonymizationException(
                'Insufficient permissions. The Data_Anonymization_Admin custom permission is required.'
            );
        }
    }

    /**
     * @description Resolves and caches an IAnonymizationStrategy instance by class name.
     *              Uses Type.forName() for dynamic dispatch — zero hardcoded field-type logic here.
     */
    private IAnonymizationStrategy resolveStrategy(
        String className,
        Map<String, IAnonymizationStrategy> cache
    ) {
        if (cache.containsKey(className)) {
            return cache.get(className);
        }
        Type t = Type.forName(className);
        if (t == null) {
            throw new DataAnonymizationException(
                'Strategy class not found: "' + className + '". ' +
                'Ensure the class is deployed and the name in Strategy_Class_Name__c is correct.'
            );
        }
        IAnonymizationStrategy instance = (IAnonymizationStrategy) t.newInstance();
        cache.put(className, instance);
        return instance;
    }

    /**
     * @description Appends an error message to the rolling error buffer, respecting the max size.
     */
    private void appendError(String message) {
        if (errorBuffer.length() < MAX_ERROR_BUFFER) {
            errorBuffer += (errorBuffer.length() > 0 ? '\n' : '') + message;
        }
    }

    /**
     * @description Resolves an object API name from a config developer name.
     *              Used in finish() to find the next batch's log record.
     */
    private String resolveObjectApiName(String configDeveloperName) {
        List<Anon_Object_Config__mdt> cfgs = [
            SELECT Object_API_Name__c
            FROM   Anon_Object_Config__mdt
            WHERE  DeveloperName = :configDeveloperName
            LIMIT  1
        ];
        return cfgs.isEmpty() ? configDeveloperName : cfgs[0].Object_API_Name__c;
    }

    // ── Custom exception ──────────────────────────────────────────────────────

    public class DataAnonymizationException extends Exception {}
}
