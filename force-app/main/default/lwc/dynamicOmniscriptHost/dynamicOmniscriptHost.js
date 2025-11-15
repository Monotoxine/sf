import { LightningElement, api, track } from 'lwc';

export default class DynamicOmniscriptHost extends LightningElement {
    
    @api omniscriptType;
    @api omniscriptSubType;
    @api omniscriptLang;
    @api omniscriptVersion;
    
    @track layoutData;
    
    connectedCallback() {
        console.log('🔵 OmniScript Host connected');
        console.log('📍 Type:', this.omniscriptType);
        console.log('📍 SubType:', this.omniscriptSubType);
        console.log('📍 Lang:', this.omniscriptLang);
        console.log('📍 Version:', this.omniscriptVersion);
        
        // Préparer les données pour l'OmniScript
        this.layoutData = JSON.stringify({
            prefill: {},
            seed: true,
            message: {}
        });
    }
    
    handleOmniScriptComplete(event) {
        console.log('✅ OmniScript completed:', event.detail);
        
        // Extraire le Case ID de la réponse
        const responseData = event.detail;
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
        
        // Dispatcher l'événement vers le parent
        this.dispatchEvent(new CustomEvent('complete', {
            detail: { caseId: caseId },
            bubbles: true,
            composed: true
        }));
    }
    
    handleOmniScriptError(event) {
        console.error('❌ OmniScript error:', event.detail);
    }
    
    handleOmniScriptStep(event) {
        console.log('🔵 OmniScript step changed:', event.detail);
    }
}