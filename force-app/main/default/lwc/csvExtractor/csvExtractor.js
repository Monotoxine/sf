import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getExtractableObjects from '@salesforce/apex/CSVExtractionController.getExtractableObjects';
import getAllObjects from '@salesforce/apex/CSVExtractionController.getAllObjects';
import getChildObjects from '@salesforce/apex/CSVExtractionController.getChildObjects';
import validateRelationship from '@salesforce/apex/CSVExtractionController.validateRelationship';
import parseCSVFile from '@salesforce/apex/CSVExtractionController.parseCSVFile';
import extractCSVDirect from '@salesforce/apex/CSVExtractionController.extractCSVDirect';

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
    @track detectedMasterObject = '';
    @track detectedMasterObjectLabel = '';

    // Object Selection
    @track masterObjects = [];
    @track selectedMasterObject = '';

    // Multi-level Child Selection
    @track childSelectionTree = []; // Tree structure for multi-level child selection
    @track selectedChildrenConfig = []; // Configuration for extraction

    // Extraction State
    @track isExtracting = false;
    @track extractionComplete = false;
    @track extractionResult = null;

    /**
     * Wire to get Master objects (for manual override)
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
                this.detectedMasterObject = result.detectedObject;
                this.detectedMasterObjectLabel = result.detectedObjectLabel;

                // Auto-set the master object if detected
                if (result.detectedObject) {
                    this.selectedMasterObject = result.detectedObject;
                    console.log('🔍 Auto-detected master object:', result.detectedObject);
                }

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

        // Reset child selection tree
        this.childSelectionTree = [];
        this.selectedChildrenConfig = [];

        // Load child objects for the selected master
        if (this.selectedMasterObject) {
            await this.loadChildObjectsForParent(this.selectedMasterObject, null, 0);
        }
    }

    /**
     * Load child objects for a given parent
     */
    async loadChildObjectsForParent(parentObject, parentNode, level) {
        this.isLoading = true;

        try {
            const childObjects = await getChildObjects({ parentObjectName: parentObject });

            console.log(`📦 Found ${childObjects.length} child objects for ${parentObject}`);

            if (!parentNode) {
                // Root level - add to tree
                this.childSelectionTree = childObjects.map(child => ({
                    ...child,
                    id: this.generateId(),
                    level: level,
                    isSelected: false,
                    isExpanded: false,
                    children: [],
                    hasLoadedChildren: false
                }));
            } else {
                // Nested level - add to parent node
                parentNode.children = childObjects.map(child => ({
                    ...child,
                    id: this.generateId(),
                    level: level,
                    isSelected: false,
                    isExpanded: false,
                    children: [],
                    hasLoadedChildren: false,
                    parentNodeId: parentNode.id
                }));
                parentNode.hasLoadedChildren = true;
            }

            // Force reactivity
            this.childSelectionTree = [...this.childSelectionTree];

        } catch (error) {
            console.error('❌ Error loading child objects:', error);
            this.showToast('Error', 'Failed to load child objects', 'error');
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Generate unique ID for tree nodes
     */
    generateId() {
        return 'node_' + Math.random().toString(36).substr(2, 9) + '_' + Date.now();
    }

    /**
     * Handle child object selection toggle
     */
    handleChildToggle(event) {
        const nodeId = event.currentTarget.dataset.nodeId;
        const node = this.findNodeById(nodeId, this.childSelectionTree);

        if (node) {
            node.isSelected = !node.isSelected;
            console.log(`📍 ${node.isSelected ? 'Selected' : 'Deselected'} child: ${node.objectName}`);

            // Force reactivity
            this.childSelectionTree = [...this.childSelectionTree];

            // Rebuild config
            this.buildChildExtractionConfig();
        }
    }

    /**
     * Handle expand/collapse node to load children
     */
    async handleExpandNode(event) {
        const nodeId = event.currentTarget.dataset.nodeId;
        const node = this.findNodeById(nodeId, this.childSelectionTree);

        if (node) {
            node.isExpanded = !node.isExpanded;

            // Load children if not loaded yet and expanding
            if (node.isExpanded && !node.hasLoadedChildren) {
                await this.loadChildObjectsForParent(node.objectName, node, node.level + 1);
            }

            // Force reactivity
            this.childSelectionTree = [...this.childSelectionTree];
        }
    }

    /**
     * Find node by ID in tree
     */
    findNodeById(nodeId, nodes) {
        for (let node of nodes) {
            if (node.id === nodeId) {
                return node;
            }

            if (node.children && node.children.length > 0) {
                const found = this.findNodeById(nodeId, node.children);
                if (found) return found;
            }
        }
        return null;
    }

    /**
     * Build child extraction configuration from selected nodes
     */
    buildChildExtractionConfig() {
        this.selectedChildrenConfig = this.buildConfigFromNodes(this.childSelectionTree);
        console.log('🔧 Built extraction config:', JSON.stringify(this.selectedChildrenConfig, null, 2));
    }

    /**
     * Recursively build config from nodes
     */
    buildConfigFromNodes(nodes) {
        const configs = [];

        for (let node of nodes) {
            if (node.isSelected) {
                const config = {
                    childObject: node.objectName,
                    relationshipField: node.relationshipField,
                    children: []
                };

                // Recursively add selected children
                if (node.children && node.children.length > 0) {
                    config.children = this.buildConfigFromNodes(node.children);
                }

                configs.push(config);
            }
        }

        return configs;
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
     * Launch extraction and download CSV directly
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
            console.log('🚀 Starting direct extraction...');
            console.log('📋 Child configs:', this.selectedChildrenConfig);

            const result = await extractCSVDirect({
                masterObject: this.selectedMasterObject,
                ids: this.parsedIds,
                childConfigs: this.selectedChildrenConfig.length > 0 ? this.selectedChildrenConfig : null
            });

            if (result.success) {
                console.log('✅ Extraction successful:', result.csvFiles.length + ' CSV files');

                this.extractionResult = result;
                this.extractionComplete = true;

                let totalRecords = result.masterRecordCount;
                result.csvFiles.forEach(file => {
                    if (file.level > 0) totalRecords += file.recordCount;
                });

                this.showToast('Success',
                    `Extracted ${result.csvFiles.length} CSV file(s) with ${totalRecords} total records`,
                    'success');

                // Download all CSV files
                result.csvFiles.forEach((file, index) => {
                    setTimeout(() => {
                        this.downloadCSV(file.csvContent, `${file.objectName}.csv`);
                    }, index * 500); // Stagger downloads
                });

            } else {
                this.showToast('Error', result.message, 'error');
            }

        } catch (error) {
            console.error('❌ Error during extraction:', error);
            const errorMessage = error.body ? error.body.message : error.message;
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
        this.detectedMasterObject = '';
        this.detectedMasterObjectLabel = '';
        this.selectedMasterObject = '';
        this.childSelectionTree = [];
        this.selectedChildrenConfig = [];
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

    get detectedObjectText() {
        return this.detectedMasterObjectLabel ?
            `Auto-detected: ${this.detectedMasterObjectLabel}` : '';
    }

    get hasChildObjects() {
        return this.childSelectionTree && this.childSelectionTree.length > 0;
    }

    get selectedChildrenCount() {
        return this.selectedChildrenConfig ? this.selectedChildrenConfig.length : 0;
    }

    get extractionSummary() {
        if (!this.extractionResult || !this.extractionResult.csvFiles) return '';

        const fileCount = this.extractionResult.csvFiles.length;
        let totalRecords = 0;
        this.extractionResult.csvFiles.forEach(file => {
            totalRecords += file.recordCount;
        });

        return `${fileCount} CSV file(s) with ${totalRecords} total records`;
    }

    /**
     * Flatten tree for template iteration
     */
    get flattenedTree() {
        return this.flattenNodes(this.childSelectionTree, 0);
    }

    flattenNodes(nodes, indent) {
        let result = [];

        for (let node of nodes) {
            result.push({
                ...node,
                indent: indent,
                indentStyle: `padding-left: ${indent * 20}px`
            });

            if (node.isExpanded && node.children && node.children.length > 0) {
                result = result.concat(this.flattenNodes(node.children, indent + 1));
            }
        }

        return result;
    }
}
