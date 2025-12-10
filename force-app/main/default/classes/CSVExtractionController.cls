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
     * Launch extraction batch
     */
    @AuraEnabled
    public static BatchLaunchResult launchExtractionBatch(
        String masterObject,
        String childObject,
        List<String> ids
    ) {
        BatchLaunchResult result = new BatchLaunchResult();

        try {
            // Validate inputs
            if (String.isBlank(masterObject)) {
                throw new AuraHandledException('Master Object is required');
            }

            if (ids == null || ids.isEmpty()) {
                throw new AuraHandledException('No IDs provided');
            }

            // Convert to Set
            Set<String> idSet = new Set<String>(ids);

            // Launch batch
            CSVExtractionBatch batch = new CSVExtractionBatch(masterObject, childObject, idSet);

            // Batch size: Start small to avoid heap issues
            Id batchJobId = Database.executeBatch(batch, 200);

            result.success = true;
            result.batchJobId = batchJobId;
            result.message = 'Batch job launched successfully';

            System.debug('✅ Batch launched: ' + batchJobId);

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error launching batch: ' + e.getMessage();
            System.debug('❌ Error launching batch: ' + e.getMessage());
        }

        return result;
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
