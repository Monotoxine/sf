import { LightningElement, api, track, wire } from 'lwc';
import loadNarrativeProjectSpeakers from '@salesforce/apex/pLM_LDCT_OrganizationSpeakersHandler.loadNarrativeProjectSpeakers';

export default class lDCTOrganizationSpeakers extends LightningElement {
    @api recordId;
    @track speakers;
    @track columns = [
        {
            label: 'Name',
            fieldName: 'Link',
            type: 'url',
            sortable: true,
            typeAttributes: { label: { fieldName: 'Full_Name__c' }, target: '_blank' }
        },
        { label: 'Title', fieldName: 'Title_EN__c', sortable: true },
        { label: 'Linked to a Fund', fieldName: 'Link_fund__c', sortable: true }
    ];

    @track sortedBy;

    @track sortedDirection = 'asc';

    @wire(loadNarrativeProjectSpeakers)
    wiredSpeakers({ error, data }) {
        if (data) {
            this.speakers = data.map(speaker => ({
                ...speaker,
                Link: '/lightning/cmp/c__pLM_LDCT_Screen4ModificationOfSpeaker?c__speakerId='+speaker.Id,
                Link_fund__c: speaker.Link_fund__c ? 'Yes' : 'No'
            }));

        } else if (error) {
            console.error('Error fetching speakers:', error);
        }
    }

    handleSort(event) {
        const { fieldName: sortedBy, sortDirection } = event.detail;
        this.sortedBy = sortedBy;
        this.sortedDirection = sortDirection;
        this.sortData(sortedBy, sortDirection);
    }

    sortData(fieldname, direction) {
        let parseData = JSON.parse(JSON.stringify(this.speakers));
        let sortField = fieldname === 'Link' ? 'Full_Name__c' : fieldname;
        let keyValue = (a) => {
            return a[sortField];
        };
        let isReverse = direction === 'asc' ? 1 : -1;
        parseData.sort((x, y) => {
            x = keyValue(x) ? keyValue(x).toLowerCase() : '';
            y = keyValue(y) ? keyValue(y).toLowerCase() : '';
            return isReverse * ((x > y) - (y > x));
        });
        this.speakers = parseData;
    }
}