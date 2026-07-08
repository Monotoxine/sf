/**
 * @description Loads the TEKCO_OrgConfig__mdt record matching the current org's domain.
 *              Falls back to a default "TEKCO mode" config when no record matches,
 *              so existing orgs need no CMDT record (backward-compatible).
 *
 * Org config fields:
 *   TEKCO_OrgDomain__c             — org domain prefix (e.g. "airliquidehhc-fr--sbx")
 *   TEKCO_FunctionalIdField__c     — field API name used as functional ID on records
 *   TEKCO_BypassEnabled__c         — whether to activate TEKCO_BypassSettings__c
 *   TEKCO_BrandObjectApiName__c    — blank → picklist on Account; set → brand lookup SObject
 *   TEKCO_BrandCodeField__c        — field on brand object holding the brand code label
 *   TEKCO_BrandCountryField__c     — field on brand object holding the country value
 *   TEKCO_BrandLookupFieldOnRecord__c — field on anonymized objects pointing to brand object
 */
public class TEKCO_OrgConfigService {

    public class OrgConfig {
        public String  orgDomain;
        public String  functionalIdField;
        public Boolean bypassEnabled;
        public String  brandObjectApiName;
        public String  brandCodeField;
        public String  brandCountryField;
        public String  brandLookupFieldOnRecord;

        public Boolean usesBrandObject() {
            return String.isNotBlank(brandObjectApiName);
        }

        /**
         * Returns the SOQL relationship name for brandLookupFieldOnRecord.
         * Custom lookup fields end in __c; their relationship name ends in __r.
         * Standard fields are returned unchanged.
         */
        public String brandLookupRelationshipName() {
            if (String.isBlank(brandLookupFieldOnRecord)) return brandLookupFieldOnRecord;
            return brandLookupFieldOnRecord.endsWith('__c')
                ? brandLookupFieldOnRecord.removeEnd('__c') + '__r'
                : brandLookupFieldOnRecord;
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

        TEKCO_OrgConfig__mdt mdtRecord = null;
        if (String.isNotBlank(currentDomain)) {
            List<TEKCO_OrgConfig__mdt> records = [
                SELECT
                    TEKCO_OrgDomain__c,
                    TEKCO_FunctionalIdField__c,
                    TEKCO_BypassEnabled__c,
                    TEKCO_BrandObjectApiName__c,
                    TEKCO_BrandCodeField__c,
                    TEKCO_BrandCountryField__c,
                    TEKCO_BrandLookupFieldOnRecord__c
                FROM TEKCO_OrgConfig__mdt
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
        } else {
            // Default: TEKCO/Air Liquide standard config
            cfg.functionalIdField          = 'TEKCO_FunctionalId__c';
            cfg.bypassEnabled              = true;
            cfg.brandObjectApiName         = null;
            cfg.brandCodeField             = null;
            cfg.brandCountryField          = null;
            cfg.brandLookupFieldOnRecord   = null;
        }

        cachedConfig = cfg;
        return cachedConfig;
    }

    /** Clears cached config — useful in tests. */
    @TestVisible
    private static void resetCache() {
        cachedConfig = null;
    }
}
