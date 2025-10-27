# 📘 Guide de Migration - Optimisations PLM Required Fields

**Version:** 2.0
**Date:** 2025-10-27
**Durée estimée:** 2-3 semaines (selon approche)
**Niveau de risque:** Moyen (breaking changes minimes)

---

## 🎯 Vue d'Ensemble

Ce guide vous accompagne pas à pas dans le déploiement des optimisations qui réduiront le temps de chargement de **15-25s à <1s** (-95%).

### Approches Possibles

**Option A: Déploiement Progressif (RECOMMANDÉ)**
- Durée: 2-3 semaines
- Risque: FAIBLE
- Quick wins → Optimisations majeures → Refactoring complet
- Rollback facile à chaque étape

**Option B: Déploiement Complet (Big Bang)**
- Durée: 1 semaine
- Risque: MOYEN
- Déployer tout d'un coup
- Nécessite tests exhaustifs

**Notre recommandation:** Option A (Progressif)

---

## 📋 PRÉ-REQUIS

### 1. Environnements

- [ ] **Sandbox Developer** disponible
- [ ] **Sandbox UAT/QA** disponible
- [ ] **Production** avec plan de rollback
- [ ] **Accès admin** sur tous les environnements

### 2. Outils Nécessaires

```bash
# Salesforce CLI
sfdx version
# Devrait afficher: sfdx-cli/7.x ou supérieur

# Git
git --version
# Devrait afficher: git version 2.x ou supérieur

# Node.js (pour LWC)
node --version
# Devrait afficher: v18.x ou supérieur
```

### 3. Backups

- [ ] **Backup de la classe Apex actuelle**
  ```bash
  sfdx force:source:retrieve -m ApexClass:PLM_RequireDataMappingLite
  cp force-app/.../PLM_RequireDataMappingLite.cls force-app/.../PLM_RequireDataMappingLite_BACKUP.cls
  ```

- [ ] **Backup du composant LWC actuel**
  ```bash
  sfdx force:source:retrieve -m LightningComponentBundle:pLM_ShowRequiredFieldsByOwnerV3
  cp -r force-app/.../pLM_ShowRequiredFieldsByOwnerV3 force-app/.../pLM_ShowRequiredFieldsByOwnerV3_BACKUP
  ```

- [ ] **Export des Custom Metadata Types**
  ```bash
  sfdx force:source:retrieve -m CustomMetadata:Require_Data_Mapping__mdt
  ```

### 4. Tests Initiaux (Baseline)

Avant toute modification, mesurez les performances actuelles:

```javascript
// Dans la console du navigateur
console.time('PLM Load Time');
// ... attendre le chargement complet ...
console.timeEnd('PLM Load Time');
// Noter le temps (ex: 22000ms)
```

**Métriques à noter:**
- Temps de chargement: ____________ ms
- Nombre d'appels Apex (Network tab): ____________
- CPU Time (Debug Logs): ____________ ms
- Heap Size (Debug Logs): ____________ MB

---

## 🚀 PHASE 1: QUICK WINS (1-2 jours) → Gain: 40-60%

**Objectif:** Passer de 15-25s à 6-10s
**Risque:** TRÈS FAIBLE
**Rollback:** IMMÉDIAT

### Étape 1.1: Activer cacheable=true

**Durée:** 1 heure
**Impact:** -40% temps de chargement

#### Actions

1. **Ouvrir PLM_RequireDataMappingLite.cls**

2. **Modifier les signatures de méthodes:**

```apex
// AVANT:
@AuraEnabled
public static Map<String, String> getLabels(String objectName)

// APRÈS:
@AuraEnabled(cacheable=true)
public static Map<String, String> getLabels(String objectName)
```

3. **Appliquer à toutes les méthodes éligibles:**
   - [x] `getLabels()`
   - [x] `getObjectsLabels()`
   - [x] `getLabelsOfFieldsByObject()`
   - [x] `getRecordById()`
   - [x] `getRequiredFieldMd()`
   - [x] `getIdsByObject()`
   - [x] `getResponsibleMap()`

4. **Déployer en Sandbox**

