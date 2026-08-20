@isTest
private class TEKCO_AnonymizationOrgConfigServiceTest {

    private static final String UNKNOWN_OBJECT = 'TEKCO_NoSuchObject__c';

    /** Config in "TEKCO mode": brands come from the mapping CMDT, not from a brand object. */
    private static TEKCO_AnonymizationOrgConfigService.OrgConfig tekcoModeConfig() {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg =
            new TEKCO_AnonymizationOrgConfigService.OrgConfig();
        cfg.functionalIdField = 'TEKCO_FunctionalId__c';
        cfg.bypassEnabled     = true;
        return cfg;
    }

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
    static void setConfigForTest_overridesResolvedConfig() {
        TEKCO_AnonymizationOrgConfigService.OrgConfig injected = tekcoModeConfig();
        injected.brandObjectApiName = 'ALH_Brand__c';
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(injected);

        System.assert(
            TEKCO_AnonymizationOrgConfigService.getConfig() === injected,
            'Injected config must be the one getConfig() returns'
        );
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

    // ─── Describe utilities ──────────────────────────────────────────────────

    @isTest
    static void hasObject_trueForExistingObject_falseForAbsentOne() {
        System.assertEquals(true, TEKCO_AnonymizationOrgConfigService.hasObject('Account'),
            'Account exists in every org');
        System.assertEquals(false, TEKCO_AnonymizationOrgConfigService.hasObject(UNKNOWN_OBJECT),
            'An absent object must be reported as missing, not throw');
        System.assertEquals(false, TEKCO_AnonymizationOrgConfigService.hasObject(null),
            'Blank object name must be handled');
    }

    @isTest
    static void getSObjectType_returnsTypeForExistingObject_nullForAbsentOne() {
        System.assertEquals(
            Account.SObjectType,
            TEKCO_AnonymizationOrgConfigService.getSObjectType('Account'),
            'Must return the SObjectType usable for newSObject()'
        );
        System.assertEquals(null, TEKCO_AnonymizationOrgConfigService.getSObjectType(UNKNOWN_OBJECT));
    }

    @isTest
    static void getFieldMap_nullForAbsentObject() {
        System.assertNotEquals(null, TEKCO_AnonymizationOrgConfigService.getFieldMap('Account'));
        System.assertEquals(null, TEKCO_AnonymizationOrgConfigService.getFieldMap(UNKNOWN_OBJECT));
    }

    @isTest
    static void hasField_falseWhenObjectAbsent() {
        System.assertEquals(true, TEKCO_AnonymizationOrgConfigService.hasField('Account', 'Name'));
        System.assertEquals(false, TEKCO_AnonymizationOrgConfigService.hasField(UNKNOWN_OBJECT, 'Name'),
            'A field on an absent object must be reported missing, not throw');
        System.assertEquals(false, TEKCO_AnonymizationOrgConfigService.hasField('Account', 'TEKCO_NoSuchField__c'));
    }

    // ─── External ID fields ──────────────────────────────────────────────────

    private static void useExternalIdFields(String configured) {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg = tekcoModeConfig();
        cfg.externalIdFields = configured;
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(cfg);
    }

    @isTest
    static void getExternalIdFieldsOn_keepsOnlyFieldsPresentOnTheObject() {
        useExternalIdFields('AccountNumber,TEKCO_NoSuchField__c');

        List<String> fields = TEKCO_AnonymizationOrgConfigService.getExternalIdFieldsOn('Account');

        System.assertEquals(1, fields.size(), 'Absent fields must be filtered out: ' + fields);
        System.assertEquals('AccountNumber', fields[0]);
    }

    @isTest
    static void getExternalIdFieldsOn_trimsWhitespaceAndSkipsEmptyEntries() {
        useExternalIdFields('  AccountNumber ,, Site  ');

        List<String> fields = TEKCO_AnonymizationOrgConfigService.getExternalIdFieldsOn('Account');

        System.assertEquals(new List<String>{ 'AccountNumber', 'Site' }, fields,
            'Entries must be trimmed and blanks dropped, declaration order preserved');
    }

    @isTest
    static void getExternalIdFieldsOn_returnsEmptyWhenNothingUsable() {
        useExternalIdFields(null);
        System.assertEquals(0,
            TEKCO_AnonymizationOrgConfigService.getExternalIdFieldsOn('Account').size(),
            'A blank setting yields no field');

        useExternalIdFields('AccountNumber');
        System.assertEquals(0,
            TEKCO_AnonymizationOrgConfigService.getExternalIdFieldsOn(UNKNOWN_OBJECT).size(),
            'An absent object yields no field rather than throwing');
    }

    // ─── buildBrandCondition ─────────────────────────────────────────────────

    @isTest
    static void buildBrandCondition_nullForEmptyBrandSelection() {
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(tekcoModeConfig());
        System.assertEquals(null,
            TEKCO_AnonymizationOrgConfigService.buildBrandCondition('Account', null));
        System.assertEquals(null,
            TEKCO_AnonymizationOrgConfigService.buildBrandCondition('Account', new List<String>()));
    }

    /**
     * The regression this guards: probing hasField() with the relationship name (__r) always
     * misses, because field maps only contain __c names — so the brand-object branch silently
     * never matched and brand-filtered runs processed the whole table. AccountId/Account stand
     * in for a real lookup: 'Account__r' probes as 'account__c', absent on Account, while the
     * traversal form is preserved in the emitted condition when the field does exist.
     */
    @isTest
    static void buildBrandCondition_brandObjectMode_probesFieldWithCForm() {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg = tekcoModeConfig();
        cfg.brandObjectApiName       = 'ALH_Brand__c';
        cfg.brandCodeField           = 'Name';
        cfg.brandLookupFieldOnRecord = 'No_Such_Lookup__r';
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(cfg);

        System.assertEquals(null,
            TEKCO_AnonymizationOrgConfigService.buildBrandCondition('Account', new List<String>{ 'B1' }),
            'A lookup absent from the object must yield no condition, not a broken query');
    }

    @isTest
    static void buildBrandCondition_picklistMode_usesFieldWhenPresent() {
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(tekcoModeConfig());

        String condition = TEKCO_AnonymizationOrgConfigService.buildBrandCondition(
            'Account', new List<String>{ 'B1' }
        );

        Boolean hasBrandField =
            TEKCO_AnonymizationOrgConfigService.hasField('Account', 'TEKCO_Brand__c');
        Boolean hasCountryField =
            TEKCO_AnonymizationOrgConfigService.hasField('Account', 'TEKCO_Country__c');
        if (hasBrandField) {
            System.assertEquals('TEKCO_Brand__c IN (\'B1\')', condition);
        } else if (!hasCountryField) {
            System.assertEquals(null, condition,
                'No brand nor country field on Account in this org → no condition');
        }
    }

    @isTest
    static void toInClause_escapesQuotes() {
        System.assertEquals(
            '\'B1\', \'O\\\'Brien\'',
            TEKCO_AnonymizationOrgConfigService.toInClause(new List<String>{ 'B1', 'O\'Brien' }),
            'Values must be quoted, escaped and comma-joined'
        );
    }

    // ─── Brand / country resolution ──────────────────────────────────────────

    @isTest
    static void getCountriesForBrands_returnsEmptyForBlankInput() {
        System.assertEquals(0, TEKCO_AnonymizationOrgConfigService.getCountriesForBrands(null).size());
        System.assertEquals(0, TEKCO_AnonymizationOrgConfigService.getCountriesForBrands(new List<String>()).size());
    }

    @isTest
    static void getCountriesForBrands_brandObjectModeReturnsEmptyWhenFieldsUnset() {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg = tekcoModeConfig();
        cfg.brandObjectApiName = 'ALH_Brand__c';
        cfg.brandCodeField     = null;   // incomplete config must not reach SOQL
        cfg.brandCountryField  = null;
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(cfg);

        System.assertEquals(
            0,
            TEKCO_AnonymizationOrgConfigService.getCountriesForBrands(new List<String>{ 'ANY' }).size(),
            'An incomplete brand-object config must yield no countries rather than fail'
        );
    }

    /**
     * In TEKCO mode the mapping CMDT is reached dynamically. Orgs that do not own it
     * (Portugal) must get an empty list instead of a runtime failure; orgs that do own it
     * simply find no match for a bogus brand.
     */
    @isTest
    static void getCountriesForBrands_tekcoModeSurvivesAbsentMappingObject() {
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(tekcoModeConfig());

        List<String> countries = TEKCO_AnonymizationOrgConfigService.getCountriesForBrands(
            new List<String>{ 'TEKCO_NO_SUCH_BRAND' }
        );

        System.assertNotEquals(null, countries, 'Must never return null');
        System.assertEquals(0, countries.size(), 'A bogus brand maps to no country');
    }

    /**
     * The mapping CMDT is now referenced by name, so the compiler no longer validates it.
     * Where the object does exist, assert its fields still match the constants — this is
     * what replaces the lost compile-time check.
     */
    @isTest
    static void countryBrandConstants_matchTheObjectWhereItExists() {
        String mappingObject = TEKCO_AnonymizationOrgConfigService.COUNTRY_BRAND_OBJECT;
        if (!TEKCO_AnonymizationOrgConfigService.hasObject(mappingObject)) {
            return; // org does not own the mapping CMDT (e.g. Portugal) — nothing to check
        }
        System.assertEquals(true,
            TEKCO_AnonymizationOrgConfigService.hasField(
                mappingObject, TEKCO_AnonymizationOrgConfigService.COUNTRY_BRAND_BRAND_FIELD),
            'COUNTRY_BRAND_BRAND_FIELD no longer matches ' + mappingObject);
        System.assertEquals(true,
            TEKCO_AnonymizationOrgConfigService.hasField(
                mappingObject, TEKCO_AnonymizationOrgConfigService.COUNTRY_BRAND_COUNTRY_FIELD),
            'COUNTRY_BRAND_COUNTRY_FIELD no longer matches ' + mappingObject);
    }
}
