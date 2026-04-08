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

    // ── Filter state ─────────────────────────────────────────────────────────
    @track selectedBrands      = [];
    @track selectedObjects     = [];
    @track selectedRecordTypes = [];

    // ── Picklist options ─────────────────────────────────────────────────────
    @track brandOptions      = [];
    @track objectOptions     = [];
    @track recordTypeOptions = [];

    // ── Data ─────────────────────────────────────────────────────────────────
    // fieldConfigs: array of FieldConfigDTO enriched with `enabled` (checkbox state)
    @track fieldConfigs    = [];
    @track previewByObject = [];
    @track auditLogs       = [];

    // ── UI flags ─────────────────────────────────────────────────────────────
    @track isLoading        = false;
    @track isLoadingPreview = false;
    @track isRunning        = false;
    @track errorMessage     = '';

    _auditTimer = null;

    // ── Lifecycle ─────────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadBrands();
        this.loadObjects();
        this.loadRecordTypes(null);
        this.loadAuditLogs();
    }

    disconnectedCallback() {
        this.stopAuditPoll();
    }

    // ── Data loaders ──────────────────────────────────────────────────────────

    loadBrands() {
        getBrands()
            .then(values => {
                this.brandOptions = values.map(v => ({ label: v, value: v }));
            })
            .catch(err => this.showError('Failed to load brands', err));
    }

    loadObjects() {
        getObjects()
            .then(values => {
                this.objectOptions = values.map(v => ({ label: v, value: v }));
            })
            .catch(err => this.showError('Failed to load objects', err));
    }

    loadRecordTypes(objectApiName) {
        getRecordTypes({ objectApiName: objectApiName || null })
            .then(values => {
                this.recordTypeOptions = values.map(v => ({ label: v, value: v }));
                // Drop any previously selected RT that no longer exists in the new scope
                if (this.recordTypeOptions.length > 0) {
                    const available = new Set(values);
                    this.selectedRecordTypes = this.selectedRecordTypes.filter(rt => available.has(rt));
                } else {
                    this.selectedRecordTypes = [];
                }
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
                    configKey: `${cfg.objectApiName}.${cfg.fieldApiName}`,
                    enabled: true
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

        const objectsToCount = this.selectedObjects.length > 0
            ? this.selectedObjects
            : this.objectOptions.map(o => o.value);

        const countPromises = objectsToCount.map(objectApiName =>
            getRecordCount({ objectApiName, selectedBrands: this.selectedBrands })
                .then(count => ({ objectApiName, count }))
                .catch(() => ({ objectApiName, count: -1 }))
        );

        Promise.all(countPromises).then(results => {
            this.previewByObject = results.map(result => ({
                objectApiName: result.objectApiName,
                countLabel: result.count === -1 ? 'Could not count' : `${result.count} record(s)`
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

    // ── Handlers ──────────────────────────────────────────────────────────────

    handleBrandChange(event) {
        this.selectedBrands = event.detail.value;
    }

    handleObjectChange(event) {
        this.selectedObjects = event.detail.value;
        this.fieldConfigs    = [];
        this.previewByObject = [];
        // Reload record types scoped to the single selected object, or all if multiple/none
        const scopeObject = this.selectedObjects.length === 1 ? this.selectedObjects[0] : null;
        this.loadRecordTypes(scopeObject);
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
        this.loadRecordTypes(null);
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

    handleStart() {
        if (!this.hasPermission) {
            this.showToast('Permission Denied', 'You need the "TEKCO Anonymize Data" custom permission.', 'error');
            return;
        }

        const excludedFields = this.fieldConfigs
            .filter(cfg => !cfg.enabled)
            .map(cfg => cfg.configKey);

        // eslint-disable-next-line no-alert
        if (!window.confirm(
            'WARNING: You are about to anonymize data.\n\n' +
            `Brands: ${this.selectedBrands.length ? this.selectedBrands.join(', ') : 'ALL'}\n` +
            `Objects: ${this.selectedObjects.length ? this.selectedObjects.join(', ') : 'ALL configured'}\n` +
            `Record Types: ${this.selectedRecordTypes.length ? this.selectedRecordTypes.join(', ') : 'ALL'}\n` +
            `Bypassed fields: ${excludedFields.length ? excludedFields.join(', ') : 'none'}\n\n` +
            'This action is IRREVERSIBLE. Confirm?'
        )) return;

        this.isRunning    = true;
        this.errorMessage = '';

        startAnonymization({
            selectedBrands:      this.selectedBrands,
            selectedObjects:     this.selectedObjects.length > 0 ? this.selectedObjects : null,
            excludedFields:      excludedFields.length > 0 ? excludedFields : null,
            selectedRecordTypes: this.selectedRecordTypes.length > 0 ? this.selectedRecordTypes : null
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

    handleRefreshLogs() {
        this.loadAuditLogs();
    }

    // ── Audit polling ─────────────────────────────────────────────────────────

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

    // ── Computed getters ──────────────────────────────────────────────────────

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

    // ── Helpers ───────────────────────────────────────────────────────────────

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
