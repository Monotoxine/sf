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

    /** Updateable boolean field names on TEKCO_BypassSettings__c, described once per transaction. */
    private static List<String> bypassFieldNames;

    private static List<String> getBypassFieldNames() {
        if (bypassFieldNames != null) return bypassFieldNames;
        bypassFieldNames = new List<String>();
        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.TEKCO_BypassSettings__c.fields.getMap();
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();
            if (fd.getType() == Schema.DisplayType.BOOLEAN && fd.isUpdateable()) {
                bypassFieldNames.add(fieldName);
            }
        }
        return bypassFieldNames;
    }

    public static BypassSnapshot activate() {
        BypassSnapshot snapshot = new BypassSnapshot();
        snapshot.preExistingFieldValues = new Map<String, Boolean>();

        if (!TEKCO_AnonymizationOrgConfigService.getConfig().bypassEnabled) {
            snapshot.hasPreExistingRecord = false;
            return snapshot;
        }

        Id userId = UserInfo.getUserId();
        TEKCO_BypassSettings__c existingUserRecord = TEKCO_BypassSettings__c.getInstance(userId);
        snapshot.hasPreExistingRecord = (existingUserRecord != null
            && existingUserRecord.SetupOwnerId == userId);

        TEKCO_BypassSettings__c bypassRecord = snapshot.hasPreExistingRecord
            ? existingUserRecord
            : new TEKCO_BypassSettings__c(SetupOwnerId = userId);

        for (String fieldName : getBypassFieldNames()) {
            if (snapshot.hasPreExistingRecord) {
                snapshot.preExistingFieldValues.put(
                    fieldName,
                    existingUserRecord.get(fieldName) == true
                );
            }
            bypassRecord.put(fieldName, true);
        }

        upsert bypassRecord;
        return snapshot;
    }

    public static void restore(BypassSnapshot snapshot) {
        if (snapshot == null) return;
        if (!TEKCO_AnonymizationOrgConfigService.getConfig().bypassEnabled) return;

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

        if (!snapshot.hasPreExistingRecord) {
            for (String fieldName : getBypassFieldNames()) {
                recordToRestore.put(fieldName, false);
            }
        } else {
            for (String fieldName : snapshot.preExistingFieldValues.keySet()) {
                recordToRestore.put(fieldName, snapshot.preExistingFieldValues.get(fieldName));
            }
        }

        upsert recordToRestore;
    }
}