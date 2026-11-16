/**
 * Covers the Phase 1 batch lifecycle: start() resilience, the terminal branch in finish(),
 * the counters carried by the run context, the By ID scope and the production guard.
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

    @isTest
    static void batch_completesAndFinalizesAuditLog() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        insert new Account(Name = 'Batch Target', Phone = '0612345678');
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(
            new TEKCO_AnonymizationFieldBatch('Account', contextFor(log.Id, 0, 0)), 200
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

    @isTest
    static void batch_carriesAccumulatedCountersIntoAuditLog() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        insert new Account(Name = 'Counter Target', Phone = '0611111111');
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(
            new TEKCO_AnonymizationFieldBatch('Account', contextFor(log.Id, 100, 7)), 200
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

    @isTest
    static void batch_unknownObject_completesWithoutThrowing() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(
            new TEKCO_AnonymizationFieldBatch('No_Such_Object_ZZZ__c', contextFor(log.Id, 0, 0)), 200
        );
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertNotEquals('Running', result.TEKCO_Status__c,
            'Missing object is skipped via the empty locator, not left hanging');
    }

    @isTest
    static void batch_unknownConfigDevNames_completeWithoutThrowing() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        insert new Account(Name = 'No Config');
        TEKCO_AnonymizationAuditLog__c log = newLog();

        TEKCO_AnonymizationRunContext ctx = contextFor(log.Id, 0, 0);
        ctx.configDevNamesByObject.put('Account', new List<String>{ 'No_Such_Config_ZZZ' });

        Test.startTest();
        Database.executeBatch(new TEKCO_AnonymizationFieldBatch('Account', ctx), 200);
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertNotEquals('Running', result.TEKCO_Status__c,
            'An empty config set skips the object and still reaches finish()');
    }

    @isTest
    static void batch_byIdScope_completesAndFinalizesAuditLog() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        Account acc = new Account(Name = 'By Id Target', Phone = '0612345678');
        insert acc;
        TEKCO_AnonymizationAuditLog__c log = newLog();

        TEKCO_AnonymizationRunContext ctx = contextFor(log.Id, 0, 0);
        ctx.byId = true;
        ctx.recordIdsByObject.put('Account', new List<Id>{ acc.Id });

        Test.startTest();
        Database.executeBatch(new TEKCO_AnonymizationFieldBatch('Account', ctx), 200);
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c, TEKCO_EndTime__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertNotEquals('Running', result.TEKCO_Status__c,
            'A By ID run reaches its terminal branch. Got: ' + result.TEKCO_Status__c);
        System.assertNotEquals(null, result.TEKCO_EndTime__c, 'End time stamped on finalize');
    }

    @isTest
    static void chainRunner_byIdStepWithoutRecords_isSkippedAndRunStillFinalizes() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        TEKCO_AnonymizationAuditLog__c log = newLog();

        TEKCO_AnonymizationRunContext ctx = contextFor(log.Id, 0, 0);
        ctx.byId = true;
        ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_FIELD, 'Account');  // no ids for Account

        Test.startTest();
        Id jobId = TEKCO_AnonymizationChainRunner.startNext(ctx);
        Test.stopTest();

        System.assertEquals(null, jobId, 'A By ID step with no resolved record starts no batch');

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertEquals('Success', result.TEKCO_Status__c,
            'Skipping the last step still closes the run instead of leaving it Running');
    }

    @isTest
    static void batch_onProduction_closesLogAsFailed() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = false;
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        Database.executeBatch(
            new TEKCO_AnonymizationFieldBatch('Account', contextFor(log.Id, 0, 0)), 200
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
