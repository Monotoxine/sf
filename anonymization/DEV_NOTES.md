# TEKCO Anonymization — Notes techniques personnelles

> Doc de navigation rapide. Pas pour les utilisateurs finaux, pas pour le déploiement — juste pour lire et comprendre le code.

---

## Structure des fichiers

```
anonymization/main/default/
│
├── classes/
│   ├── TEKCO_AnonymizationController.cls       ← point d'entrée LWC (AuraEnabled)
│   ├── TEKCO_AnonymizationBatch.cls            ← Phase 1 : mise à jour des champs
│   ├── TEKCO_ContentDocumentBatch.cls          ← Phase 2 : suppression fichiers
│   ├── TEKCO_FieldHistoryBatch.cls             ← Phase 3 : suppression historique
│   ├── TEKCO_AnonymizationPatternService.cls   ← algo de chaque pattern (pure logic)
│   ├── TEKCO_AnonymizationBypassService.cls    ← active/restore TEKCO_BypassSettings__c
│   └── TEKCO_AnonymizationSandboxGuard.cls     ← bloque si org = Production
│
├── lwc/tekcoDataAnonymizationAdmin/            ← interface admin (onglet SF)
│
├── objects/
│   ├── TEKCO_AnonymizationAuditLog__c/         ← trace de chaque run
│   ├── TEKCO_AnonymizationFieldConfig__mdt/    ← "quoi anonymiser" (config centrale)
│   └── TEKCO_AnonymizationPattern__mdt/        ← "comment anonymiser" (algo params)
│
├── customMetadata/                             ← valeurs des 2 MDTs ci-dessus
├── permissionsets/TEKCO_AnonymizationAdmin     ← qui peut lancer l'anonymisation
└── manifest/package-anonymization.xml         ← déploiement standalone
```

---

## La "base de données" qui pilote tout

Tout le comportement est dirigé par 2 Custom Metadata Types. Pas de code à changer pour ajouter un objet ou un champ — tout se fait dans les CMT records.

### TEKCO_AnonymizationFieldConfig__mdt — "quoi anonymiser"

Un record = un champ d'un objet à anonymiser.

| Champ | Rôle |
|---|---|
| `TEKCO_ObjectApiName__c` | Objet cible (ex: `Account`) |
| `TEKCO_FieldApiName__c` | Champ cible (ex: `PersonEmail`) |
| `TEKCO_PatternType__c` | Clé vers Pattern__mdt (ex: `EMAIL_PLUS_EXTERNALID`) |
| `TEKCO_IsActive__c` | Si false → ignoré partout |
| `TEKCO_RecordTypeDeveloperName__c` | Filtre RT (vide = tous les RTs) |
| `TEKCO_DeleteHistory__c` | Si true → Phase 3 supprime l'historique |
| `TEKCO_ParentObjectApiName__c` | Pour les objets sans Brand (ex: `Account` pour `EmailMessage`) |
| `TEKCO_ParentLookupFieldApiName__c` | Lookup vers le parent (ex: `ParentId`) |
| `TEKCO_ParentRecordTypeDeveloperName__c` | Filtre RT côté parent |

### TEKCO_AnonymizationPattern__mdt — "comment anonymiser"

Un record = un algorithme de transformation.

| Champ | Rôle |
|---|---|
| `DeveloperName` | Clé = valeur dans `TEKCO_PatternType__c` ci-dessus |
| `TEKCO_IsActive__c` | Si false → le pattern est ignoré |
| `TEKCO_BaseEmail__c` | Email de base pour les patterns EMAIL_* |
| `TEKCO_ExternalIdField__c` | Champ ExternalId à lire sur l'enregistrement |
| `TEKCO_SsnLength__c` | Longueur cible pour SSN_SEQUENTIAL |
| `TEKCO_Description__c` | Texte affiché dans le LWC |

---

## Les patterns et ce qu'ils font

Tout le code est dans `TEKCO_AnonymizationPatternService.cls` — méthode `applyPattern()`.

| Pattern | Entrée | Sortie | Ligne |
|---|---|---|---|
| `NAME_FIRST_LETTER` | `"Jean"` | `"JEXT001"` (1ère lettre + ExternalId) | ~108 |
| `PHONE_MASK` | `"+33123456789"` | `"+33100000000"` (4 chars + zéros) | ~125 |
| `EMAIL_PLUS_EXTERNALID` | `"sf@air.com"` | `"sf+EXT001@air.com"` | ~145 |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | `"sf@air.com"` | `"sf+EXT001@air.com.fr.mmedlej"` (suffixe après domaine) | ~145 |
| `SSN_SEQUENTIAL` | `"1234567890"` | `"1234567891"` (séquentiel 1-9, même longueur) | ~182 |
| `LOREM_IPSUM` | n'importe quoi | texte lorem fixe | ~81 |
| `ADDRESS_STREET_RANDOM` | `"123 Rue de la Paix"` | `"137 Rue de la Paix"` (num + offset 1-20) | ~204 |
| `DELETE_CONTENT_DOCUMENT` | — | null → géré par ContentDocumentBatch | ~86 |
| `EMAIL_MESSAGE_LOREM` | — | null → géré dans AnonymizationBatch directement | ~89 |

