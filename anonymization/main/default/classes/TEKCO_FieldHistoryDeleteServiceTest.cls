@isTest
private class TEKCO_FieldHistoryDeleteServiceTest {

    /**
     * Note: history objects (AccountHistory etc.) are read-only — Apex cannot insert them,
     * so a true end-to-end delete cannot be exercised in a test context. These cover the
     * counting and error-capture contract using records the test can actually create.
     */

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
        // Already-deleted records fail on a second delete, exercising the error path.
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
}
