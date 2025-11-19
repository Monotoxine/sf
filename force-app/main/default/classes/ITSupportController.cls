/**
 * @description Controller for IT Support Case creation flow
 * Provides Application/Module data based on user's Account and active Contracts
 *
 * @author Claude
 * @date 2025-11-19
 */
public with sharing class ITSupportController {

    /**
     * Get IT Support data for the current user
     * Returns applications and modules based on active contracts
     *
     * @return ResponseDTO containing applications, modules, and context
     */
    @AuraEnabled(cacheable=true)
    public static ResponseDTO getITSupportData() {
        try {
            ResponseDTO response = new ResponseDTO();

            // 1. Get current user and Division
            User currentUser = [
                SELECT Id, Division__c
                FROM User
                WHERE Id = :UserInfo.getUserId()
                LIMIT 1
            ];

            if (String.isBlank(currentUser.Division__c)) {
                throw new AuraHandledException('User has no Division assigned');
            }

            response.userDivision = currentUser.Division__c;
            System.debug('🔵 User Division: ' + response.userDivision);

            // 2. Get Account matching Division
            List<Account> accounts = [
                SELECT Id, Name
                FROM Account
                WHERE Legal_Name__c = :currentUser.Division__c
                LIMIT 1
            ];

            if (accounts.isEmpty()) {
                throw new AuraHandledException('No Account found for Division: ' + currentUser.Division__c);
            }

            Account userAccount = accounts[0];
            response.accountId = userAccount.Id;
            response.accountName = userAccount.Name;
            System.debug('✅ Account found: ' + response.accountName);

            // 3. Get active Contracts for this Account
            List<Contract> activeContracts = [
                SELECT Id, ContractNumber, Status
                FROM Contract
                WHERE AccountId = :userAccount.Id
                AND Status = 'Activated'
            ];

            if (activeContracts.isEmpty()) {
                throw new AuraHandledException('No active Contracts found for Account: ' + userAccount.Name);
            }

            System.debug('📦 Found ' + activeContracts.size() + ' active contracts');

            // Extract Contract IDs
            Set<Id> contractIds = new Set<Id>();
            for (Contract c : activeContracts) {
                contractIds.add(c.Id);
            }

            // 4. Get Provisioned Applications with Applications and Modules
            // Junction: Provisioned_Application__c links Contract to Application__c
            // Module__c is a lookup field on Provisioned_Application__c
            List<Provisioned_Application__c> provisionedApps = [
                SELECT Id,
                       Contract__c,
                       Application__c,
                       Application__r.Id,
                       Application__r.Name,
                       Application__r.Description__c,
                       Module__c,
                       Module__r.Id,
                       Module__r.Name,
                       Module__r.Description__c
                FROM Provisioned_Application__c
                WHERE Contract__c IN :contractIds
                AND Application__c != null
                ORDER BY Application__r.Name
            ];

            if (provisionedApps.isEmpty()) {
                throw new AuraHandledException('No Applications provisioned for active Contracts');
            }

            System.debug('📦 Found ' + provisionedApps.size() + ' provisioned applications');

            // 5. Build structured data
            // Group modules by application name
            response.applications = new List<String>();
            response.modulesByApplication = new Map<String, List<ModuleDTO>>();

            Set<String> uniqueApplications = new Set<String>();

            for (Provisioned_Application__c pa : provisionedApps) {
                String appName = pa.Application__r.Name;

                // Add application to list (deduplicate)
                if (!uniqueApplications.contains(appName)) {
                    uniqueApplications.add(appName);
                    response.applications.add(appName);
                }

                // Add module to this application (if module exists)
                if (pa.Module__c != null) {
                    ModuleDTO moduleDto = new ModuleDTO();
                    moduleDto.id = pa.Module__r.Id;
                    moduleDto.name = pa.Module__r.Name;
                    moduleDto.description = pa.Module__r.Description__c;

                    // Store module by application name
                    if (!response.modulesByApplication.containsKey(appName)) {
                        response.modulesByApplication.put(appName, new List<ModuleDTO>());
                    }

                    // Check for duplicates before adding
                    List<ModuleDTO> existingModules = response.modulesByApplication.get(appName);
                    Boolean isDuplicate = false;
                    for (ModuleDTO existing : existingModules) {
                        if (existing.id == moduleDto.id) {
                            isDuplicate = true;
                            break;
                        }
                    }

                    if (!isDuplicate) {
                        existingModules.add(moduleDto);
                    }
                }
            }

            response.applications.sort();

            System.debug('✅ Response built: ' + response.applications.size() + ' applications');
            return response;

        } catch (Exception e) {
            System.debug('❌ Error in getITSupportData: ' + e.getMessage());
            System.debug('❌ Stack trace: ' + e.getStackTraceString());
            throw new AuraHandledException('Error loading IT Support data: ' + e.getMessage());
        }
    }

    /**
     * Response DTO
     */
    public class ResponseDTO {
        @AuraEnabled public List<String> applications;
        @AuraEnabled public Map<String, List<ModuleDTO>> modulesByApplication;
        @AuraEnabled public String userDivision;
        @AuraEnabled public String accountId;
        @AuraEnabled public String accountName;
    }

    /**
     * Module DTO
     */
    public class ModuleDTO {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String description;
    }
}
