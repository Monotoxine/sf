import { createElement } from 'lwc';
import AffiliateTranslationModal from 'c/affiliateTranslationModal';
import translateText from '@salesforce/apex/AffiliateDataController.translateText';

jest.mock('@salesforce/apex/AffiliateDataController.translateText', () => {
    return { default: jest.fn() };
}, { virtual: true });

describe('c-affiliate-translation-modal', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('calls apex on translate', async () => {
        translateText.mockResolvedValue('Bonjour');
        const element = createElement('c-affiliate-translation-modal', {
            is: AffiliateTranslationModal
        });
        element.descriptions = { Legal_Description_EN__c: 'Hello' };
        document.body.appendChild(element);
        await Promise.resolve();
        const button = element.shadowRoot.querySelector('lightning-button');
        button.click();
        await Promise.resolve();
        expect(translateText).toHaveBeenCalled();
    });
});
