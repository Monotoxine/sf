/**
 * @description Decides which batch runs next, and ends the run (bypass restore, audit log).
 */
public without sharing class TEKCO_AnonymizationChainRunner {

    public static Id startNext(TEKCO_AnonymizationRunContext ctx) {
        if (ctx == null) return null;

        try {
            while (ctx.hasSteps()) {
                String step  = ctx.popStep();
                String phase = TEKCO_AnonymizationRunContext.phaseOf(step);
                String key   = TEKCO_AnonymizationRunContext.keyOf(step);

                Id jobId = startStep(phase, key, ctx);
                if (jobId != null) {
                    TEKCO_AnonymizationAuditService.markRunning(
                        ctx.auditLogId, ctx.recordsProcessed, ctx.recordsFailed, ctx.errors, jobId
                    );
                    return jobId;
                }
            }

            complete(ctx);
            return null;
        } catch (Exception e) {
            restoreBypassQuietly(ctx);
            TEKCO_AnonymizationAuditService.closeFailed(
                ctx.auditLogId, ctx.recordsProcessed, ctx.recordsFailed,
                ctx.documentsDeleted, ctx.historyRecordsDeleted, ctx.errors, e.getMessage()
            );
            return null;
        }
    }

    private static Id startStep(String phase, String key, TEKCO_AnonymizationRunContext ctx) {
        if (phase == TEKCO_AnonymizationRunContext.PHASE_FIELD) {
            if (ctx.byId && ctx.recordIdsFor(key).isEmpty()) return null;
            return Database.executeBatch(
                new TEKCO_AnonymizationFieldBatch(key, ctx),
                TEKCO_AnonymizationFieldBatch.DEFAULT_BATCH_SIZE
            );
        }

        if (phase == TEKCO_AnonymizationRunContext.PHASE_CD) {
            TEKCO_AnonymizationFieldConfig__mdt config = configByDevName(key);
            if (config == null || String.isBlank(config.TEKCO_ObjectApiName__c)) return null;
            if (ctx.byId && ctx.recordIdsFor(config.TEKCO_ObjectApiName__c).isEmpty()) return null;
            return Database.executeBatch(
                new TEKCO_ContentDocumentBatch(key, ctx),
                TEKCO_ContentDocumentBatch.batchSizeFor(ctx.byId)
            );
        }

        if (phase == TEKCO_AnonymizationRunContext.PHASE_HISTORY) {
            if (ctx.historyConfigDevNamesFor(key).isEmpty()) return null;
            if (ctx.byId && ctx.recordIdsFor(key).isEmpty()) return null;
            return Database.executeBatch(
                new TEKCO_FieldHistoryBatch(key, ctx),
                TEKCO_FieldHistoryBatch.DEFAULT_BATCH_SIZE
            );
        }

        return null;
    }

    private static void complete(TEKCO_AnonymizationRunContext ctx) {
        TEKCO_AnonymizationBypassService.restore(ctx.bypassSnapshot);
        TEKCO_AnonymizationAuditService.finalize(
            ctx.auditLogId, ctx.recordsProcessed, ctx.recordsFailed,
            ctx.documentsDeleted, ctx.historyRecordsDeleted, ctx.chunksFailed, ctx.errors
        );
    }

    /** Counts the chunks of a finished batch that threw and were rolled back. */
    public static void recordChunkFailures(Id jobId, String stepLabel, TEKCO_AnonymizationRunContext ctx) {
        if (jobId == null || ctx == null) return;
        List<AsyncApexJob> jobs = [
            SELECT NumberOfErrors, ExtendedStatus FROM AsyncApexJob WHERE Id = :jobId LIMIT 1
        ];
        if (jobs.isEmpty() || jobs[0].NumberOfErrors == null || jobs[0].NumberOfErrors == 0) return;
        ctx.addChunksFailed(jobs[0].NumberOfErrors);
        ctx.addErrors(new List<String>{
            stepLabel + ': ' + jobs[0].NumberOfErrors
            + ' chunk(s) rolled back, their records left unchanged: ' + jobs[0].ExtendedStatus
        });
    }

    private static void restoreBypassQuietly(TEKCO_AnonymizationRunContext ctx) {
        try {
            TEKCO_AnonymizationBypassService.restore(ctx.bypassSnapshot);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'Bypass restore failed; flags may remain enabled: ' + e.getMessage()
            );
        }
    }

    public static TEKCO_AnonymizationFieldConfig__mdt configByDevName(String developerName) {
        List<TEKCO_AnonymizationFieldConfig__mdt> configs =
            TEKCO_AnonymizationConfigSelector.loadFieldConfigsByDevNames(new List<String>{ developerName });
        return configs.isEmpty() ? null : configs[0];
    }
}
