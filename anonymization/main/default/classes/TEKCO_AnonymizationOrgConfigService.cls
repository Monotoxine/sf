/**
 * @description Loads the TEKCO_AnonymizationOrgConfig__mdt record matching the current org's domain.
 *              Falls back to a default "TEKCO mode" config when no record matches,
 *              so existing orgs need no CMDT record
 */
public class TEKCO_AnonymizationOrgConfigService {

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
        fieldMapCache = new Map<String, Map<String, Schema.SObjectField>>();
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

    // ─── Field utilities ─────────────────────────────────────────────────────

    /**
     * Cache of field maps by lowercase object API name. hasField() is called in loops
     * (preview counts, external ID resolution, every batch start()), and each miss costs
     * a full describe. Null value = object does not exist in this org.
     */
    private static Map<String, Map<String, Schema.SObjectField>> fieldMapCache =
        new Map<String, Map<String, Schema.SObjectField>>();

    public static Boolean hasField(String objectApiName, String fieldApiName) {
        if (String.isBlank(objectApiName) || String.isBlank(fieldApiName)) return false;
        Map<String, Schema.SObjectField> fields = getFieldMap(objectApiName);
        return fields != null && fields.containsKey(fieldApiName.toLowerCase());
    }

    private static Map<String, Schema.SObjectField> getFieldMap(String objectApiName) {
        String key = objectApiName.toLowerCase();
        if (fieldMapCache.containsKey(key)) return fieldMapCache.get(key);
        Map<String, Schema.SObjectField> fields = null;
        try {
            fields = Schema.describeSObjects(new List<String>{ objectApiName })[0].fields.getMap();
        } catch (Exception e) {
            fields = null;
        }
        fieldMapCache.put(key, fields);
        return fields;
    }

    // ─── Brand / country resolution ──────────────────────────────────────────

    public static List<String> getCountriesForBrands(List<String> brands) {
        List<String> countries = new List<String>();
        if (brands == null || brands.isEmpty()) return countries;

        OrgConfig cfg = getConfig();

        if (cfg.usesBrandObject()) {
            if (String.isBlank(cfg.brandObjectApiName)
                    || String.isBlank(cfg.brandCodeField)
                    || String.isBlank(cfg.brandCountryField)) {
                return countries;
            }
            String soql = 'SELECT ' + cfg.brandCountryField
                + ' FROM ' + cfg.brandObjectApiName
                + ' WHERE ' + cfg.brandCodeField + ' IN :brands'
                + ' AND ' + cfg.brandCountryField + ' != null';
            for (SObject rec : Database.query(soql)) {
                Object country = rec.get(cfg.brandCountryField);
                if (country != null) countries.add(String.valueOf(country));
            }
        } else {
            for (TEKCO_CountryBrandSetting__mdt mapping : [
                SELECT TEKCO_Country__c
                FROM TEKCO_CountryBrandSetting__mdt
                WHERE TEKCO_Brand__c IN :brands
                  AND TEKCO_Country__c != null
            ]) {
                countries.add(mapping.TEKCO_Country__c);
            }
        }
        return countries;
    }
}
