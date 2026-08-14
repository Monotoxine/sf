/**
 * @description Loads the TEKCO_AnonymizationOrgConfig__mdt record matching the current org's domain.
 *              Falls back to a default "TEKCO mode" config when no record matches,
 *              so existing orgs need no CMDT record
 */
public inherited sharing class TEKCO_AnonymizationOrgConfigService {

    public class OrgConfig {
        public String  orgDomain;
        public String  functionalIdField;
        public Boolean bypassEnabled;
        public String  brandObjectApiName;
        public String  brandCodeField;
        public String  brandCountryField;
        public String  brandLookupFieldOnRecord;
        /** Comma-separated list of extra external ID field API names offered in the By ID tab. */
        public String  externalIdFields;

        public Boolean usesBrandObject() {
            return String.isNotBlank(brandObjectApiName);
        }
    }

    private static OrgConfig cachedConfig;

    public static OrgConfig getConfig() {
        if (cachedConfig != null) return cachedConfig;

        String currentDomain = '';
        try {
            currentDomain = URL.getOrgDomainUrl().getHost().substringBefore('.');
        } catch (Exception e) {
            currentDomain = '';
        }

        TEKCO_AnonymizationOrgConfig__mdt mdtRecord = null;
        if (String.isNotBlank(currentDomain)) {
            List<TEKCO_AnonymizationOrgConfig__mdt> records = [
                SELECT
                    TEKCO_OrgDomain__c,
                    TEKCO_FunctionalIdField__c,
                    TEKCO_BypassEnabled__c,
                    TEKCO_BrandObjectApiName__c,
                    TEKCO_BrandCodeField__c,
                    TEKCO_BrandCountryField__c,
                    TEKCO_BrandLookupFieldOnRecord__c,
                    TEKCO_ExternalIdFields__c
                FROM TEKCO_AnonymizationOrgConfig__mdt
                WHERE TEKCO_OrgDomain__c = :currentDomain
                LIMIT 1
            ];
            if (!records.isEmpty()) mdtRecord = records[0];
        }

        OrgConfig cfg = new OrgConfig();
        cfg.orgDomain = currentDomain;

        if (mdtRecord != null) {
            cfg.functionalIdField          = mdtRecord.TEKCO_FunctionalIdField__c;
            cfg.bypassEnabled              = mdtRecord.TEKCO_BypassEnabled__c == true;
            cfg.brandObjectApiName         = mdtRecord.TEKCO_BrandObjectApiName__c;
            cfg.brandCodeField             = mdtRecord.TEKCO_BrandCodeField__c;
            cfg.brandCountryField          = mdtRecord.TEKCO_BrandCountryField__c;
            cfg.brandLookupFieldOnRecord   = mdtRecord.TEKCO_BrandLookupFieldOnRecord__c;
            cfg.externalIdFields           = mdtRecord.TEKCO_ExternalIdFields__c;
        } else {
            // Default: TEKCO standard config
            cfg.functionalIdField          = 'TEKCO_FunctionalId__c';
            cfg.bypassEnabled              = true;
            cfg.brandObjectApiName         = null;
            cfg.brandCodeField             = null;
            cfg.brandCountryField          = null;
            cfg.brandLookupFieldOnRecord   = null;
            cfg.externalIdFields           = 'TEKCO_DataMigrationId__c,TEKCO_ExternalId__c,TEKCO_FhirId__c';
        }

        cachedConfig = cfg;
        return cachedConfig;
    }

    @TestVisible
    private static void resetCache() {
        cachedConfig = null;
        describeCache = new Map<String, Schema.DescribeSObjectResult>();
    }

    /** Forces the config for the current transaction so tests can exercise both org modes. */
    @TestVisible
    private static void setConfigForTest(OrgConfig cfg) {
        cachedConfig = cfg;
    }

    // ─── Sandbox guard ───────────────────────────────────────────────────────

    public class ProductionOrgException extends Exception {}

    @TestVisible public static Boolean isSandboxCached = null;

    public static void assertIsSandbox() {
        if (isSandboxCached == null) {
            Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
            isSandboxCached = org.IsSandbox;
        }
        if (!isSandboxCached) {
            throw new ProductionOrgException(
                'ABORT: Data anonymization is not allowed on Production orgs. ' +
                'This operation has been blocked. No data was modified.'
            );
        }
    }

    // ─── Describe utilities ──────────────────────────────────────────────────

    /**
     * Cache of object describes by lowercase API name. hasField() is called in loops
     * (preview counts, external ID resolution, every batch start()), and each miss costs
     * a full describe. Null value = object does not exist in this org.
     *
     * Single describe entry point for the whole package: hasObject(), hasField() and
     * getSObjectType() all read from here, so no caller opens its own describe path.
     */
    private static Map<String, Schema.DescribeSObjectResult> describeCache =
        new Map<String, Schema.DescribeSObjectResult>();

    private static Schema.DescribeSObjectResult getDescribe(String objectApiName) {
        if (String.isBlank(objectApiName)) return null;
        String key = objectApiName.toLowerCase();
        if (describeCache.containsKey(key)) return describeCache.get(key);
        Schema.DescribeSObjectResult describeResult = null;
        try {
            describeResult = Schema.describeSObjects(new List<String>{ objectApiName })[0];
        } catch (Exception e) {
            describeResult = null;
        }
        describeCache.put(key, describeResult);
        return describeResult;
    }

    /**
     * True when the object exists in this org. Lets callers reach objects that are absent
     * from some orgs (e.g. Portugal has neither TEKCO_BypassSettings__c nor
     * TEKCO_CountryBrandSetting__mdt) without a compile-time reference that would make the
     * package undeployable there.
     */
    public static Boolean hasObject(String objectApiName) {
        return getDescribe(objectApiName) != null;
    }

    /** SObjectType for dynamic instantiation, or null when the object is absent. */
    public static Schema.SObjectType getSObjectType(String objectApiName) {
        Schema.DescribeSObjectResult describeResult = getDescribe(objectApiName);
        return describeResult == null ? null : describeResult.getSObjectType();
    }

    /** Field map for the object, or null when the object is absent. */
    public static Map<String, Schema.SObjectField> getFieldMap(String objectApiName) {
        Schema.DescribeSObjectResult describeResult = getDescribe(objectApiName);
        return describeResult == null ? null : describeResult.fields.getMap();
    }

    public static Boolean hasField(String objectApiName, String fieldApiName) {
        if (String.isBlank(fieldApiName)) return false;
        Map<String, Schema.SObjectField> fields = getFieldMap(objectApiName);
        return fields != null && fields.containsKey(fieldApiName.toLowerCase());
    }

    // ─── Brand / country resolution ──────────────────────────────────────────

    /**
     * Brand-to-country mapping CMDT used by orgs that do not model brands as a lookup
     * object. Absent from the Portugal org, hence reached dynamically.
     */
    @TestVisible
    private static final String COUNTRY_BRAND_OBJECT        = 'TEKCO_CountryBrandSetting__mdt';
    @TestVisible
    private static final String COUNTRY_BRAND_COUNTRY_FIELD = 'TEKCO_Country__c';
    @TestVisible
    private static final String COUNTRY_BRAND_BRAND_FIELD   = 'TEKCO_Brand__c';

    public static List<String> getCountriesForBrands(List<String> brands) {
        if (brands == null || brands.isEmpty()) return new List<String>();

        OrgConfig cfg = getConfig();

        if (cfg.usesBrandObject()) {
            if (String.isBlank(cfg.brandCodeField) || String.isBlank(cfg.brandCountryField)) {
                return new List<String>();
            }
            return queryCountryColumn(
                cfg.brandObjectApiName, cfg.brandCodeField, cfg.brandCountryField, brands
            );
        }

        if (!hasObject(COUNTRY_BRAND_OBJECT)) return new List<String>();
        return queryCountryColumn(
            COUNTRY_BRAND_OBJECT, COUNTRY_BRAND_BRAND_FIELD, COUNTRY_BRAND_COUNTRY_FIELD, brands
        );
    }

    /**
     * Both brand modes resolve countries the same way — filter a source object on the brand
     * values, collect one text column — so they share this query rather than each carrying
     * their own loop.
     */
    private static List<String> queryCountryColumn(
        String sourceObject, String brandField, String countryField, List<String> brands
    ) {
        List<String> countries = new List<String>();
        String soql = 'SELECT ' + countryField
            + ' FROM ' + sourceObject
            + ' WHERE ' + brandField + ' IN :brands'
            + ' AND ' + countryField + ' != null';
        for (SObject record : Database.queryWithBinds(
                soql,
                new Map<String, Object>{ 'brands' => brands },
                AccessLevel.SYSTEM_MODE)) {
            Object country = record.get(countryField);
            if (country != null) countries.add(String.valueOf(country));
        }
        return countries;
    }
}
