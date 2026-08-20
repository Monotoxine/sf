@isTest
private class TEKCO_AnonymizationPreviewServiceTest {

    /**
     * First object that actually carries an active field-level configuration in THIS org.
     * The suite runs on TEKCO orgs and on Portugal, whose configurations differ, so the tests
     * assert behaviour rather than a particular object being present.
     */
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

    @isTest
    static void previewByCriteria_unconfiguredObjectIsRejected() {
        Test.startTest();
        try {
            TEKCO_AnonymizationPreviewService.previewByCriteria(
                'ThisObjectIsNotConfigured__c', null, null, null, 5
            );
            System.assert(false, 'An object outside the configuration must never be queried');
        } catch (Exception e) {
            System.assert(true, 'Rejected as expected: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void previewByIds_unconfiguredObjectIsRejected() {
        Test.startTest();
        try {
            TEKCO_AnonymizationPreviewService.previewByIds(
                'ThisObjectIsNotConfigured__c', new List<Id>{ UserInfo.getUserId() }, null, 5
            );
            System.assert(false, 'An object outside the configuration must never be queried');
        } catch (Exception e) {
            System.assert(true, 'Rejected as expected: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @isTest
    static void previewByIds_withoutIdsReturnsAWarningRatherThanThrowing() {
        String objectApiName = anyConfiguredObject();
        if (objectApiName == null) return;   // org without configuration: nothing to assert

        Test.startTest();
        TEKCO_AnonymizationPreviewService.PreviewSampleDTO result =
            TEKCO_AnonymizationPreviewService.previewByIds(objectApiName, new List<Id>(), null, 5);
        Test.stopTest();

        System.assertEquals(0, result.recordsSampled, 'Nothing was read');
        System.assertEquals(0, result.rows.size(), 'Nothing to show');
        System.assertEquals(false, result.warnings.isEmpty(), 'The empty scope is explained');
    }

    /**
     * The point of the whole feature: a preview must never write. Whatever the org configuration,
     * the call completes with zero DML statements consumed.
     */
    @isTest
    static void previewByCriteria_performsNoDml() {
        String objectApiName = anyConfiguredObject();
        if (objectApiName == null) return;

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        TEKCO_AnonymizationPreviewService.PreviewSampleDTO result =
            TEKCO_AnonymizationPreviewService.previewByCriteria(
                objectApiName, null, null, null, 5
            );
        Integer dmlAfter = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals(dmlBefore, dmlAfter, 'A preview must not consume a single DML statement');
        System.assertNotEquals(null, result, 'A result is always returned');
        System.assertEquals(objectApiName, result.objectApiName, 'The result names the object');
        System.assert(result.recordsSampled <= TEKCO_AnonymizationPreviewService.MAX_SAMPLE_SIZE,
            'The sample never exceeds the hard ceiling');
    }

    @isTest
    static void previewByCriteria_sampleSizeIsCappedWhateverTheCallerAsks() {
        String objectApiName = anyConfiguredObject();
        if (objectApiName == null) return;

        Test.startTest();
        TEKCO_AnonymizationPreviewService.PreviewSampleDTO result =
            TEKCO_AnonymizationPreviewService.previewByCriteria(
                objectApiName, null, null, null, 10000
            );
        Test.stopTest();

        System.assert(result.recordsSampled <= TEKCO_AnonymizationPreviewService.MAX_SAMPLE_SIZE,
            'A caller asking for 10 000 records still gets at most MAX_SAMPLE_SIZE');
    }

    /**
     * Excluding every configured field leaves nothing to apply — the preview must say so
     * instead of silently showing an empty table.
     */
    @isTest
    static void previewByCriteria_allFieldsExcludedIsExplained() {
        String objectApiName = anyConfiguredObject();
        if (objectApiName == null) return;

        List<String> allKeys = new List<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : [
            SELECT TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c, TEKCO_RecordTypeDeveloperName__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_IsActive__c = true AND TEKCO_ObjectApiName__c = :objectApiName
        ]) {
            allKeys.add(
                fc.TEKCO_ObjectApiName__c + '.' + fc.TEKCO_FieldApiName__c + '.'
                + (fc.TEKCO_RecordTypeDeveloperName__c != null ? fc.TEKCO_RecordTypeDeveloperName__c : '')
            );
        }

        Test.startTest();
        TEKCO_AnonymizationPreviewService.PreviewSampleDTO result =
            TEKCO_AnonymizationPreviewService.previewByCriteria(
                objectApiName, null, null, allKeys, 5
            );
        Test.stopTest();

        System.assertEquals(0, result.rows.size(), 'Nothing is shown');
        System.assertEquals(false, result.warnings.isEmpty(),
            'The user is told why the sample is empty');
    }
}
