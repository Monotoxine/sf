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
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

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

    // ─── applyPatternsTo: the transformation without the DML ───────────────────

    /**
     * The preview relies on this method returning the same result as a run while writing
     * nothing. If these two ever diverge, the preview becomes a lie.
     */
    @isTest
    static void applyPatternsTo_capturesBeforeValuesAndLeavesTheDatabaseUntouched() {
        Account acc = new Account(Name = 'Jean Dupont', Phone = '0612345678');
        insert acc;

        TEKCO_AnonymizationFieldConfig__mdt fc = new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_ObjectApiName__c = 'Account',
            TEKCO_FieldApiName__c  = 'Phone',
            TEKCO_PatternType__c   = 'REGEX',
            TEKCO_IsActive__c      = true
        );

        SObject record = [SELECT Id, Phone FROM Account WHERE Id = :acc.Id];
        Map<String, String> beforeByField = new Map<String, String>();

        Test.startTest();
        TEKCO_AnonymizationExecuteService.RecordOutcome outcome =
            TEKCO_AnonymizationExecuteService.applyPatternsTo(
                record,
                new List<TEKCO_AnonymizationFieldConfig__mdt>{ fc },
                new Map<String, TEKCO_AnonymizationPattern__mdt>{
                    'REGEX' => activeRegexPattern('\\d', '0')
                },
                new Map<Id, String>(),
                beforeByField
            );
        Test.stopTest();

        System.assertEquals(true, outcome.modified, 'The record was transformed');
        System.assertEquals(false, outcome.toDelete, 'A REGEX pattern never deletes');
        System.assertEquals('0612345678', beforeByField.get('Phone'), 'The former value is captured');
        System.assertEquals('0000000000', (String) record.get('Phone'), 'The in-memory value is the new one');

        Account stored = [SELECT Phone FROM Account WHERE Id = :acc.Id];
        System.assertEquals('0612345678', stored.Phone,
            'applyPatternsTo must not persist anything — this is what makes the preview safe');
    }

    @isTest
    static void applyPatternsTo_withoutCaptureMapStillTransforms() {
        Account acc = new Account(Name = 'Test', Phone = '0611111111');
        insert acc;

        TEKCO_AnonymizationFieldConfig__mdt fc = new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_ObjectApiName__c = 'Account',
            TEKCO_FieldApiName__c  = 'Phone',
            TEKCO_PatternType__c   = 'REGEX',
            TEKCO_IsActive__c      = true
        );

        SObject record = [SELECT Id, Phone FROM Account WHERE Id = :acc.Id];

        // null capture map: what every batch run passes, so capture costs nothing there.
        TEKCO_AnonymizationExecuteService.RecordOutcome outcome =
            TEKCO_AnonymizationExecuteService.applyPatternsTo(
                record,
                new List<TEKCO_AnonymizationFieldConfig__mdt>{ fc },
                new Map<String, TEKCO_AnonymizationPattern__mdt>{
                    'REGEX' => activeRegexPattern('\\d', '0')
                },
                new Map<Id, String>(),
                null
            );

        System.assertEquals(true, outcome.modified, 'Transformation happens with or without capture');
        System.assertEquals('0000000000', (String) record.get('Phone'), 'The value is transformed');
    }

    @isTest
    static void applyPatternsTo_recordTypeScopedConfigIsSkippedOnAnotherRecordType() {
        Account acc = new Account(Name = 'Test', Phone = '0611111111');
        insert acc;

        TEKCO_AnonymizationFieldConfig__mdt fc = new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_ObjectApiName__c = 'Account',
            TEKCO_FieldApiName__c  = 'Phone',
            TEKCO_PatternType__c   = 'REGEX',
            TEKCO_IsActive__c      = true,
            TEKCO_RecordTypeDeveloperName__c = 'SomeOtherRecordType'
        );

        SObject record = [SELECT Id, Phone FROM Account WHERE Id = :acc.Id];

        TEKCO_AnonymizationExecuteService.RecordOutcome outcome =
            TEKCO_AnonymizationExecuteService.applyPatternsTo(
                record,
                new List<TEKCO_AnonymizationFieldConfig__mdt>{ fc },
                new Map<String, TEKCO_AnonymizationPattern__mdt>{
                    'REGEX' => activeRegexPattern('\\d', '0')
                },
                new Map<Id, String>(),
                new Map<String, String>()
            );

        System.assertEquals(false, outcome.modified,
            'A record type scoped config must not touch a record of another type');
        System.assertEquals('0611111111', (String) record.get('Phone'), 'The value is untouched');
    }

    // ─── Couverture par record type : une regle porte une LISTE de populations ───────────

    /**
     * RETROCOMPATIBILITE. Une regle mono-valuee doit se comporter exactement comme avant :
     * elle s applique a sa population et a aucune autre.
     */
    @isTest
    static void recordTypeScoping_singleValue_stillExcludesOtherPopulations() {
        TEKCO_AnonymizationFieldConfig__mdt rule = new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_RecordTypeDeveloperName__c = 'Patient'
        );
        Set<String> covered = TEKCO_AnonymizationConfigSelector.recordTypesOf(rule);

        System.assert(covered.contains('Patient'), 'Sa population');
        System.assert(!covered.contains('Prescriber'), 'Et aucune autre');
    }

    /** Une regle multi-population couvre chacune de ses valeurs, et rien d autre. */
    @isTest
    static void recordTypeScoping_listCoversEachValueAndNoOther() {
        Set<String> covered = TEKCO_AnonymizationConfigSelector.recordTypesOf(
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_RecordTypeDeveloperName__c = 'Patient,Prescriber'
            )
        );

        System.assert(covered.contains('Patient') && covered.contains('Prescriber'),
            'Les deux populations declarees');
        System.assert(!covered.contains('Hospital'),
            'Hospital n est pas couvert : ALH_FiscalNumber__c ne doit pas toucher un Patient');
    }

    /** Vide = toutes les populations, donc aucun test de record type a l execution. */
    @isTest
    static void recordTypeScoping_blankAppliesEverywhere() {
        System.assertEquals(false, TEKCO_AnonymizationConfigSelector.isRecordTypeScoped(
            new TEKCO_AnonymizationFieldConfig__mdt()),
            'Une regle sans record type s applique a tout l objet');
    }
}
