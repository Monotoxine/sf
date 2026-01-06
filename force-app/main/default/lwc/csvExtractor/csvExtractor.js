import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getExtractableObjects from '@salesforce/apex/CSVExtractionController.getExtractableObjects';
import getAllObjects from '@salesforce/apex/CSVExtractionController.getAllObjects';
import getChildObjects from '@salesforce/apex/CSVExtractionController.getChildObjects';
import extractCSVDirect from '@salesforce/apex/CSVExtractionController.extractCSVDirect';
import parseCSVFile from '@salesforce/apex/CSVExtractionController.parseCSVFile';

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

    // Multi-level Child Selection
    @track childSelectionTree = []; 
    @track selectedChildrenConfig = []; 

    // Extraction State
    @track isExtracting = false;
    @track extractionComplete = false;
    @track extractionResult = null;

    /**
     * Wire to get Master objects
     */
    @wire(getExtractableObjects)
    wiredMasterObjects({ error, data }) {
        if (data) {
            this.masterObjects = data;
        } else if (error) {
            this.showToast('Error', 'Failed to load objects', 'error');
        }
    }

    /**
     * Handle file upload
     */
    handleFileUpload(event) {
        const file = event.target.files[0];
        if (!file) return;

        if (!file.name.endsWith('.csv')) {
            this.showToast('Error', 'Please upload a CSV file', 'error');
            return;
        }

        this.uploadedFileName = file.name;

        const reader = new FileReader();
        reader.onload = () => {
            const base64 = reader.result.split(',')[1];
            this.uploadedFileData = base64;
            this.parseCSV(); // Auto-trigger parse
        };
        reader.onerror = () => {
            this.showToast('Error', 'Failed to read file', 'error');
        };
        reader.readAsDataURL(file);
    }

    /**
     * Parse CSV file (Updated for DataMigrationId logic)
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
                
                // RESET Master Object - User MUST select it manually now
                this.selectedMasterObject = '';
                
                this.showToast('Success', result.message, 'success');
                
                // Auto-advance to Step 2 to prompt selection
                this.currentStep = 2; 
            } else {
                this.showToast('Error', result.message, 'error');
                // Reset file input if valid ID column not found
                this.parsedIds = [];
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

            // Create Node Object with icon property
            const mapNodes = (children) => {
                return children.map(child => ({
                    ...child,
                    id: this.generateId(),
                    level: level,
                    isSelected: false,
                    isExpanded: false,
                    // Pre-calculate icon:
                    chevronIcon: 'utility:chevronright', 
                    children: [],
                    hasLoadedChildren: false,
                    parentNodeId: parentNode ? parentNode.id : null
                }));
            };

            if (!parentNode) {
                // Root level
                this.childSelectionTree = mapNodes(childObjects);
            } else {
                // Nested level
                parentNode.children = mapNodes(childObjects);
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

    generateId() {
        return 'node_' + Math.random().toString(36).substr(2, 9) + '_' + Date.now();
    }

    handleChildToggle(event) {
        const nodeId = event.currentTarget.dataset.nodeId;
        const node = this.findNodeById(nodeId, this.childSelectionTree);

        if (node) {
            node.isSelected = !node.isSelected;
            this.childSelectionTree = [...this.childSelectionTree];
            this.buildChildExtractionConfig();
        }
    }

    async handleExpandNode(event) {
        const nodeId = event.currentTarget.dataset.nodeId;
        const node = this.findNodeById(nodeId, this.childSelectionTree);

        if (node) {
            node.isExpanded = !node.isExpanded;
            // Update icon dynamically
            node.chevronIcon = node.isExpanded ? 'utility:chevrondown' : 'utility:chevronright';

            if (node.isExpanded && !node.hasLoadedChildren) {
                await this.loadChildObjectsForParent(node.objectName, node, node.level + 1);
            }

            this.childSelectionTree = [...this.childSelectionTree];
        }
    }

    findNodeById(nodeId, nodes) {
        for (let node of nodes) {
            if (node.id === nodeId) return node;
            if (node.children && node.children.length > 0) {
                const found = this.findNodeById(nodeId, node.children);
                if (found) return found;
            }
        }
        return null;
    }

    buildChildExtractionConfig() {
        this.selectedChildrenConfig = this.buildConfigFromNodes(this.childSelectionTree);
    }

    buildConfigFromNodes(nodes) {
        const configs = [];
        for (let node of nodes) {
            if (node.isSelected) {
                const config = {
                    childObject: node.objectName,
                    relationshipField: node.relationshipField,
                    children: []
                };
                if (node.children && node.children.length > 0) {
                    config.children = this.buildConfigFromNodes(node.children);
                }
                configs.push(config);
            }
        }
        return configs;
    }

    handleNext() {
        if (this.currentStep === 1) {
            if (!this.parsedIds || this.parsedIds.length === 0) {
                this.showToast('Error', 'Please upload a valid CSV file first', 'error');
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

    handlePrevious() {
        this.currentStep--;
    }

    async handleDownload() {
        // Validation
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
            console.log('🚀 Starting extraction...');
            console.log('📊 Master Object:', this.selectedMasterObject);
            console.log('📊 Selected Children Config:', this.selectedChildrenConfig);

            // Build child extraction config before calling Apex
            this.buildChildExtractionConfig();

            const result = await extractCSVDirect({
                masterObject: this.selectedMasterObject,
                ids: this.parsedIds,
                childConfigs: this.selectedChildrenConfig.length > 0 ? this.selectedChildrenConfig : null
            });

            if (result.success) {
                console.log('✅ Extraction successful:', result.csvFiles.length, 'file(s)');

                this.extractionResult = result;
                this.extractionComplete = true;

                // Download each generated CSV file
                result.csvFiles.forEach((file, index) => {
                    setTimeout(() => {
                        this.downloadCSVFile(file.csvContent, file.objectName + '_Export.csv');
                    }, index * 500);
                });

                this.showToast('Success', 'Data extracted and downloaded successfully', 'success');
            } else {
                console.error('❌ Extraction failed:', result.message);
                this.showToast('Error', result.message, 'error');
            }

        } catch (error) {
            console.error('❌ Technical error:', error);
            const errorMessage = error.body && error.body.message ? error.body.message : 'Unknown error occurred';
            this.showToast('Error', 'Failed to extract data: ' + errorMessage, 'error');
        } finally {
            this.isLoading = false;
            this.isExtracting = false;
        }
    }

    downloadCSVFile(csvContent, fileName) {
    // Création d'un élément invisible <a> pour simuler le clic
    let element = document.createElement('a');
    
    // Ajout du BOM (Byte Order Mark) pour qu'Excel ouvre bien les accents (UTF-8)
    const BOM = '\uFEFF'; 
    
    element.setAttribute('href', 'data:text/csv;charset=utf-8,' + encodeURIComponent(BOM + csvContent));
    element.setAttribute('download', fileName);

    element.style.display = 'none';
    document.body.appendChild(element);

    element.click();

    document.body.removeChild(element);
    }

    handleReset() {
        this.currentStep = 1;
        this.uploadedFileName = '';
        this.uploadedFileData = '';
        this.parsedIds = [];
        this.selectedMasterObject = '';
        this.childSelectionTree = [];
        this.selectedChildrenConfig = [];
        this.extractionComplete = false;
        this.extractionResult = null;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // Getters
    get isStep1() { return this.currentStep === 1; }
    get isStep2() { return this.currentStep === 2; }
    get isStep3() { return this.currentStep === 3; }
    get canProceedStep1() { return !(this.parsedIds && this.parsedIds.length > 0); }
    get canProceedStep2() { return !this.selectedMasterObject; }
    get canLaunchExtraction() { return !this.selectedMasterObject || !this.parsedIds.length; }
    get idCountText() { return this.parsedIds ? `${this.parsedIds.length} DataMigration IDs loaded` : ''; }
    get hasChildObjects() { return this.childSelectionTree && this.childSelectionTree.length > 0; }
    get selectedChildrenCount() { return this.selectedChildrenConfig ? this.selectedChildrenConfig.length : 0; }
    
    get extractionSummary() {
        if (!this.extractionResult?.csvFiles) return '';
        const fileCount = this.extractionResult.csvFiles.length;
        let totalRecords = 0;
        this.extractionResult.csvFiles.forEach(file => totalRecords += file.recordCount);
        return `${fileCount} CSV file(s) with ${totalRecords} total records`;
    }

    get flattenedTree() {
        return this.flattenNodes(this.childSelectionTree, 0);
    }

    flattenNodes(nodes, indent) {
        let result = [];
        for (let node of nodes) {
            result.push({
                ...node,
                indentStyle: `padding-left: ${indent * 20}px`
            });
            if (node.isExpanded && node.children?.length > 0) {
                result = result.concat(this.flattenNodes(node.children, indent + 1));
            }
        }
        return result;
    }
}
