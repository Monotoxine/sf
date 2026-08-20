/**
 * @author
 * @description Activates all boolean bypass flags on TEKCO_BypassSettings__c (Hierarchy Custom Setting)
 *              for the running user before the anonymization batch starts, then restores the original
 *              state once the entire batch chain is complete.
 *
 *              The setting is reached dynamically: it is absent from some orgs (Portugal, where
 *              TEKCO_BypassEnabled__c is false), and a compile-time reference would make the whole
 *              package undeployable there even though this code never runs.
 *
 *              Which setting carries the flags is per-org configuration:
 *              TEKCO_AnonymizationOrgConfig__mdt.TEKCO_BypassObjectApiName__c, defaulting to the
 *              standard TEKCO_BypassSettings__c when blank. An org with its own bypass setting can
 *              enable TEKCO_BypassEnabled__c and point this at it, so its automations are
 *              suppressed during a run instead of firing on every anonymization update.
 */
public inherited sharing class TEKCO_AnonymizationBypassService {

    private static final String DEFAULT_BYPASS_OBJECT = 'TEKCO_BypassSettings__c';

    private static String bypassObject() {
        String configured = TEKCO_AnonymizationOrgConfigService.getConfig().bypassObjectApiName;
        return String.isNotBlank(configured) ? configured : DEFAULT_BYPASS_OBJECT;
    }

    public class BypassSnapshot {
        public Boolean              hasPreExistingRecord;
        public Map<String, Boolean> preExistingFieldValues;
    }

    private static List<String> bypassFieldNames;

    private static Boolean bypassAvailable() {
        return TEKCO_AnonymizationOrgConfigService.getConfig().bypassEnabled
            && TEKCO_AnonymizationOrgConfigService.hasObject(bypassObject());
    }

    private static List<String> getBypassFieldNames() {
        if (bypassFieldNames != null) return bypassFieldNames;
        bypassFieldNames = new List<String>();
        Map<String, Schema.SObjectField> fieldMap =
            TEKCO_AnonymizationOrgConfigService.getFieldMap(bypassObject());
        if (fieldMap == null) return bypassFieldNames;
        for (String fieldName : fieldMap.keySet()) {
            Schema.DescribeFieldResult fd = fieldMap.get(fieldName).getDescribe();
            if (fd.getType() == Schema.DisplayType.BOOLEAN && fd.isUpdateable()) {
                bypassFieldNames.add(fieldName);
            }
        }
        return bypassFieldNames;
    }

    private static SObject getOrNewBypassRecord(Id userId) {
        List<String> fieldNames = getBypassFieldNames();
        String selectList = fieldNames.isEmpty() ? 'Id' : 'Id, ' + String.join(fieldNames, ', ');
        List<SObject> existing = Database.queryWithBinds(
            'SELECT ' + selectList + ' FROM ' + bypassObject()
                + ' WHERE SetupOwnerId = :userId LIMIT 1',
            new Map<String, Object>{ 'userId' => userId },
            AccessLevel.SYSTEM_MODE
        );
        if (!existing.isEmpty()) return existing[0];

        SObject bypassRecord =
            TEKCO_AnonymizationOrgConfigService.getSObjectType(bypassObject()).newSObject();
        bypassRecord.put('SetupOwnerId', userId);
        return bypassRecord;
    }

    private static void saveBypassRecord(SObject bypassRecord) {
        if (bypassRecord.Id == null) {
            Database.insert(bypassRecord);
        } else {
            Database.update(bypassRecord);
        }
    }

    public static BypassSnapshot activate() {
        BypassSnapshot snapshot = new BypassSnapshot();
        snapshot.preExistingFieldValues = new Map<String, Boolean>();
        snapshot.hasPreExistingRecord = false;

        if (!bypassAvailable()) return snapshot;

        SObject bypassRecord = getOrNewBypassRecord(UserInfo.getUserId());
        snapshot.hasPreExistingRecord = (bypassRecord.Id != null);

        for (String fieldName : getBypassFieldNames()) {
            if (snapshot.hasPreExistingRecord) {
                snapshot.preExistingFieldValues.put(
                    fieldName,
                    bypassRecord.get(fieldName) == true
                );
            }
            bypassRecord.put(fieldName, true);
        }

        saveBypassRecord(bypassRecord);
        return snapshot;
    }

    public static void restore(BypassSnapshot snapshot) {
        if (snapshot == null) return;
        if (!bypassAvailable()) return;

        SObject recordToRestore = getOrNewBypassRecord(UserInfo.getUserId());

        if (!snapshot.hasPreExistingRecord) {
            for (String fieldName : getBypassFieldNames()) {
                recordToRestore.put(fieldName, false);
            }
        } else {
            for (String fieldName : snapshot.preExistingFieldValues.keySet()) {
                recordToRestore.put(fieldName, snapshot.preExistingFieldValues.get(fieldName));
            }
        }

        saveBypassRecord(recordToRestore);
    }
}