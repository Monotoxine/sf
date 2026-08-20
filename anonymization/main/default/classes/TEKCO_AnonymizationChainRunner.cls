/**
 * @description Single owner of "what runs next" for an anonymization run.
 *
 *              Each batch used to name its own successors: TEKCO_AnonymizationBatch.finish() knew
 *              about TEKCO_ContentDocumentBatch AND TEKCO_FieldHistoryBatch, which in turn knew
 *              about each other, twice over for the By ID chain. Adding a phase meant editing four
 *              classes; changing a constructor meant re-checking six call sites — which is exactly
 *              how a rollback once left the chain compiling against a stale API.
 *
 *              Now every finish() is the same two lines: fold the chunk's results into the
 *              context, then call startNext(). The step list lives in the context, the wiring
 *              lives here, and terminating the run — restoring the bypass, finalizing the audit
 *              log — happens in one place instead of six.
 */
public without sharing class TEKCO_AnonymizationChainRunner {

    /**
     * Runs the next step of the plan, or closes the run when the plan is empty.
     *
     * Never throws: a failure to chain restores the bypass and closes the audit log as Failed.
     * Leaving the bypass raised would disable the org's automation for every later user.
     *
     * @return the AsyncApexJob Id of the batch that was started, null when the run ended here.
     */
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
                        ctx.auditLogId, ctx.recordsProcessed, ctx.recordsFailed, ctx.errors
                    );
                    return jobId;
                }
                // Step not runnable in this org (object absent, no config left): skip to the
                // next one rather than ending the run early.
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

    /** @return the job Id when a batch was enqueued for this step, null when it was skipped. */
    private static Id startStep(String phase, String key, TEKCO_AnonymizationRunContext ctx) {
        if (phase == TEKCO_AnonymizationRunContext.PHASE_FIELD) {
            if (ctx.byId) {
                if (ctx.recordIdsFor(key).isEmpty()) return null;
                return Database.executeBatch(
                    new TEKCO_AnonymizationByIdBatch(key, ctx),
                    TEKCO_AnonymizationByIdBatch.DEFAULT_BATCH_SIZE
                );
            }
            return Database.executeBatch(
                new TEKCO_AnonymizationBatch(key, ctx),
                TEKCO_AnonymizationBatch.DEFAULT_BATCH_SIZE
            );
        }

        if (phase == TEKCO_AnonymizationRunContext.PHASE_CD) {
            // key is a field-config developer name: a ContentDocument step can be scoped to one
            // record type, and only the config carries that.
            TEKCO_AnonymizationFieldConfig__mdt config = configByDevName(key);
            if (config == null || String.isBlank(config.TEKCO_ObjectApiName__c)) return null;

            if (ctx.byId) {
                if (ctx.recordIdsFor(config.TEKCO_ObjectApiName__c).isEmpty()) return null;
                return Database.executeBatch(
                    new TEKCO_ContentDocumentByIdBatch(key, ctx),
                    TEKCO_ContentDocumentByIdBatch.DEFAULT_BATCH_SIZE
                );
            }
            return Database.executeBatch(
                new TEKCO_ContentDocumentBatch(key, ctx),
                TEKCO_ContentDocumentBatch.DEFAULT_BATCH_SIZE
            );
        }

        if (phase == TEKCO_AnonymizationRunContext.PHASE_HISTORY) {
            if (ctx.historyConfigDevNamesFor(key).isEmpty()) return null;
            if (ctx.byId) {
                if (ctx.recordIdsFor(key).isEmpty()) return null;
                return Database.executeBatch(
                    new TEKCO_FieldHistoryByIdBatch(key, ctx),
                    TEKCO_FieldHistoryByIdBatch.DEFAULT_BATCH_SIZE
                );
            }
            return Database.executeBatch(
                new TEKCO_FieldHistoryBatch(key, ctx),
                TEKCO_FieldHistoryBatch.DEFAULT_BATCH_SIZE
            );
        }

        return null;
    }

    /** End of the plan: put the org's automation back, then write the final audit log. */
    private static void complete(TEKCO_AnonymizationRunContext ctx) {
        TEKCO_AnonymizationBypassService.restore(ctx.bypassSnapshot);
        TEKCO_AnonymizationAuditService.finalize(
            ctx.auditLogId, ctx.recordsProcessed, ctx.recordsFailed,
            ctx.documentsDeleted, ctx.historyRecordsDeleted, ctx.errors
        );
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
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(new List<String>{ developerName });
        return configs.isEmpty() ? null : configs[0];
    }
}
