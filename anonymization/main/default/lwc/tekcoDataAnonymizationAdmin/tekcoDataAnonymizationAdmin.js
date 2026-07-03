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

import resolveIds                  from '@salesforce/apex/TEKCO_AnonymizationByIdController.resolveIds';
import startAnonymizationByIds     from '@salesforce/apex/TEKCO_AnonymizationByIdController.startAnonymizationByIds';
import getAuditLogsByid            from '@salesforce/apex/TEKCO_AnonymizationByIdController.getAuditLogsByid';
import getExternalIdFieldsForObject from '@salesforce/apex/TEKCO_AnonymizationByIdController.getExternalIdFieldsForObject';
import getDirectObjects              from '@salesforce/apex/TEKCO_AnonymizationByIdController.getDirectObjects';

const AUDIT_POLL_INTERVAL_MS = 5000;

const RESOLVE_MODE_OPTIONS = [
    { label: 'Salesforce ID',  value: 'SF_ID' },
    { label: 'External ID',    value: 'EXTERNAL_ID' }
];

export default class TekcoDataAnonymizationAdmin extends LightningElement {

    hasPermission = hasAnonymizePermission;

    // ── By Criteria state ─────────────────────────────────────────────────────
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

    _pendingExcludedFields        = [];
    _pendingDisabledHistoryFields = [];
    _auditTimer   = null;

    // ── By ID tab state ───────────────────────────────────────────────────────
    @track byIdRawInput              = '';
    @track byIdResolveMode           = 'SF_ID';
    @track byIdTargetObject          = '';
    @track byIdExternalIdField       = '';
    @track byIdExternalIdFieldOptions = [];
    @track byIdDirectObjectOptions   = [];
    @track byIdResolveResult         = null;
    @track byIdFieldConfigs          = [];      // Fields to Anonymize for resolved objects
    @track isByIdResolving           = false;
    @track isByIdRunning             = false;
    @track showByIdConfirmPanel      = false;
    @track byIdConfirmSummaryLines   = [];
    @track byIdAuditLogs             = [];
    @track byIdErrorMessage          = '';

    _byIdAuditTimer = null;

    connectedCallback() {
        this.loadBrands();
        this.loadObjects();
        this.loadRecordTypes([]);
        this.loadAuditLogs();
        this.loadByIdAuditLogs();
        this.loadDirectObjects();
    }

    disconnectedCallback() {
        this.stopAuditPoll();
        this.stopByIdAuditPoll();
    }

    // ── By Criteria loaders ───────────────────────────────────────────────────

    loadBrands() {
        getBrands()
            .then(options => { this.brandOptions = options.map(o => ({ label: o.label, value: o.value })); })
            .catch(err => this.showError('Failed to load brands', err));
    }

