/**
 * @description Contract for all anonymization strategy implementations.
 *
 * Each strategy is a standalone Apex class that knows how to transform one field value
 * into its anonymized equivalent. Strategies are stateless and must be safe to call
 * across multiple records in the same batch execution.
 *
 * To add a new strategy:
 *   1. Create a new Apex class that implements this interface.
 *   2. Deploy the class.
 *   3. Reference the class name in the Strategy_Class_Name__c field of one or more
 *      Anon_Field_Config__mdt records.
 *   No changes to any existing Apex class are required.
 *
 * @author  Data Anonymization System
 * @since   API v65.0
 */
public interface IAnonymizationStrategy {

    /**
     * @description Anonymize a single field value.
     * @param  ctx  Runtime context containing the record, field name, external ID field,
     *              and any strategy parameters configured in metadata.
     * @return      The anonymized value to write back to the field. Return the original
     *              value unchanged if the strategy chooses to keep it (e.g. AnonymizeKeep).
     *              Return null only if the field should explicitly be set to null.
     */
    String anonymize(AnonymizationContext ctx);
}
