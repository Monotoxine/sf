import { LightningElement, api, track } from 'lwc';
import translateText from '@salesforce/apex/AffiliateDataController.translateText';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AffiliateTranslationModal extends LightningElement {
    @api descriptions;
    @track translations = {};
    @track loading = false;

    handleTranslate() {
        this.loading = true;
        const promises = [];
        ['Legal_Description_EN__c', 'Long_Description_EN__c', 'Short_Description_EN__c'].forEach((field) => {
            const text = this.descriptions[field];
            promises.push(
                translateText({ text: text, sourceLang: 'en', targetLang: 'fr' }).then((t) => {
                    this.translations[field] = t;
                })
            );
        });
        Promise.all(promises)
            .catch((err) => {
                this.dispatchEvent(
                    new ShowToastEvent({ title: 'Error', message: err.body.message, variant: 'error' })
                );
            })
            .finally(() => {
                this.loading = false;
            });
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }
}
