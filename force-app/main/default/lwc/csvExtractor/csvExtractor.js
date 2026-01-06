import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getExtractableObjects from '@salesforce/apex/CSVExtractionController.getExtractableObjects';
import getChildObjectsHierarchy from '@salesforce/apex/CSVExtractionController.getChildObjectsHierarchy';
import parseCSVFile from '@salesforce/apex/CSVExtractionController.parseCSVFile';
import extractCSVDirect from '@salesforce/apex/CSVExtractionController.extractCSVDirect';

/**
 * CSV Extractor Component
 * Allows dynamic extraction of Parent-Child data with tree-based hierarchical selection
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
    @track selectedMasterObject = '';

    // Child Objects Tree
    @track childObjectsTree = [];
    @track flattenedTree = [];
    @track selectedChildObjects = new Set();
    @track expandedNodes = new Set();

    // Extraction State
    @track isExtracting = false;
    @track extractionComplete = false;
    @track extractionResult = null;

    /**
     * Wire to get Master objects (with TEKCO_DataMigrationId__c)
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

        // Reset child selections
        this.selectedChildObjects.clear();
        this.expandedNodes.clear();
        this.childObjectsTree = [];
        this.flattenedTree = [];

        // Load child objects hierarchy
        if (this.selectedMasterObject) {
            await this.loadChildObjectsHierarchy();
        }
    }

    /**
     * Load child objects hierarchy for selected master object
     */
    async loadChildObjectsHierarchy() {
        this.isLoading = true;

        try {
            const result = await getChildObjectsHierarchy({
                masterObject: this.selectedMasterObject
            });

            console.log('🌳 Child objects hierarchy loaded:', result);
            this.childObjectsTree = result || [];
            this.buildFlattenedTree();

        } catch (error) {
            console.error('❌ Error loading child objects:', error);
            this.showToast('Error', 'Failed to load child objects', 'error');
            this.childObjectsTree = [];
            this.flattenedTree = [];
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Build flattened tree for rendering with indentation
     */
    buildFlattenedTree() {
        const flattened = [];

        const traverse = (nodes, level = 0, parentId = null) => {
            if (!nodes || nodes.length === 0) return;

            nodes.forEach((node, index) => {
                const nodeId = parentId ? `${parentId}-${index}` : `node-${index}`;
                const isExpanded = this.expandedNodes.has(nodeId);
                const isSelected = this.selectedChildObjects.has(node.objectName);

                flattened.push({
                    id: nodeId,
                    objectName: node.objectName,
                    objectLabel: node.objectLabel,
                    relationshipField: node.relationshipField,
                    relationshipLabel: node.relationshipLabel,
                    relationshipType: node.relationshipType,
                    level: level,
                    indentStyle: `padding-left: ${level * 20}px`,
                    isExpanded: isExpanded,
                    isSelected: isSelected,
                    children: node.children,
                    chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright'
                });

                // Add children if expanded
                if (isExpanded && node.children && node.children.length > 0) {
                    traverse(node.children, level + 1, nodeId);
                }
            });
        };

        traverse(this.childObjectsTree);
        this.flattenedTree = flattened;
    }

    /**
     * Handle expand/collapse node
     */
    handleExpandNode(event) {
        const nodeId = event.currentTarget.dataset.nodeId;

        if (this.expandedNodes.has(nodeId)) {
            this.expandedNodes.delete(nodeId);
        } else {
            this.expandedNodes.add(nodeId);
        }

        this.buildFlattenedTree();
    }

    /**
     * Handle child object selection toggle
     */
    handleChildToggle(event) {
        const nodeId = event.currentTarget.dataset.nodeId;
        const isChecked = event.detail.checked;

        // Find the node in flattened tree
        const node = this.flattenedTree.find(n => n.id === nodeId);

        if (!node) return;

        if (isChecked) {
            this.selectedChildObjects.add(node.objectName);
            console.log('✅ Child selected:', node.objectName);
        } else {
            this.selectedChildObjects.delete(node.objectName);
            console.log('➖ Child deselected:', node.objectName);
        }

        // Rebuild tree to reflect selection
        this.buildFlattenedTree();
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
     * Handle extraction and download CSV files directly
     */
    async handleDownload() {
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
            console.log('🚀 Starting direct extraction...');
            console.log('📊 Master Object:', this.selectedMasterObject);
            console.log('📊 Selected Children:', Array.from(this.selectedChildObjects));

            const result = await extractCSVDirect({
                masterObject: this.selectedMasterObject,
                childObjects: Array.from(this.selectedChildObjects),
                ids: this.parsedIds
            });

            if (result.success) {
                console.log('✅ Extraction successful');

                this.extractionResult = result;
                this.extractionComplete = true;

                // Download Master CSV
                if (result.masterCSV) {
                    this.downloadCSV(result.masterCSV, `${this.selectedMasterObject}.csv`);
                }

                // Download Child CSVs
                if (result.childCSVs && result.childCSVs.length > 0) {
                    result.childCSVs.forEach((childCSV, index) => {
                        setTimeout(() => {
                            this.downloadCSV(childCSV.csvContent, `${childCSV.objectName}.csv`);
                        }, (index + 1) * 500);
                    });
                }

                this.showToast('Success', 'Data extracted and downloaded successfully', 'success');

            } else {
                this.showToast('Error', result.message, 'error');
            }

        } catch (error) {
            console.error('❌ Error during extraction:', error);
            const errorMessage = error.body && error.body.message ? error.body.message : 'Unknown error occurred';
            this.showToast('Error', 'Failed to extract data: ' + errorMessage, 'error');
        } finally {
            this.isLoading = false;
            this.isExtracting = false;
        }
    }

    /**
     * Download CSV file directly in browser
     */
    downloadCSV(csvContent, fileName) {
        // Create a Blob from CSV content
        const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });

        // Create download link
        const link = document.createElement('a');
        const url = URL.createObjectURL(blob);

        link.setAttribute('href', url);
        link.setAttribute('download', fileName);
        link.style.visibility = 'hidden';

        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);

        console.log('📥 Downloaded:', fileName);
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
        this.childObjectsTree = [];
        this.flattenedTree = [];
        this.selectedChildObjects = new Set();
        this.expandedNodes = new Set();
        this.isExtracting = false;
        this.extractionComplete = false;
        this.extractionResult = null;
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

    get extractionSummary() {
        if (!this.extractionResult) return '';

        return `Master: ${this.extractionResult.masterRecordCount} records | Child: ${this.extractionResult.childRecordCount} records`;
    }
}