```bash
cd /home/user/sf
sfdx force:source:deploy -m ApexClass:PLM_RequireDataMappingLite -u YourSandbox
```

5. **Tester en Sandbox**

   - Ouvrir le composant PLM
   - Mesurer le temps (devrait être ~12-15s au premier chargement)
   - Rafraîchir la page
   - Mesurer le temps (devrait être ~3-5s avec cache)
   - **Gain attendu:** -40% sur reloads

6. **Si OK → Déployer en Production**

```bash
# Validation sans déploiement
sfdx force:source:deploy -m ApexClass:PLM_RequireDataMappingLite -u Production --checkonly

# Si validation OK → Déploiement
sfdx force:source:deploy -m ApexClass:PLM_RequireDataMappingLite -u Production
```

**✅ CHECKPOINT 1.1**
- [ ] Tests passent en Sandbox
- [ ] Temps de chargement réduit de 40% sur reloads
- [ ] Aucune erreur fonctionnelle
- [ ] Déployé en Production

---

### Étape 1.2: Ajouter Cache Schema

**Durée:** 2 heures
**Impact:** -15% temps de chargement

#### Actions

1. **Ajouter les variables statiques de cache**

```apex
public class PLM_RequireDataMappingLite {

    // ✅ AJOUTER CES LIGNES EN HAUT DE LA CLASSE
    private static Map<String, Schema.SObjectType> SCHEMA_CACHE;
    private static Map<String, Map<String, Schema.SObjectField>> FIELD_CACHE =
        new Map<String, Map<String, Schema.SObjectField>>();

    private static Map<String, Schema.SObjectType> getSchemaMapCached(){
        if(SCHEMA_CACHE == null){
            SCHEMA_CACHE = Schema.getGlobalDescribe();
        }
        return SCHEMA_CACHE;
    }

    private static Map<String, Schema.SObjectField> getFieldMapCached(String objectName){
        if(!FIELD_CACHE.containsKey(objectName)){
            Map<String, Schema.SObjectType> schemaMap = getSchemaMapCached();
            Schema.SObjectType obj = schemaMap.get(objectName);
            if(obj != null){
                FIELD_CACHE.put(objectName, obj.getDescribe().fields.getMap());
            }
        }
        return FIELD_CACHE.get(objectName);
    }

    // ... reste du code ...
}
```

2. **Remplacer tous les appels à getGlobalDescribe()**

```apex
// AVANT (dans getLabels):
Map<String, Schema.SObjectType> schemaMap = Schema.getGlobalDescribe();
Schema.SObjectType obj = schemaMap.get(objectName);
Map<String, Schema.SObjectField> fieldMap = obj.getDescribe().fields.getMap();

// APRÈS:
Map<String, Schema.SObjectField> fieldMap = getFieldMapCached(objectName);
```

3. **Chercher et remplacer dans toutes les méthodes:**
   - `getLabels()`
   - `getLabelsOfFieldsByObject()`
   - `getObjectsLabels()`

4. **Tester et déployer** (même processus que 1.1)

**✅ CHECKPOINT 1.2**
- [ ] Cache Schema implémenté
- [ ] Temps de chargement réduit de 55% total
- [ ] Tests passent
- [ ] Déployé en Production

---

### Étape 1.3: Désactiver Logs JSON en Production

**Durée:** 30 minutes
**Impact:** -5% temps CPU

#### Actions

1. **Remplacer tous les logs JSON**

```apex
// AVANT:
Logger.info(JSON.serializePretty(result)).addTag('PLM');

// APRÈS:
if(Test.isRunningTest()){  // Logs seulement en test
    Logger.info(JSON.serializePretty(result)).addTag('PLM');
}
```

2. **Ou mieux: Créer un helper**

```apex
private static void logDebug(String message){
    if(Test.isRunningTest()){
        Logger.info(message).addTag('PLM_OPTIMIZED');
    }
}

// Utilisation:
logDebug('getLabels for: ' + objectName);
```

3. **Tester et déployer**

**✅ CHECKPOINT 1.3 - FIN PHASE 1**
- [ ] Logs conditionnels implémentés
- [ ] **Temps total réduit de ~60%** (de 20s → 8s)
- [ ] Tous les tests passent
- [ ] Production stable

