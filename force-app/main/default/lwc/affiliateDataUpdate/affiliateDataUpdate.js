import { LightningElement, track, wire } from 'lwc';
import getAffiliate from '@salesforce/apex/AffiliateDataController.getAffiliate';
import updateAffiliate from '@salesforce/apex/AffiliateDataController.updateAffiliate';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AffiliateDataUpdate extends LightningElement {
    @track affiliate = {};
    @track originalShareCapital;
    @track originalShareCapitalDate;
    @track showModal = false;

    @wire(getAffiliate)
    wiredAffiliate({ error, data }) {
        if (data) {
            this.affiliate = { ...data };
            this.originalShareCapital = data.Share_capital_euro__c;
            this.originalShareCapitalDate = data.Share_capital_date__c;
        } else if (error) {
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Error', message: error.body.message, variant: 'error' })
            );
        }
    }

    handleChange(event) {
        this.affiliate = { ...this.affiliate, [event.target.name]: event.target.value };
    }

    get shareCapitalChanged() {
        return (
            this.affiliate.Share_capital_euro__c !== this.originalShareCapital ||
            this.affiliate.Share_capital_date__c !== this.originalShareCapitalDate
        );
    }

    handleSave() {
        updateAffiliate({ affiliate: this.affiliate })
            .then(() => {
                this.dispatchEvent(
                    new ShowToastEvent({ title: 'Saved', message: 'Affiliate updated', variant: 'success' })
                );
            })
            .catch((err) => {
                this.dispatchEvent(
                    new ShowToastEvent({ title: 'Error', message: err.body.message, variant: 'error' })
                );
            });
    }

    openTranslate() {
        this.showModal = true;
    }

    closeModal() {
        this.showModal = false;
    }
}
