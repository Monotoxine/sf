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
            // Modules: Module__c has Master-Detail to Application__c
            List<Provisioned_Application__c> provisionedApps = [
                SELECT Id,
                       Contract__c,
                       Application__c,
                       Application__r.Id,
                       Application__r.Name,
                       Application__r.Description__c,
                       (SELECT Id, Name, Description__c
                        FROM Modules__r
                        ORDER BY Name)
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

                // Build modules list for this application
                List<ModuleDTO> modules = new List<ModuleDTO>();
                for (Module__c mod : pa.Modules__r) {
                    ModuleDTO moduleDto = new ModuleDTO();
                    moduleDto.id = mod.Id;
                    moduleDto.name = mod.Name;
                    moduleDto.description = mod.Description__c;
                    modules.add(moduleDto);
                }

                // Store modules by application name
                if (!response.modulesByApplication.containsKey(appName)) {
                    response.modulesByApplication.put(appName, modules);
                } else {
                    // Merge modules if same application appears multiple times
                    List<ModuleDTO> existingModules = response.modulesByApplication.get(appName);
                    existingModules.addAll(modules);
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
