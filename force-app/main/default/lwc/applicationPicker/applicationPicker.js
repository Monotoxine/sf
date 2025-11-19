import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getITSupportData from '@salesforce/apex/ITSupportController.getITSupportData';

/**
 * Application Picker for IT Support Cases
 *
 * Displays dependent picklists: Application → Module
 * Designed to be embedded in OmniScript
 *
 * NOTE: Does NOT use OmniscriptBaseMixin to avoid cross-namespace issues.
 * The component works in OmniScript by emitting standard events.
 *
 * Emits 'selectionchange' event with:
 * {
 *   applicationName: String,
 *   moduleId: String,
 *   moduleName: String
 * }
 */
export default class ApplicationPicker extends LightningElement {

    @api recordTypeId;  // Passed from OmniScript if needed

    // Data from Apex
    itSupportData;
    @track applications = [];
    @track modules = [];

    // User selections
    @track selectedApplication;
    @track selectedModuleId;

    // UI State
    @track isLoading = true;
    @track error;

    /**
     * Wire to get IT Support data (Applications/Modules from Contracts)
     */
    @wire(getITSupportData)
    wiredITSupportData({ error, data }) {
        this.isLoading = false;

        if (data) {
            console.log('📦 IT Support Data received:', data);
            this.itSupportData = data;
            this.processData(data);
        } else if (error) {
            console.error('❌ Error loading IT Support data:', error);
            this.error = 'Error loading applications: ' + this.reduceErrors(error);
            this.showErrorToast('Error', this.error);
        }
    }

    /**
     * Process IT Support data into picklist options
     */
    processData(data) {
        // Build application options
        this.applications = data.applications.map(app => ({
            label: app,
            value: app
        }));

        console.log('✅ Processed:', {
            applications: this.applications.length,
            accountName: data.accountName
        });
    }

    /**
     * Handle Application change
     */
    handleApplicationChange(event) {
        this.selectedApplication = event.detail.value;
        this.selectedModuleId = null;  // Reset module selection

        console.log('📍 Application selected:', this.selectedApplication);

        // Update modules based on selected application
        if (this.itSupportData && this.itSupportData.modulesByApplication[this.selectedApplication]) {
            const moduleDTOs = this.itSupportData.modulesByApplication[this.selectedApplication];
            this.modules = moduleDTOs.map(mod => ({
                label: mod.name,
                value: mod.id
            }));

            console.log('✅ Modules loaded:', this.modules.length);
        } else {
            this.modules = [];
            console.log('⚠️ No modules found for application:', this.selectedApplication);
        }

        // Emit selection change
        this.emitSelectionChange();
    }

    /**
     * Handle Module change
     */
    handleModuleChange(event) {
        this.selectedModuleId = event.detail.value;

        console.log('📍 Module selected:', this.selectedModuleId);

        // Emit selection change
        this.emitSelectionChange();
    }

    /**
     * Emit selection change event for OmniScript
     */
    emitSelectionChange() {
        const moduleName = this.getSelectedModuleName();

        const selectionData = {
            applicationName: this.selectedApplication,
            moduleId: this.selectedModuleId,
            moduleName: moduleName,
            accountId: this.itSupportData?.accountId,
            userDivision: this.itSupportData?.userDivision
        };

        console.log('📤 Emitting selection:', selectionData);

        // Emit custom event for OmniScript
        const event = new CustomEvent('selectionchange', {
            detail: selectionData,
            bubbles: true,
            composed: true
        });
        this.dispatchEvent(event);
    }

    /**
     * Get selected module name from ID
     */
    getSelectedModuleName() {
        if (!this.selectedModuleId || !this.itSupportData) return '';

        const moduleDTOs = this.itSupportData.modulesByApplication[this.selectedApplication];
        if (!moduleDTOs) return '';

        const module = moduleDTOs.find(m => m.id === this.selectedModuleId);
        return module ? module.name : '';
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
    get isModuleDisabled() {
        return !this.selectedApplication;
    }

    get showSpinner() {
        return this.isLoading;
    }

    get isSelectionComplete() {
        return this.selectedApplication && this.selectedModuleId;
    }
}
