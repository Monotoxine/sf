import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasAnonymizePermission from '@salesforce/customPermission/TEKCO_AnonymizeData';

import getBrands          from '@salesforce/apex/TEKCO_AnonymizationController.getBrands';
import getObjects         from '@salesforce/apex/TEKCO_AnonymizationController.getObjects';
import getRecordTypes     from '@salesforce/apex/TEKCO_AnonymizationController.getRecordTypes';
import getFieldConfigs    from '@salesforce/apex/TEKCO_AnonymizationController.getFieldConfigs';
import getPreviewCounts   from '@salesforce/apex/TEKCO_AnonymizationController.getPreviewCounts';
import getAuditLogs       from '@salesforce/apex/TEKCO_AnonymizationController.getAuditLogs';
import startAnonymization from '@salesforce/apex/TEKCO_AnonymizationController.startAnonymization';

import resolveIds              from '@salesforce/apex/TEKCO_AnonymizationByIdController.resolveIds';
import startAnonymizationByIds from '@salesforce/apex/TEKCO_AnonymizationByIdController.startAnonymizationByIds';
import getAuditLogsByid        from '@salesforce/apex/TEKCO_AnonymizationByIdController.getAuditLogsByid';

const AUDIT_POLL_INTERVAL_MS = 5000;

export default class TekcoDataAnonymizationAdmin extends LightningElement {

    hasPermission = hasAnonymizePermission;

    @track selectedBrands      = [];
    @track selectedObjects     = [];
    @track selectedRecordTypes = [];

    @track brandOptions      = [];
    @track objectOptions     = [];
    @track recordTypeOptions = [];

    @track fieldConfigs    = [];
    @track previewByObject = [];
    @track auditLogs       = [];

    @track isLoading        = false;
    @track isLoadingPreview = false;
    @track isRunning        = false;
    @track errorMessage     = '';
    @track previewNote      = null;

    @track showConfirmPanel    = false;
    @track confirmSummaryLines = [];

    // ── By ID tab state ───────────────────────────────────────────────────────
    @track byIdRawInput           = '';
    @track byIdResolveResult      = null;
    @track isByIdResolving        = false;
    @track isByIdRunning          = false;
    @track showByIdConfirmPanel   = false;
    @track byIdConfirmSummaryLines = [];
    @track byIdAuditLogs          = [];
    @track byIdErrorMessage       = '';

    _pendingExcludedFields        = [];
    _pendingDisabledHistoryFields = [];
    _auditTimer   = null;
    _byIdAuditTimer = null;

    connectedCallback() {
        this.loadBrands();
        this.loadObjects();
        this.loadRecordTypes([]);
        this.loadAuditLogs();
        this.loadByIdAuditLogs();
    }

    disconnectedCallback() {
        this.stopAuditPoll();
        this.stopByIdAuditPoll();
    }

    loadBrands() {
        getBrands()
            .then(options => {
                this.brandOptions = options.map(o => ({ label: o.label, value: o.value }));
            })
            .catch(err => this.showError('Failed to load brands', err));
    }

    loadObjects() {
        getObjects()
            .then(options => {
                this.objectOptions = options;
            })
            .catch(err => this.showError('Failed to load objects', err));
    }

    loadRecordTypes(selectedObjects) {
        getRecordTypes({ selectedObjects: selectedObjects || [] })
            .then(options => {
                this.recordTypeOptions = options.map(o => ({ label: o.label, value: o.value }));
                const available = new Set(options.map(o => o.value));
                this.selectedRecordTypes = this.selectedRecordTypes.filter(rt => available.has(rt));
            })
            .catch(err => this.showError('Failed to load record types', err));
    }

    loadFieldConfigs() {
        this.isLoading = true;
        getFieldConfigs({ selectedObjects: this.selectedObjects.length > 0 ? this.selectedObjects : null })
            .then(configs => {
                // Enrich each config with a unique key and enabled=true by default
                this.fieldConfigs = configs.map(cfg => ({
                    ...cfg,
                    configKey:             `${cfg.objectApiName}.${cfg.fieldApiName}.${cfg.recordTypeDeveloperName || ''}`,
                    enabled:               true,
                    originalDeleteHistory: cfg.deleteHistory,
                    isContentDoc:          cfg.patternType === 'DELETE_CONTENT_DOCUMENT'
                }));
                this.isLoading = false;
            })
            .catch(err => {
                this.showError('Failed to load field configs', err);
                this.isLoading = false;
            });
    }

