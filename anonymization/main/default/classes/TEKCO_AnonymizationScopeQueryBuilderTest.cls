@isTest
private class TEKCO_AnonymizationScopeQueryBuilderTest {

    private static TEKCO_AnonymizationFieldConfig__mdt config(
        String objectApiName, String fieldApiName, String patternType
    ) {
        return new TEKCO_AnonymizationFieldConfig__mdt(
            DeveloperName          = (objectApiName + '_' + fieldApiName).replaceAll('[^a-zA-Z0-9_]', '_'),
            TEKCO_ObjectApiName__c = objectApiName,
            TEKCO_FieldApiName__c  = fieldApiName,
            TEKCO_PatternType__c   = patternType,
            TEKCO_IsActive__c      = true
        );
    }

    /** Org-independent config: no brand object, no external ID field to add to the selection. */
    private static void useNeutralOrgConfig() {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg =
            new TEKCO_AnonymizationOrgConfigService.OrgConfig();
        cfg.functionalIdField = 'TEKCO_FunctionalId__c';
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(cfg);
    }

    @isTest
    static void buildFieldSelection_keepsRealFieldsAndAlwaysSelectsId() {
        useNeutralOrgConfig();

        Test.startTest();
        TEKCO_AnonymizationScopeQueryBuilder.FieldSelection selection =
            TEKCO_AnonymizationScopeQueryBuilder.buildFieldSelection(
                'Account',
                new List<TEKCO_AnonymizationFieldConfig__mdt>{ config('Account', 'Phone', 'REGEX') },
                new Map<String, TEKCO_AnonymizationPattern__mdt>()
            );
        Test.stopTest();

        System.assert(selection.fields.contains('Id'), 'Id is always selected');
        System.assert(selection.fields.contains('Phone'), 'The configured field is selected');
        System.assertEquals(1, selection.validConfigs.size(), 'The config survives validation');
        System.assert(selection.errors.isEmpty(), 'A real field produces no error');
        System.assertEquals(false, selection.needsRecordTypeId, 'No record type declared');
    }

    @isTest
    static void buildFieldSelection_dropsFieldAbsentFromTheObject() {
        useNeutralOrgConfig();

        TEKCO_AnonymizationScopeQueryBuilder.FieldSelection selection =
            TEKCO_AnonymizationScopeQueryBuilder.buildFieldSelection(
                'Account',
                new List<TEKCO_AnonymizationFieldConfig__mdt>{
                    config('Account', 'ThisFieldDoesNotExist__c', 'REGEX')
                },
                new Map<String, TEKCO_AnonymizationPattern__mdt>()
            );

        System.assertEquals(0, selection.validConfigs.size(), 'The config is dropped');
        System.assertEquals(1, selection.errors.size(), 'The skip is reported');
        System.assert(selection.errors[0].contains('ThisFieldDoesNotExist__c'),
            'The error names the missing field');
        System.assertEquals(false, selection.fields.contains('ThisFieldDoesNotExist__c'),
            'A missing field must never reach the SELECT clause');
    }

    /**
     * ContentDocument deletion is handled by its own batch in BOTH chains. Carrying those configs
     * into the field phase used to happen on the By Criteria side only.
     */
    @isTest
    static void buildFieldSelection_skipsContentDocumentConfigs() {
        useNeutralOrgConfig();

        TEKCO_AnonymizationScopeQueryBuilder.FieldSelection selection =
            TEKCO_AnonymizationScopeQueryBuilder.buildFieldSelection(
                'Account',
                new List<TEKCO_AnonymizationFieldConfig__mdt>{
                    config('Account', null, 'DELETE_CONTENT_DOCUMENT'),
                    config('Account', 'Phone', 'REGEX')
                },
                new Map<String, TEKCO_AnonymizationPattern__mdt>()
            );

        System.assertEquals(1, selection.validConfigs.size(),
            'Only the field-level config is kept');
        System.assertEquals('REGEX', selection.validConfigs[0].TEKCO_PatternType__c,
            'The kept config is the REGEX one');
    }

