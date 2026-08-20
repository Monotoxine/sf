/**
 * @description State shared by every batch of one anonymization run, plus the plan of what is
 *              left to do.
 *
 *              Before this class each batch declared the same eight-odd values as its own fields
 *              and recopied them constructor to constructor across six classes. That is the direct
 *              cause of the recordsFailed counter that stopped accumulating: adding a counter
 *              meant editing six constructors and six finish() blocks, and forgetting one broke
 *              nothing visibly. Here a counter is added once.
 *
 *              Carried by Database.Stateful, so everything in it is serialized between chunks.
 *              Heap is neutral by construction: Apex passes maps and lists by reference, so this
 *              groups references that already existed instead of copying anything. It replaces
 *              remainingObjects / remainingContentDocConfigDevNames /
 *              remainingHistoryConfigDevNames with a single list of short step descriptors.
 *
 *              Serves both chains. By Criteria scopes on brands and filters; By ID scopes on
 *              recordIdsByObject. Same context, same steps, same counters.
 */
public class TEKCO_AnonymizationRunContext {

    /** Same ceiling the batches applied individually, now enforced in one place. */
    public static final Integer MAX_ACCUMULATED_ERRORS = 200;
    /** Per-message ceiling. */
    public static final Integer MAX_ERROR_MSG_LENGTH   = 200;
    /**
     * Ceiling on what one producer collects before handing its list over — the execute service
     * and the two delete services each stop here. Distinct from MAX_ACCUMULATED_ERRORS, which
     * bounds the whole run. This class owns the error contract in all three dimensions:
     * message length, per-producer count, and run total.
     */
    public static final Integer MAX_CAPTURED_ERRORS    = 50;

    public static final String PHASE_FIELD   = 'FIELD';
    public static final String PHASE_CD      = 'CD';
    public static final String PHASE_HISTORY = 'HISTORY';

    private static final String STEP_SEPARATOR = ':';

    // ─── Run identity ────────────────────────────────────────────────────────

    public Id      auditLogId;
    /** true = the run was launched from an ID list, false = from brand/object criteria. */
    public Boolean byId = false;
    public TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;

    // ─── Scope ───────────────────────────────────────────────────────────────

    /** By Criteria only. Empty = every brand. */
    public List<String> selectedBrands = new List<String>();
    /** By Criteria only: per-object SOQL fragment declared on the field configs. */
    public Map<String, String> additionalFiltersByObject = new Map<String, String>();
    /** By ID only: the records to touch, per object. Never used by the By Criteria chain. */
    public Map<String, List<Id>> recordIdsByObject = new Map<String, List<Id>>();

    /**
     * Field configs per object, as filtered by the controller — user exclusions and record-type
     * selection already applied. Batches reload from these developer names rather than from
     * everything active, which would resurrect the fields the user unchecked.
     */
    public Map<String, List<String>> configDevNamesByObject = new Map<String, List<String>>();
    /** Configs whose history must be purged, per object. */
    public Map<String, List<String>> historyConfigDevNamesByObject = new Map<String, List<String>>();

    // ─── Plan ────────────────────────────────────────────────────────────────

    /**
     * What is left to run, in order, as 'PHASE:key' descriptors — 'FIELD:Account',
     * 'CD:Case_Attachments', 'HISTORY:Account'. The key is an object API name for FIELD and
     * HISTORY, a field-config developer name for CD (a ContentDocument step can be scoped to
     * one record type, which only the config knows).
     */
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

    public List<Id> recordIdsFor(String objectApiName) {
        List<Id> ids = recordIdsByObject.get(objectApiName);
        return ids != null ? ids : new List<Id>();
    }
}
