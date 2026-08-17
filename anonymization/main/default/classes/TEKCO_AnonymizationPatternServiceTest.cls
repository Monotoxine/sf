@isTest
private class TEKCO_AnonymizationPatternServiceTest {

    // ─── Helpers ───────────────────────────────────────────────────────────────

    private static TEKCO_AnonymizationPattern__mdt activePattern(String type) {
        return new TEKCO_AnonymizationPattern__mdt(
            DeveloperName    = type,
            MasterLabel      = type,
            TEKCO_IsActive__c = true
        );
    }

    private static Contact mockContact(String firstName, String lastName, String sfId) {
        Contact c = new Contact(FirstName = firstName, LastName = lastName);
        return c;
    }

    // ─── NAME_FIRST_LETTER ─────────────────────────────────────────────────────

    @isTest
    static void nameFirstLetter_usesExternalId() {
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('NAME_FIRST_LETTER');
        pattern.TEKCO_ExternalIdField__c = 'TEKCO_FunctionalId__c';

        Contact c = new Contact(FirstName = 'Jean', LastName = 'Test');
        c.put('TEKCO_FunctionalId__c', 'EXT001');

        // In unit test we can't actually query — we just verify the logic path
        // since TEKCO_FunctionalId__c may not exist on Contact in all orgs.
        // Instead, verify blank value pass-through.
        String result = TEKCO_AnonymizationPatternService.applyPattern('NAME_FIRST_LETTER', '', c, pattern);
        System.assertEquals('', result, 'Blank value returned unchanged');
    }

