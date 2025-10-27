@isTest
public with sharing class PLM_RequireDataMappingLiteTest {
    @TestSetup
    static void setupData(){
        
        String  testUserId = UserInfo.getUserId();
        TestDataFactory.insertPDM();
         String profileId = [SELECT Id FROM Profile WHERE Name LIKE '%System Administrator%' LIMIT 1].Id;
        Logger.info('profileId' + profileId);
 		Logger.saveLog();
        
        
        User u  = [Select Id, UserRoleId From User Where Profile.Name='System Administrator'  and isactive=true Limit 1];

        u.Deactivate_Workflows__c= true;
        u.Deactivate_Validation_Rules__c= true;
        u.Deactivate_Trigger__c= true;
        update u;
        
        List<Product_Services_Project__c> lstProduct_Services_Project = new List<Product_Services_Project__c>();
        Product_Services_Project__c newRec = new Product_Services_Project__c();
        newRec.Governance_Body__c = 'IPC';
        newRec.Project_Stage__c = 'Go/No Go';
        newRec.Project_Type__c = 'Creation';
        newRec.Product_Committee_Status__c = 'Approved';
        newRec.Product_Committee_Comments__c = 'test comment';
        newRec.End_of_Feasibility_Study_Date__c = system.today();
        newRec.Product_Committee_Date__c = system.today();
        newRec.Go_No_Go_Date__c = system.today();
        newRec.Go_Live_Date__c = system.today();
        newRec.Project_on_hold_discontinued__c = 'ON HOLD';
        newRec.On_hold_Discontinued_reason__c='Test reason';
        newRec.Product_Owner__c = u.ID;
        newRec.Effective_Date__c =System.today();
        newRec.Legal_Owner__c = u.ID;
        newRec.Fund_Ops_Owner__c = u.ID;
        newRec.Finance_Owner__c = u.ID;
        newRec.Sales_Owner__c = u.ID;
        newRec.Compliance_Owner__c = u.ID;
        newRec.AML_Owner__c = u.ID;
        newRec.Investment_Risk_Control_Owner__c = u.ID;
        newRec.ISG_Owner__c = u.ID;
        newRec.Reporting_Owner__c = u.ID;
        newRec.Marketing_Owner__c= u.ID;
        newRec.Risk_Solutions_Owner__c= u.ID;
        newRec.Third_Party_Risk_Owner__c= u.ID;
        newRec.Project_Sub_Type__c = 'N/A';
        newRec.vehicle_type__c ='Dedicated Fund';
        newRec.legal_structure__c ='FCP';
        newRec.Countries_of_Registration__c = 'France;Germany';
        newRec.Domiciliation__c = 'Germany';
        newRec.Impact_KIID__c=true;
        newRec.BLOCK_RM_IN_DDPC__c=true;
        newRec.Freeze_Risk_Measure_Fields__c= 'Yes';
        lstProduct_Services_Project.add(newRec);
        
        insert lstProduct_Services_Project;
        List<Product_Data_Mapping__c> pdm = new List<Product_Data_Mapping__c>();
        pdm.add(new Product_Data_Mapping__c(Project_Object__c = 'Project_Product__c', Project_Object_Field__c = 'Guarantee_End_Date__c'
                                            , Live_Object__c = 'Produit__c', Live_Object_Field__c = 'Guarantee_End_Date__c',Responsable_type__c = 'Id',Responsable__c = testUserId,Project_Stage__c='Go/No Go'
                                            , Push_to_Live__c = true, Clone_to_Project__c = true, Include_in_Excel_template__c = true));
        pdm.add(new Product_Data_Mapping__c(Project_Object__c = 'Project_Share_class__c', Project_Object_Field__c = 'Dividend__c'
                                            , Live_Object__c = 'Shareclass__c', Live_Object_Field__c = 'Dividend__c',Responsable_type__c = 'Id',Responsable__c = testUserId,Project_Stage__c='Go/No Go'
                                            , Push_to_Live__c = true, Clone_to_Project__c = true, Include_in_Excel_template__c = true)); 
        pdm.add(new Product_Data_Mapping__c(Project_Object__c = 'Project_Fund_Registration__c', Project_Object_Field__c = 'Registration_Status__c'
                                            , Live_Object__c = 'Fund_Registration__c', Live_Object_Field__c = 'Registration_Status__c ',Responsable_type__c = 'Id',Responsable__c = testUserId,Project_Stage__c='Go/No Go'
                                            , Push_to_Live__c = true, Clone_to_Project__c = true, Include_in_Excel_template__c = true)); 
        pdm.add(new Product_Data_Mapping__c(Project_Object__c = 'Project_Fund_Highlights__c', Project_Object_Field__c = 'ESMA_Q_A__c'
                                            , Live_Object__c = 'Fund_Highlight__c', Live_Object_Field__c = 'ESMA_Q_A__c',Responsable_type__c = 'Id',Responsable__c = testUserId,Project_Stage__c='Go/No Go'
                                            , Push_to_Live__c = true, Clone_to_Project__c = true, Include_in_Excel_template__c = true));
        pdm.add(new Product_Data_Mapping__c(Project_Object__c = 'Project_Share_Class_Event__c', Project_Object_Field__c = 'Description__c'
                                            , Live_Object__c = 'Share_Class_Event__c', Live_Object_Field__c = 'Description__c',Responsable_type__c = 'Id',Responsable__c = testUserId,Project_Stage__c='Go/No Go'
                                            , Push_to_Live__c = true, Clone_to_Project__c = true, Include_in_Excel_template__c = true));
        pdm.add(new Product_Data_Mapping__c(Project_Object__c = 'Project_Share_Class_Narrative__c', Project_Object_Field__c = 'Extra_Hurdle_Rate__c'
                                            , Live_Object__c = 'Share_Class_Narratives__c', Live_Object_Field__c = 'Extra_Hurdle_Rate__c',Responsable_type__c = 'Id',Responsable__c = testUserId,Project_Stage__c='Go/No Go'
                                            , Push_to_Live__c = true, Clone_to_Project__c = true, Include_in_Excel_template__c = true));
                                            pdm.add(new Product_Data_Mapping__c(Project_Object__c = 'Project_Fee_Band__c', Project_Object_Field__c = 'Type__c'
                                            , Live_Object__c = 'Fee_Band__c', Live_Object_Field__c = 'Type__c',Responsable_type__c = 'Id',Responsable__c = testUserId,Project_Stage__c='Go/No Go'
                                            , Push_to_Live__c = true, Clone_to_Project__c = true, Include_in_Excel_template__c = true));
        
        insert pdm;     
    }

    @isTest
    public static void testMethods(){
      
        Id prodId = [Select Id from Product_Services_Project__c limit 1].Id;
        Project_Product__c proj = new Project_Product__c(
            Name = 'test Proj'
            , CurrencyIsoCode = 'USD'
            , Fund_Administrator__c = 'Brown Brothers Harriman Fund Administration Services (Ireland) Limited'
            , Product_Services_Project__c = prodId );
        insert proj;
        Project_Share_class__c pfh = new Project_Share_class__c(Project_Product__c = proj.Id);
        pfh.Currency__c = 'EUR';
        pfh.Product_Services_Project__c = prodId;
        insert pfh;
        Product_Services_Project__c plm_project = [Select Id from Product_Services_Project__c where Id =:prodId limit 1];
        plm_project.Legal_Owner__c = UserInfo.getUserId();
        update plm_project;
        List<String> userList = new List<String>();
        userList.add('Legal_Owner__c');
        List<Require_Data_Mapping__mdt> RequiredFieldsList = PLM_RequireDataMappingLite.getRequiredFieldMd(prodId, 'KPMGControle', null);
        PLM_RequireDataMappingLite.getResponsibleMap(prodId, userList);
        PLM_RequireDataMappingLite.getLabels('Product_Services_Project__c');
        PLM_RequireDataMappingLite.getRecordById(prodId);
        PLM_RequireDataMappingLite.getObjectsLabelsOfFieldsByObject();
        PLM_RequireDataMappingLite.getObjectsLabels();
        PLM_RequireDataMappingLite.getLabelsOfFieldsByObject();
        List<TreeLogicalEval.EvalInput> scEval = new List<TreeLogicalEval.EvalInput>();
        List<TreeLogicalEval.EvalInput> prodEval = new List<TreeLogicalEval.EvalInput>();
        for(Require_Data_Mapping__mdt md : RequiredFieldsList){
            if(md.Object_Name__c == 'Project_Share_class__c' && String.isNotBlank(md.Formula_Expression__c)){
                TreeLogicalEval.EvalInput scInput = new TreeLogicalEval.EvalInput();
                scInput.id = pfh.id;
                scInput.field = md.FIeld_Name__c;
                scInput.expression = md.Formula_Expression__c;
                scEval.add(scInput);
            }
            if(md.Object_Name__c == 'Project_Product__c' && String.isNotBlank(md.Formula_Expression__c)){
                TreeLogicalEval.EvalInput scInput = new TreeLogicalEval.EvalInput();
                scInput.id = proj.Id;
                scInput.field = md.FIeld_Name__c;
                scInput.expression = md.Formula_Expression__c;
                prodEval.add(scInput);
            }
        }
        String scEvalString = JSON.serialize(scEval);
        String prodEvalString = JSON.serialize(prodEval);
        PLM_RequireDataMappingLite.getEvals(scEvalString);
        PLM_RequireDataMappingLite.getEvals(prodEvalString);

        Map<String , List<String>> fieldsByObjects =new  Map<String , List<String>>();
        // a map of field name by an other map object by each responsible
        Map<String, Map<String, List<String>>> fieldsByObjectByResponsible = new Map<String, Map<String, List<String>>>();
        // a map of object name -> PLM project id field name
        Map<String, String> PLM_fieldIdNameByObject = new Map<String, String>();
        // map FieldName --> Require_Data_Mapping__mdt
        Map<PLM_RequireDataMappingLite.FieldKey, Require_Data_Mapping__mdt> rdmByFieldName = new Map<PLM_RequireDataMappingLite.FieldKey, Require_Data_Mapping__mdt>();
        Map<String, Require_Data_Mapping__mdt> rdmByFieldNameAll = new Map<String, Require_Data_Mapping__mdt>();
        // prepare all maps to get records
        String responisble;
        for(Require_Data_Mapping__mdt field :RequiredFieldsList){
            PLM_RequireDataMappingLite.FieldKey fieldKey = new PLM_RequireDataMappingLite.FieldKey();
            fieldKey.fieldName = field.FIeld_Name__c;
            fieldKey.objectName = field.Object_Name__c;
            responisble = field.Responsible__c;
            rdmByFieldName.put(fieldKey, field);
            String keyValue = field.FIeld_Name__c+field.Object_Name__c+field.Responsible__c;
            rdmByFieldNameAll.put(keyValue, field);
            //add the name of the PLM project id field on this object
            PLM_fieldIdNameByObject.put(field.Object_Name__c, field.PLM_Project_Related_Field_Name__c);
            // check if the map of the object is initiate or not
            if(!fieldsByObjects.keySet().contains(field.Object_Name__c)){
                // if not initiate it
                fieldsByObjects.put(field.Object_Name__c, new List<String>());
            }
            // add the field name on the list of the object (map)
            fieldsByObjects.get(field.Object_Name__c).add(field.FIeld_Name__c);
            // check if the map of the responisibles is initiate or not
            if(!fieldsByObjectByResponsible.keySet().contains(field.Responsible__c)){
                // if not initiate it
                fieldsByObjectByResponsible.put(field.Responsible__c, new Map<String, List<String>>());
            }
            // check if the map of the object is initiate or not
            if(!fieldsByObjectByResponsible.get(field.Responsible__c).keySet().contains(field.Object_Name__c)){
                // if not initiate it
                fieldsByObjectByResponsible.get(field.Responsible__c).put(field.Object_Name__c, new List<String>());
            }
            // add the field on the list of the embedded maps 
            fieldsByObjectByResponsible.get(field.Responsible__c).get(field.Object_Name__c).add(field.FIeld_Name__c);
            
        }
        PLM_RequireDataMappingLite.getIdsByObject(prodId, fieldsByObjects, PLM_fieldIdNameByObject, rdmByFieldName);

        PLM_RequireDataMappingLite.getAllExpressionInput(prodId, fieldsByObjects, PLM_fieldIdNameByObject, rdmByFieldNameAll,responisble);

    }

    @isTest 
    public static void testopenfund(){
        
        Product_Services_Project__c newRec = new Product_Services_Project__c();
        newRec.Governance_Body__c = 'IPC';
        newRec.Project_Stage__c = 'Go/No Go';
        newRec.Project_Type__c = 'Creation';
        newRec.Product_Committee_Status__c = 'Approved';
        newRec.Product_Committee_Comments__c = 'test comment';
        newRec.End_of_Feasibility_Study_Date__c = system.today();
        newRec.Product_Committee_Date__c = system.today();
        newRec.Go_No_Go_Date__c = system.today();
        newRec.Go_Live_Date__c = system.today();
        newRec.Project_on_hold_discontinued__c = 'ON HOLD';
        newRec.On_hold_Discontinued_reason__c='Test reason';
        newRec.Product_Owner__c = UserInfo.getUserId();
        newRec.Legal_Owner__c = UserInfo.getUserId();
        newRec.Fund_Ops_Owner__c = UserInfo.getUserId();
        newRec.Finance_Owner__c = UserInfo.getUserId();
        newRec.Sales_Owner__c = UserInfo.getUserId();
        newRec.Compliance_Owner__c = UserInfo.getUserId();
        newRec.AML_Owner__c = UserInfo.getUserId();
        newRec.Investment_Risk_Control_Owner__c = UserInfo.getUserId();
        newRec.ISG_Owner__c = UserInfo.getUserId();
        newRec.Reporting_Owner__c = UserInfo.getUserId();
        newRec.Marketing_Owner__c= UserInfo.getUserId();
        newRec.Risk_Solutions_Owner__c= UserInfo.getUserId();
        newRec.Third_Party_Risk_Owner__c= UserInfo.getUserId();
        newRec.Project_Sub_Type__c = 'N/A';
        newRec.vehicle_type__c ='Open-End Fund';
        newRec.legal_structure__c ='SICAV';
        newRec.Countries_of_Registration__c = 'France;Germany';
        newRec.Domiciliation__c = 'Ireland';
        insert newRec;
        List<String> userList = new List<String>();
        userList.add('Legal_Owner__c');
        PLM_RequireDataMappingLite.getRequiredFieldMd(newRec.Id, 'KPMGControle', null);
    }
    @isTest 
    public static void testopenfundV2(){
        
        Product_Services_Project__c newRec = new Product_Services_Project__c();
        newRec.Governance_Body__c = 'IPC';
        newRec.Project_Stage__c = 'Go/No Go';
        newRec.Project_Type__c = 'Creation';
        newRec.Product_Committee_Status__c = 'Approved';
        newRec.Product_Committee_Comments__c = 'test comment';
        newRec.End_of_Feasibility_Study_Date__c = system.today();
        newRec.Product_Committee_Date__c = system.today();
        newRec.Go_No_Go_Date__c = system.today();
        newRec.Go_Live_Date__c = system.today();
        newRec.Project_on_hold_discontinued__c = 'ON HOLD';
        newRec.On_hold_Discontinued_reason__c='Test reason';
        newRec.Product_Owner__c = UserInfo.getUserId();
        newRec.Legal_Owner__c = UserInfo.getUserId();
        newRec.Fund_Ops_Owner__c = UserInfo.getUserId();
        newRec.Finance_Owner__c = UserInfo.getUserId();
        newRec.Sales_Owner__c = UserInfo.getUserId();
        newRec.Compliance_Owner__c = UserInfo.getUserId();
        newRec.AML_Owner__c = UserInfo.getUserId();
        newRec.Investment_Risk_Control_Owner__c = UserInfo.getUserId();
        newRec.ISG_Owner__c = UserInfo.getUserId();
        newRec.Reporting_Owner__c = UserInfo.getUserId();
        newRec.Marketing_Owner__c= UserInfo.getUserId();
        newRec.Risk_Solutions_Owner__c= UserInfo.getUserId();
        newRec.Third_Party_Risk_Owner__c= UserInfo.getUserId();
        newRec.Project_Sub_Type__c = 'N/A';
        newRec.vehicle_type__c ='Open-End Fund';
        newRec.legal_structure__c ='SICAV';
        newRec.Countries_of_Registration__c = 'France;Germany';
        newRec.Domiciliation__c = 'Luxembourg';
        insert newRec;
        List<String> userList = new List<String>();
        userList.add('Legal_Owner__c');
        PLM_RequireDataMappingLite.getRequiredFieldMd(newRec.Id, 'KPMGControle', null);
    }
    @isTest 
    public static void testopenfundV3(){
        
        Product_Services_Project__c newRec = new Product_Services_Project__c();
        newRec.Governance_Body__c = 'IPC';
        newRec.Project_Stage__c = 'Go/No Go';
        newRec.Project_Type__c = 'Creation';
        newRec.Product_Committee_Status__c = 'Approved';
        newRec.Product_Committee_Comments__c = 'test comment';
        newRec.End_of_Feasibility_Study_Date__c = system.today();
        newRec.Product_Committee_Date__c = system.today();
        newRec.Go_No_Go_Date__c = system.today();
        newRec.Go_Live_Date__c = system.today();
        newRec.Project_on_hold_discontinued__c = 'ON HOLD';
        newRec.On_hold_Discontinued_reason__c='Test reason';
        newRec.Product_Owner__c = UserInfo.getUserId();
        newRec.Legal_Owner__c = UserInfo.getUserId();
        newRec.Fund_Ops_Owner__c = UserInfo.getUserId();
        newRec.Finance_Owner__c = UserInfo.getUserId();
        newRec.Sales_Owner__c = UserInfo.getUserId();
        newRec.Compliance_Owner__c = UserInfo.getUserId();
        newRec.AML_Owner__c = UserInfo.getUserId();
        newRec.Investment_Risk_Control_Owner__c = UserInfo.getUserId();
        newRec.ISG_Owner__c = UserInfo.getUserId();
        newRec.Reporting_Owner__c = UserInfo.getUserId();
        newRec.Marketing_Owner__c= UserInfo.getUserId();
        newRec.Risk_Solutions_Owner__c= UserInfo.getUserId();
        newRec.Third_Party_Risk_Owner__c= UserInfo.getUserId();
        newRec.Project_Sub_Type__c = 'N/A';
        newRec.vehicle_type__c ='Open-End Fund';
        newRec.legal_structure__c ='FCPE';
        newRec.Countries_of_Registration__c = 'France;Germany';
        newRec.Domiciliation__c = 'France';
        insert newRec;
        List<String> userList = new List<String>();
        userList.add('Legal_Owner__c');
        PLM_RequireDataMappingLite.getRequiredFieldMd(newRec.Id, 'KPMGControle', null);
    }
}