/**
 * @description 
 */
public class TEKCO_AnonymizationRunContext {

    public static final Integer MAX_ACCUMULATED_ERRORS = 200;
    public static final Integer MAX_ERROR_MSG_LENGTH   = 200;
    public static final Integer MAX_CAPTURED_ERRORS    = 50;

    public static final String PHASE_FIELD   = 'FIELD';
    public static final String PHASE_CD      = 'CD';
    public static final String PHASE_HISTORY = 'HISTORY';

    private static final String STEP_SEPARATOR = ':';


    public Id      auditLogId;
    public Boolean byId = false;
    public TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;

    public List<String> selectedBrands = new List<String>();
    public Map<String, String> additionalFiltersByObject = new Map<String, String>();

    public List<String> selectedRecordTypes = new List<String>();
    public Map<String, List<Id>> recordIdsByObject = new Map<String, List<Id>>();
    public Map<String, List<String>> configDevNamesByObject = new Map<String, List<String>>();
    public Map<String, List<String>> historyConfigDevNamesByObject = new Map<String, List<String>>();

    public List<String> steps = new List<String>();

    // ─── Results ─────────────────────────────────────────────────────────────

    public Integer recordsProcessed      = 0;
    public Integer recordsFailed         = 0;
    public Integer documentsDeleted      = 0;
    public Integer historyRecordsDeleted = 0;
    public List<String> errors           = new List<String>();

    // ─── Plan handling ───────────────────────────────────────────────────────

    public void addStep(String phase, String key) {
        if (String.isBlank(phase) || String.isBlank(key)) return;
        steps.add(phase + STEP_SEPARATOR + key);
    }

    public Boolean hasSteps() {
        return !steps.isEmpty();
    }

    /** Removes and returns the next step, or null when the run is done. */
    public String popStep() {
        return steps.isEmpty() ? null : steps.remove(0);
    }

    public static String phaseOf(String step) {
        return step == null ? null : step.substringBefore(STEP_SEPARATOR);
    }

    /** Everything after the first separator, so a key containing one survives. */
    public static String keyOf(String step) {
        return step == null ? null : step.substringAfter(STEP_SEPARATOR);
    }

    // ─── Accumulation ────────────────────────────────────────────────────────

    public void addProcessed(Integer count) {
        if (count != null) recordsProcessed += count;
    }

    public void addFailed(Integer count) {
        if (count != null) recordsFailed += count;
    }

    public void addDocumentsDeleted(Integer count) {
        if (count != null) documentsDeleted += count;
    }

    public void addHistoryDeleted(Integer count) {
        if (count != null) historyRecordsDeleted += count;
    }

    /**
     * Truncates one message to MAX_ERROR_MSG_LENGTH. Public because the error producers —
     * the execute service and the two delete services — cap before handing their lists over.
     */
    public static String cap(String message) {
        return (message != null && message.length() > MAX_ERROR_MSG_LENGTH)
            ? message.substring(0, MAX_ERROR_MSG_LENGTH)
            : message;
    }

    /** Capped in length and in count, so a failing run cannot grow the stateful payload. */
    public void addErrors(List<String> newErrors) {
        if (newErrors == null) return;
        for (String message : newErrors) {
            if (errors.size() >= MAX_ACCUMULATED_ERRORS) return;
            errors.add(cap(message));
        }
    }

    // ─── Scope lookups ───────────────────────────────────────────────────────

    public List<String> configDevNamesFor(String objectApiName) {
        List<String> devNames = configDevNamesByObject.get(objectApiName);
        return devNames != null ? devNames : new List<String>();
    }

    public List<String> historyConfigDevNamesFor(String objectApiName) {
        List<String> devNames = historyConfigDevNamesByObject.get(objectApiName);
        return devNames != null ? devNames : new List<String>();
    }

    public String additionalFilterFor(String objectApiName) {
        return additionalFiltersByObject.get(objectApiName);
    }

    /** The user's record-type selection, never null so callers can pass it straight through. */
    public List<String> recordTypeSelection() {
        return selectedRecordTypes != null ? selectedRecordTypes : new List<String>();
    }

    public List<Id> recordIdsFor(String objectApiName) {
        List<Id> ids = recordIdsByObject.get(objectApiName);
        return ids != null ? ids : new List<Id>();
    }
}
