@isTest
private class TEKCO_FieldHistoryDeleteServiceTest {

    @isTest
    static void deleteHistoryRecords_deletesAndCounts() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'H1'), new Account(Name = 'H2'), new Account(Name = 'H3')
        };
        insert accounts;

        Test.startTest();
        TEKCO_FieldHistoryDeleteService.DeleteOutcome outcome =
            TEKCO_FieldHistoryDeleteService.deleteHistoryRecords(accounts);
        Test.stopTest();

        System.assertEquals(3, outcome.recordsDeleted, 'All three deleted');
        System.assertEquals(0, outcome.recordsFailed, 'No failures');
        System.assert(outcome.errors.isEmpty(), 'No errors captured');
    }

    @isTest
    static void deleteHistoryRecords_capturesFailures() {
        List<Account> accounts = new List<Account>{
            new Account(Name = 'Gone1'), new Account(Name = 'Gone2')
        };
        insert accounts;
        delete accounts;

        Test.startTest();
        TEKCO_FieldHistoryDeleteService.DeleteOutcome outcome =
            TEKCO_FieldHistoryDeleteService.deleteHistoryRecords(accounts);
        Test.stopTest();

        System.assertEquals(0, outcome.recordsDeleted, 'Nothing actually deleted');
        System.assertEquals(2, outcome.recordsFailed, 'Both failures counted');
        System.assertEquals(2, outcome.errors.size(), 'Both messages captured');
        for (String e : outcome.errors) {
            System.assert(e.length() <= 200, 'Error strings are capped at 200 chars');
        }
    }

    @isTest
    static void deleteHistoryRecords_emptyScope_returnsZeroes() {
        Test.startTest();
        TEKCO_FieldHistoryDeleteService.DeleteOutcome outcome =
            TEKCO_FieldHistoryDeleteService.deleteHistoryRecords(new List<SObject>());
        Test.stopTest();

        System.assertEquals(0, outcome.recordsDeleted);
        System.assertEquals(0, outcome.recordsFailed);
        System.assert(outcome.errors.isEmpty());
    }

    @isTest
    static void deleteHistoryRecords_nullScope_returnsZeroes() {
        Test.startTest();
        TEKCO_FieldHistoryDeleteService.DeleteOutcome outcome =
            TEKCO_FieldHistoryDeleteService.deleteHistoryRecords(null);
        Test.stopTest();

        System.assertEquals(0, outcome.recordsDeleted, 'Null scope handled without exception');
    }

    private static AccountHistory historyRow(String field, Id accountId) {
        return (AccountHistory) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'AccountHistory' },
                'Field'      => field,
                'AccountId'  => accountId
            }),
            AccountHistory.class
        );
    }

    private static TEKCO_AnonymizationFieldConfig__mdt rule(String field, String recordTypes) {
        return new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_FieldApiName__c = field, TEKCO_RecordTypeDeveloperName__c = recordTypes
        );
    }

    @isTest
    static void rowsCoveredByConfigs_keepsOnlyConfiguredFields() {
        Account acc = new Account(Name = 'History Parent');
        insert acc;

        List<SObject> kept = TEKCO_FieldHistoryDeleteService.rowsCoveredByConfigs(
            new List<SObject>{ historyRow('Phone', acc.Id), historyRow('Name', acc.Id) },
            'Account', 'AccountId', new List<TEKCO_AnonymizationFieldConfig__mdt>{ rule('phone', null) }
        );

        System.assertEquals(1, kept.size(), 'Only the configured field is kept');
        System.assertEquals('Phone', kept[0].get('Field'));
    }

    @isTest
    static void rowsCoveredByConfigs_scopedRule_dropsOtherRecordTypes() {
        Account acc = new Account(Name = 'History Parent');
        insert acc;

        List<SObject> kept = TEKCO_FieldHistoryDeleteService.rowsCoveredByConfigs(
            new List<SObject>{ historyRow('Phone', acc.Id) },
            'Account', 'AccountId',
            new List<TEKCO_AnonymizationFieldConfig__mdt>{ rule('Phone', 'No_Such_RT_ZZZ') }
        );

        System.assert(kept.isEmpty(), 'A rule scoped to another record type deletes no history here');
    }

    @isTest
    static void rowsCoveredByConfigs_scopedRule_keepsItsRecordType() {
        List<RecordType> recordTypes = [
            SELECT Id, DeveloperName FROM RecordType
            WHERE SobjectType = 'Account' AND IsActive = true AND IsPersonType = false LIMIT 1
        ];
        if (recordTypes.isEmpty()) return;
        Account acc = new Account(Name = 'History Parent', RecordTypeId = recordTypes[0].Id);
        insert acc;

        List<SObject> kept = TEKCO_FieldHistoryDeleteService.rowsCoveredByConfigs(
            new List<SObject>{ historyRow('Phone', acc.Id) },
            'Account', 'AccountId',
            new List<TEKCO_AnonymizationFieldConfig__mdt>{
                rule('Phone', 'No_Such_RT_ZZZ, ' + recordTypes[0].DeveloperName)
            }
        );

        System.assertEquals(1, kept.size(), 'The rule covers the parent record type');
    }
}