**📊 MÉTRIQUES PHASE 1:**
- Temps de chargement: ~8-10s (premier), ~3-5s (reload)
- Gain: **-60%** sur premier chargement, **-85%** sur reloads
- Durée totale: **4 heures de travail**

---

## 🔥 PHASE 2: OPTIMISATIONS MAJEURES (3-5 jours) → Gain: 85%

**Objectif:** Passer de 8-10s à 2-3s
**Risque:** MOYEN
**Rollback:** Facile (code versionné)

### Étape 2.1: Consolider les Appels Apex (getInitialData)

**Durée:** 4 heures
**Impact:** -50% temps réseau

#### Actions

1. **Copier le code optimisé**

```bash
# Copier la classe optimisée
cp /home/user/sf/optimizations/apex/PLM_RequireDataMappingLite_OPTIMIZED.cls \
   force-app/main/default/classes/PLM_RequireDataMappingLite.cls

# Copier les meta.xml si besoin
cp force-app/main/default/classes/PLM_RequireDataMappingLite_BACKUP.cls-meta.xml \
   force-app/main/default/classes/PLM_RequireDataMappingLite.cls-meta.xml
```

2. **Vérifier les Inner Classes**

Assurez-vous que ces classes sont présentes dans le fichier:
- `InitDataWrapper`
- `Expressions`
- `TraitementInput`

3. **Déployer la nouvelle classe Apex**

```bash
# Sandbox d'abord
sfdx force:source:deploy -m ApexClass:PLM_RequireDataMappingLite -u YourSandbox

# Vérifier qu'il n'y a pas d'erreurs
```

4. **Modifier le composant LWC**

```bash
# Copier le fichier optimisé
cp /home/user/sf/optimizations/lwc/pLM_ShowRequiredFieldsByOwnerV3_OPTIMIZED.js \
   force-app/main/default/lwc/pLM_ShowRequiredFieldsByOwnerV3/pLM_ShowRequiredFieldsByOwnerV3.js
```

5. **Mettre à jour les imports dans le LWC**

```javascript
// ✅ NOUVEAU: Un seul import principal
import getInitialData from "@salesforce/apex/PLM_RequireDataMappingLite.getInitialData";
import getAllEvalsConsolidated from "@salesforce/apex/PLM_RequireDataMappingLite.getAllEvalsConsolidated";

// ❌ SUPPRIMER tous les autres imports (getLabels, getObjectsLabels, etc.)
```

6. **Déployer le LWC**

```bash
sfdx force:source:deploy -m LightningComponentBundle:pLM_ShowRequiredFieldsByOwnerV3 -u YourSandbox
```

7. **Tester en Sandbox**

   **Tests Fonctionnels:**
   - [ ] Le composant s'affiche correctement
   - [ ] Les champs requis manquants apparaissent
   - [ ] Les erreurs sont en rouge, warnings en jaune
   - [ ] Le Tree Grid est expandable
   - [ ] La modale d'édition fonctionne
   - [ ] La sauvegarde d'un champ fonctionne
   - [ ] Le banner se met à jour

   **Tests de Performance:**
   ```javascript
   // Console navigateur
   console.time('PLM v2.0 Load');
   // ... chargement ...
   console.timeEnd('PLM v2.0 Load');
   // Devrait afficher: ~2-3 secondes
   ```

   **Tests Réseau:**
   - Ouvrir Network tab (F12)
   - Filtrer par "Apex"
   - Compter les appels → **Devrait être 1-2 au lieu de 15-20**

8. **Si OK → Déployer en Production**

```bash
# Validation
sfdx force:source:deploy -m ApexClass:PLM_RequireDataMappingLite,LightningComponentBundle:pLM_ShowRequiredFieldsByOwnerV3 -u Production --checkonly

# Déploiement
sfdx force:source:deploy -m ApexClass:PLM_RequireDataMappingLite,LightningComponentBundle:pLM_ShowRequiredFieldsByOwnerV3 -u Production
```

