public inherited sharing class TEKCO_AnonymizationAuditService {

    public static void finalize(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed,
        Integer documentsDeleted, Integer historyRecordsDeleted, List<String> errors
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed,
                documentsDeleted, historyRecordsDeleted,
                recordsFailed > 0 ? 'Partial' : 'Success', Datetime.now(), errors);
    }

    public static void markRunning(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed, List<String> errors
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed,
                null, null, 'Running', null, errors);
    }

    public static void closeFailed(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed,
        Integer documentsDeleted, Integer historyRecordsDeleted,
        List<String> errors, String chainError
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed,
                documentsDeleted, historyRecordsDeleted,
                'Failed', Datetime.now(), combined(errors, chainError));
    }

    private static List<String> combined(List<String> errors, String chainError) {
        List<String> all = new List<String>(errors);
        all.add('Chain error in finish(): ' + chainError);
        return all;
    }

    private static void persist(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed,
        Integer documentsDeleted, Integer historyRecordsDeleted,
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
            if (recordsProcessed      != null) log.TEKCO_RecordsProcessed__c      = recordsProcessed;
            if (recordsFailed         != null) log.TEKCO_RecordsFailed__c         = recordsFailed;
            if (documentsDeleted      != null) log.TEKCO_DocumentsDeleted__c      = documentsDeleted;
            if (historyRecordsDeleted != null) log.TEKCO_HistoryRecordsDeleted__c = historyRecordsDeleted;
            update log;
        } catch (Exception e) {
            // Nothing else can record this — the audit log IS the reporting channel.
            System.debug(LoggingLevel.ERROR,
                'Failed to persist audit log ' + auditLogId + ': ' + e.getMessage());
        }
    }
}
