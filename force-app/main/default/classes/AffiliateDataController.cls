public with sharing class AffiliateDataController {
    /**
     * Retrieves the current user's affiliate record.
     */
    @AuraEnabled(cacheable=true)
    public static LDCT_Affiliate__c getAffiliate() {
        Id userId = UserInfo.getUserId();
        User u = [SELECT CompanyName FROM User WHERE Id = :userId LIMIT 1];
        return [SELECT Id, Name, Founding_Year__c, Date_Of_Entry__c, Headquarters__c,
                       Share_capital_dollar__c, Share_capital_euro__c, Share_capital_date__c,
                       Legal_Description_EN__c, Long_Description_EN__c, Short_Description_EN__c
                FROM LDCT_Affiliate__c WHERE Name = :u.CompanyName LIMIT 1];
    }

    /**
     * Updates an affiliate record.
     */
    @AuraEnabled
    public static void updateAffiliate(LDCT_Affiliate__c affiliate) {
        upsert affiliate;
    }

    /**
     * Calls Verto translation API.
     */
    @AuraEnabled
    public static String translateText(String text, String sourceLang, String targetLang) {
        String token = 'REPLACE_WITH_TOKEN';
        Http h = new Http();
        HttpRequest req = new HttpRequest();
        req.setEndpoint('https://www.verto.finance/api/v2/translation/text');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Bearer ' + token);
        req.setHeader('Content-Type', 'application/json');
        req.setBody(JSON.serialize(new Map<String, Object>{
            'sourceText' => text,
            'sourceLanguage' => sourceLang,
            'targetLanguage' => targetLang
        }));
        HttpResponse res = h.send(req);
        if(res.getStatusCode() >= 200 && res.getStatusCode() < 300) {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            return (String) body.get('translatedText');
        }
        throw new AuraHandledException('Translation error: ' + res.getBody());
    }
}
