import { LightningElement, api, track, wire } from 'lwc';
import loadAffiliateFunds from '@salesforce/apex/pLM_LDCT_OrganizationSpeakersHandler.loadAffiliateFunds';

export default class lDCTOrganisationFunds extends LightningElement {
    @api recordId;
    @track funds;
    @track columns = [
        {
            label: 'Name',
            fieldName: 'Link',
            type: 'url',
            sortable: true,
            typeAttributes: { label: { fieldName: 'Name' }, target: '_blank' }
        },
        {
            label: 'Head Portfolio Manager',
            fieldName: 'HeadPortfolioManagerLink',
            type: 'url',
            sortable: true,
            typeAttributes: { label: { fieldName: 'HeadPortfolioManager' }, target: '_blank' }
        },
        { label: 'Linked to a Speaker', fieldName: 'LinkedToASpeaker', sortable: true }
    ];

    @track sortedBy;

    @track sortedDirection = 'asc';

    @wire(loadAffiliateFunds)
    wiredSpeakers({ error, data }) {
        if (data) {

            console.log(data); 
            this.funds = data.map(fund => ({
                ...fund,
                HeadPortfolioManager: fund.Nom_du_gerant_principal__r?.Name,
                HeadPortfolioManagerLink: fund.Nom_du_gerant_principal__r ? '/' + fund.Nom_du_gerant_principal__r?.Id : '',
                Link: '/' + fund.Id, // ADD COMPONENT LINK LATER
                LinkedToASpeaker: fund.Link_Speaker__c ? 'Yes' : 'No'
            }));

        } else if (error) {
            console.error('Error fetching funds:', error);
        }
    }

    handleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.sortedBy = sortedBy;
        this.sortedDirection = sortDirection;
        this.sortData(sortedBy, sortDirection);
    }

    sortData(fieldname, direction) {
        let parseData = JSON.parse(JSON.stringify(this.funds));
        let sortField; 
        
        if(fieldname === 'Link'){
            sortField = 'Name'; 
        }
        else if(fieldname === 'HeadPortfolioManagerLink'){
            sortField = 'HeadPortfolioManager';
        }
        else if(fieldname === ''){
            sortField = 'Name';
        }

        let keyValue = (a) => {
            return a[sortField];
        };
        let isReverse = direction === 'asc' ? 1 : -1;
        parseData.sort((x, y) => {
            x = keyValue(x) ? keyValue(x).toLowerCase() : '';
            y = keyValue(y) ? keyValue(y).toLowerCase() : '';
            return isReverse * ((x > y) - (y > x));
        });
        this.funds = parseData;
    }
}