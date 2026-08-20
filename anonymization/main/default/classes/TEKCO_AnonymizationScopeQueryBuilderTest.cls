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
}
