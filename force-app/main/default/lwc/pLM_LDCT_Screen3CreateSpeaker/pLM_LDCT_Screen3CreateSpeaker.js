import { LightningElement,wire, track, api } from 'lwc';
import ldctStandardModel from 'c/ldctStandardModel';
import createSpeaker from '@salesforce/apex/pLM_LDCT_OrganizationSpeakersHandler.createSpeaker';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {  CurrentPageReference,NavigationMixin } from 'lightning/navigation';

export default class PLM_LDCT_Screen3CreateSpeaker extends NavigationMixin(LightningElement) {

    @api ldctProjectId;
    @track firstName; 
    @track lastName; 
    @track yearBeganInvestmentCareer; 
    @track yearJoinedTheGroup; 
    @track cfaChartHolder; 
    @track cefaHolder; 
    @track pHd;
    @track email; 
    @track phone;
    @track title; 
    @track education; 
    @track biography;
    @track experience;
    @track publicPicture;
    @api projectId;
    @track currentPageReference;
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        this.currentPageReference = currentPageReference;
        this.projectId = this.currentPageReference.state.c__projectId;
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
            case "Title":
                this.title = event.target.value;
                break;
            case "Education":
                this.education = event.target.value;
                break;
            case "Biography":
                this.biography = event.target.value;
                break;
            case "Experience":
                this.experience = event.target.value;
                break;
            case "IpadPicture":
                this.publicPicture = event.target.value;
                break;
            default:
                break;
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

    saveDraft(){}

    validate(){
        ldctStandardModel.open({
            headerTitle: 'Warning',
            size: 'small',
            description: '',
            yesActionCallback: () => {
                createSpeaker({
                    firstName: this.firstName, 
                    lastName: this.lastName, 
                    yearBeganInvestmentCareer: this.yearBeganInvestmentCareer,
                    yearJoinedTheGroup: this.yearJoinedTheGroup,
                    cfaChartHolder: this.cfaChartHolder,
                    cefaHolder: this.cefaHolder,
                    pHd: this.pHd,
                    email: this.email, 
                    phone: this.phone,
                    title: this.title,
                    education: this.education,
                    biography: this.biography,
                    experience: this.experience,
                    publicPicture: this.publicPicture
                }).then(() => {
                        // Show a success toast message
                        const evt = new ShowToastEvent({
                        title: 'Success',
                        message: 'LDCT Speaker record created successfully.',
                        variant: 'success',
                        });
                        this.dispatchEvent(evt);
                        window.history.back();
                    })
                    .catch(error => {
                        console.log(error); 
                        // Show an error toast message
                        const evt = new ShowToastEvent({
                        title: 'Error',
                        message: 'Error creating LDCT Speaker record. '+error.body.message,
                        variant: 'error',
                        });
                        this.dispatchEvent(evt);
                    });
            },
            content: 'You\'re about to submit a project. Are you sure you want to continue?'
        });
        
    }
}