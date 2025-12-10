import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getExtractableObjects from '@salesforce/apex/CSVExtractionController.getExtractableObjects';
import getAllObjects from '@salesforce/apex/CSVExtractionController.getAllObjects';
import validateRelationship from '@salesforce/apex/CSVExtractionController.validateRelationship';
import parseCSVFile from '@salesforce/apex/CSVExtractionController.parseCSVFile';
import launchExtractionBatch from '@salesforce/apex/CSVExtractionController.launchExtractionBatch';
import getBatchJobStatus from '@salesforce/apex/CSVExtractionController.getBatchJobStatus';

/**
 * CSV Extractor Component
 * Allows dynamic extraction of Parent-Child data with Governor Limits handling
 */
export default class CsvExtractor extends LightningElement {

    // UI State
    @track currentStep = 1;
    @track isLoading = false;

    // File Upload
    @track uploadedFileName = '';
    @track uploadedFileData = '';
    @track parsedIds = [];

    // Object Selection
    @track masterObjects = [];
    @track childObjects = [];
    @track selectedMasterObject = '';
    @track selectedChildObject = '';

    // Relationship Validation
    @track relationshipInfo = null;
    @track hasValidRelationship = false;

    // Batch Execution
    @track batchJobId = '';
    @track batchStatus = '';
    @track batchProgress = 0;
    @track isExtracting = false;

    // Polling interval ID
    pollingIntervalId;

    /**
     * Wire to get Master objects (with DataMigrationId__c)
     */
    @wire(getExtractableObjects)
    wiredMasterObjects({ error, data }) {
        if (data) {
            console.log('📦 Master objects loaded:', data.length);
            this.masterObjects = data;
        } else if (error) {
            console.error('❌ Error loading master objects:', error);
            this.showToast('Error', 'Failed to load objects', 'error');
        }
    }

    /**
     * Wire to get all Child objects
     */
    @wire(getAllObjects)
    wiredChildObjects({ error, data }) {
        if (data) {
            console.log('📦 Child objects loaded:', data.length);
            this.childObjects = data;
        } else if (error) {
            console.error('❌ Error loading child objects:', error);
            this.showToast('Error', 'Failed to load objects', 'error');
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
    handleMasterObjectChange(event) {
        this.selectedMasterObject = event.detail.value;
        console.log('📍 Master object selected:', this.selectedMasterObject);

        // Reset relationship validation
        this.relationshipInfo = null;
        this.hasValidRelationship = false;

        // Re-validate if child is already selected
        if (this.selectedChildObject) {
            this.validateRelationshipBetweenObjects();
        }
    }

    /**
     * Handle Child Object change
     */
    handleChildObjectChange(event) {
        this.selectedChildObject = event.detail.value;
        console.log('📍 Child object selected:', this.selectedChildObject);

        // Validate relationship
        if (this.selectedMasterObject) {
            this.validateRelationshipBetweenObjects();
        }
    }

    /**
     * Validate relationship between Master and Child
     */
    async validateRelationshipBetweenObjects() {
        if (!this.selectedMasterObject || !this.selectedChildObject) return;

        this.isLoading = true;

        try {
            const result = await validateRelationship({
                masterObject: this.selectedMasterObject,
                childObject: this.selectedChildObject
            });

            this.relationshipInfo = result;
            this.hasValidRelationship = result.hasRelationship;

            if (result.hasRelationship) {
                console.log('✅ Relationship validated:', result.relationshipField);
                this.showToast('Relationship Found',
                    `${result.relationshipLabel} (${result.relationshipType})`,
                    'success');
            } else {
                console.log('⚠️ No relationship found');
                this.showToast('No Relationship', result.message, 'warning');
            }

        } catch (error) {
            console.error('❌ Error validating relationship:', error);
            this.showToast('Error', 'Failed to validate relationship', 'error');
        } finally {
            this.isLoading = false;
        }
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
     * Launch extraction
     */
    async handleLaunchExtraction() {
        // Final validation
        if (!this.selectedMasterObject) {
            this.showToast('Error', 'Master Object is required', 'error');
            return;
        }

        if (!this.parsedIds || this.parsedIds.length === 0) {
            this.showToast('Error', 'No IDs to extract', 'error');
            return;
        }

        this.isLoading = true;
        this.isExtracting = true;

        try {
            const result = await launchExtractionBatch({
                masterObject: this.selectedMasterObject,
                childObject: this.selectedChildObject || null,
                ids: this.parsedIds
            });

            if (result.success) {
                this.batchJobId = result.batchJobId;
                console.log('✅ Batch launched:', this.batchJobId);
                this.showToast('Success', 'Extraction started successfully', 'success');

                // Start polling for status
                this.startStatusPolling();
                this.currentStep = 4;

            } else {
                this.showToast('Error', result.message, 'error');
                this.isExtracting = false;
            }

        } catch (error) {
            console.error('❌ Error launching extraction:', error);
            this.showToast('Error', 'Failed to launch extraction', 'error');
            this.isExtracting = false;
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Start polling for batch status
     */
    startStatusPolling() {
        // Poll every 3 seconds
        this.pollingIntervalId = setInterval(() => {
            this.checkBatchStatus();
        }, 3000);
    }

    /**
     * Check batch status
     */
    async checkBatchStatus() {
        if (!this.batchJobId) return;

        try {
            const status = await getBatchJobStatus({
                batchJobId: this.batchJobId
            });

            this.batchStatus = status.status;
            this.batchProgress = status.progressPercentage || 0;

            console.log('📊 Batch status:', status.status, '-', this.batchProgress + '%');

            // Stop polling if completed or failed
            if (status.isCompleted || status.isFailed) {
                clearInterval(this.pollingIntervalId);
                this.isExtracting = false;

                if (status.isCompleted) {
                    this.showToast('Success', 'Extraction completed successfully!', 'success');
                } else if (status.isFailed) {
                    this.showToast('Error', 'Extraction failed: ' + status.extendedStatus, 'error');
                }
            }

        } catch (error) {
            console.error('❌ Error checking batch status:', error);
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
        this.selectedChildObject = '';
        this.relationshipInfo = null;
        this.hasValidRelationship = false;
        this.batchJobId = '';
        this.batchStatus = '';
        this.batchProgress = 0;
        this.isExtracting = false;

        if (this.pollingIntervalId) {
            clearInterval(this.pollingIntervalId);
        }
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

    get canLaunchExtraction() {
        return this.selectedMasterObject !== '' &&
               this.parsedIds &&
               this.parsedIds.length > 0;
    }

    get idCountText() {
        return this.parsedIds ? `${this.parsedIds.length} IDs loaded` : '';
    }

    get relationshipText() {
        if (!this.relationshipInfo) return '';

        if (this.relationshipInfo.hasRelationship) {
            return `✓ ${this.relationshipInfo.relationshipLabel} (${this.relationshipInfo.relationshipType})`;
        } else {
            return '✗ No relationship found';
        }
    }

    get progressStyle() {
        return `width: ${this.batchProgress}%`;
    }

    /**
     * Cleanup on component destroy
     */
    disconnectedCallback() {
        if (this.pollingIntervalId) {
            clearInterval(this.pollingIntervalId);
        }
    }
}
