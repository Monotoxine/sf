/**
 * Covers what the launch service owns now that both tabs delegate to it: refusing an empty
 * scope before anything is touched, and opening a run correctly when there is work.
 *
 * Custom Metadata cannot be inserted in a test, so the config-dependent paths are exercised
 * against whatever the org actually declares, and the assertions are written to hold on any
 * org — TEKCO or Portugal.
 */
@isTest
private class TEKCO_AnonymizationLaunchServiceTest {

    /** First object carrying an active field-level config in THIS org, or null. */
    private static String anyConfiguredObject() {
        for (TEKCO_AnonymizationFieldConfig__mdt fc : [
            SELECT TEKCO_ObjectApiName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true
              AND TEKCO_PatternType__c != 'DELETE_CONTENT_DOCUMENT'
            LIMIT 1
        ]) {
            return fc.TEKCO_ObjectApiName__c;
        }
        return null;
    }

    private static TEKCO_AnonymizationLaunchService.LaunchRequest baseRequest() {
        TEKCO_AnonymizationLaunchService.LaunchRequest request =
            new TEKCO_AnonymizationLaunchService.LaunchRequest();
        request.brandFilterLabel   = 'TEST';
        request.objectsLabel       = 'TEST';
        request.nothingToDoMessage = 'Nothing to do for this scope.';
        return request;
    }

    /** Callers do request.excludedFieldKeys.addAll(...) directly — none of these may be null. */
    @isTest
    static void launchRequest_collectionsAreInitialised() {
        TEKCO_AnonymizationLaunchService.LaunchRequest request =
            new TEKCO_AnonymizationLaunchService.LaunchRequest();

        System.assertEquals(false, request.byId, 'By Criteria is the default');
        System.assertNotEquals(null, request.objectApiNames, 'objectApiNames initialised');
        System.assertNotEquals(null, request.selectedBrands, 'selectedBrands initialised');
        System.assertNotEquals(null, request.recordIdsByObject, 'recordIdsByObject initialised');
        System.assertNotEquals(null, request.excludedFieldKeys, 'excludedFieldKeys initialised');
        System.assertNotEquals(null, request.disabledHistoryFieldKeys,
            'disabledHistoryFieldKeys initialised');
    }

    /**
     * An object with no configuration resolves to no work. The launch must be refused, and —
     * this is the part that matters — refused BEFORE the bypass is raised, so no audit log is
     * opened and the org's automation is never left disabled with nothing to switch it back.
     */
    @isTest
    static void launch_withNothingToDo_throwsAndOpensNoRun() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        Integer logsBefore = [SELECT COUNT() FROM TEKCO_AnonymizationAuditLog__c];

        TEKCO_AnonymizationLaunchService.LaunchRequest request = baseRequest();
        request.objectApiNames = new List<String>{ 'No_Such_Configured_Object_ZZZ__c' };

        Boolean threw = false;
        Test.startTest();
        try {
            TEKCO_AnonymizationLaunchService.launch(request);
        } catch (Exception e) {
            threw = true;
        }
        Test.stopTest();

