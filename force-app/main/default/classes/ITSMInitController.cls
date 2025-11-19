/**
 * @description Contrôleur Apex pour l'IP Init ITSM
 * Récupère tous les services disponibles pour l'utilisateur courant
 * @author Mouhamadoune
 * @date 2025
 */
public with sharing class ITSMInitController {
    
    private static final String ERROR_NO_DIVISION = 'User has no Division assigned';
    private static final String ERROR_NO_ACCOUNT = 'No Account found for this user';
    private static final String ERROR_NO_SERVICES = 'No services found for this account';
    
    /**
     * @description Récupère toutes les données ITSM pour l'utilisateur courant
     * @return ResponseDTO contenant categories, subcategories, services et setups
     */
    @AuraEnabled(cacheable=true)
    public static ResponseDTO getITSMInitData() {
        try {
            // 1. Get Current User with Division
            User currentUser = getCurrentUser();
            
            // 2. Get Account for this Division
            Account userAccount = getAccountForDivision(currentUser.Division__c);
            
            // 3. Get All Services for this Account (SOQL CORRIGÉE)
            List<Product2> services = getServicesForAccount(userAccount.Id);
            
            // 4. Build and return DTO
            return buildResponseDTO(services, currentUser, userAccount);
            
        } catch (Exception e) {
            throw new AuraHandledException('Error in ITSM Init: ' + e.getMessage());
        }
    }
    
    /**
     * @description Récupère l'utilisateur courant avec sa Division
     */
    private static User getCurrentUser() {
        Id userId = UserInfo.getUserId();
        
        List<User> users = [
            SELECT Id, Name, Division__c 
            FROM User 
            WHERE Id = :userId 
            LIMIT 1
        ];
        
        if (users.isEmpty() || String.isBlank(users[0].Division__c)) {
            throw new AuraHandledException(ERROR_NO_DIVISION);
        }
        
        return users[0];
    }
    
    /**
     * @description Récupère le compte associé à la Division
     */
    private static Account getAccountForDivision(String division) {
        List<Account> accounts = [
            SELECT Id, Name
            FROM Account 
            WHERE Legal_Name__c = :division 
            LIMIT 1
        ];
        
        if (accounts.isEmpty()) {
            throw new AuraHandledException(ERROR_NO_ACCOUNT);
        }
        
        return accounts[0];
    }
    
    /**
     * @description Récupère tous les services pour un Account donné
     * Utilise la SOQL corrigée avec Account_Service_Relationship__c
     */
    private static List<Product2> getServicesForAccount(Id accountId) {
        List<Product2> services = [
            SELECT Id,
                   Name,
                   Family,
                   SubCategory__c,
                   (
                       SELECT Id,
                              RelatedSupportForm__c,
                              RelatedChangeForm__c,
                              QueueForAssignment__c
                       FROM Service_Setups__r
                   )
            FROM Product2
            WHERE Id IN (
                SELECT Service__c
                FROM Account_Service_Relationship__c
                WHERE Account__c = :accountId
            )
            AND IsActive = true
            ORDER BY Family, SubCategory__c, Name
        ];
        
        if (services.isEmpty()) {
            throw new AuraHandledException(ERROR_NO_SERVICES);
        }
        
        return services;
    }
    
    /**
     * @description Construit le DTO de réponse à partir des services
     */
    private static ResponseDTO buildResponseDTO(
        List<Product2> services, 
        User currentUser,
        Account userAccount
    ) {
        ResponseDTO response = new ResponseDTO();
        response.userDivision = currentUser.Division__c;
        response.accountId = userAccount.Id;
        response.accountName = userAccount.Name;
        
        Set<String> categorySet = new Set<String>();
        Map<String, Set<String>> subcatMap = new Map<String, Set<String>>();
        
        for (Product2 svc : services) {
            String category = svc.Family; // Family = Category
            String subcat = svc.SubCategory__c;
            
            // Skip if missing critical fields
            if (String.isBlank(category) || String.isBlank(subcat)) {
                continue;
            }
            
            // 1. Build Categories List
            if (!categorySet.contains(category)) {
                categorySet.add(category);
                response.categories.add(category);
            }
            
            // 2. Build Subcategories Map
            if (!subcatMap.containsKey(category)) {
                subcatMap.put(category, new Set<String>());
            }
            subcatMap.get(category).add(subcat);
            
            // 3. Build Services Map (key = category||subcategory)
            String key = category + '||' + subcat;
            if (!response.servicesByCatSubcat.containsKey(key)) {
                response.servicesByCatSubcat.put(key, new List<ServiceDTO>());
            }
            
            ServiceDTO serviceDTO = new ServiceDTO();
            serviceDTO.id = svc.Id;
            serviceDTO.name = svc.Name;
            serviceDTO.category = category;
            serviceDTO.subcategory = subcat;
            response.servicesByCatSubcat.get(key).add(serviceDTO);
            
            // 4. Build Service Setups List
            for (Service_Setup__c setup : svc.Service_Setups__r) {
                ServiceSetupDTO setupDTO = new ServiceSetupDTO();
                setupDTO.id = setup.Id;
                setupDTO.serviceId = svc.Id;
                setupDTO.serviceName = svc.Name;
                setupDTO.relatedSupportForm = setup.RelatedSupportForm__c;
                setupDTO.relatedChangeForm = setup.RelatedChangeForm__c;
                setupDTO.queueForAssignment=setup.QueueForAssignment__c;
                response.serviceSetups.add(setupDTO);
            }
        }
        
        // 5. Convert subcategory Sets to Lists (for JSON serialization)
        for (String cat : subcatMap.keySet()) {
            List<String> subcatList = new List<String>(subcatMap.get(cat));
            subcatList.sort(); // Tri alphabétique
            response.subcategoriesByCategory.put(cat, subcatList);
        }
        
        // 6. Sort categories alphabetically
        response.categories.sort();
        
        return response;
    }
    
    // ========================================================================
    // INNER CLASSES - DTOs
    // ========================================================================
    
    /**
     * @description DTO principal de réponse
     */
    public class ResponseDTO {
        @AuraEnabled public List<String> categories;
        @AuraEnabled public Map<String, List<String>> subcategoriesByCategory;
        @AuraEnabled public Map<String, List<ServiceDTO>> servicesByCatSubcat;
        @AuraEnabled public List<ServiceSetupDTO> serviceSetups;
        @AuraEnabled public String userDivision;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
        
        public ResponseDTO() {
            this.categories = new List<String>();
            this.subcategoriesByCategory = new Map<String, List<String>>();
            this.servicesByCatSubcat = new Map<String, List<ServiceDTO>>();
            this.serviceSetups = new List<ServiceSetupDTO>();
        }
    }
    
    /**
     * @description DTO pour un service (Product2)
     */
    public class ServiceDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String category;
        @AuraEnabled public String subcategory;
    }
    
    /**
     * @description DTO pour un Service Setup
     */
    public class ServiceSetupDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String serviceId;
        @AuraEnabled public String serviceName;
        @AuraEnabled public String relatedSupportForm;
        @AuraEnabled public String relatedChangeForm;
        @AuraEnabled public String queueForAssignment;

    }
}