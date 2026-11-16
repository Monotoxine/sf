/** Le scheduler ne fait jamais échouer le job ; un refus est journalisé en Refused. */
@isTest
private class TEKCO_AnonymizationSchedulerTest {

    @isTest
    static void scheduler_runsWithoutThrowing() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        Test.startTest();
        new TEKCO_AnonymizationScheduler().execute(null);
        Test.stopTest();

        System.assert(true, 'Le scheduler ne doit jamais propager d exception');
    }

    /** Production : aucun run ouvert, une ligne Refused. */
    @isTest
    static void scheduler_onProduction_isRefusedAndLogged() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = false;

        Test.startTest();
        new TEKCO_AnonymizationScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(0, [
            SELECT COUNT() FROM TEKCO_AnonymizationAuditLog__c WHERE TEKCO_Status__c = 'Running'
        ], 'Aucun run ouvert sur une org de production');
        List<TEKCO_AnonymizationAuditLog__c> refused = [
            SELECT TEKCO_ErrorMessage__c, TEKCO_RunMode__c, TEKCO_EndTime__c
            FROM TEKCO_AnonymizationAuditLog__c
            WHERE TEKCO_Status__c = :TEKCO_AnonymizationScheduler.STATUS_REFUSED
        ];
        System.assertEquals(1, refused.size(), 'Le refus est journalisé une fois');
        System.assert(refused[0].TEKCO_ErrorMessage__c.startsWith('Scheduled run not started: '),
            'La raison est lisible : ' + refused[0].TEKCO_ErrorMessage__c);
        System.assertEquals('BY_CRITERIA', refused[0].TEKCO_RunMode__c,
            'La ligne apparaît dans l onglet By Criteria');
        System.assertNotEquals(null, refused[0].TEKCO_EndTime__c, 'Un refus est clos d emblée');
    }

    /** Run en cours : refusé, le run en cours n'est pas touché. */
    @isTest
    static void scheduler_whileARunIsInProgress_isRefusedAndLogged() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        TEKCO_AnonymizationAuditLog__c running = new TEKCO_AnonymizationAuditLog__c(
            TEKCO_Status__c = 'Running', TEKCO_StartTime__c = Datetime.now(),
            TEKCO_RunMode__c = 'BY_CRITERIA'
        );
        insert running;

        Test.startTest();
        new TEKCO_AnonymizationScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT() FROM TEKCO_AnonymizationAuditLog__c WHERE TEKCO_Status__c = 'Running'
        ], 'Seul le run déjà en cours est Running');
        System.assertEquals(1, [
            SELECT COUNT() FROM TEKCO_AnonymizationAuditLog__c
            WHERE TEKCO_Status__c = :TEKCO_AnonymizationScheduler.STATUS_REFUSED
        ], 'Le scheduler refusé laisse une ligne Refused');
    }

    /** La portée restreinte est reprise dans la ligne d'audit. */
    @isTest
    static void scheduler_narrowedScope_isCarriedToTheAuditLog() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = false;

        Test.startTest();
        new TEKCO_AnonymizationScheduler(
            new List<String>{ 'ACCCO_Patient' }, new List<String>{ 'Account' }, new List<String>{ 'IT_VIT' }
        ).execute(null);
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c log = [
            SELECT TEKCO_ObjectApiName__c, TEKCO_BrandFilter__c FROM TEKCO_AnonymizationAuditLog__c
            WHERE TEKCO_Status__c = :TEKCO_AnonymizationScheduler.STATUS_REFUSED
        ];
        System.assertEquals('Account', log.TEKCO_ObjectApiName__c, 'Les objets choisis sont tracés');
        System.assertEquals('IT_VIT', log.TEKCO_BrandFilter__c, 'Les marques choisies sont tracées');
    }

    @isTest
    static void scheduler_canBeScheduled() {
        Test.startTest();
        String jobId = System.schedule(
            'TEKCO Anonymization Test', '0 0 2 * * ?', new TEKCO_AnonymizationScheduler()
        );
        Test.stopTest();

        System.assertNotEquals(null, jobId, 'La classe est bien planifiable');
        System.assertEquals(1, [
            SELECT COUNT() FROM CronTrigger WHERE Id = :jobId
        ], 'Le déclencheur est enregistré');
    }
}
