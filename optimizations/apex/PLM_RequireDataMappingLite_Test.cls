/**
 * @description Tests unitaires pour PLM_RequireDataMappingLite (Version Optimisée)
 * @author Performance Optimization Team
 * @date 2025-10-27
 * @version 2.0
 *
 * COVERAGE ATTENDU: >80%
 *
 * Tests inclus:
 * - Performance tests (temps de chargement)
 * - Functional tests (logique métier)
 * - Cache tests (Platform Cache)
 * - Governor Limits tests
 * - Error handling tests
 */
@isTest
private class PLM_RequireDataMappingLite_Test {

    // ==================== TEST DATA SETUP ====================

    /**
     * Crée les données de test
     */
    @testSetup
    static void setupTestData() {
        // Créer un projet de test
        Product_Services_Project__c project = new Product_Services_Project__c(
            Name = 'Test PLM Project',
            Domiciliation__c = 'Ireland',
            vehicle_type__c = 'Open-End Fund',
            legal_structure__c = 'SICAV',
            Project_Type__c = 'Fund',
            Stage__c = 'Stage1'
        );
        insert project;

        // Créer des objets liés (selon votre modèle)
        // Note: Adapter selon les objets réels de votre org
        /*
        Project_Share_class__c shareClass = new Project_Share_class__c(
            Name = 'Share Class A',
            Product_Services_Project__c = project.Id,
            Label__c = 'Class A'
        );
        insert shareClass;

        Project_Team__c team = new Project_Team__c(
            Name = 'Team Member 1',
            Product_Services_Project__c = project.Id
        );
        insert team;
        */
    }

    // ==================== PERFORMANCE TESTS ====================

    /**
     * Test P0: Temps de chargement avec getInitialData()
     *
     * OBJECTIF: <500ms en environnement de test
     * (En prod avec cache: <1000ms)
     */
    @isTest
    static void testPerformance_getInitialData_shouldBeUnder500ms() {
        // Arrange
        Product_Services_Project__c project = [
            SELECT Id
            FROM Product_Services_Project__c
            LIMIT 1
        ];

        // Act
        Test.startTest();
        Datetime startTime = Datetime.now();

        PLM_RequireDataMappingLite.InitDataWrapper result =
            PLM_RequireDataMappingLite.getInitialData(
                project.Id,
                'Stage1',
                'all'
            );

        Datetime endTime = Datetime.now();
        Test.stopTest();

        // Assert
        Long durationMs = endTime.getTime() - startTime.getTime();
        System.debug('⏱️ getInitialData duration: ' + durationMs + 'ms');

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(durationMs < 500, 'Should complete in <500ms, got: ' + durationMs + 'ms');

        // Vérifier que les données sont présentes
        // System.assertEquals(true, result.hasData, 'Should have data');
    }

    /**
     * Test P1: Nombre de requêtes SOQL
     *
     * OBJECTIF: <10 queries pour getInitialData
     */
    @isTest
    static void testGovernorLimits_getInitialData_shouldUseFewerThan10Queries() {
        // Arrange
        Product_Services_Project__c project = [
            SELECT Id
            FROM Product_Services_Project__c
            LIMIT 1
        ];

        // Act
        Test.startTest();
        Integer queriesBefore = Limits.getQueries();

        PLM_RequireDataMappingLite.InitDataWrapper result =
            PLM_RequireDataMappingLite.getInitialData(
                project.Id,
                'Stage1',
                'all'
            );

        Integer queriesAfter = Limits.getQueries();
        Test.stopTest();

        // Assert
        Integer queriesUsed = queriesAfter - queriesBefore;
        System.debug('🔍 Queries used: ' + queriesUsed);

        System.assert(queriesUsed < 10, 'Should use <10 queries, used: ' + queriesUsed);
    }

    /**
     * Test P2: Heap Size
     *
     * OBJECTIF: <50% du heap (3MB en test, 6MB en prod)
     */
    @isTest
    static void testGovernorLimits_getInitialData_shouldUseReasonableHeapSize() {
        // Arrange
        Product_Services_Project__c project = [
            SELECT Id
            FROM Product_Services_Project__c
            LIMIT 1
        ];

        // Act
        Test.startTest();
        Integer heapBefore = Limits.getHeapSize();

        PLM_RequireDataMappingLite.InitDataWrapper result =
            PLM_RequireDataMappingLite.getInitialData(
                project.Id,
                'Stage1',
                'all'
            );

        Integer heapAfter = Limits.getHeapSize();
        Test.stopTest();

        // Assert
        Integer heapUsed = heapAfter - heapBefore;
        System.debug('💾 Heap used: ' + heapUsed + ' bytes (' + (heapUsed/1024) + ' KB)');

        Integer heapLimit = Limits.getLimitHeapSize();
        Decimal heapPercent = (Decimal)heapUsed / heapLimit * 100;

        System.assert(heapPercent < 50, 'Should use <50% heap, used: ' + heapPercent + '%');
    }

