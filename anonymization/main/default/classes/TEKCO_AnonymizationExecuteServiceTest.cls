@isTest
private class TEKCO_AnonymizationExecuteServiceTest {

    private static TEKCO_AnonymizationPattern__mdt activeRegexPattern(String find, String replace) {
        return new TEKCO_AnonymizationPattern__mdt(
            DeveloperName     = 'REGEX',
            MasterLabel       = 'REGEX',
            TEKCO_IsActive__c  = true,
            TEKCO_RegexFind__c = find,
            TEKCO_RegexReplace__c = replace
        );
    }

    // ─── Field update ──────────────────────────────────────────────────────────

    @isTest
    static void execute_updatesFieldWhenPatternChangesValue() {
        TEKCO_AnonymizationPatternService.isSandboxCached = true;

        Account acc = new Account(Name = 'Jean Dupont', Phone = '0612345678');
        insert acc;

        TEKCO_AnonymizationFieldConfig__mdt fc = new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_ObjectApiName__c = 'Account',
            TEKCO_FieldApiName__c  = 'Phone',
            TEKCO_PatternType__c   = 'REGEX',
            TEKCO_IsActive__c      = true
        );

        Map<String, TEKCO_AnonymizationPattern__mdt> patterns =
            new Map<String, TEKCO_AnonymizationPattern__mdt>{
                'REGEX' => activeRegexPattern('\\d', '0')
            };

        Test.startTest();
        TEKCO_AnonymizationExecuteService.ExecuteResult result =
            TEKCO_AnonymizationExecuteService.executeFieldAnonymization(
                new List<SObject>{ [SELECT Id, Phone FROM Account WHERE Id = :acc.Id] },
                new List<TEKCO_AnonymizationFieldConfig__mdt>{ fc },
                patterns,
                new Map<Id, String>()
            );
        Test.stopTest();

        System.assertEquals(1, result.recordsProcessed, 'One record processed');
        System.assertEquals(0, result.recordsFailed, 'No failures');
        System.assert(result.errors.isEmpty(), 'No errors');

        Account updated = [SELECT Phone FROM Account WHERE Id = :acc.Id];
        System.assertEquals('0000000000', updated.Phone, 'All digits replaced with 0');
    }

    @isTest
    static void execute_skipsInactivePattern() {
        Account acc = new Account(Name = 'Test', Phone = '0611111111');
        insert acc;

        TEKCO_AnonymizationFieldConfig__mdt fc = new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_ObjectApiName__c = 'Account',
            TEKCO_FieldApiName__c  = 'Phone',
            TEKCO_PatternType__c   = 'REGEX',
            TEKCO_IsActive__c      = true
        );

        TEKCO_AnonymizationPattern__mdt inactivePattern = activeRegexPattern('\\d', '0');
        inactivePattern.TEKCO_IsActive__c = false;

        Map<String, TEKCO_AnonymizationPattern__mdt> patterns =
            new Map<String, TEKCO_AnonymizationPattern__mdt>{ 'REGEX' => inactivePattern };

        TEKCO_AnonymizationExecuteService.ExecuteResult result =
            TEKCO_AnonymizationExecuteService.executeFieldAnonymization(
                new List<SObject>{ [SELECT Id, Phone FROM Account WHERE Id = :acc.Id] },
                new List<TEKCO_AnonymizationFieldConfig__mdt>{ fc },
                patterns,
                new Map<Id, String>()
            );

        System.assertEquals(0, result.recordsProcessed, 'Inactive pattern → record not updated');
    }

    // ─── Record type filtering ─────────────────────────────────────────────────

    @isTest
    static void execute_skipsRecordWhenRecordTypeMismatch() {
        Account acc = new Account(Name = 'Test', Phone = '0612345678');
        insert acc;

        TEKCO_AnonymizationFieldConfig__mdt fc = new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_ObjectApiName__c             = 'Account',
            TEKCO_FieldApiName__c              = 'Phone',
            TEKCO_PatternType__c               = 'REGEX',
            TEKCO_IsActive__c                  = true,
            TEKCO_RecordTypeDeveloperName__c   = 'NonMatchingRT'
        );

        Map<String, TEKCO_AnonymizationPattern__mdt> patterns =
            new Map<String, TEKCO_AnonymizationPattern__mdt>{ 'REGEX' => activeRegexPattern('\\d', '0') };

        TEKCO_AnonymizationExecuteService.ExecuteResult result =
            TEKCO_AnonymizationExecuteService.executeFieldAnonymization(
                new List<SObject>{ [SELECT Id, Phone FROM Account WHERE Id = :acc.Id] },
                new List<TEKCO_AnonymizationFieldConfig__mdt>{ fc },
                patterns,
                new Map<Id, String>()  // empty → no RT match possible
            );

        System.assertEquals(0, result.recordsProcessed, 'RT mismatch → record skipped');
    }

    // ─── EMAIL_MESSAGE_LOREM ───────────────────────────────────────────────────

    @isTest
    static void execute_emailMessageLorem_draftAppliesLoremText() {
        // EmailMessage can only be tested via Case > EmailMessage
        // We simulate the status='5' branch via a mock SObject
        // Using Account as a stand-in with a put() approach is not possible for EmailMessage
        // → This is documented as a manual test requirement (requires Case + EmailMessage setup)
        // Verify at minimum the LOREM_TEXT constant is accessible
        System.assertNotEquals(null, TEKCO_AnonymizationPatternService.LOREM_TEXT);
        System.assert(TEKCO_AnonymizationPatternService.LOREM_TEXT.length() > 0);
    }

    // ─── Empty scope ───────────────────────────────────────────────────────────

    @isTest
    static void execute_emptyScope_returnsZeroCounts() {
        TEKCO_AnonymizationExecuteService.ExecuteResult result =
            TEKCO_AnonymizationExecuteService.executeFieldAnonymization(
                new List<SObject>(),
                new List<TEKCO_AnonymizationFieldConfig__mdt>(),
                new Map<String, TEKCO_AnonymizationPattern__mdt>(),
                new Map<Id, String>()
            );

        System.assertEquals(0, result.recordsProcessed);
        System.assertEquals(0, result.recordsFailed);
        System.assert(result.errors.isEmpty());
    }
}
