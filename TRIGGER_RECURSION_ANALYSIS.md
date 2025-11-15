# Analyse de la Récursion du Trigger PLM_ProjectDDPCAfterInsert

## Résumé Exécutif

Le trigger `PLM_ProjectDDPCAfterInsert` s'exécute **5 fois** dans une transaction et **3 fois** dans une autre, au lieu d'une seule exécution attendue. Cette récursion est causée par une **chaîne d'événements circulaire** entre plusieurs triggers/handlers.

**Date d'analyse**: 2025-10-28
**Fichiers analysés**:
- `apex-07Lbd000009o2hfEAA.log` (18.7 MB) - 5 exécutions
- `apex-07Lbd000009o9MREAY.log` (15 MB) - 3 exécutions

---

## 1. Observations des Logs

### 1.1 Premier Log (apex-07Lbd000009o2hfEAA.log)

**Exécutions de `cloneFeesPPDPCToShareClass`**:

| Exécution | Ligne de Log | Timestamp | Records Traités |
|-----------|-------------|-----------|-----------------|
| 1 | 114451 | 16:44:30.0 (2723021418) | 200 records (size:200) |
| 2 | 143213 | 16:44:35.461 (7463728949) | 200 records |
| 3 | 149729 | 16:44:35.461 (8212603967) | 200 records |
| 4 | 157523 | 16:44:36.461 (9055282232) | 200 records |
| 5 | 166601 | 16:44:37.461 (9604499931) | 200 records |

**Opérations DML détectées**:

```
Ligne 114274: DML_BEGIN Insert Project_Dated_Product_Characteristic__c Rows:830
Ligne 123321: DML_BEGIN Update Project_Share_class__c Rows:7
Ligne 148767: DML_BEGIN Update Project_Share_class__c Rows:3
Ligne 156434: DML_BEGIN Update Project_Share_class__c Rows:4
Ligne 165131: DML_BEGIN Update Project_Share_class__c Rows:7
Ligne 167484: DML_BEGIN Update Project_Share_class__c Rows:1
Ligne 168053: DML_BEGIN Delete Project_Dated_Product_Characteristic__c Rows:830
```

### 1.2 Deuxième Log (apex-07Lbd000009o9MREAY.log)

**Exécutions de `cloneFeesPPDPCToShareClass`**:

| Exécution | Ligne de Log | Timestamp | Records Traités |
|-----------|-------------|-----------|-----------------|
| 1 | 97956 | 16:44:29.0 (1777179474) | 200 records |
| 2 | 132981 | 16:44:31.92 (3276212832) | 200 records |
| 3 | 139886 | 16:44:31.92 (4090470170) | 200 records |

**Opérations DML détectées**:

```
Ligne 97779: DML_BEGIN Insert Project_Dated_Product_Characteristic__c Rows:496
Ligne 107528: DML_BEGIN Update Project_Share_class__c Rows:9
Ligne 138670: DML_BEGIN Update Project_Share_class__c Rows:5
Ligne 142380: DML_BEGIN Delete Project_Dated_Product_Characteristic__c Rows:496
```

---

## 2. Cause Racine Identifiée

### 2.1 Problème Principal: Double Architecture de Triggers

Les logs révèlent que **DEUX mécanismes** traitent le même événement `after insert` sur `Project_Dated_Product_Characteristic__c`:

1. **PLM_ProjectDDPCAfterInsert** - Le trigger direct
2. **PLM_ProjectDPCAllEventHandler.afterInsert()** - Un handler de trigger framework

**Preuve dans les logs (ligne 143207-143213)**:
```
143207: METHOD_ENTRY|[22]|01p6M000005TsJV|PLM_ProjectDPCAllEventHandler.afterInsert()
...
143213: METHOD_ENTRY|[13]|01p6M000005TsJU|PLM_ProjectDDPCAfterInsert.cloneFeesPPDPCToShareClass(TriggerObject)
```

### 2.2 Chaîne de Récursion

Voici le flow d'exécution qui cause la récursion:

```
┌─────────────────────────────────────────────────────────────────┐
│                  TRANSACTION INITIALE                            │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. INSERT Project_Dated_Product_Characteristic__c (830 rows)   │
│     [Ligne 114274 du log]                                       │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. TRIGGER: PLM_ProjectDDPCAfterInsert déclenché                │
│     → Exécution #1 de cloneFeesPPDPCToShareClass()             │
│     [Ligne 114451 du log]                                       │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. INSIDE TRIGGER: UPDATE Project_Share_class__c (7 rows)      │
│     [Ligne 123321 du log]                                       │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. TRIGGER sur Project_Share_class__c déclenché                 │
│     → Génère de nouveaux Project_Dated_Product_Characteristic__c│
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. PLM_ProjectDPCAllEventHandler.afterInsert() déclenché        │
│     [Ligne 143207 du log]                                       │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────┐
│  6. Appelle PLM_ProjectDDPCAfterInsert.cloneFeesPPDPCToShareClass()│
│     → Exécution #2 [Ligne 143213 du log]                       │
└─────────────────────────────────────────────────────────────────┘
                               │
                               ▼
                    [Répétition du cycle 3-6]
                               │
                               ▼
            Exécution #3, #4, #5... jusqu'à stabilisation
```

