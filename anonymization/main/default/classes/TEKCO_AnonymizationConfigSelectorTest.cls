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
}
