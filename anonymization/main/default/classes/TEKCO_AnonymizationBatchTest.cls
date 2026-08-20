/**
 * Covers the Phase 1 batch lifecycle: start() resilience, the terminal branch in finish(), the
 * accumulated-counter contract carried by the run context, and the production guard.
 *
 * Two constraints shape what can be asserted here:
 *  - Custom Metadata cannot be inserted in a test, and the batch loads its configs from CMDT by
 *    developer name. Field selection and transformation are therefore asserted directly, without
 *    a batch, in TEKCO_AnonymizationScopeQueryBuilderTest and TEKCO_AnonymizationExecuteServiceTest.
 *  - Only one Database.executeBatch may run per test, so the chaining branches are exercised by
 *    leaving the step list empty and asserting the terminal branch.
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

    /** A context with no step left: the batch under test is the last link of the chain. */
    private static TEKCO_AnonymizationRunContext contextFor(
        Id auditLogId, Integer accProcessed, Integer accFailed
    ) {
        TEKCO_AnonymizationRunContext ctx = new TEKCO_AnonymizationRunContext();
        ctx.auditLogId = auditLogId;
        ctx.byId       = false;
        ctx.addProcessed(accProcessed);
        ctx.addFailed(accFailed);
        return ctx;
    }

    // ─── Lifecycle ─────────────────────────────────────────────────────────────

    @isTest
    static void batch_completesAndFinalizesAuditLog() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        insert new Account(Name = 'Batch Target', Phone = '0612345678');
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(
            new TEKCO_AnonymizationBatch('Account', contextFor(log.Id, 0, 0)), 200
        );
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

    /**
     * The counters live on the context now, which is what stops them being forgotten by one
     * link of the chain — the bug that made multi-object runs report only the last object.
     */
    @isTest
    static void batch_carriesAccumulatedCountersIntoAuditLog() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        insert new Account(Name = 'Counter Target', Phone = '0611111111');
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(
            new TEKCO_AnonymizationBatch('Account', contextFor(log.Id, 100, 7)), 200
        );
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
            'Prior failure count carried forward rather than reset. Got: '
            + result.TEKCO_RecordsFailed__c
        );
    }

    // ─── start() resilience ────────────────────────────────────────────────────

    @isTest
    static void batch_unknownObject_completesWithoutThrowing() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(
            new TEKCO_AnonymizationBatch('No_Such_Object_ZZZ__c', contextFor(log.Id, 0, 0)), 200
        );
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertNotEquals('Running', result.TEKCO_Status__c,
            'Missing object is skipped via the empty locator, not left hanging');
    }

    /** Developer names that match no CMDT record: nothing to apply, the run still terminates. */
    @isTest
    static void batch_unknownConfigDevNames_completeWithoutThrowing() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        insert new Account(Name = 'No Config');
        TEKCO_AnonymizationAuditLog__c log = newLog();

        TEKCO_AnonymizationRunContext ctx = contextFor(log.Id, 0, 0);
        ctx.configDevNamesByObject.put('Account', new List<String>{ 'No_Such_Config_ZZZ' });

        Test.startTest();
        Database.executeBatch(new TEKCO_AnonymizationBatch('Account', ctx), 200);
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertNotEquals('Running', result.TEKCO_Status__c,
            'An empty config set skips the object and still reaches finish()');
    }

    // ─── Production guard ──────────────────────────────────────────────────────

    @isTest
    static void batch_onProduction_closesLogAsFailed() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = false;
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(
            new TEKCO_AnonymizationBatch('Account', contextFor(log.Id, 0, 0)), 200
        );
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

    // ─── Chain termination ─────────────────────────────────────────────────────

    /**
     * With no step left, the runner must restore the bypass and finalize the log rather than
     * leave it Running. This is the single terminal path that used to be repeated in six
     * finish() blocks.
     */
    @isTest
    static void chainRunner_withNoStepLeft_finalizesTheRun() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        TEKCO_AnonymizationAuditLog__c log = newLog();

        TEKCO_AnonymizationRunContext ctx = contextFor(log.Id, 42, 0);

        Test.startTest();
        Id jobId = TEKCO_AnonymizationChainRunner.startNext(ctx);
        Test.stopTest();

        System.assertEquals(null, jobId, 'No batch is started when the plan is empty');

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c, TEKCO_EndTime__c, TEKCO_RecordsProcessed__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertEquals('Success', result.TEKCO_Status__c, 'Run closed as Success');
        System.assertNotEquals(null, result.TEKCO_EndTime__c, 'End time stamped');
        System.assertEquals(42, result.TEKCO_RecordsProcessed__c,
            'The context counters are what the audit log records');
    }

    @isTest
    static void chainRunner_nullContext_isANoOp() {
        Test.startTest();
        Id jobId = TEKCO_AnonymizationChainRunner.startNext(null);
        Test.stopTest();
        System.assertEquals(null, jobId, 'A null context must not throw');
    }
}
