import { LightningElement, api } from 'lwc';

export default class DynamicOmniscriptHost extends LightningElement {

    @api omniscriptType;
    @api omniscriptSubType;
    @api omniscriptLang = 'English'; // Default language
    @api omniscriptVersion;

    connectedCallback() {
        console.log('🔵 OmniScript Host connected (Aura wrapper mode)');
        console.log('📍 Type:', this.omniscriptType);
        console.log('📍 SubType:', this.omniscriptSubType);
        console.log('📍 Lang:', this.omniscriptLang);
        console.log('📍 Version:', this.omniscriptVersion);

        // Register Aura event listeners
        this.registerAuraEventListeners();
    }

    disconnectedCallback() {
        // Clean up event listeners if needed
        this.unregisterAuraEventListeners();
    }

    /**
     * Register listeners for Aura Application Events
     * Note: LWC can listen to Aura events via window event listeners
     */
    registerAuraEventListeners() {
        // Listen for completion event from Aura wrapper
        window.addEventListener('omniscriptcomplete', this.handleAuraComplete.bind(this));
        // Listen for error event from Aura wrapper
        window.addEventListener('omniscripterror', this.handleAuraError.bind(this));

        console.log('✅ Aura event listeners registered');
    }

    unregisterAuraEventListeners() {
        window.removeEventListener('omniscriptcomplete', this.handleAuraComplete.bind(this));
        window.removeEventListener('omniscripterror', this.handleAuraError.bind(this));
    }

    /**
     * Handle OmniScript completion from Aura component
     */
    handleAuraComplete(event) {
        console.log('✅ OmniScript completed (from Aura):', event.detail);

        // Extraire le Case ID de la réponse
        const responseData = event.detail?.detail || event.detail;
        let caseId;

        // Essayer plusieurs chemins possibles
        if (responseData?.CaseId) {
            caseId = responseData.CaseId;
        } else if (responseData?.response?.CaseId) {
            caseId = responseData.response.CaseId;
        } else if (responseData?.data?.CaseId) {
            caseId = responseData.data.CaseId;
        } else if (responseData?.contextId) {
            caseId = responseData.contextId;
        }

        console.log('📍 Extracted Case ID:', caseId);

        // Dispatcher l'événement vers le parent LWC
        this.dispatchEvent(new CustomEvent('complete', {
            detail: { caseId: caseId },
            bubbles: true,
            composed: true
        }));
    }

    /**
     * Handle OmniScript error from Aura component
     */
    handleAuraError(event) {
        console.error('❌ OmniScript error (from Aura):', event.detail);

        // Dispatcher l'événement vers le parent LWC
        this.dispatchEvent(new CustomEvent('error', {
            detail: event.detail,
            bubbles: true,
            composed: true
        }));
    }
}