import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class LdctStandardModel extends LightningModal  {
    @api content;
    @api headerTitle; 
    @api buttons; 
    @api yesActionCallback;

    handleYes() {
        if(this.yesActionCallback != null){
            this.yesActionCallback(); 
        }

        this.close('Yes');
    }

    handleNo() {
        this.close('No');
    }
}