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
        /** Hierarchy Custom Setting carrying the bypass flags. Blank = TEKCO_BypassSettings__c. */
        public String  bypassObjectApiName;
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
                    TEKCO_BypassObjectApiName__c,
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
            cfg.bypassObjectApiName        = mdtRecord.TEKCO_BypassObjectApiName__c;
            cfg.brandObjectApiName         = mdtRecord.TEKCO_BrandObjectApiName__c;
            cfg.brandCodeField             = mdtRecord.TEKCO_BrandCodeField__c;
            cfg.brandCountryField          = mdtRecord.TEKCO_BrandCountryField__c;
            cfg.brandLookupFieldOnRecord   = mdtRecord.TEKCO_BrandLookupFieldOnRecord__c;
            cfg.externalIdFields           = mdtRecord.TEKCO_ExternalIdFields__c;
        } else {
            // Default: TEKCO standard config
            cfg.functionalIdField          = 'TEKCO_FunctionalId__c';
            cfg.bypassEnabled              = true;
            cfg.bypassObjectApiName        = null; // blank = TEKCO_BypassSettings__c
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
        countriesByBrandsKey = new Map<String, List<String>>();
    }

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

    /**
     * External ID field API names this org declares, restricted to those actually present on
     * the object. Single parser for TEKCO_ExternalIdFields__c: the By ID selector, the batch
     * SELECT builders and the pattern service all read the setting through here.
     */
    public static List<String> getExternalIdFieldsOn(String objectApiName) {
        List<String> result = new List<String>();
        String configured = getConfig().externalIdFields;
        if (String.isBlank(configured)) return result;
        for (String raw : configured.split(',')) {
            String trimmed = raw.trim();
            if (String.isNotBlank(trimmed) && hasField(objectApiName, trimmed)) {
                result.add(trimmed);
            }
        }
        return result;
    }

    // ─── Brand / country resolution ──────────────────────────────────────────

    @TestVisible
    private static final String COUNTRY_BRAND_OBJECT        = 'TEKCO_CountryBrandSetting__mdt';
    @TestVisible
    private static final String COUNTRY_BRAND_COUNTRY_FIELD = 'TEKCO_Country__c';
    @TestVisible
    private static final String COUNTRY_BRAND_BRAND_FIELD   = 'TEKCO_Brand__c';

    /**
     * Per-transaction cache: buildBrandCondition() runs once per object (preview loops over
     * every selected object in one transaction), and each miss costs a SOQL query.
     */
    private static Map<String, List<String>> countriesByBrandsKey = new Map<String, List<String>>();

    public static List<String> getCountriesForBrands(List<String> brands) {
        if (brands == null || brands.isEmpty()) return new List<String>();

        List<String> sortedBrands = new List<String>(brands);
        sortedBrands.sort();
        String cacheKey = String.join(sortedBrands, '|');
        if (countriesByBrandsKey.containsKey(cacheKey)) return countriesByBrandsKey.get(cacheKey);

        List<String> countries = resolveCountriesForBrands(brands);
        countriesByBrandsKey.put(cacheKey, countries);
        return countries;
    }

    private static List<String> resolveCountriesForBrands(List<String> brands) {
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
     * SOQL condition restricting objectApiName records to the selected brands, or null when no
     * brand condition applies to this object. Single implementation for the three By Criteria
     * batches and the preview count — they each carried a copy, and every copy probed
     * hasField() with the relationship name (__r), which a field map never contains, so the
     * brand-object branch silently never matched and brand-filtered runs processed the whole
     * table. The field map is probed with the __c form; the SOQL traversal keeps __r.
     */
    public static String buildBrandCondition(String objectApiName, List<String> selectedBrands) {
        if (selectedBrands == null || selectedBrands.isEmpty()) return null;
        OrgConfig cfg = getConfig();

        if (cfg.usesBrandObject()) {
            if (String.isBlank(cfg.brandLookupFieldOnRecord) || String.isBlank(cfg.brandCodeField)) {
                return null;
            }
            String lookupFieldApiName = cfg.brandLookupFieldOnRecord.replaceAll('__r$', '__c');
            if (!hasField(objectApiName, lookupFieldApiName)) return null;
            return cfg.brandLookupFieldOnRecord + '.' + cfg.brandCodeField
                + ' IN (' + toInClause(selectedBrands) + ')';
        }

        if (hasField(objectApiName, 'TEKCO_Brand__c')) {
            return 'TEKCO_Brand__c IN (' + toInClause(selectedBrands) + ')';
        }
        if (hasField(objectApiName, 'TEKCO_Country__c')) {
            List<String> countries = getCountriesForBrands(selectedBrands);
            if (countries.isEmpty()) return null;
            return 'TEKCO_Country__c IN (' + toInClause(countries) + ')';
        }
        return null;
    }

    /** Escaped, quoted, comma-joined values for a dynamic SOQL IN clause. */
    public static String toInClause(List<String> values) {
        List<String> escaped = new List<String>();
        for (String value : values) {
            escaped.add('\'' + String.escapeSingleQuotes(value) + '\'');
        }
        return String.join(escaped, ', ');
    }

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