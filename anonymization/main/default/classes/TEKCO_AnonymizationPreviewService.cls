/**
 * @description Before/after preview of what an anonymization run would write, on a bounded
 *              sample of records and with NO DML of any kind.
 *
 *              Why it exists: the existing preview only counts records. A misconfigured pattern
 *              (the ALH_EMAIL_PLUS_EXTERNALID case) produced a run reported as Success while the
 *              targeted emails were left intact — and the data was already destroyed elsewhere by
 *              the time anyone noticed. Showing the produced values before launching turns that
 *              class of bug into something visible in one click.
 *
 *              It reuses TEKCO_AnonymizationScopeQueryBuilder for the field selection and
 *              TEKCO_AnonymizationExecuteService.applyPatternsTo() for the transformation, so the
 *              preview cannot drift from the run: there is a single implementation of both.
 *
 *              Both chains are served: previewByCriteria() for the brand/object/record-type tab,
 *              previewByIds() for the ID list tab. Nothing here is org-specific — brand scoping
 *              goes through TEKCO_AnonymizationOrgConfigService like everywhere else, so TEKCO
 *              orgs and Portugal behave the same.
 *
 *              `without sharing`, deliberately and for the same reason the batches are: the run
 *              anonymizes org-wide regardless of the launching user's record access. A preview
 *              reading with sharing would hide rows the run is going to destroy — a preview that
 *              reassures about records it never looked at is worse than no preview. Access is
 *              gated by the TEKCO_AnonymizeData custom permission on the controller endpoints,
 *              and nothing here writes.
 */
