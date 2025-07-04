import { createElement } from 'lwc';
import AffiliateDataUpdate from 'c/affiliateDataUpdate';
import getAffiliate from '@salesforce/apex/AffiliateDataController.getAffiliate';
import updateAffiliate from '@salesforce/apex/AffiliateDataController.updateAffiliate';

jest.mock('@salesforce/apex/AffiliateDataController.getAffiliate', () => {
    return { default: jest.fn() };
}, { virtual: true });

jest.mock('@salesforce/apex/AffiliateDataController.updateAffiliate', () => {
    return { default: jest.fn() };
}, { virtual: true });

describe('c-affiliate-data-update', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('opens modal on translate click', async () => {
        getAffiliate.mockResolvedValue({});
        const element = createElement('c-affiliate-data-update', {
            is: AffiliateDataUpdate
        });
        document.body.appendChild(element);
        await Promise.resolve();
        const button = element.shadowRoot.querySelector('lightning-button');
        button.click();
        await Promise.resolve();
        expect(element.showModal).toBe(true);
    });
});
