/**
 * @description Batch Apex Stateful for CSV extraction with Governor Limits monitoring
 * Extracts Master and Child records based on uploaded IDs
 * Handles heap size monitoring and file splitting
 *
 * @author AI Assistant
 * @date 2025-12-10
 */
public class CSVExtractionBatch implements Database.Batchable<SObject>, Database.Stateful {

    // Configuration
    private String masterObjectName;
    private String childObjectName;
    private Set<String> masterIds;

    // State variables (Database.Stateful)
    private String masterCSV = '';
    private String childCSV = '';
    private Integer masterPartNumber = 1;
    private Integer childPartNumber = 1;
    private List<Id> masterContentVersionIds = new List<Id>();
    private List<Id> childContentVersionIds = new List<Id>();

    // Heap size thresholds (in bytes)
    private static final Integer MAX_HEAP_SIZE = 6000000; // 6MB (safe limit, max is ~6MB)
    private static final Integer FLUSH_THRESHOLD = 5000000; // 5MB - flush before reaching limit

    // CSV headers
    private Boolean masterHeaderWritten = false;
    private Boolean childHeaderWritten = false;

    // Child relationship field
    private String childLookupField;

    /**
     * Constructor
     */
    public CSVExtractionBatch(String masterObj, String childObj, Set<String> ids) {
        this.masterObjectName = masterObj;
        this.childObjectName = childObj;
        this.masterIds = ids;

        // Find the relationship field dynamically
        this.childLookupField = findRelationshipField(childObj, masterObj);

        System.debug('🔵 Batch initialized: Master=' + masterObj + ', Child=' + childObj + ', IDs=' + ids.size());
        System.debug('📍 Relationship field: ' + childLookupField);
    }

    /**
     * Start method - Query Master records
     */
    public Database.QueryLocator start(Database.BatchableContext bc) {
        // Build dynamic SOQL for Master object
        String query = buildDynamicQuery(masterObjectName, masterIds);
        System.debug('🔍 Query: ' + query);
        return Database.getQueryLocator(query);
    }

    /**
     * Execute method - Process Master records and related Child records
     */
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        System.debug('⚙️ Processing batch: ' + scope.size() + ' records');

