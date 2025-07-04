import { LightningElement, track, api, wire} from 'lwc';
import ldctStandardModel from 'c/ldctStandardModel';
import loadNarrativeProjectSpeaker from '@salesforce/apex/pLM_LDCT_OrganizationSpeakersHandler.loadNarrativeProjectSpeaker';
import updateLDCTSpeaker from '@salesforce/apex/pLM_LDCT_OrganizationSpeakersHandler.updateLDCTSpeaker';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';

export default class PLM_LDCT_Screen4ModificationOfSpeaker extends NavigationMixin(LightningElement) {

    @api error
    @api speakerId;
    @api projectId;
    @api projectLang;
    @api firstName; 
    @api lastName; 
    @api yearBeganInvestmentCareer; 
    @api yearJoinedTheGroup; 
    @api cfaChartHolder; 
    @api cefaHolder; 
    @api pHd;
    @api email; 
    @api phone;
    @api title; 
    @api education; 
    @api biography;
    @api experience;
    @api publicPicture;

    @track currentPageReference;
    @wire(CurrentPageReference)
    setCurrentPageReference(currentPageReference) {
        this.currentPageReference = currentPageReference;
        this.projectId = this.currentPageReference.state.c__projectId;
        this.projectLang= this.currentPageReference.state.c__ProjectLang;
    }


    handleInputChange(event) {
        let fieldName = event.target.name;
        switch (fieldName) {
            case "FirstName":
                this.firstName = event.target.value;
                break;
            case "LastName":
                this.lastName = event.target.value;
                break;
            case "YearBeganInvestmentCareer":
                this.yearBeganInvestmentCareer = event.target.value;
                break;
            case "CFAchartholder":
                this.cfaChartHolder = event.detail.value;
                break;
            case "CefaHolder":
                this.cefaHolder = event.detail.value;
                break;
            case "Phd":
                this.pHd = event.detail.value;
                break;
            case "Email":
                this.email = event.target.value;
                break;
            case "Phone":
                this.phone = event.target.value;
                break;
            case "TitleEN":
                this.title = event.target.value;
                break;
            case "EducationEN":
                this.education = event.target.value;
                break;
            case "BiographyEN":
                this.biography = event.target.value;
                break;
            case "ExperienceEN":
                this.experience = event.target.value;
                break;
            case "IpadPicture":
                this.publicPicture = event.target.value;
                break;
            default:
                break;
        }
    }

    @wire(loadNarrativeProjectSpeaker, {speakerId: '$speakerId'})
    wiredLoadNarrativeProjectSpeaker({ error, data }) {
        if (data != null) {
            this.error = undefined; 
            // Populate fields for affiliate record
            this.firstName = data.FirstName__c;
            this.lastName = data.Name;
            this.yearBeganInvestmentCareer = data.Began_Investment_Career__c;
            this.yearJoinedTheGroup = data.Joined_Firm__c;
            this.cfaChartHolder = data.CFA_Charterholder__c;
            this.cefaHolder = data.Caia__c;
            this.pHd = data.Phd__c;
            this.email = data.Email__c;
            this.phone = data.Phone__c;
            this.title = data.Title_EN__c;
            this.education = data.Education_EN__c;
            this.biography = data.Bio_EN__c;
            this.experience = data.Experience_EN__c;
            this.publicPicture = data.Ipad_Picture_URL__c;
        } else if (error) {
            this.error = error; 
        }
    }

    home(){
        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: 'c__pLM_LDCT_Screen2'
            }
        });
    }

    validate(){
        ldctStandardModel.open({
            headerTitle: 'Warning',
            size: 'small',
            description: '',
            yesActionCallback: () => {
                updateLDCTSpeaker({
                    speakerId: this.speakerId,
                    firstName: this.firstName, 
                    lastName: this.lastName, 
                    yearBeganInvestmentCareer: this.yearBeganInvestmentCareer,
                    yearJoinedTheGroup: this.yearJoinedTheGroup,
                    cfaChartHolder: this.cfaChartHolder,
                    cefaHolder: this.cefaHolder,
                    pHd: this.pHd,
                    email: this.email, 
                    phone: this.phone,
                    titleEN: this.title,
                    educationEN: this.education,
                    biographyEN: this.biography,
                    experienceEN: this.experience,
                    publicPicture: this.publicPicture,
                    projectLang:this.projectLang
                }).then(() => {
                        // Show a success toast message
                        const evt = new ShowToastEvent({
                        title: 'Success',
                        message: 'LDCT Speaker record updated successfully.',
                        variant: 'success',
                        });
                        this.dispatchEvent(evt);
                    })
                    .catch(error => {
                        console.log(error); 
                        // Show an error toast message
                        const evt = new ShowToastEvent({
                        title: 'Error',
                        message: 'Error updating LDCT Speaker record. '+error.body.message,
                        variant: 'error',
                        });
                        this.dispatchEvent(evt);
                    });
            },
            content: 'You\'re about to update a Speaker. Are you sure you want to continue?'
        });
    }
    
}