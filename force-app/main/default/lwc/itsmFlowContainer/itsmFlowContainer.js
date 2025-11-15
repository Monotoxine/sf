import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getITSMInitData from '@salesforce/apex/ITSMInitController.getITSMInitData';

export default class ItsmFlowContainer extends LightningElement {
    
    @api recordTypeId;
    
    // Data from Apex
    itsmData;
    @track categories = [];
    @track subcategories = [];
    @track services = [];
    
    // User selections
    @track selectedType;
    @track selectedCategory;
    @track selectedSubcategory;
    @track selectedServiceId;
    
    // UI State
    @track showSelectionForm = true;
    @track showOmniScript = false;
    @track isLoading = true;
    @track error;
    
    // OmniScript parameters
    omniscriptType;
    omniscriptSubType;
    omniscriptLang;
    omniscriptVersion;
    
    /**
     * Wire to get ITSM data
     */
    @wire(getITSMInitData)
    wiredItsmData({ error, data }) {
        this.isLoading = false;
        
        if (data) {
            this.itsmData = data;
            this.processItsmData(data);
        } else if (error) {
            this.error = 'Error loading ITSM data: ' + this.reduceErrors(error);
            this.showErrorToast('Error', this.error);
            console.error('Error loading ITSM data:', error);
        }
    }
    
    /**
     * Process ITSM data into picklist options
     */
    processItsmData(data) {
        // Build category options
        this.categories = data.categories.map(cat => ({
            label: cat,
            value: cat
        }));
        
        console.log('ITSM Data loaded:', {
            categories: data.categories.length,
            services: data.serviceSetups.length,
            account: data.accountName
        });
    }
    
    /**
     * Handle Type selection (Support/Change)
     */
    handleTypeChange(event) {
        const newType = event.currentTarget.dataset.type;
        
        if (this.selectedType !== newType) {
            this.selectedType = newType;
            // Reset downstream selections
            this.resetSelections();
        }
    }
    
    /**
     * Handle Category change
     */
    handleCategoryChange(event) {
        this.selectedCategory = event.detail.value;
        this.selectedSubcategory = null;
        this.selectedServiceId = null;
        
        // Update subcategories based on selected category
        if (this.itsmData && this.itsmData.subcategoriesByCategory[this.selectedCategory]) {
            this.subcategories = this.itsmData.subcategoriesByCategory[this.selectedCategory]
                .map(sub => ({
                    label: sub,
                    value: sub
                }));
        } else {
            this.subcategories = [];
        }
        
        this.services = [];
    }
    
    /**
     * Handle Subcategory change
     */
    handleSubcategoryChange(event) {
        this.selectedSubcategory = event.detail.value;
        this.selectedServiceId = null;
        
        // Update services based on category + subcategory
        const key = `${this.selectedCategory}||${this.selectedSubcategory}`;
        
        if (this.itsmData && this.itsmData.servicesByCatSubcat[key]) {
            this.services = this.itsmData.servicesByCatSubcat[key]
                .map(svc => ({
                    label: svc.name,
                    value: svc.id
                }));
        } else {
            this.services = [];
        }
    }
    
    /**
     * Handle Service change
     */
    handleServiceChange(event) {
        this.selectedServiceId = event.detail.value;
    }
    
    /**
     * Handle Launch OmniScript button
     */
    handleLaunchOmniScript() {
        if (!this.validateSelections()) {
            return;
        }
        
        // Find the Service Setup
        const setup = this.itsmData.serviceSetups.find(
            s => s.serviceId === this.selectedServiceId
        );
        
        if (!setup) {
            this.showErrorToast('Error', 'No Service Setup found for this service');
            return;
        }
        
        // Get the appropriate form field
        const formField = this.selectedType === 'Support' 
            ? setup.relatedSupportForm 
            : setup.relatedChangeForm;
        
        if (!formField) {
            this.showErrorToast('Error', `No ${this.selectedType} form configured for this service`);
            return;
        }
        
        // Parse the form field (Format: Type:SubType:Lang:Version)
        if (!this.parseOmniScriptReference(formField)) {
            return;
        }
        
        // Show OmniScript
        this.showSelectionForm = false;
        this.showOmniScript = true;
    }
    
    /**
     * Parse OmniScript reference string
     */
    parseOmniScriptReference(reference) {
        const parts = reference.split(':');
        
        if (parts.length !== 4) {
            this.showErrorToast('Error', 'Invalid OmniScript reference format');
            return false;
        }
        
        this.omniscriptType = parts[0];
        this.omniscriptSubType = parts[1];
        this.omniscriptLang = parts[2];
        this.omniscriptVersion = parseInt(parts[3], 10);
        
        console.log('Launching OmniScript:', {
            type: this.omniscriptType,
            subType: this.omniscriptSubType,
            lang: this.omniscriptLang,
            version: this.omniscriptVersion
        });
        
        return true;
    }
    
    /**
     * Validate all selections are made
     */
    validateSelections() {
        if (!this.selectedType) {
            this.showErrorToast('Required', 'Please select Support or Change');
            return false;
        }
        if (!this.selectedCategory) {
            this.showErrorToast('Required', 'Please select a Category');
            return false;
        }
        if (!this.selectedSubcategory) {
            this.showErrorToast('Required', 'Please select a Subcategory');
            return false;
        }
        if (!this.selectedServiceId) {
            this.showErrorToast('Required', 'Please select a Service');
            return false;
        }
        return true;
    }
    
    /**
     * Reset selections when type changes
     */
    resetSelections() {
        this.selectedCategory = null;
        this.selectedSubcategory = null;
        this.selectedServiceId = null;
        this.subcategories = [];
        this.services = [];
    }
    
    /**
     * Handle back button from OmniScript
     */
    handleBack() {
        this.showOmniScript = false;
        this.showSelectionForm = true;
    }
    
    /**
     * Handle OmniScript completion
     */
    handleOmniScriptComplete(event) {
        const caseId = event.detail.caseId;
        
        // Dispatch event to parent
        this.dispatchEvent(new CustomEvent('casecreated', {
            detail: { caseId: caseId }
        }));
    }
    
    /**
     * Handle Cancel
     */
    handleCancel() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }
    
    /**
     * Toast helpers
     */
    showErrorToast(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: 'error'
            })
        );
    }
    
    reduceErrors(errors) {
        if (!Array.isArray(errors)) {
            errors = [errors];
        }
        return errors
            .filter(error => !!error)
            .map(error => {
                if (error.body && error.body.message) {
                    return error.body.message;
                } else if (error.message) {
                    return error.message;
                }
                return 'Unknown error';
            })
            .join(', ');
    }
    
    /**
     * Getters
     */
    get typeOptions() {
        return [
            { label: 'Support', value: 'Support', icon: 'utility:help' },
            { label: 'Change', value: 'Change', icon: 'utility:change_owner' }
        ];
    }
    
    get isSupportSelected() {
        return this.selectedType === 'Support';
    }
    
    get isChangeSelected() {
        return this.selectedType === 'Change';
    }
    
    get isNextDisabled() {
        return !this.selectedType || !this.selectedCategory || 
               !this.selectedSubcategory || !this.selectedServiceId;
    }
    
    get showSpinner() {
        return this.isLoading;
    }
}