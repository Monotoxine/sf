public inherited sharing class TEKCO_AnonymizationAuditService {

    public static void finalize(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed,
        Integer documentsDeleted, Integer historyRecordsDeleted, List<String> errors
    ) {
        finalize(auditLogId, recordsProcessed, recordsFailed,
                 documentsDeleted, historyRecordsDeleted, 0, errors);
    }

    public static void finalize(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed,
        Integer documentsDeleted, Integer historyRecordsDeleted, Integer chunksFailed,
        List<String> errors
    ) {
        Boolean partial = recordsFailed > 0 || (chunksFailed != null && chunksFailed > 0);
        persist(auditLogId, recordsProcessed, recordsFailed,
                documentsDeleted, historyRecordsDeleted,
                partial ? 'Partial' : 'Success', Datetime.now(), errors, null);
    }

    public static void markRunning(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed, List<String> errors
    ) {
        markRunning(auditLogId, recordsProcessed, recordsFailed, errors, null);
    }

    /** Also records the job now running, which the concurrency guard checks. */
    public static void markRunning(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed, List<String> errors,
        Id jobId
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed,
                null, null, 'Running', null, errors, jobId);
    }

    public static void closeFailed(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed,
        Integer documentsDeleted, Integer historyRecordsDeleted,
        List<String> errors, String chainError
    ) {
        persist(auditLogId, recordsProcessed, recordsFailed,
                documentsDeleted, historyRecordsDeleted,
                'Failed', Datetime.now(), combined(errors, chainError), null);
    }

    private static List<String> combined(List<String> errors, String chainError) {
        List<String> all = new List<String>(errors);
        all.add('Chain error in finish(): ' + chainError);
        return all;
    }

    private static void persist(
        Id auditLogId, Integer recordsProcessed, Integer recordsFailed,
        Integer documentsDeleted, Integer historyRecordsDeleted,
        String status, Datetime endTime, List<String> errors, Id jobId
    ) {
        if (auditLogId == null) return;
        try {
            TEKCO_AnonymizationAuditLog__c log = new TEKCO_AnonymizationAuditLog__c(
                Id                    = auditLogId,
                TEKCO_Status__c       = status,
                TEKCO_EndTime__c      = endTime,
                TEKCO_ErrorMessage__c = errorMessage(errors)
            );
            if (jobId                 != null) log.TEKCO_JobId__c                 = String.valueOf(jobId);
            if (recordsProcessed      != null) log.TEKCO_RecordsProcessed__c      = recordsProcessed;
            if (recordsFailed         != null) log.TEKCO_RecordsFailed__c         = recordsFailed;
            if (documentsDeleted      != null) log.TEKCO_DocumentsDeleted__c      = documentsDeleted;
            if (historyRecordsDeleted != null) log.TEKCO_HistoryRecordsDeleted__c = historyRecordsDeleted;
            update log;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR,
                'Failed to persist audit log ' + auditLogId + ': ' + e.getMessage());
        }
    }

    /** The joined errors, cut to what TEKCO_ErrorMessage__c can hold. */
    @TestVisible
    private static String errorMessage(List<String> errors) {
        if (errors == null || errors.isEmpty()) return null;
        String message = String.join(errors, '\n');
        Integer maxLength = TEKCO_AnonymizationAuditLog__c.TEKCO_ErrorMessage__c.getDescribe().getLength();
        return message.length() > maxLength ? message.abbreviate(maxLength) : message;
    }
}
