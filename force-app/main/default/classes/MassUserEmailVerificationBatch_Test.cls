@IsTest
private class MassUserEmailVerificationBatch_Test {

    private static final String TEST_DOMAIN = 'masstest.example.com';

    private static User buildUser(String alias) {
        Profile p = [SELECT Id FROM Profile WHERE UserType = 'Standard' LIMIT 1];
        String stamp = alias + System.now().getTime();
        return new User(
            Alias = alias,
            Email = stamp + '@' + TEST_DOMAIN,
            EmailEncodingKey = 'UTF-8',
            LastName = 'MassEmailTest',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'Europe/Paris',
            Username = stamp + '@masstest.example.com'
        );
    }

    @IsTest
    static void dryRunCountsTargetsWithoutSending() {
        User u = buildUser('mvt1');
        insert u;

        MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();
        batch.dryRun = true;
        batch.onlyUnverified = false;
        batch.emailDomainFilter = TEST_DOMAIN;

        Test.startTest();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        System.assertEquals(0, batch.failedCount, 'Le mode simulation ne doit produire aucun echec.');
        System.assert(batch.sentCount >= 1, 'L utilisateur de test doit etre compte comme cible.');
    }

    @IsTest
    static void explicitUserIdsTakePrecedenceOverOtherFilters() {
        User target = buildUser('mvt2');
        User other = buildUser('mvt3');
        insert new List<User>{ target, other };

        MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();
        batch.dryRun = true;
        batch.onlyUnverified = false;
        batch.userIds = new Set<Id>{ target.Id };
        // Volontairement incoherent avec userIds : doit etre ignore.
        batch.emailDomainFilter = 'domaine-qui-ne-matche-rien.example';

        Test.startTest();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        System.assertEquals(
            1,
            batch.sentCount,
            'Une selection explicite par Id doit primer sur emailDomainFilter.'
        );
    }

    @IsTest
    static void createdSinceExcludesOlderUsers() {
        User u = buildUser('mvt4');
        insert u;

        MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();
        batch.dryRun = true;
        batch.onlyUnverified = false;
        batch.emailDomainFilter = TEST_DOMAIN;
        batch.createdSince = System.now().addDays(1);

        Test.startTest();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        System.assertEquals(
            0,
            batch.sentCount,
            'Une borne createdSince dans le futur ne doit retenir aucun utilisateur.'
        );
    }

    @IsTest
    static void invalidAddressesAreInScopeByDefault() {
        User u = buildUser('mvt5');
        u.Email = u.Email + '.invalid';
        insert u;

        MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();
        batch.dryRun = true;
        batch.onlyUnverified = false;
        batch.emailDomainFilter = TEST_DOMAIN + '.invalid';

        Test.startTest();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        System.assertEquals(
            1,
            batch.sentCount,
            'Par defaut les adresses suffixees restent dans le scope.'
        );
    }

    @IsTest
    static void invalidAddressesCanBeExcluded() {
        User u = buildUser('mvt7');
        u.Email = u.Email + '.invalid';
        insert u;

        MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();
        batch.dryRun = true;
        batch.onlyUnverified = false;
        batch.includeInvalidAddresses = false;
        // Meme filtre que le test precedent : seul le flag change.
        batch.emailDomainFilter = TEST_DOMAIN + '.invalid';

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
        User u = buildUser('mvt6');
        insert u;

        MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();
        batch.dryRun = true;
        batch.onlyUnverified = true;
        batch.emailDomainFilter = TEST_DOMAIN;

        Test.startTest();
        Database.executeBatch(batch, 50);
        Test.stopTest();

        System.assertEquals(
            0,
            batch.failedCount,
            'Le filtre des non verifies ne doit pas provoquer d echec.'
        );
    }
}
