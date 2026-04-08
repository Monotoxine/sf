# Documentation Technique — Système d'Anonymisation TEKCO

> **Auteur** : TEKCO Team  
> **Date** : 07/04/2026  
> **Version API Salesforce** : 65.0

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Modèle de données (Custom Metadata Types)](#2-modèle-de-données-custom-metadata-types)
3. [Architecture des classes Apex](#3-architecture-des-classes-apex)
4. [Mécanisme de chaînage des batches](#4-mécanisme-de-chaînage-des-batches)
5. [Patterns d'anonymisation](#5-patterns-danonymisation)
6. [Bypass des triggers (BypassService)](#6-bypass-des-triggers-bypassservice)
7. [Garde sandbox (SandboxGuard)](#7-garde-sandbox-sandboxguard)
8. [Enjeux de Governor Limits](#8-enjeux-de-governor-limits)
9. [Interface LWC Admin](#9-interface-lwc-admin)
10. [Journal d'audit](#10-journal-daudit)
11. [Guide de configuration](#11-guide-de-configuration)

---

## 1. Vue d'ensemble

Le système TEKCO Anonymization permet d'anonymiser en masse les données personnelles dans un org Salesforce sandbox. Il est déclenché manuellement via un composant LWC d'administration, protégé par une custom permission, et bloqué en production par un guard applicatif.

### Flux global

```
LWC Admin (tekcoDataAnonymizationAdmin)
  └─ TEKCO_AnonymizationController.startAnonymization()
       ├─ Vérifie la permission TEKCO_AnonymizeData
       ├─ Vérifie que l'org est un sandbox (SandboxGuard)
       ├─ Active le bypass des triggers (BypassService)
       ├─ Crée un enregistrement TEKCO_AnonymizationAuditLog__c (Status = Running)
       └─ Lance Database.executeBatch(TEKCO_AnonymizationBatch)
            │
            ├── Phase 1 : TEKCO_AnonymizationBatch (un batch par objet)
            │     ├─ Applique les patterns champ par champ
            │     └─ finish() → chaîne vers l'objet suivant ou Phase 2
            │
            ├── Phase 2 : TEKCO_ContentDocumentBatch (un batch par objet)
            │     ├─ Supprime les ContentDocument liés aux enregistrements
            │     └─ finish() → chaîne vers l'objet suivant ou Phase 3
            │
            └── Phase 3 : TEKCO_FieldHistoryBatch (un batch par objet)
                  ├─ Supprime les enregistrements d'historique de champs
                  └─ finish() → restaure le bypass, ferme l'AuditLog
```

---

## 2. Modèle de données (Custom Metadata Types)

### 2.1 `TEKCO_AnonymizationFieldConfig__mdt`

Définit **quel champ** anonymiser, sur **quel objet**, avec **quel pattern**.

| Champ | Type | Rôle |
|-------|------|------|
| `TEKCO_ObjectApiName__c` | Text(255) | API name de l'objet Salesforce (ex. `Account`) |
| `TEKCO_FieldApiName__c` | Text(255) | API name du champ à anonymiser (ex. `FirstName`) |
| `TEKCO_PatternType__c` | Text(100) | DeveloperName du pattern à appliquer |
| `TEKCO_RecordTypeDeveloperName__c` | Text(255) | Restreint la règle à un Record Type précis (vide = tous les RT) |
| `TEKCO_DeleteHistory__c` | Checkbox | Si coché, supprime l'historique de ce champ après anonymisation |
| `TEKCO_IsActive__c` | Checkbox | Inactive = ignorée par le batch |

> **Règle RT-agnostique** : un enregistrement dont `TEKCO_RecordTypeDeveloperName__c` est vide s'applique à **tous** les Record Types, même lorsqu'un filtre RT est actif côté LWC.

### 2.2 `TEKCO_AnonymizationPattern__mdt`

Définit les **paramètres** d'un pattern d'anonymisation.

| Champ | Type | Rôle |
|-------|------|------|
| `DeveloperName` | Text | Identifiant du pattern (ex. `EMAIL_PLUS_EXTERNALID`) |
| `TEKCO_Description__c` | Text(255) | Libellé affiché dans le LWC |
| `TEKCO_BaseEmail__c` | Text(255) | Email de base pour les patterns email |
| `TEKCO_ExternalIdField__c` | Text(255) | Champ de l'objet à utiliser comme ID externe |
| `TEKCO_SsnLength__c` | Number | Longueur cible pour le pattern SSN_SEQUENTIAL |
| `TEKCO_IsActive__c` | Checkbox | Inactive = ignorée |

---

## 3. Architecture des classes Apex

### 3.1 `TEKCO_AnonymizationController`

Contrôleur AuraEnabled exposé au LWC. Toutes les méthodes de lecture utilisent `cacheable=true`.

**Méthodes de lecture**

| Méthode | Rôle |
|---------|------|
| `getBrands()` | Liste les valeurs actives du picklist `TEKCO_Brand__c` sur Account via Schema describe |
| `getObjects()` | Retourne les objets distincts configurés dans les CMT actives (hors DELETE_CONTENT_DOCUMENT) |
| `getRecordTypes(objectApiName)` | Retourne les Record Type Developer Names configurés, scopés à un objet ou tous |
| `getFieldConfigs(objectApiName, selectedRecordTypes)` | Retourne les configs enrichies avec la description du pattern + filtre RT en mémoire |
| `getRecordCount(objectApiName, selectedBrands)` | COUNT() dynamique pour l'aperçu du périmètre |
| `getAuditLogs()` | 20 derniers journaux d'audit, triés par date décroissante |

**Méthode d'écriture**

`startAnonymization(selectedBrands, selectedObjects, excludedFields, selectedRecordTypes, disabledHistoryFields)` :

1. Vérifie la custom permission `TEKCO_AnonymizeData`
2. Appelle `TEKCO_AnonymizationSandboxGuard.assertIsSandbox()`
3. Active le bypass des triggers via `TEKCO_AnonymizationBypassService.activate()`
4. Charge et filtre les CMT configs (filtre RT en mémoire)
5. Répartit les configs en 3 buckets : anonymisation champs / suppression ContentDocument / suppression historique
6. Crée le `TEKCO_AnonymizationAuditLog__c` (Status = Running)
7. Lance `Database.executeBatch(TEKCO_AnonymizationBatch)` avec le premier objet
8. Met à jour l'AuditLog avec le JobId

### 3.2 `TEKCO_AnonymizationBatch` — Phase 1

Implémente `Database.Batchable<SObject>` et `Database.Stateful`.

**`start()`**

- Reconstruit dynamiquement la liste des champs à SELECTer (uniquement les champs utiles + `Id` + `RecordTypeId` si nécessaire)
- Construit un `Map<Id, String> recordTypeDevNameById` si des configs RT-spécifiques existent
- Génère la SOQL query dynamique avec filtre `TEKCO_Brand__c IN :selectedBrands` si applicable
- Retourne un `Database.QueryLocator` (pas de limite des 50 000 lignes en mémoire)

**`execute()`**

Pour chaque enregistrement du scope :
1. Parcourt les fieldConfigs de l'objet
2. Vérifie le Record Type de l'enregistrement si la config est RT-spécifique
3. Appelle `TEKCO_AnonymizationPatternService.applyPattern()`
4. Collecte les enregistrements modifiés
5. `Database.update(recordsToUpdate, false)` — mode allOrNone=false (un échec n'annule pas les autres)
6. Comptabilise `recordsProcessed` / `recordsFailed` (champs `@Stateful`)

**`finish()`**

Cascade de décision :
```
si remainingObjects non vide  → nouveau TEKCO_AnonymizationBatch pour l'objet suivant
sinon si contentDocObjects    → TEKCO_ContentDocumentBatch
sinon si historyConfigs       → TEKCO_FieldHistoryBatch
sinon                         → restore bypass + clôture AuditLog (Success / Partial)
```

### 3.3 `TEKCO_ContentDocumentBatch` — Phase 2

Supprime les fichiers (ContentDocument) attachés aux enregistrements anonymisés.

**`start()`**

```sql
SELECT ContentDocumentId FROM ContentDocumentLink
WHERE LinkedEntityId IN (SELECT Id FROM <Object> [WHERE TEKCO_Brand__c IN :brands])
```

**`execute()`**

- Collecte les `ContentDocumentId` distincts
- `Database.delete(contentDocumentsToDelete, false)`

**`finish()`** — même logique de chaînage que Phase 1.

### 3.4 `TEKCO_FieldHistoryBatch` — Phase 3

Supprime les enregistrements d'historique de champs (`AccountHistory`, `Contact__History`, etc.).

**Conventions de nommage (calculées dynamiquement)**

| Type d'objet | Objet historique | Champ parent |
|-------------|-----------------|-------------|
| Standard (`Account`) | `AccountHistory` | `AccountId` |
| Custom (`MyObj__c`) | `MyObj__History` | `ParentId` |

**`start()`**

```sql
SELECT Id FROM <ObjectHistory>
WHERE Field IN ('FieldName1', 'FieldName2')
AND <ParentIdField> IN (SELECT Id FROM <Object> [WHERE TEKCO_Brand__c IN :brands])
```

**`finish()`** — restaure le bypass et ferme l'AuditLog si c'est le dernier batch.

---

## 4. Mécanisme de chaînage des batches

### Pourquoi chaîner ?

Salesforce impose une seule transaction par batch. Anonymiser plusieurs objets en série, puis supprimer les fichiers, puis supprimer l'historique, nécessite plusieurs batches séquentiels.

### Comment fonctionne le chaînage ?

La méthode `finish()` est le **seul endroit valide** pour appeler `Database.executeBatch()` à l'intérieur d'un batch. Chaque batch reçoit en paramètre de constructeur les listes des travaux restants.

**Transmission de l'état via `Database.Stateful`**

Sans `Database.Stateful`, les variables d'instance sont réinitialisées entre chaque chunk `execute()`. Avec ce marqueur :
- `remainingObjects`, `contentDocObjects`, `historyConfigs` survivent à tous les chunks
- `recordsProcessed`, `recordsFailed`, `errors` s'accumulent correctement
- `bypassSnapshot` reste disponible jusqu'au dernier `finish()`

**Passage de contexte entre batches**

```
AnonymizationBatch(objectN, configs, patterns, brands, auditLogId,
                   remainingObjects, contentDocObjects, historyConfigs, bypassSnapshot)
    │
    └─ finish() → new ContentDocumentBatch(nextObject, brands, auditLogId,
                                           remainingContentDocObjects, historyConfigs, bypassSnapshot)
                      │
                      └─ finish() → new FieldHistoryBatch(nextObject, configs, brands, auditLogId,
                                                          remainingHistoryConfigs, bypassSnapshot)
```

Aucune requête SOQL supplémentaire n'est nécessaire entre batches : tout le contexte voyage dans les constructeurs.

---

## 5. Patterns d'anonymisation

Implémentés dans `TEKCO_AnonymizationPatternService`.

| Pattern | Comportement | Exemple |
|---------|-------------|---------|
| `NAME_FIRST_LETTER` | Première lettre + valeur du champ ExternalId | `Jean` + `EXT001` → `JEXT001` |
| `PHONE_MASK` | 4 premiers chars + zéros | `+33123456789` → `+33100000000` |
| `EMAIL_PLUS_EXTERNALID` | Email de base avec +ExternalId en alias | `sf@al.com` + `EXT001` → `sf+EXT001@al.com` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Idem + suffixe du sous-domaine org | `sf+EXT001+myorg--uat1@al.com` |
| `SSN_SEQUENTIAL` | Séquence de chiffres cyclique 1–9 | longueur 13 → `1234567891234` |
| `LOREM_IPSUM` | Texte Lorem ipsum fixe | — |
| `ADDRESS_STREET_RANDOM` | Ajoute 1–20 au premier nombre de l'adresse | `123 Rue de la Paix` → `137 Rue de la Paix` |
| `KEEP` | Aucune modification | — |
| `DELETE_CONTENT_DOCUMENT` | Traité par ContentDocumentBatch (ignoré ici) | — |
| `EMAIL_MESSAGE_LOREM` | Traité par un batch dédié (ignoré ici) | — |

**Sous-domaine org** : calculé une seule fois par transaction via `URL.getOrgDomainUrl()` et mis en cache dans une propriété lazy (`orgSubdomain`), évitant des appels répétés.

---

## 6. Bypass des triggers (BypassService)

### Problème

Lors de l'anonymisation, chaque `Database.update()` déclenche les triggers Apex sur les objets traités. Ces triggers (validation, intégration, calculs) sont coûteux, inutiles et peuvent même bloquer les mises à jour anonymisées.

### Solution

`TEKCO_AnonymizationBypassService` manipule la Custom Setting hiérarchique `TEKCO_BypassSettings__c` au niveau utilisateur avant le lancement du batch.

**Priorité hiérarchique** : Utilisateur > Profil > Org. Écrire au niveau utilisateur n'affecte **que** l'utilisateur courant pendant l'exécution du batch.

### Flux d'activation

**`activate()`** :
1. Vérifie si un enregistrement utilisateur existait déjà (`SetupOwnerId = userId`)
2. Mémorise l'état d'origine dans un `BypassSnapshot` (`Database.Stateful`)
3. Met tous les champs booléens à `true` dynamiquement via Schema describe
4. `upsert` de l'enregistrement utilisateur

**`restore(snapshot)`** (appelé dans le dernier `finish()`) :
- Si aucun enregistrement n'existait avant → `delete` de l'enregistrement créé
- Si un enregistrement existait → `upsert` avec les valeurs d'origine

### Découverte dynamique des champs

```apex
Map<String, Schema.SObjectField> fieldMap =
    Schema.SObjectType.TEKCO_BypassSettings__c.fields.getMap();
for (String fieldName : fieldMap.keySet()) {
    Schema.DescribeFieldResult dfr = fieldMap.get(fieldName).getDescribe();
    if (dfr.getType() == Schema.DisplayType.BOOLEAN && dfr.isUpdateable()) {
        bypassRecord.put(fieldName, true);
    }
}
```

Aucun champ n'est hardcodé : tout nouveau champ booléen ajouté à `TEKCO_BypassSettings__c` sera automatiquement activé.

---

## 7. Garde sandbox (SandboxGuard)

`TEKCO_AnonymizationSandboxGuard.assertIsSandbox()` est appelé à **deux niveaux** :
1. Dans `startAnonymization()` du contrôleur (avant toute DML)
2. Dans `start()` de chaque batch (protection contre un déploiement accidentel en prod)

```apex
Organization org = [SELECT IsSandbox FROM Organization LIMIT 1];
if (!org.IsSandbox) {
    throw new ProductionOrgException('ABORT: ...');
}
```

Si l'org est une production, une exception est levée immédiatement. Aucune donnée n'est modifiée.

---

## 8. Enjeux de Governor Limits

### 8.1 Limites SOQL (100 par transaction)

| Situation | Approche |
|-----------|----------|
| Chargement des configs CMT | 1 seule requête par batch dans `start()` |
| Filtre Record Type en mémoire | Filtrage en Apex (`if/continue`) plutôt qu'un WHERE SOQL pour éviter l'expression `NULL OR IN (...)` non supportée |
| `buildPatternMap()` | 1 requête dans le contrôleur, résultat passé en constructeur (évite une requête par batch) |
| RecordType IDs | 1 requête dans `start()` uniquement si des configs RT-spécifiques existent |

### 8.2 Mémoire heap (6 MB en batch)

| Situation | Approche |
|-----------|----------|
| Lecture des enregistrements | `Database.getQueryLocator` — streaming, pas de liste en mémoire |
| Chargement des configs CMT | Fait une fois dans le contrôleur pour Phase 1 ; rechargé depuis CMT dans `loadFieldConfigs()` pour les objets suivants (CMT = cache local, pas de SOQL comptabilisé) |
| Patterns | `Map<String, TEKCO_AnonymizationPattern__mdt>` passé en constructeur, partagé entre les batches Phase 1 |
| Errors list | Plafonnée à 50 entrées (`MAX_CAPTURED_ERRORS`) |

### 8.3 DML rows (10 000 par transaction)

Le batch size par défaut est **200 enregistrements** par chunk. Chaque `execute()` émet **1 DML statement** (`Database.update` ou `Database.delete`) pour les 200 enregistrements du scope, bien en dessous des limites.

### 8.4 CPU time (10s par transaction)

- Pas de boucles imbriquées O(n²) : la boucle externe sur `scope` (~200) × la boucle interne sur `fieldConfigs` (~20 max) = ~4 000 itérations par chunk, largement acceptable.
- `applyPattern()` utilise `switch on` (O(1)) plutôt qu'une chaîne de `if/else`.
- L'orgSubdomain est calculé une seule fois par transaction (lazy property).

### 8.5 `Database.executeBatch` dans `finish()`

`Database.executeBatch` est interdit dans `execute()` mais autorisé dans `finish()`. C'est la seule raison pour laquelle le chaînage est placé exclusivement dans `finish()`.

### 8.6 CMT et SOQL governor

Les Custom Metadata Types sont **exempt** des limites SOQL de gouverneur (`SELECT ... FROM CustomMetadata__mdt` ne consomme pas de quota SOQL). Cependant, la requête est tout de même exécutée une seule fois là où c'est possible pour la lisibilité et la cohérence.

---

## 9. Interface LWC Admin

**Composant** : `tekcoDataAnonymizationAdmin`

### Filtres disponibles

| Filtre | Source | Comportement |
|--------|--------|-------------|
| Marques | Picklist `Account.TEKCO_Brand__c` | Multi-select ; "Select All" disponible |
| Objets | CMT configs actives (hors DELETE_CONTENT_DOCUMENT) | Multi-select ; scope le filtre RT |
| Record Types | CMT configs, scopés à l'objet sélectionné si unique | Multi-select ; vide = tous les RT |

### Aperçu du périmètre (Preview Scope)

Clique sur "Preview Scope" → appels parallèles à `getRecordCount()` pour chaque objet sélectionné (ou tous si aucun) → affichage du nombre d'enregistrements concernés par objet.

### Table des champs

Après preview, la table affiche tous les champs configurés groupés par objet :

| Colonne | Interactif | Rôle |
|---------|-----------|------|
| Run | Checkbox | Décocher = exclut le champ de cette exécution (`excludedFields`) |
| Field | — | API name du champ |
| Pattern | Badge | Type de pattern appliqué |
| Record Type | — | RT cible (vide = tous) |
| Del. History | Checkbox | Décocher = désactive la suppression d'historique pour ce champ (`disabledHistoryFields`) |
| Description | — | Description du pattern depuis CMT |

### Modal de confirmation

Clic sur "Launch Anonymization" → modal SLDS récapitulatif avec :
- Marques, Objets, Record Types sélectionnés
- Champs exclus du run
- Champs dont la suppression d'historique a été désactivée

**Annuler** ferme le modal sans action. **Confirmer le lancement** déclenche `startAnonymization()`.

### Polling du journal d'audit

Après un lancement réussi, un `setInterval` de 5 secondes rafraîchit automatiquement les `auditLogs`. Il s'arrête dès qu'aucun log n'est plus en statut `Running`.

---

## 10. Journal d'audit

Objet : `TEKCO_AnonymizationAuditLog__c`

| Champ | Contenu |
|-------|---------|
| `TEKCO_Status__c` | `Running` → `Success` / `Partial` / `Failed` |
| `TEKCO_ObjectApiName__c` | Objets traités (concaténés) |
| `TEKCO_BrandFilter__c` | Marques filtrées ou `ALL` |
| `TEKCO_RecordsProcessed__c` | Nombre d'enregistrements mis à jour avec succès |
| `TEKCO_RecordsFailed__c` | Nombre d'échecs DML |
| `TEKCO_StartTime__c` / `TEKCO_EndTime__c` | Horodatage début / fin |
| `TEKCO_JobId__c` | ID du premier job Apex Batch |
| `TEKCO_TriggeredBy__r.Name` | Utilisateur déclencheur |
| `TEKCO_ErrorMessage__c` | Messages d'erreur (max 50 lignes) |

**Statut `Partial`** : au moins un enregistrement a échoué mais d'autres ont réussi (grâce à `allOrNone=false`).

---

## 11. Guide de configuration

### Ajouter un nouvel objet à anonymiser

1. Créer un ou plusieurs enregistrements `TEKCO_AnonymizationFieldConfig__mdt` :
   - `TEKCO_ObjectApiName__c` = API name de l'objet
   - `TEKCO_FieldApiName__c` = API name du champ
   - `TEKCO_PatternType__c` = DeveloperName d'un `TEKCO_AnonymizationPattern__mdt` actif
   - `TEKCO_IsActive__c` = true

2. Si la suppression des fichiers est nécessaire, ajouter un enregistrement avec `TEKCO_PatternType__c = DELETE_CONTENT_DOCUMENT` (le champ `TEKCO_FieldApiName__c` est ignoré pour ce type).

3. Si la suppression de l'historique est nécessaire pour un champ, cocher `TEKCO_DeleteHistory__c`.

### Ajouter un nouveau pattern

1. Créer un enregistrement `TEKCO_AnonymizationPattern__mdt` avec un `DeveloperName` unique.
2. Remplir `TEKCO_Description__c`, `TEKCO_BaseEmail__c`, `TEKCO_ExternalIdField__c` ou `TEKCO_SsnLength__c` selon le type.
3. Implémenter le comportement dans `TEKCO_AnonymizationPatternService.applyPattern()` en ajoutant un `when` dans le `switch on`.

### Ajouter un nouveau champ bypass

Ajouter un champ `Checkbox` à `TEKCO_BypassSettings__c`. Il sera automatiquement activé par `TEKCO_AnonymizationBypassService` sans modification de code.

### Commande de déploiement (delta)

```bash
sf project deploy start --manifest manifest/package-delta.xml
```

Le fichier `manifest/package-delta.xml` couvre les classes Apex, les CMT fields, l'objet CMT et le LWC.
