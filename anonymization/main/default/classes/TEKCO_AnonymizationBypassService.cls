/**
 * @author
 * @description Activates all boolean bypass flags on TEKCO_BypassSettings__c (Hierarchy Custom Setting)
 *              for the running user before the anonymization batch starts, then restores the original
 *              state once the entire batch chain is complete.
 */
public class TEKCO_AnonymizationBypassService {

    public class BypassSnapshot {
        public Boolean              hasPreExistingRecord;
        public Map<String, Boolean> preExistingFieldValues;
    }

    public static BypassSnapshot activate() {
        Id userId = UserInfo.getUserId();
        BypassSnapshot snapshot = new BypassSnapshot();
        snapshot.preExistingFieldValues = new Map<String, Boolean>();

        TEKCO_BypassSettings__c existingUserRecord = TEKCO_BypassSettings__c.getInstance(userId);
        snapshot.hasPreExistingRecord = (existingUserRecord != null
            && existingUserRecord.SetupOwnerId == userId);

        TEKCO_BypassSettings__c bypassRecord = snapshot.hasPreExistingRecord
            ? existingUserRecord
            : new TEKCO_BypassSettings__c(SetupOwnerId = userId);

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.TEKCO_BypassSettings__c.fields.getMap();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescriptor = fieldMap.get(fieldName).getDescribe();

            if (fieldDescriptor.getType() == Schema.DisplayType.BOOLEAN
                    && fieldDescriptor.isUpdateable()
                    && fieldDescriptor.isCreateable()
                    && !fieldDescriptor.isCalculated()) {
                if (snapshot.hasPreExistingRecord) {
                    snapshot.preExistingFieldValues.put(
                        fieldName,
                        (Boolean) existingUserRecord.get(fieldName)
                    );
                }
                bypassRecord.put(fieldName, true);
            }
        }

        upsert bypassRecord;
        return snapshot;
    }

    public static void restore(BypassSnapshot snapshot) {
        if (snapshot == null) return;

        Id userId = UserInfo.getUserId();
        List<TEKCO_BypassSettings__c> existingRecords = [
            SELECT Id
            FROM TEKCO_BypassSettings__c
            WHERE SetupOwnerId = :userId
            LIMIT 1
        ];

        TEKCO_BypassSettings__c recordToRestore = existingRecords.isEmpty()
            ? new TEKCO_BypassSettings__c(SetupOwnerId = userId)
            : existingRecords[0];

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.TEKCO_BypassSettings__c.fields.getMap();

        if (!snapshot.hasPreExistingRecord) {
            for (String fieldName : fieldMap.keySet()) {
                Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();
                if (fd.getType() == Schema.DisplayType.BOOLEAN
                        && fd.isUpdateable()
                        && fd.isCreateable()
                        && !fd.isCalculated()) {
                    recordToRestore.put(fieldName, false);
                }
            }
        } else {
            for (String fieldName : snapshot.preExistingFieldValues.keySet()) {
                recordToRestore.put(fieldName, snapshot.preExistingFieldValues.get(fieldName));
            }
        }

        upsert recordToRestore;
    }
}