    @isTest
    static void buildFieldSelection_requestsRecordTypeIdWhenAConfigIsRecordTypeScoped() {
        useNeutralOrgConfig();

        TEKCO_AnonymizationFieldConfig__mdt scoped = config('Account', 'Phone', 'REGEX');
        scoped.TEKCO_RecordTypeDeveloperName__c = 'Business';

        TEKCO_AnonymizationScopeQueryBuilder.FieldSelection selection =
            TEKCO_AnonymizationScopeQueryBuilder.buildFieldSelection(
                'Account',
                new List<TEKCO_AnonymizationFieldConfig__mdt>{ scoped },
                new Map<String, TEKCO_AnonymizationPattern__mdt>()
            );

        System.assertEquals(true, selection.needsRecordTypeId, 'A scoped config needs RecordTypeId');
        System.assert(selection.fields.contains('RecordTypeId'), 'RecordTypeId is selected');
    }

    @isTest
    static void buildFieldSelection_selectsStatusForEmailMessageLorem() {
        useNeutralOrgConfig();

        TEKCO_AnonymizationScopeQueryBuilder.FieldSelection selection =
            TEKCO_AnonymizationScopeQueryBuilder.buildFieldSelection(
                'EmailMessage',
                new List<TEKCO_AnonymizationFieldConfig__mdt>{
                    config('EmailMessage', 'TextBody', 'EMAIL_MESSAGE_LOREM')
                },
                new Map<String, TEKCO_AnonymizationPattern__mdt>()
            );

        System.assertEquals(true, selection.hasEmailMessageLorem, 'The lorem pattern is flagged');
        System.assert(selection.fields.contains('Status'),
            'Status decides mask-vs-delete, so it must be read');
    }

    @isTest
    static void buildFieldSelection_reportsUnknownObjectInsteadOfThrowing() {
        useNeutralOrgConfig();

        TEKCO_AnonymizationScopeQueryBuilder.FieldSelection selection =
            TEKCO_AnonymizationScopeQueryBuilder.buildFieldSelection(
                'ThisObjectDoesNotExist__c',
                new List<TEKCO_AnonymizationFieldConfig__mdt>(),
                new Map<String, TEKCO_AnonymizationPattern__mdt>()
            );

        System.assertEquals(1, selection.errors.size(), 'The missing object is reported');
        System.assertEquals(0, selection.validConfigs.size(), 'Nothing is kept');
    }

    @isTest
    static void selectClause_isSortedAndComplete() {
        String clause = TEKCO_AnonymizationScopeQueryBuilder.selectClause(
            new Set<String>{ 'Phone', 'Id', 'Name' }
        );
        System.assertEquals('SELECT Id, Name, Phone', clause,
            'Fields are sorted so the produced query is comparable');
    }

    @isTest
    static void whereClause_joinsOnlyNonBlankConditions() {
        System.assertEquals(
            '',
            TEKCO_AnonymizationScopeQueryBuilder.whereClause(new List<String>{ null, '', '  ' }),
            'No condition means no WHERE at all'
        );
        System.assertEquals(
            ' WHERE A = 1 AND B = 2',
            TEKCO_AnonymizationScopeQueryBuilder.whereClause(
                new List<String>{ 'A = 1', null, 'B = 2' }
            ),
            'Blank conditions are dropped, the rest are ANDed'
        );
    }

    // ─── Scope queries ────────────────────────────────────────────────────────

    /** Picklist-mode org (no brand object): brand scoping lands on TEKCO_Brand__c. */
    private static void usePicklistBrandOrgConfig() {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg =
            new TEKCO_AnonymizationOrgConfigService.OrgConfig();
        cfg.functionalIdField = 'TEKCO_FunctionalId__c';
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(cfg);
    }

    /** Brand-object org (Portugal shape): brand scoping traverses a lookup. */
    private static void useBrandObjectOrgConfig() {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg =
            new TEKCO_AnonymizationOrgConfigService.OrgConfig();
        cfg.functionalIdField        = 'TEKCO_FunctionalId__c';
        cfg.brandObjectApiName       = 'ALH_Brand__c';
        cfg.brandCodeField           = 'ALH_Code__c';
        cfg.brandLookupFieldOnRecord = 'ALH_Brand__r';
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(cfg);
    }

    @isTest
    static void buildFieldScopeQuery_withoutBrandsHasNoWhereClause() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildFieldScopeQuery(
            'Account', new Set<String>{ 'Id', 'Phone' }, new List<String>(), null, null, null, false
        );

