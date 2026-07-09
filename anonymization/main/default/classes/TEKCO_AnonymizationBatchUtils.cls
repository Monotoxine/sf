/**
 * @description Shared utilities for the anonymization batch chain.
 *              Eliminates duplication of history-object helpers and popConfigsForObject
 *              across TEKCO_AnonymizationBatch, TEKCO_AnonymizationByIdBatch,
 *              TEKCO_ContentDocumentBatch, TEKCO_FieldHistoryBatch and their By-ID mirrors.
 */
public class TEKCO_AnonymizationBatchUtils {

    private static final String CUSTOM_OBJECT_SUFFIX = '__c';

    public static String computeHistoryObjectName(String objectApiName) {
        return objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX)
            ? objectApiName.replace(CUSTOM_OBJECT_SUFFIX, '__History')
            : objectApiName + 'History';
    }

    public static String computeParentIdFieldName(String objectApiName) {
        return objectApiName.endsWith(CUSTOM_OBJECT_SUFFIX) ? 'ParentId' : objectApiName + 'Id';
    }

    /**
     * Removes and returns all configs for objectApiName from the supplied list (mutated in place).
     */
    public static List<TEKCO_AnonymizationFieldConfig__mdt> popConfigsForObject(
        String objectApiName,
        List<TEKCO_AnonymizationFieldConfig__mdt> configs
    ) {
        List<TEKCO_AnonymizationFieldConfig__mdt> forObj    = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        List<TEKCO_AnonymizationFieldConfig__mdt> remaining = new List<TEKCO_AnonymizationFieldConfig__mdt>();
        for (TEKCO_AnonymizationFieldConfig__mdt fc : configs) {
            if (fc.TEKCO_ObjectApiName__c == objectApiName) forObj.add(fc);
            else remaining.add(fc);
        }
        configs.clear();
        configs.addAll(remaining);
        return forObj;
    }
}
