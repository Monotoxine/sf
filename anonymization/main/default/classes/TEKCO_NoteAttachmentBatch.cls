/**
 * @author
 * @description Phase 4 of the anonymization chain: deletes legacy Note and Attachment records
 *              linked to records of the target object via ParentId.
 *              Triggered by TEKCO_PatternType__c = 'DELETE_LEGACY_ATTACHMENT'.
 *              Processes Note records first, then Attachment records, per object.
 */
public class TEKCO_NoteAttachmentBatch implements Database.Batchable<SObject>, Database.Stateful {

    private static final Integer DEFAULT_BATCH_SIZE  = 1000;
    private static final Integer MAX_CAPTURED_ERRORS = 50;

    private String                                         objectApiName;
    private Boolean                                        isAttachmentPhase;
    private List<String>                                   selectedBrands;
    private Id                                             auditLogId;
    private List<TEKCO_AnonymizationFieldConfig__mdt>      remainingLegacyConfigs;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    private Map<String, List<String>>                      parentFiltersByObject;
    private Map<String, String>                            additionalFiltersByObject;

    private Integer recordsDeleted = 0;
    private Integer recordsFailed  = 0;
    private List<String> errors    = new List<String>();

    public TEKCO_NoteAttachmentBatch(
        String objectApiName,
        Boolean isAttachmentPhase,
        List<String> selectedBrands,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingLegacyConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        Map<String, List<String>> parentFiltersByObject,
        Map<String, String> additionalFiltersByObject
    ) {
        this.objectApiName            = objectApiName;
        this.isAttachmentPhase        = isAttachmentPhase != null ? isAttachmentPhase : false;
        this.selectedBrands           = selectedBrands           != null
            ? selectedBrands : new List<String>();
        this.auditLogId               = auditLogId;
        this.remainingLegacyConfigs   = remainingLegacyConfigs   != null
            ? remainingLegacyConfigs : new List<TEKCO_AnonymizationFieldConfig__mdt>();
        this.bypassSnapshot           = bypassSnapshot;
        this.parentFiltersByObject    = parentFiltersByObject    != null
            ? parentFiltersByObject : new Map<String, List<String>>();
        this.additionalFiltersByObject = additionalFiltersByObject != null
            ? additionalFiltersByObject : new Map<String, String>();
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        TEKCO_AnonymizationSandboxGuard.assertIsSandbox();

        if (Schema.getGlobalDescribe().get(objectApiName) == null) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        try {
            String legacyObject = isAttachmentPhase ? 'Attachment' : 'Note';

            List<String> parentFilter     = parentFiltersByObject.get(objectApiName);
            String parentObjectApiName    = (parentFilter != null && parentFilter.size() > 0) ? parentFilter.get(0) : null;
            String parentLookupField      = (parentFilter != null && parentFilter.size() > 1) ? parentFilter.get(1) : null;
            String parentRecordTypeDvName = (parentFilter != null && parentFilter.size() > 2) ? parentFilter.get(2) : null;
            String additionalFilter       = additionalFiltersByObject.get(objectApiName);
            List<String> countryValues    = new List<String>();

            String innerFilter;
            if (String.isNotBlank(parentObjectApiName)) {
                List<String> parentConditions = new List<String>();
                if (!selectedBrands.isEmpty()) {
                    parentConditions.add('TEKCO_Brand__c IN :selectedBrands');
                }
                if (String.isNotBlank(parentRecordTypeDvName)) {
                    parentConditions.add(
                        'RecordType.DeveloperName = \'' + String.escapeSingleQuotes(parentRecordTypeDvName) + '\''
                    );
                }
                String parentSubquery = 'SELECT Id FROM ' + parentObjectApiName;
                if (!parentConditions.isEmpty()) {
                    parentSubquery += ' WHERE ' + String.join(parentConditions, ' AND ');
                }
                List<String> childConditions = new List<String>{
                    parentLookupField + ' IN (' + parentSubquery + ')'
                };
                if (String.isNotBlank(additionalFilter)) {
                    childConditions.add(additionalFilter);
                }
                innerFilter = ' WHERE ' + String.join(childConditions, ' AND ');
            } else {
                List<String> conditions = new List<String>();
                if (!selectedBrands.isEmpty()) {
                    if (hasBrandField(objectApiName)) {
                        conditions.add('TEKCO_Brand__c IN :selectedBrands');
                    } else if (hasCountryField(objectApiName)) {
                        countryValues = getCountriesForBrands(selectedBrands);
                        if (!countryValues.isEmpty()) {
                            conditions.add('TEKCO_Country__c IN :countryValues');
                        }
                    }
                }
                if (String.isNotBlank(additionalFilter)) {
                    conditions.add(additionalFilter);
                }
                innerFilter = conditions.isEmpty() ? '' : ' WHERE ' + String.join(conditions, ' AND ');
            }

            String soqlQuery = 'SELECT Id FROM ' + legacyObject
                + ' WHERE ParentId IN (SELECT Id FROM ' + objectApiName + innerFilter + ')';

            return Database.getQueryLocator(soqlQuery);
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Database.DeleteResult[] deleteResults = Database.delete(scope, false);
        for (Database.DeleteResult deleteResult : deleteResults) {
            if (deleteResult.isSuccess()) {
                recordsDeleted++;
            } else {
                recordsFailed++;
                if (errors.size() < MAX_CAPTURED_ERRORS) {
                    List<String> errorMessages = new List<String>();
                    for (Database.Error dmlError : deleteResult.getErrors()) {
                        errorMessages.add(dmlError.getMessage());
                    }
                    errors.add(String.join(errorMessages, '; '));
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        try {
            if (!isAttachmentPhase) {
                // Note pass done — run Attachment pass for the same object
                Database.executeBatch(
                    new TEKCO_NoteAttachmentBatch(
                        objectApiName,
                        true,
                        selectedBrands,
                        auditLogId,
                        remainingLegacyConfigs,
                        bypassSnapshot,
                        parentFiltersByObject,
                        additionalFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!remainingLegacyConfigs.isEmpty()) {
                // Attachment pass done — move to Note pass for next object
                TEKCO_AnonymizationFieldConfig__mdt nextConfig = remainingLegacyConfigs.remove(0);
                Database.executeBatch(
                    new TEKCO_NoteAttachmentBatch(
                        nextConfig.TEKCO_ObjectApiName__c,
                        false,
                        selectedBrands,
                        auditLogId,
                        remainingLegacyConfigs,
                        bypassSnapshot,
                        parentFiltersByObject,
                        additionalFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(auditLogId, recordsFailed, errors);
                return;
            }
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) {}
            TEKCO_AnonymizationAuditService.closeFailed(auditLogId, recordsFailed, errors, e.getMessage());
        }
    }

    private static Boolean hasBrandField(String objectApiName) {
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        return sot != null
            && sot.getDescribe().fields.getMap().containsKey('tekco_brand__c');
    }

    private static Boolean hasCountryField(String objectApiName) {
        Schema.SObjectType sot = Schema.getGlobalDescribe().get(objectApiName);
        return sot != null
            && sot.getDescribe().fields.getMap().containsKey('tekco_country__c');
    }

    private static List<String> getCountriesForBrands(List<String> brands) {
        List<String> countries = new List<String>();
        for (TEKCO_CountryBrandSetting__mdt mapping : [
            SELECT TEKCO_Country__c
            FROM TEKCO_CountryBrandSetting__mdt
            WHERE TEKCO_BrandCode__c IN :brands
              AND TEKCO_Country__c != null
        ]) {
            countries.add(mapping.TEKCO_Country__c);
        }
        return countries;
    }
}