**✅ CHECKPOINT 2.1**
- [ ] Méthode getInitialData() fonctionne
- [ ] Nombre d'appels Apex réduit à 1-2
- [ ] Temps de chargement ~2-3s
- [ ] Aucune régression fonctionnelle
- [ ] Déployé en Production

---

### Étape 2.2: Optimiser getRecordById (Éliminer SOQL in Loop)

**Durée:** 2 heures
**Impact:** -10% temps

Cette optimisation est déjà incluse dans le fichier OPTIMIZED.cls de l'étape 2.1.

**Vérifications:**
- [ ] La méthode `getRecordById()` a `cacheable=true`
- [ ] La méthode a un `LIMIT 1000` sur toutes les queries
- [ ] Pas de query dans une boucle sans optimisation

---

### Étape 2.3: Éliminer Sérialisations JSON

**Durée:** 4 heures
**Impact:** -10% CPU time

#### Actions

1. **Vérifier que getAllExpressionInput utilise des objets natifs**

Dans le code optimisé, la signature est:

```apex
private static Expressions getAllExpressionInputInternal(
    Id PLM_ProjectId,
    Map<String, Map<String, List<String>>> fieldsByObjectByResponsible,
    Map<String, String> PLM_fieldIdNameByObject,
    Map<String, Require_Data_Mapping__mdt> rdmByFieldName  // ✅ Objet natif
)
```

Au lieu de:

```apex
// ❌ ANCIEN (avec JSON string)
public static Expressions getAllExpressionInput(
    // ...
    String rdmByFieldNameString  // ❌ String JSON
)
```

2. **Vérifier le LWC**

Le LWC v2.0 ne fait plus de `JSON.stringify()` pour passer les données à Apex (tout est dans `getInitialData()`).

3. **Tester**

**✅ CHECKPOINT 2.3 - FIN PHASE 2**
- [ ] JSON serializations réduite de 95%
- [ ] **Temps total: ~2-3s** (premier chargement)
- [ ] CPU time réduit de 50%
- [ ] Tous les tests passent

**📊 MÉTRIQUES PHASE 2:**
- Temps de chargement: ~2-3s
- Gain total depuis début: **-85%** (20s → 3s)
- Durée totale Phase 2: **10 heures de travail**

---

## 🏗️ PHASE 3: REFACTORING ARCHITECTURAL (1-2 semaines) → Gain: 95-98%

**Objectif:** Passer de 2-3s à <1s
**Risque:** MOYEN-ÉLEVÉ
**Rollback:** Nécessite planification

### Étape 3.1: Implémenter Platform Cache

**Durée:** 2 jours
**Impact:** -60% sur données cachées

#### Actions

1. **Créer la Partition Cache dans Salesforce**

   - Setup → Platform Cache → New Platform Cache Partition
   - Name: `PLMCache`
   - Type: Session Cache
   - Size: 10 MB
   - Default Partition: No

2. **Vérifier le code de cache dans PLM_RequireDataMappingLite**

Le code optimisé contient déjà:

```apex
private static final String CACHE_PARTITION = 'local.PLMCache';

private static Object getCached(String key){
    try {
        Cache.SessionPartition sessionPart = Cache.Session.getPartition(CACHE_PARTITION);
        return sessionPart.get(key);
    } catch (Exception e) {
        return null;
    }
}

private static void putCached(String key, Object value, Integer ttlSeconds){
    try {
        Cache.SessionPartition sessionPart = Cache.Session.getPartition(CACHE_PARTITION);
        sessionPart.put(key, value, ttlSeconds, Cache.Visibility.ALL, false);
    } catch (Exception e) {
        // Log error
    }
}
```

3. **Activer le cache dans les méthodes**

Exemple dans `getRequiredFieldMd()`:

```apex
@AuraEnabled(cacheable=true)
public static List<Require_Data_Mapping__mdt> getRequiredFieldMd(...){
    // ✅ Vérifier cache
    String cacheKey = 'req_fields_' + PLM_ProjectId + '_' + stage + '_' + plmTeam;
    List<Require_Data_Mapping__mdt> cachedResult =
        (List<Require_Data_Mapping__mdt>) getCached(cacheKey);

    if(cachedResult != null){
        return cachedResult;  // Cache HIT
    }

    // ... logique normale ...

    // ✅ Mettre en cache
    putCached(cacheKey, result, 3600);  // 1 heure

    return result;
}
```