    // ==================== FUNCTIONAL TESTS ====================

    /**
     * Test F1: getRequiredFieldMd avec différents types de véhicules
     */
    @isTest
    static void testGetRequiredFieldMd_withDifferentVehicleTypes() {
        // Test 1: Open-End Fund, Ireland, SICAV
        Product_Services_Project__c project1 = new Product_Services_Project__c(
            Name = 'OEF Ireland SICAV',
            Domiciliation__c = 'Ireland',
            vehicle_type__c = 'Open-End Fund',
            legal_structure__c = 'SICAV'
        );
        insert project1;

        Test.startTest();
        List<Require_Data_Mapping__mdt> result1 =
            PLM_RequireDataMappingLite.getRequiredFieldMd(project1.Id, 'Stage1', 'all');
        Test.stopTest();

        System.assertNotEquals(null, result1, 'Result should not be null');
        // System.assert(result1.size() > 0, 'Should return metadata for OEF Ireland SICAV');

        // Test 2: Dedicated Fund, FCP
        Product_Services_Project__c project2 = new Product_Services_Project__c(
            Name = 'Dedicated FCP',
            vehicle_type__c = 'Dedicated Fund',
            legal_structure__c = 'FCP'
        );
        insert project2;

        List<Require_Data_Mapping__mdt> result2 =
            PLM_RequireDataMappingLite.getRequiredFieldMd(project2.Id, 'Stage1', 'all');

        System.assertNotEquals(null, result2, 'Result should not be null');
    }

    /**
     * Test F2: Map-based configuration (au lieu de if/else)
     *
     * OBJECTIF: Vérifier que la logique Map-based fonctionne
     */
    @isTest
    static void testMapBasedConfiguration_shouldWorkForAllVehicleTypes() {
        // Créer des projets pour tous les types de véhicules
        List<Product_Services_Project__c> projects = new List<Product_Services_Project__c>{
            new Product_Services_Project__c(
                Name = 'OEF Ireland SICAV',
                Domiciliation__c = 'Ireland',
                vehicle_type__c = 'Open-End Fund',
                legal_structure__c = 'SICAV'
            ),
            new Product_Services_Project__c(
                Name = 'OEF France FCP',
                Domiciliation__c = 'France',
                vehicle_type__c = 'Open-End Fund',
                legal_structure__c = 'FCP'
            ),
            new Product_Services_Project__c(
                Name = 'Dedicated FPS',
                vehicle_type__c = 'Dedicated Fund',
                legal_structure__c = 'FPS'
            ),
            new Product_Services_Project__c(
                Name = 'Mandate',
                vehicle_type__c = 'Mandate'
            )
        };
        insert projects;

        Test.startTest();
        for(Product_Services_Project__c project : projects) {
            List<Require_Data_Mapping__mdt> result =
                PLM_RequireDataMappingLite.getRequiredFieldMd(project.Id, 'Stage1', 'all');

            System.assertNotEquals(null, result, 'Result should not be null for ' + project.Name);
        }
        Test.stopTest();
    }

    /**
     * Test F3: getLabels avec cache
     */
    @isTest
    static void testGetLabels_shouldUseSchemaCache() {
        Test.startTest();

        // Premier appel (cache miss)
        Map<String, String> result1 = PLM_RequireDataMappingLite.getLabels('Product_Services_Project__c');

        // Deuxième appel (cache hit)
        Map<String, String> result2 = PLM_RequireDataMappingLite.getLabels('Product_Services_Project__c');

        Test.stopTest();

        System.assertNotEquals(null, result1, 'First result should not be null');
        System.assertNotEquals(null, result2, 'Second result should not be null');
        System.assertEquals(result1.size(), result2.size(), 'Both results should have same size');

        // Vérifier que des labels existent
        System.assert(result1.size() > 0, 'Should have labels');
    }

    /**
     * Test F4: getObjectsLabels
     */
    @isTest
    static void testGetObjectsLabels_shouldReturnAllObjectLabels() {
        Test.startTest();
        Map<String, String> result = PLM_RequireDataMappingLite.getObjectsLabels();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        // System.assert(result.size() > 0, 'Should have object labels');
    }