    loadPreview() {
        this.isLoadingPreview = true;
        this.previewByObject  = [];
        this.previewNote = this.selectedObjects.length > 0
            ? null
            : 'No object selected — all configured objects will be included.';

        getPreviewCounts({
            selectedBrands:      this.selectedBrands,
            selectedObjects:     this.selectedObjects.length > 0 ? this.selectedObjects : null,
            selectedRecordTypes: this.selectedRecordTypes.length > 0 ? this.selectedRecordTypes : null
        })
        .then(results => {
            this.previewByObject = results.map(({ objectApiName, count, isContentDocOnly }) => ({
                objectApiName,
                isContentDocOnly,
                countLabel: count === -1
                    ? 'Could not count'
                    : isContentDocOnly
                        ? `${count} record(s) (ContentDocumentLinks to delete)`
                        : `${count} record(s)`
            }));
            this.isLoadingPreview = false;
        })
        .catch(() => {
            this.isLoadingPreview = false;
        });
    }

    loadAuditLogs() {
        getAuditLogs()
            .then(logs => {
                this.auditLogs = logs.map(log => ({
                    ...log,
                    statusClass: this.computeStatusBadgeClass(log.TEKCO_Status__c),
                    startFormatted: log.TEKCO_StartTime__c
                        ? new Date(log.TEKCO_StartTime__c).toLocaleString()
                        : '—'
                }));
            })
            .catch(() => {});
    }

    handleBrandChange(event) {
        this.selectedBrands = event.detail.value;
    }

    handleObjectChange(event) {
        this.selectedObjects = event.detail.value;
        this.fieldConfigs    = [];
        this.previewByObject = [];
        this.previewNote     = null;
        this.loadRecordTypes(this.selectedObjects);
    }

    handleRecordTypeChange(event) {
        this.selectedRecordTypes = event.detail.value;
        this.fieldConfigs        = [];
        this.previewByObject     = [];
    }

    handleSelectAllBrands() {
        this.selectedBrands = this.brandOptions.map(o => o.value);
    }

    handleSelectAllObjects() {
        this.selectedObjects = this.objectOptions.map(o => o.value);
        this.loadRecordTypes(this.selectedObjects);
    }

    handleSelectAllRecordTypes() {
        this.selectedRecordTypes = this.recordTypeOptions.map(o => o.value);
    }

    handlePreview() {
        this.loadFieldConfigs();
        this.loadPreview();
    }

    /**
     * Toggles the `enabled` flag on a field config row.
     * The checkbox data-key attribute carries "ObjectApiName.FieldApiName".
     */
    handleFieldToggle(event) {
        const configKey = event.target.dataset.key;
        this.fieldConfigs = this.fieldConfigs.map(cfg =>
            cfg.configKey === configKey ? { ...cfg, enabled: event.target.checked } : cfg
        );
    }

    /**
     * Toggles the `deleteHistory` flag on a field config row.
     * Only meaningful for rows where originalDeleteHistory is true.
     */
    handleDeleteHistoryToggle(event) {
        const configKey = event.target.dataset.key;
        this.fieldConfigs = this.fieldConfigs.map(cfg =>
            cfg.configKey === configKey ? { ...cfg, deleteHistory: event.target.checked } : cfg
        );
    }

    /**
     * Prepares the confirmation summary and opens the modal.
     */
    handleStart() {
        if (!this.hasPermission) {
            this.showToast('Permission Denied', 'You need the "TEKCO Anonymize Data" custom permission.', 'error');
            return;
        }

        this._pendingExcludedFields = this.fieldConfigs
            .filter(cfg => !cfg.enabled)
            .map(cfg => cfg.configKey);

        // Only fields that had history enabled in CMT but were unchecked by the user
        this._pendingDisabledHistoryFields = this.fieldConfigs
            .filter(cfg => cfg.originalDeleteHistory && !cfg.deleteHistory)
            .map(cfg => cfg.configKey);

        this.confirmSummaryLines = [
            {
                key:   'brands',
                label: 'Brands',
                value: this.selectedBrands.length
                    ? this.selectedBrands.join(', ') : 'ALL'
            },
            {
                key:   'objects',
                label: 'Objects',
                value: this.selectedObjects.length
                    ? this.selectedObjects.join(', ') : 'All configured objects'
            },
            {
                key:   'recordTypes',
                label: 'Record Types',
                value: this.selectedRecordTypes.length
                    ? this.selectedRecordTypes.join(', ') : 'All'
            },
            {
                key:   'excluded',
                label: 'Excluded Fields',
                value: this._pendingExcludedFields.length
                    ? this._pendingExcludedFields.join(', ') : 'none'
            },
            {
                key:   'history',
                label: 'History Disabled',
                value: this._pendingDisabledHistoryFields.length
                    ? this._pendingDisabledHistoryFields.join(', ') : 'none'
            }
        ];

        this.showConfirmPanel = true;
    }

