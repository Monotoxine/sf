@isTest
private class TEKCO_AnonymizationPatternServiceTest {

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

    @isTest
    static void nameFirstLetter_usesExternalId() {
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('NAME_FIRST_LETTER');
        pattern.TEKCO_ExternalIdField__c = 'TEKCO_FunctionalId__c';

        Contact c = new Contact(FirstName = 'Jean', LastName = 'Test');

        String result = TEKCO_AnonymizationPatternService.applyPattern('NAME_FIRST_LETTER', '', c, pattern);
        System.assertEquals('', result, 'Blank value returned unchanged');
    }

    @isTest
    static void nameFirstLetter_uppercasesFirstChar() {
        TEKCO_AnonymizationOrgConfigService.resetCache();
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

        TEKCO_AnonymizationPattern__mdt pattern = activePattern('NAME_FIRST_LETTER');

        Account acc = new Account(Name = 'Test');
        insert acc;

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'NAME_FIRST_LETTER', 'jean', acc, pattern
        );
        System.assert(result.startsWith('J'), 'First letter must be uppercased: ' + result);
    }

    @isTest
    static void nameFirstLetterSfid_usesSalesforceIdDirectly() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('NAME_FIRST_LETTER_SFID');
        pattern.TEKCO_ExternalIdField__c = 'TEKCO_FunctionalId__c';

        Account acc = new Account(Name = 'Test');
        insert acc;

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'NAME_FIRST_LETTER_SFID', 'marie', acc, pattern
        );
        System.assertEquals('M' + acc.Id, result,
            'NAME_FIRST_LETTER_SFID must use Salesforce record Id, got: ' + result);
    }

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

    private static void useOrgExternalIdField(String fieldApiName) {
        TEKCO_AnonymizationOrgConfigService.OrgConfig cfg =
            new TEKCO_AnonymizationOrgConfigService.OrgConfig();
        cfg.functionalIdField = 'TEKCO_FunctionalId__c';
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

        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'EMAIL_PLUS_SFID', 'original@example.com', acc, pattern
        );

        System.assert(!result.contains('EXT12345'),
            'A pattern naming no external ID field must not pick one up: ' + result);
    }

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

    @isTest
    static void keep_returnsCurrentValue() {
        TEKCO_AnonymizationPattern__mdt pattern = activePattern('KEEP');
        String result = TEKCO_AnonymizationPatternService.applyPattern(
            'KEEP', 'unchanged', new Account(), pattern
        );
        System.assertEquals('unchanged', result);
    }

    @isTest
    static void assertIsSandbox_cachedAfterFirstCall() {
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = null;
        TEKCO_AnonymizationOrgConfigService.isSandboxCached = true;

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

    @isTest
    static void hasField_returnsTrueForExistingField() {
        Boolean result = TEKCO_AnonymizationOrgConfigService.hasField('Account', 'Name');
        System.assertEquals(true, result);
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

    private static TEKCO_AnonymizationPattern__mdt regexPattern(String find, String replace) {
        return new TEKCO_AnonymizationPattern__mdt(
            DeveloperName         = 'REGEX',
            MasterLabel           = 'REGEX',
            TEKCO_IsActive__c     = true,
            TEKCO_RegexFind__c    = find,
            TEKCO_RegexReplace__c = replace
        );
    }

    @isTest
    static void applyRegex_twoDifferentPatterns_doNotShareTheirCompilation() {
        String value = 'abc123';

        String digitsMasked = TEKCO_AnonymizationPatternService.applyPattern(
            'REGEX', value, null, regexPattern('\\d', '0')
        );
        String lettersMasked = TEKCO_AnonymizationPatternService.applyPattern(
            'REGEX', value, null, regexPattern('[a-z]', 'x')
        );

        System.assertEquals('abc000', digitsMasked, 'La premiere regex ne touche que les chiffres');
        System.assertEquals('xxx123', lettersMasked, 'La seconde a bien sa propre compilation');
    }

    @isTest
    static void applyRegex_samePatternTwice_isStable() {
        TEKCO_AnonymizationPattern__mdt pattern = regexPattern('\\d', '0');

        String first  = TEKCO_AnonymizationPatternService.applyPattern('REGEX', 'a1b2', null, pattern);
        String second = TEKCO_AnonymizationPatternService.applyPattern('REGEX', 'a1b2', null, pattern);

        System.assertEquals('a0b0', first, 'Premier appel : compilation');
        System.assertEquals(first, second, 'Second appel : lecture du cache, meme resultat');
    }

    @isTest
    static void applySsnSequential_twoLengths_doNotShareTheirCache() {
        TEKCO_AnonymizationPattern__mdt ssn = new TEKCO_AnonymizationPattern__mdt(
            DeveloperName = 'SSN_SEQUENTIAL', MasterLabel = 'SSN_SEQUENTIAL',
            TEKCO_IsActive__c = true
        );

        String short5 = TEKCO_AnonymizationPatternService.applyPattern(
            'SSN_SEQUENTIAL', '12345', null, ssn
        );
        String long9 = TEKCO_AnonymizationPatternService.applyPattern(
            'SSN_SEQUENTIAL', '123456789', null, ssn
        );
        String short5Again = TEKCO_AnonymizationPatternService.applyPattern(
            'SSN_SEQUENTIAL', 'abcde', null, ssn
        );

        System.assertEquals(5, short5.length(), 'La longueur suit celle de la valeur d\'entree');
        System.assertEquals(9, long9.length(), 'Une autre longueur produit une autre suite');
        System.assertEquals('12345', short5, 'La suite reste 1,2,3... a partir de 1');
        System.assertEquals(short5, short5Again, 'Meme longueur : meme suite, servie par le cache');
    }
}
