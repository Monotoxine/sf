/**
 * @description Decode seedData for OmniScripts
 * @author Claude
 * @date 2025-11-18
 */
public with sharing class OmniScriptSeedDecoder {

    /**
     * Decode URL-encoded JSON seedData
     * @param encodedSeedData The encoded seed data from omniscript__seedData
     * @return Map<String, Object> Decoded data map
     */
    @AuraEnabled
    public static Map<String, Object> decodeSeedData(String encodedSeedData) {
        try {
            if (String.isBlank(encodedSeedData)) {
                return new Map<String, Object>();
            }

            // Decode URI component
            String decodedJson = EncodingUtil.urlDecode(encodedSeedData, 'UTF-8');

            // Parse JSON
            Map<String, Object> seedData = (Map<String, Object>) JSON.deserializeUntyped(decodedJson);

            System.debug('🔓 Decoded seed data: ' + seedData);

            return seedData;

        } catch (Exception e) {
            System.debug('❌ Error decoding seed data: ' + e.getMessage());
            throw new AuraHandledException('Failed to decode seed data: ' + e.getMessage());
        }
    }
}
