# Documentation fonctionnelle — Système d'anonymisation TEKCO

## Vue d'ensemble

Le système d'anonymisation TEKCO permet de masquer ou supprimer des données personnelles (PII) dans une org Salesforce sandbox. Il est piloté par une interface d'administration LWC et s'exécute via une chaîne de traitements Batch Apex asynchrones.

**Contrainte de sécurité fondamentale** : le système est bloqué de manière irréversible sur les orgs de production. Toute tentative d'exécution hors sandbox lève une exception et arrête immédiatement le traitement, sans aucune modification de données.

---

## Architecture générale

```
Interface LWC (tekcoDataAnonymizationAdmin)
        │
        ▼
TEKCO_AnonymizationController  (Apex @AuraEnabled)
        │
        ▼
Phase 1 — TEKCO_AnonymizationBatch         (anonymisation des champs)
        │
        ▼
Phase 2 — TEKCO_ContentDocumentBatch       (suppression des fichiers joints)
        │
        ▼
Phase 3 — TEKCO_FieldHistoryBatch          (suppression de l'historique des champs)
```

Les trois phases se chaînent automatiquement : chaque batch lance le suivant dans sa méthode `finish()`. Si aucun objet n'est configuré pour une phase, celle-ci est sautée et la suivante démarre directement.

---

## Configuration par Custom Metadata Types (CMT)

### TEKCO_AnonymizationFieldConfig__mdt — Configuration des champs

Chaque enregistrement représente une règle d'anonymisation pour un champ donné.

| Champ | Rôle |
|---|---|
| `TEKCO_ObjectApiName__c` | API name de l'objet Salesforce (ex. `Account`) |
| `TEKCO_FieldApiName__c` | API name du champ à anonymiser (ex. `PersonEmail`) |
| `TEKCO_PatternType__c` | Identifiant du pattern à appliquer (ex. `EMAIL_PLUS_SFID`) |
| `TEKCO_IsActive__c` | Active ou désactive la règle sans la supprimer |
| `TEKCO_RecordTypeDeveloperName__c` | Restreint la règle à un Record Type précis (optionnel) |
| `TEKCO_DeleteHistory__c` | Si `true`, l'historique du champ est supprimé en Phase 3 |

**Cas particulier `DELETE_CONTENT_DOCUMENT`** : quand `TEKCO_PatternType__c = 'DELETE_CONTENT_DOCUMENT'`, le champ ne représente pas une règle sur un champ mais l'instruction de supprimer les `ContentDocument` liés aux records de l'objet. Ce type de config est traité en Phase 2 et jamais en Phase 1.

### TEKCO_AnonymizationPattern__mdt — Définition des patterns

Chaque enregistrement décrit comment un pattern transforme une valeur.

| Champ | Rôle |
|---|---|
| `TEKCO_IsActive__c` | Pattern actif ou non |
| `TEKCO_BaseEmail__c` | Adresse email de base pour les patterns email (optionnel) |
| `TEKCO_ExternalIdField__c` | Champ utilisé comme identifiant externe (optionnel) |
| `TEKCO_SsnLength__c` | Longueur cible pour le pattern `SSN_SEQUENTIAL` (optionnel) |
| `TEKCO_Description__c` | Description lisible du pattern |

---

## Patterns d'anonymisation disponibles

### Patterns sur les noms

| Pattern | Algorithme | Exemple |
|---|---|---|
| `NAME_FIRST_LETTER` | Première lettre + ExternalId du champ configuré | `Jean` + `EXT001` → `JEXT001` |
| `NAME_FIRST_LETTER_SFID` | Première lettre + Salesforce Id du record | `Jean` + `0035g00000XyZAA` → `J0035g00000XyZAA` |

### Patterns sur les emails

| Pattern | Algorithme | Exemple |
|---|---|---|
| `EMAIL_PLUS_EXTERNALID` | Email de base avec alias `+ExternalId` | `sf_sap+EXT001@airliquide.com` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Idem + suffixe subdomain sandbox | `sf_sap+EXT001@airliquide.com.fr.mmedlej` |
| `EMAIL_PLUS_SFID` | Email de base avec alias `+SalesforceId` | `sf_sap+0035g00000XyZAA@airliquide.com` |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | Idem + suffixe subdomain sandbox | `sf_sap+0035g00000XyZAA@airliquide.com.fr.mmedlej` |

Pour les patterns email :
- Si `TEKCO_BaseEmail__c` est renseigné dans le pattern CMT, c'est cet email qui sert de base.
- Sinon, c'est la valeur actuelle du champ qui sert de base.
- Le subdomain est dérivé automatiquement du domaine de l'org (`URL.getOrgDomainUrl()`).

