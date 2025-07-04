import { LightningElement, api, track } from 'lwc';

export default class lDCTGenericScreensComponent extends LightningElement {
    @api badgeLabel = 'Affiliate Data Update'; // Default Label
    @api objectApiName = 'LDCT_Affiliate__c'; // Default Object API Name
    @api blockCount = 1; // Default to one block
    @api gridSize = "lds-col slds-size_5-of-12";

    @track isBlock1Visible = false;
    @track isBlock2Visible = false;
    @track isBlock3Visible = false;

    connectedCallback() {
        this.setBlockVisibility();
    }

    setBlockVisibility() {
        this.isBlock1Visible = this.blockCount >= 1;
        this.isBlock2Visible = this.blockCount >= 2;
        this.isBlock3Visible = this.blockCount >= 3;

        if(!this.isBlock3Visible){
            this.gridSize = "lds-col slds-size_1-of-2";
        }
    }
}