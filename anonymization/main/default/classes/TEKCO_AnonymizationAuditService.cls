public class TEKCO_AnonymizationAuditService {

    // Called by AnonymizationBatch on final object (updates processed + failed counts)
    public static void finalize(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed, List<String> errors
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed,
                recordsFailed > 0 ? 'Partial' : 'Success', Datetime.now(), errors);
    }

    // Called by ContentDocumentBatch and FieldHistoryBatch (no count fields)
    public static void finalize(Id auditLogId, Integer recordsFailed, List<String> errors) {
        persist(auditLogId, null, null,
                recordsFailed > 0 ? 'Partial' : 'Success', Datetime.now(), errors);
    }

    // Called by AnonymizationBatch between objects — intermediate running state
    public static void markRunning(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed, List<String> errors
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed, 'Running', null, errors);
    }

    // Called by AnonymizationBatch on chain failure (updates processed + failed counts)
    public static void closeFailed(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed, List<String> errors, String chainError
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed,
                'Failed', Datetime.now(), combined(errors, chainError));
    }

    // Called by ContentDocumentBatch and FieldHistoryBatch on chain failure (no count fields)
    public static void closeFailed(Id auditLogId, Integer recordsFailed, List<String> errors, String chainError) {
        persist(auditLogId, null, null, 'Failed', Datetime.now(), combined(errors, chainError));
    }

    private static List<String> combined(List<String> errors, String chainError) {
        List<String> all = new List<String>(errors);
        all.add('Chain error in finish(): ' + chainError);
        return all;
    }

    private static void persist(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed,
        String status, Datetime endTime, List<String> errors
    ) {
        if (auditLogId == null) return;
        try {
            TEKCO_AnonymizationAuditLog__c log = new TEKCO_AnonymizationAuditLog__c(
                Id                    = auditLogId,
                TEKCO_Status__c       = status,
                TEKCO_EndTime__c      = endTime,
                TEKCO_ErrorMessage__c = errors.isEmpty() ? null : String.join(errors, '\n')
            );
            if (recordsProcessed != null) log.TEKCO_RecordsProcessed__c = recordsProcessed;
            if (recordsFailed    != null) log.TEKCO_RecordsFailed__c    = recordsFailed;
            update log;
        } catch (Exception e) {}
    }
}
