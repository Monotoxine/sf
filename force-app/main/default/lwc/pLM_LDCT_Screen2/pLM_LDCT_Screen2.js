import { LightningElement, wire, api, track } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import Name from '@salesforce/schema/User.Name';
import CompanyName from '@salesforce/schema/User.CompanyName';
import Id from '@salesforce/user/Id';
import {CurrentPageReference, NavigationMixin } from 'lightning/navigation';

export default class PLM_LDCT_Screen2 extends NavigationMixin(LightningElement){
    userId = Id;
    @api projectId;
    @track userName = "";
    @track companyName = ""; 
    @track updateAffiliateXDataText = ""; 

    welcomeMessage = 'Welcome to your dashboard '; 
    @track currentPageReference;
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        this.currentPageReference = currentPageReference;
        this.projectId = this.currentPageReference.state.c__projectId;
    }

  
    @wire(getRecord, { recordId: Id, fields: [Name, CompanyName] })
    userDetails({ error, data }) {
       
        if (error) {
            this.error = error;
        } else if (data) {
            if (data.fields.Name.value != null) {
                this.userName = data.fields.Name.value;
                this.welcomeMessage += data.fields.Name.value;
            }

            if(data.fields.CompanyName != null){
                this.companyName = data.fields.CompanyName.value;
                this.updateAffiliateXDataText = "Update Affiliate "+data.fields.CompanyName.value+" Data"; 
            }
        }
    }

    backEvent(){
        window.history.back();
    }

    updateAffiliateXDataEvent() {
        this.navigateToCustomComponent('c__lDCTAffiliateComponent');
    }
    navigateToScreen4_1(){
        this.navigateToCustomComponent('c__pLM_LDCT_Screen4_1FundSpeakerModification');
    }
    createAnewSpeaker(){
        this.navigateToCustomComponent('c__pLM_LDCT_Screen3CreateSpeaker');
    }

    navigateToCustomComponent(customComponentName){
        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: customComponentName
            },
            state: {
                c__projectId: this.projectId
            },
        });
    }

}