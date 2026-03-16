import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// Apex methods
import isSandbox        from '@salesforce/apex/DataAnonymizationController.isSandbox';
import hasPermission    from '@salesforce/apex/DataAnonymizationController.hasPermission';
import getObjectConfigs from '@salesforce/apex/DataAnonymizationController.getObjectConfigs';
import getFieldConfigs  from '@salesforce/apex/DataAnonymizationController.getFieldConfigs';
import getBrandValues   from '@salesforce/apex/DataAnonymizationController.getBrandValues';
import previewAnonymization from '@salesforce/apex/DataAnonymizationController.previewAnonymization';
import launchAnonymization  from '@salesforce/apex/DataAnonymizationController.launchAnonymization';
import getRecentRuns        from '@salesforce/apex/DataAnonymizationController.getRecentRuns';
import getRunsByGroupId     from '@salesforce/apex/DataAnonymizationController.getRunsByGroupId';

// ── Preview table columns ──────────────────────────────────────────────────────
const PREVIEW_COLUMNS = [
    { label: 'Object',          fieldName: 'objectLabel',   type: 'text' },
    { label: 'Records Affected', fieldName: 'recordCount',  type: 'number',
      cellAttributes: { alignment: 'left' } },
    { label: 'Fields to Anonymize', fieldName: 'fieldCount', type: 'number',
      cellAttributes: { alignment: 'left' } }
];

// ── History table columns ──────────────────────────────────────────────────────
const HISTORY_COLUMNS = [
    { label: 'Name',        fieldName: 'Name',              type: 'text', initialWidth: 120 },
    { label: 'Object',      fieldName: 'Object_API_Name__c', type: 'text' },
    { label: 'Status',      fieldName: 'Status__c',         type: 'text', initialWidth: 100,
      cellAttributes: { class: { fieldName: 'statusClass' } } },
    { label: 'Records OK',  fieldName: 'Records_Processed__c', type: 'number', initialWidth: 110,
      cellAttributes: { alignment: 'left' } },
    { label: 'Records Failed', fieldName: 'Records_Failed__c', type: 'number', initialWidth: 120,
      cellAttributes: { alignment: 'left' } },
    { label: 'Brand Filter', fieldName: 'Brand_Filter__c',  type: 'text', initialWidth: 120 },
    { label: 'Run Date',    fieldName: 'Run_Date__c',       type: 'date',
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit',
                        hour: '2-digit', minute: '2-digit' } },
    { label: 'Completed',   fieldName: 'Completion_Date__c', type: 'date',
      typeAttributes: { year: 'numeric', month: 'short', day: '2-digit',
                        hour: '2-digit', minute: '2-digit' } }
];

const POLL_INTERVAL_MS = 5000; // poll run status every 5 seconds while running

export default class DataAnonymizationManager extends LightningElement {

    // ── Environment & access ───────────────────────────────────────────────────
    @track isSandboxOrg     = null; // null = loading
    @track hasAdminPerm     = null;

    get isAccessDenied()   { return this.hasAdminPerm === false; }
    get isProductionOrg()  { return this.isSandboxOrg === false && this.hasAdminPerm !== false; }

    // ── Filter state ───────────────────────────────────────────────────────────
    @track selectedBrand    = '';
    @track brandOptions     = [];
    @track hasBrandOptions  = false;

    @track objectOptions    = []; // [{value, label, checked, checkboxId}]
    @track isLoadingObjects = false;
    @track fieldOptions     = []; // [{value, label, fieldLabel, fieldType, objectConfigName, checked, checkboxId}]

    get noObjectsAvailable() { return !this.isLoadingObjects && this.objectOptions.length === 0; }
    get noFieldsAvailable()  { return this.fieldOptions.length === 0; }

    get selectedObjectNames() {
        return this.objectOptions
            .filter(o => o.checked)
            .map(o => o.value);
    }
    get selectedFieldKeys() {
        return this.fieldOptions
            .filter(f => f.checked)
            .map(f => f.value);
    }
    get selectedObjectCount() { return this.selectedObjectNames.length; }
    get selectedFieldCount()  { return this.selectedFieldKeys.length; }

    // ── Preview state ──────────────────────────────────────────────────────────
    @track showPreview      = false;
    @track isLoadingPreview = false;
    @track previewData      = [];
    previewColumns          = PREVIEW_COLUMNS;

