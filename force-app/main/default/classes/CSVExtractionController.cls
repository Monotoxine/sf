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
     * Get child objects that have a relationship to the given parent object
     */
    @AuraEnabled(cacheable=true)
    public static List<ChildObjectInfo> getChildObjects(String parentObjectName) {
        List<ChildObjectInfo> childObjects = new List<ChildObjectInfo>();

        try {
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

            // Loop through all objects to find those with relationships to parent
            for (String objectName : globalDescribe.keySet()) {
                Schema.DescribeSObjectResult childDescribe = globalDescribe.get(objectName).getDescribe();

                // Skip if not custom object
                if (!childDescribe.isCustom()) continue;

                // Check all fields for reference to parent
                for (Schema.SObjectField field : childDescribe.fields.getMap().values()) {
                    Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

                    // Check if it's a reference field
                    if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                        List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();

                        for (Schema.SObjectType refType : references) {
                            if (refType.getDescribe().getName() == parentObjectName) {
                                ChildObjectInfo childInfo = new ChildObjectInfo();
                                childInfo.objectName = childDescribe.getName();
                                childInfo.objectLabel = childDescribe.getLabel();
                                childInfo.relationshipField = fieldDescribe.getName();
                                childInfo.relationshipLabel = fieldDescribe.getLabel();
                                childInfo.relationshipType = fieldDescribe.getRelationshipOrder() == 0 ?
                                    'Master-Detail' : 'Lookup';

                                childObjects.add(childInfo);
                                break; // Only add each child object once
                            }
                        }
                    }
                }
            }

            System.debug('📋 Found ' + childObjects.size() + ' child objects for ' + parentObjectName);

        } catch (Exception e) {
            System.debug('❌ Error getting child objects: ' + e.getMessage());
        }

        return childObjects;
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

    @AuraEnabled
    public static ParseCSVResult parseCSVFile(String base64Data, String fileName) {
        ParseCSVResult result = new ParseCSVResult();
        try {
            String csvString = EncodingUtil.base64Decode(base64Data).toString();
            
            // Split by line, handling both Windows (\r\n) and Unix (\n)
            List<String> lines = csvString.split('\\r?\\n');
            
            if (lines.isEmpty()) {
                throw new AuraHandledException('The file is empty.');
            }

            // Identify the column index for the DataMigrationId
            List<String> headers = lines[0].split(',');
            Integer idColIndex = -1;
            String headerName = 'TEKCO_DataMigrationId__c'; // Define expected header

            for (Integer i = 0; i < headers.size(); i++) {
                // Remove quotes and trim header to ensure exact match
                String cleanHeader = headers[i].replace('"', '').trim(); 
                if (cleanHeader.equalsIgnoreCase(headerName)) {
                    idColIndex = i;
                    break;
                }
            }

            if (idColIndex == -1) {
                result.success = false;
                result.message = 'Error: Column "TEKCO_DataMigrationId__c" not found in CSV header.';
                return result;
            }

            Set<String> ids = new Set<String>();
            
            // Start from index 1 to skip header
            for (Integer i = 1; i < lines.size(); i++) {
                String currentLine = lines[i];

                // FIX 1: Skip completely empty lines or lines with only whitespace
                if (String.isBlank(currentLine)) continue;

                List<String> columns = currentLine.split(',');
                
                if (columns.size() > idColIndex) {
                    String val = columns[idColIndex].replace('"', '').trim();
                    
                    // FIX 2: Enhanced Validation
                    // Ensure value is not blank AND is not the header name repeated
                    if (String.isNotBlank(val) && !val.equalsIgnoreCase(headerName)) {
                        ids.add(val);
                        // FIX 3: Debug to see exactly what IDs are being found
                        System.debug('✅ Found ID: [' + val + ']'); 
                    }
                }
            }

            result.success = true;
            result.idCount = ids.size();
            result.ids = new List<String>(ids);
            result.message = 'Successfully parsed ' + ids.size() + ' Data Migration IDs.';
            
            // Debugging output
            System.debug('Total IDs found: ' + ids.size());
            System.debug('IDs: ' + ids);
            
        } catch (Exception e) {
            result.success = false;
            result.message = 'Parsing Error: ' + e.getMessage();
        }
        return result;
    }

    /**
     * Detect Salesforce object type from a Record ID
     */
    private static String detectObjectFromId(String recordId) {
        try {
            if (String.isBlank(recordId) || recordId.length() < 15) {
                return null;
            }

            // Get key prefix (first 3 characters)
            String keyPrefix = recordId.substring(0, 3);

            // Search through all objects to find matching key prefix
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

            for (String objectName : globalDescribe.keySet()) {
                Schema.DescribeSObjectResult describe = globalDescribe.get(objectName).getDescribe();

                if (describe.getKeyPrefix() == keyPrefix) {
                    System.debug('🔍 Detected object: ' + objectName + ' from ID prefix: ' + keyPrefix);
                    return describe.getName();
                }
            }

            System.debug('⚠️ No object found for ID prefix: ' + keyPrefix);
            return null;

        } catch (Exception e) {
            System.debug('❌ Error detecting object from ID: ' + e.getMessage());
            return null;
        }
    }

    /**
     * Extract CSV directly (synchronous) - for smaller datasets
     * Recommended for < 5,000 records
     * Supports multi-level child extraction
     */
    @AuraEnabled
    public static CSVExtractionResult extractCSVDirect(
        String masterObject,
        List<String> ids,
        List<ChildExtractionConfig> childConfigs
    ) {
        CSVExtractionResult result = new CSVExtractionResult();

        try {
            // FIX 1: Do not throw Exceptions for validation, return the result object
            if (String.isBlank(masterObject)) {
                result.success = false;
                result.message = 'Master Object is required';
                return result;
            }

            if (ids == null || ids.isEmpty()) {
                result.success = false;
                result.message = 'No IDs provided';
                return result;
            }

            System.debug('🔵 Starting direct CSV extraction for: ' + masterObject);

            Set<String> idSet = new Set<String>(ids);

            // Extract Master records
            String masterCSV = extractMasterRecords(masterObject, idSet);
            result.masterRecordCount = countLines(masterCSV) - 1; 

            result.csvFiles = new List<CSVFileResult>();

            CSVFileResult masterFile = new CSVFileResult();
            masterFile.objectName = masterObject;
            masterFile.csvContent = masterCSV;
            masterFile.recordCount = result.masterRecordCount;
            masterFile.level = 0;
            result.csvFiles.add(masterFile);

            if (childConfigs != null && !childConfigs.isEmpty()) {
                extractChildRecordsRecursively(masterObject, idSet, childConfigs, result.csvFiles, 1);
            }

            result.success = true;
            result.message = 'Extraction completed successfully';

        } catch (Exception e) {
            result.success = false;
            // FIX 2: Include Stack Trace to find the real error location
            result.message = 'Error extracting data: ' + e.getMessage() + ' (Line: ' + e.getLineNumber() + ')';
            System.debug('❌ Error: ' + e.getMessage());
            System.debug('❌ Stack: ' + e.getStackTraceString());
        }

        return result;
    }
    
    /**
     * Extract child records recursively
     */
    private static void extractChildRecordsRecursively(
        String parentObject,
        Set<String> parentIds,
        List<ChildExtractionConfig> childConfigs,
        List<CSVFileResult> results,
        Integer level
    ) {
        // Get parent record IDs (not DataMigration IDs)
        String parentQuery = 'SELECT Id FROM ' + parentObject + ' WHERE TEKCO_DataMigrationId__c IN :parentIds';
        List<SObject> parentRecords = Database.query(parentQuery);

        Set<Id> parentRecordIds = new Set<Id>();
        for (SObject record : parentRecords) {
            parentRecordIds.add(record.Id);
        }

        if (parentRecordIds.isEmpty()) return;

        // Extract each child object
        for (ChildExtractionConfig config : childConfigs) {
            try {
                // Extract child records
                String childCSV = extractChildRecordsByRelationship(
                    config.childObject,
                    config.relationshipField,
                    parentRecordIds
                );

                if (String.isNotBlank(childCSV)) {
                    CSVFileResult childFile = new CSVFileResult();
                    childFile.objectName = config.childObject;
                    childFile.csvContent = childCSV;
                    childFile.recordCount = countLines(childCSV) - 1;
                    childFile.level = level;
                    childFile.parentObject = parentObject;
                    results.add(childFile);

                    System.debug('✅ Extracted ' + childFile.recordCount + ' records from ' + config.childObject);

                    // Recursively extract grandchildren if configured
                    if (config.children != null && !config.children.isEmpty()) {
                        // Get child record DataMigration IDs for recursive extraction
                        Set<String> childDataMigrationIds = extractDataMigrationIds(childCSV);

                        if (!childDataMigrationIds.isEmpty()) {
                            extractChildRecordsRecursively(
                                config.childObject,
                                childDataMigrationIds,
                                config.children,
                                results,
                                level + 1
                            );
                        }
                    }
                }

            } catch (Exception e) {
                System.debug('❌ Error extracting child ' + config.childObject + ': ' + e.getMessage());
            }
        }
    }

    /**
     * Extract child records by relationship field
     */
    private static String extractChildRecordsByRelationship(
        String childObject,
        String relationshipField,
        Set<Id> parentRecordIds
    ) {
        // Build child query
        String query = buildDynamicQuery(childObject);
        query += ' WHERE ' + relationshipField + ' IN :parentRecordIds';
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
     * Extract DataMigration IDs from CSV content
     */
    private static Set<String> extractDataMigrationIds(String csvContent) {
        Set<String> ids = new Set<String>();

        try {
            List<String> lines = csvContent.split('\n');

            // Skip header
            if (lines.size() <= 1) return ids;

            // Get header to find DataMigrationId column index
            List<String> headers = lines[0].split(',');
            Integer idColumnIndex = -1;

            for (Integer i = 0; i < headers.size(); i++) {
                if (headers[i].toLowerCase().contains('datamigrationid')) {
                    idColumnIndex = i;
                    break;
                }
            }

            if (idColumnIndex < 0) return ids;

            // Extract IDs from data rows
            for (Integer i = 1; i < lines.size(); i++) {
                List<String> values = lines[i].split(',');
                if (values.size() > idColumnIndex) {
                    String idValue = values[idColumnIndex].trim();
                    if (String.isNotBlank(idValue)) {
                        ids.add(idValue);
                    }
                }
            }

        } catch (Exception e) {
            System.debug('❌ Error extracting DataMigration IDs from CSV: ' + e.getMessage());
        }

        return ids;
    }

    /**
     * Extract Master records as CSV
     */
    private static String extractMasterRecords(String objectName, Set<String> ids) {
        // Build dynamic query
        String query = buildDynamicQuery(objectName);
        query += ' WHERE TEKCO_DataMigrationId__c IN :ids';
        query += ' ORDER BY TEKCO_DataMigrationId__c';

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
            Schema.DisplayType fieldType = fieldDescribe.getType();
            if (fieldType == Schema.DisplayType.ADDRESS || fieldType == Schema.DisplayType.LOCATION) {
                continue;
            }

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
        return fieldMap.containsKey('TEKCO_DataMigrationId__c');
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
     * Child object information with relationship details
     */
    public class ChildObjectInfo {
        @AuraEnabled public String objectName;
        @AuraEnabled public String objectLabel;
        @AuraEnabled public String relationshipField;
        @AuraEnabled public String relationshipLabel;
        @AuraEnabled public String relationshipType;
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
        @AuraEnabled public String detectedObject;
        @AuraEnabled public String detectedObjectLabel;
        @AuraEnabled public String message;
    }

    /**
     * CSV extraction result (direct download with multi-level support)
     */
    public class CSVExtractionResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public List<CSVFileResult> csvFiles;
        @AuraEnabled public Integer masterRecordCount;
        @AuraEnabled public String message;
    }

    /**
     * Individual CSV file result
     */
    public class CSVFileResult {
        @AuraEnabled public String objectName;
        @AuraEnabled public String csvContent;
        @AuraEnabled public Integer recordCount;
        @AuraEnabled public Integer level; // 0 = master, 1 = child, 2 = grandchild, etc.
        @AuraEnabled public String parentObject;
    }

    /**
     * Child extraction configuration
     */
    public class ChildExtractionConfig {
        @AuraEnabled public String childObject;
        @AuraEnabled public String relationshipField;
        @AuraEnabled public List<ChildExtractionConfig> children; // For nested children
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