public without sharing class TEKCO_AnonymizationPreviewService {

    /** Hard ceiling on the sample, whatever the UI asks for: bounds heap, SOQL rows and CPU. */
    public static final Integer MAX_SAMPLE_SIZE = 20;
    private static final Integer DEFAULT_SAMPLE_SIZE = 5;
    /** Values are for eyeballing, not for export — long text bodies are truncated. */
    private static final Integer MAX_VALUE_LENGTH = 120;
    private static final String  PATTERN_EMAIL_LOREM = 'EMAIL_MESSAGE_LOREM';

    public class PreviewRowDTO {
        @AuraEnabled public String  recordId;
        @AuraEnabled public String  fieldApiName;
        @AuraEnabled public String  patternType;
        @AuraEnabled public String  beforeValue;
        @AuraEnabled public String  afterValue;
    }

    public class PreviewSampleDTO {
        @AuraEnabled public String        objectApiName;
        @AuraEnabled public Integer       recordsSampled    = 0;
        @AuraEnabled public Integer       recordsChanged    = 0;
        @AuraEnabled public Integer       recordsUnchanged  = 0;
        @AuraEnabled public Integer       recordsToDelete   = 0;
        @AuraEnabled public List<PreviewRowDTO> rows        = new List<PreviewRowDTO>();
        @AuraEnabled public List<String>  warnings          = new List<String>();
    }

    /**
     * Sample of the By Criteria scope: same brand condition, same record-type filter and same
     * per-object additional filter the batch would use.
     */
    public static PreviewSampleDTO previewByCriteria(
        String objectApiName,
        List<String> selectedBrands,
        List<String> selectedRecordTypes,
        List<String> excludedFields,
        Integer sampleSize
    ) {
        String safeObject = TEKCO_AnonymizationBatchUtils.requireConfiguredObject(objectApiName);

        List<TEKCO_AnonymizationFieldConfig__mdt> configs =
            filterConfigs(loadConfigs(safeObject), selectedRecordTypes, excludedFields);

        List<String> conditions = new List<String>();
        conditions.add(TEKCO_AnonymizationOrgConfigService.buildBrandCondition(safeObject, selectedBrands));
        conditions.add(recordTypeCondition(safeObject, selectedRecordTypes, configs));
        conditions.add(additionalFilterOf(configs));

        return runPreview(safeObject, configs, conditions, null, sampleSize);
    }

    /**
     * Sample of a By ID scope. Only the first MAX_SAMPLE_SIZE ids are ever bound, so a list of
     * 50 000 records previews exactly as cheaply as a list of five.
     */
    public static PreviewSampleDTO previewByIds(
        String objectApiName,
        List<Id> recordIds,
        List<String> excludedFields,
        Integer sampleSize
    ) {
        String safeObject = TEKCO_AnonymizationBatchUtils.requireConfiguredObject(objectApiName);

        PreviewSampleDTO empty = new PreviewSampleDTO();
        empty.objectApiName = safeObject;
        if (recordIds == null || recordIds.isEmpty()) {
            empty.warnings.add('No record ID resolved for ' + safeObject + '.');
            return empty;
        }

        Integer limitSize = boundedSize(sampleSize);
        List<Id> sampleIds = new List<Id>();
        for (Id recordId : recordIds) {
            if (sampleIds.size() >= limitSize) break;
            sampleIds.add(recordId);
        }

        List<TEKCO_AnonymizationFieldConfig__mdt> configs =
            filterConfigs(loadConfigs(safeObject), null, excludedFields);

        return runPreview(
            safeObject, configs, new List<String>{ 'Id IN :sampleIds' },
            new Map<String, Object>{ 'sampleIds' => sampleIds }, limitSize
        );
    }

    // ---------------------------------------------------------------- internals

    /**
     * The single read-and-transform path. Queries at most `sampleSize` records, applies the
     * patterns in memory and throws the modified SObjects away — no update, no delete, ever.
     */
    private static PreviewSampleDTO runPreview(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs,
        List<String> conditions,
        Map<String, Object> binds,
        Integer sampleSize
    ) {
        PreviewSampleDTO result = new PreviewSampleDTO();
        result.objectApiName    = objectApiName;

        Map<String, TEKCO_AnonymizationPattern__mdt> patternsByType =
            TEKCO_AnonymizationBatchUtils.buildPatternMap();

        TEKCO_AnonymizationScopeQueryBuilder.FieldSelection selection =
            TEKCO_AnonymizationScopeQueryBuilder.buildFieldSelection(
                objectApiName, configs, patternsByType
            );
        result.warnings.addAll(selection.errors);

        if (selection.validConfigs.isEmpty()) {
            result.warnings.add(
                'No field-level pattern applies to ' + objectApiName
                + ' with the current selection — nothing to show.'
            );
            return result;
        }

        Integer limitSize = boundedSize(sampleSize);
        String soql = TEKCO_AnonymizationScopeQueryBuilder.selectClause(selection.fields)
            + ' FROM ' + objectApiName
            + TEKCO_AnonymizationScopeQueryBuilder.whereClause(conditions)
            + ' LIMIT ' + limitSize;

        List<SObject> sample;
        try {
            sample = Database.queryWithBinds(
                soql,
                binds == null ? new Map<String, Object>() : binds,
                // SYSTEM_MODE like the batches: the preview must show what the run will do.
                // Reading in USER_MODE could strip a field the run would still anonymize and
                // turn the preview into a false reassurance.
                AccessLevel.SYSTEM_MODE
            );
        } catch (Exception e) {
            result.warnings.add('Query failed: ' + e.getMessage());
            return result;
        }

        if (sample.isEmpty()) {
            result.warnings.add('No record matches the current selection on ' + objectApiName + '.');
            return result;
        }

        Map<Id, String> recordTypeDevNameById = selection.needsRecordTypeId
            ? loadRecordTypeDevNames(objectApiName)
            : new Map<Id, String>();

        for (SObject record : sample) {
            result.recordsSampled++;
            Map<String, String> beforeByField = new Map<String, String>();

            TEKCO_AnonymizationExecuteService.RecordOutcome outcome =
                TEKCO_AnonymizationExecuteService.applyPatternsTo(
                    record, selection.validConfigs, patternsByType,
                    recordTypeDevNameById, beforeByField
                );

            if (outcome.toDelete) {
                result.recordsToDelete++;
                result.rows.add(deletionRow(record.Id));
                continue;
            }
            if (!outcome.modified) {
                result.recordsUnchanged++;
                continue;
            }

            result.recordsChanged++;
            for (String fieldApiName : beforeByField.keySet()) {
                PreviewRowDTO row = new PreviewRowDTO();
                row.recordId     = String.valueOf(record.Id);
                row.fieldApiName = fieldApiName;
                row.patternType  = patternTypeFor(selection.validConfigs, fieldApiName);
                row.beforeValue  = truncate(beforeByField.get(fieldApiName));
                row.afterValue   = truncate(readString(record, fieldApiName));
                result.rows.add(row);
            }
        }
        return result;
    }

    /** A non-draft EmailMessage is not masked but deleted — say so rather than showing nothing. */
    private static PreviewRowDTO deletionRow(Id recordId) {
        PreviewRowDTO row = new PreviewRowDTO();
        row.recordId     = String.valueOf(recordId);
        row.fieldApiName = '(whole record)';
        row.patternType  = PATTERN_EMAIL_LOREM;
        row.beforeValue  = '(record exists)';
        row.afterValue   = '(record deleted)';
        return row;
    }

    private static List<TEKCO_AnonymizationFieldConfig__mdt> loadConfigs(String objectApiName) {
        return [
            SELECT DeveloperName, TEKCO_ObjectApiName__c, TEKCO_FieldApiName__c,
                   TEKCO_PatternType__c, TEKCO_IsActive__c,
                   TEKCO_RecordTypeDeveloperName__c, TEKCO_DeleteHistory__c,
                   TEKCO_AdditionalFilter__c
            FROM TEKCO_AnonymizationFieldConfig__mdt
            WHERE TEKCO_ObjectApiName__c = :objectApiName AND TEKCO_IsActive__c = true
        ];
    }

    /**
     * Applies the two narrowing choices the user makes in the UI, with the exact key format
     * startAnonymization() uses so the preview reflects the launch, not a variant of it.
     */
    private static List<TEKCO_AnonymizationFieldConfig__mdt> filterConfigs(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs,
        List<String> selectedRecordTypes,
        List<String> excludedFields
    ) {
        Set<String> rtFilter = (selectedRecordTypes == null || selectedRecordTypes.isEmpty())
            ? null : new Set<String>(selectedRecordTypes);
        Set<String> excluded = excludedFields == null
            ? new Set<String>() : new Set<String>(excludedFields);

        List<TEKCO_AnonymizationFieldConfig__mdt> kept =
            new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            String rtDevName = fc.TEKCO_RecordTypeDeveloperName__c;
            if (rtFilter != null && String.isNotBlank(rtDevName) && !rtFilter.contains(rtDevName)) {
                continue;
            }
            String fieldKey = fc.TEKCO_ObjectApiName__c + '.' + fc.TEKCO_FieldApiName__c + '.'
                + (rtDevName != null ? rtDevName : '');
            if (excluded.contains(fieldKey)) continue;
            kept.add(fc);
        }
        return kept;
    }

    /** First non-blank per-object additional filter, same rule as startAnonymization(). */
    private static String additionalFilterOf(List<TEKCO_AnonymizationFieldConfig__mdt> configs) {
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            if (String.isNotBlank(fc.TEKCO_AdditionalFilter__c)) return fc.TEKCO_AdditionalFilter__c;
        }
        return null;
    }

    private static String recordTypeCondition(
        String objectApiName,
        List<String> selectedRecordTypes,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        if (selectedRecordTypes == null || selectedRecordTypes.isEmpty()) return null;
        if (!TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, 'recordtypeid')) return null;

        // Only the record types this object actually declares — a Case record type must not end
        // up filtering an Account query.
        Set<String> declared = new Set<String>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            if (String.isNotBlank(fc.TEKCO_RecordTypeDeveloperName__c)) {
                declared.add(fc.TEKCO_RecordTypeDeveloperName__c);
            }
        }
        List<String> escaped = new List<String>();
        for (String rt : selectedRecordTypes) {
            if (declared.contains(rt)) escaped.add('\'' + String.escapeSingleQuotes(rt) + '\'');
        }
        if (escaped.isEmpty()) return null;
        escaped.sort();
        return 'RecordType.DeveloperName IN (' + String.join(escaped, ', ') + ')';
    }

    private static Map<Id, String> loadRecordTypeDevNames(String objectApiName) {
        Map<Id, String> byId = new Map<Id, String>();
        for (RecordType rt : [
            SELECT Id, DeveloperName FROM RecordType WHERE SobjectType = :objectApiName
        ]) {
            byId.put(rt.Id, rt.DeveloperName);
        }
        return byId;
    }

    private static String patternTypeFor(
        List<TEKCO_AnonymizationFieldConfig__mdt> configs, String fieldApiName
    ) {
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            if (fieldApiName.equalsIgnoreCase(fc.TEKCO_FieldApiName__c)) return fc.TEKCO_PatternType__c;
        }
        return '';
    }

    private static String readString(SObject record, String fieldApiName) {
        try {
            Object value = record.get(fieldApiName);
            return value == null ? null : String.valueOf(value);
        } catch (Exception e) {
            return null;
        }
    }

    private static String truncate(String value) {
        if (value == null) return '';
        return value.length() > MAX_VALUE_LENGTH
            ? value.substring(0, MAX_VALUE_LENGTH) + '…'
            : value;
    }

    private static Integer boundedSize(Integer requested) {
        if (requested == null || requested <= 0) return DEFAULT_SAMPLE_SIZE;
        return requested > MAX_SAMPLE_SIZE ? MAX_SAMPLE_SIZE : requested;
    }
}