        System.assertEquals('SELECT Id, Phone FROM Account', soql,
            'No brand and no additional filter means no WHERE at all');
    }

    @isTest
    static void buildFieldScopeQuery_appendsTheAdditionalFilter() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildFieldScopeQuery(
            'Account', new Set<String>{ 'Id' }, null, null, null, 'IsDeleted = false', false
        );

        System.assertEquals('SELECT Id FROM Account WHERE IsDeleted = false', soql,
            'The per-object additional filter is applied on its own');
    }

    /**
     * An org whose objects carry no brand field at all must produce an unfiltered query rather
     * than a broken one — this is the Portugal-without-brand-lookup case.
     */
    @isTest
    static void buildFieldScopeQuery_dropsBrandScopeWhenTheObjectCannotCarryIt() {
        useBrandObjectOrgConfig();   // Account has no ALH_Brand__c lookup in this org

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildFieldScopeQuery(
            'Account', new Set<String>{ 'Id' }, new List<String>{ 'BRAND_A' }, null, null, null, false
        );

        System.assertEquals('SELECT Id FROM Account', soql,
            'An impossible brand condition is dropped, never guessed');
    }

    /**
     * EmailMessage carries no brand field of its own. When the brand condition cannot be built
     * for it, the scope goes through the parent Case — only if that org has the field.
     */
    @isTest
    static void buildFieldScopeQuery_emailMessageFallsBackToTheParentCaseWhenAvailable() {
        usePicklistBrandOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildFieldScopeQuery(
            'EmailMessage', new Set<String>{ 'Id' }, new List<String>{ 'BRAND_A' }, null, null, null, true
        );

        Boolean caseHasBrand =
            TEKCO_AnonymizationOrgConfigService.hasField('Case', 'TEKCO_Brand__c');
        Boolean emailHasBrand =
            TEKCO_AnonymizationOrgConfigService.hasField('EmailMessage', 'TEKCO_Brand__c');

        if (!emailHasBrand && caseHasBrand) {
            System.assert(soql.contains('Parent.TEKCO_Brand__c IN :selectedBrands'),
                'The parent Case carries the brand scope');
        } else {
            System.assertEquals(false, soql.contains('Parent.TEKCO_Brand__c'),
                'Without the field on Case, no parent traversal is emitted');
        }
    }

    @isTest
    static void buildByIdScopeQuery_bindsTheNamedIdCollection() {
        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildByIdScopeQuery(
            'Contact', new Set<String>{ 'Id', 'Email' }, 'recordIds'
        );

        System.assertEquals('SELECT Email, Id FROM Contact WHERE Id IN :recordIds', soql,
            'The bind name reaches the query so the batch field resolves it');
    }

    @isTest
    static void buildContentDocScopeQuery_escapesTheRecordTypeName() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery(
            'Account', null, new Set<String>{ 'O\'Brien' }, null, null
        );

        System.assert(soql.contains('RecordType.DeveloperName IN (\'O\\\'Brien\')'),
            'A quote in a record type name is escaped, not injected: ' + soql);
    }

    /** Retrocompatibilite : une regle mono-valuee produit exactement une valeur dans le IN. */
    @isTest
    static void buildContentDocScopeQuery_oneRecordType_behavesAsBefore() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery(
            'Account', null, new Set<String>{ 'Patient' }, null, null
        );

        System.assertEquals(
            'SELECT Id FROM Account WHERE RecordType.DeveloperName IN (\'Patient\')',
            soql,
            'Meme perimetre qu avec l ancienne egalite');
    }

    @isTest
    static void buildContentDocScopeQuery_severalRecordTypes_areAllIncluded() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery(
            'Account', null, new Set<String>{ 'Prescriber', 'Patient' }, null, null
        );

        System.assertEquals(
            'SELECT Id FROM Account WHERE RecordType.DeveloperName IN (\'Patient\', \'Prescriber\')',
            soql,
            'Les deux populations, triees pour que la requete soit comparable');
    }

    @isTest
    static void buildContentDocScopeQuery_withNothingToFilterSelectsTheWholeObject() {
        useNeutralOrgConfig();

        System.assertEquals(
            'SELECT Id FROM Account',
            TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery('Account', null, null, null, null),
            'No brand, no record type, no filter'
        );
    }

    // ─── combineAdditionalFilters : le perimetre d un objet ──────────────────────

    private static TEKCO_AnonymizationFieldConfig__mdt withFilter(String filter) {
        return new TEKCO_AnonymizationFieldConfig__mdt(
            TEKCO_ObjectApiName__c    = 'Address',
            TEKCO_FieldApiName__c     = 'Street',
            TEKCO_AdditionalFilter__c = filter
        );
    }

    /**
     * Le cas Address : deux regles, deux filtres exclusifs. L ancienne version n en gardait qu un,
     * au hasard de l ordre de la requete, et une des deux populations n etait jamais anonymisee.
     */
    @isTest
    static void combineAdditionalFilters_twoFilters_areBothApplied() {
        String filter = TEKCO_AnonymizationScopeQueryBuilder.combineAdditionalFilters(
            new List<TEKCO_AnonymizationFieldConfig__mdt>{
                withFilter('A = 1'), withFilter('B = 2')
            }
        );

        System.assertEquals('((A = 1) OR (B = 2))', filter,
            'Les deux termes, tries, englobes');
    }

    /**
     * whereClause() joint les conditions avec AND, et AND lie plus fort que OR en SOQL. Sans
     * parentheses englobantes, "marque AND (A) OR (B)" se lit "(marque AND A) OR B" et attrape
     * des enregistrements hors du filtre de marque.
     */
    @isTest
    static void combineAdditionalFilters_singleFilter_isParenthesisedToo() {
        System.assertEquals(
            '((X = 1 OR Y = 2))',
            TEKCO_AnonymizationScopeQueryBuilder.combineAdditionalFilters(
                new List<TEKCO_AnonymizationFieldConfig__mdt>{ withFilter('X = 1 OR Y = 2') }
            ),
            'Un filtre unique est englobe : il peut contenir son propre OR');
    }

    /**
     * Une regle retenue sans filtre s applique a tous les enregistrements de l objet :
     * restreindre la requete lui retirerait des enregistrements qu elle doit anonymiser.
     */
    @isTest
    static void combineAdditionalFilters_anUnfilteredRuleLiftsTheRestriction() {
        System.assertEquals(null,
            TEKCO_AnonymizationScopeQueryBuilder.combineAdditionalFilters(
                new List<TEKCO_AnonymizationFieldConfig__mdt>{
                    withFilter('A = 1'), withFilter(null)
                }
            ),
            'Aucun filtre : l objet est lu en entier');
    }

    /** Decocher une regle retire son terme du OR — un OR ampute ne peut que retrecir. */
    @isTest
    static void combineAdditionalFilters_droppingARuleNarrows() {
        String both = TEKCO_AnonymizationScopeQueryBuilder.combineAdditionalFilters(
            new List<TEKCO_AnonymizationFieldConfig__mdt>{ withFilter('A = 1'), withFilter('B = 2') }
        );
        String one = TEKCO_AnonymizationScopeQueryBuilder.combineAdditionalFilters(
            new List<TEKCO_AnonymizationFieldConfig__mdt>{ withFilter('A = 1') }
        );

        System.assertNotEquals(both, one, 'Retirer une regle change la requete');
        System.assert(!one.contains('B = 2'), 'Le terme de la regle decochee a disparu : ' + one);
    }

    @isTest
    static void combineAdditionalFilters_nothing_returnsNull() {
        System.assertEquals(null,
            TEKCO_AnonymizationScopeQueryBuilder.combineAdditionalFilters(null));
        System.assertEquals(null,
            TEKCO_AnonymizationScopeQueryBuilder.combineAdditionalFilters(
                new List<TEKCO_AnonymizationFieldConfig__mdt>()));
    }

    @isTest
    static void buildHistoryScopeQuery_targetsTheConfiguredFieldsOnTheScopedParents() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildHistoryScopeQuery(
            'Account', 'AccountHistory', 'AccountId',
            new Set<String>{ 'Phone', 'Name' }, null, null, null, 'IsDeleted = false'
        );

        System.assertEquals(
            'SELECT Id FROM AccountHistory WHERE Field IN (\'Name\', \'Phone\')'
            + ' AND AccountId IN (SELECT Id FROM Account WHERE IsDeleted = false)',
            soql,
            'History rows are targeted by field and scoped through the parent query'
        );
    }

    /**
     * Zero targeted fields would emit 'Field IN ()', which is invalid SOQL. Returning null lets
     * both chains skip cleanly — the By Criteria batch used to report a parse error here.
     */
    @isTest
    static void buildHistoryScopeQuery_withoutFieldsReturnsNull() {
        useNeutralOrgConfig();

        System.assertEquals(null,
            TEKCO_AnonymizationScopeQueryBuilder.buildHistoryScopeQuery(
                'Account', 'AccountHistory', 'AccountId', new Set<String>(), null, null, null, null
            ),
            'No targeted field means no query at all');

        System.assertEquals(null,
            TEKCO_AnonymizationScopeQueryBuilder.buildHistoryByIdScopeQuery(
                'AccountHistory', 'AccountId', null, 'recordIds'
            ),
            'Same contract on the By ID side');
    }

    @isTest
    static void buildHistoryByIdScopeQuery_bindsTheParentIds() {
        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildHistoryByIdScopeQuery(
            'AccountHistory', 'AccountId', new Set<String>{ 'Phone' }, 'recordIds'
        );

        System.assertEquals(
            'SELECT Id FROM AccountHistory WHERE Field IN (\'Phone\') AND AccountId IN :recordIds',
            soql,
            'The By ID history scope is the same shape without the parent subquery'
        );
    }

    // ─── History object naming (relocated from TEKCO_AnonymizationBatchUtilsTest) ────


    @isTest
    static void computeHistoryObjectName_customObject() {
        String result = TEKCO_AnonymizationScopeQueryBuilder.historyObjectNameFor('MyObj__c');
        System.assertEquals('MyObj__History', result, 'Custom object history suffix');
    }

    @isTest
    static void computeHistoryObjectName_standardObject() {
        String result = TEKCO_AnonymizationScopeQueryBuilder.historyObjectNameFor('Account');
        System.assertEquals('AccountHistory', result, 'Standard object history suffix');
    }

    @isTest
    static void computeParentIdFieldName_customObject() {
        System.assertEquals('ParentId', TEKCO_AnonymizationScopeQueryBuilder.historyParentIdFieldFor('MyObj__c'));
    }

    @isTest
    static void computeParentIdFieldName_standardObject() {
        System.assertEquals('AccountId', TEKCO_AnonymizationScopeQueryBuilder.historyParentIdFieldFor('Account'));
    }

    // ─── cap ───────────────────────────────────────────────────────────────────

    // ─── recordTypeCondition : la selection de l utilisateur borne le RUN ────────

    private static List<TEKCO_AnonymizationFieldConfig__mdt> accountConfigs(String recordTypes) {
        return new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(
                TEKCO_ObjectApiName__c           = 'Account',
                TEKCO_FieldApiName__c            = 'Phone',
                TEKCO_RecordTypeDeveloperName__c = recordTypes
            )
        };
    }

    /** Retrocompatibilite : aucune selection, aucune condition, perimetre inchange. */
    @isTest
    static void recordTypeCondition_noSelection_addsNothing() {
        useNeutralOrgConfig();

        System.assertEquals(null, TEKCO_AnonymizationScopeQueryBuilder.recordTypeCondition(
            'Account', null, accountConfigs('ACCCO_Patient')));
        System.assertEquals(null, TEKCO_AnonymizationScopeQueryBuilder.recordTypeCondition(
            'Account', new List<String>(), accountConfigs('ACCCO_Patient')));
    }

    /**
     * LE CAS QUI MOTIVE TOUT. Une regle couvre deux populations, l utilisateur n en selectionne
     * qu une : la requete ne doit lire que celle-la. Sans cette condition, la regle etait
     * appliquee aux deux et l autre population etait anonymisee sans que rien ne le dise.
     */
    @isTest
    static void recordTypeCondition_narrowsARuleCoveringSeveralPopulations() {
        useNeutralOrgConfig();

        String condition = TEKCO_AnonymizationScopeQueryBuilder.recordTypeCondition(
            'Account',
            new List<String>{ 'ACCCO_Patient' },
            accountConfigs('ACCCO_IndividualPerson,ACCCO_Patient')
        );

        System.assertEquals("RecordType.DeveloperName IN ('ACCCO_Patient')", condition,
            'Seule la population selectionnee est lue : ' + condition);
    }

    /** Un record type declare par un AUTRE objet ne doit pas filtrer celui-ci. */
    @isTest
    static void recordTypeCondition_ignoresRecordTypesTheObjectDoesNotDeclare() {
        useNeutralOrgConfig();

        System.assertEquals(null, TEKCO_AnonymizationScopeQueryBuilder.recordTypeCondition(
            'Account',
            new List<String>{ 'CTCCO_StandardContact' },
            accountConfigs('ACCCO_Patient')),
            'Un record type de Contact ne filtre pas une requete Account');
    }

    @isTest
    static void recordTypeCondition_severalSelected_areSortedAndEscaped() {
        useNeutralOrgConfig();

        System.assertEquals(
            "RecordType.DeveloperName IN ('ACCCO_IndividualPerson', 'ACCCO_Patient')",
            TEKCO_AnonymizationScopeQueryBuilder.recordTypeCondition(
                'Account',
                new List<String>{ 'ACCCO_Patient', 'ACCCO_IndividualPerson' },
                accountConfigs('ACCCO_IndividualPerson,ACCCO_Patient')),
            'Triees, pour que la requete soit comparable d un run a l autre');
    }

    @isTest
    static void recordTypeCondition_withoutConfigs_addsNothing() {
        useNeutralOrgConfig();

        System.assertEquals(null, TEKCO_AnonymizationScopeQueryBuilder.recordTypeCondition(
            'Account', new List<String>{ 'ACCCO_Patient' }, null));
        System.assertEquals(null, TEKCO_AnonymizationScopeQueryBuilder.recordTypeCondition(
            'Account', new List<String>{ 'ACCCO_Patient' },
            new List<TEKCO_AnonymizationFieldConfig__mdt>()));
    }

    /** La condition entre bien dans la requete de la phase champ. */
    @isTest
    static void buildFieldScopeQuery_appliesTheRecordTypeSelection() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildFieldScopeQuery(
            'Account', new Set<String>{ 'Id' }, null,
            new List<String>{ 'ACCCO_Patient' },
            accountConfigs('ACCCO_IndividualPerson,ACCCO_Patient'),
            null, false
        );

        System.assertEquals(
            "SELECT Id FROM Account WHERE RecordType.DeveloperName IN ('ACCCO_Patient')",
            soql,
            'La phase champ ne lit que la population selectionnee : ' + soql);
    }

    /** Et dans celle de la phase historique, via la sous-requete sur le parent. */
    @isTest
    static void buildHistoryScopeQuery_appliesTheRecordTypeSelection() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildHistoryScopeQuery(
            'Account', 'AccountHistory', 'AccountId', new Set<String>{ 'Phone' }, null,
            new List<String>{ 'ACCCO_Patient' },
            accountConfigs('ACCCO_IndividualPerson,ACCCO_Patient'),
            null
        );

        System.assert(soql.contains("RecordType.DeveloperName IN ('ACCCO_Patient')"),
            'Les lignes d historique suivent le meme perimetre : ' + soql);
    }

    /** La phase fichiers croise la couverture de la regle et la selection. */
    @isTest
    static void buildContentDocScopeQuery_intersectsRuleCoverageWithTheSelection() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery(
            'Account', null,
            new Set<String>{ 'ACCCO_IndividualPerson', 'ACCCO_Patient' },
            new List<String>{ 'ACCCO_Patient' },
            null
        );

        System.assertEquals(
            "SELECT Id FROM Account WHERE RecordType.DeveloperName IN ('ACCCO_Patient')",
            soql,
            'Les fichiers de la population non selectionnee ne sont pas supprimes : ' + soql);
    }

    /** Regle sans record type, run restreint : la selection borne quand meme la requete. */
    @isTest
    static void buildContentDocScopeQuery_unscopedRuleIsStillBoundedByTheSelection() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery(
            'Account', null, new Set<String>(),
            new List<String>{ 'ACCCO_Patient' },
            null
        );

        System.assertEquals(
            "SELECT Id FROM Account WHERE RecordType.DeveloperName IN ('ACCCO_Patient')",
            soql,
            'Une regle couvrant tout l objet reste bornee par la selection : ' + soql);
    }
}
