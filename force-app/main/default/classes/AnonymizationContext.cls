/**
 * @description Immutable value object passed to every IAnonymizationStrategy.anonymize() call.
 *
 * Carries everything a strategy needs to produce its output:
 *   - the record being processed (read-only reference)
 *   - the name of the field being anonymized
 *   - the name of the external-ID field for this object (e.g. SAP_External_ID__c)
 *   - up to two strategy-specific parameters from metadata
 *
 * Convenience getters avoid null-pointer risks inside strategy implementations.
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public class AnonymizationContext {

    /** The SObject record currently being processed. Strategies must NOT write to it — the
     *  batch executor applies the returned value after all strategies have run. */
    public SObject record       { get; private set; }

    /** API name of the field being anonymized on this execution (e.g. 'FirstName'). */
    public String  fieldName    { get; private set; }

    /** API name of the external-ID field configured on the parent Anon_Object_Config__mdt
     *  (e.g. 'SAP_External_ID__c'). Null if not configured. */
    public String  externalIdField { get; private set; }

    /** First strategy parameter from Anon_Field_Config__mdt.Strategy_Param_1__c. Null if blank. */
    public String  param1       { get; private set; }

    /** Second strategy parameter from Anon_Field_Config__mdt.Strategy_Param_2__c. Null if blank. */
    public String  param2       { get; private set; }

    public AnonymizationContext(
        SObject record,
        String  fieldName,
        String  externalIdField,
        String  param1,
        String  param2
    ) {
        this.record          = record;
        this.fieldName       = fieldName;
        this.externalIdField = externalIdField;
        this.param1          = String.isBlank(param1) ? null : param1.trim();
        this.param2          = String.isBlank(param2) ? null : param2.trim();
    }

    /**
     * @description Returns the current field value as a String, or null if the field is empty.
     *              Safe to call even when the field is not present in the query projection
     *              (returns null in that case).
     */
    public String getCurrentValue() {
        try {
            Object val = record.get(fieldName);
            return val != null ? String.valueOf(val) : null;
        } catch (SObjectException e) {
            return null;
        }
    }

    /**
     * @description Returns the external ID value for this record, or null if the
     *              external ID field is not configured or not populated.
     */
    public String getExternalId() {
        if (String.isBlank(externalIdField)) {
            return null;
        }
        try {
            Object val = record.get(externalIdField);
            return val != null ? String.valueOf(val) : null;
        } catch (SObjectException e) {
            return null;
        }
    }
}
