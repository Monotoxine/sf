import { LightningElement, wire, track } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CASE_OBJECT from '@salesforce/schema/Case';

/**
 * Router component for Case creation override
 *
 * NEW ARCHITECTURE (LWC in OmniScript):
 * - Reads recordTypeId from CurrentPageReference (selected in standard Salesforce modal)
 * - Routes directly to the appropriate OmniScript based on Record Type:
 *   * NIM-OS IT Support → OmniScript IT Support (contains applicationPicker LWC)
 *   * NIM-OS Support → OmniScript Support (contains servicePicker LWC)
 *   * NIM-OS Change → OmniScript Change (no picker yet)
 *   * Other RTs → Navigate to standard Case creation (with nooverride to avoid loop)
 *
 * The router ONLY handles RT detection and navigation.
 * All business logic (picklists, form, Case creation) is in OmniScripts.
 */
export default class NimOsNewCaseRouter extends NavigationMixin(LightningElement) {

    // OmniScript mapping for each Record Type
    OMNISCRIPT_MAPPING = {
        'NIM-OS_IT_Support': {
            type: 'ITSM',
            subType: 'ITSupport',
            language: 'English',
            version: 1
        },
        'NIM-OS_Support': {
            type: 'ITSM',
            subType: 'Support',
            language: 'English',
            version: 1
        },
        'NIM-OS_Change': {
            type: 'ITSM',
            subType: 'Change',
            language: 'English',
            version: 1
        }
    };

    @track selectedRecordTypeId;
    @track selectedRecordTypeDeveloperName;
    @track isLoading = true;
    @track error;

    // Store Case object info for RT lookups
    caseObjectInfo;

    /**
     * Read recordTypeId from URL/page state (set by standard Salesforce modal)
     */
    @wire(CurrentPageReference)
    currentPageReference(pageRef) {
        console.log('🔵 CurrentPageReference changed:', pageRef);

        if (pageRef && pageRef.state) {
            // recordTypeId comes from standard Salesforce "Select Record Type" modal
            const recordTypeId = pageRef.state.recordTypeId;

            console.log('📍 RecordTypeId from page state:', recordTypeId);

            if (recordTypeId && recordTypeId !== this.selectedRecordTypeId) {
                this.selectedRecordTypeId = recordTypeId;
                this.resolveRecordTypeAndRoute();
            }
        }
    }

    /**
     * Get Case object info to resolve Record Type details
     */
    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    wiredObjectInfo({ error, data }) {
        console.log('🔵 getObjectInfo called');

        if (data) {
            console.log('✅ Case ObjectInfo received');
            this.caseObjectInfo = data;
            this.isLoading = false;

            // If we already have a recordTypeId from page state, resolve it now
            if (this.selectedRecordTypeId) {
                this.resolveRecordTypeAndRoute();
            }
        } else if (error) {
            console.error('❌ ObjectInfo error:', error);
            this.error = 'Error loading Case object info: ' + this.reduceErrors(error);
            this.showErrorToast('Error', this.error);
            this.isLoading = false;
        }
    }

    /**
     * Resolve Record Type Developer Name and route accordingly
     */
    resolveRecordTypeAndRoute() {
        if (!this.caseObjectInfo || !this.selectedRecordTypeId) {
            console.log('⏳ Waiting for ObjectInfo or RecordTypeId...');
            return;
        }

        console.log('🔍 Resolving Record Type:', this.selectedRecordTypeId);

        const rtInfo = this.caseObjectInfo.recordTypeInfos[this.selectedRecordTypeId];

        if (!rtInfo) {
            console.error('❌ Record Type not found:', this.selectedRecordTypeId);
            this.error = 'Invalid Record Type';
            this.showErrorToast('Error', this.error);
            return;
        }

        // Get the Developer Name (need to derive from Name - Salesforce doesn't expose devName directly in UI API)
        // Note: This assumes DeveloperName follows pattern: Name with spaces replaced by underscores
        this.selectedRecordTypeDeveloperName = rtInfo.name.replace(/\s+/g, '_');

        console.log('✅ Record Type resolved:', {
            id: this.selectedRecordTypeId,
            name: rtInfo.name,
            developerName: this.selectedRecordTypeDeveloperName
        });

        // Route based on Record Type
        this.routeBasedOnRecordType();
    }

    /**
     * Route user based on selected Record Type
     * Routes directly to OmniScript (no intermediate container)
     */
    routeBasedOnRecordType() {
        console.log('🚦 Routing based on RT:', this.selectedRecordTypeDeveloperName);

        // Check if RT has a mapped OmniScript
        const omniscriptConfig = this.OMNISCRIPT_MAPPING[this.selectedRecordTypeDeveloperName];

        if (omniscriptConfig) {
            console.log('✅ NIM-OS RT detected → Navigating to OmniScript:', omniscriptConfig);
            this.navigateToOmniScript(omniscriptConfig);
        } else {
            console.log('✅ Other RT detected → Navigating to standard Case creation');
            this.navigateToStandardCaseCreation();
        }
    }

    /**
     * Navigate directly to OmniScript with context data
     */
    navigateToOmniScript(config) {
        console.log('🚀 Navigating to OmniScript:', config);

        // Build minimal context to pass to OmniScript
        // OmniScript will load additional data (User, Account, etc.) via DataRaptor/IP
        const contextData = {
            recordTypeId: this.selectedRecordTypeId
        };

        // Encode seed data
        const seedDataEncoded = encodeURIComponent(JSON.stringify(contextData));

        console.log('📦 Context data:', contextData);

        // Navigate using modern standard__featurePage
        this[NavigationMixin.Navigate]({
            type: 'standard__featurePage',
            attributes: {
                featureName: 'omnistudio',
                pageName: 'omniscript'
            },
            state: {
                omniscript__type: config.type,
                omniscript__subType: config.subType,
                omniscript__language: config.language,
                omniscript__version: config.version,
                omniscript__seedData: seedDataEncoded
            }
        });

        console.log('✅ Navigation initiated');
    }

    /**
     * Navigate to standard Case creation (for non-NIM-OS RTs)
     * Uses nooverride=1 to prevent infinite loop
     */
    navigateToStandardCaseCreation() {
        console.log('🔵 Navigating to standard Case creation');
        console.log('📍 RecordTypeId:', this.selectedRecordTypeId);

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Case',
                actionName: 'new'
            },
            state: {
                recordTypeId: this.selectedRecordTypeId,
                nooverride: '1'  // CRITICAL: Prevents infinite override loop
            }
        });

        console.log('✅ Navigation initiated');
    }

    /**
     * Toast message helpers
     */
    showErrorToast(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }

    /**
     * Error message reducer
     */
    reduceErrors(errors) {
        if (!Array.isArray(errors)) {
            errors = [errors];
        }

        return errors
            .filter(error => !!error)
            .map(error => {
                if (Array.isArray(error.body)) {
                    return error.body.map(e => e.message);
                } else if (error.body && typeof error.body.message === 'string') {
                    return error.body.message;
                } else if (typeof error.message === 'string') {
                    return error.message;
                }
                return 'Unknown error';
            })
            .reduce((prev, curr) => prev + ', ' + curr, '')
            .substring(2);
    }

    /**
     * Getters for template
     */
    get showSpinner() {
        return this.isLoading;
    }

    get showError() {
        return !!this.error;
    }
}