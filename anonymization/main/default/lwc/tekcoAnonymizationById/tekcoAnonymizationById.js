import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasAnonymizePermission from '@salesforce/customPermission/TEKCO_AnonymizeData';

import resolveIds              from '@salesforce/apex/TEKCO_AnonymizationByIdController.resolveIds';
import startAnonymizationByIds from '@salesforce/apex/TEKCO_AnonymizationByIdController.startAnonymizationByIds';
import getAuditLogs            from '@salesforce/apex/TEKCO_AnonymizationByIdController.getAuditLogs';

const AUDIT_POLL_INTERVAL_MS = 5000;

export default class TekcoAnonymizationById extends LightningElement {

    hasPermission = hasAnonymizePermission;

    @track rawInput         = '';
    @track resolveResult    = null;
    @track auditLogs        = [];
    @track isResolving      = false;
    @track isRunning        = false;
    @track errorMessage     = '';
    @track showConfirmPanel = false;
    @track confirmSummaryLines = [];

    _auditTimer = null;

    connectedCallback() {
        this.loadAuditLogs();
    }

    disconnectedCallback() {
        this.stopAuditPoll();
    }

    handleInputChange(event) {
        this.rawInput      = event.target.value;
        this.resolveResult = null;
        this.errorMessage  = '';
    }

    handleResolve() {
        const ids = this.parseIds(this.rawInput);
        if (ids.length === 0) {
            this.errorMessage = 'No IDs found in the input.';
            return;
        }
        this.isResolving   = true;
        this.resolveResult = null;
        this.errorMessage  = '';

        resolveIds({ rawIds: ids })
            .then(result => {
                this.resolveResult = result;
                this.isResolving   = false;
            })
            .catch(err => {
                this.errorMessage = err?.body?.message ?? err?.message ?? 'Unknown error';
                this.isResolving  = false;
            });
    }

    handleLaunch() {
        if (!this.hasPermission) {
            this.showToast('Permission Denied', 'You need the "TEKCO Anonymize Data" custom permission.', 'error');
            return;
        }

        const totalValid = this.resolveResult?.totalValid ?? 0;
        const objLines   = (this.resolveResult?.objectCounts ?? [])
            .map(o => `${o.objectApiName}: ${o.recordCount} record(s)`)
            .join(', ');

        this.confirmSummaryLines = [
            { key: 'total',   label: 'Total IDs to process', value: String(totalValid) },
            { key: 'objects', label: 'Objects',              value: objLines || '—' }
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

        const ids = this.parseIds(this.rawInput);
        startAnonymizationByIds({ rawIds: ids })
            .then(auditLogId => {
                this.isRunning = false;
                this.showToast('Anonymization Started', `Audit log ID: ${auditLogId}`, 'success');
                this.loadAuditLogs();
                this.startAuditPoll();
            })
            .catch(err => {
                this.isRunning    = false;
                const msg         = err?.body?.message ?? err?.message ?? 'Unknown error';
                this.errorMessage = msg;
                this.showToast('Error', msg, 'error');
            });
    }

    handleRefreshLogs() {
        this.loadAuditLogs();
    }

    // ── Private ───────────────────────────────────────────────────────────────

    loadAuditLogs() {
        getAuditLogs()
            .then(logs => {
                this.auditLogs = logs.map(log => ({
                    ...log,
                    statusClass:    this.statusBadgeClass(log.TEKCO_Status__c),
                    startFormatted: log.TEKCO_StartTime__c
                        ? new Date(log.TEKCO_StartTime__c).toLocaleString() : '—'
                }));
            })
            .catch(() => {});
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

    /**
     * Splits rawInput on newlines, commas, and semicolons.
     * Returns de-duplicated, trimmed, non-empty strings.
     */
    parseIds(rawInput) {
        if (!rawInput) return [];
        const seen = new Set();
        return rawInput
            .split(/[\n,;]+/)
            .map(s => s.trim())
            .filter(s => s.length > 0 && !seen.has(s) && seen.add(s));
    }

    statusBadgeClass(status) {
        const map = {
            'Success': 'badge badge-success',
            'Running': 'badge badge-running',
            'Partial': 'badge badge-partial',
            'Failed' : 'badge badge-failed'
        };
        return map[status] || 'badge';
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // ── Getters ───────────────────────────────────────────────────────────────

    get parsedCountLabel() {
        const count = this.parseIds(this.rawInput).length;
        return count === 0 ? 'Paste your IDs above.' : `${count} unique ID(s) entered.`;
    }

    get hasResolveResult()  { return this.resolveResult !== null; }
    get hasValidObjects()   { return (this.resolveResult?.objectCounts?.length ?? 0) > 0; }
    get hasInvalidIds()     { return (this.resolveResult?.invalidIds?.length ?? 0) > 0; }
    get hasAuditLogs()      { return this.auditLogs.length > 0; }
    get isResolveDisabled() { return this.isResolving || this.parseIds(this.rawInput).length === 0; }
    get isLaunchDisabled()  {
        return !this.hasPermission
            || this.isRunning
            || !this.hasResolveResult
            || !this.hasValidObjects;
    }
    get launchLabel()       { return this.isRunning ? 'Running...' : 'Launch Anonymization'; }
    get permissionWarning() {
        return this.hasPermission ? ''
            : 'You need the "TEKCO Anonymize Data" custom permission to trigger anonymization.';
    }
}
