/**
 * @description Controller for CSV Migration Cloner LWC
 * Provides methods to detect relationships and clone records with suffix
 *
 * @author AI Assistant
 * @date 2026-01-12
 */
public with sharing class CSVMigrationClonerController {

    /**
     * Get all extractable objects (custom objects with DataMigrationId__c)
     */
    @AuraEnabled(cacheable=true)
    public static List<ObjectOption> getExtractableObjects() {
        List<ObjectOption> options = new List<ObjectOption>();

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

        for (String objectName : globalDescribe.keySet()) {
            Schema.DescribeSObjectResult describe = globalDescribe.get(objectName).getDescribe();

            // Filter: Custom objects only
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
     * Get related objects with Lookup or Master-Detail relationships
     */
    @AuraEnabled
    public static List<RelatedObjectInfo> getRelatedObjects(String parentObject) {
        List<RelatedObjectInfo> relatedObjects = new List<RelatedObjectInfo>();

        try {
            Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();

            // Get parent object describe
            Schema.DescribeSObjectResult parentDescribe = globalDescribe.get(parentObject).getDescribe();

            System.debug('🔍 Finding related objects for: ' + parentObject);

            // Iterate through all custom objects
            for (String objectName : globalDescribe.keySet()) {
                Schema.DescribeSObjectResult childDescribe = globalDescribe.get(objectName).getDescribe();

                // Skip if not custom object
                if (!childDescribe.isCustom()) continue;

                // Skip the parent object itself
                if (objectName == parentObject) continue;

                // Check if this object has a relationship to the parent
                List<RelationshipDetail> relationships = findRelationshipsToParent(
                    childDescribe,
                    parentObject
                );

                // Add each relationship as a separate entry
                for (RelationshipDetail rel : relationships) {
                    RelatedObjectInfo info = new RelatedObjectInfo();
                    info.label = childDescribe.getLabel();
                    info.apiName = childDescribe.getName();
                    info.relationshipField = rel.fieldName;
                    info.relationshipLabel = rel.fieldLabel;
                    info.relationshipType = rel.relationshipType;

                    relatedObjects.add(info);
                }
            }

            System.debug('✅ Found ' + relatedObjects.size() + ' related objects');

        } catch (Exception e) {
            System.debug('❌ Error finding related objects: ' + e.getMessage());
            throw new AuraHandledException('Error finding related objects: ' + e.getMessage());
        }

        return relatedObjects;
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
     * Clone records with suffix in DataMigrationId__c
     */
    @AuraEnabled
    public static CloneResult cloneRecords(
        String masterObject,
        List<String> relatedObjects,
        List<String> ids,
        String suffix
    ) {
        CloneResult result = new CloneResult();

        try {
            // Validate inputs
            if (String.isBlank(masterObject)) {
                throw new AuraHandledException('Master Object is required');
            }

            if (ids == null || ids.isEmpty()) {
                throw new AuraHandledException('No IDs provided');
            }

            if (String.isBlank(suffix)) {
                throw new AuraHandledException('Suffix is required');
            }

            System.debug('🔵 Starting cloning process');
            System.debug('📍 Master: ' + masterObject);
            System.debug('📍 Related: ' + relatedObjects);
            System.debug('📍 Suffix: ' + suffix);
            System.debug('📍 IDs: ' + ids.size());

            Set<String> idSet = new Set<String>(ids);

            // Clone master records
            Map<Id, Id> masterIdMapping = cloneMasterRecords(masterObject, idSet, suffix);
            result.masterRecordCount = masterIdMapping.size();

            System.debug('✅ Cloned ' + result.masterRecordCount + ' master records');

            // Clone related records
            result.childRecordCounts = new Map<String, Integer>();
            result.totalChildRecords = 0;

            if (relatedObjects != null && !relatedObjects.isEmpty()) {
                for (String relatedObj : relatedObjects) {
                    Integer count = cloneRelatedRecords(
                        masterObject,
                        relatedObj,
                        masterIdMapping,
                        suffix
                    );

                    result.childRecordCounts.put(relatedObj, count);
                    result.totalChildRecords += count;

                    System.debug('✅ Cloned ' + count + ' records for ' + relatedObj);
                }
            }

            result.success = true;
            result.message = 'Successfully cloned records';

            System.debug('🎉 Cloning complete!');

        } catch (Exception e) {
            result.success = false;
            result.message = 'Error cloning records: ' + e.getMessage();
            System.debug('❌ Error: ' + e.getMessage());
            System.debug('❌ Stack: ' + e.getStackTraceString());
            throw new AuraHandledException(result.message);
        }

        return result;
    }

    // ==================== PRIVATE HELPER METHODS ====================

    /**
     * Clone master records and return old-to-new ID mapping
     */
    private static Map<Id, Id> cloneMasterRecords(
        String objectName,
        Set<String> dataMigrationIds,
        String suffix
    ) {
        Map<Id, Id> idMapping = new Map<Id, Id>();

        try {
            // Build dynamic query
            String query = buildDynamicQuery(objectName);
            query += ' WHERE DataMigrationId__c IN :dataMigrationIds';

            System.debug('🔍 Master Query: ' + query);

            List<SObject> originalRecords = Database.query(query);
            System.debug('📦 Found ' + originalRecords.size() + ' master records to clone');

            if (originalRecords.isEmpty()) {
                return idMapping;
            }

            // Clone records
            List<SObject> clonedRecords = new List<SObject>();

            for (SObject record : originalRecords) {
                SObject clonedRecord = record.clone(false, true, false, false);

                // Update DataMigrationId__c with suffix
                String originalMigrationId = (String) record.get('DataMigrationId__c');
                clonedRecord.put('DataMigrationId__c', originalMigrationId + suffix);

                clonedRecords.add(clonedRecord);
                System.debug('📋 Cloning: ' + originalMigrationId + ' → ' + originalMigrationId + suffix);
            }

            // Insert cloned records
            List<Database.SaveResult> saveResults = Database.insert(clonedRecords, false);

            // Build ID mapping
            for (Integer i = 0; i < saveResults.size(); i++) {
                if (saveResults[i].isSuccess()) {
                    Id originalId = originalRecords[i].Id;
                    Id newId = saveResults[i].getId();
                    idMapping.put(originalId, newId);

                    System.debug('✅ Mapped: ' + originalId + ' → ' + newId);
                } else {
                    System.debug('❌ Failed to clone record: ' + saveResults[i].getErrors()[0].getMessage());
                }
            }

        } catch (Exception e) {
            System.debug('❌ Error cloning master records: ' + e.getMessage());
            throw e;
        }

        return idMapping;
    }

    /**
     * Clone related records with updated relationship references
     */
    private static Integer cloneRelatedRecords(
        String masterObject,
        String relatedObject,
        Map<Id, Id> masterIdMapping,
        String suffix
    ) {
        Integer clonedCount = 0;

        try {
            // Find relationship field
            String relationshipField = findRelationshipFieldName(relatedObject, masterObject);

            if (String.isBlank(relationshipField)) {
                System.debug('⚠️ No relationship field found for ' + relatedObject);
                return 0;
            }

            System.debug('📍 Relationship field: ' + relationshipField);

            // Get original master IDs
            Set<Id> originalMasterIds = masterIdMapping.keySet();

            // Build query for related records
            String query = buildDynamicQuery(relatedObject);
            query += ' WHERE ' + relationshipField + ' IN :originalMasterIds';

            System.debug('🔍 Related Query: ' + query);

            List<SObject> originalRecords = Database.query(query);
            System.debug('📦 Found ' + originalRecords.size() + ' related records to clone');

            if (originalRecords.isEmpty()) {
                return 0;
            }

            // Clone records
            List<SObject> clonedRecords = new List<SObject>();

            for (SObject record : originalRecords) {
                SObject clonedRecord = record.clone(false, true, false, false);

                // Update relationship field to point to new master record
                Id originalMasterId = (Id) record.get(relationshipField);
                Id newMasterId = masterIdMapping.get(originalMasterId);

                if (newMasterId != null) {
                    clonedRecord.put(relationshipField, newMasterId);

                    // Update DataMigrationId__c with suffix if exists
                    if (hasDataMigrationIdField(relatedObject)) {
                        String originalMigrationId = (String) record.get('DataMigrationId__c');
                        if (String.isNotBlank(originalMigrationId)) {
                            clonedRecord.put('DataMigrationId__c', originalMigrationId + suffix);
                        }
                    }

                    clonedRecords.add(clonedRecord);
                }
            }

            // Insert cloned records
            List<Database.SaveResult> saveResults = Database.insert(clonedRecords, false);

            // Count successes
            for (Database.SaveResult sr : saveResults) {
                if (sr.isSuccess()) {
                    clonedCount++;
                } else {
                    System.debug('❌ Failed to clone related record: ' + sr.getErrors()[0].getMessage());
                }
            }

        } catch (Exception e) {
            System.debug('❌ Error cloning related records: ' + e.getMessage());
            throw e;
        }

        return clonedCount;
    }

    /**
     * Find all relationships from child to parent object
     */
    private static List<RelationshipDetail> findRelationshipsToParent(
        Schema.DescribeSObjectResult childDescribe,
        String parentObject
    ) {
        List<RelationshipDetail> relationships = new List<RelationshipDetail>();

        for (Schema.SObjectField field : childDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

            // Check if it's a reference field
            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();

                for (Schema.SObjectType refType : references) {
                    if (refType.getDescribe().getName() == parentObject) {
                        RelationshipDetail detail = new RelationshipDetail();
                        detail.fieldName = fieldDescribe.getName();
                        detail.fieldLabel = fieldDescribe.getLabel();

                        // Determine relationship type
                        if (fieldDescribe.getRelationshipOrder() == 0) {
                            detail.relationshipType = 'Master-Detail';
                        } else {
                            detail.relationshipType = 'Lookup';
                        }

                        relationships.add(detail);
                    }
                }
            }
        }

        return relationships;
    }

    /**
     * Find relationship field name from child to parent
     */
    private static String findRelationshipFieldName(String childObj, String parentObj) {
        Schema.DescribeSObjectResult childDescribe = Schema.getGlobalDescribe()
            .get(childObj)
            .getDescribe();

        for (Schema.SObjectField field : childDescribe.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

            if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
                List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();

                for (Schema.SObjectType refType : references) {
                    if (refType.getDescribe().getName() == parentObj) {
                        return fieldDescribe.getName();
                    }
                }
            }
        }

        return null;
    }

    /**
     * Build dynamic SOQL query with all accessible fields
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
     * Check if object has DataMigrationId__c field
     */
    private static Boolean hasDataMigrationIdField(Schema.DescribeSObjectResult describe) {
        Map<String, Schema.SObjectField> fieldMap = describe.fields.getMap();
        return fieldMap.containsKey('datamigrationid__c');
    }

    /**
     * Check if object has DataMigrationId__c field (by name)
     */
    private static Boolean hasDataMigrationIdField(String objectName) {
        Schema.DescribeSObjectResult describe = Schema.getGlobalDescribe()
            .get(objectName)
            .getDescribe();

        return hasDataMigrationIdField(describe);
    }

    // ==================== INNER CLASSES ====================

    /**
     * Relationship detail
     */
    public class RelationshipDetail {
        public String fieldName;
        public String fieldLabel;
        public String relationshipType;
    }

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
     * Related object info
     */
    public class RelatedObjectInfo {
        @AuraEnabled public String label;
        @AuraEnabled public String apiName;
        @AuraEnabled public String relationshipField;
        @AuraEnabled public String relationshipLabel;
        @AuraEnabled public String relationshipType;
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
     * Clone result
     */
    public class CloneResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public Integer masterRecordCount;
        @AuraEnabled public Integer totalChildRecords;
        @AuraEnabled public Map<String, Integer> childRecordCounts;
        @AuraEnabled public String message;
    }
}
