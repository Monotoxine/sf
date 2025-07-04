import { LightningElement, api, track, wire } from 'lwc';
import loadNarrativeProjectSpeakers from '@salesforce/apex/pLM_LDCT_OrganizationSpeakersHandler.loadNarrativeProjectSpeakers';

export default class PLMLDCTOrganizationSpeakers extends LightningElement {
    @api recordId;
    @track speakers;
    @track columns = [
        { label: 'Name', fieldName: 'Full_Name__c', sortable: true },
        { label: 'Title', fieldName: 'Title_EN__c', sortable: true },
        { label: 'Linked to a Fund', fieldName: 'Link_fund__c', sortable: false }
    ];

    @track sortedBy;

    @track sortedDirection = 'asc';

    @wire(loadNarrativeProjectSpeakers)
    wiredSpeakers({ error, data }) {
        if (data) {
            this.speakers = data;
        } else if (error) {
            console.error('Error fetching speakers:', error);
        }
    }

    viewSpeaker(row) {
        console.log('View speaker:', row.Id);
    }

    handleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.sortedBy = sortedBy;
        this.sortedDirection = sortDirection;
        this.sortData(sortedBy, sortDirection);
    }

    sortData(fieldname, direction) {
        let parseData = JSON.parse(JSON.stringify(this.speakers));
        let keyValue = (a) => {
            return a[fieldname];
        };
        let isReverse = direction === 'asc' ? 1 : -1;
        parseData.sort((x, y) => {
            x = keyValue(x) ? keyValue(x) : '';
            y = keyValue(y) ? keyValue(y) : '';
            return isReverse * ((x > y) - (y > x));
        });
        this.speakers = parseData;
    }
}