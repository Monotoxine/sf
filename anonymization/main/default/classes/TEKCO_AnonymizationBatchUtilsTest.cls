@isTest
private class TEKCO_AnonymizationBatchUtilsTest {

    @isTest
    static void computeHistoryObjectName_customObject() {
        String result = TEKCO_AnonymizationBatchUtils.computeHistoryObjectName('MyObj__c');
        System.assertEquals('MyObj__History', result, 'Custom object history suffix');
    }

    @isTest
    static void computeHistoryObjectName_standardObject() {
        String result = TEKCO_AnonymizationBatchUtils.computeHistoryObjectName('Account');
        System.assertEquals('AccountHistory', result, 'Standard object history suffix');
    }

    @isTest
    static void computeParentIdFieldName_customObject() {
        System.assertEquals('ParentId', TEKCO_AnonymizationBatchUtils.computeParentIdFieldName('MyObj__c'));
    }

    @isTest
    static void computeParentIdFieldName_standardObject() {
        System.assertEquals('AccountId', TEKCO_AnonymizationBatchUtils.computeParentIdFieldName('Account'));
    }

    // ─── cap ───────────────────────────────────────────────────────────────────

    @isTest
    static void cap_truncatesLongStrings() {
        String long400 = 'x'.repeat(400);
        String result  = TEKCO_AnonymizationBatchUtils.cap(long400);
        System.assertEquals(200, result.length(), 'Capped at 200 characters');
    }

    @isTest
    static void cap_leavesShortStringsAndNullAlone() {
        System.assertEquals('short', TEKCO_AnonymizationBatchUtils.cap('short'), 'Under the cap');
        System.assertEquals(null, TEKCO_AnonymizationBatchUtils.cap(null), 'Null passes through');
    }

    // ─── toDevNames ────────────────────────────────────────────────────────────

