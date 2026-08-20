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
            'Account', new Set<String>{ 'Id', 'Phone' }, new List<String>(), null, false
        );

        System.assertEquals('SELECT Id, Phone FROM Account', soql,
            'No brand and no additional filter means no WHERE at all');
    }

    @isTest
    static void buildFieldScopeQuery_appendsTheAdditionalFilter() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildFieldScopeQuery(
            'Account', new Set<String>{ 'Id' }, null, 'IsDeleted = false', false
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
            'Account', new Set<String>{ 'Id' }, new List<String>{ 'BRAND_A' }, null, false
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
            'EmailMessage', new Set<String>{ 'Id' }, new List<String>{ 'BRAND_A' }, null, true
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
            'Account', null, 'O\'Brien', null
        );

        System.assert(soql.contains('RecordType.DeveloperName = \'O\\\'Brien\''),
            'A quote in a record type name is escaped, not injected: ' + soql);
    }

    @isTest
    static void buildContentDocScopeQuery_withNothingToFilterSelectsTheWholeObject() {
        useNeutralOrgConfig();

        System.assertEquals(
            'SELECT Id FROM Account',
            TEKCO_AnonymizationScopeQueryBuilder.buildContentDocScopeQuery('Account', null, null, null),
            'No brand, no record type, no filter'
        );
    }

    @isTest
    static void buildHistoryScopeQuery_targetsTheConfiguredFieldsOnTheScopedParents() {
        useNeutralOrgConfig();

        String soql = TEKCO_AnonymizationScopeQueryBuilder.buildHistoryScopeQuery(
            'Account', 'AccountHistory', 'AccountId',
            new Set<String>{ 'Phone', 'Name' }, null, 'IsDeleted = false'
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
                'Account', 'AccountHistory', 'AccountId', new Set<String>(), null, null
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
}