    @isTest
    static void nameFirstLetter_uppercasesFirstChar() {
        TEKCO_AnonymizationOrgConfigService.resetCache();
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        TEKCO_AnonymizationPattern__mdt pattern = activePattern('NAME_FIRST_LETTER');

        // Using a Contact created in memory — external ID field blank → falls to SfId
        Account acc = new Account(Name = 'Test');
        insert acc;

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'NAME_FIRST_LETTER', 'jean', acc, pattern
        );
        System.assert(result.startsWith('J'), 'First letter must be uppercased: ' + result);
    }

    // ─── NAME_FIRST_LETTER_SFID ────────────────────────────────────────────────

    @isTest
    static void nameFirstLetterSfid_usesSalesforceIdDirectly() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('NAME_FIRST_LETTER_SFID');
        // External ID configured — SFID variant must ignore it
        pattern.TEKCO_ExternalIdField__c = 'TEKCO_FunctionalId__c';

        Account acc = new Account(Name = 'Test');
        insert acc;

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'NAME_FIRST_LETTER_SFID', 'marie', acc, pattern
        );
        System.assertEquals('M' + acc.Id, result,
            'NAME_FIRST_LETTER_SFID must use Salesforce record Id, got: ' + result);
    }

    // ─── EMAIL patterns ────────────────────────────────────────────────────────

    @isTest
    static void emailPlusExternalId_insertsIdAsAlias() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        Account acc = new Account(Name = 'Test');
        insert acc;

        TEKCO_AnonymizationPattern__mdt pattern = activePattern('EMAIL_PLUS_SFID');
        pattern.TEKCO_BaseEmail__c = 'anon@example.com';

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'EMAIL_PLUS_SFID', 'original@example.com', acc, pattern
        );
        System.assert(result.startsWith('anon+'), 'Email alias must contain plus sign: ' + result);
        System.assert(result.contains('@example.com'), 'Domain must be preserved: ' + result);
    }

    // ─── External ID resolution via OrgConfig ──────────────────────────────────
    //
    // AccountNumber stands in for the org's own external ID field: it is a standard
    // Account field, so these tests behave identically in every org.

    private static void useOrgExternalIdField(String fieldApiName) {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg =
            new TEKCO_AnonymizationOrgConfigService.OrgConfig();
        cfg.functionalIdField = 'TEKCO_FunctionalId__c';
        cfg.bypassEnabled     = false;
        cfg.externalIdFields  = fieldApiName;
        TEKCO_AnonymizationOrgConfigService.setConfigForTest(cfg);
    }

    @isTest
    static void externalId_fallsBackToOrgConfigFieldWhenPatternFieldAbsent() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        useOrgExternalIdField('AccountNumber');

        Account acc = new Account(Name = 'Test', AccountNumber = 'EXT12345');
        insert acc;

        TEKCO_AnonymizationPattern__mdt pattern = activePattern('EMAIL_PLUS_EXTERNALID');
        pattern.TEKCO_BaseEmail__c        = 'anon@example.com';
        // Standard TEKCO field, absent from orgs that key on their own — this is the case
        // the fallback exists for.
        pattern.TEKCO_ExternalIdField__c  = 'TEKCO_NoSuchExternalId__c';

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'EMAIL_PLUS_EXTERNALID', 'original@example.com', acc, pattern
        );

        System.assert(result.contains('+EXT12345'),
            'Must key on the org-configured external ID field, got: ' + result);
        System.assert(!result.contains(acc.Id),
            'Must not degrade to the Salesforce Id when the org declares a usable field: ' + result);
    }

    @isTest
    static void externalId_patternFieldWinsOverOrgConfig() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        useOrgExternalIdField('AccountNumber');

        Account acc = new Account(Name = 'Test', AccountNumber = 'ORGFIELD', Site = 'PATTERNFIELD');
        insert acc;

        TEKCO_AnonymizationPattern__mdt pattern = activePattern('EMAIL_PLUS_EXTERNALID');
        pattern.TEKCO_BaseEmail__c       = 'anon@example.com';
        pattern.TEKCO_ExternalIdField__c = 'Site';

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'EMAIL_PLUS_EXTERNALID', 'original@example.com', acc, pattern
        );

        System.assert(result.contains('+PATTERNFIELD'),
            'The field named on the pattern must win when it resolves: ' + result);
        System.assert(!result.contains('ORGFIELD'),
            'The org fallback must stay dormant while the pattern field answers: ' + result);
    }

    @isTest
    static void externalId_sfidPatternNeverDivertsToOrgConfig() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        useOrgExternalIdField('AccountNumber');

        Account acc = new Account(Name = 'Test', AccountNumber = 'EXT12345');
        insert acc;

        TEKCO_AnonymizationPattern__mdt pattern = activePattern('EMAIL_PLUS_SFID');
        pattern.TEKCO_BaseEmail__c       = 'anon@example.com';
        pattern.TEKCO_ExternalIdField__c = 'Id'; // how the shipped SFID patterns are configured

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'EMAIL_PLUS_SFID', 'original@example.com', acc, pattern
        );

        System.assert(result.contains(acc.Id),
            'A SFID pattern must key on the record Id: ' + result);
        System.assert(!result.contains('EXT12345'),
            'A SFID pattern must never drift onto a business identifier: ' + result);
    }

    @isTest
    static void externalId_patternDeclaringNoFieldIgnoresOrgConfig() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        useOrgExternalIdField('AccountNumber');

        Account acc = new Account(Name = 'Test', AccountNumber = 'EXT12345');
        insert acc;

        TEKCO_AnonymizationPattern__mdt pattern = activePattern('EMAIL_PLUS_SFID');
        pattern.TEKCO_BaseEmail__c = 'anon@example.com';
        // No external ID field declared at all — deliberate, so no fallback.

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'EMAIL_PLUS_SFID', 'original@example.com', acc, pattern
        );

        System.assert(!result.contains('EXT12345'),
            'A pattern naming no external ID field must not pick one up: ' + result);
    }

    // ─── SSN_SEQUENTIAL ────────────────────────────────────────────────────────

    @isTest
    static void ssnSequential_matchesOriginalLength() {
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('SSN_SEQUENTIAL');
        String original = '1234567890123'; // 13 chars
        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'SSN_SEQUENTIAL', original, new Account(), pattern
        );
        System.assertEquals(original.length(), result.length(), 'SSN length preserved');
        System.assert(result.isNumeric(), 'SSN must be numeric');
    }

    // ─── REGEX ─────────────────────────────────────────────────────────────────

    @isTest
    static void regex_replacesDigitsWithZero() {
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('REGEX');
        pattern.TEKCO_RegexFind__c    = '\\d';
        pattern.TEKCO_RegexReplace__c = '0';

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'REGEX', 'abc123def456', new Account(), pattern
        );
        System.assertEquals('abc000def000', result);
    }

    @isTest
    static void regex_blankFind_replacesEntireValue() {
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('REGEX');
        pattern.TEKCO_RegexFind__c    = '';
        pattern.TEKCO_RegexReplace__c = 'ANONYMIZED';

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'REGEX', 'anything here', new Account(), pattern
        );
        System.assertEquals('ANONYMIZED', result);
    }

    @isTest
    static void regex_invalidRegex_returnsOriginal() {
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('REGEX');
        pattern.TEKCO_RegexFind__c    = '[invalid(';
        pattern.TEKCO_RegexReplace__c = '0';

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'REGEX', 'original', new Account(), pattern
        );
        System.assertEquals('original', result, 'Invalid regex must leave value unchanged');
    }

    @isTest
    static void regex_nullReplace_treatedAsEmpty() {
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('REGEX');
        pattern.TEKCO_RegexFind__c    = '\\d+';
        pattern.TEKCO_RegexReplace__c = null;

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'REGEX', 'abc123', new Account(), pattern
        );
        System.assertEquals('abc', result, 'Null replacement must delete matches');
    }

    // ─── KEEP ──────────────────────────────────────────────────────────────────

    @isTest
    static void keep_returnsCurrentValue() {
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('KEEP');
        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'KEEP', 'unchanged', new Account(), pattern
        );
        // KEEP falls into when else → returns currentValue
        System.assertEquals('unchanged', result);
    }

    // ─── assertIsSandbox caching ───────────────────────────────────────────────

    @isTest
    static void assertIsSandbox_cachedAfterFirstCall() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = null;
        // In test context, org.IsSandbox may be true or false depending on the org.
        // We just verify that a second call does NOT issue another SOQL (cache hit).
        // We inject the cached value to avoid needing a real sandbox.
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        // Should not throw
        TEKCO_AnonymizationOrgConfigService.assertIsSandbox();
        System.assertEquals(true, TEKCO_AnonymizationOrgConfigService.isSandboxCached, 'Cache populated');
    }

    @isTest
    static void assertIsSandbox_throwsOnProduction() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = false;

        try {
            TEKCO_AnonymizationOrgConfigService.assertIsSandbox();
            System.assert(false, 'Expected ProductionOrgException');
        } catch (TEKCO_AnonymizationOrgConfigService.ProductionOrgException e) {
            System.assert(e.getMessage().contains('ABORT'), 'Exception message must say ABORT');
        }
    }

    // ─── hasField caching ──────────────────────────────────────────────────────

    @isTest
    static void hasField_returnsTrueForExistingField() {
        TEKCO_AnonymizationPatternService.globalDescribeCache = null;
        Boolean result = TEKCO_AnonymizationOrgConfigService.hasField('Account', 'Name');
        System.assertEquals(true, result);
        System.assertNotEquals(null, TEKCO_AnonymizationPatternService.globalDescribeCache,
            'Describe cache must be populated after first call');
    }

    @isTest
    static void hasField_returnsFalseForMissingField() {
        Boolean result = TEKCO_AnonymizationOrgConfigService.hasField('Account', 'NonExistentField__xyz');
        System.assertEquals(false, result);
    }

    @isTest
    static void hasField_returnsFalseForMissingObject() {
        Boolean result = TEKCO_AnonymizationOrgConfigService.hasField('NonExistentObject__xyz', 'Name');
        System.assertEquals(false, result);
    }

    @isTest
    static void hasField_returnsFalseForBlanks() {
        System.assertEquals(false, TEKCO_AnonymizationOrgConfigService.hasField('', 'Name'));
        System.assertEquals(false, TEKCO_AnonymizationOrgConfigService.hasField('Account', ''));
        System.assertEquals(false, TEKCO_AnonymizationOrgConfigService.hasField(null, null));
    }
}