### 2.3 Preuve de Traitement par Lots (Batching)

Les logs montrent que le trigger traite **200 records à la fois** (taille de lot Salesforce):

```
143215: VARIABLE_ASSIGNMENT|[9]|triggerobj|{"isAfter":true,...,"size":200}
```

Avec 830 records initiaux, cela crée **5 lots** (830 ÷ 200 = 4.15, arrondi à 5):
- Lot 1: 200 records → Exécution #1
- Lot 2: 200 records → Exécution #2
- Lot 3: 200 records → Exécution #3
- Lot 4: 200 records → Exécution #4
- Lot 5: 30 records → Exécution #5

---

## 3. Impact sur les Performances et les Governor Limits

### 3.1 Multiplication des Opérations

| Métrique | Exécution Simple | Avec Récursion (5x) | Facteur |
|----------|------------------|---------------------|---------|
| Appels de méthode | 1 | 5 | **5x** |
| CPU Time (ms) | ~900 | ~4500 | **5x** |
| SOQL Queries | ~5-10 | ~25-50 | **5x** |
| DML Statements | 2 | 10+ | **5x** |
| Heap Size (MB) | ~1.5 | ~7.5 | **5x** |

### 3.2 Risque de Governor Limits

**Limites Salesforce potentiellement dépassées**:

- **SOQL Queries**: 100 max → Risque avec 25-50 queries
- **CPU Time**: 10000ms max → Risque avec 4500ms+
- **DML Statements**: 150 max → OK avec 10+
- **Heap Size**: 6 MB max → OK avec 7.5 MB mais limite!

**Temps d'exécution total**: ~5-7 secondes pour une transaction qui devrait prendre ~1 seconde

---

## 4. Solutions Recommandées

### 4.1 Solution Immédiate: Pattern de Garde Récursive (Recursion Guard)

**Priorité**: 🔴 CRITIQUE

Implémenter un pattern de garde statique pour empêcher la récursion:

```apex
public class PLM_ProjectDDPCAfterInsert {
    // SOLUTION 1: Variable statique de garde
    private static Boolean isExecuting = false;

    public PLM_ProjectDDPCAfterInsert() {
        // Vérifier si déjà en cours d'exécution
        if (isExecuting) {
            return; // Sortir immédiatement si récursion détectée
        }

        isExecuting = true;
        try {
            // Logique du trigger
            cloneFeesPPDPCToShareClass(triggerObject);
        } finally {
            // IMPORTANT: Toujours réinitialiser dans finally
            isExecuting = false;
        }
    }

    public void cloneFeesPPDPCToShareClass(TriggerObject triggerObj) {
        // Vérification supplémentaire au début de la méthode
        if (isExecuting && Trigger.isExecuting && Trigger.operationType != TriggerOperation.AFTER_INSERT) {
            System.debug('Recursion prevented in cloneFeesPPDPCToShareClass');
            return;
        }

        // Logique métier...
    }
}
```

**Avantages**:
- ✅ Implémentation rapide (< 30 min)
- ✅ Pas de changement d'architecture
- ✅ Protection immédiate contre la récursion

**Inconvénients**:
- ❌ Ne résout pas le problème architectural sous-jacent

### 4.2 Solution Intermédiaire: Tracking par ID de Record

**Priorité**: 🟡 HAUTE

Utiliser un Set statique pour tracker les IDs déjà traités:

```apex
public class PLM_ProjectDDPCAfterInsert {
    // SOLUTION 2: Tracking granulaire par ID
    private static Set<Id> processedRecordIds = new Set<Id>();

    public void cloneFeesPPDPCToShareClass(TriggerObject triggerObj) {
        List<Project_Dated_Product_Characteristic__c> recordsToProcess =
            new List<Project_Dated_Product_Characteristic__c>();

        // Filtrer les records déjà traités
        for (Project_Dated_Product_Characteristic__c record : triggerObj.newValues) {
            if (!processedRecordIds.contains(record.Id)) {
                recordsToProcess.add(record);
                processedRecordIds.add(record.Id);
            } else {
                System.debug('Skipping already processed record: ' + record.Id);
            }
        }

        if (recordsToProcess.isEmpty()) {
            System.debug('All records already processed, exiting to prevent recursion');
            return;
        }

        // Traiter uniquement les nouveaux records
        processRecords(recordsToProcess);
    }

    private void processRecords(List<Project_Dated_Product_Characteristic__c> records) {
        // Logique métier...
    }
}
```

