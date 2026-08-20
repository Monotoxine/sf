/**
 * @description Shared Phase 2 delete logic, called from TEKCO_ContentDocumentBatch. The two
 *              chains once had a batch each, carrying byte-identical copies of this in their
 *              execute() methods; extracting it here is what made merging them possible.
 *
 *              Deletes, in order: ServiceReport (must go before ContentDocument), then
 *              ContentDocument via ContentDocumentLink, then Attachment.
 *
 *              DML row limits: a single execute() chunk may resolve far more files than the
 *              10 000-row DML ceiling — one parent can own hundreds of documents. Rather than
 *              letting the chunk die with a LimitException, deletes stop at the remaining
 *              budget and the shortfall is reported so the run can be repeated for the rest.
 */
public inherited sharing class TEKCO_ContentDocumentDeleteService {

    /** Leave headroom so the caller can still write its audit log update. */
    private static final Integer DML_ROW_RESERVE = 200;

    public class DeleteOutcome {
        public Integer      recordsDeleted = 0;
        public Integer      recordsFailed  = 0;
        public List<String> errors         = new List<String>();
    }

    public static DeleteOutcome deleteForParentIds(Set<Id> parentIds) {
        DeleteOutcome outcome = new DeleteOutcome();
        if (parentIds == null || parentIds.isEmpty()) return outcome;

        deleteServiceReports(parentIds, outcome);
        deleteContentDocuments(parentIds, outcome);
        deleteAttachments(parentIds, outcome);
        return outcome;
    }

    private static void deleteServiceReports(Set<Id> parentIds, DeleteOutcome outcome) {
        try {
            List<SObject> serviceReports = Database.query(
                'SELECT Id FROM ServiceReport WHERE ParentId IN :parentIds'
            );
            deleteAll(serviceReports, 'ServiceReport', outcome);
        } catch (Exception e) {
            // ServiceReport is not available in every org — nothing to do.
        }
    }

    private static void deleteContentDocuments(Set<Id> parentIds, DeleteOutcome outcome) {
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink cdl : [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :parentIds
        ]) {
            contentDocumentIds.add(cdl.ContentDocumentId);
        }
        if (contentDocumentIds.isEmpty()) return;

        List<ContentDocument> toDelete = new List<ContentDocument>();
        for (Id cdId : contentDocumentIds) toDelete.add(new ContentDocument(Id = cdId));
        deleteAll(toDelete, 'ContentDocument', outcome);
    }

    private static void deleteAttachments(Set<Id> parentIds, DeleteOutcome outcome) {
        deleteAll(
            [SELECT Id FROM Attachment WHERE ParentId IN :parentIds],
            'Attachment',
            outcome
        );
    }

    /**
     * Deletes in slices sized to the remaining DML row budget. Anything that does not fit is
     * reported rather than attempted, so the chunk completes instead of throwing.
     */
    private static void deleteAll(List<SObject> records, String label, DeleteOutcome outcome) {
        if (records == null || records.isEmpty()) return;

        Integer budget = Limits.getLimitDmlRows() - Limits.getDmlRows() - DML_ROW_RESERVE;
        if (budget <= 0) {
            addError(outcome, label + ': DML row limit reached, ' + records.size()
                + ' record(s) not deleted. Re-run the anonymization to remove the remainder.');
            outcome.recordsFailed += records.size();
            return;
        }

        Integer processed = 0;
        while (processed < records.size() && budget > 0) {
            Integer sliceSize = Math.min(Math.min(budget, 10000), records.size() - processed);
            List<SObject> slice = new List<SObject>();
            for (Integer i = processed; i < processed + sliceSize; i++) slice.add(records[i]);

            for (Database.DeleteResult dr : Database.delete(slice, false)) {
                if (dr.isSuccess()) {
                    outcome.recordsDeleted++;
                } else {
                    outcome.recordsFailed++;
                    List<String> msgs = new List<String>();
                    for (Database.Error e : dr.getErrors()) msgs.add(e.getMessage());
                    addError(outcome, label + ' ' + dr.getId() + ': ' + String.join(msgs, '; '));
                }
            }
            processed += sliceSize;
            budget = Limits.getLimitDmlRows() - Limits.getDmlRows() - DML_ROW_RESERVE;
        }

        if (processed < records.size()) {
            Integer remaining = records.size() - processed;
            outcome.recordsFailed += remaining;
            addError(outcome, label + ': DML row limit reached, ' + remaining
                + ' record(s) not deleted. Re-run the anonymization to remove the remainder.');
        }
    }

    private static void addError(DeleteOutcome outcome, String message) {
        if (outcome.errors.size() < TEKCO_AnonymizationRunContext.MAX_CAPTURED_ERRORS) {
            outcome.errors.add(TEKCO_AnonymizationRunContext.cap(message));
        }
    }
}