### Patterns sur les téléphones

| Pattern | Algorithme | Exemple |
|---|---|---|
| `PHONE_MASK` | Conserve les 4 premiers caractères, remplace le reste par des zéros | `+33123456789` → `+33100000000` |

### Patterns sur les adresses

| Pattern | Algorithme | Exemple |
|---|---|---|
| `ADDRESS_STREET_RANDOM` | Trouve le premier nombre dans la chaîne et lui ajoute une valeur aléatoire entre 1 et 20 | `123 Rue de la Paix` → `137 Rue de la Paix` |

### Patterns divers

| Pattern | Algorithme | Exemple |
|---|---|---|
| `SSN_SEQUENTIAL` | Génère une séquence de chiffres 1–9 cyclique, à la même longueur que la valeur originale | `123456789` (9 chars) → `123456789` |
| `LOREM_IPSUM` | Remplace par un texte Lorem Ipsum fixe | *(texte fixe)* |
| `KEEP` | Ne modifie pas la valeur — champ ignoré | *(inchangé)* |

### Patterns spéciaux (comportement batch)

| Pattern | Comportement |
|---|---|
| `DELETE_CONTENT_DOCUMENT` | Déclenche la suppression des `ContentDocument` liés aux records de l'objet en Phase 2. Jamais appliqué en Phase 1. |
| `EMAIL_MESSAGE_LOREM` | Sur les `EmailMessage` : si statut `Draft` → applique Lorem Ipsum sur le champ. Si autre statut → supprime le record entier. Le filtrage se fait via `Parent.TEKCO_Brand__c` (relation vers le Case parent). |

---

## Interface d'administration (LWC)

### Filtres disponibles

**Brands** : sélection multiple depuis le Global Picklist Value Set `TEKCO_Brands`. Les labels sont affichés (pas les API values). Si aucune brand n'est sélectionnée, le traitement s'applique à tous les records sans filtre brand.

**Objets** : sélection multiple des objets à traiter. Si aucun objet n'est sélectionné, tous les objets configurés dans les CMT sont inclus.

**Record Types** : visible uniquement si au moins un champ configuré pour les objets sélectionnés porte un `TEKCO_RecordTypeDeveloperName__c`. Si aucun Record Type n'est sélectionné, toutes les configs s'appliquent indépendamment du Record Type.

### Preview du scope

Le bouton **Preview Scope** calcule le nombre de records qui seront traités par objet, en appliquant les mêmes filtres (brand, Record Type) que le traitement réel. Un appel Apex indépendant est émis par objet en parallèle (`Promise.all`). Le count est ignoré si l'objet ne possède pas le champ `TEKCO_Brand__c` ou `RecordTypeId`.

### Table des champs à anonymiser

Affiche toutes les règles actives pour les objets sélectionnés. Chaque ligne est cochable/décochable pour exclure temporairement un champ du run en cours, sans modifier la configuration CMT. La colonne **Del. History** indique si l'historique du champ sera supprimé en Phase 3.

### Lancement

Un clic sur **Start** ouvre une modale de confirmation récapitulant les objets, brands et Record Types sélectionnés. La confirmation déclenche l'appel Apex `startAnonymization`.

### Journal des runs

Affiche les 20 derniers runs avec statut (`Running`, `Success`, `Partial`, `Failed`), nombre de records traités/échoués, utilisateur déclencheur et horodatage.

---

## Chaîne de traitement Batch

### Phase 1 — TEKCO_AnonymizationBatch

Traite les champs des records de chaque objet configuré.

**Filtrage des records :**
- Si un filtre parent est configuré (`parentFiltersByObject`) : les records sont filtrés via une sous-requête SOQL sur l'objet parent (ex. `AccountId IN (SELECT Id FROM Account WHERE TEKCO_Brand__c IN :brands)`).
- Sinon, si l'objet possède `TEKCO_Brand__c` : filtre direct sur le champ.
- Cas `EMAIL_MESSAGE_LOREM` sans filtre parent : filtre via `Parent.TEKCO_Brand__c` (relation polymorphique vers le Case).

**Traitement par record :**
- Pour chaque champ configuré et actif, le pattern est appliqué si la nouvelle valeur est différente de l'ancienne.
- Si `TEKCO_RecordTypeDeveloperName__c` est renseigné sur la config, le champ n'est modifié que si le record correspond à ce Record Type.
- Les records modifiés sont mis à jour via `Database.update(allOrNone=false)`.
- Les `EmailMessage` non-Draft sont supprimés via `Database.delete(allOrNone=false)`.

