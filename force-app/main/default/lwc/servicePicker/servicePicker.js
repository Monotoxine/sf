import { LightningElement, api, wire, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getITSMInitData from '@salesforce/apex/ITSMInitController.getITSMInitData';

/**
 * Service Picker for Non-Applicatif Support Cases
 *
 * Displays dependent picklists: Category → Subcategory → Service
 * Designed to be embedded in OmniScript
 *
 * NOTE: Does NOT use OmniscriptBaseMixin to avoid cross-namespace issues.
 * The component works in OmniScript by emitting standard events.
 *
 * Emits 'selectionchange' event with:
 * {
 *   serviceId: String,
 *   serviceName: String,
 *   category: String,
 *   subcategory: String,
 *   queueForAssignment: String
 * }
 */
export default class ServicePicker extends LightningElement {

    @api recordTypeId;  // Passed from OmniScript if needed

    // Data from Apex
    itsmData;
    @track categories = [];
    @track subcategories = [];
    @track services = [];

    // User selections
    @track selectedCategory;
    @track selectedSubcategory;
    @track selectedServiceId;

    // UI State
    @track isLoading = true;
    @track error;
    @track validationError;

    /**
     * Wire to get ITSM data (Services from Product2)
     */
    @wire(getITSMInitData)
    wiredItsmData({ error, data }) {
        this.isLoading = false;

        if (data) {
            console.log('📦 ITSM Data received:', data);
            this.itsmData = data;
            this.processItsmData(data);
        } else if (error) {
            console.error('❌ Error loading ITSM data:', error);
            this.error = 'Error loading services: ' + this.reduceErrors(error);
            this.showErrorToast('Error', this.error);
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

        console.log('✅ Processed:', {
            categories: data.categories.length,
            account: data.accountName
        });
    }

    /**
     * Handle Category change
     */
    handleCategoryChange(event) {
        this.selectedCategory = event.detail.value;
        this.selectedSubcategory = null;
        this.selectedServiceId = null;
        this.validationError = null;  // Clear validation error

        console.log('📍 Category selected:', this.selectedCategory);

        // Update subcategories based on selected category
        if (this.itsmData && this.itsmData.subcategoriesByCategory[this.selectedCategory]) {
            this.subcategories = this.itsmData.subcategoriesByCategory[this.selectedCategory]
                .map(sub => ({
                    label: sub,
                    value: sub
                }));

            console.log('✅ Subcategories loaded:', this.subcategories.length);
        } else {
            this.subcategories = [];
        }

        this.services = [];

        // Emit selection change
        this.emitSelectionChange();
    }

    /**
     * Handle Subcategory change
     */
    handleSubcategoryChange(event) {
        this.selectedSubcategory = event.detail.value;
        this.selectedServiceId = null;
        this.validationError = null;  // Clear validation error

        console.log('📍 Subcategory selected:', this.selectedSubcategory);

        // Update services based on category + subcategory
        const key = `${this.selectedCategory}||${this.selectedSubcategory}`;

        if (this.itsmData && this.itsmData.servicesByCatSubcat[key]) {
            this.services = this.itsmData.servicesByCatSubcat[key]
                .map(svc => ({
                    label: svc.name,
                    value: svc.id
                }));

            console.log('✅ Services loaded:', this.services.length);
        } else {
            this.services = [];
        }

        // Emit selection change
        this.emitSelectionChange();
    }

    /**
     * Handle Service change
     */
    handleServiceChange(event) {
        this.selectedServiceId = event.detail.value;
        this.validationError = null;  // Clear validation error

        console.log('📍 Service selected:', this.selectedServiceId);

        // Emit selection change
        this.emitSelectionChange();
    }

    /**
     * Emit selection change event for OmniScript
     */
    emitSelectionChange() {
        const serviceName = this.getSelectedServiceName();
        const queueForAssignment = this.getQueueForAssignment();

        const selectionData = {
            serviceId: this.selectedServiceId,
            serviceName: serviceName,
            category: this.selectedCategory,
            subcategory: this.selectedSubcategory,
            accountId: this.itsmData?.accountId,
            userDivision: this.itsmData?.userDivision,
            queueForAssignment: queueForAssignment
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
     * Get selected service name from ID
     */
    getSelectedServiceName() {
        if (!this.selectedServiceId || !this.itsmData) return '';

        const key = `${this.selectedCategory}||${this.selectedSubcategory}`;
        const serviceList = this.itsmData.servicesByCatSubcat[key] || [];
        const service = serviceList.find(s => s.id === this.selectedServiceId);
        return service ? service.name : '';
    }

    /**
     * Get QueueForAssignment from selected service
     */
    getQueueForAssignment() {
        if (!this.selectedServiceId || !this.itsmData || !this.itsmData.serviceSetups) return '';

        const setup = this.itsmData.serviceSetups.find(s => s.serviceId === this.selectedServiceId);
        return setup?.queueForAssignment || '';
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
    get isSubcategoryDisabled() {
        return !this.selectedCategory;
    }

    /**
     * Validation method called by OmniScript before navigation
     * Required to block navigation if fields are not filled
     *
     * @return {boolean} true if valid, false if invalid
     */
    @api
    validate() {
        console.log('🔍 Validating servicePicker...');

        // Clear previous validation error
        this.validationError = null;

        // Check if all required fields are selected
        if (!this.selectedCategory) {
            this.validationError = 'Please select a Category';
            console.log('❌ Validation failed: No category selected');
            this.showErrorToast('Required Field Missing', this.validationError);
            return false;
        }

        if (!this.selectedSubcategory) {
            this.validationError = 'Please select a Subcategory';
            console.log('❌ Validation failed: No subcategory selected');
            this.showErrorToast('Required Field Missing', this.validationError);
            return false;
        }

        if (!this.selectedServiceId) {
            this.validationError = 'Please select a Service';
            console.log('❌ Validation failed: No service selected');
            this.showErrorToast('Required Field Missing', this.validationError);
            return false;
        }

        console.log('✅ Validation passed');
        return true;
    }

    get isServiceDisabled() {
        return !this.selectedSubcategory;
    }

    get showSpinner() {
        return this.isLoading;
    }

    get isSelectionComplete() {
        return this.selectedCategory && this.selectedSubcategory && this.selectedServiceId;
    }

    get hasValidationError() {
        return !!this.validationError;
    }
}
