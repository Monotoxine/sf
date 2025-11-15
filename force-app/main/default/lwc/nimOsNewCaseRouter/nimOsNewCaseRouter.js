import { LightningElement, api, wire, track } from 'lwc';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import CASE_OBJECT from '@salesforce/schema/Case';

export default class NimOsNewCaseRouter extends NavigationMixin(LightningElement) {
    
    @api recordId;
    @api recordTypeId;
    
    @track recordTypes = [];
    @track selectedRecordTypeId;
    @track selectedRecordTypeDeveloperName;
    @track showRecordTypeSelection = true;
    @track showItsmFlow = false;
    @track isLoading = true;
    @track error;
    
    NIMOS_SUPPORT_RT_DEVNAME = 'NIM_OS_Support';
    
    @wire(getObjectInfo, { objectApiName: CASE_OBJECT })
    wiredObjectInfo({ error, data }) {
        console.log('🔵 Wire getObjectInfo called');
        this.isLoading = false;
        
        if (data) {
            console.log('✅ ObjectInfo data received:', data);
            this.processCaseObjectInfo(data);
        } else if (error) {
            console.error('❌ ObjectInfo error:', error);
            this.error = 'Error loading Record Types: ' + this.reduceErrors(error);
            this.showErrorToast('Error', this.error);
        }
    }
    
    processCaseObjectInfo(data) {
        console.log('🔵 processCaseObjectInfo called');
        const rtMap = data.recordTypeInfos;
        console.log('📋 RecordTypeInfos:', rtMap);
        
        this.recordTypes = Object.keys(rtMap)
            .filter(rtId => {
                const rt = rtMap[rtId];
                return rt.available && !rt.master;
            })
            .map(rtId => {
                const rt = rtMap[rtId];
                return {
                    id: rtId,
                    name: rt.name,
                    developerName: rt.name.replace(/\s+/g, '_'),
                    description: `Create a ${rt.name} case`
                };
            });
        
        console.log('✅ Processed recordTypes:', this.recordTypes);
        
        if (this.recordTypes.length === 1) {
            console.log('ℹ️ Only 1 RT available, auto-selecting');
            this.selectedRecordTypeId = this.recordTypes[0].id;
            this.selectedRecordTypeDeveloperName = this.recordTypes[0].developerName;
        }
    }
    
    handleRecordTypeSelection(event) {
        console.log('🔵 handleRecordTypeSelection called');
        console.log('📍 Event:', event);
        console.log('📍 currentTarget:', event.currentTarget);
        
        const rtId = event.currentTarget.dataset.id;
        const rtDevName = event.currentTarget.dataset.devname;
        
        console.log('📍 Selected RT ID:', rtId);
        console.log('📍 Selected RT DevName:', rtDevName);
        
        this.selectedRecordTypeId = rtId;
        this.selectedRecordTypeDeveloperName = rtDevName;
        
        console.log('✅ State updated:', {
            selectedRecordTypeId: this.selectedRecordTypeId,
            selectedRecordTypeDeveloperName: this.selectedRecordTypeDeveloperName
        });
        
        this.updateSelectedClass(rtId);
    }
    
    updateSelectedClass(selectedId) {
        console.log('🔵 updateSelectedClass called with:', selectedId);
        const options = this.template.querySelectorAll('.record-type-option');
        console.log('📍 Found options:', options.length);
        
        options.forEach(option => {
            if (option.dataset.id === selectedId) {
                option.classList.add('selected');
                console.log('✅ Added selected class to:', selectedId);
            } else {
                option.classList.remove('selected');
            }
        });
    }
    
    handleNext() {
        console.log('🔵 🔵 🔵 handleNext called!');
        console.log('📍 selectedRecordTypeId:', this.selectedRecordTypeId);
        console.log('📍 selectedRecordTypeDeveloperName:', this.selectedRecordTypeDeveloperName);
        console.log('📍 NIMOS_SUPPORT_RT_DEVNAME:', this.NIMOS_SUPPORT_RT_DEVNAME);
        
        if (!this.selectedRecordTypeId) {
            console.log('❌ No RT selected');
            this.showErrorToast('Error', 'Please select a Record Type');
            return;
        }
        
        console.log('🔍 Comparing:', this.selectedRecordTypeDeveloperName, '===', this.NIMOS_SUPPORT_RT_DEVNAME);
        
        if (this.selectedRecordTypeDeveloperName === this.NIMOS_SUPPORT_RT_DEVNAME) {
            console.log('✅ NIM-OS Support selected → Showing ITSM Flow');
            this.showRecordTypeSelection = false;
            this.showItsmFlow = true;
            console.log('📍 showItsmFlow:', this.showItsmFlow);
        } else {
            console.log('✅ Other RT selected → Navigating to standard creation');
            this.navigateToStandardCaseCreation();
        }
    }
    
    navigateToStandardCaseCreation() {
        console.log('🔵 navigateToStandardCaseCreation called');
        console.log('📍 Navigating with RT ID:', this.selectedRecordTypeId);
        
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Case',
                actionName: 'new'
            },
            state: {
                recordTypeId: this.selectedRecordTypeId,
                nooverride: '1'
            }
        });
        
        console.log('✅ Navigation called');
    }
    
    handleCaseCreated(event) {
        console.log('🔵 handleCaseCreated called');
        const caseId = event.detail.caseId;
        console.log('📍 Case ID:', caseId);
        
        this.showSuccessToast('Success', 'Case created successfully');
        
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: caseId,
                objectApiName: 'Case',
                actionName: 'view'
            }
        });
    }
    
    handleCancel() {
        console.log('🔵 handleCancel called');
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Case',
                actionName: 'home'
            }
        });
    }
    
    showSuccessToast(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: 'success'
            })
        );
    }
    
    showErrorToast(title, message) {
        this.dispatchEvent(
            new ShowToastEvent({
                title: title,
                message: message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }
    
    reduceErrors(errors) {
        if (!Array.isArray(errors)) {
            errors = [errors];
        }
        
        return errors
            .filter(error => !!error)
            .map(error => {
                if (Array.isArray(error.body)) {
                    return error.body.map(e => e.message);
                } else if (error.body && typeof error.body.message === 'string') {
                    return error.body.message;
                } else if (typeof error.message === 'string') {
                    return error.message;
                }
                return 'Unknown error';
            })
            .reduce((prev, curr) => prev + ', ' + curr, '')
            .substring(2);
    }
    
    get hasRecordTypes() {
        return this.recordTypes && this.recordTypes.length > 0;
    }
    
    get showSpinner() {
        return this.isLoading;
    }
    
    get showError() {
        return !!this.error;
    }
    
    get isNextDisabled() {
        const disabled = !this.selectedRecordTypeId;
        console.log('🔍 isNextDisabled:', disabled, '| selectedRecordTypeId:', this.selectedRecordTypeId);
        return disabled;
    }
}