    handleCancelLaunch() {
        this.showConfirmPanel = false;
    }

    handleConfirmLaunch() {
        this.showConfirmPanel = false;
        this.isRunning        = true;
        this.errorMessage     = '';

        startAnonymization({
            selectedBrands:        this.selectedBrands,
            selectedObjects:       this.selectedObjects.length > 0 ? this.selectedObjects : null,
            excludedFields:        this._pendingExcludedFields.length > 0 ? this._pendingExcludedFields : null,
            selectedRecordTypes:   this.selectedRecordTypes.length > 0 ? this.selectedRecordTypes : null,
            disabledHistoryFields: this._pendingDisabledHistoryFields.length > 0 ? this._pendingDisabledHistoryFields : null
        })
        .then(auditLogId => {
            this.isRunning = false;
            this.showToast('Anonymization Started', `Audit log: ${auditLogId}`, 'success');
            this.startAuditPoll();
        })
        .catch(err => {
            this.isRunning    = false;
            const errorMessage = err?.body?.message ?? err?.message ?? 'Unknown error';
            this.errorMessage = errorMessage;
            this.showToast('Error', errorMessage, 'error');
        });
    }

    handleSelectAllRun() {
        this.fieldConfigs = this.fieldConfigs.map(cfg => ({ ...cfg, enabled: true }));
    }

    handleDeselectAllRun() {
        this.fieldConfigs = this.fieldConfigs.map(cfg => ({ ...cfg, enabled: false }));
    }

    handleSelectAllHistory() {
        this.fieldConfigs = this.fieldConfigs.map(cfg =>
            cfg.originalDeleteHistory ? { ...cfg, deleteHistory: true } : cfg
        );
    }

    handleDeselectAllHistory() {
        this.fieldConfigs = this.fieldConfigs.map(cfg => ({ ...cfg, deleteHistory: false }));
    }

    handleRefreshLogs() {
        this.loadAuditLogs();
    }

    startAuditPoll() {
        this._auditTimer = setInterval(() => {
            this.loadAuditLogs();
            if (!this.auditLogs.some(log => log.TEKCO_Status__c === 'Running')) {
                this.stopAuditPoll();
            }
        }, AUDIT_POLL_INTERVAL_MS);
    }

    stopAuditPoll() {
        if (this._auditTimer) {
            clearInterval(this._auditTimer);
            this._auditTimer = null;
        }
    }

    // ── By ID handlers ────────────────────────────────────────────────────────

    handleByIdInputChange(event) {
        this.byIdRawInput      = event.target.value;
        this.byIdResolveResult = null;
        this.byIdErrorMessage  = '';
    }

    handleByIdResolve() {
        const ids = this._parseByIdInput();
        if (!ids.length) return;
        this.isByIdResolving   = true;
        this.byIdResolveResult = null;
        this.byIdErrorMessage  = '';
        resolveIds({ rawIds: ids })
            .then(result => {
                this.byIdResolveResult = result;
                this.isByIdResolving   = false;
            })
            .catch(err => {
                this.byIdErrorMessage = err?.body?.message ?? err?.message ?? 'Unknown error';
                this.isByIdResolving  = false;
            });
    }

    handleByIdLaunch() {
        if (!this.hasPermission) {
            this.showToast('Permission Denied', 'You need the "TEKCO Anonymize Data" custom permission.', 'error');
            return;
        }
        const result = this.byIdResolveResult;
        const directSummary = result && result.directObjects && result.directObjects.length
            ? result.directObjects.map(o => `${o.objectApiName} (${o.recordCount})`).join(', ')
            : '—';
        const childSummary  = result && result.childObjects && result.childObjects.length
            ? result.childObjects.map(o => `${o.objectApiName} (${o.recordCount})`).join(', ')
            : '—';
        this.byIdConfirmSummaryLines = [
            { key: 'total',    label: 'Total valid records', value: String(result ? result.totalValid : 0) },
            { key: 'direct',   label: 'Direct objects',      value: directSummary },
            { key: 'children', label: 'Resolved children',   value: childSummary }
        ];
        this.showByIdConfirmPanel = true;
    }

    handleByIdCancelLaunch() {
        this.showByIdConfirmPanel = false;
    }

    handleByIdConfirmLaunch() {
        this.showByIdConfirmPanel = false;
        this.isByIdRunning        = true;
        this.byIdErrorMessage     = '';
        const ids = this._parseByIdInput();
        startAnonymizationByIds({ rawIds: ids })
            .then(auditLogId => {
                this.isByIdRunning = false;
                this.showToast('Anonymization Started', `Audit log: ${auditLogId}`, 'success');
                this.startByIdAuditPoll();
            })
            .catch(err => {
                this.isByIdRunning    = false;
                this.byIdErrorMessage = err?.body?.message ?? err?.message ?? 'Unknown error';
                this.showToast('Error', this.byIdErrorMessage, 'error');
            });
    }

