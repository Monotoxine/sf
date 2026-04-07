/**
 * AnonymizationBypassService
 *
 * Activates all boolean bypass flags on TEKCO_BypassSettings__c (Hierarchy
 * Custom Setting) for the running user before the anonymization batch starts,
 * then restores the original state once the entire batch chain is complete.
 *
 * Why User-level override?
 *   Hierarchy priority: User > Profile > Org.
 *   Setting a User-level record only affects the running user; other users
 *   and org defaults are untouched. Deleting the User-level record afterward
 *   automatically reverts to the Profile/Org default.
 *
 * All boolean fields are set dynamically via Schema describe — no hardcoding.
 */
public class AnonymizationBypassService {

    /**
     * Snapshot of the User-level TEKCO_BypassSettings__c state before activation.
     * Serializable as a Database.Stateful field (Map<String, Boolean> + Boolean).
     */
    public class BypassSnapshot {
        public Boolean              hadUserRecord;
        public Map<String, Boolean> originalBooleanValues;
    }

    /**
     * Sets all updateable boolean fields on TEKCO_BypassSettings__c to TRUE
     * at the User level for the running user.
     *
     * @return BypassSnapshot — original state, to be passed through the batch
     *         chain and handed to restore() at the very end.
     */
    public static BypassSnapshot activate() {
        Id userId = UserInfo.getUserId();
        BypassSnapshot snapshot = new BypassSnapshot();
        snapshot.originalBooleanValues = new Map<String, Boolean>();

        // Check for an existing User-level record
        TEKCO_BypassSettings__c userRecord = TEKCO_BypassSettings__c.getInstance(userId);
        // getInstance(userId) returns the User-level record only (null if none)
        snapshot.hadUserRecord = (userRecord != null && userRecord.SetupOwnerId == userId);

        TEKCO_BypassSettings__c bypassRecord = snapshot.hadUserRecord
            ? userRecord
            : new TEKCO_BypassSettings__c(SetupOwnerId = userId);

        // Dynamically set ALL updateable boolean fields to true
        for (String fieldName : Schema.SObjectType.TEKCO_BypassSettings__c.fields.getMap().keySet()) {
            Schema.DescribeFieldResult dfr =
                Schema.SObjectType.TEKCO_BypassSettings__c.fields.getMap()
                    .get(fieldName).getDescribe();

            if (dfr.getType() == Schema.DisplayType.BOOLEAN && dfr.isUpdateable()) {
                // Capture original value for restoration
                if (snapshot.hadUserRecord) {
                    snapshot.originalBooleanValues.put(
                        fieldName,
                        (Boolean) userRecord.get(fieldName)
                    );
                }
                bypassRecord.put(fieldName, true);
            }
        }

        upsert bypassRecord;
        return snapshot;
    }

    /**
     * Restores the TEKCO_BypassSettings__c User-level record to its state
     * before activate() was called.
     *
     * - If no User-level record existed: deletes the one we created.
     * - If one existed: upserts with the original boolean values.
     *
     * @param snapshot  The BypassSnapshot returned by activate(). No-op if null.
     */
    public static void restore(BypassSnapshot snapshot) {
        if (snapshot == null) return;

        Id userId = UserInfo.getUserId();
        List<TEKCO_BypassSettings__c> existing = [
            SELECT Id FROM TEKCO_BypassSettings__c
            WHERE SetupOwnerId = :userId
            LIMIT 1
        ];

        if (!snapshot.hadUserRecord) {
            // We created this record — remove it entirely
            if (!existing.isEmpty()) {
                delete existing;
            }
        } else {
            // Restore original boolean values
            TEKCO_BypassSettings__c restore = existing.isEmpty()
                ? new TEKCO_BypassSettings__c(SetupOwnerId = userId)
                : existing[0];

            for (String fieldName : snapshot.originalBooleanValues.keySet()) {
                restore.put(fieldName, snapshot.originalBooleanValues.get(fieldName));
            }
            upsert restore;
        }
    }
}