> **Note EMAIL_MESSAGE_LOREM** : pas dans le service. La logique est dans `AnonymizationBatch.execute()` lignes ~194-209.
> Draft → remplace le texte par lorem. Non-Draft → supprime le record entier.

---

## Flux d'exécution complet

```
[LWC] Clic "Run"
   └─▶ TEKCO_AnonymizationController.startAnonymization()          [ligne 302]
           │
           ├─ Vérifie permission TEKCO_AnonymizeData                [ligne 309]
           ├─ Vérifie sandbox                                       [ligne 315]
           ├─ BypassService.activate() → active tous les flags      [ligne 334]
           ├─ Construit 3 listes :
           │     objectsToProcess    → Phase 1 (champs normaux)
           │     contentDocConfigs   → Phase 2 (suppression fichiers)
           │     historyConfigs      → Phase 3 (suppression historique)
           ├─ Crée TEKCO_AnonymizationAuditLog__c (Status=Running)  [ligne 438]
           └─ executeBatch(AnonymizationBatch)
                   │
                   ▼
           ┌──────────────────────────────────────────┐
           │  PHASE 1 : AnonymizationBatch             │
           │  start()   → SOQL dynamique               │  [ligne 92]
           │  execute() → applyPattern() par champ     │  [ligne 179]
           │  finish()  → chain ou passe à Phase 2     │  [ligne 300]
           └──────────────────────────────────────────┘
                   │  (si d'autres objets dans remainingObjects → re-chain Phase 1)
                   │  (si contentDocConfigs non vide)
                   ▼
           ┌──────────────────────────────────────────┐
           │  PHASE 2 : ContentDocumentBatch           │
           │  Un batch PAR config CMT (pas par objet)  │
           │  start()   → ContentDocumentLink query    │  [ligne 79]
           │  execute() → delete ContentDocument       │  [ligne 140]
           │  finish()  → chain ou passe à Phase 3     │  [ligne 177]
           └──────────────────────────────────────────┘
                   │  (si historyConfigs non vide)
                   ▼
           ┌──────────────────────────────────────────┐
           │  PHASE 3 : FieldHistoryBatch              │
           │  Un batch PAR objet                       │
           │  start()   → SELECT sur ObjectHistory     │  [ligne 80]
           │  execute() → delete scope direct          │  [ligne 144]
           │  finish()  → chain ou fin de chaîne       │  [ligne 168]
           └──────────────────────────────────────────┘
                   │
                   ▼
           BypassService.restore()  → remet les flags à leur valeur d'origine
           AuditLog → Status = Success / Partial / Failed
```

---

## Ce que chaque batch reçoit en paramètre

Tous les batches se passent les mêmes données "stateful" d'un bout à l'autre de la chaîne.

```apex
// Ce qui "voyage" dans toute la chaîne :
String                                   objectApiName         // l'objet en cours
List<TEKCO_AnonymizationFieldConfig__mdt> fieldConfigs         // configs du batch en cours
Map<String,TEKCO_AnonymizationPattern__mdt> patternsByType     // tous les patterns actifs
List<String>                              selectedBrands        // filtres brand sélectionnés
Id                                        auditLogId            // pour écrire les résultats
List<String>                              remainingObjects      // Phase 1 restante
List<TEKCO_AnonymizationFieldConfig__mdt> contentDocConfigs    // Phase 2 restante
List<TEKCO_AnonymizationFieldConfig__mdt> historyConfigs       // Phase 3 restante
BypassSnapshot                            bypassSnapshot        // pour restore() en fin
Map<String,List<String>>                  parentFiltersByObject // [parentObj, lookupField, RT]
```

---

## Le filtre parent (parentFiltersByObject)

Certains objets n'ont pas de `TEKCO_Brand__c` (ex: `EmailMessage`). On filtre via leur parent.

```
parentFiltersByObject = {
  "EmailMessage" → ["Account", "ParentId", ""]
  //                 parentObj  lookupField  parentRT (vide = tous)
}
```

Dans `start()` de chaque batch, si l'objet a un parent configuré :
- Phase 1 : `WHERE ParentId IN (SELECT Id FROM Account WHERE TEKCO_Brand__c IN :brands)`
- Phase 2 : résout d'abord les IDs enfants en mémoire (pas de sous-requête imbriquée dans ContentDocumentLink)
- Phase 3 : même résolution upfront des IDs enfants

---

## Le Bypass (TEKCO_BypassSettings__c)

