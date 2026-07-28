/**
 * @author
 * @description Phase 2 of the anonymization chain: deletes ContentDocument records and
 *              Attachment records linked to records of the target object, filtered by brand
 *              and/or Record Type as configured in TEKCO_AnonymizationFieldConfig__mdt
 *              (TEKCO_PatternType__c = 'DELETE_CONTENT_DOCUMENT')
 */
// Deliberately 'without sharing': anonymization must reach every record matching the
// configured scope. Running with sharing would silently skip records the launching
// user cannot see, leaving PII in place with no error.
public without sharing class TEKCO_ContentDocumentBatch implements Database.Batchable<SObject>, Database.Stateful {

    public static final Integer DEFAULT_BATCH_SIZE   = 500;
    private static final Integer MAX_CAPTURED_ERRORS  = 50;

    private String                                        objectApiName;
    private String                                        recordTypeDvName;

    private List<String>                                  selectedBrands;
    private Id                                            auditLogId;
    private List<String>                                  remainingContentDocConfigDevNames;
    private List<String>                                  historyConfigDevNames;
    private TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot;
    private Map<String, List<String>>                     parentFiltersByObject;
    private Map<String, String>                           additionalFiltersByObject;

    private Integer recordsDeleted               = 0;
    private Integer recordsFailed                = 0;
    private Integer accumulatedRecordsProcessed  = 0;
    private Integer accumulatedRecordsFailed     = 0;
    private Integer accumulatedDocumentsDeleted  = 0;
    private List<String> errors                  = new List<String>();
    private List<String> accumulatedErrors       = new List<String>();

    public TEKCO_ContentDocumentBatch(
        TEKCO_AnonymizationFieldConfig__mdt currentConfig,
        List<String> selectedBrands,
        Id auditLogId,
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingContentDocConfigs,
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs,
        TEKCO_AnonymizationBypassService.BypassSnapshot bypassSnapshot,
        List<String> accumulatedErrors,
        Integer accumulatedRecordsProcessed,
        Integer accumulatedRecordsFailed,
        Integer accumulatedDocumentsDeleted,
        Map<String, List<String>> parentFiltersByObject,
        Map<String, String> additionalFiltersByObject
    ) {
        this.objectApiName              = currentConfig?.TEKCO_ObjectApiName__c;
        this.recordTypeDvName           = currentConfig?.TEKCO_RecordTypeDeveloperName__c;
        this.selectedBrands             = selectedBrands             != null
            ? selectedBrands : new List<String>();
        this.auditLogId                 = auditLogId;
        this.remainingContentDocConfigDevNames = TEKCO_AnonymizationBatchUtils.toDevNames(remainingContentDocConfigs);
        this.historyConfigDevNames             = TEKCO_AnonymizationBatchUtils.toDevNames(historyConfigs);
        this.bypassSnapshot              = bypassSnapshot;
        this.accumulatedErrors           = accumulatedErrors           != null ? accumulatedErrors           : new List<String>();
        this.accumulatedRecordsProcessed = accumulatedRecordsProcessed != null ? accumulatedRecordsProcessed : 0;
        this.accumulatedRecordsFailed    = accumulatedRecordsFailed    != null ? accumulatedRecordsFailed    : 0;
        this.accumulatedDocumentsDeleted = accumulatedDocumentsDeleted != null ? accumulatedDocumentsDeleted : 0;
        this.parentFiltersByObject       = parentFiltersByObject != null
            ? parentFiltersByObject : new Map<String, List<String>>();
        this.additionalFiltersByObject   = additionalFiltersByObject != null
            ? additionalFiltersByObject : new Map<String, String>();
    }


    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (!TEKCO_AnonymizationBatchUtils.assertSandboxOrClose(auditLogId, bypassSnapshot)) {
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        List<String> parentFilter = parentFiltersByObject.get(objectApiName);

        try { Schema.describeSObjects(new List<String>{ objectApiName }); }
        catch (Exception e) {
            errors.add('Object not found in org, skipped: ' + objectApiName);
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }

        try {
        String parentObjectApiName    = (parentFilter != null && parentFilter.size() > 0) ? parentFilter.get(0) : null;
        String parentLookupField      = (parentFilter != null && parentFilter.size() > 1) ? parentFilter.get(1) : null;
        String parentRecordTypeDvName = (parentFilter != null && parentFilter.size() > 2) ? parentFilter.get(2) : null;

        String additionalFilter = additionalFiltersByObject.get(objectApiName);
        String innerFilter = '';
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
            if (String.isNotBlank(recordTypeDvName)) {
                childConditions.add('RecordType.DeveloperName = \''
                    + String.escapeSingleQuotes(recordTypeDvName) + '\'');
            }
            if (String.isNotBlank(additionalFilter)) {
                childConditions.add(additionalFilter);
            }
            innerFilter = ' WHERE ' + String.join(childConditions, ' AND ');
        } else {
            List<String> conditions = new List<String>();
            if (!selectedBrands.isEmpty()) {
                TEKCO_AnonymizationOrgConfigService.OrgConfig orgCfg = TEKCO_AnonymizationOrgConfigService.getConfig();
                if (orgCfg.usesBrandObject()
                        && String.isNotBlank(orgCfg.brandLookupFieldOnRecord)
                        && TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, orgCfg.brandLookupFieldOnRecord)) {
                    List<String> escaped = new List<String>();
                    for (String b : selectedBrands) escaped.add('\'' + String.escapeSingleQuotes(b) + '\'');
                    conditions.add(orgCfg.brandLookupFieldOnRecord + '.' + orgCfg.brandCodeField
                        + ' IN (' + String.join(escaped, ', ') + ')');
                } else if (TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, 'tekco_brand__c')) {
                    conditions.add('TEKCO_Brand__c IN :selectedBrands');
                } else if (TEKCO_AnonymizationOrgConfigService.hasField(objectApiName, 'tekco_country__c')) {
                    List<String> countryValues = TEKCO_AnonymizationOrgConfigService.getCountriesForBrands(selectedBrands);
                    if (!countryValues.isEmpty()) {
                        conditions.add('TEKCO_Country__c IN :countryValues');
                    }
                }
            }
            if (String.isNotBlank(recordTypeDvName)) {
                conditions.add(
                    'RecordType.DeveloperName = \'' + String.escapeSingleQuotes(recordTypeDvName) + '\''
                );
            }
            if (String.isNotBlank(additionalFilter)) {
                conditions.add(additionalFilter);
            }
            if (!conditions.isEmpty()) {
                innerFilter = ' WHERE ' + String.join(conditions, ' AND ');
            }
        }

        String soqlQuery = 'SELECT Id FROM ' + objectApiName + innerFilter;

        return Database.getQueryLocator(soqlQuery);
        } catch (Exception e) {
            errors.add('Failed to build query for ' + objectApiName + ': ' + e.getMessage());
            return Database.getQueryLocator('SELECT Id FROM User WHERE Id = null');
        }
    }

    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        Set<Id> parentIds = new Set<Id>();
        for (SObject record : scope) {
            parentIds.add(record.Id);
        }
        if (parentIds.isEmpty()) return;

        // ServiceReports (must be deleted before ContentDocument) 
        try {
            List<SObject> serviceReports = Database.query(
                'SELECT Id FROM ServiceReport WHERE ParentId IN :parentIds'
            );
            if (!serviceReports.isEmpty()) {
                for (Database.DeleteResult dr : Database.delete(serviceReports, false)) {
                    if (dr.isSuccess()) {
                        recordsDeleted++;
                    } else {
                        recordsFailed++;
                        if (errors.size() < MAX_CAPTURED_ERRORS) {
                            List<String> msgs = new List<String>();
                            for (Database.Error e : dr.getErrors()) msgs.add(e.getMessage());
                            errors.add(TEKCO_AnonymizationBatchUtils.cap(
                                'ServiceReport ' + dr.getId() + ': ' + String.join(msgs, '; ')));
                        }
                    }
                }
            }
        } catch (Exception e) {
            // ServiceReport not available in this org — skip
        }

        // ContentDocuments 
        List<ContentDocumentLink> cdLinks = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId IN :parentIds
        ];
        if (!cdLinks.isEmpty()) {
            Set<Id> contentDocumentIds = new Set<Id>();
            for (ContentDocumentLink cdl : cdLinks) {
                contentDocumentIds.add(cdl.ContentDocumentId);
            }
            List<ContentDocument> toDelete = new List<ContentDocument>();
            for (Id cdId : contentDocumentIds) {
                toDelete.add(new ContentDocument(Id = cdId));
            }
            Database.DeleteResult[] deleteResults = Database.delete(toDelete, false);
            for (Database.DeleteResult dr : deleteResults) {
                if (dr.isSuccess()) {
                    recordsDeleted++;
                } else {
                    recordsFailed++;
                    if (errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> msgs = new List<String>();
                        for (Database.Error e : dr.getErrors()) msgs.add(e.getMessage());
                        errors.add(TEKCO_AnonymizationBatchUtils.cap(String.join(msgs, '; ')));
                    }
                }
            }
        }

        // Attachments 
        List<Attachment> attachments = [
            SELECT Id FROM Attachment WHERE ParentId IN :parentIds
        ];
        if (!attachments.isEmpty()) {
            Database.DeleteResult[] deleteResults = Database.delete(attachments, false);
            for (Database.DeleteResult dr : deleteResults) {
                if (dr.isSuccess()) {
                    recordsDeleted++;
                } else {
                    recordsFailed++;
                    if (errors.size() < MAX_CAPTURED_ERRORS) {
                        List<String> msgs = new List<String>();
                        for (Database.Error e : dr.getErrors()) msgs.add(e.getMessage());
                        errors.add(TEKCO_AnonymizationBatchUtils.cap(String.join(msgs, '; ')));
                    }
                }
            }
        }
    }

    public void finish(Database.BatchableContext bc) {
        for (String e : errors) {
            if (accumulatedErrors.size() < TEKCO_AnonymizationBatch.MAX_ACCUMULATED_ERRORS) {
                accumulatedErrors.add(e);
            }
        }
        Integer totalDocsDeleted = accumulatedDocumentsDeleted + recordsDeleted;
        Integer totalFailed      = accumulatedRecordsFailed    + recordsFailed;
        List<TEKCO_AnonymizationFieldConfig__mdt> remainingContentDocConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(remainingContentDocConfigDevNames);
        List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs =
            TEKCO_AnonymizationBatchUtils.loadFieldConfigsByDevNames(historyConfigDevNames);
        try {
            if (!remainingContentDocConfigs.isEmpty()) {
                TEKCO_AnonymizationFieldConfig__mdt nextConfig = remainingContentDocConfigs.remove(0);
                Database.executeBatch(
                    new TEKCO_ContentDocumentBatch(
                        nextConfig,
                        selectedBrands,
                        auditLogId,
                        remainingContentDocConfigs,
                        historyConfigs,
                        bypassSnapshot,
                        accumulatedErrors,
                        accumulatedRecordsProcessed,
                        totalFailed,
                        totalDocsDeleted,
                        parentFiltersByObject,
                        additionalFiltersByObject
                    ),
                    DEFAULT_BATCH_SIZE
                );
            } else if (!historyConfigs.isEmpty()) {
                String firstHistoryObject = historyConfigs[0].TEKCO_ObjectApiName__c;
                List<TEKCO_AnonymizationFieldConfig__mdt> firstObjectHistoryConfigs =
                    TEKCO_AnonymizationBatchUtils.popConfigsForObject(firstHistoryObject, historyConfigs);
                Database.executeBatch(
                    new TEKCO_FieldHistoryBatch(
                        firstHistoryObject,
                        firstObjectHistoryConfigs,
                        selectedBrands,
                        auditLogId,
                        historyConfigs,
                        bypassSnapshot,
                        accumulatedErrors,
                        accumulatedRecordsProcessed,
                        totalFailed,
                        totalDocsDeleted,
                        0,
                        parentFiltersByObject,
                        additionalFiltersByObject
                    ),
                    TEKCO_FieldHistoryBatch.DEFAULT_BATCH_SIZE
                );
            } else {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
                TEKCO_AnonymizationAuditService.finalize(
                    auditLogId, accumulatedRecordsProcessed, totalFailed,
                    totalDocsDeleted, 0, accumulatedErrors
                );
                return;
            }
            TEKCO_AnonymizationAuditService.markRunning(
                auditLogId, accumulatedRecordsProcessed, totalFailed, accumulatedErrors
            );
        } catch (Exception e) {
            try {
                TEKCO_AnonymizationBypassService.restore(bypassSnapshot);
            } catch (Exception restoreEx) {}
            TEKCO_AnonymizationAuditService.closeFailed(
                auditLogId, accumulatedRecordsProcessed, totalFailed,
                totalDocsDeleted, 0, accumulatedErrors, e.getMessage()
            );
        }
    }



}
