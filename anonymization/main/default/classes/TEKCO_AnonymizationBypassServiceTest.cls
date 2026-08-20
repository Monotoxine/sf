@isTest
private class TEKCO_AnonymizationBypassServiceTest {

    /** Blank object name = bypass disabled; set = bypass through that hierarchy setting. */
    private static TEKCO_AnonymizationOrgConfigService.OrgConfig configWithBypassObject(String objectApiName) {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg =
            new TEKCO_AnonymizationOrgConfigService.OrgConfig();
        cfg.functionalIdField   = 'TEKCO_FunctionalId__c';
        cfg.bypassObjectApiName = objectApiName;
        return cfg;
    }

    @isTest
    static void activate_whenNoBypassObjectConfigured_isNoOp() {
        // Portugal-like org: no bypass setting named — the tool must not touch anything.
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(configWithBypassObject(null));

        Test.startTest();
        TEKCO_AnonymizationBypassService.BypassSnapshot snapshot =
            TEKCO_AnonymizationBypassService.activate();
        Test.stopTest();

        System.assertNotEquals(null, snapshot, 'Snapshot must never be null');
        System.assertEquals(false, snapshot.hasPreExistingRecord,
            'Nothing was read, so no pre-existing record can be reported');
        System.assertEquals(0, snapshot.preExistingFieldValues.size(),
            'No field value must be captured when the bypass is disabled');
    }

    @isTest
    static void restore_whenNoBypassObjectConfigured_isNoOp() {
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(configWithBypassObject(null));

        TEKCO_AnonymizationBypassService.BypassSnapshot snapshot =
            new TEKCO_AnonymizationBypassService.BypassSnapshot();
        snapshot.hasPreExistingRecord   = false;
        snapshot.preExistingFieldValues = new Map<String, Boolean>();

        Test.startTest();
        TEKCO_AnonymizationBypassService.restore(snapshot);
        Test.stopTest();

        System.assert(true, 'restore() must not throw when the bypass is disabled');
    }

    @isTest
    static void restore_nullSnapshot_doesNotThrow() {
        // Passing null must be a no-op
        Test.startTest();
        TEKCO_AnonymizationBypassService.restore(null);
        Test.stopTest();
        System.assert(true, 'No exception thrown for null snapshot');
    }

    /**
     * Runs against the org's real config. Where the bypass setting exists the flags are
     * raised then put back; where it does not, both calls are inert. Either way the pair
     * must complete without error.
     */
    @isTest
    static void activateAndRestore_roundTrip() {
        TEKCO_AnonymizationOrgConfigService.resetCache();

        Test.startTest();
        TEKCO_AnonymizationBypassService.BypassSnapshot snapshot =
            TEKCO_AnonymizationBypassService.activate();
        TEKCO_AnonymizationBypassService.restore(snapshot);
        Test.stopTest();

        System.assertNotEquals(null, snapshot, 'Snapshot from activate() must not be null');
        System.assertNotEquals(null, snapshot.preExistingFieldValues, 'Field values map must be initialized');
    }
}
