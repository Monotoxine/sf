import { LightningElement, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasAnonymizePermission from '@salesforce/customPermission/Anonymize_Data';

import getBrands       from '@salesforce/apex/AnonymizationController.getBrands';
import getObjects      from '@salesforce/apex/AnonymizationController.getObjects';
import getFieldConfigs from '@salesforce/apex/AnonymizationController.getFieldConfigs';
import getRecordCount  from '@salesforce/apex/AnonymizationController.getRecordCount';
import getAuditLogs    from '@salesforce/apex/AnonymizationController.getAuditLogs';
import startAnonymization from '@salesforce/apex/AnonymizationController.startAnonymization';

const AUDIT_REFRESH_INTERVAL_MS = 5000;

export default class DataAnonymizationAdmin extends LightningElement {

    // ─── Permission ───────────────────────────────────────────────────────────
    hasPermission = hasAnonymizePermission;

    // ─── Filters ──────────────────────────────────────────────────────────────
    @track selectedBrand  = '';
    @track selectedObject = '';

    // ─── Data ─────────────────────────────────────────────────────────────────
    @track brandOptions   = [];
    @track objectOptions  = [];
    @track fieldConfigs   = [];
    @track auditLogs      = [];
    @track previewByObject = []; // [{ objectApiName, count, fields }]

    // ─── UI State ─────────────────────────────────────────────────────────────
    @track isLoading      = false;
    @track isLoadingPreview = false;
    @track isRunning      = false;
    @track errorMessage   = '';

    _auditRefreshTimer = null;

    // ─── Lifecycle ────────────────────────────────────────────────────────────

    connectedCallback() {
        this.loadBrands();
        this.loadObjects();
        this.loadAuditLogs();
    }

    disconnectedCallback() {
        this.stopAuditRefresh();
    }

    // ─── Data Loaders ─────────────────────────────────────────────────────────

    loadBrands() {
        getBrands()
            .then(brands => {
                this.brandOptions = [
                    { label: '-- All Brands --', value: '' },
                    ...brands.map(b => ({ label: b, value: b }))
                ];
            })
            .catch(err => this.handleError('Failed to load brands', err));
    }

    loadObjects() {
        getObjects({ brand: this.selectedBrand || null })
            .then(objects => {
                this.objectOptions = [
                    { label: '-- All Objects --', value: '' },
                    ...objects.map(o => ({ label: o, value: o }))
                ];
            })
            .catch(err => this.handleError('Failed to load objects', err));
    }

    loadFieldConfigs() {
        this.isLoading = true;
        getFieldConfigs({
            objectApiName: this.selectedObject || null,
            brand: this.selectedBrand || null
        })
        .then(configs => {
            this.fieldConfigs = configs;
            this.isLoading = false;
        })
        .catch(err => {
            this.handleError('Failed to load field configurations', err);
            this.isLoading = false;
        });
    }

    loadAuditLogs() {
        getAuditLogs()
            .then(logs => {
                this.auditLogs = logs.map(log => ({
                    ...log,
                    statusClass: this.getStatusClass(log.Status__c),
                    startTimeFormatted: log.Start_Time__c
                        ? new Date(log.Start_Time__c).toLocaleString()
                        : '-'
                }));
            })
            .catch(err => this.handleError('Failed to load audit logs', err));
    }

    // ─── Event Handlers ───────────────────────────────────────────────────────

    handleBrandChange(event) {
        this.selectedBrand = event.detail.value;
        this.selectedObject = '';
        this.fieldConfigs = [];
        this.previewByObject = [];
        this.loadObjects();
    }

    handleObjectChange(event) {
        this.selectedObject = event.detail.value;
        this.fieldConfigs = [];
        this.previewByObject = [];
    }

    handlePreview() {
        this.loadFieldConfigs();
        this.loadPreview();
    }

    loadPreview() {
        this.isLoadingPreview = true;
        this.previewByObject = [];

        // Determine which objects to preview
        const objectsToPreview = this.selectedObject
            ? [this.selectedObject]
            : this.objectOptions.filter(o => o.value !== '').map(o => o.value);

        const promises = objectsToPreview.map(obj =>
            getRecordCount({ objectApiName: obj })
                .then(count => ({ objectApiName: obj, count }))
                .catch(() => ({ objectApiName: obj, count: -1 }))
        );

        Promise.all(promises)
            .then(results => {
                this.previewByObject = results.map(r => ({
                    objectApiName: r.objectApiName,
                    count: r.count === -1 ? 'N/A' : r.count,
                    countLabel: r.count === -1
                        ? 'Could not count records'
                        : `${r.count} record(s) will be anonymized`
                }));
                this.isLoadingPreview = false;
            });
    }

    handleStart() {
        if (!this.hasPermission) {
            this.showToast('Permission Denied', 'You do not have the "Anonymize Data" permission.', 'error');
            return;
        }

        if (!this.confirmExecution()) return;

        this.isRunning = true;
        this.errorMessage = '';

        const objectList = this.selectedObject ? [this.selectedObject] : null;

        startAnonymization({
            brand: this.selectedBrand || null,
            objectApiNames: objectList
        })
        .then(auditLogId => {
            this.showToast(
                'Anonymization Started',
                `Job launched. Audit Log ID: ${auditLogId}`,
                'success'
            );
            this.isRunning = false;
            this.startAuditRefresh();
        })
        .catch(err => {
            this.isRunning = false;
            const msg = err.body ? err.body.message : err.message;
            this.errorMessage = msg;
            this.showToast('Error', msg, 'error');
        });
    }

    handleRefreshLogs() {
        this.loadAuditLogs();
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────

    confirmExecution() {
        const scope = this.selectedObject || 'ALL objects';
        const brand = this.selectedBrand || 'ALL brands';
        // eslint-disable-next-line no-alert
        return window.confirm(
            `⚠️ You are about to anonymize data on: ${scope} (${brand}).\n\n` +
            `This action is IRREVERSIBLE. Are you sure?`
        );
    }

    startAuditRefresh() {
        this._auditRefreshTimer = setInterval(() => {
            this.loadAuditLogs();
            // Stop refreshing once no log is "Running"
            const hasRunning = this.auditLogs.some(l => l.Status__c === 'Running');
            if (!hasRunning) this.stopAuditRefresh();
        }, AUDIT_REFRESH_INTERVAL_MS);
    }

    stopAuditRefresh() {
        if (this._auditRefreshTimer) {
            clearInterval(this._auditRefreshTimer);
            this._auditRefreshTimer = null;
        }
    }

    getStatusClass(status) {
        switch (status) {
            case 'Success': return 'slds-badge slds-theme_success';
            case 'Running': return 'slds-badge slds-theme_info';
            case 'Partial': return 'slds-badge slds-theme_warning';
            case 'Failed':  return 'slds-badge slds-theme_error';
            default:        return 'slds-badge';
        }
    }

    handleError(context, err) {
        const msg = err && err.body ? err.body.message : (err ? err.message : 'Unknown error');
        console.error(`[AnonymizationAdmin] ${context}:`, msg);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // ─── Computed Getters ─────────────────────────────────────────────────────

    get hasFieldConfigs() {
        return this.fieldConfigs && this.fieldConfigs.length > 0;
    }

    get hasPreview() {
        return this.previewByObject && this.previewByObject.length > 0;
    }

    get hasAuditLogs() {
        return this.auditLogs && this.auditLogs.length > 0;
    }

    get startButtonDisabled() {
        return !this.hasPermission || this.isRunning;
    }

    get startButtonLabel() {
        return this.isRunning ? 'Running...' : 'Launch Anonymization';
    }

    get permissionWarning() {
        return !this.hasPermission
            ? 'You do not have the "Anonymize Data" custom permission. Contact your administrator.'
            : '';
    }

    // Group field configs by object for display
    get fieldConfigsByObject() {
        const map = {};
        (this.fieldConfigs || []).forEach(cfg => {
            if (!map[cfg.objectApiName]) {
                map[cfg.objectApiName] = { objectApiName: cfg.objectApiName, fields: [] };
            }
            map[cfg.objectApiName].fields.push(cfg);
        });
        return Object.values(map);
    }
}