        System.assertEquals(true, threw, 'An empty scope is refused rather than started');
        System.assertEquals(logsBefore, [SELECT COUNT() FROM TEKCO_AnonymizationAuditLog__c],
            'No audit log opened for a run that never started');
    }

    /**
     * A real scope opens the run: audit log created, run mode recorded, chain handed over.
     * Only one Database.executeBatch may run per test, which this consumes.
     */
    @isTest
    static void launch_withConfiguredObject_opensRunAndRecordsMode() {
        String objectApiName = anyConfiguredObject();
        if (objectApiName == null) return;   // org without configuration: nothing to assert

        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        TEKCO_AnonymizationLaunchService.LaunchRequest request = baseRequest();
        request.byId             = false;
        request.objectApiNames   = new List<String>{ objectApiName };
        request.brandFilterLabel = 'ALL';
        request.objectsLabel     = objectApiName;

        Test.startTest();
        Id auditLogId = TEKCO_AnonymizationLaunchService.launch(request);
        Test.stopTest();

        System.assertNotEquals(null, auditLogId, 'The launch returns its audit log');

        TEKCO_AnonymizationAuditLog__c log = [
            SELECT TEKCO_RunMode__c, TEKCO_Status__c, TEKCO_ObjectApiName__c, TEKCO_TriggeredBy__c
            FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :auditLogId
        ];
        System.assertEquals('BY_CRITERIA', log.TEKCO_RunMode__c,
            'The mode is data on the log, not something inferred from the brand label');
        System.assertEquals(objectApiName, log.TEKCO_ObjectApiName__c, 'Scope recorded');
        System.assertEquals(UserInfo.getUserId(), log.TEKCO_TriggeredBy__c, 'Author recorded');
        System.assertNotEquals('Running', log.TEKCO_Status__c,
            'The chain reached a terminal state rather than being left hanging');
    }

    /** Same service, By ID mode: the run mode written to the log follows request.byId. */
    @isTest
    static void launch_byIdMode_recordsByIdOnTheLog() {
        String objectApiName = anyConfiguredObject();
        if (objectApiName == null) return;

        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        TEKCO_AnonymizationLaunchService.LaunchRequest request = baseRequest();
        request.byId              = true;
        request.objectApiNames    = new List<String>{ objectApiName };
        request.recordIdsByObject = new Map<String, List<Id>>{ objectApiName => new List<Id>() };
        request.brandFilterLabel  = 'BY_ID (0 record(s))';
        request.objectsLabel      = objectApiName;

        Test.startTest();
        Id auditLogId = TEKCO_AnonymizationLaunchService.launch(request);
        Test.stopTest();

        TEKCO_AnonymizationAuditLog__c log = [
            SELECT TEKCO_RunMode__c FROM TEKCO_AnonymizationAuditLog__c WHERE Id = :auditLogId
        ];
        System.assertEquals('BY_ID', log.TEKCO_RunMode__c, 'Mode taken from the request');
    }

    /**
     * A record-type selection that matches nothing still leaves the configs with no record type
     * of their own — those apply to every record type and must survive the filter.
     */
    @isTest
    static void launch_recordTypeFilter_keepsUnscopedConfigs() {
        String objectApiName = anyConfiguredObject();
        if (objectApiName == null) return;

        Integer unscoped = [
            SELECT COUNT() FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true AND TEKCO_ObjectApiName__c = :objectApiName
              AND TEKCO_RecordTypeDeveloperName__c = null
        ];
        if (unscoped == 0) return;   // this object is entirely record-type scoped

        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        TEKCO_AnonymizationLaunchService.LaunchRequest request = baseRequest();
        request.objectApiNames      = new List<String>{ objectApiName };
        request.selectedRecordTypes = new List<String>{ 'No_Such_RecordType_ZZZ' };
        request.objectsLabel        = objectApiName;

        Test.startTest();
        Id auditLogId = TEKCO_AnonymizationLaunchService.launch(request);
        Test.stopTest();

        System.assertNotEquals(null, auditLogId,
            'Configs with no record type of their own survive any record-type selection');
    }

    // ─── combineFilters : le perimetre d un objet est le OR de ses configs retenues ──────

    /**
     * Le cas Address. Deux configs, deux filtres exclusifs : l ancienne version n en gardait
     * qu un, au hasard de l ordre de la requete, et une des deux populations n etait jamais
     * anonymisee.
     */
    @isTest
    static void combineFilters_twoFiltersOnOneObject_areBothApplied() {
        Map<String, String> combined = TEKCO_AnonymizationLaunchService.combineFilters(
            new Map<String, Set<String>>{
                'Address' => new Set<String>{ 'A = 1', 'B = 2' }
            },
            new Set<String>()
        );

        String filter = combined.get('Address');
        System.assert(filter.contains('A = 1'), 'Le premier filtre est present : ' + filter);
        System.assert(filter.contains('B = 2'), 'Le second aussi : ' + filter);
        System.assert(filter.contains(' OR '), 'Les deux sont combines en OR : ' + filter);
    }

    /**
     * whereClause() joint les conditions avec AND, et AND lie plus fort que OR en SOQL. Sans
     * parentheses englobantes, "marque AND (A) OR (B)" se lit "(marque AND A) OR B" et attrape
     * des enregistrements hors du filtre de marque.
     */
    @isTest
    static void combineFilters_isParenthesisedAsAWhole() {
        String twoTerms = TEKCO_AnonymizationLaunchService.combineFilters(
            new Map<String, Set<String>>{ 'Address' => new Set<String>{ 'A = 1', 'B = 2' } },
            new Set<String>()
        ).get('Address');
        System.assert(twoTerms.startsWith('(') && twoTerms.endsWith(')'),
            'Expression englobee : ' + twoTerms);

        String oneTerm = TEKCO_AnonymizationLaunchService.combineFilters(
            new Map<String, Set<String>>{ 'Account' => new Set<String>{ 'X = 1 OR Y = 2' } },
            new Set<String>()
        ).get('Account');
        System.assert(oneTerm.startsWith('(') && oneTerm.endsWith(')'),
            'Un filtre unique est englobe lui aussi, il peut contenir son propre OR : ' + oneTerm);
    }

    /**
     * Une config retenue sans filtre s applique a tous les enregistrements de l objet :
     * restreindre la requete lui retirerait des enregistrements qu elle doit anonymiser.
     */
    @isTest
    static void combineFilters_anUnfilteredConfigLiftsTheRestriction() {
        Map<String, String> combined = TEKCO_AnonymizationLaunchService.combineFilters(
            new Map<String, Set<String>>{ 'Account' => new Set<String>{ 'A = 1' } },
            new Set<String>{ 'Account' }
        );

        System.assertEquals(null, combined.get('Account'),
            'Aucun filtre pour cet objet : il est lu en entier');
    }

    /**
     * Decocher un champ retire son terme du OR. C est ce qui remplace l ancien piege d ordre :
     * un terme retire d un OR ne peut que retrecir, jamais elargir.
     */
    @isTest
    static void combineFilters_droppingATermNarrows() {
        String both = TEKCO_AnonymizationLaunchService.combineFilters(
            new Map<String, Set<String>>{ 'Address' => new Set<String>{ 'A = 1', 'B = 2' } },
            new Set<String>()
        ).get('Address');
        String one = TEKCO_AnonymizationLaunchService.combineFilters(
            new Map<String, Set<String>>{ 'Address' => new Set<String>{ 'A = 1' } },
            new Set<String>()
        ).get('Address');

        System.assertNotEquals(both, one, 'Retirer une config change la requete');
        System.assert(!one.contains('B = 2'), 'Le terme de la config decochee a disparu : ' + one);
    }

    @isTest
    static void combineFilters_noFilterAtAll_returnsEmpty() {
        System.assertEquals(0,
            TEKCO_AnonymizationLaunchService.combineFilters(
                new Map<String, Set<String>>(), new Set<String>()
            ).size(),
            'Aucun objet filtre : aucune entree');
    }
}
