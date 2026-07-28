/**
 * Covers the Phase 1 batch lifecycle: start() query construction, the finalize path in
 * finish(), the accumulated-counter contract, and the production guard.
 *
 * Two constraints shape what can be asserted here:
 *  - Custom Metadata cannot be inserted in a test, and the batch re-queries CMDT inside
 *    execute()/finish() (the serialization fix). Field-level transformation is therefore
 *    covered by TEKCO_AnonymizationExecuteServiceTest, which takes configs as parameters.
 *  - Only one Database.executeBatch may run per test, so chaining branches are exercised by
 *    leaving the remaining/contentDoc/history lists empty and asserting the terminal branch.
 */
@isTest
private class TEKCO_AnonymizationBatchTest {

    private static TEKCO_AnonymizationAuditLog__c newLog() {
        TEKCO_AnonymizationAuditLog__c log = new TEKCO_AnonymizationAuditLog__c(
            TEKCO_TriggeredBy__c = UserInfo.getUserId(),
            TEKCO_BrandFilter__c = 'TEST',
            TEKCO_Status__c      = 'Running',
            TEKCO_StartTime__c   = Datetime.now()
        );
        insert log;
        return log;
    }

    private static List<TEKCO_AnonymizationFieldConfig__mdt> phoneConfig() {
        return new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(
                DeveloperName          = 'Test_Account_Phone',
                TEKCO_ObjectApiName__c = 'Account',
                TEKCO_FieldApiName__c  = 'Phone',
                TEKCO_PatternType__c   = 'REGEX',
                TEKCO_IsActive__c      = true
            )
        };
    }

    private static TEKCO_AnonymizationBatch buildBatch(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs,
        Id auditLogId,
        Integer accProcessed,
        Integer accFailed
    ) {
        return new TEKCO_AnonymizationBatch(
            objectApiName,
            configs,
            new Map<String, TEKCO_AnonymizationPattern__mdt>(),
            new List<String>(),                                   // selectedBrands
            auditLogId,
            new List<String>(),                                   // remainingObjects
            new List<TEKCO_AnonymizationFieldConfig__mdt>(),      // contentDocConfigs
            new List<TEKCO_AnonymizationFieldConfig__mdt>(),      // historyConfigs
            null,                                                 // bypassSnapshot
            new List<String>(),                                   // accumulatedErrors
            accProcessed,
            accFailed,
            new Map<String, List<String>>(),
            new Map<String, String>()
        );
    }

    // ─── Lifecycle ─────────────────────────────────────────────────────────────

    @isTest
    static void batch_completesAndFinalizesAuditLog() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        insert new Account(Name = 'Batch Target', Phone = '0612345678');
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(buildBatch('Account', phoneConfig(), log.Id, 0, 0), 200);
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c, TEKCO_EndTime__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assert(
            result.TEKCO_Status__c == 'Success' || result.TEKCO_Status__c == 'Partial',
            'Terminal branch reached, not left Running. Got: ' + result.TEKCO_Status__c
        );
        System.assertNotEquals(null, result.TEKCO_EndTime__c, 'End time stamped on finalize');
    }

    @isTest
    static void batch_carriesAccumulatedCountersIntoAuditLog() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        insert new Account(Name = 'Counter Target', Phone = '0611111111');
        TEKCO_AnonymizationAuditLog__c log = newLog();

        // Seed counters as an earlier link in the chain would.
        Test.startTest();
        Database.executeBatch(buildBatch('Account', phoneConfig(), log.Id, 100, 7), 200);
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_RecordsProcessed__c, TEKCO_RecordsFailed__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assert(
            result.TEKCO_RecordsProcessed__c >= 100,
            'Prior processed count carried forward, got: ' + result.TEKCO_RecordsProcessed__c
        );
        System.assert(
            result.TEKCO_RecordsFailed__c >= 7,
            'Prior failure count carried forward rather than reset — this is the bug that made '
            + 'multi-object runs report only the last object. Got: ' + result.TEKCO_RecordsFailed__c
        );
    }

    // ─── start() resilience ────────────────────────────────────────────────────

    @isTest
    static void batch_unknownObject_completesWithoutThrowing() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(
            buildBatch('No_Such_Object_ZZZ__c', phoneConfig(), log.Id, 0, 0), 200
        );
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertNotEquals('Running', result.TEKCO_Status__c,
            'Missing object is skipped via the empty locator, not left hanging');
    }

    @isTest
    static void batch_unknownField_isSkippedAndRunContinues() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        insert new Account(Name = 'Field Skip');
        TEKCO_AnonymizationAuditLog__c log = newLog();

        List<TEKCO_AnonymizationFieldConfig__mdt> badField =
            new List<TEKCO_AnonymizationFieldConfig__mdt>{
                new TEKCO_AnonymizationFieldConfig__mdt(
                    DeveloperName          = 'Test_Bad_Field',
                    TEKCO_ObjectApiName__c = 'Account',
                    TEKCO_FieldApiName__c  = 'No_Such_Field_ZZZ__c',
                    TEKCO_PatternType__c   = 'REGEX',
                    TEKCO_IsActive__c      = true
                )
            };

        Test.startTest();
        Database.executeBatch(buildBatch('Account', badField, log.Id, 0, 0), 200);
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertNotEquals('Running', result.TEKCO_Status__c,
            'Unknown field is recorded and skipped; the batch still reaches finish()');
    }

    // ─── Production guard ──────────────────────────────────────────────────────

    @isTest
    static void batch_onProduction_closesLogAsFailed() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = false;
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(buildBatch('Account', phoneConfig(), log.Id, 0, 0), 200);
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c, TEKCO_ErrorMessage__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertEquals('Failed', result.TEKCO_Status__c,
            'Production guard closes the log instead of leaving it stuck on Running');
        System.assert(result.TEKCO_ErrorMessage__c.containsIgnoreCase('production'),
            'Reason recorded: ' + result.TEKCO_ErrorMessage__c);
    }

    // ─── Constructor null-tolerance ────────────────────────────────────────────

    @isTest
    static void constructor_nullCollections_defaultToEmpty() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        Test.startTest();
        TEKCO_AnonymizationBatch batch = new TEKCO_AnonymizationBatch(
            'Account', null, null, null, null, null, null, null, null, null, null, null, null, null
        );
        Test.stopTest();

        System.assertNotEquals(null, batch,
            'Every collection parameter is null-guarded, so construction never throws');
    }
}