    get previewTotalRecords() {
        if (!this.previewData.length) return 0;
        return this.previewData.reduce((sum, e) => sum + (e.recordCount || 0), 0);
    }

    get isPreviewDisabled() {
        return this.selectedObjectNames.length === 0;
    }

    // ── Launch state ───────────────────────────────────────────────────────────
    @track showConfirmModal   = false;
    @track isRunning          = false;
    @track currentRunGroupId  = null;
    _pollTimer                = null;

    get isLaunchDisabled() {
        return this.selectedObjectNames.length === 0 || this.isRunning;
    }

    // ── History state ──────────────────────────────────────────────────────────
    @track runHistory         = [];
    @track isLoadingHistory   = false;
    historyColumns            = HISTORY_COLUMNS;
    get hasRunHistory() { return this.runHistory.length > 0; }

    // ── Toast state ────────────────────────────────────────────────────────────
    @track toastMessage = null;
    @track toastVariant = 'success';
    get toastClass() {
        return `slds-notify slds-notify_toast slds-theme_${this.toastVariant} da-toast`;
    }
    get toastIcon() {
        return this.toastVariant === 'error' ? 'utility:error'
             : this.toastVariant === 'warning' ? 'utility:warning'
             : 'utility:success';
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    connectedCallback() {
        this._initEnvironment();
    }

    disconnectedCallback() {
        this._clearPollTimer();
    }

    async _initEnvironment() {
        try {
            const [sandbox, perm] = await Promise.all([isSandbox(), hasPermission()]);
            this.isSandboxOrg = sandbox;
            this.hasAdminPerm = perm;

            if (perm && sandbox) {
                await Promise.all([
                    this._loadObjectConfigs(),
                    this._loadBrandValues(),
                    this._loadHistory()
                ]);
            }
        } catch (e) {
            this._showError('Initialization failed: ' + this._extractError(e));
        }
    }

    // ── Data loaders ───────────────────────────────────────────────────────────

    async _loadObjectConfigs() {
        this.isLoadingObjects = true;
        try {
            const configs = await getObjectConfigs();
            this.objectOptions = (configs || []).map(cfg => ({
                value:      cfg.developerName,
                label:      cfg.objectLabel,
                checked:    false,
                checkboxId: 'obj_' + cfg.developerName
            }));
        } catch (e) {
            this._showError('Failed to load object configs: ' + this._extractError(e));
        } finally {
            this.isLoadingObjects = false;
        }
    }

    async _loadBrandValues() {
        try {
            const brands = await getBrandValues();
            if (brands && brands.length > 0) {
                this.brandOptions = [
                    { label: '— All brands —', value: '' },
                    ...brands.map(b => ({ label: b, value: b }))
                ];
                this.hasBrandOptions = true;
            } else {
                this.hasBrandOptions = false;
            }
        } catch (e) {
            this.hasBrandOptions = false; // fall back to text input silently
        }
    }

    async _loadFieldConfigs(objectConfigNames) {
        if (!objectConfigNames || objectConfigNames.length === 0) {
            this.fieldOptions = [];
            return;
        }
        try {
            const fields = await getFieldConfigs({ objectConfigNames });
            this.fieldOptions = (fields || []).map(fc => ({
                value:            fc.developerName,
                label:            fc.fieldLabel + ' (' + fc.fieldApiName + ')',
                fieldLabel:       fc.fieldLabel || fc.fieldApiName,
                fieldApiName:     fc.fieldApiName,
                fieldType:        fc.fieldType || fc.strategyClassName,
                objectConfigName: fc.objectConfigName,
                checked:          true, // default: all fields selected
                checkboxId:       'fld_' + fc.developerName
            }));
        } catch (e) {
            this._showError('Failed to load field configs: ' + this._extractError(e));
        }
    }

    async _loadHistory() {
        this.isLoadingHistory = true;
        try {
            const runs = await getRecentRuns();
            this.runHistory = (runs || []).map(r => ({
                ...r,
                statusClass: this._statusClass(r.Status__c)
            }));
        } catch (e) {
            // non-critical — silent fail
        } finally {
            this.isLoadingHistory = false;
        }
    }

    // ── Event handlers ─────────────────────────────────────────────────────────

    handleBrandChange(event) {
        this.selectedBrand = event.detail.value;
        // Reset preview when filters change
        this.showPreview = false;
    }

    handleObjectToggle(event) {
        const value   = event.target.value;
        const checked = event.target.checked;
        this.objectOptions = this.objectOptions.map(o =>
            o.value === value ? { ...o, checked } : o
        );
        this.showPreview = false;
        // Reload field configs for selected objects
        this._loadFieldConfigs(this.selectedObjectNames);
    }

    handleFieldToggle(event) {
        const value   = event.target.value;
        const checked = event.target.checked;
        this.fieldOptions = this.fieldOptions.map(f =>
            f.value === value ? { ...f, checked } : f
        );
    }

    handleSelectAllFields() {
        this.fieldOptions = this.fieldOptions.map(f => ({ ...f, checked: true }));
    }

    async handlePreview() {
        if (this.selectedObjectNames.length === 0) return;

        this.isLoadingPreview = true;
        this.showPreview      = true;
        this.previewData      = [];

        try {
            const entries = await previewAnonymization({
                objectConfigNames: this.selectedObjectNames,
                brandFilter:       this.selectedBrand || null
            });
            this.previewData = (entries || []).map(e => ({
                ...e,
                recordCount: e.recordCount < 0 ? 'N/A' : e.recordCount
            }));
        } catch (e) {
            this._showError('Preview failed: ' + this._extractError(e));
            this.showPreview = false;
        } finally {
            this.isLoadingPreview = false;
        }
    }

    handleLaunchConfirmOpen()  { this.showConfirmModal = true;  }
    handleLaunchConfirmClose() { this.showConfirmModal = false; }

    async handleLaunch() {
        this.showConfirmModal = false;
        this.isRunning        = true;
        this.toastMessage     = null;

        try {
            const runGroupId = await launchAnonymization({
                objectConfigNames: this.selectedObjectNames,
                brandFilter:       this.selectedBrand || null
            });
            this.currentRunGroupId = runGroupId;
            this._showSuccess('Anonymization started. Run Group ID: ' + runGroupId);
            this._startPolling();
            this._loadHistory();
        } catch (e) {
            this.isRunning = false;
            this._showError('Launch failed: ' + this._extractError(e));
        }
    }

    handleRefreshStatus() {
        this._pollRunStatus();
    }

    handleRefreshHistory() {
        this._loadHistory();
    }

    handleDismissToast() {
        this.toastMessage = null;
    }

    // ── Status polling ─────────────────────────────────────────────────────────

    _startPolling() {
        this._clearPollTimer();
        this._pollTimer = setInterval(() => this._pollRunStatus(), POLL_INTERVAL_MS);
    }

    _clearPollTimer() {
        if (this._pollTimer) {
            clearInterval(this._pollTimer);
            this._pollTimer = null;
        }
    }

    async _pollRunStatus() {
        if (!this.currentRunGroupId) return;
        try {
            const logs = await getRunsByGroupId({ runGroupId: this.currentRunGroupId });
            const allDone = (logs || []).every(
                l => l.Status__c === 'Success' || l.Status__c === 'Partial' || l.Status__c === 'Failed'
            );
            if (allDone) {
                this.isRunning = false;
                this._clearPollTimer();
                this._loadHistory();
                const hasErrors = (logs || []).some(l => l.Status__c !== 'Success');
                if (hasErrors) {
                    this._showWarning('Anonymization completed with some errors. Check the Run History.');
                } else {
                    this._showSuccess('Anonymization completed successfully.');
                }
            }
        } catch (e) {
            // polling error — non-critical, keep polling
        }
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    _showSuccess(msg) { this.toastMessage = msg; this.toastVariant = 'success'; }
    _showError(msg)   { this.toastMessage = msg; this.toastVariant = 'error'; }
    _showWarning(msg) { this.toastMessage = msg; this.toastVariant = 'warning'; }

    _extractError(e) {
        return (e && e.body && e.body.message) ? e.body.message
             : (e && e.message) ? e.message
             : JSON.stringify(e);
    }

    _statusClass(status) {
        if (status === 'Success') return 'slds-text-color_success';
        if (status === 'Failed')  return 'slds-text-color_error';
        if (status === 'Partial') return 'slds-text-color_warning';
        return '';
    }
}
