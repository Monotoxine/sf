/**
 * @description Shared Phase 3 delete logic. TEKCO_FieldHistoryBatch and
 *              TEKCO_FieldHistoryByIdBatch previously carried byte-identical copies of this
 *              in their execute() methods; only their start() scoping differs.
 */
public inherited sharing class TEKCO_FieldHistoryDeleteService {

    private static final Integer MAX_CAPTURED_ERRORS = 50;

    public class DeleteOutcome {
        public Integer      recordsDeleted = 0;
        public Integer      recordsFailed  = 0;
        public List<String> errors         = new List<String>();
    }

    public static DeleteOutcome deleteHistoryRecords(List<SObject> scope) {
        DeleteOutcome outcome = new DeleteOutcome();
        if (scope == null || scope.isEmpty()) return outcome;

        for (Database.DeleteResult deleteResult : Database.delete(scope, false)) {
            if (deleteResult.isSuccess()) {
                outcome.recordsDeleted++;
            } else {
                outcome.recordsFailed++;
                if (outcome.errors.size() < MAX_CAPTURED_ERRORS) {
                    List<String> messages = new List<String>();
                    for (Database.Error dmlError : deleteResult.getErrors()) {
                        messages.add(dmlError.getMessage());
                    }
                    outcome.errors.add(
                        TEKCO_AnonymizationBatchUtils.cap(String.join(messages, '; '))
                    );
                }
            }
        }
        return outcome;
    }
}
