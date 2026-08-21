/**
 * Le scheduler avale volontairement toute exception : un Schedulable qui lève ne laisse rien
 * qu'un administrateur puisse relire. Ces tests vérifient donc qu'il se planifie et s'exécute
 * sans jamais faire échouer le job, quelle que soit la configuration de l'org.
 */
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

    /**
     * Sur une org de production, le lancement doit être refusé — et refusé silencieusement,
     * sans faire échouer le job planifié.
     */
    @isTest
    static void scheduler_onProduction_isRefusedQuietly() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = false;
        Integer logsBefore = [SELECT COUNT() FROM TEKCO_AnonymizationAuditLog__c];

        Test.startTest();
        new TEKCO_AnonymizationScheduler().execute(null);
        Test.stopTest();

        System.assertEquals(logsBefore, [SELECT COUNT() FROM TEKCO_AnonymizationAuditLog__c],
            'Aucun run ouvert sur une org de production');
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
