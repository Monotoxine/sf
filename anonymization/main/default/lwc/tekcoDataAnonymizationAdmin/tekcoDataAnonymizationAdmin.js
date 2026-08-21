import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasAnonymizePermission from '@salesforce/customPermission/TEKCO_AnonymizeData';

import getBrands          from '@salesforce/apex/TEKCO_AnonymizationController.getBrands';
import getObjects         from '@salesforce/apex/TEKCO_AnonymizationController.getObjects';
import getRecordTypes     from '@salesforce/apex/TEKCO_AnonymizationController.getRecordTypes';
import getFieldConfigs    from '@salesforce/apex/TEKCO_AnonymizationController.getFieldConfigs';
import getPreviewCounts   from '@salesforce/apex/TEKCO_AnonymizationController.getPreviewCounts';
import getAuditLogs       from '@salesforce/apex/TEKCO_AnonymizationController.getAuditLogs';
import getConfigHealth    from '@salesforce/apex/TEKCO_AnonymizationController.getConfigHealth';
import startAnonymization from '@salesforce/apex/TEKCO_AnonymizationController.startAnonymization';
import previewSample      from '@salesforce/apex/TEKCO_AnonymizationController.previewSample';

import resolveIds                  from '@salesforce/apex/TEKCO_AnonymizationByIdController.resolveIds';
import startAnonymizationByIds     from '@salesforce/apex/TEKCO_AnonymizationByIdController.startAnonymizationByIds';
import getAuditLogsByid            from '@salesforce/apex/TEKCO_AnonymizationByIdController.getAuditLogsByid';
import getExternalIdFieldsForObject from '@salesforce/apex/TEKCO_AnonymizationByIdController.getExternalIdFieldsForObject';
import getDirectObjects              from '@salesforce/apex/TEKCO_AnonymizationByIdController.getDirectObjects';
import previewSampleByIds           from '@salesforce/apex/TEKCO_AnonymizationByIdController.previewSampleByIds';

const AUDIT_POLL_INTERVAL_MS = 5000;

/**
 * Extracts a human-readable message from anything a promise chain can reject with:
 * Apex AuraHandledException ({body: {message}}), body as an array, pageErrors, plain
 * Error objects, thrown strings. The JSON fallback guarantees an opaque 'Unknown error'
 * never reaches the user again.
 */
function extractErrorMessage(err) {
    if (!err) return 'Unknown error';
    if (typeof err === 'string') return err;
    const body = err.body ?? err;
    if (Array.isArray(body)) {
        const joined = body.map(e => e?.message).filter(Boolean).join(', ');
        if (joined) return joined;
    }
    return body?.message
        ?? err.message
        ?? body?.pageErrors?.[0]?.message
        ?? JSON.stringify(err);
}

function buildDeleteStatsLine(docs, hist) {
    const parts = [];
    if (docs > 0)  parts.push(`${docs} docs`);
    if (hist > 0)  parts.push(`${hist} hist.`);
    return parts.length ? parts.join(' · ') + ' deleted' : null;
}

/**
 * The record types one rule covers.
 *
 * TEKCO_RecordTypeDeveloperName__c holds a COMMA-SEPARATED LIST — the populations the rule
 * applies to — so it can never be compared as a single value. Its Apex mirror is
 * TEKCO_AnonymizationConfigSelector.recordTypesOf(); this is the only place the string is split
 * on the client.
 *
 * Treating it as one value is exactly what emptied the Fields to Anonymize table: a rule reading
 * "ACCCO_IndividualPerson,ACCCO_Patient" matched no selected record type, so every merged
 * Account rule was filtered out and the object looked unconfigured.
 */
function recordTypesOf(cfg) {
    if (!cfg || !cfg.recordTypeDeveloperName) return [];
    return cfg.recordTypeDeveloperName.split(',').map(v => v.trim()).filter(v => v.length > 0);
}

/** Records read per before/after sample. Apex caps it again server-side. */
const SAMPLE_SIZE = 1;

/**
 * Shapes a PreviewSampleDTO for rendering. Shared by both tabs: the two panels are the same
 * panel fed by two endpoints, so a change to the display happens once.
 */
