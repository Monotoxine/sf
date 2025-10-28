/**
 * @description       : 
 * @author            : ChangeMeIn@UserSettingsUnder.SFDoc
 * @group             : 
 * @last modified on  : 03-12-2024
 * @last modified by  : ChangeMeIn@UserSettingsUnder.SFDoc
**/
import { api, LightningElement,track } from 'lwc';
import getPLM_CloneDPC from '@salesforce/apex/PLM_CloneDPC.getPLM_CloneDPC'
import getShareclassesById from '@salesforce/apex/PLM_CloneDPC.getShareclassesById'
import getProjectDatedProductCharacteristics from '@salesforce/apex/PLM_CloneDPC.getProjectDatedProductCharacteristics';
import getPLM_Project from '@salesforce/apex/PLM_CloneDPC.getPLM_Project'
import resetStatusProject from '@salesforce/apex/PLM_CloneDPC.resetStatusProject'
import updateAndGetStatusProject from '@salesforce/apex/PLM_CloneDPC.updateAndGetStatusProject' 
import { updateRecord } from 'lightning/uiRecordApi';
import PROJECT_SHARE_CLASS_OBJECT from "@salesforce/schema/Project_Share_class__c";
import ID_FIELD from '@salesforce/schema/Project_Share_class__c.Id';
import NAME_FIELD from '@salesforce/schema/Project_Share_class__c.Name';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import LightningAlert from 'lightning/alert';

export default class PLM_CloneDPC extends LightningElement {
    @track recordsMap = new Map();
    PDPCdata=new Map();
    PDPCDate='';
    @api shareclasses = [];
    @api recordId;
    @api freezeUpdate = false;
    @api size;
    dataTable = [];
    isValid = true;
    isLoading = true
    message
    finalMessage
    @api projectType;
    @api selectedCons;
    @api outputSelectedrows = [];
    @api outputSelectedRow;
    @track selectedCons = []; 
    @track sharclassById;
    checked=true;

    get isMassUpdate() {
        return this.projectType == 'Mass Update' ? true : false;
    }
    
    get dataTableWithRowNumber(){
        return this.dataTable.map((row,index)=> {
            return {
                ...row,
                rowNumber: index + 1
            };
        });
    }
 
    async connectedCallback(){
        this.isLoading = true;
        const promiseList = [];
        const chunkSize = 15;
        const shareclasses = this.shareclasses;
        //let freezeStatus = await resetStatusProject({plm_ProjectId: this.recordId});
        const plmProject = await getPLM_Project({plm_ProjectId : this.recordId, ProjectShareClassIdList : shareclasses});
        // plmProject.Project_Share_classes__r = {done: true, records: plmProject.Project_Share_classes__r, totalSize:  plmProject.Project_Share_classes__r.length }
        plmProject.Project_Products__r = {done: true, records: plmProject.Project_Products__r, totalSize:  plmProject.Project_Products__r.length }
        const plmProject_Project_Share_classes__r = plmProject.Project_Share_classes__r;
        //console.log(plmProject);
        //console.log(plmProject_Project_Share_classes__r);
        for (let i = 0; i < shareclasses.length; i += chunkSize) {
            const chunk = shareclasses.slice(i, i + chunkSize);
            plmProject.Project_Share_classes__r = {done: true, records: plmProject_Project_Share_classes__r.slice(i, i + chunkSize), totalSize:  chunkSize }
            promiseList.push(await getPLM_CloneDPC({plm_ProjectId : this.recordId, ProjectShareClassIdList : chunk, plmProjectString: JSON.stringify(plmProject),freezeUpdate: this.freezeUpdate}));
            // do whatever
        }
        
        const result = (await Promise.all(promiseList)).flat()
        //await updateAndGetStatusProject({plm_ProjectId: this.recordId, freezeStatus: freezeStatus});
        this.sharclassById = await getShareclassesById({plm_project_Id : this.recordId, plm_ShareclassesList_Id : this.shareclasses});
        //console.log("this.sharclassById",this.sharclassById);
        //console.log('result befor cut',result)
        result.splice(this.shareclasses.length)
        //console.log('result after cut',result)
        //console.log('sharclassById ',sharclassById)
        const dataTable = [];
        this.selectedCons = [];
        let isValid = true;
        // Geeting related ProjectDatedProductCharacteristics for this current PLM Project of type PRIIPS SRI
             await getProjectDatedProductCharacteristics({ plm_ShareclassesList_Id: this.shareclasses, plm_ID: this.recordId, TypeOf: 'PRIIPS SRI'}).then((results) => {
                for (var key in results) {
                    this.PDPCdata.set(key,results[key]);
                }
            }).catch((error) => {
            });
        let showControlRMAlert = false;
        result.forEach(element => {
            const dateObj = new Date(this.sharclassById[element.id].Calculation_Date__c==null?this.sharclassById[element.id].Calculation_Date_Formula__c:this.sharclassById[element.id].Calculation_Date__c);
            const monthName = dateObj.toLocaleString('en-US', { month: 'long' });
            isValid = element.status !== 'error'  

            if (this.PDPCdata.size>0){
                if (this.PDPCdata.has(this.sharclassById[element.id].Id)){ this.PDPCDate= this.PDPCdata.get(this.sharclassById[element.id].Id).Date__c+'';}
                else {this.PDPCDate=this.sharclassById[element.id].Calculation_Date__c}
             } else 
              {this.PDPCDate=this.sharclassById[element.id].Calculation_Date__c;}

           // this.message = this.sharclassById[element.id].RM_Status__c =='RM computation has not yet started' || this.sharclassById[element.id].RM_Status__c =='No need for RM computation'? 'The current risk measures are based on '+ monthName+' monthly CDR batch':'The current risk measures are based on ad hoc calculation from PLM ; date of calcul : '+this.PDPCDate
           this.message = 'The current risk measures are based on '+ this.PDPCDate+'';
           this.finalMessage =  element.status == 'error'? element.message:this.message //this.message == 'The current risk measures are based on ad hoc calculation from PLM ; date of calcul : '+sharclassById[element.id].Calculation_Date__c &&
           if(this.projectType != 'Mass Update'){
            if(element.controlResultRM == 'KO, a support request has been created for this shareclass anomaly'){
                showControlRMAlert = true;
            }
            dataTable.push({
                controlResultRM: element.controlResultRM,
                message: this.finalMessage, 
                // status: element.status,
                name: this.sharclassById[element.id].Label__c,
                url: '/lightning/r/Project_ShareClass__c/' + element.id + '/view',
                id: element.id, 
                class: ''//element.status === 'error'? 'slds-hint-parent slds-icon-standard-dashboard' : (element.status === 'warning'? 'slds-hint-parent slds-icon-standard-decision': 'slds-hint-parent slds-icon-standard-forecasts')
            });
            }else{
                dataTable.push({
                    message: this.finalMessage, 
                    isinCode: this.sharclassById[element.id].ISIN_Code__c,
                    ongoingFeesEndCalcDate: this.sharclassById[element.id].Ongoing_Fees_End_of_Calculation_Period__c,
                    name: this.sharclassById[element.id].Label__c,
                    url: '/lightning/r/Project_ShareClass__c/' + element.id + '/view',
                    id: element.id, 
                    marked: true,
                    class: ''//element.status === 'error'? 'slds-hint-parent slds-icon-standard-dashboard' : (element.status === 'warning'? 'slds-hint-parent slds-icon-standard-decision': 'slds-hint-parent slds-icon-standard-forecasts')
                });
                this.selectedCons.push(element.id);
            }
        });
    
        this.dataTable = dataTable;
        this.isLoading = false;
        this.isValid = isValid;
        this.dispatchEvent(new FlowAttributeChangeEvent('outputSelectedrows', this.selectedCons));
        if(showControlRMAlert){
            await LightningAlert.open({
            message: 'Data anomalies have been detected for some shareclass in your project',
            theme: 'info',
            label: 'Control Result RM data',
        });
        }
    }