4. **Tester le cache**

```apex
// Dans Anonymous Apex ou Test
System.debug('First call:');
Long start1 = System.now().getTime();
PLM_RequireDataMappingLite.getRequiredFieldMd(projectId, 'Stage1', 'all');
Long duration1 = System.now().getTime() - start1;
System.debug('Duration 1: ' + duration1 + 'ms');

System.debug('Second call (cached):');
Long start2 = System.now().getTime();
PLM_RequireDataMappingLite.getRequiredFieldMd(projectId, 'Stage1', 'all');
Long duration2 = System.now().getTime() - start2;
System.debug('Duration 2: ' + duration2 + 'ms');

// duration2 devrait être ~10x plus rapide que duration1
```

5. **Gérer l'invalidation du cache**

Créer une méthode pour vider le cache quand les données changent:

```apex
@AuraEnabled
public static void clearCacheForProject(Id projectId){
    // Invalider tous les cacheKeys liés à ce projet
    // Note: Platform Cache ne supporte pas les wildcard,
    // donc il faut tracker les keys ou utiliser un TTL court
}
```

**✅ CHECKPOINT 3.1**
- [ ] Platform Cache partition créée
- [ ] Code de cache déployé
- [ ] Cache fonctionne (vérifié avec logs)
- [ ] Performance améliorée de 60% sur cache hits
- [ ] Stratégie d'invalidation définie

---

### Étape 3.2: Refactoriser Logique Conditionnelle (Map-based)

**Durée:** 2 jours
**Impact:** -20% sur getRequiredFieldMd

Cette optimisation est déjà incluse dans le code OPTIMIZED.cls:

```apex
private static final Map<String, String> VEHICLE_CONFIG = new Map<String, String>{
    'Open-End Fund_Ireland_SICAV' => 'Required_for_OEF_NIF_IR_SICAV__c',
    'Open-End Fund_United Kingdom_SICAV' => 'Required_for_OEF_LUX_UK_SICAV__c',
    // ... etc
};
```

**Vérifications:**
- [ ] VEHICLE_CONFIG map est complète
- [ ] Tous les cas métier sont couverts
- [ ] Fallback sur GENERIC si clé non trouvée
- [ ] Tests unitaires couvrent tous les cas

---

### Étape 3.3: Ajouter Lazy Loading au Tree Grid (Optionnel)

**Durée:** 1 jour
**Impact:** -10% sur gros volumes

Pour les projets avec 100+ champs manquants, implémenter du lazy loading:

```javascript
// Dans le LWC
@wire(getTreeGridData, { projectId: '$recordId', offset: '$offset', limit: '$limit' })
wiredData({ error, data }) {
    if (data) {
        this.gridData = [...this.gridData, ...data];
    }
}

// Charger plus de données au scroll
handleLoadMore(event) {
    this.offset += this.limit;
}
```

**Note:** Cette optimisation est optionnelle et utile seulement si vous avez régulièrement >50 items dans le grid.

---

### Étape 3.4: Compiler les Formules (Optionnel Avancé)

**Durée:** 2 jours
**Impact:** -5%

Remplacer TreeLogicalEval par un parser custom peut donner un petit gain supplémentaire.

**Note:** Cette optimisation est très avancée et optionnelle. Gain marginal (<5%).

**✅ CHECKPOINT 3.4 - FIN PHASE 3**
- [ ] Platform Cache actif
- [ ] Map-based config déployée
- [ ] Lazy loading implémenté (si nécessaire)
- [ ] **Temps total: <1s**
- [ ] **Gain total: -95-98%**

**📊 MÉTRIQUES FINALES:**
- Temps de chargement: **<1s** (objectif atteint!)
- Appels Apex: **1** (-95%)
- SOQL Queries: **3-5** (-85%)
- CPU Time: **500-800ms** (-90%)
- Heap Size: **2-3MB** (-75%)

