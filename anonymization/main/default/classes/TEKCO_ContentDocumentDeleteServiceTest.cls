@isTest
private class TEKCO_ContentDocumentDeleteServiceTest {

    private static Account newAccountWithFile(String name) {
        Account acc = new Account(Name = name);
        insert acc;

        ContentVersion cv = new ContentVersion(
            Title           = name + ' doc',
            PathOnClient    = 'doc.txt',
            VersionData     = Blob.valueOf('content'),
            IsMajorVersion  = true
        );
        insert cv;

        Id docId = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :cv.Id].ContentDocumentId;
        insert new ContentDocumentLink(
            ContentDocumentId = docId,
            LinkedEntityId    = acc.Id,
            ShareType         = 'V'
        );
        return acc;
    }

    @isTest
    static void deleteForParentIds_removesLinkedContentDocument() {
        Account acc = newAccountWithFile('WithDoc');

        Test.startTest();
        TEKCO_ContentDocumentDeleteService.DeleteOutcome outcome =
            TEKCO_ContentDocumentDeleteService.deleteForParentIds(new Set<Id>{ acc.Id });
        Test.stopTest();

        System.assertEquals(1, outcome.recordsDeleted, 'The linked document was deleted');
        System.assertEquals(0, outcome.recordsFailed, 'No failures');
        System.assert(outcome.errors.isEmpty(), 'No errors captured');
        System.assertEquals(
            0,
            [SELECT COUNT() FROM ContentDocumentLink WHERE LinkedEntityId = :acc.Id],
            'Link removed with the document'
        );
    }

    @isTest
    static void deleteForParentIds_removesAttachments() {
        Account acc = new Account(Name = 'WithAttachment');
        insert acc;
        insert new Attachment(ParentId = acc.Id, Name = 'a.txt', Body = Blob.valueOf('x'));
        insert new Attachment(ParentId = acc.Id, Name = 'b.txt', Body = Blob.valueOf('y'));

        Test.startTest();
        TEKCO_ContentDocumentDeleteService.DeleteOutcome outcome =
            TEKCO_ContentDocumentDeleteService.deleteForParentIds(new Set<Id>{ acc.Id });
        Test.stopTest();

        System.assertEquals(2, outcome.recordsDeleted, 'Both attachments deleted');
        System.assertEquals(
            0, [SELECT COUNT() FROM Attachment WHERE ParentId = :acc.Id], 'None left'
        );
    }

    @isTest
    static void deleteForParentIds_emptySet_returnsZeroes() {
        Test.startTest();
        TEKCO_ContentDocumentDeleteService.DeleteOutcome outcome =
            TEKCO_ContentDocumentDeleteService.deleteForParentIds(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, outcome.recordsDeleted);
        System.assertEquals(0, outcome.recordsFailed);
        System.assert(outcome.errors.isEmpty());
    }

    @isTest
    static void deleteForParentIds_nullSet_returnsZeroes() {
        Test.startTest();
        TEKCO_ContentDocumentDeleteService.DeleteOutcome outcome =
            TEKCO_ContentDocumentDeleteService.deleteForParentIds(null);
        Test.stopTest();

        System.assertEquals(0, outcome.recordsDeleted, 'Null scope handled without exception');
    }

    @isTest
    static void deleteForParentIds_parentWithNothingAttached_isNoOp() {
        Account acc = new Account(Name = 'Bare');
        insert acc;

        Test.startTest();
        TEKCO_ContentDocumentDeleteService.DeleteOutcome outcome =
            TEKCO_ContentDocumentDeleteService.deleteForParentIds(new Set<Id>{ acc.Id });
        Test.stopTest();

        System.assertEquals(0, outcome.recordsDeleted, 'Nothing to delete');
        System.assertEquals(0, outcome.recordsFailed, 'Absence of files is not a failure');
        System.assertEquals(
            1, [SELECT COUNT() FROM Account WHERE Id = :acc.Id], 'Parent itself untouched'
        );
    }

    @isTest
    static void deleteForParentIds_multipleParents_deletesAcrossAll() {
        Account a = newAccountWithFile('Multi A');
        Account b = newAccountWithFile('Multi B');

        Test.startTest();
        TEKCO_ContentDocumentDeleteService.DeleteOutcome outcome =
            TEKCO_ContentDocumentDeleteService.deleteForParentIds(new Set<Id>{ a.Id, b.Id });
        Test.stopTest();

        System.assertEquals(2, outcome.recordsDeleted, 'One document per parent');
    }
}