function mapSampleResult(result) {
    const rows = (result.rows || []).map((r, index) => ({
        ...r,
        key:        `${r.recordId}.${r.fieldApiName}.${index}`,
        beforeValue: r.beforeValue === '' ? '(empty)' : r.beforeValue,
        afterValue:  r.afterValue  === '' ? '(empty)' : r.afterValue
    }));

    const parts = [`${result.recordsSampled} record(s) sampled`];
    if (result.recordsChanged   > 0) parts.push(`${result.recordsChanged} would change`);
    if (result.recordsUnchanged > 0) parts.push(`${result.recordsUnchanged} unchanged`);
    if (result.recordsToDelete  > 0) parts.push(`${result.recordsToDelete} would be deleted`);

    return {
        rows,
        summary:  parts.join(' · '),
        warnings: result.warnings || []
    };
}

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

    @track fieldFilterText = '';
    @track fieldFilterRT   = '_all_';

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

    // Configuration health
    @track configFindings   = [];
    @track configChecked    = false;
    @track isCheckingConfig = false;

    // Before/after sample (By Criteria)
    @track sampleObjectOptions = [];
    @track sampleObject        = '';
    @track sampleRows          = [];
    @track sampleSummary       = null;
    @track sampleWarnings      = [];
    @track isLoadingSample     = false;

    // ── By ID tab state ───────────────────────────────────────────────────────
    @track byIdFieldFilterText = '';
    @track byIdFieldFilterRT   = '_all_';

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

    // Before/after sample (By ID)
    @track byIdSampleObjectOptions = [];
    @track byIdSampleObject        = '';
    @track byIdSampleRows          = [];
    @track byIdSampleSummary       = null;
    @track byIdSampleWarnings      = [];
    @track isLoadingByIdSample     = false;

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
                    configKey:             cfg.developerName,
                    recordTypeLabel:       recordTypesOf(cfg).join(', '),
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
            // Only objects that hold field-level patterns and actually match can be sampled.
            this.sampleObjectOptions = results
                .filter(r => !r.isContentDocOnly && r.count > 0)
                .map(r => ({ label: r.objectApiName, value: r.objectApiName }));
            this.resetSample();
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
                    startFormatted: log.TEKCO_StartTime__c ? new Date(log.TEKCO_StartTime__c).toLocaleString() : '—',
                    statsLine1:     `${log.TEKCO_RecordsProcessed__c ?? 0} processed`,
                    statsLine2:     buildDeleteStatsLine(log.TEKCO_DocumentsDeleted__c ?? 0, log.TEKCO_HistoryRecordsDeleted__c ?? 0)
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

    /**
     * Surfaces what the batches would merely "skip": an object or field that does not exist,
     * a pattern type with no active record, a filter that will not parse. Each of those leaves
     * a field un-anonymized today with no visible signal.
     */
    handleCheckConfig() {
        this.isCheckingConfig = true;
        getConfigHealth()
            .then(findings => {
                this.configFindings   = (findings || []).map((text, index) => ({ key: index, text }));
                this.configChecked    = true;
                this.isCheckingConfig = false;
            }, err => {
                this.showError('Configuration check failed', err);
                this.isCheckingConfig = false;
            });
    }

    // ── Before/after sample (By Criteria) ─────────────────────────────────────

    resetSample() {
        const available = new Set(this.sampleObjectOptions.map(o => o.value));
        if (!available.has(this.sampleObject)) {
            this.sampleObject = this.sampleObjectOptions.length === 1
                ? this.sampleObjectOptions[0].value
                : '';
        }
        this.sampleRows     = [];
        this.sampleSummary  = null;
        this.sampleWarnings = [];
    }

    handleSampleObjectChange(event) {
        this.sampleObject   = event.detail.value;
        this.sampleRows     = [];
        this.sampleSummary  = null;
        this.sampleWarnings = [];
    }

    /**
     * Reads a handful of records and shows what the run would write, without any DML.
     * Field exclusions ticked in the table below are honoured, so what is shown is what the
     * launch would actually do.
     */
    handleShowSample() {
        if (!this.sampleObject) return;
        this.isLoadingSample = true;
        this.sampleRows      = [];
        this.sampleSummary   = null;
        this.sampleWarnings  = [];

        const excludedFields = this.fieldConfigs
            .filter(cfg => cfg.objectApiName === this.sampleObject && !cfg.enabled)
            .map(cfg => cfg.configKey);

        previewSample({
            objectApiName:       this.sampleObject,
            selectedBrands:      this.selectedBrands,
            selectedRecordTypes: this.selectedRecordTypes.length > 0 ? this.selectedRecordTypes : null,
            excludedFields:      excludedFields.length > 0 ? excludedFields : null,
            sampleSize:          SAMPLE_SIZE
        })
        .then(result => {
            const mapped        = mapSampleResult(result);
            this.sampleRows     = mapped.rows;
            this.sampleSummary  = mapped.summary;
            this.sampleWarnings = mapped.warnings;
            this.isLoadingSample = false;
        }, err => {
            this.showError('Sample preview failed', err);
            this.isLoadingSample = false;
        });
    }
    handleFieldFilterChange(event)   { this.fieldFilterText = event.target.value; }
    handleFieldFilterRtChange(event) { this.fieldFilterRT   = event.detail.value; }
    handleSelectAllRun() {
        const visible = new Set(this.fieldConfigsFiltered.map(c => c.configKey));
        this.fieldConfigs = this.fieldConfigs.map(cfg => visible.has(cfg.configKey) ? { ...cfg, enabled: true } : cfg);
    }
    handleDeselectAllRun() {
        const visible = new Set(this.fieldConfigsFiltered.map(c => c.configKey));
        this.fieldConfigs = this.fieldConfigs.map(cfg => visible.has(cfg.configKey) ? { ...cfg, enabled: false } : cfg);
    }
    handleSelectAllHistory() {
        const visible = new Set(this.fieldConfigsFiltered.map(c => c.configKey));
        this.fieldConfigs = this.fieldConfigs.map(cfg => visible.has(cfg.configKey) && cfg.originalDeleteHistory ? { ...cfg, deleteHistory: true } : cfg);
    }
    handleDeselectAllHistory() {
        const visible = new Set(this.fieldConfigsFiltered.map(c => c.configKey));
        this.fieldConfigs = this.fieldConfigs.map(cfg => visible.has(cfg.configKey) ? { ...cfg, deleteHistory: false } : cfg);
    }
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
        // Two-argument then(): the rejection handler must only see the Apex failure.
        // A chained .catch would also swallow throws from the success handler (e.g. the
        // Lightning container's toast instrumentation) and report a started run as failed.
        .then(
            auditLogId => {
                this.isRunning = false;
                this.startAuditPoll(); // before the toast, so a toast-layer throw cannot skip it
                this.showToast('Anonymization Started', `Audit log: ${auditLogId}`, 'success');
            },
            err => {
                this.isRunning    = false;
                this.errorMessage = extractErrorMessage(err);
                this.showToast('Error', this.errorMessage, 'error');
            }
        );
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
                this._refreshByIdSampleOptions(result);
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
                    configKey:             cfg.developerName,
                    recordTypeLabel:       recordTypesOf(cfg).join(', '),
                    enabled:               true,
                    deleteHistory:         cfg.deleteHistory !== false,
                    originalDeleteHistory: cfg.deleteHistory !== false,
                    isContentDoc:          cfg.patternType === 'DELETE_CONTENT_DOCUMENT'
                }));
            })
            .catch(() => { this.byIdFieldConfigs = []; });
    }

    // ── Before/after sample (By ID) ───────────────────────────────────────────

    _refreshByIdSampleOptions(resolveResult) {
        this.byIdSampleObjectOptions = [
            ...(resolveResult.directObjects || []),
            ...(resolveResult.childObjects  || [])
        ].map(o => ({ label: o.objectApiName, value: o.objectApiName }));

        const available = new Set(this.byIdSampleObjectOptions.map(o => o.value));
        if (!available.has(this.byIdSampleObject)) {
            this.byIdSampleObject = this.byIdSampleObjectOptions.length === 1
                ? this.byIdSampleObjectOptions[0].value
                : '';
        }
        this.byIdSampleRows     = [];
        this.byIdSampleSummary  = null;
        this.byIdSampleWarnings = [];
    }

    handleByIdSampleObjectChange(event) {
        this.byIdSampleObject   = event.detail.value;
        this.byIdSampleRows     = [];
        this.byIdSampleSummary  = null;
        this.byIdSampleWarnings = [];
    }

    handleShowByIdSample() {
        if (!this.byIdSampleObject) return;
        const ids = this._parseByIdInput();
        if (!ids.length) return;

        this.isLoadingByIdSample = true;
        this.byIdSampleRows      = [];
        this.byIdSampleSummary   = null;
        this.byIdSampleWarnings  = [];

        const excludedFields = this.byIdFieldConfigs
            .filter(cfg => cfg.objectApiName === this.byIdSampleObject && !cfg.enabled)
            .map(cfg => cfg.configKey);

        previewSampleByIds({
            rawIds:          ids,
            resolveMode:     this.byIdResolveMode,
            targetObject:    this.byIdTargetObject || null,
            externalIdField: this.byIdExternalIdField || null,
            objectApiName:   this.byIdSampleObject,
            excludedFields:  excludedFields.length > 0 ? excludedFields : null,
            sampleSize:      SAMPLE_SIZE
        })
        .then(result => {
            const mapped            = mapSampleResult(result);
            this.byIdSampleRows     = mapped.rows;
            this.byIdSampleSummary  = mapped.summary;
            this.byIdSampleWarnings = mapped.warnings;
            this.isLoadingByIdSample = false;
        }, err => {
            this.byIdErrorMessage    = extractErrorMessage(err);
            this.isLoadingByIdSample = false;
        });
    }

    handleByIdFieldToggle(event) {
        const configKey = event.target.dataset.key;
        this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg =>
            cfg.configKey === configKey ? { ...cfg, enabled: event.target.checked } : cfg
        );
    }

    handleByIdFieldFilterChange(event)   { this.byIdFieldFilterText = event.target.value; }
    handleByIdFieldFilterRtChange(event) { this.byIdFieldFilterRT   = event.detail.value; }
    handleByIdSelectAllFields() {
        const visible = new Set(this.byIdFieldConfigsFiltered.map(c => c.configKey));
        this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg => visible.has(cfg.configKey) ? { ...cfg, enabled: true } : cfg);
    }
    handleByIdDeselectAllFields() {
        const visible = new Set(this.byIdFieldConfigsFiltered.map(c => c.configKey));
        this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg => visible.has(cfg.configKey) ? { ...cfg, enabled: false } : cfg);
    }
    handleByIdSelectAllHistory() {
        const visible = new Set(this.byIdFieldConfigsFiltered.map(c => c.configKey));
        this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg => visible.has(cfg.configKey) && cfg.originalDeleteHistory ? { ...cfg, deleteHistory: true } : cfg);
    }
    handleByIdDeselectAllHistory() {
        const visible = new Set(this.byIdFieldConfigsFiltered.map(c => c.configKey));
        this.byIdFieldConfigs = this.byIdFieldConfigs.map(cfg => visible.has(cfg.configKey) ? { ...cfg, deleteHistory: false } : cfg);
    }

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
            // Same two-argument shape as handleConfirmLaunch — see the comment there.
            .then(
                auditLogId => {
                    this.isByIdRunning = false;
                    this.startByIdAuditPoll();
                    this.showToast('Anonymization Started', `Audit log: ${auditLogId}`, 'success');
                },
                err => {
                    this.isByIdRunning    = false;
                    this.byIdErrorMessage = extractErrorMessage(err);
                    this.showToast('Error', this.byIdErrorMessage, 'error');
                }
            );
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
                    startFormatted: log.TEKCO_StartTime__c ? new Date(log.TEKCO_StartTime__c).toLocaleString() : '—',
                    statsLine1:     `${log.TEKCO_RecordsProcessed__c ?? 0} processed`,
                    statsLine2:     buildDeleteStatsLine(log.TEKCO_DocumentsDeleted__c ?? 0, log.TEKCO_HistoryRecordsDeleted__c ?? 0)
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

    get hasByIdSampleObjects()    { return this.byIdSampleObjectOptions.length > 0; }
    get hasByIdSampleRows()        { return this.byIdSampleRows.length > 0; }
    get hasByIdSampleWarnings()    { return this.byIdSampleWarnings.length > 0; }
    get isByIdSampleDisabled()     { return !this.byIdSampleObject || this.isLoadingByIdSample; }
    get hasByIdFieldConfigs()     { return this.byIdFieldConfigs.length > 0; }
    get isByIdLaunchDisabled()    { return !this.hasPermission || !this.hasByIdAnyValid || this.isByIdRunning; }
    get byIdLaunchLabel()         { return this.isByIdRunning ? 'Running...' : 'Launch Anonymization'; }

    get byIdFieldConfigsFiltered() {
        let result = this.byIdFieldConfigs || [];
        if (this.byIdFieldFilterText) {
            const q = this.byIdFieldFilterText.toLowerCase();
            result = result.filter(c => c.fieldApiName.toLowerCase().includes(q));
        }
        if (this.byIdFieldFilterRT && this.byIdFieldFilterRT !== '_all_') {
            const isBlank = this.byIdFieldFilterRT === '_blank_';
            result = result.filter(c => isBlank
                ? recordTypesOf(c).length === 0
                : recordTypesOf(c).includes(this.byIdFieldFilterRT));
        }
        return result;
    }

    get byIdFieldFilterRtOptions() {
        const seen = new Set();
        const options = [{ label: 'All Record Types', value: '_all_' }];
        (this.byIdFieldConfigs || []).forEach(c => {
            const covered = recordTypesOf(c);
            if (covered.length === 0) covered.push('');
            covered.forEach(rt => {
                if (seen.has(rt)) return;
                seen.add(rt);
                options.push({ label: rt || '(none)', value: rt || '_blank_' });
            });
        });
        return options;
    }

    get byIdFieldConfigsByObject() {
        const groupMap = {};
        this.byIdFieldConfigsFiltered.forEach(cfg => {
            if (!groupMap[cfg.objectApiName]) {
                groupMap[cfg.objectApiName] = { objectApiName: cfg.objectApiName, fields: [] };
            }
            groupMap[cfg.objectApiName].fields.push(cfg);
        });
        return Object.values(groupMap);
    }

    // ── By Criteria getters ───────────────────────────────────────────────────

    get hasFieldConfigs()      { return this.fieldConfigs.length > 0; }
    get hasConfigFindings()    { return this.configFindings.length > 0; }
    get configIsClean()        { return this.configChecked && this.configFindings.length === 0; }
    get hasPreview()           { return this.previewByObject.length > 0; }
    get hasSampleObjects()     { return this.sampleObjectOptions.length > 0; }
    get hasSampleRows()        { return this.sampleRows.length > 0; }
    get hasSampleWarnings()    { return this.sampleWarnings.length > 0; }
    get isSampleDisabled()     { return !this.sampleObject || this.isLoadingSample; }
    get hasAuditLogs()         { return this.auditLogs.length > 0; }
    get hasRecordTypeOptions() { return this.recordTypeOptions.length > 0; }
    get isStartDisabled()      { return !this.hasPermission || this.isRunning; }
    get startLabel()           { return this.isRunning ? 'Running...' : 'Launch Anonymization'; }
    get permissionWarning() {
        return this.hasPermission ? ''
            : 'You need the "TEKCO Anonymize Data" custom permission to trigger anonymization.';
    }

    get fieldConfigsFiltered() {
        let result = this.fieldConfigs || [];
        // Pre-filter by the main RT selector when record types are selected
        if (this.selectedRecordTypes && this.selectedRecordTypes.length > 0) {
            const selectedSet = new Set(this.selectedRecordTypes);
            // A rule stays as soon as ONE of the populations it covers is selected — the same
            // intersection the launch service applies server-side.
            result = result.filter(c => {
                const covered = recordTypesOf(c);
                return covered.length === 0 || covered.some(rt => selectedSet.has(rt));
            });
        }
        // Manual text filter
        if (this.fieldFilterText) {
            const q = this.fieldFilterText.toLowerCase();
            result = result.filter(c => c.fieldApiName.toLowerCase().includes(q));
        }
        // Manual RT dropdown filter
        if (this.fieldFilterRT && this.fieldFilterRT !== '_all_') {
            const isBlank = this.fieldFilterRT === '_blank_';
            result = result.filter(c => isBlank
                ? recordTypesOf(c).length === 0
                : recordTypesOf(c).includes(this.fieldFilterRT));
        }
        return result;
    }

    get fieldFilterRtOptions() {
        const seen = new Set();
        const options = [{ label: 'All Record Types', value: '_all_' }];
        (this.fieldConfigs || []).forEach(c => {
            const covered = recordTypesOf(c);
            if (covered.length === 0) covered.push('');
            covered.forEach(rt => {
                if (seen.has(rt)) return;
                seen.add(rt);
                options.push({ label: rt || '(none)', value: rt || '_blank_' });
            });
        });
        return options;
    }

    get fieldConfigsByObject() {
        const groupMap = {};
        this.fieldConfigsFiltered.forEach(cfg => {
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
        console.error(`[TekcoAnonymizationAdmin] ${context}:`, extractErrorMessage(err));
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}