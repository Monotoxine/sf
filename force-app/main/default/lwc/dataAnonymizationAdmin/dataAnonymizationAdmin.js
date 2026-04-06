import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasAnonymizePermission from '@salesforce/customPermission/Anonymize_Data';

import getBrands          from '@salesforce/apex/AnonymizationController.getBrands';
import getObjects         from '@salesforce/apex/AnonymizationController.getObjects';
import getFieldConfigs    from '@salesforce/apex/AnonymizationController.getFieldConfigs';
import getRecordCount     from '@salesforce/apex/AnonymizationController.getRecordCount';
import getAuditLogs       from '@salesforce/apex/AnonymizationController.getAuditLogs';
import startAnonymization from '@salesforce/apex/AnonymizationController.startAnonymization';

const AUDIT_POLL_INTERVAL_MS = 5000;

export default class DataAnonymizationAdmin extends LightningElement {

    hasPermission = hasAnonymizePermission;

    // ── Filter state ─────────────────────────────────────────────────────────
    @track selectedBrands  = [];
    @track selectedObjects = [];

    // ── Picklist options ─────────────────────────────────────────────────────
    @track brandOptions  = [];
    @track objectOptions = [];

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

    loadFieldConfigs() {
        this.isLoading = true;
        const obj = this.selectedObjects.length === 1 ? this.selectedObjects[0] : null;
        getFieldConfigs({ objectApiName: obj })
            .then(configs => {
                // Enrich each config with a unique key and enabled=true by default
                this.fieldConfigs = configs.map(cfg => ({
                    ...cfg,
                    // unique key used for checkbox tracking: "Object.Field"
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

        const promises = objectsToCount.map(obj =>
            getRecordCount({ objectApiName: obj, selectedBrands: this.selectedBrands })
                .then(count => ({ objectApiName: obj, count }))
                .catch(() => ({ objectApiName: obj, count: -1 }))
        );

        Promise.all(promises).then(results => {
            this.previewByObject = results.map(r => ({
                objectApiName: r.objectApiName,
                countLabel: r.count === -1 ? 'Could not count' : `${r.count} record(s)`
            }));
            this.isLoadingPreview = false;
        });
    }

    loadAuditLogs() {
        getAuditLogs()
            .then(logs => {
                this.auditLogs = logs.map(log => ({
                    ...log,
                    statusClass: this.statusBadgeClass(log.Status__c),
                    startFormatted: log.Start_Time__c
                        ? new Date(log.Start_Time__c).toLocaleString()
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
    }

    handleSelectAllBrands() {
        this.selectedBrands = this.brandOptions.map(o => o.value);
    }

    handleSelectAllObjects() {
        this.selectedObjects = this.objectOptions.map(o => o.value);
    }

    handlePreview() {
        this.loadFieldConfigs();
        this.loadPreview();
    }

    /**
     * Toggle the `enabled` flag on a field config row.
     * The checkbox data-key attribute carries "ObjectApiName.FieldApiName".
     */
    handleFieldToggle(event) {
        const key = event.target.dataset.key;
        this.fieldConfigs = this.fieldConfigs.map(cfg =>
            cfg.configKey === key ? { ...cfg, enabled: event.target.checked } : cfg
        );
    }

    handleStart() {
        if (!this.hasPermission) {
            this.showToast('Permission Denied', 'You need the "Anonymize Data" custom permission.', 'error');
            return;
        }

        // Build list of excluded fields (unchecked rows)
        const excludedFields = this.fieldConfigs
            .filter(cfg => !cfg.enabled)
            .map(cfg => cfg.configKey);

        // eslint-disable-next-line no-alert
        if (!window.confirm(
            '⚠️ You are about to anonymize data.\n\n' +
            `Brands: ${this.selectedBrands.length ? this.selectedBrands.join(', ') : 'ALL'}\n` +
            `Objects: ${this.selectedObjects.length ? this.selectedObjects.join(', ') : 'ALL configured'}\n` +
            `Bypassed fields: ${excludedFields.length ? excludedFields.join(', ') : 'none'}\n\n` +
            'This action is IRREVERSIBLE. Confirm?'
        )) return;

        this.isRunning    = true;
        this.errorMessage = '';

        startAnonymization({
            selectedBrands:  this.selectedBrands,
            selectedObjects: this.selectedObjects.length > 0 ? this.selectedObjects : null,
            excludedFields:  excludedFields.length > 0 ? excludedFields : null
        })
        .then(auditLogId => {
            this.isRunning = false;
            this.showToast('Anonymization Started', `Audit log: ${auditLogId}`, 'success');
            this.startAuditPoll();
        })
        .catch(err => {
            this.isRunning    = false;
            const msg = err?.body?.message ?? err?.message ?? 'Unknown error';
            this.errorMessage = msg;
            this.showToast('Error', msg, 'error');
        });
    }

    handleRefreshLogs() {
        this.loadAuditLogs();
    }

    // ── Audit polling ─────────────────────────────────────────────────────────

    startAuditPoll() {
        this._auditTimer = setInterval(() => {
            this.loadAuditLogs();
            if (!this.auditLogs.some(l => l.Status__c === 'Running')) {
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

    get hasFieldConfigs()   { return this.fieldConfigs.length > 0; }
    get hasPreview()        { return this.previewByObject.length > 0; }
    get hasAuditLogs()      { return this.auditLogs.length > 0; }
    get startDisabled()     { return !this.hasPermission || this.isRunning; }
    get startLabel()        { return this.isRunning ? 'Running...' : 'Launch Anonymization'; }
    get permissionWarning() {
        return this.hasPermission ? '' :
            'You need the "Anonymize Data" custom permission to trigger anonymization.';
    }

    get fieldConfigsByObject() {
        const map = {};
        this.fieldConfigs.forEach(cfg => {
            if (!map[cfg.objectApiName]) {
                map[cfg.objectApiName] = { objectApiName: cfg.objectApiName, fields: [] };
            }
            map[cfg.objectApiName].fields.push(cfg);
        });
        return Object.values(map);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    statusBadgeClass(status) {
        const map = {
            'Success': 'badge badge-success',
            'Running': 'badge badge-running',
            'Partial': 'badge badge-partial',
            'Failed' : 'badge badge-failed'
        };
        return map[status] || 'badge';
    }

    showError(context, err) {
        const msg = err?.body?.message ?? err?.message ?? 'Unknown error';
        console.error(`[AnonymizationAdmin] ${context}:`, msg);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