    handleByIdRefreshLogs() {
        this.loadByIdAuditLogs();
    }

    loadByIdAuditLogs() {
        getAuditLogsByid()
            .then(logs => {
                this.byIdAuditLogs = logs.map(log => ({
                    ...log,
                    statusClass:    this.computeStatusBadgeClass(log.TEKCO_Status__c),
                    startFormatted: log.TEKCO_StartTime__c
                        ? new Date(log.TEKCO_StartTime__c).toLocaleString() : '—'
                }));
            })
            .catch(() => {});
    }

    startByIdAuditPoll() {
        this._byIdAuditTimer = setInterval(() => {
            this.loadByIdAuditLogs();
            if (!this.byIdAuditLogs.some(log => log.TEKCO_Status__c === 'Running')) {
                this.stopByIdAuditPoll();
            }
        }, AUDIT_POLL_INTERVAL_MS);
    }

    stopByIdAuditPoll() {
        if (this._byIdAuditTimer) {
            clearInterval(this._byIdAuditTimer);
            this._byIdAuditTimer = null;
        }
    }

    _parseByIdInput() {
        const raw = this.byIdRawInput || '';
        const seen = new Set();
        return raw.split(/[\n,;]+/)
            .map(s => s.trim())
            .filter(s => s.length > 0 && !seen.has(s) && seen.add(s));
    }

    // ── By ID getters ─────────────────────────────────────────────────────────

    get byIdParsedCountLabel() {
        const count = this._parseByIdInput().length;
        return count > 0 ? `${count} ID(s) detected` : 'Paste IDs above';
    }

    get isByIdResolveDisabled() {
        return this._parseByIdInput().length === 0 || this.isByIdResolving;
    }

    get hasByIdResolveResult()  { return !!this.byIdResolveResult; }
    get hasByIdDirectObjects()  { return !!(this.byIdResolveResult && this.byIdResolveResult.directObjects && this.byIdResolveResult.directObjects.length > 0); }
    get hasByIdChildObjects()   { return !!(this.byIdResolveResult && this.byIdResolveResult.childObjects  && this.byIdResolveResult.childObjects.length  > 0); }
    get hasByIdInvalidIds()     { return !!(this.byIdResolveResult && this.byIdResolveResult.invalidIds    && this.byIdResolveResult.invalidIds.length    > 0); }
    get hasByIdAnyValid()       { return !!(this.byIdResolveResult && this.byIdResolveResult.totalValid > 0); }
    get hasByIdAuditLogs()      { return this.byIdAuditLogs.length > 0; }
    get isByIdLaunchDisabled()  { return !this.hasPermission || !this.hasByIdAnyValid || this.isByIdRunning; }
    get byIdLaunchLabel()       { return this.isByIdRunning ? 'Running...' : 'Launch Anonymization'; }

    get hasFieldConfigs()      { return this.fieldConfigs.length > 0; }
    get hasPreview()           { return this.previewByObject.length > 0; }
    get hasAuditLogs()         { return this.auditLogs.length > 0; }
    get hasRecordTypeOptions() { return this.recordTypeOptions.length > 0; }
    get isStartDisabled()      { return !this.hasPermission || this.isRunning; }
    get startLabel()           { return this.isRunning ? 'Running...' : 'Launch Anonymization'; }
    get permissionWarning() {
        return this.hasPermission ? ''
            : 'You need the "TEKCO Anonymize Data" custom permission to trigger anonymization.';
    }

    get fieldConfigsByObject() {
        const groupMap = {};
        this.fieldConfigs.forEach(cfg => {
            if (!groupMap[cfg.objectApiName]) {
                groupMap[cfg.objectApiName] = { objectApiName: cfg.objectApiName, fields: [] };
            }
            groupMap[cfg.objectApiName].fields.push(cfg);
        });
        return Object.values(groupMap);
    }

    computeStatusBadgeClass(status) {
        const statusClassMap = {
            'Success': 'badge badge-success',
            'Running': 'badge badge-running',
            'Partial': 'badge badge-partial',
            'Failed' : 'badge badge-failed'
        };
        return statusClassMap[status] || 'badge';
    }

    showError(context, err) {
        const errorMessage = err?.body?.message ?? err?.message ?? 'Unknown error';
        console.error(`[TekcoAnonymizationAdmin] ${context}:`, errorMessage);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
