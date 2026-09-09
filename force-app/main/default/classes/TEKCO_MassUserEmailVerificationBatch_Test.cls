@IsTest
private class TEKCO_MassUserEmailVerificationBatch_Test {
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

    TEKCO_MassUserEmailVerificationBatch batch = new TEKCO_MassUserEmailVerificationBatch();
    batch.dryRun = true;
    batch.onlyUnverified = false;
    batch.emailDomainFilter = TEST_DOMAIN;

    Test.startTest();
    Database.executeBatch(batch, 50);
    Test.stopTest();

    System.assertEquals(
      0,
      batch.failedCount,
      'A dry run must produce no failure.'
    );
    System.assert(
      batch.sentCount >= 1,
      'The test user must be counted as a target.'
    );
  }

  @IsTest
  static void explicitUserIdsTakePrecedenceOverOtherFilters() {
    User target = buildUser('mvt2');
    User other = buildUser('mvt3');
    insert new List<User>{ target, other };

    TEKCO_MassUserEmailVerificationBatch batch = new TEKCO_MassUserEmailVerificationBatch();
    batch.dryRun = true;
    batch.onlyUnverified = false;
    batch.userIds = new Set<Id>{ target.Id };
    // Deliberately inconsistent with userIds: it must be ignored.
    batch.emailDomainFilter = 'domain-that-matches-nothing.example';

    Test.startTest();
    Database.executeBatch(batch, 50);
    Test.stopTest();

    System.assertEquals(
      1,
      batch.sentCount,
      'An explicit id selection must win over emailDomainFilter.'
    );
  }

  @IsTest
  static void createdSinceExcludesOlderUsers() {
    User u = buildUser('mvt4');
    insert u;

    TEKCO_MassUserEmailVerificationBatch batch = new TEKCO_MassUserEmailVerificationBatch();
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
      'A createdSince bound in the future must retain no user.'
    );
  }

  @IsTest
  static void invalidAddressesAreInScopeByDefault() {
    User u = buildUser('mvt5');
    u.Email = u.Email + '.invalid';
    insert u;

    TEKCO_MassUserEmailVerificationBatch batch = new TEKCO_MassUserEmailVerificationBatch();
    batch.dryRun = true;
    batch.onlyUnverified = false;
    batch.emailDomainFilter = TEST_DOMAIN + '.invalid';

    Test.startTest();
    Database.executeBatch(batch, 50);
    Test.stopTest();

    System.assertEquals(
      1,
      batch.sentCount,
      'Suffixed addresses stay in scope by default.'
    );
  }

  @IsTest
  static void invalidAddressesCanBeExcluded() {
    User u = buildUser('mvt7');
    u.Email = u.Email + '.invalid';
    insert u;

    TEKCO_MassUserEmailVerificationBatch batch = new TEKCO_MassUserEmailVerificationBatch();
    batch.dryRun = true;
    batch.onlyUnverified = false;
    batch.includeInvalidAddresses = false;
    // Same filter as the previous test: only the flag differs.
    batch.emailDomainFilter = TEST_DOMAIN + '.invalid';

    Test.startTest();
    Database.executeBatch(batch, 50);
    Test.stopTest();

    System.assertEquals(
      0,
      batch.sentCount,
      'includeInvalidAddresses = false must exclude suffixed addresses.'
    );
  }

  @IsTest
  static void passwordResetIsOffByDefault() {
    TEKCO_MassUserEmailVerificationBatch batch = new TEKCO_MassUserEmailVerificationBatch();

    System.assertEquals(
      false,
      batch.sendPasswordReset,
      'A password reset invalidates existing passwords: it must stay ' +
      'an explicit opt-in.'
    );
    System.assertEquals(
      true,
      batch.sendVerification,
      'Sending the verification link is the default action.'
    );
  }

  @IsTest
  static void dryRunCountsPasswordResetsWithoutApplyingThem() {
    User u = buildUser('mvt8');
    insert u;

    TEKCO_MassUserEmailVerificationBatch batch = new TEKCO_MassUserEmailVerificationBatch();
    batch.dryRun = true;
    batch.onlyUnverified = false;
    batch.sendPasswordReset = true;
    batch.emailDomainFilter = TEST_DOMAIN;

    Test.startTest();
    Database.executeBatch(batch, 10);
    Test.stopTest();

    System.assert(
      batch.resetCount >= 1,
      'A dry run must count the planned resets.'
    );
    System.assertEquals(
      0,
      batch.resetFailedCount,
      'A dry run must produce no reset failure.'
    );
  }

  @IsTest
  static void passwordResetInProductionIsGuarded() {
    TEKCO_MassUserEmailVerificationBatch batch = new TEKCO_MassUserEmailVerificationBatch();

    System.assertEquals(
      false,
      batch.allowPasswordResetInProduction,
      'The production guardrail must be on by default: under SSO a bulk ' +
      'reset mails out unusable credentials.'
    );

    // The refusal itself depends on Organization.IsSandbox, which cannot be
    // simulated in a test; only the guardrail default is assertable here.
    Boolean isSandbox = [SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox;
    System.debug('Org is a sandbox: ' + isSandbox);
  }

  @IsTest
  static void unverifiedFilterDoesNotBreakExecution() {
    User u = buildUser('mvt6');
    insert u;

    TEKCO_MassUserEmailVerificationBatch batch = new TEKCO_MassUserEmailVerificationBatch();
    batch.dryRun = true;
    batch.onlyUnverified = true;
    batch.emailDomainFilter = TEST_DOMAIN;

    Test.startTest();
    Database.executeBatch(batch, 50);
    Test.stopTest();

    System.assertEquals(
      0,
      batch.failedCount,
      'The unverified filter must not cause a failure.'
    );
  }
}
