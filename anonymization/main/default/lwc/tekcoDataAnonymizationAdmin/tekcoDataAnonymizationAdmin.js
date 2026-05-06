import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasAnonymizePermission from '@salesforce/customPermission/TEKCO_AnonymizeData';

import getBrands          from '@salesforce/apex/TEKCO_AnonymizationController.getBrands';
import getObjects         from '@salesforce/apex/TEKCO_AnonymizationController.getObjects';
import getRecordTypes     from '@salesforce/apex/TEKCO_AnonymizationController.getRecordTypes';
import getFieldConfigs    from '@salesforce/apex/TEKCO_AnonymizationController.getFieldConfigs';
import getRecordCount     from '@salesforce/apex/TEKCO_AnonymizationController.getRecordCount';
import getAuditLogs       from '@salesforce/apex/TEKCO_AnonymizationController.getAuditLogs';
import startAnonymization from '@salesforce/apex/TEKCO_AnonymizationController.startAnonymization';

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

    _pendingExcludedFields        = [];
    _pendingDisabledHistoryFields = [];
    _auditTimer = null;

    connectedCallback() {
        this.loadBrands();
        this.loadObjects();
        this.loadRecordTypes([]);
        this.loadAuditLogs();
    }

    disconnectedCallback() {
        this.stopAuditPoll();
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
        const objectApiName = this.selectedObjects.length === 1 ? this.selectedObjects[0] : null;
        const selectedRecordTypes = this.selectedRecordTypes.length > 0 ? this.selectedRecordTypes : null;
        getFieldConfigs({ objectApiName, selectedRecordTypes })
            .then(configs => {
                // Enrich each config with a unique key and enabled=true by default
                this.fieldConfigs = configs.map(cfg => ({
                    ...cfg,
                    configKey:             `${cfg.objectApiName}.${cfg.fieldApiName}`,
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

        const hasFilter = this.selectedObjects.length > 0;
        const objectsToCount = hasFilter
            ? this.selectedObjects
            : this.objectOptions.map(o => o.value);

        // Build a set of objects that ONLY have DELETE_CONTENT_DOCUMENT configs
        // so we can display a meaningful label instead of a plain record count.
        const contentDocOnly = new Set(
            this.fieldConfigs.length > 0
                ? Object.entries(
                    this.fieldConfigs.reduce((acc, cfg) => {
                        if (!acc[cfg.objectApiName]) acc[cfg.objectApiName] = { total: 0, contentDoc: 0 };
                        acc[cfg.objectApiName].total++;
                        if (cfg.isContentDoc) acc[cfg.objectApiName].contentDoc++;
                        return acc;
                    }, {})
                  )
                    .filter(([, counts]) => counts.total === counts.contentDoc)
                    .map(([obj]) => obj)
                : []
        );

        this.previewNote = hasFilter
            ? null
            : 'No object selected — all configured objects will be included.';

        const selectedRecordType = this.selectedRecordTypes.length === 1
            ? this.selectedRecordTypes[0]
            : null;

        const countPromises = objectsToCount.map(objectApiName =>
            getRecordCount({ objectApiName, selectedBrands: this.selectedBrands, selectedRecordType })
                .then(count => ({ objectApiName, count, isContentDocOnly: contentDocOnly.has(objectApiName) }))
                .catch(() => ({ objectApiName, count: -1, isContentDocOnly: contentDocOnly.has(objectApiName) }))
        );

        Promise.all(countPromises).then(results => {
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