---

## 🧪 PLAN DE TESTS COMPLET

### Tests Fonctionnels

#### Test 1: Affichage des Champs Manquants
- [ ] Le Tree Grid s'affiche
- [ ] Les erreurs sont en rouge
- [ ] Les warnings sont en jaune
- [ ] Les compteurs sont corrects (X Errors And Y Warnings)

#### Test 2: Navigation
- [ ] Expand All fonctionne
- [ ] Cliquer sur une ligne ouvre la modale
- [ ] La modale affiche le bon champ
- [ ] Le lien "View" ouvre le bon record

#### Test 3: Édition
- [ ] Le formulaire d'édition s'affiche
- [ ] La sauvegarde fonctionne
- [ ] Le grid se rafraîchit après sauvegarde
- [ ] Le champ disparaît de la liste après correction

#### Test 4: Validation Flow
- [ ] Le composant bloque la navigation si erreurs
- [ ] Le composant permet la navigation si warnings only
- [ ] Le composant permet la navigation si tout est OK

### Tests de Performance

#### Test 1: Premier Chargement (Cache Froid)
```javascript
// Console
performance.clearResourceTimings();
console.time('First Load');
// Rafraîchir la page
// Attendre le chargement complet
console.timeEnd('First Load');
// Objectif: <1000ms
```

#### Test 2: Rechargement (Cache Chaud)
```javascript
console.time('Reload');
// Rafraîchir la page
console.timeEnd('Reload');
// Objectif: <500ms
```

#### Test 3: Nombre d'Appels Apex
- Ouvrir Network tab
- Filtrer par "aura" ou "action"
- Compter les appels
- **Objectif: 1-2 appels**

#### Test 4: CPU Time Apex
```apex
// Dans Debug Logs
// Setup → Debug Logs → New → User Trace Flag
// Niveau: FINEST pour Apex Code

// Chercher dans les logs:
// CUMULATIVE_PROFILING
// CPU TIME
// Objectif: <1000ms
```

### Tests de Régression

#### Test 1: Différents Types de Projet
- [ ] Open-End Fund (Ireland, SICAV)
- [ ] Open-End Fund (France, FCP)
- [ ] Dedicated Fund
- [ ] Mandate

#### Test 2: Différents Stages
- [ ] Stage 1
- [ ] Stage 2
- [ ] Multiple stages (Stage1,Stage2)

#### Test 3: Différents Teams
- [ ] Team specific
- [ ] All teams

#### Test 4: Edge Cases
- [ ] Projet sans champs manquants → Message "All data completed"
- [ ] Projet avec 1 seul champ manquant
- [ ] Projet avec 100+ champs manquants
- [ ] Formule invalide dans metadata → Gestion d'erreur gracieuse

### Tests de Charge (Optionnel)

#### Test 1: Concurrence
- 10 utilisateurs simultanés
- Ouvrent le composant en même temps
- **Objectif: Aucun timeout, temps <2s**

#### Test 2: Gros Volume
- Projet avec 50+ objets liés
- 100+ champs requis
- **Objectif: Temps <2s, pas de timeout**

---

## 🔄 PLAN DE ROLLBACK

### Rollback Immédiat (< 5 minutes)

Si problème critique en production:

```bash
# 1. Déployer la classe de backup
sfdx force:source:deploy -m ApexClass:PLM_RequireDataMappingLite_BACKUP -u Production

# 2. Renommer pour restaurer
# Via Salesforce UI ou SFDX

# 3. Déployer le LWC de backup
sfdx force:source:deploy -m LightningComponentBundle:pLM_ShowRequiredFieldsByOwnerV3_BACKUP -u Production
```

### Rollback Partiel (Phase par Phase)

Si Phase 2 ou 3 pose problème:

**Retour à Phase 1:**
- Déployer PLM_RequireDataMappingLite version Phase 1
- Déployer pLM_ShowRequiredFieldsByOwnerV3 version originale
- Désactiver Platform Cache

**Retour à Phase 2:**
- Garder getInitialData()
- Désactiver Platform Cache
- Garder Map-based config

