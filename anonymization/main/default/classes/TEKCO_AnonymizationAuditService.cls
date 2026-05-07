public class TEKCO_AnonymizationAuditService {

    public static void finalize(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed, List<String> errors
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed,
                recordsFailed > 0 ? 'Partial' : 'Success', Datetime.now(), errors);
    }

    public static void markRunning(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed, List<String> errors
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed, 'Running', null, errors);
    }

    public static void closeFailed(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed, List<String> errors, String chainError
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed,
                'Failed', Datetime.now(), combined(errors, chainError));
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
