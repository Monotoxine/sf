/**
 * @description LWC controller for the Data Anonymization Manager component.
 *
 * Exposes AuraEnabled methods for:
 *   - Checking sandbox status and user permissions (called on component load)
 *   - Fetching object and field configurations from metadata
 *   - Fetching available brand/subsidiary filter values
 *   - Previewing the scope (record counts) before executing
 *   - Launching the anonymization job
 *   - Polling recent audit log entries
 *
 * ─── SECURITY ─────────────────────────────────────────────────────────────────
 *  Every mutating method (launchAnonymization, previewAnonymization) calls
 *  both assertSandbox() and assertPermission() as server-side guards,
 *  independent of any LWC-side checks.
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public with sharing class DataAnonymizationController {

    // ── Guard methods ──────────────────────────────────────────────────────────

    private static void assertSandbox() {
        Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
        if (!org.IsSandbox) {
            throw new AuraHandledException(
                '⛔ PRODUCTION ORG DETECTED. Anonymization is strictly forbidden on production orgs. ' +
                'No action has been taken.'
            );
        }
    }

    private static void assertPermission() {
        if (!FeatureManagement.checkPermission('Data_Anonymization_Admin')) {
            throw new AuraHandledException(
                'Insufficient permissions. The Data_Anonymization_Admin custom permission is required.'
            );
        }
    }

    // ── Environment info (called on page load, no guards needed) ──────────────

    /**
     * @description Returns true if the current org is a sandbox/scratch org.
     *              Called by the LWC on init to display an environment warning banner.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean isSandbox() {
        return [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
    }

    /**
     * @description Returns true if the running user has the Data_Anonymization_Admin
     *              custom permission. LWC uses this to show/hide the UI entirely.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean hasPermission() {
        return FeatureManagement.checkPermission('Data_Anonymization_Admin');
    }

    // ── Metadata loaders ──────────────────────────────────────────────────────

    /**
     * @description Returns all active object configs, ordered by Execution_Order__c.
     *              Used to populate the Object multi-select in the LWC filter panel.
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectConfigWrapper> getObjectConfigs() {
        List<ObjectConfigWrapper> result = new List<ObjectConfigWrapper>();
        for (Anon_Object_Config__mdt cfg : [
            SELECT DeveloperName, Label, Object_API_Name__c, Object_Label__c,
                   Brand_Field_API_Name__c, Is_Brand_Source__c, Execution_Order__c
            FROM   Anon_Object_Config__mdt
            WHERE  Is_Active__c = true
            ORDER BY Execution_Order__c NULLS LAST, Label
        ]) {
            result.add(new ObjectConfigWrapper(cfg));
        }
        return result;
    }

    /**
     * @description Returns active field configs for the given object config developer names.
     *              Used to populate the Field multi-select after the user picks objects.
     * @param  objectConfigNames  List of Anon_Object_Config__mdt DeveloperNames.
     */
    @AuraEnabled(cacheable=true)
    public static List<FieldConfigWrapper> getFieldConfigs(List<String> objectConfigNames) {
        if (objectConfigNames == null || objectConfigNames.isEmpty()) {
            return new List<FieldConfigWrapper>();
        }
        List<FieldConfigWrapper> result = new List<FieldConfigWrapper>();
        for (Anon_Field_Config__mdt fc : [
            SELECT DeveloperName, Label, Object_Config_Name__c, Field_API_Name__c,
                   Field_Label__c, Field_Type__c, Strategy_Class_Name__c,
                   Strategy_Param_1__c, Strategy_Param_2__c, Execution_Order__c
            FROM   Anon_Field_Config__mdt
            WHERE  Object_Config_Name__c IN :objectConfigNames
            AND    Is_Active__c          = true
            ORDER BY Object_Config_Name__c, Execution_Order__c NULLS LAST, Field_API_Name__c
        ]) {
            result.add(new FieldConfigWrapper(fc));
        }
        return result;
    }

    /**
     * @description Returns distinct brand/subsidiary values from the object flagged as
     *              Is_Brand_Source__c = true, using its Brand_Field_API_Name__c field.
     *              Returns an empty list if no brand source is configured.
     */
    @AuraEnabled(cacheable=false)
    public static List<String> getBrandValues() {
        List<Anon_Object_Config__mdt> sources = [
            SELECT Object_API_Name__c, Brand_Field_API_Name__c
            FROM   Anon_Object_Config__mdt
            WHERE  Is_Brand_Source__c = true
            AND    Is_Active__c       = true
            LIMIT  1
        ];
        if (sources.isEmpty() || String.isBlank(sources[0].Brand_Field_API_Name__c)) {
            return new List<String>();
        }

        String objName        = sources[0].Object_API_Name__c;
        String brandFieldName = sources[0].Brand_Field_API_Name__c;

        String soql = 'SELECT ' + brandFieldName
                    + ' FROM ' + objName
                    + ' WHERE ' + brandFieldName + ' != null'
                    + ' GROUP BY ' + brandFieldName
                    + ' ORDER BY ' + brandFieldName
                    + ' LIMIT 200';

        List<String> brands = new List<String>();
        for (AggregateResult ar : Database.query(soql)) {
            Object val = ar.get(brandFieldName);
            if (val != null) {
                brands.add(String.valueOf(val));
            }
        }
        return brands;
    }

    // ── Preview ────────────────────────────────────────────────────────────────

    /**
     * @description Counts how many records would be affected for each selected object config,
     *              applying the brand filter if provided. No DML — read-only.
     * @param  objectConfigNames  List of Anon_Object_Config__mdt DeveloperNames to preview.
     * @param  brandFilter        Optional brand value to filter on.
     * @return                    List of preview entries, one per object config.
     */
    @AuraEnabled(cacheable=false)
    public static List<PreviewEntry> previewAnonymization(
        List<String> objectConfigNames,
        String       brandFilter
    ) {
        assertSandbox();
        assertPermission();

        if (objectConfigNames == null || objectConfigNames.isEmpty()) {
            return new List<PreviewEntry>();
        }

        // Load object configs
        Map<String, Anon_Object_Config__mdt> cfgMap = new Map<String, Anon_Object_Config__mdt>();
        for (Anon_Object_Config__mdt cfg : [
            SELECT DeveloperName, Object_API_Name__c, Object_Label__c,
                   Brand_Field_API_Name__c
            FROM   Anon_Object_Config__mdt
            WHERE  DeveloperName IN :objectConfigNames
            AND    Is_Active__c  = true
        ]) {
            cfgMap.put(cfg.DeveloperName, cfg);
        }

        // Load field counts per object
        Map<String, Integer> fieldCountMap = new Map<String, Integer>();
        for (Anon_Field_Config__mdt fc : [
            SELECT Object_Config_Name__c, COUNT(Id) fieldCount
            FROM   Anon_Field_Config__mdt
            WHERE  Object_Config_Name__c IN :objectConfigNames
            AND    Is_Active__c          = true
            GROUP BY Object_Config_Name__c
        ]) {
            fieldCountMap.put(fc.Object_Config_Name__c, (Integer)fc.get('fieldCount'));
        }

        List<PreviewEntry> entries = new List<PreviewEntry>();
        for (String configName : objectConfigNames) {
            Anon_Object_Config__mdt cfg = cfgMap.get(configName);
            if (cfg == null) {
                continue;
            }

            Long recordCount = countRecords(cfg, brandFilter);
            PreviewEntry entry = new PreviewEntry();
            entry.objectConfigName = configName;
            entry.objectApiName    = cfg.Object_API_Name__c;
            entry.objectLabel      = String.isNotBlank(cfg.Object_Label__c)
                                     ? cfg.Object_Label__c
                                     : cfg.Object_API_Name__c;
            entry.recordCount      = recordCount;
            entry.fieldCount       = fieldCountMap.containsKey(configName)
                                     ? fieldCountMap.get(configName)
                                     : 0;
            entries.add(entry);
        }
        return entries;
    }

    // ── Launch ─────────────────────────────────────────────────────────────────

    /**
     * @description Launches the anonymization batch chain for the selected objects.
     *              Creates one Anon_Run_Log__c record per object before starting
     *              the first batch, so all log entries pre-exist when chaining.
     *
     * @param  objectConfigNames  Ordered list of Anon_Object_Config__mdt DeveloperNames.
     * @param  brandFilter        Optional brand filter. Null = all records.
     * @return                    Run Group ID (UUID) to poll progress against.
     */
    @AuraEnabled(cacheable=false)
    public static String launchAnonymization(
        List<String> objectConfigNames,
        String       brandFilter
    ) {
        assertSandbox();
        assertPermission();

        if (objectConfigNames == null || objectConfigNames.isEmpty()) {
            throw new AuraHandledException('No objects selected for anonymization.');
        }

        // Generate a UUID-style run group ID
        String runGroupId = generateRunGroupId();

        // Load object configs to get API names for log records
        Map<String, Anon_Object_Config__mdt> cfgMap = new Map<String, Anon_Object_Config__mdt>();
        for (Anon_Object_Config__mdt cfg : [
            SELECT DeveloperName, Object_API_Name__c
            FROM   Anon_Object_Config__mdt
            WHERE  DeveloperName IN :objectConfigNames
            AND    Is_Active__c  = true
        ]) {
            cfgMap.put(cfg.DeveloperName, cfg);
        }

        // Load field names per object for the log
        Map<String, List<String>> fieldsPerConfig = new Map<String, List<String>>();
        for (Anon_Field_Config__mdt fc : [
            SELECT Object_Config_Name__c, Field_API_Name__c
            FROM   Anon_Field_Config__mdt
            WHERE  Object_Config_Name__c IN :objectConfigNames
            AND    Is_Active__c          = true
            ORDER BY Execution_Order__c NULLS LAST
        ]) {
            if (!fieldsPerConfig.containsKey(fc.Object_Config_Name__c)) {
                fieldsPerConfig.put(fc.Object_Config_Name__c, new List<String>());
            }
            fieldsPerConfig.get(fc.Object_Config_Name__c).add(fc.Field_API_Name__c);
        }

        // Pre-create all log records in a single DML
        List<Anon_Run_Log__c> logs = new List<Anon_Run_Log__c>();
        for (String configName : objectConfigNames) {
            Anon_Object_Config__mdt cfg = cfgMap.get(configName);
            if (cfg == null) {
                continue;
            }
            List<String> fields = fieldsPerConfig.containsKey(configName)
                ? fieldsPerConfig.get(configName)
                : new List<String>();

            logs.add(new Anon_Run_Log__c(
                Run_Group_ID__c      = runGroupId,
                Triggered_By__c      = UserInfo.getUserId(),
                Run_Date__c          = Datetime.now(),
                Object_API_Name__c   = cfg.Object_API_Name__c,
                Fields_Processed__c  = JSON.serialize(fields),
                Brand_Filter__c      = brandFilter,
                Status__c            = 'In Progress',
                Records_Processed__c = 0,
                Records_Failed__c    = 0
            ));
        }
        insert logs;

        // Build a map: configName → logId (preserve order via objectConfigNames)
        Map<String, Id> logIdByConfig = new Map<String, Id>();
        for (Integer i = 0; i < objectConfigNames.size(); i++) {
            if (i < logs.size()) {
                logIdByConfig.put(objectConfigNames[i], logs[i].Id);
            }
        }

        // Launch first batch; it will chain the rest via finish()
        String firstConfigName = objectConfigNames[0];
        List<String> remaining = objectConfigNames.size() > 1
            ? objectConfigNames.subList(1, objectConfigNames.size())
            : new List<String>();

        Database.executeBatch(
            new DataAnonymizationBatch(
                firstConfigName,
                remaining,
                brandFilter,
                runGroupId,
                logIdByConfig.get(firstConfigName)
            ),
            200 // initial batch size; each batch reads its own configured size
        );

        return runGroupId;
    }

    // ── Audit log polling ──────────────────────────────────────────────────────

    /**
     * @description Returns the 50 most recent anonymization run log entries.
     *              Used by the LWC to show run history and poll current job status.
     */
    @AuraEnabled(cacheable=false)
    public static List<Anon_Run_Log__c> getRecentRuns() {
        assertPermission();
        return [
            SELECT Id, Name, Run_Group_ID__c, Object_API_Name__c, Status__c,
                   Records_Processed__c, Records_Failed__c, Run_Date__c,
                   Completion_Date__c, Brand_Filter__c, Batch_Job_ID__c,
                   Triggered_By__r.Name, Fields_Processed__c
            FROM   Anon_Run_Log__c
            ORDER BY Run_Date__c DESC
            LIMIT  50
        ];
    }

    /**
     * @description Returns log entries for a specific run group ID.
     *              Used by the LWC to poll status of a just-launched run.
     */
    @AuraEnabled(cacheable=false)
    public static List<Anon_Run_Log__c> getRunsByGroupId(String runGroupId) {
        assertPermission();
        return [
            SELECT Id, Name, Object_API_Name__c, Status__c,
                   Records_Processed__c, Records_Failed__c, Run_Date__c,
                   Completion_Date__c, Batch_Job_ID__c, Error_Details__c
            FROM   Anon_Run_Log__c
            WHERE  Run_Group_ID__c = :runGroupId
            ORDER BY Run_Date__c ASC
        ];
    }

    // ── Private helpers ────────────────────────────────────────────────────────

    private static Long countRecords(Anon_Object_Config__mdt cfg, String brandFilter) {
        String soql = 'SELECT COUNT() FROM ' + cfg.Object_API_Name__c;
        if (String.isNotBlank(brandFilter) && String.isNotBlank(cfg.Brand_Field_API_Name__c)) {
            soql += ' WHERE ' + cfg.Brand_Field_API_Name__c
                  + ' = \'' + String.escapeSingleQuotes(brandFilter) + '\'';
        }
        try {
            return Database.countQuery(soql);
        } catch (Exception e) {
            return -1; // signals "could not count"
        }
    }

    /** Generates a pseudo-UUID using Crypto.getRandomLong() for uniqueness. */
    private static String generateRunGroupId() {
        String h1 = EncodingUtil.convertToHex(Crypto.generateAESKey(128)).substring(0, 8);
        String h2 = EncodingUtil.convertToHex(Crypto.generateAESKey(128)).substring(0, 4);
        String h3 = EncodingUtil.convertToHex(Crypto.generateAESKey(128)).substring(0, 4);
        String h4 = EncodingUtil.convertToHex(Crypto.generateAESKey(128)).substring(0, 4);
        String h5 = EncodingUtil.convertToHex(Crypto.generateAESKey(128)).substring(0, 12);
        return h1 + '-' + h2 + '-' + h3 + '-' + h4 + '-' + h5;
    }

    // ── Wrapper DTOs ───────────────────────────────────────────────────────────

    public class ObjectConfigWrapper {
        @AuraEnabled public String  developerName;
        @AuraEnabled public String  label;
        @AuraEnabled public String  objectApiName;
        @AuraEnabled public String  objectLabel;
        @AuraEnabled public String  brandFieldApiName;
        @AuraEnabled public Boolean isBrandSource;
        @AuraEnabled public Integer executionOrder;

        public ObjectConfigWrapper(Anon_Object_Config__mdt cfg) {
            this.developerName    = cfg.DeveloperName;
            this.label            = cfg.Label;
            this.objectApiName    = cfg.Object_API_Name__c;
            this.objectLabel      = String.isNotBlank(cfg.Object_Label__c)
                                    ? cfg.Object_Label__c
                                    : cfg.Object_API_Name__c;
            this.brandFieldApiName = cfg.Brand_Field_API_Name__c;
            this.isBrandSource    = cfg.Is_Brand_Source__c;
            this.executionOrder   = cfg.Execution_Order__c != null
                                    ? (Integer)cfg.Execution_Order__c : 99;
        }
    }

    public class FieldConfigWrapper {
        @AuraEnabled public String  developerName;
        @AuraEnabled public String  objectConfigName;
        @AuraEnabled public String  fieldApiName;
        @AuraEnabled public String  fieldLabel;
        @AuraEnabled public String  fieldType;
        @AuraEnabled public String  strategyClassName;
        @AuraEnabled public String  strategyParam1;
        @AuraEnabled public String  strategyParam2;
        @AuraEnabled public Integer executionOrder;

        public FieldConfigWrapper(Anon_Field_Config__mdt fc) {
            this.developerName    = fc.DeveloperName;
            this.objectConfigName = fc.Object_Config_Name__c;
            this.fieldApiName     = fc.Field_API_Name__c;
            this.fieldLabel       = String.isNotBlank(fc.Field_Label__c)
                                    ? fc.Field_Label__c
                                    : fc.Field_API_Name__c;
            this.fieldType        = fc.Field_Type__c;
            this.strategyClassName = fc.Strategy_Class_Name__c;
            this.strategyParam1   = fc.Strategy_Param_1__c;
            this.strategyParam2   = fc.Strategy_Param_2__c;
            this.executionOrder   = fc.Execution_Order__c != null
                                    ? (Integer)fc.Execution_Order__c : 99;
        }
    }

    public class PreviewEntry {
        @AuraEnabled public String objectConfigName;
        @AuraEnabled public String objectApiName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public Long   recordCount;
        @AuraEnabled public Integer fieldCount;
    }
}
