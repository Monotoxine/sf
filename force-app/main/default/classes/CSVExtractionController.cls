/**
 * @description Controller for CSV Extraction LWC
 * Provides methods to launch batch and retrieve object metadata
 *
 * @author AI Assistant
 * @date 2025-12-10
 */
public with sharing class CSVExtractionController {

    /**
     * Get all extractable objects (custom objects with DataMigrationId__c)
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getExtractableObjects() {
        List<ObjectOption> options = new List<ObjectOption>();

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (String objectName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult describe = globalDescribe.get(objectName).getDescribe();

            // Filter: Custom objects only (or add specific standard objects)
            if (!describe.isCustom()) continue;

            // Check if object has DataMigrationId__c field
            if (!hasDataMigrationIdField(describe)) continue;

            ObjectOption option = new ObjectOption();
            option.label = describe.getLabel();
            option.value = describe.getName();
            option.apiName = describe.getName();

            options.add(option);
        }

        // Sort by label
        options.sort();

        System.debug('📋 Found ' + options.size() + ' extractable objects');
        return options;
    }

    /**
     * Get all objects (for child object selection)
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getAllObjects() {
        List<ObjectOption> options = new List<ObjectOption>();

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (String objectName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult describe = globalDescribe.get(objectName).getDescribe();

            // Filter: Custom objects only
            if (!describe.isCustom()) continue;

            ObjectOption option = new ObjectOption();
            option.label = describe.getLabel();
            option.value = describe.getName();
            option.apiName = describe.getName();

            options.add(option);
        }

        // Sort by label
        options.sort();

        return options;
    }

    /**
     * Validate relationship between Master and Child objects
     */
    @AuraEnabled
    public static RelationshipValidation validateRelationship(String masterObject, String childObject) {
        RelationshipValidation result = new RelationshipValidation();

        try {
            Schema.DescribeSObjectResult childDescribe = Schema.getGlobalDescribe()
                .get(childObject)
                .getDescribe();

            // Find relationship field
            for (Schema.SObjectField field : childDescribe.fields.getMap().values()) {
                Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

                // Check if it's a reference field
                if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                    List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();

                    for (Schema.SObjectType refType : references) {
                        if (refType.getDescribe().getName() == masterObject) {
                            result.hasRelationship = true;
                            result.relationshipField = fieldDescribe.getName();
                            result.relationshipLabel = fieldDescribe.getLabel();
                            result.relationshipType = fieldDescribe.getRelationshipOrder() == 0 ? 'Master-Detail' : 'Lookup';

                            System.debug('✅ Relationship found: ' + result.relationshipField);
                            return result;
                        }
                    }
                }
            }

            result.hasRelationship = false;
            result.message = 'No relationship found from ' + childObject + ' to ' + masterObject;

        } catch (Exception e) {
            result.hasRelationship = false;
            result.message = 'Error: ' + e.getMessage();
        }

        return result;
    }

    /**
     * Parse CSV file and extract IDs
     */
    @AuraEnabled
    public static ParseCSVResult parseCSVFile(String base64Data, String fileName) {
        ParseCSVResult result = new ParseCSVResult();

        try {
            // Decode base64
            Blob csvBlob = EncodingUtil.base64Decode(base64Data);
            String csvString = csvBlob.toString();

            // Parse CSV
            List<String> lines = csvString.split('\n');
            Set<String> ids = new Set<String>();

            for (String line : lines) {
                line = line.trim();

                // Skip empty lines
                if (String.isBlank(line)) continue;

                // Skip header if it doesn't look like an ID
                if (!line.contains('-') && !line.startsWith('a')) continue;

                // Clean and add ID
                String cleanId = line.replace('\r', '').replace('"', '').trim();
                if (String.isNotBlank(cleanId)) {
                    ids.add(cleanId);
                }
            }

            result.success = true;
            result.idCount = ids.size();
            result.ids = new List<String>(ids);
            result.message = 'Successfully parsed ' + ids.size() + ' IDs';

            System.debug('✅ Parsed CSV: ' + ids.size() + ' IDs');

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error parsing CSV: ' + e.getMessage();
            System.debug('❌ Error parsing CSV: ' + e.getMessage());
        }

        return result;
    }

    /**
     * Extract CSV directly (synchronous) - for smaller datasets
     * Recommended for < 5,000 records
     */
    @AuraEnabled
    public static CSVExtractionResult extractCSVDirect(
        String masterObject,
        String childObject,
        List<String> ids
    ) {
        CSVExtractionResult result = new CSVExtractionResult();

        try {
            // Validate inputs
            if (String.isBlank(masterObject)) {
                throw new AuraHandledException('Master Object is required');
            }

            if (ids == null || ids.isEmpty()) {
                throw new AuraHandledException('No IDs provided');
            }

            System.debug('🔵 Starting direct CSV extraction');
            System.debug('📍 Master: ' + masterObject + ', Child: ' + childObject + ', IDs: ' + ids.size());

            // Convert to Set
            Set<String> idSet = new Set<String>(ids);

            // Extract Master records
            String masterCSV = extractMasterRecords(masterObject, idSet);

            // Extract Child records (if child object specified)
            String childCSV = '';
            if (String.isNotBlank(childObject)) {
                childCSV = extractChildRecords(masterObject, childObject, idSet);
            }

            result.success = true;
            result.masterCSV = masterCSV;
            result.childCSV = childCSV;
            result.masterRecordCount = countLines(masterCSV) - 1; // Exclude header
            result.childRecordCount = String.isNotBlank(childCSV) ? countLines(childCSV) - 1 : 0;
            result.message = 'Extraction completed successfully';

            System.debug('✅ Extraction complete: ' + result.masterRecordCount + ' master, ' + result.childRecordCount + ' child');

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error extracting data: ' + e.getMessage();
            System.debug('❌ Error: ' + e.getMessage());
            System.debug('❌ Stack: ' + e.getStackTraceString());
        }

        return result;
    }

    /**
     * Extract Master records as CSV
     */
    private static String extractMasterRecords(String objectName, Set<String> ids) {
        // Build dynamic query
        String query = buildDynamicQuery(objectName);
        query += ' WHERE DataMigrationId__c IN :ids';
        query += ' ORDER BY DataMigrationId__c';

        System.debug('🔍 Master Query: ' + query);

        List<SObject> records = Database.query(query);
        System.debug('📦 Found ' + records.size() + ' master records');

        if (records.isEmpty()) {
            return '';
        }

        // Build CSV
        return buildCSV(records);
    }

    /**
     * Extract Child records as CSV
     */
    private static String extractChildRecords(String masterObject, String childObject, Set<String> masterIds) {
        // Find relationship field
        String relationshipField = findRelationshipField(childObject, masterObject);

        if (String.isBlank(relationshipField)) {
            System.debug('⚠️ No relationship field found');
            return '';
        }

        System.debug('📍 Relationship field: ' + relationshipField);

        // Get Master record IDs
        String masterQuery = 'SELECT Id FROM ' + masterObject + ' WHERE DataMigrationId__c IN :masterIds';
        List<SObject> masterRecords = Database.query(masterQuery);

        Set<Id> masterRecordIds = new Set<Id>();
        for (SObject record : masterRecords) {
            masterRecordIds.add(record.Id);
        }

        if (masterRecordIds.isEmpty()) {
            return '';
        }

        // Build child query
        String query = buildDynamicQuery(childObject);
        query += ' WHERE ' + relationshipField + ' IN :masterRecordIds';
        query += ' ORDER BY ' + relationshipField;

        System.debug('🔍 Child Query: ' + query);

        List<SObject> records = Database.query(query);
        System.debug('📦 Found ' + records.size() + ' child records');

        if (records.isEmpty()) {
            return '';
        }

        // Build CSV
        return buildCSV(records);
    }

    /**
     * Build dynamic SOQL query
     */
    private static String buildDynamicQuery(String objectName) {
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

            // Skip compound fields
            if (fieldDescribe.isCompound()) continue;

            fieldNames.add(fieldName);
        }

        return 'SELECT ' + String.join(fieldNames, ', ') + ' FROM ' + objectName;
    }

    /**
     * Find relationship field from Child to Master
     */
    private static String findRelationshipField(String childObj, String masterObj) {
        Schema.DescribeSObjectResult childDescribe = Schema.getGlobalDescribe()
            .get(childObj)
            .getDescribe();

        for (Schema.SObjectField field : childDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();

                for (Schema.SObjectType refType : references) {
                    if (refType.getDescribe().getName() == masterObj) {
                        return fieldDescribe.getName();
                    }
                }
            }
        }

        return null;
    }

    /**
     * Build CSV from SObject list
     */
    private static String buildCSV(List<SObject> records) {
        if (records.isEmpty()) return '';

        List<String> lines = new List<String>();

        // Build header
        Map<String, Object> firstRecordFields = records[0].getPopulatedFieldsAsMap();
        List<String> headers = new List<String>(firstRecordFields.keySet());
        lines.add(String.join(headers, ','));

        // Build rows
        for (SObject record : records) {
            List<String> values = new List<String>();

            for (String fieldName : headers) {
                Object value = record.get(fieldName);
                String stringValue = value != null ? String.valueOf(value) : '';
                values.add(escapeCSV(stringValue));
            }

            lines.add(String.join(values, ','));
        }

        return String.join(lines, '\n');
    }

    /**
     * Escape CSV special characters
     */
    private static String escapeCSV(String value) {
        if (String.isBlank(value)) return '';

        // Escape quotes and wrap if contains comma, quote, or newline
        if (value.contains(',') || value.contains('"') || value.contains('\n')) {
            value = '"' + value.replace('"', '""') + '"';
        }

        return value;
    }

    /**
     * Count lines in CSV
     */
    private static Integer countLines(String csv) {
        if (String.isBlank(csv)) return 0;
        return csv.split('\n').size();
    }

    /**
     * Get batch job status
     */
    @AuraEnabled
    public static BatchJobStatus getBatchJobStatus(String batchJobId) {
        BatchJobStatus status = new BatchJobStatus();

        try {
            AsyncApexJob job = [
                SELECT Id, Status, NumberOfErrors, JobItemsProcessed, TotalJobItems,
                       CreatedDate, CompletedDate, ExtendedStatus
                FROM AsyncApexJob
                WHERE Id = :batchJobId
                LIMIT 1
            ];

            status.status = job.Status;
            status.jobItemsProcessed = job.JobItemsProcessed;
            status.totalJobItems = job.TotalJobItems;
            status.numberOfErrors = job.NumberOfErrors;
            status.isCompleted = (job.Status == 'Completed');
            status.isFailed = (job.Status == 'Failed' || job.Status == 'Aborted');
            status.extendedStatus = job.ExtendedStatus;

            // Calculate progress percentage
            if (job.TotalJobItems > 0) {
                status.progressPercentage = (Integer)((job.JobItemsProcessed * 100) / job.TotalJobItems);
            }

        } catch (Exception e) {
            status.status = 'Error';
            status.extendedStatus = e.getMessage();
        }

        return status;
    }

    /**
     * Check if object has DataMigrationId__c field
     */
    private static Boolean hasDataMigrationIdField(Schema.DescribeSObjectResult describe) {
        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
        return fieldMap.containsKey('datamigrationid__c');
    }

    // ==================== DTOs ====================

    /**
     * Object option for picklists
     */
    public class ObjectOption implements Comparable {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        @AuraEnabled public String apiName;

        public Integer compareTo(Object other) {
            ObjectOption otherOption = (ObjectOption)other;
            return this.label.compareTo(otherOption.label);
        }
    }

    /**
     * Relationship validation result
     */
    public class RelationshipValidation {
        @AuraEnabled public Boolean hasRelationship;
        @AuraEnabled public String relationshipField;
        @AuraEnabled public String relationshipLabel;
        @AuraEnabled public String relationshipType;
        @AuraEnabled public String message;
    }

    /**
     * CSV parse result
     */
    public class ParseCSVResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Integer idCount;
        @AuraEnabled public List<String> ids;
        @AuraEnabled public String message;
    }

    /**
     * CSV extraction result (direct download)
     */
    public class CSVExtractionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String masterCSV;
        @AuraEnabled public String childCSV;
        @AuraEnabled public Integer masterRecordCount;
        @AuraEnabled public Integer childRecordCount;
        @AuraEnabled public String message;
    }

    /**
     * Batch launch result
     */
    public class BatchLaunchResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String batchJobId;
        @AuraEnabled public String message;
    }

    /**
     * Batch job status
     */
    public class BatchJobStatus {
        @AuraEnabled public String status;
        @AuraEnabled public Integer jobItemsProcessed;
        @AuraEnabled public Integer totalJobItems;
        @AuraEnabled public Integer numberOfErrors;
        @AuraEnabled public Boolean isCompleted;
        @AuraEnabled public Boolean isFailed;
        @AuraEnabled public String extendedStatus;
        @AuraEnabled public Integer progressPercentage;
    }
}
