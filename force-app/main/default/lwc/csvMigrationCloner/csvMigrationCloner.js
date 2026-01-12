import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getExtractableObjects from '@salesforce/apex/CSVMigrationClonerController.getExtractableObjects';
import parseCSVFile from '@salesforce/apex/CSVMigrationClonerController.parseCSVFile';
import getRelatedObjects from '@salesforce/apex/CSVMigrationClonerController.getRelatedObjects';
import cloneRecords from '@salesforce/apex/CSVMigrationClonerController.cloneRecords';

/**
 * CSV Migration Cloner Component
 * Allows cloning of Parent-Child data with DataMigrationId suffix
 */
export default class CsvMigrationCloner extends LightningElement {

    // UI State
    @track currentStep = 1;
    @track isLoading = false;

    // File Upload
    @track uploadedFileName = '';
    @track uploadedFileData = '';
    @track parsedIds = [];

    // Object Selection
    @track masterObjects = [];
    @track selectedMasterObject = '';

    // Related Objects
    @track relatedObjects = [];
    @track selectedRelatedObjects = [];

    // Suffix Configuration
    @track migrationSuffix = '';

    // Cloning State
    @track isCloning = false;
    @track cloningComplete = false;
    @track cloningResult = null;

    /**
     * Lifecycle: Initialize component
     */
    connectedCallback() {
        this.loadMasterObjects();
    }

