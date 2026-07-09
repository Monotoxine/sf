@isTest
private class TEKCO_AnonymizationBatchUtilsTest {

    @isTest
    static void computeHistoryObjectName_customObject() {
        String result = TEKCO_AnonymizationBatchUtils.computeHistoryObjectName('MyObj__c');
        System.assertEquals('MyObj__History', result, 'Custom object history suffix');
    }

    @isTest
    static void computeHistoryObjectName_standardObject() {
        String result = TEKCO_AnonymizationBatchUtils.computeHistoryObjectName('Account');
        System.assertEquals('AccountHistory', result, 'Standard object history suffix');
    }

    @isTest
    static void computeParentIdFieldName_customObject() {
        System.assertEquals('ParentId', TEKCO_AnonymizationBatchUtils.computeParentIdFieldName('MyObj__c'));
    }

    @isTest
    static void computeParentIdFieldName_standardObject() {
        System.assertEquals('AccountId', TEKCO_AnonymizationBatchUtils.computeParentIdFieldName('Account'));
    }

    @isTest
    static void popConfigsForObject_splitsCorrectly() {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(TEKCO_ObjectApiName__c = 'Account', TEKCO_FieldApiName__c = 'Name'),
            new TEKCO_AnonymizationFieldConfig__mdt(TEKCO_ObjectApiName__c = 'Contact', TEKCO_FieldApiName__c = 'FirstName'),
            new TEKCO_AnonymizationFieldConfig__mdt(TEKCO_ObjectApiName__c = 'Account', TEKCO_FieldApiName__c = 'Phone')
        };

        List<TEKCO_AnonymizationFieldConfig__mdt> popped =
            TEKCO_AnonymizationBatchUtils.popConfigsForObject('Account', configs);

        System.assertEquals(2, popped.size(), 'Two Account configs popped');
        System.assertEquals(1, configs.size(), 'One Contact config remains');
        System.assertEquals('Contact', configs[0].TEKCO_ObjectApiName__c);
    }

    @isTest
    static void popConfigsForObject_emptyWhenNoMatch() {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs = new List<TEKCO_AnonymizationFieldConfig__mdt>{
            new TEKCO_AnonymizationFieldConfig__mdt(TEKCO_ObjectApiName__c = 'Contact', TEKCO_FieldApiName__c = 'FirstName')
        };

        List<TEKCO_AnonymizationFieldConfig__mdt> popped =
            TEKCO_AnonymizationBatchUtils.popConfigsForObject('Account', configs);

        System.assertEquals(0, popped.size(), 'Nothing popped for non-matching object');
        System.assertEquals(1, configs.size(), 'Original list unchanged');
    }
}
