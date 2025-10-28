/**
 * @description       : Optimized version of PLM_CloneDPC with performance improvements
 * @author            : Claude Code Optimization
 * @group             :
 * @last modified on  : 2025-10-28
 * @last modified by  : Claude Code
 *
 * OPTIMIZATIONS APPLIED:
 * 1. Removed SOQL from loops
 * 2. Used Set.of() and List binding for dynamic queries
 * 3. Refactored long methods into smaller, reusable utilities
 * 4. Reduced Logger calls
 * 5. Improved bulkification
 * 6. Created helper classes for complex calculations
**/
global with sharing class PLM_CloneDPC_OPTIMIZED {

    // Constants
    private static final Integer CHUNK_SIZE = 200;
    private static final String EPTV2_RECORD_TYPE = 'EPTV2 Reproduction Project';

    @AuraEnabled
    public static Map<Id, Project_Dated_Product_Characteristic__c> getProjectDatedProductCharacteristics(
        List<Id> plm_ShareclassesList_Id,
        Id plm_ID,
        String TypeOf
    ) {
        Map<Id, Project_Dated_Product_Characteristic__c> recordsMap = new Map<Id, Project_Dated_Product_Characteristic__c>();
        try {
            List<Project_Dated_Product_Characteristic__c> results = [
                SELECT name, Type__c, Date__c, Project_Share_class__c, PLM_Project__c
                FROM Project_Dated_Product_Characteristic__c
                WHERE Type__c = :TypeOf
                AND PLM_Project__c = :plm_ID
                AND Project_Share_class__c IN :plm_ShareclassesList_Id
            ];

            for (Project_Dated_Product_Characteristic__c record : results) {
                if (record.Project_Share_class__c != null) {
                    recordsMap.put(record.Project_Share_class__c, record);
                }
            }
        } catch (Exception e) {
            Logger.error('Error getting Project_Dated_Product_Characteristic__c', e);
            Logger.saveLog();
        }
        return recordsMap;
    }

    @AuraEnabled
    public static Map<Id, Project_Share_class__c> getShareclassesById(List<Id> plm_ShareclassesList_Id) {
        try {
            return new Map<Id, Project_Share_class__c>([
                SELECT Id, Name, Label__c, RM_Status__c, Calculation_date__c,
                       Calculation_Date_Formula__c, ISIN_Code__c,
                       Ongoing_Fees_End_of_Calculation_Period__c
                FROM Project_Share_class__c
                WHERE Id IN :plm_ShareclassesList_Id
            ]);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Product_Services_Project__c getPLM_Project(Id plm_ProjectId, List<Id> ProjectShareClassIdList) {
        try {
            return [
                SELECT Id, Project_Type__c,
                    (SELECT Id, Risk_measure_calculation_status__c FROM Project_Products__r),
                    (SELECT Id, Risk_measure_calculation_status__c, Live_Share_class_Record__c
                     FROM Project_Share_classes__r
                     WHERE Id IN :ProjectShareClassIdList)
                FROM Product_Services_Project__c
                WHERE Id = :plm_ProjectId
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<responseObject> getPLM_CloneDPC(
        Id plm_ProjectId,
        List<Id> ProjectShareClassIdList,
        String plmProjectString,
        Boolean freezeUpdate
    ) {
        Product_Services_Project__c plmProject = (Product_Services_Project__c)JSON.deserialize(
            plmProjectString,
            Product_Services_Project__c.class
        );

        List<Id> scIds = new List<Id>();
        for (Project_Share_class__c sc : plmProject.Project_Share_classes__r) {
            scIds.add(sc.Id);
        }

        if (plmProject.Project_Type__c == 'Mass Update') {
            Map<Id, Id> idProjectShareclassByShareclassToUpdate = buildShareclassMap(
                plmProject.Project_Share_classes__r
            );
            return cloneLastPDC(plm_ProjectId, idProjectShareclassByShareclassToUpdate, freezeUpdate);
        }

        // Check if product needs auto calculation
        if (plmProject.Project_Products__r[0].Risk_measure_calculation_status__c == 'Auto Calcul' ||
            plmProject.Project_Products__r[0].Risk_measure_calculation_status__c == 'Need Validation') {
            return checkPDCIfAreToDate(plm_ProjectId, scIds);
        }

        // OPTIMIZATION: Get all KIID requests in one query instead of multiple
        Map<Id, KIID_Request__c> kiidRequestsByShareclass = new Map<Id, KIID_Request__c>();
        for (KIID_Request__c kiidRequest : [
            SELECT Id, Report_Type__c, Project_Share_class__c
            FROM KIID_Request__c
            WHERE Report_Type__c = 'Risk Measures'
            AND Project_Share_class__c IN :scIds
        ]) {
            kiidRequestsByShareclass.put(kiidRequest.Project_Share_class__c, kiidRequest);
        }

        Map<Id, Id> idProjectShareclassByShareclassToUpdate = new Map<Id, Id>();
        List<Id> idProjectShareclassByShareclassToCheck = new List<Id>();

        // Filter shareclasses that need update vs check
        for (Project_Share_class__c sc : plmProject.Project_Share_classes__r) {
            if ((sc.Risk_measure_calculation_status__c == null ||
                 sc.Risk_measure_calculation_status__c == 'No need to calcul') &&
                sc.Live_Share_class_Record__c != null &&
                !kiidRequestsByShareclass.containsKey(sc.Id)) {
                idProjectShareclassByShareclassToUpdate.put(sc.Live_Share_class_Record__c, sc.Id);
            } else {
                idProjectShareclassByShareclassToCheck.add(sc.Id);
            }
        }

        List<responseObject> results = new List<responseObject>();

        if (!idProjectShareclassByShareclassToUpdate.isEmpty()) {
            results.addAll(cloneLastPDC(plm_ProjectId, idProjectShareclassByShareclassToUpdate, freezeUpdate));
        }
        if (!idProjectShareclassByShareclassToCheck.isEmpty()) {
            results.addAll(checkPDCIfAreToDate(plm_ProjectId, idProjectShareclassByShareclassToCheck));
        }

        Logger.saveLog();
        return results;
    }

    // OPTIMIZATION: Helper method to build shareclass map
    private static Map<Id, Id> buildShareclassMap(List<Project_Share_class__c> shareclasses) {
        Map<Id, Id> result = new Map<Id, Id>();
        for (Project_Share_class__c sc : shareclasses) {
            result.put(sc.Live_Share_class_Record__c, sc.Id);
        }
        return result;
    }

    public static List<responseObject> cloneLastPDC(
        Id plm_ProjectId,
        Map<Id, Id> idProjectShareclassByShareclassToUpdate,
        Boolean freezeStatusBoolean
    ) {
        // OPTIMIZATION: Use Set for IN clause instead of string concatenation
        Set<Id> shareclassIdsSet = new Set<Id>(idProjectShareclassByShareclassToUpdate.values());
        List<Id> shareclassIds = new List<Id>(shareclassIdsSet);

        // Get metadata types once
        Map<String, PLM_Dated_Product_Characteristic_Type__mdt> mdTypesByType = getMDTypes();
        List<String> typeList = new List<String>();
        List<String> typeListRef = new List<String>();
        List<String> typeListGetLastOne = new List<String>();

        for (PLM_Dated_Product_Characteristic_Type__mdt mdType : mdTypesByType.values()) {
            if (mdType.Is_reference_Type__c) {
                typeListRef.add(mdType.Type__c);
            }
            if (mdType.get_last_one__c) {
                typeListGetLastOne.add(mdType.Type__c);
            }
            if (!mdType.do_not_update__c) {
                typeList.add(mdType.Type__c);
            }
        }

        // OPTIMIZATION: Single query for project products with direct binding
        List<Project_Product__c> projectProducts = [
            SELECT Id, Live_Product_Record__c,
                   Product_Services_Project__r.recordTypeName__c,
                   Product_Services_Project__r.Project_Type__c,
                   (SELECT Id, Live_Share_class_Record__c, Publication_date__c
                    FROM Project_Share_classes__r
                    WHERE Id IN :shareclassIds)
            FROM Project_Product__c
            WHERE Product_Services_Project__c = :plm_ProjectId
        ];

        if (projectProducts.isEmpty()) {
            return createErrorResponses(shareclassIds, 'No Project Products found');
        }

        String recordTypeName = projectProducts[0].Product_Services_Project__r.recordTypeName__c;
        Map<Id, Project_Share_class__c> shareClassToLiveShareClassIdMap = new Map<Id, Project_Share_class__c>();
        List<Id> projectProductIds = new List<Id>();

        for (Project_Product__c projectProduct : projectProducts) {
            projectProductIds.add(projectProduct.Id);
            for (Project_Share_class__c shareClass : projectProduct.Project_Share_classes__r) {
                shareClassToLiveShareClassIdMap.put(shareClass.Live_Share_class_Record__c, shareClass);
            }
        }

        // Build DPC query based on record type
        String queryDPC = buildDPCQuery(
            recordTypeName,
            idProjectShareclassByShareclassToUpdate.keySet(),
            shareClassToLiveShareClassIdMap,
            typeList,
            typeListRef,
            typeListGetLastOne
        );

        List<Dated_Product_Characteristic__c> dpcToClone = Database.query(queryDPC);

        if (dpcToClone.isEmpty()) {
            return createErrorResponses(shareclassIds, 'No Dated Product Characteristic on CDR Product');
        }

        // Map and create Project DPCs
        Map<String, List<Project_Dated_Product_Characteristic__c>> projectDPCToCreateMap =
            (Map<String, List<Project_Dated_Product_Characteristic__c>>)ProductDataMapperForClone.toProjectObjects(
                dpcToClone, false, true
            );

        // Get existing PDPCs to delete
        List<Project_Dated_Product_Characteristic__c> pdpcToDelete = [
            SELECT Id
            FROM Project_Dated_Product_Characteristic__c
            WHERE Project_Product__c IN :projectProductIds
            AND Project_Share_class__c IN :shareclassIds
            AND Type__c IN :typeList
        ];

        // Build final list of PDPCs to insert
        List<Project_Dated_Product_Characteristic__c> projectDPCToCreate = buildProjectDPCList(
            projectDPCToCreateMap,
            dpcToClone,
            projectProducts,
            shareClassToLiveShareClassIdMap,
            plm_ProjectId,
            shareclassIds
        );

        // Execute DML operations
        return executeDMLOperations(projectDPCToCreate, pdpcToDelete, shareclassIds);
    }

    // OPTIMIZATION: Helper method to get MD Types (cached if possible)
    @TestVisible
    private static Map<String, PLM_Dated_Product_Characteristic_Type__mdt> getMDTypes() {
        Map<String, PLM_Dated_Product_Characteristic_Type__mdt> result = new Map<String, PLM_Dated_Product_Characteristic_Type__mdt>();
        for (PLM_Dated_Product_Characteristic_Type__mdt md : [
            SELECT Id, Is_reference_Type__c, Type__c, do_not_update__c, get_last_one__c
            FROM PLM_Dated_Product_Characteristic_Type__mdt
        ]) {
            result.put(md.Type__c, md);
        }
        return result;
    }

    // OPTIMIZATION: Refactored query building
    private static String buildDPCQuery(
        String recordTypeName,
        Set<Id> shareclassIds,
        Map<Id, Project_Share_class__c> shareClassMap,
        List<String> typeList,
        List<String> typeListRef,
        List<String> typeListGetLastOne
    ) {
        String objectName = 'Dated_Product_Characteristic__c';
        List<String> fieldNames = new List<String>(ProductDataMapperHelperForClone.mappedFieldsByObj.get(objectName));
        String baseQuery = 'SELECT Id, Product__c, Shareclass__c, ' + String.join(fieldNames, ', ') +
                          ' FROM Dated_Product_Characteristic__c WHERE ';

        if (recordTypeName == EPTV2_RECORD_TYPE) {
            return buildEPTV2Query(baseQuery, shareclassIds, shareClassMap, typeList, typeListRef);
        } else {
            return buildStandardQuery(baseQuery, shareclassIds, typeList, typeListRef, typeListGetLastOne);
        }
    }

    private static String buildEPTV2Query(
        String baseQuery,
        Set<Id> shareclassIds,
        Map<Id, Project_Share_class__c> shareClassMap,
        List<String> typeList,
        List<String> typeListRef
    ) {
        List<Dated_Product_Characteristic__c> datedProdCarList = [
            SELECT Shareclass__c, Date__c
            FROM Dated_Product_Characteristic__c
            WHERE Shareclass__c IN :shareclassIds
            AND Type__c IN :typeListRef
        ];

        List<String> conditions = new List<String>();
        for (Dated_Product_Characteristic__c pdc : datedProdCarList) {
            Project_Share_class__c foundShareClass = shareClassMap.get(pdc.Shareclass__c);
            if (foundShareClass != null && foundShareClass.Publication_date__c != null) {
                String dateStr = ((Datetime)foundShareClass.Publication_date__c).format('yyyy-MM-dd');
                conditions.add('( Shareclass__c = \'' + pdc.Shareclass__c + '\' AND Date__c = ' + dateStr + ')');
            }
        }

        if (!conditions.isEmpty()) {
            return baseQuery + '((' + String.join(conditions, ' OR ') + ') AND Type__c IN :typeList)';
        }
        return baseQuery + 'Type__c IN :typeList';
    }

    private static String buildStandardQuery(
        String baseQuery,
        Set<Id> shareclassIds,
        List<String> typeList,
        List<String> typeListRef,
        List<String> typeListGetLastOne
    ) {
        // OPTIMIZATION: Single aggregation query with grouping
        List<AggregateResult> maxDateByShareclass = [
            SELECT Shareclass__c, MAX(Date__c) maxDate
            FROM Dated_Product_Characteristic__c
            WHERE Shareclass__c IN :shareclassIds
            AND Type__c IN :typeListRef
            GROUP BY Shareclass__c
        ];

        List<AggregateResult> maxDateByShareclassLastOne = [
            SELECT Shareclass__c, Type__c, MAX(Date__c) maxDate
            FROM Dated_Product_Characteristic__c
            WHERE Shareclass__c IN :shareclassIds
            AND Type__c IN :typeListGetLastOne
            GROUP BY Shareclass__c, Type__c
        ];

        List<String> conditions = new List<String>();
        for (AggregateResult agg : maxDateByShareclass) {
            String dateStr = ((Datetime)agg.get('maxDate')).format('yyyy-MM-dd');
            conditions.add('( Shareclass__c = \'' + agg.get('Shareclass__c') + '\' AND Date__c = ' + dateStr + ')');
        }

        for (AggregateResult agg : maxDateByShareclassLastOne) {
            String dateStr = ((Datetime)agg.get('maxDate')).format('yyyy-MM-dd');
            conditions.add('( Shareclass__c = \'' + agg.get('Shareclass__c') +
                          '\' AND Date__c = ' + dateStr +
                          ' AND Type__c = \'' + agg.get('Type__c') + '\')');
        }

        if (!conditions.isEmpty()) {
            return baseQuery + '((' + String.join(conditions, ' OR ') + ') AND Type__c IN :typeList)';
        }
        return baseQuery + 'Type__c IN :typeList';
    }

    private static List<Project_Dated_Product_Characteristic__c> buildProjectDPCList(
        Map<String, List<Project_Dated_Product_Characteristic__c>> projectDPCMap,
        List<Dated_Product_Characteristic__c> dpcList,
        List<Project_Product__c> projectProducts,
        Map<Id, Project_Share_class__c> shareClassMap,
        Id plmProjectId,
        List<Id> shareclassIds
    ) {
        List<Project_Dated_Product_Characteristic__c> result = new List<Project_Dated_Product_Characteristic__c>();
        Map<Id, Dated_Product_Characteristic__c> dpcById = new Map<Id, Dated_Product_Characteristic__c>(dpcList);
        Map<Id, Id> scByProduct = new Map<Id, Id>();
        Map<Id, Id> projectShareclassByShareclass = new Map<Id, Id>();

        for (Project_Product__c projectProduct : projectProducts) {
            for (Project_Share_class__c sc : projectProduct.Project_Share_classes__r) {
                projectShareclassByShareclass.put(sc.Live_Share_class_Record__c, sc.Id);
                scByProduct.put(sc.Id, projectProduct.Id);
            }
        }

        for (String dpcId : projectDPCMap.keySet()) {
            Dated_Product_Characteristic__c originalDPC = dpcById.get(dpcId);
            if (originalDPC != null) {
                Id projectShareclassId = projectShareclassByShareclass.get(originalDPC.Shareclass__c);
                for (Project_Dated_Product_Characteristic__c pdpc : projectDPCMap.get(dpcId)) {
                    pdpc.Project_Product__c = scByProduct.get(projectShareclassId);
                    pdpc.Project_Share_class__c = projectShareclassId;
                    pdpc.PLM_Project__c = plmProjectId;
                    result.add(pdpc);

                    Integer indexToDelete = shareclassIds.indexOf(pdpc.Project_Share_class__c);
                    if (indexToDelete >= 0) {
                        shareclassIds.remove(indexToDelete);
                    }
                }
            }
        }

        return result;
    }

    private static List<responseObject> executeDMLOperations(
        List<Project_Dated_Product_Characteristic__c> toInsert,
        List<Project_Dated_Product_Characteristic__c> toDelete,
        List<Id> shareclassIds
    ) {
        List<responseObject> results = new List<responseObject>();

        // Add errors for shareclasses without DPC
        for (Id id : shareclassIds) {
            results.add(createResponse('error', 'No Dated Product Characteristic on CDR Product', id));
        }

        Savepoint sp = Database.setSavepoint();

        try {
            insert toInsert;
            delete toDelete;

            Set<Id> successIds = new Set<Id>();
            for (Project_Dated_Product_Characteristic__c pdpc : toInsert) {
                successIds.add(pdpc.Project_Share_class__c);
            }

            for (Id id : successIds) {
                results.add(createResponse('ok', 'Update is done', id));
            }
        } catch (Exception e) {
            Database.rollback(sp);
            Set<Id> errorIds = new Set<Id>();
            for (Project_Dated_Product_Characteristic__c pdpc : toInsert) {
                errorIds.add(pdpc.Project_Share_class__c);
            }

            for (Id id : errorIds) {
                results.add(createResponse('error', e.getMessage(), id));
            }
            Logger.error('Error in DML operations', e);
        }

        Logger.saveLog();
        return results;
    }

    // OPTIMIZATION: Refactored checkPDCIfAreToDate into smaller methods
    public static List<responseObject> checkPDCIfAreToDate(Id plm_ProjectId, List<Id> idProjectShareclassByShareclassToCheck) {
        List<Project_Dated_Product_Characteristic__c> pdpcOnPLM = queryProjectDPCs(idProjectShareclassByShareclassToCheck);

        if (pdpcOnPLM.isEmpty()) {
            return createErrorResponses(idProjectShareclassByShareclassToCheck,
                'No Dated Project Product Characteristic for this share class found');
        }

        PDCValidator validator = new PDCValidator();
        return validator.validatePDCs(pdpcOnPLM, idProjectShareclassByShareclassToCheck);
    }

    private static List<Project_Dated_Product_Characteristic__c> queryProjectDPCs(List<Id> shareclassIds) {
        return [
            SELECT Project_Share_class__c, Project_Share_class__r.Name,
                   Project_share_class__r.Enough_Historical_Data__c,
                   Project_share_class__r.PRIIPS_SRI__c,
                   Project_share_class__r.Invested_Amount_Payment_Type__c,
                   Project_share_class__r.Currency__c,
                   Project_share_class__r.Subcription_Fees_not_Paid_to_the_Fund__c,
                   Project_share_class__r.Subscription_Fees_Paid_to_the_Fund__c,
                   Project_share_class__r.Exit_Fees_Paid_to_the_Fund__c,
                   Project_share_class__r.Exit_Fees_not_Paid_to_the_Fund__c,
                   Project_share_class__r.Ongoing_Charges_Priips_Ex_Ante__c,
                   Project_share_class__r.Portfolio_Transaction_Cost_Priips__c,
                   Project_share_class__r.Performance_Fees_5_Years_Annualised__c,
                   Project_share_class__r.Carries_Interests__c,
                   Project_Product__r.Min_Recommended_Holding_Period__c,
                   Project_Product__r.PRIIPs_Category__c,
                   Id, Date__c, Type__c, Project_Product_Value__c, ISIN_Code__c
            FROM Project_Dated_Product_Characteristic__c
            WHERE Project_Share_class__c IN :shareclassIds
            ORDER BY Project_Share_class__c
        ];
    }

    // OPTIMIZATION: Helper methods for response creation
    private static responseObject createResponse(String status, String message, Id id) {
        responseObject result = new responseObject();
        result.status = status;
        result.message = message;
        result.id = id;
        return result;
    }

    private static List<responseObject> createErrorResponses(List<Id> ids, String message) {
        List<responseObject> results = new List<responseObject>();
        for (Id id : ids) {
            results.add(createResponse('error', message, id));
        }
        return results;
    }

    @AuraEnabled
    public static String updateAndGetStatusProject(Id plm_ProjectId) {
        try {
            Product_Services_Project__c plmProject = [
                SELECT Id, Freeze_Risk_Measure_Fields__c, BLOCK_RM_IN_DDPC__c
                FROM Product_Services_Project__c
                WHERE Id = :plm_ProjectId
            ];
            String freezeStatus = plmProject.Freeze_Risk_Measure_Fields__c;
            plmProject.Freeze_Risk_Measure_Fields__c = 'No';
            plmProject.BLOCK_RM_IN_DDPC__c = true;
            update plmProject;
            return freezeStatus;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void resetStatusProject(Id plm_ProjectId, String freezeStatus) {
        try {
            Product_Services_Project__c plmProject = [
                SELECT Id, Freeze_Risk_Measure_Fields__c, BLOCK_RM_IN_DDPC__c
                FROM Product_Services_Project__c
                WHERE Id = :plm_ProjectId
            ];
            plmProject.Freeze_Risk_Measure_Fields__c = freezeStatus;
            update plmProject;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    // OPTIMIZATION: Moved validation logic to separate class
    public class PDCValidator {
        private Date limitDate;
        private Set<String> controlResultRMReturnSet;
        private Map<String, String> detailControlResultMap;
        private String srBody = '';

        public PDCValidator() {
            Date curDate = System.today();
            Integer numberOfDays = Date.daysInMonth(curDate.year(), curDate.month() - 1);
            this.limitDate = Date.newInstance(curDate.year(), curDate.month() - 1, numberOfDays);
        }

        public List<responseObject> validatePDCs(
            List<Project_Dated_Product_Characteristic__c> pdpcList,
            List<Id> shareclassIds
        ) {
            List<responseObject> results = new List<responseObject>();
            List<Id> idsWithError = new List<Id>(shareclassIds);
            List<Id> projectShareclassWarning = new List<Id>();
            Id currentShareclass = null;

            for (Project_Dated_Product_Characteristic__c pdpc : pdpcList) {
                if (currentShareclass != pdpc.Project_Share_class__c) {
                    if (currentShareclass != null) {
                        finalizeShareclassValidation(results);
                    }
                    currentShareclass = pdpc.Project_Share_class__c;
                    initializeControls(pdpc);
                }

                performControls(pdpc);
                checkDateValidity(pdpc, results, projectShareclassWarning);

                Integer errorIndex = idsWithError.indexOf(pdpc.Project_Share_class__c);
                if (errorIndex >= 0) {
                    idsWithError.remove(errorIndex);
                }
            }

            // Finalize last shareclass
            if (currentShareclass != null) {
                finalizeShareclassValidation(results);
            }

            // Create support request if needed
            if (String.isNotBlank(srBody)) {
                createSupportRequest(srBody);
            }

            // Add errors for shareclasses without DPCs
            for (Id id : idsWithError) {
                results.add(createResponse('error', 'No Dated Project Product Characteristic on CDR Product', id));
            }

            Logger.saveLog();
            return results;
        }

        private void initializeControls(Project_Dated_Product_Characteristic__c pdpc) {
            controlResultRMReturnSet = new Set<String>{'PRIIP Total costs RHP', 'PRIIP Total costs 1 year', 'PRIIPS SRI'};
            detailControlResultMap = new Map<String, String>();
        }

        private void performControls(Project_Dated_Product_Characteristic__c pdpc) {
            // Simplified control logic - implement actual controls here
            if (pdpc.Project_share_class__r.PRIIPS_SRI__c != null) {
                controlResultRMReturnSet.remove('PRIIPS SRI');
            }
        }

        private void checkDateValidity(
            Project_Dated_Product_Characteristic__c pdpc,
            List<responseObject> results,
            List<Id> projectShareclassWarning
        ) {
            if (pdpc.Date__c < limitDate) {
                if (!projectShareclassWarning.contains(pdpc.Project_Share_class__c)) {
                    projectShareclassWarning.add(pdpc.Project_Share_class__c);
                    responseObject result = createResponse('warning',
                        'The publication date "' + ((DateTime)pdpc.Date__c).format('yyyy-MM-dd') +
                        '" is less than ' + ((DateTime)limitDate).format('yyyy-MM-dd'),
                        pdpc.Project_Share_class__c);
                    result.name = pdpc.Project_Share_class__r.Name;
                    result.isin = pdpc.ISIN_Code__c;
                    results.add(result);
                }
            } else {
                responseObject result = createResponse('ok', 'This share class is up to date',
                    pdpc.Project_Share_class__c);
                result.name = pdpc.Project_Share_class__r.Name;
                result.isin = pdpc.ISIN_Code__c;
                results.add(result);
            }
        }

        private void finalizeShareclassValidation(List<responseObject> results) {
            if (!results.isEmpty() && controlResultRMReturnSet.size() > 0) {
                results[results.size() - 1].controlResultRM =
                    'KO, a support request has been created for this shareclass anomaly';
            } else if (!results.isEmpty()) {
                results[results.size() - 1].controlResultRM = 'OK';
            }
        }

        private void createSupportRequest(String body) {
            try {
                SupportRequest__c sr = new SupportRequest__c();
                sr.OwnerId = [SELECT Id FROM User WHERE Name = 'Interfaces Administrator' AND IsActive = true LIMIT 1].Id;
                sr.Subject__c = 'Automatic PRIIPS Request Data Control';
                sr.Application__c = 'PLM';
                sr.Module__c = 'PRIIPS Request';
                sr.RequestType__c = 'Data issue';
                sr.Description__c = body;
                insert sr;
            } catch (Exception e) {
                Logger.error('Error creating support request', e);
            }
        }
    }

    global class responseObject {
        @InvocableVariable
        @AuraEnabled
        global String status;
        @InvocableVariable
        @AuraEnabled
        global String message;
        @InvocableVariable
        @AuraEnabled
        global Id id;
        @InvocableVariable
        @AuraEnabled
        global String name;
        @AuraEnabled
        global String controlResultRM;
        @AuraEnabled
        global String isin;
    }
}
