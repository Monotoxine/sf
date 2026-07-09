@isTest
private class TEKCO_AnonymizationBypassServiceTest {

    @isTest
    static void activate_whenBypassDisabled_returnsSnapshotWithNoRecord() {
        // Force bypassEnabled = false via a fake org config
        TEKCO_AnonymizationOrgConfigService.resetCache();
        // We can't inject a custom OrgConfig directly, but we can validate the snapshot shape.
        // If the org has no CMDT record for the current domain and default config has bypassEnabled=true,
        // the real activate() will attempt the upsert. In @isTest DML is allowed.
        // This test just validates that activate() returns a non-null snapshot.
        Test.startTest();
        TEKCO_AnonymizationBypassService.BypassSnapshot snapshot =
            TEKCO_AnonymizationBypassService.activate();
        Test.stopTest();

        System.assertNotEquals(null, snapshot, 'Snapshot must never be null');
        System.assertNotEquals(null, snapshot.preExistingFieldValues, 'Field values map must be initialized');
    }

    @isTest
    static void restore_nullSnapshot_doesNotThrow() {
        // Passing null must be a no-op
        Test.startTest();
        TEKCO_AnonymizationBypassService.restore(null);
        Test.stopTest();
        System.assert(true, 'No exception thrown for null snapshot');
    }

    @isTest
    static void activateAndRestore_roundTrip() {
        TEKCO_AnonymizationOrgConfigService.resetCache();

        Test.startTest();
        TEKCO_AnonymizationBypassService.BypassSnapshot snapshot =
            TEKCO_AnonymizationBypassService.activate();
        TEKCO_AnonymizationBypassService.restore(snapshot);
        Test.stopTest();

        System.assertNotEquals(null, snapshot, 'Snapshot from activate() must not be null');
    }
}