    /**
     * Load Master objects (with DataMigrationId__c)
     */
    async loadMasterObjects() {
        this.isLoading = true;

        try {
            const data = await getExtractableObjects();
            console.log('📦 Master objects loaded:', data.length);
            this.masterObjects = data;
        } catch (error) {
            console.error('❌ Error loading master objects:', error);
            this.showToast('Error', 'Failed to load objects', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Handle file upload
     */
    handleFileUpload(event) {
        const file = event.target.files[0];

        if (!file) return;

        console.log('📁 File selected:', file.name);

        if (!file.name.endsWith('.csv')) {
            this.showToast('Error', 'Please upload a CSV file', 'error');
            return;
        }

        this.uploadedFileName = file.name;

        // Read file content
        const reader = new FileReader();

        reader.onload = () => {
            const base64 = reader.result.split(',')[1];
            this.uploadedFileData = base64;

            // Parse CSV
            this.parseCSV();
        };

        reader.onerror = () => {
            this.showToast('Error', 'Failed to read file', 'error');
        };

        reader.readAsDataURL(file);
    }

    /**
     * Parse CSV file
     */
    async parseCSV() {
        this.isLoading = true;

        try {
            const result = await parseCSVFile({
                base64Data: this.uploadedFileData,
                fileName: this.uploadedFileName
            });

            if (result.success) {
                this.parsedIds = result.ids;
                console.log('✅ Parsed IDs:', result.idCount);
                this.showToast('Success', result.message, 'success');
            } else {
                this.showToast('Error', result.message, 'error');
            }

        } catch (error) {
            console.error('❌ Error parsing CSV:', error);
            this.showToast('Error', 'Failed to parse CSV file', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Handle Master Object change
     */
    async handleMasterObjectChange(event) {
        this.selectedMasterObject = event.detail.value;
        console.log('📍 Master object selected:', this.selectedMasterObject);

        // Load related objects
        await this.loadRelatedObjects();
    }

    /**
     * Load related objects (Lookup/Master-Detail)
     */
    async loadRelatedObjects() {
        if (!this.selectedMasterObject) return;

        this.isLoading = true;

        try {
            const result = await getRelatedObjects({
                parentObject: this.selectedMasterObject
            });

            console.log('📦 Related objects:', result.length);

            // Add selected property for checkboxes
            this.relatedObjects = result.map(obj => ({
                ...obj,
                selected: false
            }));

            if (result.length === 0) {
                this.showToast('Info', 'No related objects found', 'info');
            } else {
                this.showToast('Success', `Found ${result.length} related objects`, 'success');
            }

        } catch (error) {
            console.error('❌ Error loading related objects:', error);
            this.showToast('Error', 'Failed to load related objects', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Handle related object checkbox change
     */
    handleRelatedObjectToggle(event) {
        const objectName = event.target.dataset.object;
        const isChecked = event.target.checked;

        console.log('📍 Toggle:', objectName, isChecked);

        // Update selected state
        this.relatedObjects = this.relatedObjects.map(obj => {
            if (obj.apiName === objectName) {
                return { ...obj, selected: isChecked };
            }
            return obj;
        });

        // Update selected list
        this.selectedRelatedObjects = this.relatedObjects
            .filter(obj => obj.selected)
            .map(obj => obj.apiName);

        console.log('✅ Selected objects:', this.selectedRelatedObjects);
    }

    /**
     * Handle suffix input change
     */
    handleSuffixChange(event) {
        this.migrationSuffix = event.target.value;
        console.log('📍 Suffix:', this.migrationSuffix);
    }

    /**
     * Navigate to next step
     */
    handleNext() {
        // Validate current step
        if (this.currentStep === 1) {
            if (!this.parsedIds || this.parsedIds.length === 0) {
                this.showToast('Error', 'Please upload a CSV file with IDs', 'error');
                return;
            }
        } else if (this.currentStep === 2) {
            if (!this.selectedMasterObject) {
                this.showToast('Error', 'Please select a Master Object', 'error');
                return;
            }
        } else if (this.currentStep === 3) {
            if (!this.migrationSuffix || this.migrationSuffix.trim() === '') {
                this.showToast('Error', 'Please enter a Migration Suffix', 'error');
                return;
            }
        }

        this.currentStep++;
    }

    /**
     * Navigate to previous step
     */
    handlePrevious() {
        this.currentStep--;
    }

    /**
     * Launch cloning process
     */
    async handleLaunchCloning() {
        // Final validation
        if (!this.selectedMasterObject) {
            this.showToast('Error', 'Master Object is required', 'error');
            return;
        }

        if (!this.parsedIds || this.parsedIds.length === 0) {
            this.showToast('Error', 'No IDs to clone', 'error');
            return;
        }

        if (!this.migrationSuffix || this.migrationSuffix.trim() === '') {
            this.showToast('Error', 'Migration Suffix is required', 'error');
            return;
        }

        this.isLoading = true;
        this.isCloning = true;

        try {
            console.log('🚀 Starting cloning process...');
            console.log('📍 Master:', this.selectedMasterObject);
            console.log('📍 Related:', this.selectedRelatedObjects);
            console.log('📍 Suffix:', this.migrationSuffix);
            console.log('📍 IDs:', this.parsedIds.length);

            const result = await cloneRecords({
                masterObject: this.selectedMasterObject,
                relatedObjects: this.selectedRelatedObjects,
                ids: this.parsedIds,
                suffix: this.migrationSuffix.trim()
            });

            if (result.success) {
                console.log('✅ Cloning successful:', result);

                this.cloningResult = result;
                this.cloningComplete = true;

                this.showToast('Success',
                    `Cloned ${result.masterRecordCount} master records and ${result.totalChildRecords} related records`,
                    'success');

            } else {
                this.showToast('Error', result.message, 'error');
            }

        } catch (error) {
            console.error('❌ Error during cloning:', error);
            const errorMessage = error.body?.message || error.message || 'Failed to clone data';
            this.showToast('Error', errorMessage, 'error');
        } finally {
            this.isLoading = false;
            this.isCloning = false;
        }
    }

    /**
     * Reset wizard
     */
    handleReset() {
        this.currentStep = 1;
        this.uploadedFileName = '';
        this.uploadedFileData = '';
        this.parsedIds = [];
        this.selectedMasterObject = '';
        this.relatedObjects = [];
        this.selectedRelatedObjects = [];
        this.migrationSuffix = '';
        this.isCloning = false;
        this.cloningComplete = false;
        this.cloningResult = null;
    }

    /**
     * Show toast notification
     */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: variant
            })
        );
    }

    /**
     * Getters for UI
     */
    get isStep1() {
        return this.currentStep === 1;
    }

    get isStep2() {
        return this.currentStep === 2;
    }

    get isStep3() {
        return this.currentStep === 3;
    }

    get isStep4() {
        return this.currentStep === 4;
    }

    get canProceedStep1() {
        return this.parsedIds && this.parsedIds.length > 0;
    }

    get canProceedStep2() {
        return this.selectedMasterObject !== '';
    }

    get canProceedStep3() {
        return this.migrationSuffix && this.migrationSuffix.trim() !== '';
    }

    get canLaunchCloning() {
        return this.selectedMasterObject !== '' &&
               this.parsedIds &&
               this.parsedIds.length > 0 &&
               this.migrationSuffix &&
               this.migrationSuffix.trim() !== '';
    }

    get idCountText() {
        return this.parsedIds ? `${this.parsedIds.length} IDs loaded` : '';
    }

    get hasRelatedObjects() {
        return this.relatedObjects && this.relatedObjects.length > 0;
    }

    get selectedRelatedObjectsCount() {
        return this.selectedRelatedObjects.length;
    }

    get cloningSummary() {
        if (!this.cloningResult) return '';

        let summary = `Master Object: ${this.cloningResult.masterRecordCount} records cloned\n`;

        if (this.cloningResult.childRecordCounts) {
            summary += '\nRelated Objects:\n';
            Object.keys(this.cloningResult.childRecordCounts).forEach(objName => {
                summary += `- ${objName}: ${this.cloningResult.childRecordCounts[objName]} records\n`;
            });
        }

        return summary;
    }
}