        try {
            // Process Master records
            processMasterRecords(scope);

            // Extract Master IDs for Child query
            Set<Id> masterRecordIds = new Set<Id>();
            for (SObject record : scope) {
                masterRecordIds.add(record.Id);
            }

            // Process Child records
            if (String.isNotBlank(childLookupField)) {
                processChildRecords(masterRecordIds);
            }

        } catch (Exception e) {
            System.debug('❌ Error in execute: ' + e.getMessage());
            System.debug('❌ Stack trace: ' + e.getStackTraceString());
            throw e;
        }
    }

    /**
     * Finish method - Save final CSV files
     */
    public void finish(Database.BatchableContext bc) {
        System.debug('✅ Batch finished - saving final files');

        // Flush any remaining data
        if (String.isNotBlank(masterCSV)) {
            saveMasterCSVPart();
        }

        if (String.isNotBlank(childCSV)) {
            saveChildCSVPart();
        }

        System.debug('📦 Total Master files: ' + masterContentVersionIds.size());
        System.debug('📦 Total Child files: ' + childContentVersionIds.size());

        // TODO: Send email notification to user with file links
    }

    /**
     * Process Master records and build CSV
     */
    private void processMasterRecords(List<SObject> records) {
        if (records.isEmpty()) return;

        // Write header if first batch
        if (!masterHeaderWritten) {
            masterCSV = buildCSVHeader(records[0]) + '\n';
            masterHeaderWritten = true;
        }

        // Build CSV rows
        for (SObject record : records) {
            String row = buildCSVRow(record) + '\n';

            // Check heap size before adding
            if (checkHeapSize()) {
                saveMasterCSVPart();
            }

            masterCSV += row;
        }
    }

    /**
     * Process Child records and build CSV
     */
    private void processChildRecords(Set<Id> masterRecordIds) {
        if (masterRecordIds.isEmpty() || String.isBlank(childLookupField)) return;

        // Build dynamic query for Child records
        String childQuery = buildDynamicQuery(childObjectName, null);
        childQuery += ' WHERE ' + childLookupField + ' IN :masterRecordIds';

        System.debug('🔍 Child Query: ' + childQuery);

        List<SObject> childRecords = Database.query(childQuery);
        System.debug('📦 Found ' + childRecords.size() + ' child records');

        if (childRecords.isEmpty()) return;

        // Write header if first batch
        if (!childHeaderWritten) {
            childCSV = buildCSVHeader(childRecords[0]) + '\n';
            childHeaderWritten = true;
        }

        // Build CSV rows
        for (SObject record : childRecords) {
            String row = buildCSVRow(record) + '\n';

            // Check heap size before adding
            if (checkHeapSize()) {
                saveChildCSVPart();
            }

            childCSV += row;
        }
    }

    /**
     * Build dynamic SOQL query
     */
    private String buildDynamicQuery(String objectName, Set<String> ids) {
        // Get all fields for the object
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
            .get(objectName)
            .getDescribe()
            .fields
            .getMap();

        List<String> fieldNames = new List<String>();
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();

            // Skip non-accessible fields
            if (!fieldDescribe.isAccessible()) continue;

            // Skip compound fields (Address, Location, etc.)
            if (fieldDescribe.isCompound()) continue;

            fieldNames.add(fieldName);
        }

        String query = 'SELECT ' + String.join(fieldNames, ', ') + ' FROM ' + objectName;

        if (ids != null && !ids.isEmpty()) {
            query += ' WHERE DataMigrationId__c IN :masterIds';
        }

        return query;
    }

    /**
     * Find relationship field from Child to Master
     */
    private String findRelationshipField(String childObj, String masterObj) {
        Schema.DescribeSObjectResult childDescribe = Schema.getGlobalDescribe().get(childObj).getDescribe();

        for (Schema.SObjectField field : childDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

            // Check if it's a reference field (Lookup or Master-Detail)
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                // Get referenced object
                List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();

                for (Schema.SObjectType refType : references) {
                    if (refType.getDescribe().getName() == masterObj) {
                        System.debug('✅ Found relationship field: ' + fieldDescribe.getName());
                        return fieldDescribe.getName();
                    }
                }
            }
        }

        System.debug('⚠️ No relationship field found from ' + childObj + ' to ' + masterObj);
        return null;
    }

    /**
     * Build CSV header from SObject
     */
    private String buildCSVHeader(SObject record) {
        Map<String, Object> fieldsMap = record.getPopulatedFieldsAsMap();
        List<String> headers = new List<String>();

        for (String fieldName : fieldsMap.keySet()) {
            headers.add(escapeCSV(fieldName));
        }

        return String.join(headers, ',');
    }

    /**
     * Build CSV row from SObject
     */
    private String buildCSVRow(SObject record) {
        Map<String, Object> fieldsMap = record.getPopulatedFieldsAsMap();
        List<String> values = new List<String>();

        for (String fieldName : fieldsMap.keySet()) {
            Object value = record.get(fieldName);
            String stringValue = value != null ? String.valueOf(value) : '';
            values.add(escapeCSV(stringValue));
        }

        return String.join(values, ',');
    }

    /**
     * Escape CSV special characters
     */
    private String escapeCSV(String value) {
        if (String.isBlank(value)) return '';

        // Escape quotes and wrap in quotes if contains comma, quote, or newline
        if (value.contains(',') || value.contains('"') || value.contains('\n')) {
            value = '"' + value.replace('"', '""') + '"';
        }

        return value;
    }

    /**
     * Check current heap size
     */
    private Boolean checkHeapSize() {
        Integer currentHeap = Limits.getHeapSize();
        System.debug('📊 Current Heap Size: ' + currentHeap + ' bytes');

        return currentHeap > FLUSH_THRESHOLD;
    }

    /**
     * Save Master CSV part and clear memory
     */
    private void saveMasterCSVPart() {
        if (String.isBlank(masterCSV)) return;

        String fileName = masterObjectName + '_Part' + masterPartNumber + '.csv';
        Id contentVersionId = saveContentVersion(fileName, masterCSV);

        masterContentVersionIds.add(contentVersionId);
        masterPartNumber++;

        // Clear CSV but keep header
        String header = masterCSV.split('\n')[0];
        masterCSV = header + '\n';

        System.debug('💾 Saved Master CSV Part ' + (masterPartNumber - 1));
    }

    /**
     * Save Child CSV part and clear memory
     */
    private void saveChildCSVPart() {
        if (String.isBlank(childCSV)) return;

        String fileName = childObjectName + '_Part' + childPartNumber + '.csv';
        Id contentVersionId = saveContentVersion(fileName, childCSV);

        childContentVersionIds.add(contentVersionId);
        childPartNumber++;

        // Clear CSV but keep header
        String header = childCSV.split('\n')[0];
        childCSV = header + '\n';

        System.debug('💾 Saved Child CSV Part ' + (childPartNumber - 1));
    }

    /**
     * Save CSV as ContentVersion
     */
    private Id saveContentVersion(String fileName, String csvContent) {
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = Blob.valueOf(csvContent);
        cv.FirstPublishLocationId = UserInfo.getUserId(); // Save in user's files

        insert cv;

        System.debug('✅ Saved ContentVersion: ' + fileName + ' (ID: ' + cv.Id + ')');
        return cv.Id;
    }

    /**
     * Get all generated file IDs
     */
    public List<Id> getAllFileIds() {
        List<Id> allIds = new List<Id>();
        allIds.addAll(masterContentVersionIds);
        allIds.addAll(childContentVersionIds);
        return allIds;
    }
}
