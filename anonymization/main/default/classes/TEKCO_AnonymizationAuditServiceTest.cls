@isTest
private class TEKCO_AnonymizationAuditServiceTest {

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

    @isTest
    static void finalize_noFailures_marksSuccess() {
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        TEKCO_AnonymizationAuditService.finalize(log.Id, 10, 0, 2, 3, new List<String>());
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c, TEKCO_RecordsProcessed__c, TEKCO_RecordsFailed__c,
                   TEKCO_DocumentsDeleted__c, TEKCO_HistoryRecordsDeleted__c,
                   TEKCO_EndTime__c, TEKCO_ErrorMessage__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertEquals('Success', result.TEKCO_Status__c, 'No failures → Success');
        System.assertEquals(10, result.TEKCO_RecordsProcessed__c);
        System.assertEquals(0,  result.TEKCO_RecordsFailed__c);
        System.assertEquals(2,  result.TEKCO_DocumentsDeleted__c);
        System.assertEquals(3,  result.TEKCO_HistoryRecordsDeleted__c);
        System.assertNotEquals(null, result.TEKCO_EndTime__c, 'End time stamped');
        System.assertEquals(null, result.TEKCO_ErrorMessage__c, 'No errors → null message');
    }

    @isTest
    static void finalize_withFailures_marksPartial() {
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        TEKCO_AnonymizationAuditService.finalize(
            log.Id, 8, 2, 0, 0, new List<String>{ 'err one', 'err two' }
        );
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c, TEKCO_RecordsFailed__c, TEKCO_ErrorMessage__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertEquals('Partial', result.TEKCO_Status__c, 'Failures → Partial');
        System.assertEquals(2, result.TEKCO_RecordsFailed__c);
        System.assert(result.TEKCO_ErrorMessage__c.contains('err one'), 'Errors joined into message');
        System.assert(result.TEKCO_ErrorMessage__c.contains('err two'));
    }

    @isTest
    static void markRunning_keepsRunningAndLeavesEndTimeNull() {
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        TEKCO_AnonymizationAuditService.markRunning(log.Id, 5, 1, new List<String>{ 'partial err' });
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c, TEKCO_RecordsProcessed__c, TEKCO_RecordsFailed__c,
                   TEKCO_EndTime__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertEquals('Running', result.TEKCO_Status__c, 'Still running mid-chain');
        System.assertEquals(5, result.TEKCO_RecordsProcessed__c, 'Progress persisted');
        System.assertEquals(1, result.TEKCO_RecordsFailed__c);
        System.assertEquals(null, result.TEKCO_EndTime__c, 'Chain not finished → no end time');
    }

    @isTest
    static void closeFailed_marksFailedAndAppendsChainError() {
        TEKCO_AnonymizationAuditLog__c log = newLog();

        Test.startTest();
        TEKCO_AnonymizationAuditService.closeFailed(
            log.Id, 3, 1, 0, 0, new List<String>{ 'record err' }, 'chain blew up'
        );
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c, TEKCO_EndTime__c, TEKCO_ErrorMessage__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertEquals('Failed', result.TEKCO_Status__c);
        System.assertNotEquals(null, result.TEKCO_EndTime__c);
        System.assert(result.TEKCO_ErrorMessage__c.contains('record err'), 'Record errors kept');
        System.assert(result.TEKCO_ErrorMessage__c.contains('chain blew up'), 'Chain error appended');
    }

    @isTest
    static void persist_nullLogId_isNoOp() {
        // Must not throw — batches call this with a null id when no audit log was created.
        Test.startTest();
        TEKCO_AnonymizationAuditService.finalize(null, 1, 0, 0, 0, new List<String>());
        TEKCO_AnonymizationAuditService.markRunning(null, 1, 0, new List<String>());
        TEKCO_AnonymizationAuditService.closeFailed(null, 1, 0, 0, 0, new List<String>(), 'x');
        Test.stopTest();

        System.assert(true, 'Null audit log id handled without exception');
    }
}