**Chaînage :** après le dernier objet, si des configs `DELETE_CONTENT_DOCUMENT` existent, la Phase 2 démarre. Sinon, si des configs `DeleteHistory` existent, la Phase 3 démarre. Sinon, le run est finalisé.

### Phase 2 — TEKCO_ContentDocumentBatch

Supprime les `ContentDocument` liés aux records de l'objet configuré avec `DELETE_CONTENT_DOCUMENT`.

- Requête sur `ContentDocumentLink` pour récupérer les IDs de documents liés.
- Suppression des `ContentDocument` correspondants.
- Si plusieurs objets sont configurés avec `DELETE_CONTENT_DOCUMENT`, un batch est chaîné par objet.

### Phase 3 — TEKCO_FieldHistoryBatch

Supprime les enregistrements d'historique (`__History`) pour les champs dont `TEKCO_DeleteHistory__c = true`.

- Supporte les objets standard (`AccountHistory`, `ContactId`) et custom (`__History`, `ParentId`).
- Si l'historique n'est pas activé sur l'objet, la phase est skippée avec un message dans le log.
- Chaîné par objet, comme la Phase 1.

### Scalabilité

Toutes les requêtes de scope sont construites via `Database.getQueryLocator` (supporte jusqu'à 50 millions de records). Le filtrage parent utilise des sous-requêtes SOQL imbriquées (jusqu'à 2 niveaux, maximum supporté par Salesforce), sans jamais charger d'IDs en mémoire.

---

## Services transversaux

### TEKCO_AnonymizationBypassService — Bypass des automations

Avant le démarrage de la chaîne, tous les champs booléens de `TEKCO_BypassSettings__c` (Hierarchy Custom Setting) sont passés à `true` pour l'utilisateur courant. Cela désactive les triggers, flows et validations qui pourraient bloquer les DML d'anonymisation. L'état original est restauré à la fin de la chaîne, quelle que soit l'issue (succès ou échec).

### TEKCO_AnonymizationSandboxGuard — Blocage production

Vérifié au début de chaque `start()` dans les trois batchs. Si `Organization.IsSandbox = false`, une exception est levée immédiatement. Cette vérification est intentionnellement placée **en dehors** du bloc try/catch pour garantir un arrêt dur.

### TEKCO_AnonymizationAuditService — Journal d'audit

Centralise les mises à jour de l'enregistrement `TEKCO_AnonymizationAuditLog__c` tout au long de la chaîne.

| Méthode | Appelée par | Statut résultant |
|---|---|---|
| `finalize(... recordsProcessed ...)` | AnonymizationBatch (fin de chaîne) | `Success` ou `Partial` |
| `finalize(... sans count ...)` | ContentDocumentBatch, FieldHistoryBatch | `Success` ou `Partial` |
| `markRunning(...)` | AnonymizationBatch (entre chaque objet) | `Running` |
| `closeFailed(... recordsProcessed ...)` | AnonymizationBatch (exception) | `Failed` |
| `closeFailed(... sans count ...)` | ContentDocumentBatch, FieldHistoryBatch (exception) | `Failed` |

---

## Gestion des erreurs

- Les erreurs DML par record sont capturées et stockées (maximum 50 par batch). Elles sont agrégées dans le champ `TEKCO_ErrorMessage__c` du log.
- Si un objet n'existe pas dans l'org ou n'est pas supporté, le batch le skippe et retourne un `QueryLocator` vide (`SELECT Id FROM User WHERE Id = null`), permettant à la chaîne de continuer.
- Si l'historique n'est pas activé pour un objet en Phase 3, l'objet est skipé de la même façon.
- Si une exception survient dans `finish()`, le bypass est restauré et le log est fermé en `Failed`.

---

## Ajouter un nouvel objet ou un nouveau champ

1. Créer un enregistrement `TEKCO_AnonymizationFieldConfig__mdt` avec l'objet, le champ, le pattern et les options souhaitées.
2. Si l'objet n'a pas de champ `TEKCO_Brand__c` mais doit être filtré par brand via un parent, configurer `parentFiltersByObject` dans le controller (map : `objectApiName → [parentObject, lookupField, parentRecordType]`).
3. Activer la config (`TEKCO_IsActive__c = true`).
4. Déployer les metadata.

Aucune modification de code n'est nécessaire pour les cas standards.

## Ajouter un nouveau pattern

1. Créer un enregistrement `TEKCO_AnonymizationPattern__mdt` avec le `DeveloperName` souhaité et les champs de configuration.
2. Ajouter le `when 'NOM_DU_PATTERN'` correspondant dans `TEKCO_AnonymizationPatternService.applyPattern()`.
3. Déployer.
