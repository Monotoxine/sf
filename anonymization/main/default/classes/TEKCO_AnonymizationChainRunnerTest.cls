/** Covers TEKCO_AnonymizationChainRunner: skipped steps, the end of the run, a null context. */
@isTest
private class TEKCO_AnonymizationChainRunnerTest {

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

    @isTest
    static void chainRunner_startedStep_recordsItsJobOnTheLog() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        TEKCO_AnonymizationAuditLog__c log = newLog();

        TEKCO_AnonymizationRunContext ctx = contextFor(log.Id, 0, 0);
        ctx.addStep(TEKCO_AnonymizationRunContext.PHASE_FIELD, 'Account');

        Test.startTest();
        Id jobId = TEKCO_AnonymizationChainRunner.startNext(ctx);
        TEKCO_AnonymizationAuditLog__c running = [
            SELECT TEKCO_JobId__c FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'The step starts a batch');
        System.assertEquals(String.valueOf(jobId), running.TEKCO_JobId__c,
            'Each step records its job, so the concurrency guard sees the run as live');
    }
}