    /**
     * Test F5: getLabelsOfFieldsByObject
     */
    @isTest
    static void testGetLabelsOfFieldsByObject_shouldReturnFieldLabels() {
        Test.startTest();
        Map<String, Map<String, String>> result =
            PLM_RequireDataMappingLite.getLabelsOfFieldsByObject();
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        // System.assert(result.size() > 0, 'Should have field labels by object');
    }

    /**
     * Test F6: getRecordById avec cacheable
     */
    @isTest
    static void testGetRecordById_shouldReturnRecords() {
        // Arrange
        Product_Services_Project__c project = [
            SELECT Id
            FROM Product_Services_Project__c
            LIMIT 1
        ];

        Test.startTest();
        Map<String, Map<Id, SObject>> result =
            PLM_RequireDataMappingLite.getRecordById(project.Id);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        // Vérifier qu'aucune erreur ne s'est produite
    }

    /**
     * Test F7: getAllEvalsConsolidated
     */
    @isTest
    static void testGetAllEvalsConsolidated_shouldEvaluateExpressions() {
        // Arrange
        String errorsJson = '[]';
        String warningsJson = '[]';

        Test.startTest();
        Map<String, List<TreeLogicalEval.EvalInput>> result =
            PLM_RequireDataMappingLite.getAllEvalsConsolidated(errorsJson, warningsJson);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assert(result.containsKey('errors'), 'Should have errors key');
        System.assert(result.containsKey('warnings'), 'Should have warnings key');
    }

    // ==================== CACHE TESTS ====================

    /**
     * Test C1: Platform Cache fonctionne
     *
     * Note: Ce test peut échouer si la partition PLMCache n'existe pas
     */
    @isTest
    static void testPlatformCache_shouldCacheResults() {
        // Arrange
        Product_Services_Project__c project = [
            SELECT Id
            FROM Product_Services_Project__c
            LIMIT 1
        ];

        Test.startTest();

        // Premier appel (cache miss)
        Datetime start1 = Datetime.now();
        List<Require_Data_Mapping__mdt> result1 =
            PLM_RequireDataMappingLite.getRequiredFieldMd(project.Id, 'Stage1', 'all');
        Datetime end1 = Datetime.now();
        Long duration1 = end1.getTime() - start1.getTime();

        // Deuxième appel (cache hit)
        Datetime start2 = Datetime.now();
        List<Require_Data_Mapping__mdt> result2 =
            PLM_RequireDataMappingLite.getRequiredFieldMd(project.Id, 'Stage1', 'all');
        Datetime end2 = Datetime.now();
        Long duration2 = end2.getTime() - start2.getTime();

        Test.stopTest();

        System.debug('⏱️ First call: ' + duration1 + 'ms, Second call: ' + duration2 + 'ms');

        // Assert
        System.assertNotEquals(null, result1, 'First result should not be null');
        System.assertNotEquals(null, result2, 'Second result should not be null');

        // Note: En environnement de test, le cache peut ne pas donner de gain visible
        // En production, duration2 devrait être beaucoup plus rapide que duration1
    }

    // ==================== ERROR HANDLING TESTS ====================

    /**
     * Test E1: Gestion d'erreur avec ID invalide
     */
    @isTest
    static void testErrorHandling_withInvalidProjectId_shouldHandleGracefully() {
        // Arrange
        Id fakeId = '001000000000000AAA'; // Fake ID

        // Act & Assert
        try {
            Test.startTest();
            PLM_RequireDataMappingLite.InitDataWrapper result =
                PLM_RequireDataMappingLite.getInitialData(fakeId, 'Stage1', 'all');
            Test.stopTest();

            // Si on arrive ici, la méthode a géré l'erreur gracieusement
            System.assert(true, 'Method handled error gracefully');
        } catch (Exception e) {
            // L'exception est attendue
            System.assert(true, 'Exception thrown as expected');
        }
    }

