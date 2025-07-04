import { LightningElement,wire,track, api } from 'lwc';
import loadAffiliateUser from '@salesforce/apex/pLM_LDCT_OrganizationSpeakersHandler.loadAffiliateUser';
import createAffiliateRecord from '@salesforce/apex/pLM_LDCT_OrganizationSpeakersHandler.createAffiliateRecord';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
export default class LDCTAffiliateComponent extends LightningElement {
     blockCount = 3; // Define the number of blocks 

     @track affiliateProducts; 
     @track error; 
     @track foundingYear;
     @track dateOfEntry;
     @track headquarters;
     @track shareCapitalDol;
     @track shareCapitalEur;
     @track shareCapitalDate;
     @track legalDescriptionEn;
     @track longDescriptionEn;
     @track shortDescriptionEn;
     
     // Wire the Apex method to the component
     @wire(loadAffiliateUser)
     wiredAffiliateUser({ error, data }) {
          if (data) {
               console.log(data);
               this.affiliateProducts = data; 
               this.error = undefined; 
               if (this.affiliateProducts != null) {
                    // Populate fields for affiliate record
                    this.foundingYear = this.affiliateProducts.Founding_Year__c;
                    this.dateOfEntry = this.affiliateProducts.Date_Of_Entry__c;
                    this.headquarters = this.affiliateProducts.Headquarters__c;
                    this.shareCapitalDol = this.affiliateProducts.Share_capital_dollar__c;
                    this.shareCapitalEur = this.affiliateProducts.Share_capital_euro__c;
                    this.shareCapitalDate = this.affiliateProducts.Share_capital_date__c;
                    this.legalDescriptionEn = this.affiliateProducts.Legal_Description_EN__c;
                    this.longDescriptionEn = this.affiliateProducts.Long_Description_EN__c;
                    this.shortDescriptionEn = this.affiliateProducts.Short_Description_EN__c;
               }
          } else if (error) {
               this.error = error; 
               this.affiliateProducts = undefined; 
          }
     }

      handleInputChange(event) {
        let fieldName = event.target.name;
        switch (fieldName) {
            case "FoundingYear":
                this.foundingYear = event.target.value;
                break;
            case "DateOfEntry":
                this.dateOfEntry = event.target.value;
                break;
            case "Headquarters":
                this.headquarters = event.target.value;
                break;
            case "ShareCapitalDol":
                this.shareCapitalDol = event.target.value;
                break;
            case "SharCapitalEur":
                this.shareCapitalEur = event.target.value;
                break;
            case "ShareCapitalDate":
                this.shareCapitalDate = event.target.value;
                break;
            case "LegalDescriptionEn":
                this.legalDescriptionEn = event.target.value;
                break;
            case "LongDescriptionEn":
                this.longDescriptionEn = event.target.value;
                break;
            case "ShortDescriptionEn":
                this.shortDescriptionEn = event.target.value;
                break;
            default:
                break;
        }
    }

     backEvent(){
          window.history.back();
     }

    saveEvent() {
          createAffiliateRecord({
               foundingYear: this.foundingYear,
               dateOfEntry: this.dateOfEntry,
               headquarters: this.headquarters,
               shareCapitalDol: this.shareCapitalDol,
               shareCapitalEur: this.shareCapitalEur,
               shareCapitalDate: this.shareCapitalDate,
               legalDescriptionEn: this.legalDescriptionEn,
               longDescriptionEn: this.longDescriptionEn,
               shortDescriptionEn: this.shortDescriptionEn
          })
          .then(() => {
               // Show a success toast message
               const evt = new ShowToastEvent({
                    title: 'Success',
                    message: 'You are submiting updated data to your project.',
                    variant: 'success',
               });
               this.dispatchEvent(evt);
          })
          .catch(error => {
               // Show an error toast message
               const evt = new ShowToastEvent({
                    title: 'Error',
                    message: 'Some automatic controls are in error. Could you please review and correct them? If the problem persists, please create a Support Request',
                    variant: 'error',
               });
               this.dispatchEvent(evt);
          });
     }
}