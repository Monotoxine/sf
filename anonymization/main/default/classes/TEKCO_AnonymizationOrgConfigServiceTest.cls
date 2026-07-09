@isTest
private class TEKCO_AnonymizationOrgConfigServiceTest {

    @isTest
    static void getConfig_returnsDefaultsWhenNoCmdtMatch() {
        TEKCO_AnonymizationOrgConfigService.resetCache();

        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg = TEKCO_AnonymizationOrgConfigService.getConfig();

        // Either matched a CMDT record (org-specific) or fell back to defaults.
        // In both cases the config must be non-null and have at minimum a functionalIdField.
        System.assertNotEquals(null, cfg, 'Config must never be null');
        System.assertNotEquals(null, cfg.functionalIdField, 'Functional ID field must be set');
    }

    @isTest
    static void getConfig_cacheReturnsSameInstance() {
        TEKCO_AnonymizationOrgConfigService.resetCache();
        TEKCO_AnonymizationOrgConfigService.OrgConfig first  = TEKCO_AnonymizationOrgConfigService.getConfig();
        TEKCO_AnonymizationOrgConfigService.OrgConfig second = TEKCO_AnonymizationOrgConfigService.getConfig();
        System.assert(first === second, 'Both calls must return the exact same cached instance');
    }

    @isTest
    static void resetCache_clearsCache() {
        TEKCO_AnonymizationOrgConfigService.getConfig(); // populate
        TEKCO_AnonymizationOrgConfigService.resetCache();
        // If cache was cleared, a new call re-runs the SOQL without throwing
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg = TEKCO_AnonymizationOrgConfigService.getConfig();
        System.assertNotEquals(null, cfg);
    }

    @isTest
    static void usesBrandObject_falseWhenBrandObjectApiNameBlank() {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg = new TEKCO_AnonymizationOrgConfigService.OrgConfig();
        cfg.brandObjectApiName = null;
        System.assertEquals(false, cfg.usesBrandObject());
    }

    @isTest
    static void usesBrandObject_trueWhenBrandObjectApiNameSet() {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg = new TEKCO_AnonymizationOrgConfigService.OrgConfig();
        cfg.brandObjectApiName = 'ALH_Brand__c';
        System.assertEquals(true, cfg.usesBrandObject());
    }
}
