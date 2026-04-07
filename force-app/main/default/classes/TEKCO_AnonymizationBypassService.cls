/**
 * @author TEKCO Team, 07/04/2026
 * @description Activates all boolean bypass flags on TEKCO_BypassSettings__c (Hierarchy Custom Setting)
 *              for the running user before the anonymization batch starts, then restores the original
 *              state once the entire batch chain is complete.
 *
 *              Why User-level override?
 *              Hierarchy priority: User > Profile > Org.
 *              Setting a User-level record only affects the running user; other users and org defaults
 *              are untouched. Deleting the User-level record afterward automatically reverts to the
 *              Profile/Org default.
 *
 *              All boolean fields are discovered dynamically via Schema describe — no hardcoding needed.
 */
public class TEKCO_AnonymizationBypassService {

    /**
     * @description Snapshot of the User-level TEKCO_BypassSettings__c state before activation.
     *              Serializable as a Database.Stateful field (Map<String, Boolean> + Boolean).
     */
    public class BypassSnapshot {
        /** Whether a User-level bypass record existed before activate() was called. */
        public Boolean              hasPreExistingRecord;
        /** Original boolean field values from the pre-existing User-level record. */
        public Map<String, Boolean> preExistingFieldValues;
    }

    /**
     * @description Sets all updateable boolean fields on TEKCO_BypassSettings__c to true
     *              at the User level for the running user.
     * @return BypassSnapshot capturing the original state, to be passed through the batch
     *         chain and handed to restore() at the very end.
     */
    public static BypassSnapshot activate() {
        Id userId = UserInfo.getUserId();
        BypassSnapshot snapshot = new BypassSnapshot();
        snapshot.preExistingFieldValues = new Map<String, Boolean>();

        // Check for an existing User-level record (getInstance returns User-level only)
        TEKCO_BypassSettings__c existingUserRecord = TEKCO_BypassSettings__c.getInstance(userId);
        snapshot.hasPreExistingRecord = (existingUserRecord != null
            && existingUserRecord.SetupOwnerId == userId);

        TEKCO_BypassSettings__c bypassRecord = snapshot.hasPreExistingRecord
            ? existingUserRecord
            : new TEKCO_BypassSettings__c(SetupOwnerId = userId);

        // Dynamically set ALL updateable boolean fields to true
        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.TEKCO_BypassSettings__c.fields.getMap();

        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fieldDescriptor = fieldMap.get(fieldName).getDescribe();

            if (fieldDescriptor.getType() == Schema.DisplayType.BOOLEAN
                    && fieldDescriptor.isUpdateable()) {
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

    /**
     * @description Restores TEKCO_BypassSettings__c to the state before activate() was called.
     *              If no User-level record existed: deletes the one created by activate().
     *              If one existed: upserts it with the original boolean values.
     * @param snapshot The BypassSnapshot returned by activate(). No-op if null.
     */
    public static void restore(BypassSnapshot snapshot) {
        if (snapshot == null) return;

        Id userId = UserInfo.getUserId();
        List<TEKCO_BypassSettings__c> existingRecords = [
            SELECT Id
            FROM TEKCO_BypassSettings__c
            WHERE SetupOwnerId = :userId
            LIMIT 1
        ];

        if (!snapshot.hasPreExistingRecord) {
            if (!existingRecords.isEmpty()) {
                delete existingRecords;
            }
        } else {
            TEKCO_BypassSettings__c recordToRestore = existingRecords.isEmpty()
                ? new TEKCO_BypassSettings__c(SetupOwnerId = userId)
                : existingRecords[0];

            for (String fieldName : snapshot.preExistingFieldValues.keySet()) {
                recordToRestore.put(fieldName, snapshot.preExistingFieldValues.get(fieldName));
            }
            upsert recordToRestore;
        }
    }
}
