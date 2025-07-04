public with sharing class pLM_LDCT_OrganizationSpeakersHandler {

    @AuraEnabled(cacheable=true)
    public static List<Speaker__c> loadNarrativeProjectSpeakers(){
        try {
            Id userId = userInfo.getUserId();
            User currentUser = [SELECT Id, CompanyName FROM User WHERE Id=:userId];
            List<Speaker__c> speakers = [SELECT Id, Full_Name__c, Title_EN__c, Title_FR__c, Link_fund__c FROM Speaker__c WHERE Company__c = :currentUser.CompanyName]; 	
            return speakers; 
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static LDCT_Speaker__c loadNarrativeProjectSpeaker(Id speakerId, Id projectId){
        try {
            LDCT_Speaker__c speaker = [SELECT FirstName__c, Name, Began_Investment_Career__c, Joined_Firm__c, CFA_Charterholder__c, Caia__c, Phd__c, Email__c, Phone__c, Title_EN__c, Education__c, Bio_EN__c, Experience__c, Ipad_Picture_URL__c FROM LDCT_Speaker__c WHERE Speaker__c=:speakerId LIMIT 1]; 	
            return speaker; 
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<Produit__c> loadAffiliateFunds(){
        try {
            Id userId = userInfo.getUserId();
            User currentUser = [SELECT Id, CompanyName FROM User WHERE Id=:userId];
            List<Produit__c> products = [SELECT Id, Name, Nom_du_gerant_principal__c, Nom_du_gerant_principal__r.Name, Link_Speaker__c FROM Produit__c WHERE Clos__c = false AND Affiliate__c = :currentUser.CompanyName LIMIT 500]; 	
            return products; 
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    //Return the Affiliate for the user logged
    @AuraEnabled(cacheable=true)
    public static LDCT_Affiliate__c loadAffiliateUser() {
        try {
            Id userId = UserInfo.getUserId();
            User currentUser = [SELECT Id, CompanyName FROM User WHERE Id = :userId LIMIT 1];

            // Query LDCT_Affiliate__c
            List<LDCT_Affiliate__c> ldct_affiliates = [SELECT Id, Name, Founding_Year__c, Date_Of_Entry__c, Headquarters__c, Share_capital_dollar__c, Share_capital_euro__c, Share_capital_date__c, Legal_Description_EN__c, Long_Description_EN__c, Short_Description_EN__c FROM LDCT_Affiliate__c WHERE Name = :currentUser.CompanyName LIMIT 1];

            if (!ldct_affiliates.isEmpty()) { // Check if the list is not empty
                LDCT_Affiliate__c ldct_affiliate = ldct_affiliates[0];
                return ldct_affiliate;
            } else {
                // Query Affiliate__c
                List<Affiliate__c> affiliates = [SELECT Id, Name, Founding_Year__c, Date_Of_Entry__c, Headquarters__c, Share_capital_dollar__c, Share_capital_euro__c, Share_capital_date__c, Legal_Description_EN__c, Long_Description_EN__c, Short_Description_EN__c FROM Affiliate__c WHERE Name = :currentUser.CompanyName LIMIT 1];
                if (!affiliates.isEmpty()) { // Check if the list is not empty
                    Affiliate__c affiliate = affiliates[0];
                    LDCT_Affiliate__c ldct_affiliate = new LDCT_Affiliate__c(
                        Name = affiliate.Name,
                        Founding_Year__c = affiliate.Founding_Year__c,
                        Date_Of_Entry__c = affiliate.Date_Of_Entry__c,
                        Headquarters__c = affiliate.Headquarters__c,
                        Share_capital_dollar__c = affiliate.Share_capital_dollar__c,
                        Share_capital_euro__c = affiliate.Share_capital_euro__c,
                        Share_capital_date__c = affiliate.Share_capital_date__c,
                        Legal_Description_EN__c = affiliate.Legal_Description_EN__c,
                        Long_Description_EN__c = affiliate.Long_Description_EN__c,
                        Short_Description_EN__c = affiliate.Short_Description_EN__c
                    );
                    return ldct_affiliate;
                }
            }
            return null; // Return null if no records are found
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    //Create new record for the LDCT_Affiliate
    @AuraEnabled
    public static void createAffiliateRecord(Name Name, Decimal foundingYear, Date dateOfEntry, String headquarters, Decimal shareCapitalDol, Decimal shareCapitalEur, Date shareCapitalDate, String legalDescriptionEn, String longDescriptionEn, String shortDescriptionEn) {
        Id userId = userInfo.getUserId();
        User currentUser = [SELECT Id, CompanyName FROM User WHERE Id=:userId];
        LDCT_Affiliate__c affiliate = new LDCT_Affiliate__c(
            Name = currentUser.CompanyName,
            Founding_Year__c = foundingYear,
            Date_Of_Entry__c = dateOfEntry,
            Headquarters__c = headquarters,
            Share_capital_dollar__c = shareCapitalDol,
            Share_capital_euro__c = shareCapitalEur,
            Share_capital_date__c = shareCapitalDate,
            Legal_Description_EN__c = legalDescriptionEn,
            Long_Description_EN__c = longDescriptionEn,
            Short_Description_EN__c = shortDescriptionEn
        );
        List<LDCT_Affiliate__c> ldct_affiliates = [SELECT Id, Name, Founding_Year__c, Date_Of_Entry__c, Headquarters__c, Share_capital_dollar__c, Share_capital_euro__c, Share_capital_date__c, Legal_Description_EN__c, Long_Description_EN__c, Short_Description_EN__c FROM LDCT_Affiliate__c WHERE Name = :currentUser.CompanyName LIMIT 1];
        if (!ldct_affiliates.isEmpty()) { // Check if the list is not empty
            affiliate.Id = ldct_affiliates[0].Id;
        }
        upsert affiliate;
    }

    @AuraEnabled
    public static void createSpeaker(String firstName, String lastName, Decimal yearBeganInvestmentCareer, 
                                       Decimal yearJoinedTheGroup, Boolean cfaChartHolder, Boolean cefaHolder, Boolean pHd,
                                       String email, String phone, String titleEN, String educationEN, String biographyEN, String experienceEN, String publicPicture){

                                        
        if(firstName == null){
            throw new AuraHandledException('First name is required.');
        } 
        
        if(lastName == null){
            throw new AuraHandledException('Last name is required.');
        } 

        try {
            Id userId = userInfo.getUserId();
            User currentUser = [SELECT Id, CompanyName FROM User WHERE Id=:userId];
            LDCT_Speaker__c ldctSpeaker = new LDCT_Speaker__c(
                FirstName__c = firstName,
                Name = lastName,
                Began_Investment_Career__c = yearBeganInvestmentCareer,
                Joined_Firm__c = yearJoinedTheGroup,
                CFA_Charterholder__c = cfaChartHolder != null ? true : false,
                Caia__c = cefaHolder != null ? true : false,
                Phd__c = pHd != null ? true : false,
                Email__c = email, 
                Phone__c = phone,
                Title_EN__c = titleEN,
                Education__c = educationEN,
                Bio_EN__c = biographyEN,
                Experience__c = experienceEN,
                Ipad_Picture_URL__c	= publicPicture
            );

            insert ldctSpeaker;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    @AuraEnabled
    public static void updateLDCTSpeaker(Id speakerId, String firstName, String lastName, Decimal yearBeganInvestmentCareer, 
                                       Decimal yearJoinedTheGroup, Boolean cfaChartHolder, Boolean cefaHolder, Boolean pHd,
                                       String email, String phone, String titleEN, String educationEN, String biographyEN, String experienceEN, String publicPicture){
        if(firstName == null){
            throw new AuraHandledException('First name is required.');
        } 

        if(lastName == null){
            throw new AuraHandledException('Last name is required.');
        } 

        try {
            LDCT_Speaker__c ldctSpeaker = [SELECT FirstName__c, Name, Began_Investment_Career__c, Joined_Firm__c, CFA_Charterholder__c, Caia__c, Phd__c, Email__c, Phone__c, Title_EN__c, Education__c, Bio_EN__c, Experience__c, Ipad_Picture_URL__c FROM LDCT_Speaker__c WHERE Speaker__c = :speakerId LIMIT 1]; 
            ldctSpeaker.FirstName__c = firstName;
            ldctSpeaker.Name = lastName;
            ldctSpeaker.Began_Investment_Career__c = yearBeganInvestmentCareer; 
            ldctSpeaker.Joined_Firm__c = yearJoinedTheGroup; 
            ldctSpeaker.CFA_Charterholder__c = cfaChartHolder; 
            ldctSpeaker.Caia__c = cefaHolder; 
            ldctSpeaker.Phd__c = pHd; 
            ldctSpeaker.Email__c = email; 
            ldctSpeaker.Phone__c = phone; 
            ldctSpeaker.Title_EN__c = titleEN; 
            ldctSpeaker.Education__c = educationEN; 
            ldctSpeaker.Bio_EN__c = biographyEN; 
            ldctSpeaker.Experience__c = experienceEN; 
            ldctSpeaker.Ipad_Picture_URL__c	= publicPicture;
            update ldctSpeaker;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<LDCT_speaker_and_product__c> loadSpeaker_ProductByProjectId(string projectId){
        try {
           List<LDCT_speaker_and_product__c> speakerProducts = [SELECT Id, Speaker__r.Name, Title_ptf__c, Product__r.Name,Manage_the_fund_since_Full_date__c,End_date__c  FROM LDCT_speaker_and_product__c WHERE LDCT_Project__c = :projectId LIMIT 1]; 	
            return speakerProducts; 
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}