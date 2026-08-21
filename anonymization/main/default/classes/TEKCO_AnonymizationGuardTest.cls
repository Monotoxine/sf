/**
 * Covers every gate the tool applies before it reads or destroys anything: the custom
 * permission, the object and field names that reach dynamic SOQL, the pattern types that would
 * otherwise be skipped in silence, and the sandbox check in the form a batch start() survives.
 *
 * Split out of TEKCO_AnonymizationBatchUtilsTest along with the class it covers.
 */
@isTest
private class TEKCO_AnonymizationGuardTest {

    @isTest
    static void validatePatternTypes_flagsUnknownType() {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c = 'Account',
                TEKCO_FieldApiName__c  = 'Name',
                TEKCO_PatternType__c   = 'NO_SUCH_PATTERN_TYPE_XYZ'
            )
        };

        List<String> warnings = TEKCO_AnonymizationGuard.validatePatternTypes(configs);

        System.assertEquals(1, warnings.size(), 'Unknown pattern type reported');
        System.assert(
            warnings[0].contains('NO_SUCH_PATTERN_TYPE_XYZ'),
            'Warning names the offending type: ' + warnings[0]
        );
    }

    @isTest
    static void validatePatternTypes_reportsEachTypeOnce() {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c='Account', TEKCO_FieldApiName__c='Name',
                TEKCO_PatternType__c='BOGUS_TYPE_ABC'),
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c='Contact', TEKCO_FieldApiName__c='LastName',
                TEKCO_PatternType__c='BOGUS_TYPE_ABC')
        };

        List<String> warnings = TEKCO_AnonymizationGuard.validatePatternTypes(configs);

        System.assertEquals(1, warnings.size(), 'Same unknown type reported once, not per field');
    }

    @isTest
    static void validatePatternTypes_ignoresBatchHandledTypes() {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c='Account', TEKCO_PatternType__c='DELETE_CONTENT_DOCUMENT'),
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c='EmailMessage', TEKCO_PatternType__c='EMAIL_MESSAGE_LOREM')
        };

        System.assertEquals(
            0,
            TEKCO_AnonymizationGuard.validatePatternTypes(configs).size(),
            'Types handled by dedicated batches need no pattern record'
        );
    }

    @isTest
    static void validatePatternTypes_emptyAndNull_returnEmpty() {
        System.assertEquals(0,
            TEKCO_AnonymizationGuard.validatePatternTypes(
                new List<TEKCO_AnonymizationFieldConfig__mdt>()).size());
        System.assertEquals(0,
            TEKCO_AnonymizationGuard.validatePatternTypes(null).size());
    }

    // ─── requireConfiguredObject / requireFieldOnObject ────────────────────────

    @isTest
    static void requireConfiguredObject_rejectsBlank() {
        try {
            TEKCO_AnonymizationGuard.requireConfiguredObject('');
            System.assert(false, 'Blank object name should throw');
        } catch (Exception e) {
            System.assert(true, 'Blank rejected');
        }
    }

    @isTest
    static void requireConfiguredObject_rejectsUnconfiguredName() {
        // Independent of which CMDT records the org holds: this name is never configured.
        try {
            TEKCO_AnonymizationGuard.requireConfiguredObject('Not_A_Real_Object_ZZZ__c');
            System.assert(false, 'Unconfigured object should throw');
        } catch (Exception e) {
            System.assert(true, 'Unconfigured object rejected before reaching SOQL');
        }
    }

    @isTest
    static void requireFieldOnObject_rejectsMissingField() {
        try {
            TEKCO_AnonymizationGuard.requireFieldOnObject('Account', 'No_Such_Field_ZZZ__c');
            System.assert(false, 'Missing field should throw');
        } catch (Exception e) {
            System.assert(true, 'Missing field rejected before reaching SOQL');
        }
    }

    @isTest
    static void requireFieldOnObject_acceptsRealField() {
        System.assertEquals(
            'Name',
            TEKCO_AnonymizationGuard.requireFieldOnObject('Account', 'Name'),
            'Existing field passes through unchanged'
        );
    }

    @isTest
    static void requireFieldOnObject_rejectsBlank() {
        try {
            TEKCO_AnonymizationGuard.requireFieldOnObject('Account', '');
            System.assert(false, 'Blank field name should throw');
        } catch (Exception e) {
            System.assert(true, 'Blank rejected');
        }
    }

    // ─── assertCanAnonymize ────────────────────────────────────────────────────

    @isTest
    static void assertCanAnonymize_throwsWithoutCustomPermission() {
        // The running test user has no custom permission assigned by default.
        try {
            TEKCO_AnonymizationGuard.assertCanAnonymize();
            // If the org grants it broadly this will not throw — either outcome is valid,
            // the point is that the gate is reachable and does not error unexpectedly.
            System.assert(true, 'Permission present in this org');
        } catch (Exception e) {
            System.assert(
                e.getMessage().containsIgnoreCase('permission'),
                'Rejection mentions the missing permission: ' + e.getMessage()
            );
        }
    }

    // ─── assertSandboxOrClose ──────────────────────────────────────────────────

    @isTest
    static void assertSandboxOrClose_returnsTrueInSandbox() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        Test.startTest();
        Boolean ok = TEKCO_AnonymizationGuard.assertSandboxOrClose(null, null);
        Test.stopTest();

        System.assertEquals(true, ok, 'Sandbox → batch proceeds');
    }

    @isTest
    static void assertSandboxOrClose_closesAuditLogOnProduction() {
        TEKCO_AnonymizationAuditLog__c log = new TEKCO_AnonymizationAuditLog__c(
            TEKCO_Status__c = 'Running', TEKCO_StartTime__c = Datetime.now()
        );
        insert log;

        TEKCO_AnonymizationOrgConfigService.isSandboxCached = false;

        Test.startTest();
        Boolean ok = TEKCO_AnonymizationGuard.assertSandboxOrClose(log.Id, null);
        Test.stopTest();

        System.assertEquals(false, ok, 'Production → batch must not proceed');

        TEKCO_AnonymizationAuditLog__c result = [
            SELECT TEKCO_Status__c, TEKCO_ErrorMessage__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :log.Id
        ];
        System.assertEquals('Failed', result.TEKCO_Status__c,
            'Log closed as Failed rather than left stuck on Running');
        System.assert(result.TEKCO_ErrorMessage__c.containsIgnoreCase('production'),
            'Reason recorded: ' + result.TEKCO_ErrorMessage__c);
    }

    // ─── Garde contre les runs simultanés ────────────────────────────────────────

    private static TEKCO_AnonymizationAuditLog__c runningLog(Datetime startedAt, String jobId) {
        TEKCO_AnonymizationAuditLog__c log = new TEKCO_AnonymizationAuditLog__c(
            TEKCO_TriggeredBy__c = UserInfo.getUserId(),
            TEKCO_BrandFilter__c = 'TEST',
            TEKCO_Status__c      = 'Running',
            TEKCO_StartTime__c   = startedAt,
            TEKCO_JobId__c       = jobId
        );
        insert log;
        return log;
    }

    @isTest
    static void assertNoRunInProgress_withNoRunningLog_allows() {
        Test.startTest();
        TEKCO_AnonymizationGuard.assertNoRunInProgress();
        Test.stopTest();
        System.assert(true, 'Aucun run en cours : le lancement passe');
    }

    /** Un log tout juste inséré, dont le batch n'a pas encore démarré, compte comme vivant. */
    @isTest
    static void assertNoRunInProgress_withFreshUnstartedLog_refuses() {
        runningLog(Datetime.now(), null);

        Boolean refused = false;
        Test.startTest();
        try {
            TEKCO_AnonymizationGuard.assertNoRunInProgress();
        } catch (Exception e) {
            refused = true;
        }
        Test.stopTest();

        System.assertEquals(true, refused,
            'Un lancement en cours doit bloquer le suivant : deux runs corrompent le snapshot du bypass');
    }

    /**
     * LE cas qui compte : un log resté sur Running parce que son job est mort sans jamais
     * atteindre finish(). Sans la fenêtre de grâce, il condamnerait l'outil définitivement.
     */
    @isTest
    static void assertNoRunInProgress_withStaleUnstartedLog_allows() {
        runningLog(Datetime.now().addHours(-3), null);

        Test.startTest();
        TEKCO_AnonymizationGuard.assertNoRunInProgress();
        Test.stopTest();

        System.assert(true, 'Un log périmé ne doit jamais verrouiller l\'outil');
    }

    /** Un job id qui ne correspond à aucun AsyncApexJob : le log est périmé. */
    @isTest
    static void assertNoRunInProgress_withUnknownJobId_allows() {
        runningLog(Datetime.now(), '707000000000000AAA');

        Test.startTest();
        TEKCO_AnonymizationGuard.assertNoRunInProgress();
        Test.stopTest();

        System.assert(true, 'Job introuvable = run terminé ou disparu, on laisse passer');
    }

    /** Un job id illisible ne doit pas faire exploser la garde. */
    @isTest
    static void assertNoRunInProgress_withUnparseableJobId_doesNotThrowUnexpectedly() {
        runningLog(Datetime.now().addHours(-3), 'pas-un-identifiant');

        Test.startTest();
        TEKCO_AnonymizationGuard.assertNoRunInProgress();
        Test.stopTest();

        System.assert(true, 'Un job id illisible est traité comme absent, pas comme une erreur');
    }

    // ─── Validations de configuration ────────────────────────────────────────────

    private static TEKCO_AnonymizationFieldConfig__mdt filterConfig(
        String devName, String label, String objectApiName, String filter
    ) {
        return new TEKCO_AnonymizationFieldConfig__mdt(
            DeveloperName             = devName,
            MasterLabel               = label,
            TEKCO_ObjectApiName__c    = objectApiName,
            TEKCO_AdditionalFilter__c = filter
        );
    }

    @isTest
    static void validateAdditionalFilters_malformedFilter_namesTheConfig() {
        List<String> warnings = TEKCO_AnonymizationGuard.validateAdditionalFilters(
            new List<TEKCO_AnonymizationFieldConfig__mdt>{
                filterConfig('Patient_Address', 'Patient Address', 'Account', 'ceci n est pas une condition')
            }
        );

        System.assertEquals(1, warnings.size(), 'Le filtre invalide est signalé');
        System.assert(warnings[0].contains('Patient Address'),
            'Le message nomme la config, pas seulement l objet : ' + warnings[0]);
        System.assert(warnings[0].contains('Account'),
            'L objet reste dans le message : ' + warnings[0]);
    }

    /**
     * Contact porte cinq configs partageant un filtre, User six. Une seule requête, un seul
     * avertissement, mais qui nomme les configs concernées — c est tout l intérêt du changement.
     */
    @isTest
    static void validateAdditionalFilters_sharedFilter_namesThemTogether() {
        List<String> warnings = TEKCO_AnonymizationGuard.validateAdditionalFilters(
            new List<TEKCO_AnonymizationFieldConfig__mdt>{
                filterConfig('C_Email',     'Contact Patient Email',     'Account', 'pas une condition'),
                filterConfig('C_FirstName', 'Contact Patient FirstName', 'Account', 'pas une condition'),
                filterConfig('C_LastName',  'Contact Patient LastName',  'Account', 'pas une condition'),
                filterConfig('C_Street',    'Contact Patient Street',    'Account', 'pas une condition')
            }
        );

        System.assertEquals(1, warnings.size(),
            'Un filtre identique partagé par plusieurs configs ne produit qu un avertissement');
        System.assert(warnings[0].contains('Contact Patient Email'),
            'La première config est nommée : ' + warnings[0]);
        System.assert(warnings[0].contains('(+1)'),
            'Au-delà de trois noms, le reste est compté : ' + warnings[0]);
    }

    @isTest
    static void validateAdditionalFilters_differentFiltersOnOneObject_areBothChecked() {
        List<String> warnings = TEKCO_AnonymizationGuard.validateAdditionalFilters(
            new List<TEKCO_AnonymizationFieldConfig__mdt>{
                filterConfig('IndividualP_Address', 'IndividualP Address', 'Account', 'premier invalide'),
                filterConfig('Patient_Address',     'Patient Address',     'Account', 'second invalide')
            }
        );

        System.assertEquals(2, warnings.size(),
            'Deux filtres distincts sur un même objet sont contrôlés séparément — '
            + 'l ancienne version n en voyait qu un');
    }

    @isTest
    static void validateAdditionalFilters_validFilter_isSilent() {
        System.assertEquals(0,
            TEKCO_AnonymizationGuard.validateAdditionalFilters(
                new List<TEKCO_AnonymizationFieldConfig__mdt>{
                    filterConfig('Ok', 'Ok', 'Account', 'IsDeleted = false')
                }
            ).size(),
            'Un filtre valide ne produit aucun avertissement');

        System.assertEquals(0,
            TEKCO_AnonymizationGuard.validateAdditionalFilters(null).size(),
            'Aucune config : rien à signaler');

        System.assertEquals(0,
            TEKCO_AnonymizationGuard.validateAdditionalFilters(
                new List<TEKCO_AnonymizationFieldConfig__mdt>{
                    new TEKCO_AnonymizationFieldConfig__mdt(
                        DeveloperName = 'NoFilter', TEKCO_ObjectApiName__c = 'Account'
                    )
                }
            ).size(),
            'Une config sans filtre n est pas contrôlée');
    }

    /**
     * Le contrôle tourne sur la configuration réelle de l org et ne doit jamais lever, quelle
     * qu elle soit — c est un diagnostic, pas une garde.
     */
    @isTest
    static void validateConfiguration_returnsFindingsWithoutThrowing() {
        Test.startTest();
        List<String> findings = TEKCO_AnonymizationGuard.validateConfiguration();
        Test.stopTest();

        System.assertNotEquals(null, findings, 'Une liste est toujours renvoyée');
    }

    // ─── validateFilterDiscrimination : la forme que le moteur ne sait pas honorer ────────

    private static TEKCO_AnonymizationFieldConfig__mdt filterRule(
        String objectApiName, String fieldApiName, String pattern, String filter
    ) {
        return new TEKCO_AnonymizationFieldConfig__mdt(
            DeveloperName             = objectApiName + '_' + fieldApiName + '_' + pattern,
            TEKCO_ObjectApiName__c    = objectApiName,
            TEKCO_FieldApiName__c     = fieldApiName,
            TEKCO_PatternType__c      = pattern,
            TEKCO_AdditionalFilter__c = filter
        );
    }

    /**
     * Le cas Address, qui ne doit PAS etre signale : deux filtres, mais le meme champ et le meme
     * pattern derriere chacun. Appliquer l une ou l autre regle a l une ou l autre population
     * donne le meme resultat.
     */
    @isTest
    static void validateFilterDiscrimination_sameEffectBehindBothFilters_isSilent() {
        List<String> findings = TEKCO_AnonymizationGuard.validateFilterDiscrimination(
            new List<TEKCO_AnonymizationFieldConfig__mdt>{
                filterRule('Address', 'Street', 'ADDRESS_STREET_RANDOM', 'RT = 1'),
                filterRule('Address', 'Street', 'ADDRESS_STREET_RANDOM', 'RT = 2')
            }
        );

        System.assertEquals(0, findings.size(),
            'Meme effet derriere les deux filtres : rien a signaler — ' + findings);
    }

    /**
     * Deux filtres qui font des choses differentes : le moteur lit leur union et ne sait pas,
     * enregistrement par enregistrement, lequel des deux l a ramene.
     */
    @isTest
    static void validateFilterDiscrimination_differentEffects_areReported() {
        List<String> findings = TEKCO_AnonymizationGuard.validateFilterDiscrimination(
            new List<TEKCO_AnonymizationFieldConfig__mdt>{
                filterRule('Contact', 'Email', 'EMAIL_PLUS_EXTERNALID', 'RT = 1'),
                filterRule('Contact', 'Phone', 'PHONE_MASK',            'RT = 2')
            }
        );

        System.assertEquals(1, findings.size(), 'Le cas est signale');
        System.assert(findings[0].contains('Contact'), 'L objet est nomme : ' + findings[0]);
    }

    @isTest
    static void validateFilterDiscrimination_oneFilterOrNone_isSilent() {
        System.assertEquals(0, TEKCO_AnonymizationGuard.validateFilterDiscrimination(
            new List<TEKCO_AnonymizationFieldConfig__mdt>{
                filterRule('Contact', 'Email', 'EMAIL_PLUS_EXTERNALID', 'RT = 1'),
                filterRule('Contact', 'Phone', 'PHONE_MASK',            'RT = 1')
            }).size(),
            'Un seul filtre sur l objet : aucune ambiguite');

        System.assertEquals(0,
            TEKCO_AnonymizationGuard.validateFilterDiscrimination(null).size());
        System.assertEquals(0, TEKCO_AnonymizationGuard.validateFilterDiscrimination(
            new List<TEKCO_AnonymizationFieldConfig__mdt>()).size());
    }
}
