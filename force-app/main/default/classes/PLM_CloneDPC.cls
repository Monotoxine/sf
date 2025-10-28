/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 11-08-2023
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
global with sharing class PLM_CloneDPC {
    public static list<Id> idProjectShareclassToGet;
    // public static list<Id> idShareclassToGet;
    // @InvocableMethod
    // public static List<responseObject> PLM_CloneDPC(List<Id> plm_ProjectIdList) {
    //     List<responseObject> result = new List<responseObject>();
    //     return getPLM_CloneDPC(plm_ProjectIdList[0]);
    // }

    @AuraEnabled
    public static Map<Id, Project_Dated_Product_Characteristic__c> getProjectDatedProductCharacteristics(List<Id> plm_ShareclassesList_Id,Id plm_ID, String TypeOf ){
        List<Project_Dated_Product_Characteristic__c> results = new List<Project_Dated_Product_Characteristic__c>();
        Map<Id, Project_Dated_Product_Characteristic__c> recordsMap = new Map<Id, Project_Dated_Product_Characteristic__c>();
        try {
            results = [SELECT name, Type__c , Date__c , Project_Share_class__c, PLM_Project__c FROM Project_Dated_Product_Characteristic__c WHERE Type__c =: TypeOf AND PLM_Project__c =: plm_ID AND  Project_Share_class__c IN :plm_ShareclassesList_Id];
            for (Project_Dated_Product_Characteristic__c record : results) {if (record.Project_Share_class__c != null) {recordsMap.put(record.Project_Share_class__c, record);}}       
        } catch (Exception e) {
             Logger.info( 'An error occured when trying to get list of Project_Dated_Product_Characteristic__c', e.getMessage());
             Logger.saveLog();
        }
        return recordsMap;
    }

    @AuraEnabled
    public static Map<Id, Project_Share_class__c> getShareclassesById(List<Id> plm_ShareclassesList_Id){
        try {
            Map<Id, Project_Share_class__c> result = new Map<Id, Project_Share_class__c>([SELECT Id, Name, Label__c,RM_Status__c,Calculation_date__c,Calculation_Date_Formula__c,ISIN_Code__c, Ongoing_Fees_End_of_Calculation_Period__c FROM Project_Share_class__c WHERE Id IN :plm_ShareclassesList_Id]);
            return result;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static Product_Services_Project__c getPLM_Project(Id plm_ProjectId, List<Id> ProjectShareClassIdList) {
        try {
            Product_Services_Project__c plmProject = [Select Id, Project_Type__c, 
                                                        (Select Id, Risk_measure_calculation_status__c from Project_Products__r ),
                                                        (Select Id , Risk_measure_calculation_status__c, Live_Share_class_Record__c from Project_Share_classes__r Where Id In : ProjectShareClassIdList)
                                                        From Product_Services_Project__c WHERE Id = :plm_ProjectId];  
            return plmProject;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static List<responseObject> getPLM_CloneDPC(Id plm_ProjectId, List<Id> ProjectShareClassIdList, String plmProjectString,Boolean freezeUpdate) {
        Logger.info(JSON.serializePretty(plmProjectString)).addTag('PLM');
        Product_Services_Project__c plmProject = (Product_Services_Project__c)JSON.deserialize(plmProjectString, Product_Services_Project__c.class);
        // check if product is impacted and we need to check all shareclasses
        List<Id> scIds = new List<Id>();
        Logger.info(JSON.serializePretty(plmProject)).addTag('PLM');
        for(Project_Share_class__c sc : plmProject.Project_Share_classes__r){
            Logger.info(JSON.serializePretty(sc)).addTag('PLM');
            scIds.add(sc.Id);
        }
        if(plmProject.Project_Type__c == 'Mass Update'){
            Map<Id, Id> idProjectShareclassByShareclassToUpdate = new Map<Id, Id>();
            for(Project_Share_class__c sc : plmProject.Project_Share_classes__r){
                idProjectShareclassByShareclassToUpdate.put(sc.Live_Share_class_Record__c, sc.Id);
            }
            return cloneLastPDC(plm_ProjectId, idProjectShareclassByShareclassToUpdate,freezeUpdate);
        } else {
            if(plmProject.Project_Products__r[0].Risk_measure_calculation_status__c == 'Auto Calcul' || plmProject.Project_Products__r[0].Risk_measure_calculation_status__c == 'Need Validation'){
                
                return checkPDCIfAreToDate(plm_ProjectId, scIds);
            }
            
            Map<Id, Project_Share_class__c> projectShareClassById = new Map<Id, Project_Share_class__c>(plmProject.Project_Share_classes__r);

            //get related kiid request to project
            List<KIID_Request__c> relatedKiidRequest = new List<KIID_Request__c>([Select Id, Report_Type__c, Project_Share_class__c From KIID_Request__c WHERE Report_Type__c = 'Risk Measures' AND Project_Share_class__c IN :scIds]);

            List<Id> requestedList = new List<Id>();

            //get all project share classes Id that have a kiid request
            for(KIID_Request__c kiidRequest : relatedKiidRequest){
                requestedList.add(kiidRequest.Project_Share_class__c);
            }

            Map<Id, Id> idProjectShareclassByShareclassToUpdate = new Map<Id, Id>();
            List<Id> idProjectShareclassByShareclassToCheck = new List<Id>();

            // filter shareclass that need to update and part that need to check
            for(Project_Share_class__c sc : plmProject.Project_Share_classes__r){
                if((sc.Risk_measure_calculation_status__c == null || sc.Risk_measure_calculation_status__c == 'No need to calcul') && sc.Live_Share_class_Record__c != null && !requestedList?.contains(sc.Id)){
                    idProjectShareclassByShareclassToUpdate.put(sc.Live_Share_class_Record__c, sc.Id);
                }
                else {
                    idProjectShareclassByShareclassToCheck.add(sc.Id);
                }
            }

            List<responseObject> results = new List<responseObject>();
            
            if(!idProjectShareclassByShareclassToUpdate.isEmpty()){
                results.addAll(cloneLastPDC(plm_ProjectId, idProjectShareclassByShareclassToUpdate,freezeUpdate));
            }
            if(!idProjectShareclassByShareclassToCheck.isEmpty()){
                results.addAll(checkPDCIfAreToDate(plm_ProjectId, idProjectShareclassByShareclassToCheck));
            }
            Logger.saveLog();
            return results;
        }
    }

    public static List<responseObject> cloneLastPDC(Id plm_ProjectId, Map<Id, Id> idProjectShareclassByShareclassToUpdate,Boolean freezeStatusBoolean){
        String whereArray = '(';
        for(Id id : idProjectShareclassByShareclassToUpdate.values()){
            if(whereArray == '('){
                whereArray+= '\'' + id + '\'';
            } else {
                whereArray+= ',\'' + id + '\'';
            }

        }
        whereArray+= ')';
        List<Id> shareclassIds = new List<Id>(idProjectShareclassByShareclassToUpdate.values());
        Map<Id, Project_Share_class__c> shareClassToLiveShareClassIdMap = new Map<Id, Project_Share_class__c>();
        List<Project_Share_class__c > listProjectShareClasses = new List<Project_Share_class__c>();
        String query = ' SELECT Id, Live_Product_Record__c, Product_Services_Project__r.recordTypeName__c ' + ', ' + 
            ' (SELECT Id, Live_Share_class_Record__c, Publication_date__c '+' FROM Project_Share_classes__r WHERE Id IN ' + whereArray + '), Product_Services_Project__r.Project_Type__c ' +
            ' FROM Project_Product__c ' +
            ' WHERE Product_Services_Project__c = \'' + plm_ProjectId+ '\'';
            Logger.info('myquery '+query).addTag('PLM');
        String recordTypeName = '';
        String queryDPC = '';
        
    
        List<Project_Product__c> projectProducts = (List<Project_Product__c>)Database.query(query);
        for(Project_Product__c p : projectProducts){
            recordTypeName = p.Product_Services_Project__r.recordTypeName__c;
        }
        List<Id> projectProductIds = new List<Id>();

        for(Project_Product__c projectProduct: projectProducts){
            projectProductIds.add(projectProduct.id);
            for (Project_Share_class__c shareClass : projectProduct.Project_Share_classes__r) {
                listProjectShareClasses.add(shareClass);
                 shareClassToLiveShareClassIdMap.put(shareClass.Live_Share_class_Record__c,shareClass );
            }
        }
        Logger.info(JSON.serializePretty(projectProducts)).addTag('PLM');
        List<PLM_Dated_Product_Characteristic_Type__mdt> MD_Types = [SELECT Id, Is_reference_Type__c, Type__c, do_not_update__c,get_last_one__c FROM PLM_Dated_Product_Characteristic_Type__mdt];
        List<String> typeList = new List<String>();
        List<String> typeListRef = new List<String>();
        List<String> typeListgetLastOne = new List<String>();
        for(PLM_Dated_Product_Characteristic_Type__mdt MD_Type : MD_Types){
            if(MD_Type.Is_reference_Type__c){
                typeListRef.add(MD_Type.type__c);
            }
            if(MD_Type.get_last_one__c){
                typeListgetLastOne.add(MD_Type.type__c);
            }
            if(!MD_Type.do_not_update__c){
                typeList.add(MD_Type.type__c);
            }
            
        }

        if(recordTypeName == 'EPTV2 Reproduction Project'){
             List<Dated_Product_Characteristic__c> datedProdCarList = [Select Shareclass__c, Date__c From Dated_Product_Characteristic__c Where Shareclass__c IN :(new List<Id>(idProjectShareclassByShareclassToUpdate.keySet())) And Type__c IN :typeListRef];

            String whereCondition = '';
             for(Dated_Product_Characteristic__c pdc : datedProdCarList){
                Project_Share_class__c foundShareClass = shareClassToLiveShareClassIdMap.get(pdc.Shareclass__c);
                if (whereCondition != ''){
                    whereCondition += ' OR ';
                }

                whereCondition+= '( Shareclass__c = \'' + (pdc.Shareclass__c == null? '' : pdc.Shareclass__c) + '\' AND Date__c = ' + ((Datetime)foundShareClass.Publication_date__c).format('yyyy-MM-dd') + ')';
                //dateByShareclass.put((Id)agg.get('Shareclass__c'), ((Datetime)agg.get('expr0')).format('yyyy-MM-dd').split(' ')[0]);
            }
                String objectName = 'Dated_Product_Characteristic__c';
                List<String> fieldNames = new List<String>(ProductDataMapperHelperForClone.mappedFieldsByObj.get(objectName));
                queryDPC = 'SELECT Id, Product__c, Shareclass__c, ' + String.join(fieldNames, ', ') +' FROM Dated_Product_Characteristic__c';
                if(whereCondition != ''){
                    queryDPC += ' Where (( ' + whereCondition + ') AND Type__c IN :typeList)';
                }else{
                    queryDPC += ' Where (Type__c IN :typeList)';
                }

        }else{
            List<AggregateResult> maxDateByShareclass = [Select Shareclass__c, Max(Date__c) From Dated_Product_Characteristic__c Where Shareclass__c IN :(new List<Id>(idProjectShareclassByShareclassToUpdate.keySet())) And Type__c IN :typeListRef group by Shareclass__c ];
            List<AggregateResult> maxDateByShareclassLastOne = [Select Shareclass__c, Type__c, Max(Date__c) From Dated_Product_Characteristic__c Where Shareclass__c IN :(new List<Id>(idProjectShareclassByShareclassToUpdate.keySet())) And (Type__c IN :typeListgetLastOne) group by Shareclass__c, Type__c];
            Logger.info(JSON.serializePretty(maxDateByShareclass)).addTag('PLM');
            Logger.info(JSON.serializePretty(idProjectShareclassByShareclassToUpdate.keySet())).addTag('PLM');
            Map<Id, String> dateByShareclass= new Map<Id, String>();
            String whereCondition = '';
            String whereConditionGetLast = '';
            for(AggregateResult agg : maxDateByShareclass){
                if (whereCondition != ''){
                    whereCondition += ' OR ';
                }
                whereCondition+= '( Shareclass__c = \'' + (agg.get('Shareclass__c')== null? '' : agg.get('Shareclass__c')) + '\' AND Date__c = ' + ((Datetime)agg.get('expr0')).format('yyyy-MM-dd') + ')';
                dateByShareclass.put((Id)agg.get('Shareclass__c'), ((Datetime)agg.get('expr0')).format('yyyy-MM-dd').split(' ')[0]);
            }
            for(AggregateResult agg : maxDateByShareclassLastOne){
                whereConditionGetLast += ' OR ';
                
                whereConditionGetLast += '( Shareclass__c = \'' + (agg.get('Shareclass__c')== null? '' : agg.get('Shareclass__c')) + '\' AND Date__c = ' + ((Datetime)agg.get('expr0')).format('yyyy-MM-dd') + ' AND Type__c = \'' + agg.get('Type__c') + '\')';
            
            }
            String objectName = 'Dated_Product_Characteristic__c';
            List<String> fieldNames = new List<String>(ProductDataMapperHelperForClone.mappedFieldsByObj.get(objectName));
            queryDPC = 'SELECT Id, Product__c, Shareclass__c, ' + String.join(fieldNames, ', ') +' FROM Dated_Product_Characteristic__c';
            if(whereCondition != ''){
                queryDPC += ' Where (( ' + whereCondition + ') AND Type__c IN :typeList)';
            }else{
                queryDPC += ' Where (Type__c IN :typeList)';
            }
            queryDPC += whereConditionGetLast;
        }
        
        Logger.info(queryDPC).addTag('PLM');
        Map<Id, Dated_Product_Characteristic__c> DPCToClone = new Map<Id, Dated_Product_Characteristic__c>((List<Dated_Product_Characteristic__c>)Database.query(queryDPC));
        Map<String, List<Project_Dated_Product_Characteristic__c>> Project_DPCToCreateMap = (Map<String, List<Project_Dated_Product_Characteristic__c>>)ProductDataMapperForClone.toProjectObjects(DPCToClone.values(), false, true);
        List<Project_Dated_Product_Characteristic__c> PDPCToDelete = [SELECT Id FROM Project_Dated_Product_Characteristic__c Where Project_Product__c IN :projectProductIds AND Project_Share_class__c IN :idProjectShareclassByShareclassToUpdate.values()  AND Type__c IN :typeList];
        Map<Id, Id> projectShareclassByShareclass = new Map<Id,Id>();
        List<Project_Dated_Product_Characteristic__c> Project_DPCToCreate = new List<Project_Dated_Product_Characteristic__c>();
        Map<Id,Id> scByProduct = new Map<Id,Id>();
        for(Project_Product__c projectProduct: projectProducts){
            for(Project_Share_class__c sc : projectProduct.Project_Share_classes__r){
                projectShareclassByShareclass.put(sc.Live_Share_class_Record__c, sc.Id);
                scByProduct.put(sc.Id, projectProduct.Id);
            }
            
        }
        Logger.info(JSON.serializePretty(shareclassIds)).addTag('PLM');
        for (String dpcId: Project_DPCToCreateMap.keySet()) {
            for(Project_Dated_Product_Characteristic__c pdpc: Project_DPCToCreateMap.get(dpcId)){
                //pdpc.Live_Dated_Product_Characteristic__c = dpcId;
                pdpc.Project_Product__c = scByProduct.get(projectShareclassByShareclass.get(DPCToClone.get(dpcId).Shareclass__c));
                pdpc.Project_Share_class__c = projectShareclassByShareclass.get(DPCToClone.get(dpcId).Shareclass__c);
                pdpc.PLM_Project__c = plm_ProjectId;
                Project_DPCToCreate.add(pdpc);
                //Logger.info('Number:  '+ shareclassIds.indexOf(pdpc.Project_Share_class__c)).addTag('PLM');
                Integer indexToDelete = shareclassIds.indexOf(pdpc.Project_Share_class__c);
                if(indexToDelete >= 0){
                    shareclassIds.remove(shareclassIds.indexOf(pdpc.Project_Share_class__c));
                } 
            }
        }
        Logger.info(JSON.serializePretty(Project_DPCToCreateMap)).addTag('PLM');
        List<responseObject> results = new List<responseObject>();
        for(Id id : shareclassIds){
            responseObject result = new responseObject();
            result.status = 'error';
            result.message = 'No Dated Product Characteristic on CDR Product';
            result.id = id;
            results.add(result); 
        }
        
        Savepoint sp = Database.setSavepoint();
        
        try{
           /* Product_Services_Project__c PLM_ProjectToSetByPass = [Select Id, Freeze_Risk_Measure_Fields__c,BLOCK_RM_IN_DDPC__c from Product_Services_Project__c WHERE Id = :plm_ProjectId];
            String freezeStatus = PLM_ProjectToSetByPass.Freeze_Risk_Measure_Fields__c;
            PLM_ProjectToSetByPass.Freeze_Risk_Measure_Fields__c = 'No';
            PLM_ProjectToSetByPass.BLOCK_RM_IN_DDPC__c=true;
            if(!freezeStatusBoolean){ 
                update PLM_ProjectToSetByPass;
            }
           
            PLM_ProjectToSetByPass.Freeze_Risk_Measure_Fields__c = freezeStatus;
            if(!freezeStatusBoolean){ 
                update PLM_ProjectToSetByPass;
            }*/
            insert Project_DPCToCreate;
            delete PDPCToDelete;


            Set<Id> idsSC = new Set<Id>();
            for( Project_Dated_Product_Characteristic__c pdpc: Project_DPCToCreate){
                idsSC.add(pdpc.Project_Share_class__c);
            }
            for( Id id: idsSC){
                responseObject result = new responseObject();
                result.status = 'ok';
                result.message = 'Update is done';
                result.id = id;
                results.add(result);
            }
            
        }catch(Exception e){
            Database.rollback(sp);
            Set<Id> idsSC = new Set<Id>();
            for( Project_Dated_Product_Characteristic__c pdpc: Project_DPCToCreate){
                idsSC.add(pdpc.Project_Share_class__c);
            }
            for( Id id: idsSC){
                responseObject result = new responseObject();
                result.status = 'error';
                result.message = e.getMessage();
                result.id = id;
                results.add(result);
            }
            Logger.info(JSON.serializePretty(e.getMessage())).addTag('PLM');
        }
        Logger.saveLog();
        return results;
    }
    public static List<responseObject> checkPDCIfAreToDate(Id plm_ProjectId, List<Id> idProjectShareclassByShareclassToCheck){
        List<Project_Dated_Product_Characteristic__c> PDPCOnPLM = new List<Project_Dated_Product_Characteristic__c>([SELECT Project_Share_class__c, Project_Share_class__r.Name, Project_share_class__r.Enough_Historical_Data__c, Project_share_class__r.PRIIPS_SRI__c,
                                                                                                                            Project_share_class__r.Invested_Amount_Payment_Type__c, Project_share_class__r.Currency__c,
                                                                                                                            Project_share_class__r.Subcription_Fees_not_Paid_to_the_Fund__c, Project_share_class__r.Subscription_Fees_Paid_to_the_Fund__c,
                                                                                                                            Project_share_class__r.Exit_Fees_Paid_to_the_Fund__c, Project_share_class__r.Exit_Fees_not_Paid_to_the_Fund__c,
                                                                                                                            Project_share_class__r.Ongoing_Charges_Priips_Ex_Ante__c,  Project_share_class__r.Portfolio_Transaction_Cost_Priips__c,
                                                                                                                            Project_share_class__r.Performance_Fees_5_Years_Annualised__c, Project_share_class__r.Carries_Interests__c,
                                                                                                                            Project_Product__r.Min_Recommended_Holding_Period__c, Project_Product__r.PRIIPs_Category__c,
                                                                                                                            Id, Date__c, Type__c, Project_Product_Value__c, ISIN_Code__c
                                                                                                                    FROM Project_Dated_Product_Characteristic__c 
                                                                                                                    WHERE Project_Share_class__c IN :idProjectShareclassByShareclassToCheck
                                                                                                                    ORDER BY Project_Share_class__c]);
        List<responseObject> results = new List<responseObject>();
        if(PDPCOnPLM.size() == 0){
            Logger.info(JSON.serializePretty(idProjectShareclassByShareclassToCheck)).addTag('PLM');
            for(Id id : idProjectShareclassByShareclassToCheck){
                responseObject result = new responseObject();
                result.status = 'error';
                result.message = 'No Dated Project Product Characteristic for this share class found';
                result.id = id;
                results.add(result);
            }
            return results;
        }
        List<Id> IdsWithError = idProjectShareclassByShareclassToCheck;
        List<Id> projectSareclassWarning = new List<Id>();
        Set<String> controlResultRMReturnSet = new Set<String>();
        Set<String> controlScenarioRHPSet = new Set<String>();
        Set<String> controlScenarioOneYearSet = new Set<String>();
        Set<String> controlScenarioTenYearSet = new Set<String>();
        Set<String> controlScenarioEPTV2Set = new Set<String>();
        Map<String,String> detailControlResultMap = new Map<String,String>();
        Id shareclass = null;
        String srBody = '';

        for(Project_Dated_Product_Characteristic__c pdpc : PDPCOnPLM){

            if(shareclass != pdpc.Project_Share_class__c){
                shareclass = pdpc.Project_Share_class__c;
                controlResultRMReturnSet.addAll(controlScenarioRHPSet);
                controlResultRMReturnSet.addAll(controlScenarioOneYearSet);
                controlResultRMReturnSet.addAll(controlScenarioTenYearSet);
                controlResultRMReturnSet.addAll(controlScenarioEPTV2Set);
                if(controlResultRMReturnSet.size() > 0){
                    if(srBody == ''){
                        srBody = '<table border="1" style="border-collapse: collapse"><caption>There is RM data anomaly of the following project share class</caption><tr><th>Project ShareClass</th><th>Project Shareclass ISIN</th><th>Data Control</th><th>Detail</th></tr>';
                    }
                    srBody += '<tr><td>' + results[results.size()-1].id + '</td><td>' + results[results.size()-1].isin + '</td><td>' + JSON.serializePretty(controlResultRMReturnSet) + '</td><td>' + JSON.serializePretty(detailControlResultMap) + '</td></tr>';
                    results[results.size()-1].controlResultRM = 'KO, a support request has been created for this shareclass anomaly';
                }else{
                    if(results.size() > 0){
                        results[results.size()-1].controlResultRM = 'OK';
                    }
                }
                //Initialize controls
                detailControlResultMap = new Map<String,String>();

                controlResultRMReturnSet = new Set<String>{'PRIIP Total costs RHP',
                                                        'PRIIP Total costs 1 year',
                    									'PRIIPS SRI'};
                                                            
                controlScenarioRHPSet = new Set<String>{'PRIIP Portfolio return unfavorable scenario RHP',
                                                        'PRIIP Portfolio return moderate scenario RHP',
                                                        'PRIIP Portfolio return favorable scenario RHP',
                                                        'PRIP Portfolio return stress scenario RHP',
                                                        'PRIIP Portfolio value unfavorable scenario RHP',
                                                        'PRIIP Portfolio value moderate scenario RHP',
                                                        'PRIIP Portfolio value favorable scenario RHP',
                                                        'PRIIP Portfolio value stress scenario RHP',
                                                        'PRIIP RIY RHP'};
				
            	controlScenarioOneYearSet = new Set<String>();
                controlScenarioTenYearSet = new Set<String>();
                controlScenarioEPTV2Set = new Set<String>();
                
                if(pdpc.Project_Product__r.Min_Recommended_Holding_Period__c > 1){
                    controlScenarioOneYearSet.addAll(new Set<String>{'PRIIP Portfolio return unfavorable scenario 1 year',
                                                                'PRIIP Portfolio return moderate scenario 1 year',
                                                                'PRIIP Portfolio return favorable scenario 1 year',
                                                                'PRIIP Portfolio return stress scenario 1 year',
                                                                'PRIIP Portfolio value unfavorable scenario 1 year',
                                                                'PRIIP Portfolio value moderate scenario 1 year',
                                                                'PRIIP Portfolio value favorable scenario 1 year',
                                                                'PRIIP Portfolio value stress scenario 1 year',
                                                                'PRIIP RIY 1 year',
                                                                'PRIIP Portfolio return moderate scenario before costs RHP',
                                                                'PRIIP Total costs 1 year'});
                }

                if(pdpc.Project_Product__r.Min_Recommended_Holding_Period__c >= 10){
                    controlScenarioTenYearSet.addAll(new Set<String>{'PRIIP Portfolio return unfavorable scenario half RHP',
                                                                'PRIIP Portfolio return moderate scenario half RHP',
                                                                'PRIIP Portfolio return favorable scenario half RHP',
                                                                'PRIIP Portfolio return stress scenario half RHP',
                                                                'PRIIP Portfolio value unfavorable scenario half RHP',
                                                                'PRIIP Portfolio value moderate scenario half RHP',
                                                                'PRIIP Portfolio value favorable scenario half RHP',
                                                                'PRIIP Portfolio value stress scenario half RHP',
                                                                'PRIIP RIY half RHP',
                                                                'PRIIP Total costs half RHP'});
                }

                if(pdpc.Project_Product__r.PRIIPs_Category__c == '2' && pdpc.Project_share_class__r.Enough_Historical_Data__c == 'true'){
                    controlScenarioEPTV2Set.addAll(new Set<String>{'EPT V2 Unfavourable interval start',
                                                                'EPT V2 Unfavourable interval end',
                                                                'EPT V2 Moderate interval start',
                                                                'EPT V2 Moderate interval end',
                                                                'EPT V2 Favourable interval start',
                                                                'EPT V2 Favourable interval end'});
                }
            }
                        
            // Remove controls labels if they are OK. 
            // If not, put the control label in JSON with the additional info to allow identifying the issue in the control. 
            if(pdpc.Project_share_class__r.PRIIPS_SRI__c != null){
                controlResultRMReturnSet.remove('PRIIPS SRI');
            }else{
                detailControlResultMap.put('PRIIPS SRI','PRIIPS_SRI__c != null<br>' + pdpc.Project_share_class__r.PRIIPS_SRI__c);
            }

            if(pdpc.Project_Product_Value__c != null){
                controlScenarioRHPSet.remove(pdpc.Type__c);

                if(pdpc.Project_Product__r.Min_Recommended_Holding_Period__c > 1){
                    controlScenarioOneYearSet.remove(pdpc.Type__c);
                }else{
                    if(controlScenarioOneYearSet.contains(pdpc.Type__c)){
                        detailControlResultMap.put(pdpc.Type__c,'Min_Recommended_Holding_Period__c > 1<br>' + pdpc.Project_Product__r.Min_Recommended_Holding_Period__c);
                    }
                }

                if(pdpc.Project_Product__r.Min_Recommended_Holding_Period__c >= 10){
                    controlScenarioTenYearSet.remove(pdpc.Type__c);
                }else{
                    if(controlScenarioTenYearSet.contains(pdpc.Type__c)){
                        detailControlResultMap.put(pdpc.Type__c,'Min_Recommended_Holding_Period__c >= 10<br>' + pdpc.Project_Product__r.Min_Recommended_Holding_Period__c);
                    }
                }
                
                if(pdpc.Project_Product__r.PRIIPs_Category__c == '2' && pdpc.Project_share_class__r.Enough_Historical_Data__c == 'true'){
                    controlScenarioEPTV2Set.remove(pdpc.Type__c);
                }else{
                    if(controlScenarioEPTV2Set.contains(pdpc.Type__c)){
                        detailControlResultMap.put(pdpc.Type__c,'PRIIPs_Category__c == 2 and Enough_Historical_Data__c == true' 
                        + '<br> PRIIPs_Category__c: ' + pdpc.Project_Product__r.PRIIPs_Category__c 
                        + '<br>Enough_Historical_Data__c: ' + pdpc.Project_share_class__r.Enough_Historical_Data__c);
                    }
                }
            }else{
                if(controlScenarioRHPSet.contains(pdpc.Type__c)){
                    detailControlResultMap.put(pdpc.Type__c,'Project_Product_Value__c != null<br>' + pdpc.Project_Product_Value__c);
                }
            }

            Integer multiplier = 1;

            if(pdpc.Project_share_class__r.Invested_Amount_Payment_Type__c == 'LUMPSUM'){
                switch on pdpc.Project_share_class__r.Currency__c{
                    when 'AUD', 'CAD', 'CHF', 'EUR', 'GBP', 'NZD', 'SGD', 'USD', 'ILS', 'MYR', 'BRL' {multiplier *= 10000;}
                    when 'HKD', 'NOK', 'SEK', 'ZAR', 'CNY', 'TWD', 'THB', 'MXN', 'DKK'               {multiplier *= 100000;}
                    when 'JPY', 'RUB', 'ARS'                                                         {multiplier *= 1000000;}
                    when 'KRW'                                                                       {multiplier *= 10000000;}
                }
            }

            if(pdpc.Project_share_class__r.Invested_Amount_Payment_Type__c == 'RECURRING'){
                switch on pdpc.Project_share_class__r.Currency__c{
                    when 'AUD', 'CAD', 'CHF', 'EUR', 'GBP', 'NZD', 'SGD', 'USD', 'ILS', 'MYR', 'BRL' {multiplier *= 1000;}
                    when 'HKD', 'NOK', 'SEK', 'ZAR', 'CNY', 'TWD', 'THB', 'MXN', 'DKK'               {multiplier *= 10000;}
                    when 'JPY', 'RUB', 'ARS'                                                         {multiplier *= 100000;}
                    when 'KRW'                                                                       {multiplier *= 1000000;}
                }
            }

            Decimal Subcription_Fees_not_Paid_to_the_Fund = pdpc.Project_share_class__r.Subcription_Fees_not_Paid_to_the_Fund__c == null ? 0 : pdpc.Project_share_class__r.Subcription_Fees_not_Paid_to_the_Fund__c;
            Decimal Subscription_Fees_Paid_to_the_Fund    = pdpc.Project_share_class__r.Subscription_Fees_Paid_to_the_Fund__c    == null ? 0 : pdpc.Project_share_class__r.Subscription_Fees_Paid_to_the_Fund__c;
            Decimal Exit_Fees_Paid_to_the_Fund            = pdpc.Project_share_class__r.Exit_Fees_Paid_to_the_Fund__c            == null ? 0 : pdpc.Project_share_class__r.Exit_Fees_Paid_to_the_Fund__c;
            Decimal Exit_Fees_not_Paid_to_the_Fund        = pdpc.Project_share_class__r.Exit_Fees_not_Paid_to_the_Fund__c        == null ? 0 : pdpc.Project_share_class__r.Exit_Fees_not_Paid_to_the_Fund__c;
            Decimal Ongoing_Charges_Priips_Ex_Ante        = pdpc.Project_share_class__r.Ongoing_Charges_Priips_Ex_Ante__c        == null ? 0 : pdpc.Project_share_class__r.Ongoing_Charges_Priips_Ex_Ante__c;
            Decimal Portfolio_Transaction_Cost_Priips     = pdpc.Project_share_class__r.Portfolio_Transaction_Cost_Priips__c     == null ? 0 : pdpc.Project_share_class__r.Portfolio_Transaction_Cost_Priips__c;
            Decimal Performance_Fees_5_Years_Annualised   = pdpc.Project_share_class__r.Performance_Fees_5_Years_Annualised__c   == null ? 0 : pdpc.Project_share_class__r.Performance_Fees_5_Years_Annualised__c;
            Decimal Carries_Interests                     = pdpc.Project_share_class__r.Carries_Interests__c                     == null ? 0 : pdpc.Project_share_class__r.Carries_Interests__c;

            Decimal subscriptionFees	 = (Subcription_Fees_not_Paid_to_the_Fund + Subscription_Fees_Paid_to_the_Fund)/100;
            Decimal entryCost			 = multiplier *    subscriptionFees;
            Decimal exitCost  			 = multiplier * (1-subscriptionFees) * ((Exit_Fees_Paid_to_the_Fund + Exit_Fees_not_Paid_to_the_Fund)/100);
            Decimal ogcPRIIPS 			 = multiplier * (1-subscriptionFees) * (Ongoing_Charges_Priips_Ex_Ante				    			 /100);
            Decimal transCostExAnte 	 = multiplier * (1-subscriptionFees) * (Portfolio_Transaction_Cost_Priips   			    		 /100);
            Decimal perfFeesCarrInterest = multiplier * (1-subscriptionFees) * (Performance_Fees_5_Years_Annualised+Carries_Interests        /100);
            Decimal roundedTotal		 = (entryCost + exitCost + ogcPRIIPS + transCostExAnte + perfFeesCarrInterest).round();

            String calculationDetail = '<br>Min_Recommended_Holding_Period__c: ' + pdpc.Project_Product__r.Min_Recommended_Holding_Period__c
                                     + '<br>Type__c: ' + pdpc.Type__c
                                     + '<br>Project_Product_Value__c:' + pdpc.Project_Product_Value__c
                                     + '<br>roundedTotal: ' + roundedTotal
                                     + '<br><br>roundedTotal = (entryCost + exitCost + ogcPRIIPS + transCostExAnte + perfFeesCarrInterest).round()'
                                     + '<br>entryCost = multiplier * subscriptionFees'
                                     + '<br>exitCost = multiplier * (1-subscriptionFees) * ((Exit_Fees_Paid_to_the_Fund + Exit_Fees_not_Paid_to_the_Fund)/100)'
                                     + '<br>ogcPRIIPS = multiplier * (1-subscriptionFees) * (Ongoing_Charges_Priips_Ex_Ante/100)'
                                     + '<br>transCostExAnte = multiplier * (1-subscriptionFees) * (Portfolio_Transaction_Cost_Priips/100)'
                                     + '<br>perfFeesCarrInterest = multiplier * (1-subscriptionFees) * (Performance_Fees_5_Years_Annualised+Carries_Interests/100)'
                                     + '<br>subscriptionFees = (Subcription_Fees_not_Paid_to_the_Fund + Subscription_Fees_Paid_to_the_Fund)/100'
                                     + '<br>multiplier                            : ' + multiplier
                                     + '<br>Subcription_Fees_not_Paid_to_the_Fund : ' + pdpc.Project_share_class__r.Subcription_Fees_not_Paid_to_the_Fund__c
                                     + '<br>Subscription_Fees_Paid_to_the_Fund    : ' + pdpc.Project_share_class__r.Subscription_Fees_Paid_to_the_Fund__c
                                     + '<br>Exit_Fees_Paid_to_the_Fund            : ' + pdpc.Project_share_class__r.Exit_Fees_Paid_to_the_Fund__c
                                     + '<br>Exit_Fees_not_Paid_to_the_Fund        : ' + pdpc.Project_share_class__r.Exit_Fees_not_Paid_to_the_Fund__c
                                     + '<br>Ongoing_Charges_Priips_Ex_Ante        : ' + pdpc.Project_share_class__r.Ongoing_Charges_Priips_Ex_Ante__c
                                     + '<br>Portfolio_Transaction_Cost_Priips     : ' + pdpc.Project_share_class__r.Portfolio_Transaction_Cost_Priips__c
                                     + '<br>Performance_Fees_5_Years_Annualised   : ' + pdpc.Project_share_class__r.Performance_Fees_5_Years_Annualised__c
                                     + '<br>Carries_Interests                     : ' + pdpc.Project_share_class__r.Carries_Interests__c;

            if(pdpc.Project_Product__r.Min_Recommended_Holding_Period__c >= 1){
                if(pdpc.Type__c == 'PRIIP Total costs 1 year' && pdpc.Project_Product_Value__c == roundedTotal){
                    controlResultRMReturnSet.remove('PRIIP Total costs 1 year');
                }else{
                    if(pdpc.Type__c == 'PRIIP Total costs 1 year' && controlResultRMReturnSet.contains(pdpc.Type__c)){
                        detailControlResultMap.put('PRIIP Total costs 1 year','Min_Recommended_Holding_Period__c >= 1 and Type__c == PRIIP Total costs 1 year and Project_Product_Value__c != roundedTotal'
                        + calculationDetail);
                    }
                }
            }else{
                controlResultRMReturnSet.remove('PRIIP Total costs 1 year');
            }

            if(pdpc.Project_Product__r.Min_Recommended_Holding_Period__c < 1){
                if(pdpc.Type__c == 'PRIIP Total costs RHP' && pdpc.Project_Product_Value__c == roundedTotal * pdpc.Project_Product__r.Min_Recommended_Holding_Period__c){
                    controlResultRMReturnSet.remove('PRIIP Total costs RHP');
                }else{
                    if(pdpc.Type__c == 'PRIIP Total costs RHP' && controlResultRMReturnSet.contains(pdpc.Type__c)){
                        detailControlResultMap.put('PRIIP Total costs RHP','Min_Recommended_Holding_Period__c < 1 and Type__c == PRIIP Total costs RHP and Project_Product_Value__c != roundedTotal * Min_Recommended_Holding_Period__c'
                                                                        + calculationDetail);
                    }
                }
            }else{
                controlResultRMReturnSet.remove('PRIIP Total costs RHP');
            }
            // End of controls

            Date curDate = system.today();
            Integer numberOfDays = Date.daysInMonth(curDate.year(), curDate.month()-1);
            Date limitedate = Date.newInstance(curDate.year(), curDate.month()-1, numberOfDays);
            if(pdpc.Date__c < limitedate){
                if(!projectSareclassWarning.contains(pdpc.Project_Share_class__c)){
                    projectSareclassWarning.add(pdpc.Project_Share_class__c);
                    responseObject result = new responseObject();
                    result.status = 'warning';
                    result.message = 'The publication date "' + ((DateTime) pdpc.Date__c).format('yyyy-MM-dd').split(' ')[0] + '" is less than ' + ((DateTime) limitedate).format('yyyy-MM-dd').split(' ')[0];
                    result.id = pdpc.Project_Share_class__c;
                    result.name = pdpc.Project_Share_class__r.Name;
                    result.isin = pdpc.ISIN_Code__c;
                    results.add(result);
                }
            }else {
                responseObject result = new responseObject();
                result.status = 'ok';
                result.message = 'This share class is up to date';
                result.id = pdpc.Project_Share_class__c;
                result.name = pdpc.Project_Share_class__r.Name;
                result.isin = pdpc.ISIN_Code__c;
                results.add(result);
            }
            if(IdsWithError.contains(pdpc.Project_Share_class__c)){
                IdsWithError.remove(IdsWithError.indexOf(pdpc.Project_Share_class__c));
            }
            
        }
        if(controlResultRMReturnSet.size() > 0){
            results[results.size()-1].controlResultRM = 'KO, a support request has been created for this shareclass anomaly';
            if(srBody == ''){
                srBody = '<table border="1" style="border-collapse: collapse"><caption>There is RM data anomaly of the following project share class</caption><tr><th>Project ShareClass</th><th>Project Shareclass ISIN</th><th>Data Control</th><th>Detail</th></tr>';
            }
            srBody += '<tr><td>' + results[results.size()-1].id + '</td><td>' + results[results.size()-1].isin + '</td><td>' + JSON.serializePretty(controlResultRMReturnSet) + '</td><td>' + JSON.serializePretty(detailControlResultMap) + '</td></tr>';
        }else{
            if(results.size() > 0){
                results[results.size()-1].controlResultRM = 'OK';
            }
        }
        if(srBody != ''){
            srBody += '</table>';
            SupportRequest__c sr = new SupportRequest__c();
            sr.OwnerId = [SELECT Id FROM User WHERE Name = 'Interfaces Administrator' AND IsActive = true LIMIT 1].Id;
            sr.Subject__c = 'Automatic PRIIPS Request Data Control';
            sr.Application__c = 'PLM';
            sr.Module__c = 'PRIIPS Request';
            sr.RequestType__c = 'Data issue';
            sr.Description__c = srBody;

            Logger.info('Support Request Description lenght: ' + String.valueOf(srBody.length())).addTag('PLM');
            insert sr;
        }

        for(Id id : IdsWithError){
            responseObject result = new responseObject();
            result.status = 'error';
            result.message = 'No Dated Project Product Characteristic on CDR Product';
            result.id = id;
            results.add(result);
        }
        Logger.saveLog();
        return results;
    }

    @AuraEnabled
    public static string updateAndGetStatusProject(Id plm_ProjectId){
        try {
            Product_Services_Project__c PLM_ProjectToSetByPass = [Select Id, Freeze_Risk_Measure_Fields__c,BLOCK_RM_IN_DDPC__c from Product_Services_Project__c WHERE Id = :plm_ProjectId];
            String freezeStatus = PLM_ProjectToSetByPass.Freeze_Risk_Measure_Fields__c;
            PLM_ProjectToSetByPass.Freeze_Risk_Measure_Fields__c = 'No';
            PLM_ProjectToSetByPass.BLOCK_RM_IN_DDPC__c=true;
            update PLM_ProjectToSetByPass;
            return freezeStatus;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static void resetStatusProject(Id plm_ProjectId, String freezeStatus){
        try {
            Product_Services_Project__c PLM_ProjectToSetByPass = [Select Id, Freeze_Risk_Measure_Fields__c,BLOCK_RM_IN_DDPC__c from Product_Services_Project__c WHERE Id = :plm_ProjectId];
            PLM_ProjectToSetByPass.Freeze_Risk_Measure_Fields__c = freezeStatus;
            update PLM_ProjectToSetByPass;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    global class responseObject{
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