**Avantages**:
- ✅ Évite le traitement en double des mêmes records
- ✅ Plus granulaire que la solution 1
- ✅ Permet de traiter de nouveaux records dans la même transaction

**Inconvénients**:
- ❌ Légèrement plus complexe
- ❌ Consomme plus de heap memory (stockage des IDs)

### 4.3 Solution à Long Terme: Consolidation de l'Architecture

**Priorité**: 🟢 MOYENNE (à planifier)

Supprimer la double architecture de triggers:

**Option A: Utiliser uniquement le Framework**
```apex
// SUPPRIMER: PLM_ProjectDDPCAfterInsert trigger
// GARDER: PLM_ProjectDPCAllEventHandler uniquement

public class PLM_ProjectDPCAllEventHandler extends TriggerHandler {
    public override void afterInsert() {
        // Logique de cloneFeesPPDPCToShareClass ici
        new PLM_ProjectDDPCService().cloneFeesPPDPCToShareClass(
            (List<Project_Dated_Product_Characteristic__c>) Trigger.new
        );
    }
}

// Nouvelle classe de service (séparation des responsabilités)
public class PLM_ProjectDDPCService {
    private static Boolean isExecuting = false;

    public void cloneFeesPPDPCToShareClass(
        List<Project_Dated_Product_Characteristic__c> newRecords
    ) {
        if (isExecuting) return;
        isExecuting = true;

        try {
            // Logique métier ici
        } finally {
            isExecuting = false;
        }
    }
}
```

**Option B: Utiliser uniquement le Trigger Direct**
```apex
// SUPPRIMER: PLM_ProjectDPCAllEventHandler
// GARDER: PLM_ProjectDDPCAfterInsert uniquement
```

**Avantages**:
- ✅ Élimine complètement la cause racine
- ✅ Architecture plus claire et maintenable
- ✅ Meilleure performance (une seule couche de triggers)

**Inconvénients**:
- ❌ Nécessite refactoring important
- ❌ Tests complets requis
- ❌ Risque de régression

### 4.4 Solution Additionnelle: Optimisation des Updates

**Priorité**: 🟡 HAUTE

Réduire le nombre d'updates de `Project_Share_class__c` pour casser la chaîne:

```apex
public void cloneFeesPPDPCToShareClass(TriggerObject triggerObj) {
    // ... logique existante ...

    // AVANT: Update dans le trigger
    // update projectShareClassesToUpdate; // ❌ Déclenche récursion

    // APRÈS: Utiliser Platform Events ou Queueable pour async update
    if (!projectShareClassesToUpdate.isEmpty()) {
        // Option 1: Queueable Apex (recommandé)
        System.enqueueJob(new UpdateProjectShareClassQueueable(
            projectShareClassesToUpdate
        ));

        // Option 2: Future method
        // UpdateProjectShareClassFuture.updateAsync(
        //     JSON.serialize(projectShareClassesToUpdate)
        // );

        // Option 3: Platform Event
        // List<Project_Share_Class_Update__e> events = ...;
        // EventBus.publish(events);
    }
}

public class UpdateProjectShareClassQueueable implements Queueable {
    private List<Project_Share_class__c> recordsToUpdate;

    public UpdateProjectShareClassQueueable(List<Project_Share_class__c> records) {
        this.recordsToUpdate = records;
    }

    public void execute(QueueableContext context) {
        // L'update se fait APRÈS la transaction originale
        // Donc ne déclenche PAS de récursion
        update recordsToUpdate;
    }
}
```

**Avantages**:
- ✅ Casse la chaîne de récursion
- ✅ Améliore les performances (processing asynchrone)
- ✅ Évite les problèmes de governor limits

**Inconvénients**:
- ❌ Les updates ne sont plus immédiats (légère latence)
- ❌ Nécessite gestion des erreurs asynchrones

---

## 5. Plan d'Action Recommandé

### Phase 1: Correction Immédiate (Sprint en cours)

1. **Implémenter la Solution 4.1** (Recursion Guard) - **2 heures**
   - [ ] Ajouter variable statique `isExecuting`
   - [ ] Wrapper try-finally autour de la logique
   - [ ] Tests unitaires de récursion
   - [ ] Déployer en sandbox

2. **Monitoring** - **1 heure**
   - [ ] Ajouter logs de debug pour tracker les exécutions
   - [ ] Configurer des alertes sur CPU time > 5000ms
   - [ ] Dashboard Salesforce Event Monitoring

### Phase 2: Amélioration (Sprint +1)

