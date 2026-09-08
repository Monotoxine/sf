@IsTest
private class MassUserEmailVerificationBatch_Test {

    private static User buildUser(String alias, String email) {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        return new User(
            Alias = alias,
            Email = email,
            EmailEncodingKey = 'UTF-8',
            LastName = 'MassEmailTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Europe/Paris',
            Username = alias + System.now().getTime() + '@masstest.example.com'
        );
    }

    @IsTest
    static void dryRunCountsTargetsWithoutSending() {
        User u = buildUser('mvt1', 'mvt1@masstest.example.com');
        insert u;

        MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();
        batch.dryRun = true;
        batch.onlyUnverified = false;
        batch.emailDomainFilter = 'masstest.example.com';

        Test.startTest();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        System.assertEquals(0, batch.failedCount, 'Le mode simulation ne doit produire aucun echec.');
        System.assert(batch.sentCount >= 1, 'L utilisateur de test doit etre compte comme cible.');
    }

    @IsTest
    static void invalidEmailsAreInScopeByDefault() {
        User invalidUser = buildUser('mvt2', 'mvt2@masstest.example.com.invalid');
        insert invalidUser;

        MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();
        batch.dryRun = true;
        batch.onlyUnverified = false;
        batch.emailDomainFilter = 'masstest.example.com.invalid';

        Test.startTest();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        System.assert(
            batch.sentCount >= 1,
            'Par defaut une adresse en .invalid doit rester dans le scope : '
                + 'l action Verify peut retirer le suffixe cote org.'
        );
    }

    @IsTest
    static void invalidEmailsCanBeExcludedExplicitly() {
        User invalidUser = buildUser('mvt4', 'mvt4@masstest.example.com.invalid');
        insert invalidUser;

        MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();
        batch.dryRun = true;
        batch.onlyUnverified = false;
        batch.includeInvalidAddresses = false;
        batch.emailDomainFilter = 'masstest.example.com.invalid';

        Test.startTest();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        System.assertEquals(
            0,
            batch.sentCount,
            'includeInvalidAddresses = false doit exclure les adresses suffixees.'
        );
    }

    @IsTest
    static void unverifiedFilterDoesNotBreakExecution() {
        User u = buildUser('mvt3', 'mvt3@masstest.example.com');
        insert u;

        MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();
        batch.dryRun = true;
        batch.onlyUnverified = true;
        batch.emailDomainFilter = 'masstest.example.com';

        Test.startTest();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        // Le total traite doit rester coherent, que TwoFactorMethodsInfo soit
        // lisible ou non dans le contexte de test.
        System.assertEquals(
            0,
            batch.failedCount,
            'Le filtre des non verifies ne doit pas provoquer d echec.'
        );
    }
}