Logique dans `TEKCO_AnonymizationBypassService.cls`.

```
activate()  → lit l'état actuel du user-level record
            → met tous les boolean fields à true
            → retourne un BypassSnapshot (pour restore)

restore()   → si pas de record préexistant : upsert avec tous les booleans à false
            → si record préexistant : upsert avec les valeurs d'origine
```

> Pourquoi `upsert` et pas `delete` ? Parce qu'un record Profile/Org level avec bypass=true
> resterait actif après la suppression du User level. On force explicitement `false`.

---

## Le Sandbox Guard

`TEKCO_AnonymizationSandboxGuard.assertIsSandbox()` est appelé à 3 endroits :
1. `TEKCO_AnonymizationController.startAnonymization()` — avant tout DML
2. `TEKCO_AnonymizationBatch.start()` — au début de chaque chunk Phase 1
3. `TEKCO_ContentDocumentBatch.start()` — au début Phase 2
4. `TEKCO_FieldHistoryBatch.start()` — au début Phase 3

Si `IsSandbox = false` → exception immédiate, rien ne s'exécute.

---

## L'Audit Log (TEKCO_AnonymizationAuditLog__c)

Créé dans `startAnonymization()` avec `Status = Running`. Mis à jour par chaque `finish()`.

| Status | Quand |
|---|---|
| `Running` | Pendant la chaîne (après chaque batch intermédiaire) |
| `Success` | Fin de chaîne, 0 erreur DML |
| `Partial` | Fin de chaîne, au moins 1 erreur DML |
| `Failed` | Exception dans un `finish()` (chaîne cassée) |

Erreurs DML : accumulées dans `errors` (max 50), stockées dans `TEKCO_ErrorMessage__c` séparées par `\n`.

---

## Nommage des objets History (Phase 3)

```
Standard → Account      HistoryObject = AccountHistory,  parentIdField = AccountId
Custom   → MyObj__c     HistoryObject = MyObj__History,  parentIdField = ParentId
```

Logique dans `TEKCO_FieldHistoryBatch.computeHistoryObjectName()` et `computeParentIdFieldName()`.

---

## Questions fréquentes en lisant le code

**Pourquoi `Database.update(records, false)` et pas juste `update` ?**
Le `false` = allOrNone=false. Un record en erreur ne fait pas rollback des autres. Les erreurs sont capturées individuellement.

**Pourquoi `remainingObjects.remove(0)` au lieu d'un index ?**
Les batches sont stateful. `remove(0)` extrait et réduit la liste à chaque `finish()`, donc le prochain batch reçoit une liste d'un élément de moins.

**Pourquoi `popHistoryConfigsForObject()` dans les deux batches ?**
`historyConfigs` contient les configs de TOUS les objets mélangés. Cette méthode extrait ceux du prochain objet et laisse le reste pour la suite de la chaîne.

**Pourquoi `contentDocConfigs` contient les configs complètes et pas juste les noms d'objets ?**
Parce que `ContentDocumentBatch` a besoin du `TEKCO_RecordTypeDeveloperName__c` pour filtrer — un même objet peut avoir plusieurs configs avec des RTs différents, chacun donnant un batch séparé.

**Pourquoi Phase 2 résout les IDs enfants en mémoire (pas de subquery) ?**
`ContentDocumentLink` n'accepte pas de sous-requête imbriquée dans le `WHERE LinkedEntityId IN`. On doit d'abord récupérer les IDs en mémoire puis les passer directement.

---

## Comment ajouter un nouvel objet à anonymiser

1. Créer des records `TEKCO_AnonymizationFieldConfig__mdt` — un par champ à anonymiser
2. Remplir `TEKCO_ObjectApiName__c`, `TEKCO_FieldApiName__c`, `TEKCO_PatternType__c`
3. Si l'objet n'a pas de `TEKCO_Brand__c` → remplir les 3 champs `Parent*`
4. Si on veut supprimer l'historique → cocher `TEKCO_DeleteHistory__c`
5. Si on veut supprimer les fichiers → créer un config avec `TEKCO_PatternType__c = DELETE_CONTENT_DOCUMENT`
6. **Aucun code à modifier**

---

## Comment ajouter un nouveau pattern

1. Créer un record `TEKCO_AnonymizationPattern__mdt` avec le DeveloperName voulu
2. Ajouter un `when 'MON_PATTERN'` dans `TEKCO_AnonymizationPatternService.applyPattern()` (~ligne 64)
3. Implémenter la méthode privée correspondante dans le même fichier
4. Ajouter le nouveau DeveloperName dans le header comment du fichier

---

## Déployer uniquement ce système

```bash
# Déploiement complet du système d'anonymisation
sf project deploy start --source-dir anonymization

# ou via le manifest dédié
sf project deploy start --manifest anonymization/../manifest/package-anonymization.xml
```
