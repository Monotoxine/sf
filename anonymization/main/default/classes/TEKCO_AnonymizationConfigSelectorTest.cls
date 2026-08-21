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

    // ─── configKey : l'identite d'une config ─────────────────────────────────────

    /**
     * La cle voyage vers le LWC sur le DTO et revient telle quelle dans excludedFields. Le
     * DeveloperName est unique par construction : c'est ce qui remplace l'ancien
     * Objet.Champ.RecordType, construit des deux cotes et surtout capable d'entrer en collision.
     */
    @isTest
    static void configKey_isTheDeveloperName() {
        TEKCO_AnonymizationFieldConfig__mdt config = new TEKCO_AnonymizationFieldConfig__mdt(
            DeveloperName                    = 'Patient_PersonEmail',
            TEKCO_ObjectApiName__c           = 'Account',
            TEKCO_FieldApiName__c            = 'PersonEmail',
            TEKCO_RecordTypeDeveloperName__c = 'Patient'
        );
        System.assertEquals('Patient_PersonEmail',
            TEKCO_AnonymizationConfigSelector.configKey(config),
            'La cle est le DeveloperName, pas une chaine composee');
    }

    /**
     * Le cas qui a motive le changement. IndividualP_Address et Patient_Address visent le meme
     * objet et le meme champ sans record type, et ne different que par leur filtre : l'ancienne
     * cle valait 'Address.Street.' pour les deux, donc decocher l'une decochait l'autre.
     */
    @isTest
    static void configKey_twoConfigsOnTheSameFieldDoNotCollide() {
        TEKCO_AnonymizationFieldConfig__mdt individual = new TEKCO_AnonymizationFieldConfig__mdt(
            DeveloperName             = 'IndividualP_Address',
            TEKCO_ObjectApiName__c    = 'Address',
            TEKCO_FieldApiName__c     = 'Street',
            TEKCO_AdditionalFilter__c = 'X = 1'
        );
        TEKCO_AnonymizationFieldConfig__mdt patient = new TEKCO_AnonymizationFieldConfig__mdt(
            DeveloperName             = 'Patient_Address',
            TEKCO_ObjectApiName__c    = 'Address',
            TEKCO_FieldApiName__c     = 'Street',
            TEKCO_AdditionalFilter__c = 'X = 2'
        );

        System.assertNotEquals(
            TEKCO_AnonymizationConfigSelector.configKey(individual),
            TEKCO_AnonymizationConfigSelector.configKey(patient),
            'Deux configs sur le meme objet et le meme champ restent distinguables');
    }

    @isTest
    static void configKey_nullConfig_returnsEmpty() {
        System.assertEquals('', TEKCO_AnonymizationConfigSelector.configKey(null),
            'Aucune exception sur une config nulle');
    }

    // ─── recordTypesOf : la liste des populations couvertes ──────────────────────

    /**
     * RETROCOMPATIBILITE. Les 98 configs livrees sont toutes mono-valuees : une valeur unique
     * doit produire exactement l ancien comportement, un ensemble d un seul element.
     */
    @isTest
    static void recordTypesOf_singleValue_behavesAsBefore() {
        Set<String> recordTypes = TEKCO_AnonymizationConfigSelector.recordTypesOf(
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_RecordTypeDeveloperName__c = 'ACCCO_Patient'
            )
        );

        System.assertEquals(1, recordTypes.size(), 'Un seul element');
        System.assert(recordTypes.contains('ACCCO_Patient'), 'La valeur d origine');
    }

    @isTest
    static void recordTypesOf_list_isSplit() {
        Set<String> recordTypes = TEKCO_AnonymizationConfigSelector.recordTypesOf(
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_RecordTypeDeveloperName__c = 'ACCCO_IndividualPerson,ACCCO_Patient'
            )
        );

        System.assertEquals(2, recordTypes.size(), 'Les deux populations');
        System.assert(recordTypes.contains('ACCCO_IndividualPerson'));
        System.assert(recordTypes.contains('ACCCO_Patient'));
    }

    /** Une liste saisie a la main dans Setup porte des espaces : ils ne doivent rien casser. */
    @isTest
    static void recordTypesOf_toleratesSpacesAndEmptySegments() {
        Set<String> recordTypes = TEKCO_AnonymizationConfigSelector.recordTypesOf(
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_RecordTypeDeveloperName__c = ' Patient ,, Prescriber , '
            )
        );

        System.assertEquals(2, recordTypes.size(), 'Segments vides ignores : ' + recordTypes);
        System.assert(recordTypes.contains('Patient') && recordTypes.contains('Prescriber'),
            'Valeurs detourees');
    }

    /** Vide = toutes les populations, exactement comme avant. */
    @isTest
    static void recordTypesOf_blankOrNull_returnsEmpty() {
        System.assertEquals(0, TEKCO_AnonymizationConfigSelector.recordTypesOf(
            new TEKCO_AnonymizationFieldConfig__mdt()).size());
        System.assertEquals(0, TEKCO_AnonymizationConfigSelector.recordTypesOf(
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_RecordTypeDeveloperName__c = '   ')).size());
        System.assertEquals(0, TEKCO_AnonymizationConfigSelector.recordTypesOf(null).size());
    }

    @isTest
    static void isRecordTypeScoped_reflectsTheList() {
        System.assertEquals(false, TEKCO_AnonymizationConfigSelector.isRecordTypeScoped(
            new TEKCO_AnonymizationFieldConfig__mdt()),
            'Sans record type, la regle couvre tout l objet');
        System.assertEquals(true, TEKCO_AnonymizationConfigSelector.isRecordTypeScoped(
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_RecordTypeDeveloperName__c = 'Patient,Prescriber')),
            'Avec une liste, elle est scopee');
    }
}