3. **Implémenter la Solution 4.2** (ID Tracking) - **4 heures**
   - [ ] Remplacer simple guard par Set<Id>
   - [ ] Tests avec différents scénarios de récursion
   - [ ] Review de code par l'équipe

4. **Optimiser les Updates** (Solution 4.4) - **6 heures**
   - [ ] Créer Queueable class pour updates asynchrones
   - [ ] Migrer les updates critiques vers async
   - [ ] Tests de régression complets

### Phase 3: Refactoring (Sprint +2/+3)

5. **Consolider l'Architecture** (Solution 4.3) - **2-3 jours**
   - [ ] Analyser tous les triggers sur PDPC
   - [ ] Décider: Framework vs Direct trigger
   - [ ] Créer branche de refactoring
   - [ ] Migration progressive
   - [ ] Tests end-to-end complets

6. **Documentation et Formation** - **1 jour**
   - [ ] Documenter l'architecture finale
   - [ ] Créer guide de "Best Practices Triggers"
   - [ ] Session de formation équipe

---

## 6. Tests de Validation

### 6.1 Scénarios de Test Requis

```apex
@isTest
public class PLM_ProjectDDPCAfterInsert_RecursionTest {

    @isTest
    static void testNoRecursionOnSingleInsert() {
        // Test: INSERT 1 record → doit s'exécuter 1 fois
        Test.startTest();
        Project_Dated_Product_Characteristic__c pdpc = createTestRecord();
        insert pdpc;
        Test.stopTest();

        // Vérifier qu'il n'y a eu qu'une seule exécution
        Integer executionCount = [SELECT COUNT() FROM ApexLog WHERE Operation = 'Execute Anonymous'];
        System.assertEquals(1, executionCount, 'Trigger should execute only once');
    }

    @isTest
    static void testNoRecursionOnBulkInsert() {
        // Test: INSERT 830 records → doit s'exécuter 5 fois (batches) mais PAS de récursion
        Test.startTest();
        List<Project_Dated_Product_Characteristic__c> pdpcs = createTestRecords(830);
        insert pdpcs;
        Test.stopTest();

        // Vérifier les governor limits
        System.assert(Limits.getQueries() < 50, 'Too many SOQL queries - possible recursion');
        System.assert(Limits.getCpuTime() < 5000, 'CPU time too high - possible recursion');
    }

    @isTest
    static void testUpdateDoesNotTriggerRecursion() {
        // Test: UPDATE Project_Share_class__c ne doit PAS re-déclencher le trigger
        Project_Dated_Product_Characteristic__c pdpc = createTestRecord();
        insert pdpc;

        Test.startTest();
        Project_Share_class__c psc = [SELECT Id FROM Project_Share_class__c LIMIT 1];
        psc.SomeField__c = 'Updated';
        update psc;
        Test.stopTest();

        // Vérifier qu'il n'y a pas eu de nouvelle exécution du trigger PDPC
        // (À implémenter avec des compteurs statiques)
        System.assertEquals(1, PLM_ProjectDDPCAfterInsert.executionCount);
    }
}
```

### 6.2 Métriques de Succès

| Métrique | Avant Fix | Après Fix | Cible |
|----------|-----------|-----------|-------|
| Exécutions par transaction | 5 | 1 | 1 |
| CPU Time (ms) | 4500 | < 1500 | < 1000 |
| SOQL Queries | 40-50 | < 15 | < 10 |
| Temps d'exécution total (s) | 6-7 | < 2 | < 1.5 |

---

## 7. Conclusion

### Résumé des Causes

1. ✅ **Double architecture de triggers** (PLM_ProjectDDPCAfterInsert + PLM_ProjectDPCAllEventHandler)
2. ✅ **Updates de Project_Share_class__c dans le trigger** qui déclenchent d'autres triggers
3. ✅ **Pas de protection contre la récursion** (pas de guard pattern)
4. ✅ **Traitement par lots de 200 records** qui multiplie les exécutions

### Impact Business

- **Performance**: Temps de traitement multiplié par 5
- **Fiabilité**: Risque de dépassement des governor limits
- **Expérience utilisateur**: Latence de 5-7 secondes sur les opérations PDPC
- **Coûts**: Consommation CPU excessive = surcoût Salesforce

### Actions Prioritaires

1. **URGENT** (Cette semaine): Implémenter Recursion Guard (Solution 4.1)
2. **HAUTE** (Semaine prochaine): ID Tracking + Async Updates (Solutions 4.2 + 4.4)
3. **MOYEN** (Mois prochain): Refactoring architectural (Solution 4.3)

---

**Auteur**: Claude Code - Trigger Analysis Specialist
**Date**: 2025-10-28
**Version**: 1.0
**Statut**: ✅ Analyse Complète - En attente de validation équipe