    showToast(title, message, variant, mode) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: mode
        });
        this.dispatchEvent(evt);
    }
    allSelected(event) {
        this.selectedCons = [];
        let selectedRows = this.template.querySelectorAll('lightning-input');
        for(let i = 0; i < selectedRows.length; i++) {
            if(selectedRows[i].type === 'checkbox' && event.target.checked == true) {
                selectedRows[i].checked = event.target.checked; 
                if(selectedRows[i].dataset.id != undefined){
                this.selectedCons.push(
                    selectedRows[i].dataset.id
            );
        }
            }else{
                selectedRows[i].checked = event.target.checked;
                this.selectedCons = [];
            }
        }

        this.dispatchEvent(new FlowAttributeChangeEvent('outputSelectedrows', this.selectedCons));
        this.dispatchEvent(new FlowAttributeChangeEvent('outputSelectedRow', this.selectedCons.toString()));
        
    }

    selectRow(){
        this.selectedCons = [];

        let selectedRows = this.template.querySelectorAll('lightning-input');

        // based on selected row getting values of the contact
        for(let i = 0; i < selectedRows.length; i++) {
            if(selectedRows[i].checked && selectedRows[i].type === 'checkbox') {
                if(selectedRows[i].dataset.id != undefined){
                this.selectedCons.push(
                    selectedRows[i].dataset.id
                )
                }else{
                    selectedRows[i].checked = false;
                }
            }
        }
        this.dispatchEvent(new FlowAttributeChangeEvent('outputSelectedrows', this.selectedCons));
        this.dispatchEvent(new FlowAttributeChangeEvent('outputSelectedRow', this.selectedCons.toString()));
    }

    handleCheckboxChange(event) {
        const value = event.target.value;
        if (event.target.checked) {
            this.selectedCons.push(value);
        } else {
            this.selectedCons = this.selectedCons.filter(item => item !== value);
        }
    }
    get totalRecords() {
        return this.dataTable.length; 
    }

    @api
    validate() {
        if(!this.isLoading && this.isValid) { 
            return { isValid: true }; 
        } 
        else { 
            // If the component is invalid, return the isValid parameter 
            // as false and return an error message. 
            if(this.isLoading){
                return { 
                    isValid: false, 
                    errorMessage: 'Please wait until the completion check done.' 
                }; 
            }
            if(!this.isValid){
                return { 
                    isValid: false, 
                    errorMessage: 'We don\'t have all the Dated Product Characteristics to request KPMG.' 
                }; 
            }
        }
    }
}