    loadObjects() {
        getObjects()
            .then(options => { this.objectOptions = options; })
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
                this.fieldConfigs = configs.map(cfg => ({
                    ...cfg,
                    configKey:             `${cfg.objectApiName}.${cfg.fieldApiName}.${cfg.recordTypeDeveloperName || ''}`,
                    enabled:               true,
                    originalDeleteHistory: cfg.deleteHistory,
                    isContentDoc:          cfg.patternType === 'DELETE_CONTENT_DOCUMENT'
                }));
                this.isLoading = false;
            })
            .catch(err => { this.showError('Failed to load field configs', err); this.isLoading = false; });
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
        .catch(() => { this.isLoadingPreview = false; });
    }

    loadAuditLogs() {
        getAuditLogs()
            .then(logs => {
                this.auditLogs = logs.map(log => ({
                    ...log,
                    statusClass:    this.computeStatusBadgeClass(log.TEKCO_Status__c),
                    startFormatted: log.TEKCO_StartTime__c ? new Date(log.TEKCO_StartTime__c).toLocaleString() : '—'
                }));
            })
            .catch(() => {});
    }

    // ── By Criteria handlers ──────────────────────────────────────────────────

    handleBrandChange(event)      { this.selectedBrands = event.detail.value; }
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
    handleSelectAllBrands()       { this.selectedBrands = this.brandOptions.map(o => o.value); }
    handleSelectAllObjects()      { this.selectedObjects = this.objectOptions.map(o => o.value); this.loadRecordTypes(this.selectedObjects); }
    handleSelectAllRecordTypes()  { this.selectedRecordTypes = this.recordTypeOptions.map(o => o.value); }
    handlePreview()               { this.loadFieldConfigs(); this.loadPreview(); }
    handleSelectAllRun()          { this.fieldConfigs = this.fieldConfigs.map(cfg => ({ ...cfg, enabled: true })); }
    handleDeselectAllRun()        { this.fieldConfigs = this.fieldConfigs.map(cfg => ({ ...cfg, enabled: false })); }
    handleSelectAllHistory()      { this.fieldConfigs = this.fieldConfigs.map(cfg => cfg.originalDeleteHistory ? { ...cfg, deleteHistory: true } : cfg); }
    handleDeselectAllHistory()    { this.fieldConfigs = this.fieldConfigs.map(cfg => ({ ...cfg, deleteHistory: false })); }
    handleRefreshLogs()           { this.loadAuditLogs(); }

    handleFieldToggle(event) {
        const configKey = event.target.dataset.key;
        this.fieldConfigs = this.fieldConfigs.map(cfg =>
            cfg.configKey === configKey ? { ...cfg, enabled: event.target.checked } : cfg
        );
    }

    handleDeleteHistoryToggle(event) {
        const configKey = event.target.dataset.key;
        this.fieldConfigs = this.fieldConfigs.map(cfg =>
            cfg.configKey === configKey ? { ...cfg, deleteHistory: event.target.checked } : cfg
        );
    }

    handleStart() {
        if (!this.hasPermission) {
            this.showToast('Permission Denied', 'You need the "TEKCO Anonymize Data" custom permission.', 'error');
            return;
        }
        this._pendingExcludedFields = this.fieldConfigs.filter(cfg => !cfg.enabled).map(cfg => cfg.configKey);
        this._pendingDisabledHistoryFields = this.fieldConfigs.filter(cfg => cfg.originalDeleteHistory && !cfg.deleteHistory).map(cfg => cfg.configKey);
        this.confirmSummaryLines = [
            { key: 'brands',      label: 'Brands',           value: this.selectedBrands.length ? this.selectedBrands.join(', ') : 'ALL' },
            { key: 'objects',     label: 'Objects',          value: this.selectedObjects.length ? this.selectedObjects.join(', ') : 'All configured objects' },
            { key: 'recordTypes', label: 'Record Types',     value: this.selectedRecordTypes.length ? this.selectedRecordTypes.join(', ') : 'All' },
            { key: 'excluded',    label: 'Excluded Fields',  value: this._pendingExcludedFields.length ? this._pendingExcludedFields.join(', ') : 'none' },
            { key: 'history',     label: 'History Disabled', value: this._pendingDisabledHistoryFields.length ? this._pendingDisabledHistoryFields.join(', ') : 'none' }
        ];
        this.showConfirmPanel = true;
    }

    handleCancelLaunch()  { this.showConfirmPanel = false; }

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
            this.errorMessage = err?.body?.message ?? err?.message ?? 'Unknown error';
            this.showToast('Error', this.errorMessage, 'error');
        });
    }

    startAuditPoll() {
        this._auditTimer = setInterval(() => {
            this.loadAuditLogs();
            if (!this.auditLogs.some(log => log.TEKCO_Status__c === 'Running')) this.stopAuditPoll();
        }, AUDIT_POLL_INTERVAL_MS);
    }

    stopAuditPoll() {
        if (this._auditTimer) { clearInterval(this._auditTimer); this._auditTimer = null; }
    }

    // ── By ID handlers ────────────────────────────────────────────────────────

    handleByIdResolveModeChange(event) {
        this.byIdResolveMode           = event.detail.value;
        this.byIdTargetObject          = '';
        this.byIdExternalIdField       = '';
        this.byIdExternalIdFieldOptions = [];
        this.byIdResolveResult         = null;
        this.byIdFieldConfigs          = [];
        this.byIdErrorMessage          = '';
    }

    handleByIdTargetObjectChange(event) {
        this.byIdTargetObject          = event.detail.value;
        this.byIdExternalIdField       = '';
        this.byIdExternalIdFieldOptions = [];
        this.byIdResolveResult         = null;
        this.byIdFieldConfigs          = [];
        this._loadExternalIdFields();
    }

    handleByIdExternalIdFieldChange(event) {
        this.byIdExternalIdField = event.detail.value;
    }

    _loadExternalIdFields() {
        if (!this.byIdTargetObject) return;
        getExternalIdFieldsForObject({ objectApiName: this.byIdTargetObject })
            .then(fields => {
                this.byIdExternalIdFieldOptions = fields.map(f => ({ label: f, value: f }));
            })
            .catch(() => { this.byIdExternalIdFieldOptions = []; });
    }

    handleByIdInputChange(event) {
        this.byIdRawInput      = event.target.value;
        this.byIdResolveResult = null;
        this.byIdFieldConfigs  = [];
        this.byIdErrorMessage  = '';
    }

    handleByIdResolve() {
        const ids = this._parseByIdInput();
        if (!ids.length) return;
        this.isByIdResolving   = true;
        this.byIdResolveResult = null;
        this.byIdFieldConfigs  = [];
        this.byIdErrorMessage  = '';
        resolveIds({
            rawIds:          ids,
            resolveMode:     this.byIdResolveMode,
            targetObject:    this.byIdTargetObject || null,
            externalIdField: this.byIdExternalIdField || null
        })
            .then(result => {
                this.byIdResolveResult = result;
                this.isByIdResolving   = false;
                if (result.totalValid > 0) this._loadByIdFieldConfigs(result);
            })
            .catch(err => {
                this.byIdErrorMessage = err?.body?.message ?? err?.message ?? 'Unknown error';
                this.isByIdResolving  = false;
            });
    }

    _loadByIdFieldConfigs(resolveResult) {
        const objects = [
            ...(resolveResult.directObjects || []),
            ...(resolveResult.childObjects  || [])
        ].map(o => o.objectApiName);

        if (!objects.length) return;

        getFieldConfigs({ selectedObjects: objects })
            .then(configs => {
                this.byIdFieldConfigs = configs.map(cfg => ({
                    ...cfg,
                    configKey:             `${cfg.objectApiName}.${cfg.fieldApiName}.${cfg.recordTypeDeveloperName || ''}`,
                    enabled:               true,
                    deleteHistory:         cfg.deleteHistory !== false,
                    originalDeleteHistory: cfg.deleteHistory !== false,
                    isContentDoc:          cfg.patternType === 'DELETE_CONTENT_DOCUMENT'
                }));
            })
            .catch(() => { this.byIdFieldConfigs = []; });
    }

    handleByIdFieldToggle(event) {
        const configKey = event.target.dataset.key;
        this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg =>
            cfg.configKey === configKey ? { ...cfg, enabled: event.target.checked } : cfg
        );
    }

    handleByIdSelectAllFields()   { this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg => ({ ...cfg, enabled: true })); }
    handleByIdDeselectAllFields() { this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg => ({ ...cfg, enabled: false })); }
    handleByIdSelectAllHistory()  { this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg => cfg.originalDeleteHistory ? { ...cfg, deleteHistory: true } : cfg); }
    handleByIdDeselectAllHistory(){ this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg => ({ ...cfg, deleteHistory: false })); }

    handleByIdDeleteHistoryToggle(event) {
        const configKey = event.target.dataset.key;
        this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg =>
            cfg.configKey === configKey ? { ...cfg, deleteHistory: event.target.checked } : cfg
        );
    }

    handleByIdLaunch() {
        if (!this.hasPermission) {
            this.showToast('Permission Denied', 'You need the "TEKCO Anonymize Data" custom permission.', 'error');
            return;
        }
        const result = this.byIdResolveResult;
        const directSummary = (result?.directObjects?.length)
            ? result.directObjects.map(o => `${o.objectApiName} (${o.recordCount})`).join(', ') : '—';
        const childSummary = (result?.childObjects?.length)
            ? result.childObjects.map(o => `${o.objectApiName} (${o.recordCount})`).join(', ') : '—';
        const brandSummary = (result?.brands?.length) ? result.brands.join(', ') : '—';
        const excluded = this.byIdFieldConfigs.filter(c => !c.enabled);

        this.byIdConfirmSummaryLines = [
            { key: 'total',    label: 'Total valid records', value: String(result?.totalValid ?? 0) },
            { key: 'brands',   label: 'Brands (detected)',   value: brandSummary },
            { key: 'direct',   label: 'Direct objects',      value: directSummary },
            { key: 'children', label: 'Resolved children',   value: childSummary },
            { key: 'excluded', label: 'Excluded fields',     value: excluded.length ? excluded.map(c => c.fieldApiName).join(', ') : 'none' }
        ];
        this.showByIdConfirmPanel = true;
    }

    handleByIdCancelLaunch() { this.showByIdConfirmPanel = false; }

    handleByIdConfirmLaunch() {
        this.showByIdConfirmPanel = false;
        this.isByIdRunning        = true;
        this.byIdErrorMessage     = '';
        const ids = this._parseByIdInput();
        const excludedFields  = this.byIdFieldConfigs.filter(c => !c.enabled).map(c => c.configKey);
        const noHistoryFields = this.byIdFieldConfigs.filter(c => c.enabled && !c.deleteHistory && !c.isContentDoc).map(c => c.configKey);
        startAnonymizationByIds({
            rawIds:          ids,
            resolveMode:     this.byIdResolveMode,
            targetObject:    this.byIdTargetObject || null,
            externalIdField: this.byIdExternalIdField || null,
            excludedFields:  excludedFields.length  > 0 ? excludedFields  : null,
            noHistoryFields: noHistoryFields.length > 0 ? noHistoryFields : null
        })
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

    handleByIdRefreshLogs() { this.loadByIdAuditLogs(); }

    loadDirectObjects() {
        getDirectObjects()
            .then(options => { this.byIdDirectObjectOptions = options; })
            .catch(() => {});
    }

    loadByIdAuditLogs() {
        getAuditLogsByid()
            .then(logs => {
                this.byIdAuditLogs = logs.map(log => ({
                    ...log,
                    statusClass:    this.computeStatusBadgeClass(log.TEKCO_Status__c),
                    startFormatted: log.TEKCO_StartTime__c ? new Date(log.TEKCO_StartTime__c).toLocaleString() : '—'
                }));
            })
            .catch(() => {});
    }

    startByIdAuditPoll() {
        this._byIdAuditTimer = setInterval(() => {
            this.loadByIdAuditLogs();
            if (!this.byIdAuditLogs.some(log => log.TEKCO_Status__c === 'Running')) this.stopByIdAuditPoll();
        }, AUDIT_POLL_INTERVAL_MS);
    }

    stopByIdAuditPoll() {
        if (this._byIdAuditTimer) { clearInterval(this._byIdAuditTimer); this._byIdAuditTimer = null; }
    }

    _parseByIdInput() {
        const raw = this.byIdRawInput || '';
        const seen = new Set();
        return raw.split(/[\n,;]+/)
            .map(s => s.trim())
            .filter(s => s.length > 0 && !seen.has(s) && seen.add(s));
    }

    // ── By ID getters ─────────────────────────────────────────────────────────

    get resolveModeOptions()        { return RESOLVE_MODE_OPTIONS; }
    get isExternalIdMode()          { return this.byIdResolveMode === 'EXTERNAL_ID'; }
    get byIdObjectOptions()         { return this.byIdDirectObjectOptions; }

    get byIdParsedCountLabel() {
        const count = this._parseByIdInput().length;
        const label = this.isExternalIdMode ? 'value(s) detected' : 'ID(s) detected';
        return count > 0 ? `${count} ${label}` : (this.isExternalIdMode ? 'Paste values above' : 'Paste IDs above');
    }

    get isByIdResolveDisabled() {
        if (this._parseByIdInput().length === 0 || this.isByIdResolving) return true;
        if (this.isExternalIdMode && (!this.byIdTargetObject || !this.byIdExternalIdField)) return true;
        return false;
    }

    get hasByIdResolveResult()    { return !!this.byIdResolveResult; }
    get hasByIdDirectObjects()    { return !!(this.byIdResolveResult?.directObjects?.length > 0); }
    get hasByIdChildObjects()     { return !!(this.byIdResolveResult?.childObjects?.length  > 0); }
    get hasByIdInvalidIds()       { return !!(this.byIdResolveResult?.invalidIds?.length    > 0); }
    get hasByIdAnyValid()         { return !!(this.byIdResolveResult?.totalValid > 0); }
    get byIdExternalIdFieldDisabled() { return !this.byIdTargetObject || this.byIdExternalIdFieldOptions.length === 0; }
    get hasByIdAuditLogs()        { return this.byIdAuditLogs.length > 0; }
    get hasByIdFieldConfigs()     { return this.byIdFieldConfigs.length > 0; }
    get isByIdLaunchDisabled()    { return !this.hasPermission || !this.hasByIdAnyValid || this.isByIdRunning; }
    get byIdLaunchLabel()         { return this.isByIdRunning ? 'Running...' : 'Launch Anonymization'; }

    get byIdFieldConfigsByObject() {
        const groupMap = {};
        this.byIdFieldConfigs.forEach(cfg => {
            if (!groupMap[cfg.objectApiName]) {
                groupMap[cfg.objectApiName] = { objectApiName: cfg.objectApiName, fields: [] };
            }
            groupMap[cfg.objectApiName].fields.push(cfg);
        });
        return Object.values(groupMap);
    }

    // ── By Criteria getters ───────────────────────────────────────────────────

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
        const map = { 'Success': 'badge badge-success', 'Running': 'badge badge-running', 'Partial': 'badge badge-partial', 'Failed': 'badge badge-failed' };
        return map[status] || 'badge';
    }

    showError(context, err) {
        console.error(`[TekcoAnonymizationAdmin] ${context}:`, err?.body?.message ?? err?.message ?? err);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
