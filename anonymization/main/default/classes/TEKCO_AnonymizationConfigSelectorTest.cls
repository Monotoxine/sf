/**
 * Covers the Custom Metadata selector. Only the input-guard paths are assertable here: CMDT
 * cannot be inserted in a test, so what the queries return depends on the org's own
 * configuration and is exercised end to end instead.
 *
 * Split out of TEKCO_AnonymizationBatchUtilsTest along with the class it covers.
 */
@isTest
private class TEKCO_AnonymizationConfigSelectorTest {

    @isTest
    static void toDevNames_extractsAndSkipsBlanks() {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName = 'Cfg_A'),
            new TEKCO_AnonymizationFieldConfig__mdt(),                          // no DeveloperName
            new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName = 'Cfg_B')
        };

        List<String> names = TEKCO_AnonymizationConfigSelector.toDevNames(configs);

        System.assertEquals(2, names.size(), 'Blank DeveloperName skipped');
        System.assert(names.contains('Cfg_A') && names.contains('Cfg_B'));
    }

    @isTest
    static void toDevNames_nullList_returnsEmpty() {
        System.assertEquals(0, TEKCO_AnonymizationConfigSelector.toDevNames(null).size());
    }

    // ─── loadFieldConfigsByDevNames ────────────────────────────────────────────

    @isTest
    static void loadFieldConfigsByDevNames_emptyInput_shortCircuits() {
        System.assertEquals(
            0,
            TEKCO_AnonymizationConfigSelector.loadFieldConfigsByDevNames(new List<String>()).size(),
            'Empty devName list returns empty without querying'
        );
        System.assertEquals(
            0,
            TEKCO_AnonymizationConfigSelector.loadFieldConfigsByDevNames(null).size(),
            'Null devName list returns empty'
        );
    }

    // ─── validatePatternTypes ──────────────────────────────────────────────────

    // ─── configKey : le contrat partagé avec le LWC ──────────────────────────────

    /**
     * Ce format est écrit par le LWC quand l'utilisateur décoche un champ et relu côté serveur
     * pour décider quoi exclure. Le figer ici : un changement silencieux ferait que les
     * exclusions cessent de correspondre et qu'un champ décoché soit anonymisé quand même.
     */
    @isTest
    static void configKey_recordTypeScoped() {
        TEKCO_AnonymizationFieldConfig__mdt config = new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_ObjectApiName__c           = 'Account',
            TEKCO_FieldApiName__c            = 'PersonEmail',
            TEKCO_RecordTypeDeveloperName__c = 'Patient'
        );
        System.assertEquals('Account.PersonEmail.Patient',
            TEKCO_AnonymizationConfigSelector.configKey(config),
            'Objet.Champ.RecordType — le format que le LWC construit de son côté');
    }

    @isTest
    static void configKey_withoutRecordType_endsWithAnEmptySegment() {
        TEKCO_AnonymizationFieldConfig__mdt config = new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_ObjectApiName__c = 'Account',
            TEKCO_FieldApiName__c  = 'Phone'
        );
        System.assertEquals('Account.Phone.',
            TEKCO_AnonymizationConfigSelector.configKey(config),
            'Le segment vide est significatif : le LWC produit la meme chose avec || \'\'');
    }

    @isTest
    static void configKey_nullConfig_returnsEmpty() {
        System.assertEquals('', TEKCO_AnonymizationConfigSelector.configKey(null),
            'Aucune exception sur une config nulle');
    }
}