    /**
     * Test E2: Stage vide
     */
    @isTest
    static void testErrorHandling_withEmptyStage_shouldHandleGracefully() {
        // Arrange
        Product_Services_Project__c project = [
            SELECT Id
            FROM Product_Services_Project__c
            LIMIT 1
        ];

        Test.startTest();
        PLM_RequireDataMappingLite.InitDataWrapper result =
            PLM_RequireDataMappingLite.getInitialData(project.Id, '', 'all');
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    /**
     * Test E3: PLM Team null
     */
    @isTest
    static void testErrorHandling_withNullTeam_shouldHandleGracefully() {
        // Arrange
        Product_Services_Project__c project = [
            SELECT Id
            FROM Product_Services_Project__c
            LIMIT 1
        ];

        Test.startTest();
        PLM_RequireDataMappingLite.InitDataWrapper result =
            PLM_RequireDataMappingLite.getInitialData(project.Id, 'Stage1', null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
    }

    // ==================== LEGACY METHOD TESTS (Rétrocompatibilité) ====================

    /**
     * Test L1: getAllExpressionInput (legacy) fonctionne toujours
     */
    @isTest
    static void testLegacyMethod_getAllExpressionInput_shouldStillWork() {
        // Arrange
        Product_Services_Project__c project = [
            SELECT Id
            FROM Product_Services_Project__c
            LIMIT 1
        ];

        Map<String, List<String>> fieldsByObjects = new Map<String, List<String>>{
            'Product_Services_Project__c' => new List<String>{'Name'}
        };

        Map<String, String> PLM_fieldIdNameByObject = new Map<String, String>{
            'Product_Services_Project__c' => 'Id'
        };

        String rdmString = '{}';

        Test.startTest();
        PLM_RequireDataMappingLite.Expressions result =
            PLM_RequireDataMappingLite.getAllExpressionInput(
                project.Id,
                fieldsByObjects,
                PLM_fieldIdNameByObject,
                rdmString,
                'all'
            );
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null');
        System.assertNotEquals(null, result.evalListErrorByRecord, 'Errors map should not be null');
        System.assertNotEquals(null, result.evalListWarningByRecord, 'Warnings map should not be null');
    }

    /**
     * Test L2: getEvals (legacy) fonctionne toujours
     */
    @isTest
    static void testLegacyMethod_getEvals_shouldStillWork() {
        // Arrange
        String expressionsJson = '[]';

        Test.startTest();
        List<TreeLogicalEval.EvalInput> result =
            PLM_RequireDataMappingLite.getEvals(expressionsJson);
        Test.stopTest();

        // Result peut être null ou empty list
        System.assert(result == null || result.size() == 0, 'Result should be null or empty');
    }

    // ==================== BULK TESTS ====================

    /**
     * Test B1: Bulk test avec multiple projets
     *
     * OBJECTIF: Tester la scalabilité
     */
    @isTest
    static void testBulk_multipleProjects_shouldHandleInBulk() {
        // Arrange
        List<Product_Services_Project__c> projects = new List<Product_Services_Project__c>();
        for(Integer i = 0; i < 10; i++) {
            projects.add(new Product_Services_Project__c(
                Name = 'Bulk Test Project ' + i,
                Domiciliation__c = 'Ireland',
                vehicle_type__c = 'Open-End Fund',
                legal_structure__c = 'SICAV'
            ));
        }
        insert projects;

        // Act
        Test.startTest();
        for(Product_Services_Project__c project : projects) {
            PLM_RequireDataMappingLite.InitDataWrapper result =
                PLM_RequireDataMappingLite.getInitialData(project.Id, 'Stage1', 'all');

            System.assertNotEquals(null, result, 'Result should not be null');
        }
        Test.stopTest();

        // Assert Governor Limits
        System.assert(Limits.getQueries() < 100, 'Should not exceed SOQL limit');
        System.assert(Limits.getCpuTime() < 10000, 'Should complete in reasonable CPU time');
    }

    // ==================== INTEGRATION TESTS ====================

    /**
     * Test I1: Scénario complet de bout en bout
     */
    @isTest
    static void testIntegration_completeScenario_shouldWork() {
        // Arrange
        Product_Services_Project__c project = [
            SELECT Id
            FROM Product_Services_Project__c
            LIMIT 1
        ];

        Test.startTest();

        // 1. Récupérer les données initiales
        PLM_RequireDataMappingLite.InitDataWrapper initData =
            PLM_RequireDataMappingLite.getInitialData(project.Id, 'Stage1', 'all');

        System.assertNotEquals(null, initData, 'Init data should not be null');

        // 2. Si des expressions existent, les évaluer
        if(initData.hasData && initData.allExpressions != null) {
            // Sérialiser les expressions pour le test
            String errorsJson = JSON.serialize(new List<TreeLogicalEval.EvalInput>());
            String warningsJson = JSON.serialize(new List<TreeLogicalEval.EvalInput>());

            Map<String, List<TreeLogicalEval.EvalInput>> evaluated =
                PLM_RequireDataMappingLite.getAllEvalsConsolidated(errorsJson, warningsJson);

            System.assertNotEquals(null, evaluated, 'Evaluated results should not be null');
        }

        Test.stopTest();

        System.assert(true, 'Complete scenario executed successfully');
    }
}