### Plan de Contingence

**Si erreur TreelogicalEvalException persiste:**
- Augmenter le nombre de groupes par object type
- Réduire la taille des batches d'évaluation
- Ajouter plus de try/catch

**Si timeout Governor Limits:**
- Réduire le TTL du cache
- Ajouter des LIMIT plus bas (500 au lieu de 1000)
- Implémenter du batch processing

**Si problème de cache:**
- Désactiver Platform Cache temporairement
- Garder seulement @cacheable=true
- Investiguer les clés de cache

---

## 📊 MONITORING POST-DÉPLOIEMENT

### Semaine 1 Post-Déploiement

**Checks quotidiens:**
- [ ] Event Monitoring: CPU Time moyen
- [ ] Event Monitoring: Nombre de queries SOQL
- [ ] User feedback: Temps perçu
- [ ] Error logs: Nouvelles exceptions?

**Métriques à surveiller:**

```sql
-- Dans Query Editor (Event Monitoring)
SELECT
    AVG(CpuTime) as AvgCPU,
    MAX(CpuTime) as MaxCPU,
    AVG(RunTime) as AvgRuntime,
    COUNT(*) as Executions
FROM ApexExecutionEvent
WHERE ClassName = 'PLM_RequireDataMappingLite'
AND EventDate = LAST_N_DAYS:7
```

**Alertes à configurer:**
- CPU Time > 2000ms
- Runtime > 3000ms
- Erreur rate > 1%

### Mois 1 Post-Déploiement

**Rapport mensuel:**
- Temps de chargement moyen: ____________
- Taux de satisfaction utilisateurs: ____________
- Nombre d'incidents: ____________
- Gain réel vs projeté: ____________

**Optimisations supplémentaires si nécessaire:**
- Ajuster TTL du cache
- Optimiser les formules lentes
- Ajouter des index sur champs filtrés

---

## ✅ CHECKLIST FINALE DE VALIDATION

### Avant Production

- [ ] Tous les tests unitaires passent (>75% coverage)
- [ ] Tous les tests fonctionnels passent
- [ ] Performance mesurée: <1s
- [ ] Appels Apex: 1-2
- [ ] Backup créés et testés
- [ ] Plan de rollback prêt
- [ ] Documentation à jour
- [ ] Users formés (si changements UI)

### Après Production

- [ ] Monitoring actif
- [ ] Aucune erreur critique dans les logs
- [ ] Feedback utilisateurs positif
- [ ] Métriques conformes aux objectifs
- [ ] Rollback plan testé (drill)

---

## 📞 SUPPORT & RESSOURCES

### Documentation

- **Rapport d'Analyse:** `/optimizations/reports/PERFORMANCE_ANALYSIS_REPORT.md`
- **Code Optimisé Apex:** `/optimizations/apex/PLM_RequireDataMappingLite_OPTIMIZED.cls`
- **Code Optimisé LWC:** `/optimizations/lwc/pLM_ShowRequiredFieldsByOwnerV3_OPTIMIZED.js`
- **Ce Guide:** `/optimizations/reports/MIGRATION_GUIDE.md`

### Contacts

- **Lead Developer:** [Votre Nom]
- **Salesforce Admin:** [Admin Name]
- **Product Owner:** [PO Name]

### Ressources Salesforce

- [Platform Cache Developer Guide](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_cache_namespace_overview.htm)
- [LWC Performance Best Practices](https://developer.salesforce.com/docs/component-library/documentation/en/lwc/lwc.perf_best_practices)
- [Governor Limits](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_gov_limits.htm)

---

## 🎉 CONCLUSION

En suivant ce guide pas à pas, vous allez:

✅ Réduire le temps de chargement de **15-25s à <1s** (-95%)
✅ Améliorer l'expérience utilisateur drastiquement
✅ Réduire la charge serveur de 90%
✅ Scaler jusqu'à 10x plus d'utilisateurs
✅ Minimiser les risques avec une approche progressive

**Bonne migration! 🚀**

---

**Version:** 2.0
**Dernière mise à jour:** 2025-10-27
**Auteur:** Claude Code Performance Team