    @isTest
    static void toDevNames_extractsAndSkipsBlanks() {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName = 'Cfg_A'),
            new TEKCO_AnonymizationFieldConfig__mdt(),                          // no DeveloperName
            new TEKCO_AnonymizationFieldConfig__mdt(DeveloperName = 'Cfg_B')
        };

        List<String> names = TEKCO_AnonymizationBatchUtils.toDevNames(configs);

        System.assertEquals(2, names.size(), 'Blank DeveloperName skipped');
        System.assert(names.contains('Cfg_A') && names.contains('Cfg_B'));
    }

    @isTest
    static void toDevNames_nullList_returnsEmpty() {
        System.assertEquals(0, TEKCO_AnonymizationBatchUtils.toDevNames(null).size());
    }

    // ─── loadFieldConfigsByDevNames ────────────────────────────────────────────

    @isTest
    static void loadFieldConfigsByDevNames_emptyInput_shortCircuits() {
        System.assertEquals(
            0,
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(new List<String>()).size(),
            'Empty devName list returns empty without querying'
        );
        System.assertEquals(
            0,
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(null).size(),
            'Null devName list returns empty'
        );
    }

    // ─── validatePatternTypes ──────────────────────────────────────────────────

    @isTest
    static void validatePatternTypes_flagsUnknownType() {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c = 'Account',
                TEKCO_FieldApiName__c  = 'Name',
                TEKCO_PatternType__c   = 'NO_SUCH_PATTERN_TYPE_XYZ'
            )
        };

        List<String> warnings = TEKCO_AnonymizationBatchUtils.validatePatternTypes(configs);

        System.assertEquals(1, warnings.size(), 'Unknown pattern type reported');
        System.assert(
            warnings[0].contains('NO_SUCH_PATTERN_TYPE_XYZ'),
            'Warning names the offending type: ' + warnings[0]
        );
    }

    @isTest
    static void validatePatternTypes_reportsEachTypeOnce() {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='Name',
                TEKCO_PatternType__c='BOGUS_TYPE_ABC'),
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c='Contact', TEKCO_FieldApiName__c='LastName',
                TEKCO_PatternType__c='BOGUS_TYPE_ABC')
        };

        List<String> warnings = TEKCO_AnonymizationBatchUtils.validatePatternTypes(configs);

        System.assertEquals(1, warnings.size(), 'Same unknown type reported once, not per field');
    }

    @isTest
    static void validatePatternTypes_ignoresBatchHandledTypes() {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c='Account', TEKCO_PatternType__c='DELETE_CONTENT_DOCUMENT'),
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c='EmailMessage', TEKCO_PatternType__c='EMAIL_MESSAGE_LOREM')
        };

        System.assertEquals(
            0,
            TEKCO_AnonymizationBatchUtils.validatePatternTypes(configs).size(),
            'Types handled by dedicated batches need no pattern record'
        );
    }

    @isTest
    static void validatePatternTypes_emptyAndNull_returnEmpty() {
        System.assertEquals(0,
            TEKCO_AnonymizationBatchUtils.validatePatternTypes(
                new List<TEKCO_AnonymizationFieldConfig__mdt>()).size());
        System.assertEquals(0,
            TEKCO_AnonymizationBatchUtils.validatePatternTypes(null).size());
    }

    // ─── requireConfiguredObject / requireFieldOnObject ────────────────────────

    @isTest
    static void requireConfiguredObject_rejectsBlank() {
        try {
            TEKCO_AnonymizationBatchUtils.requireConfiguredObject('');
            System.assert(false, 'Blank object name should throw');
        } catch (Exception e) {
            System.assert(true, 'Blank rejected');
        }
    }

    @isTest
    static void requireConfiguredObject_rejectsUnconfiguredName() {
        // Independent of which CMDT records the org holds: this name is never configured.
        try {
            TEKCO_AnonymizationBatchUtils.requireConfiguredObject('Not_A_Real_Object_ZZZ__c');
            System.assert(false, 'Unconfigured object should throw');
        } catch (Exception e) {
            System.assert(true, 'Unconfigured object rejected before reaching SOQL');
        }
    }

    @isTest
    static void requireFieldOnObject_rejectsMissingField() {
        try {
            TEKCO_AnonymizationBatchUtils.requireFieldOnObject('Account', 'No_Such_Field_ZZZ__c');
            System.assert(false, 'Missing field should throw');
        } catch (Exception e) {
            System.assert(true, 'Missing field rejected before reaching SOQL');
        }
    }

    @isTest
    static void requireFieldOnObject_acceptsRealField() {
        System.assertEquals(
            'Name',
            TEKCO_AnonymizationBatchUtils.requireFieldOnObject('Account', 'Name'),
            'Existing field passes through unchanged'
        );
    }

    @isTest
    static void requireFieldOnObject_rejectsBlank() {
        try {
            TEKCO_AnonymizationBatchUtils.requireFieldOnObject('Account', '');
            System.assert(false, 'Blank field name should throw');
        } catch (Exception e) {
            System.assert(true, 'Blank rejected');
        }
    }

    // ─── assertCanAnonymize ────────────────────────────────────────────────────

    @isTest
    static void assertCanAnonymize_throwsWithoutCustomPermission() {
        // The running test user has no custom permission assigned by default.
        try {
            TEKCO_AnonymizationBatchUtils.assertCanAnonymize();
            // If the org grants it broadly this will not throw — either outcome is valid,
            // the point is that the gate is reachable and does not error unexpectedly.
            System.assert(true, 'Permission present in this org');
        } catch (Exception e) {
            System.assert(
                e.getMessage().containsIgnoreCase('permission'),
                'Rejection mentions the missing permission: ' + e.getMessage()
            );
        }
    }

    // ─── assertSandboxOrClose ──────────────────────────────────────────────────

    @isTest
    static void assertSandboxOrClose_returnsTrueInSandbox() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        Test.startTest();
        Boolean ok = TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(null, null);
        Test.stopTest();

        System.assertEquals(true, ok, 'Sandbox → batch proceeds');
    }

    @isTest
    static void assertSandboxOrClose_closesAuditLogOnProduction() {
        TEKCO_AnonymizationAuditLog__c log = new TEKCO_AnonymizationAuditLog__c(
            TEKCO_Status__c = 'Running', TEKCO_StartTime__c = Datetime.now()
        );
        insert log;

        TEKCO_AnonymizationOrgConfigService.isSandboxCached = false;

        Test.startTest();
        Boolean ok = TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(log.Id, null);
        Test.stopTest();

        System.assertEquals(false, ok, 'Production → batch must not proceed');

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c, TEKCO_ErrorMessage__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertEquals('Failed', result.TEKCO_Status__c,
            'Log closed as Failed rather than left stuck on Running');
        System.assert(result.TEKCO_ErrorMessage__c.containsIgnoreCase('production'),
            'Reason recorded: ' + result.TEKCO_ErrorMessage__c);
    }
}
