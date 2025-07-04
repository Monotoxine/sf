import { LightningElement, api, track, wire  } from 'lwc';
import ldctStandardModel from 'c/ldctStandardModel';
import loadSpeakerProduct from '@salesforce/apex/pLM_LDCT_OrganizationSpeakersHandler.loadSpeaker_ProductByProjectId'; 

export default class PLM_LDCT_Screen4_1FundSpeakerModification extends LightningElement {
    @api recordId;
    @track SpeakerProducts;
    @track columns = [
        {
            label: 'Speaker Name',
            fieldName: 'Speaker__r.Name'
        },
        {
            label: 'Fund Name',
            fieldName: 'Product__r.Name'
        },
        { label: 'PtfTitle', fieldName: 'Title_ptf__c' },
        { label: 'Beginning Date', fieldName: 'Manage_the_fund_since_Full_date__c' },
        { label: 'End Date', typr: 'date', fieldName: 'End_date__c', editable: true }
    ];
@wire(loadSpeakerProduct,  { projectId:'a55AU00000UsOQkYAN'})//{ projectId: '$recordId' })
    wiredSpeakerProduct({ error, data }) {
        if (data) {

            console.log(data); 
            this.SpeakerProducts = data;

        } else if (error) {
            console.error('Error fetching Speaker funds:', error);
        }
    }
     home(){
            this[NavigationMixin.Navigate]({
                type: 'standard__component',
                attributes: {
                    componentName: 'c__pLM_LDCT_Screen4ModificationOfSpeaker'
                }
            });
        }
    
        saveDraft(){}
    
        validate(){}
}