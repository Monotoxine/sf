# Guide utilisateur — Anonymisation des données

## Table des matières

1. [Accéder à l'interface](#1-accéder-à-linterface)
2. [Comprendre les filtres disponibles](#2-comprendre-les-filtres-disponibles)
3. [Prévisualiser le périmètre](#3-prévisualiser-le-périmètre)
4. [Vérifier les champs à traiter](#4-vérifier-les-champs-à-traiter)
5. [Lancer l'anonymisation](#5-lancer-lanonymisation)
6. [Suivre l'exécution](#6-suivre-lexécution)
7. [Paramétrer les règles d'anonymisation](#7-paramétrer-les-règles-danonymisation)

---

## 1. Accéder à l'interface

L'outil est accessible depuis l'onglet **TEKCO Data Anonymization** dans la barre de navigation Salesforce.

> **Prérequis** : vous devez disposer de la permission personnalisée **TEKCO Anonymize Data**. Si vous voyez un bandeau d'erreur rouge en haut de la page, contactez votre administrateur Salesforce pour obtenir cette permission.

---

## 2. Comprendre les filtres disponibles

L'interface propose trois filtres qui permettent de cibler précisément le périmètre de l'anonymisation.

### Marques (Brands)

Permet de restreindre le traitement aux enregistrements appartenant à certaines marques.

- Déplacez une ou plusieurs marques de la colonne **Available** vers la colonne **Selected**.
- Le bouton **Select All** sélectionne toutes les marques en une seule action.
- Si aucune marque n'est sélectionnée, **tous les enregistrements** de l'organisation sont inclus, sans restriction de marque.

> Les marques disponibles correspondent aux valeurs de la picklist `TEKCO_Brand__c` présente sur les objets configurés. Pour les objets qui ne disposent pas de ce champ mais d'un champ pays (`TEKCO_Country__c`), le système déduit automatiquement les pays associés aux marques sélectionnées.

### Objets (Objects)

Permet de choisir quels objets Salesforce seront traités.

- La liste affiche uniquement les objets pour lesquels des règles d'anonymisation ont été définies.
- Si aucun objet n'est sélectionné, **tous les objets configurés** sont traités.
- La sélection d'un objet rafraîchit automatiquement la liste des Record Types disponibles.

### Record Types

Ce filtre apparaît uniquement si les objets sélectionnés possèdent des configurations spécifiques à certains Record Types.

- Laissez ce filtre vide pour traiter **tous les Record Types** de l'objet.
- Sélectionnez un ou plusieurs Record Types pour restreindre le traitement à ces populations uniquement.

---

## 3. Prévisualiser le périmètre

Avant de lancer l'anonymisation, il est fortement recommandé d'utiliser le bouton **Preview Scope**.

Cette action effectue deux choses simultanément :

1. **Compte les enregistrements** qui seront impactés pour chaque objet sélectionné, en appliquant les filtres de marque et de Record Type choisis.
2. **Charge la liste des champs** qui seront anonymisés, pour vous permettre de les réviser.

Le résultat s'affiche sous la forme d'un tableau récapitulatif indiquant, par objet, le nombre d'enregistrements concernés.

> Les objets dont la seule action est la suppression de fichiers joints (ContentDocument) sont distingués visuellement par un badge foncé.

---

## 4. Vérifier les champs à traiter

Après la prévisualisation, le tableau **Fields to Anonymize** liste tous les champs qui seront modifiés, regroupés par objet.

| Colonne | Description |
|---|---|
| **Run** | Case à cocher — décochez un champ pour l'**exclure de cette exécution uniquement** (la règle n'est pas supprimée). |
| **Field** | Nom API du champ Salesforce qui sera modifié. |
| **Pattern** | Algorithme d'anonymisation appliqué (voir section 7 pour le détail des patterns). |
| **Record Type** | Record Type ciblé par cette règle. Vide = toutes les populations. |
| **Del. History** | Si coché, l'historique des modifications de ce champ sera supprimé après anonymisation. Vous pouvez décocher cette case pour conserver l'historique sur cette exécution. |
| **Description** | Description fonctionnelle du pattern appliqué. |

---

## 5. Lancer l'anonymisation

Une fois le périmètre vérifié, cliquez sur le bouton rouge **Launch Anonymization**.

Une fenêtre de confirmation s'ouvre et récapitule :

- Les **marques** sélectionnées (ou « TOUTES » si aucune sélection)
- Les **objets** qui seront traités
- Les **Record Types** concernés
- Les **champs exclus** de cette exécution (cases décochées à l'étape précédente)
- Les **champs dont l'historique ne sera pas supprimé** sur cette exécution

> ⚠️ **Cette opération est irréversible.** Les données seront écrasées définitivement et ne pourront pas être restaurées depuis cet outil.

Cliquez sur **Confirmer le lancement** pour démarrer le traitement, ou **Annuler** pour revenir à l'interface sans rien modifier.

---

## 6. Suivre l'exécution

Le traitement s'exécute en arrière-plan via des batchs Salesforce. L'interface se met à jour automatiquement toutes les 5 secondes tant qu'une exécution est en cours.

Le tableau **Recent Runs** affiche l'historique des exécutions avec les informations suivantes :

| Colonne | Description |
|---|---|
| **Log #** | Identifiant unique de l'exécution dans le journal d'audit. |
| **Object(s)** | Objets traités lors de cette exécution. |
| **Brands** | Filtre de marque appliqué. |
| **Status** | État de l'exécution : `Running`, `Success`, `Partial`, `Failed`. |
| **Processed** | Nombre total d'enregistrements traités. |
| **Failed** | Nombre d'enregistrements en erreur. |
| **By** | Utilisateur ayant déclenché l'anonymisation. |
| **Started** | Date et heure de démarrage. |

Le bouton **↺** en haut à droite du tableau permet de rafraîchir manuellement la liste.

### Séquence de traitement

L'anonymisation se déroule en quatre phases successives et automatiques :

1. **Phase 1 — Anonymisation des champs** : mise à jour des valeurs selon les patterns configurés.
2. **Phase 2 — Suppression des fichiers** : suppression des ContentDocuments liés aux enregistrements (si configuré).
3. **Phase 3 — Suppression de l'historique** : purge de l'historique des champs marqués `Del. History`.
4. **Phase 4 — Suppression des Notes & Pièces jointes legacy** : suppression des enregistrements `Note` et `Attachment` classiques liés (si configuré).

---

## 7. Paramétrer les règles d'anonymisation

Le comportement de l'outil est entièrement piloté par deux types de Custom Metadata accessibles depuis **Setup → Custom Metadata Types**.

---

### 7.1 Les patterns disponibles — `TEKCO_AnonymizationPattern__mdt`

Un pattern définit **comment** un champ sera transformé. Les patterns disponibles sont :

| Nom (Developer Name) | Comportement |
|---|---|
| `NAME_FIRST_LETTER` | Conserve uniquement la première lettre de la valeur, suivie de l'identifiant externe, du champ `TEKCO_FunctionalId__c`, ou de l'Id Salesforce en dernier recours. Ex : `Jean Dupont` → `J0035g00000XyZAA` |
| `NAME_FIRST_LETTER_SFID` | Conserve la première lettre suivie de l'Id Salesforce (forcé, sans fallback). Ex : `Jean` → `J0035g00000XyZAA` |
| `EMAIL_PLUS_EXTERNALID` | Génère un email avec alias `+` contenant l'identifiant externe. Ex : `sf_sap+EXT001@airliquide.com` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Idem avec ajout du sous-domaine de l'org sandbox. Ex : `sf_sap+EXT001@airliquide.com.fr.mmedlej` |
| `EMAIL_PLUS_SFID` | Génère un email avec alias `+` contenant l'Id Salesforce. Ex : `sf_sap+0035g00000XyZAA@airliquide.com` |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | Idem avec ajout du sous-domaine de l'org sandbox. |
| `PHONE_MASK` | Masque le numéro de téléphone en conservant le format mais en remplaçant les chiffres. |
| `SSN_SEQUENTIAL` | Remplace le numéro de sécurité sociale par un numéro séquentiel unique. |
| `ADDRESS_STREET_RANDOM` | Remplace l'adresse postale par une adresse générée aléatoirement. |
| `LOREM_IPSUM` | Remplace le contenu texte par du Lorem Ipsum. |
| `CLEAR` | Vide le champ (le met à null si non vide). |
| `DELETE_CONTENT_DOCUMENT` | Supprime tous les fichiers (ContentDocument) liés à l'enregistrement. Traité en Phase 2. |
| `DELETE_LEGACY_ATTACHMENT` | Supprime toutes les Notes et Pièces jointes classiques liées à l'enregistrement. Traité en Phase 4. |
| `KEEP` | Aucune modification — conserve la valeur d'origine telle quelle. |

#### Champs de configuration d'un pattern

| Champ | Description |
|---|---|
| `TEKCO_Description__c` | Description fonctionnelle affichée dans l'interface. |
| `TEKCO_IsActive__c` | Activé / désactivé. Un pattern inactif ne peut pas être utilisé. |
| `TEKCO_BaseEmail__c` | Adresse email de base pour les patterns `EMAIL_PLUS_*`. Ex : `sf_sap@airliquide.com` |
| `TEKCO_ExternalIdField__c` | Nom API du champ utilisé comme identifiant externe pour les patterns `EMAIL_PLUS_EXTERNALID` et `NAME_FIRST_LETTER`. |
| `TEKCO_SsnLength__c` | Longueur du numéro séquentiel généré pour le pattern `SSN_SEQUENTIAL`. |

---

### 7.2 Les règles de champs — `TEKCO_AnonymizationFieldConfig__mdt`

Une règle de champ définit **quel champ** d'**quel objet** sera anonymisé avec **quel pattern**.

#### Champs obligatoires

| Champ | Description |
|---|---|
| `TEKCO_ObjectApiName__c` | Nom API de l'objet Salesforce cible. Ex : `Account`, `Contact`, `Case` |
| `TEKCO_FieldApiName__c` | Nom API du champ à anonymiser. Ex : `FirstName`, `PersonEmail`, `ACCCO_Email__c` |
| `TEKCO_PatternType__c` | Developer Name du pattern à appliquer. Doit correspondre à un enregistrement actif de `TEKCO_AnonymizationPattern__mdt`. |
| `TEKCO_IsActive__c` | Doit être coché pour que la règle soit prise en compte. |

#### Champs de filtrage

| Champ | Description |
|---|---|
| `TEKCO_RecordTypeDeveloperName__c` | Restreint la règle aux enregistrements d'un Record Type spécifique. Laisser vide pour s'appliquer à tous les Record Types. |
| `TEKCO_AdditionalFilter__c` | Condition SOQL additionnelle ajoutée à la clause WHERE de la requête. Ex : `ACCCO_RelatedAccount__r.RecordType.DeveloperName = 'ACCCO_Patient'` |

#### Champs pour objets enfants

À utiliser lorsque le champ à anonymiser se trouve sur un objet enfant et que le filtrage doit se faire via un objet parent.

| Champ | Description |
|---|---|
| `TEKCO_ParentObjectApiName__c` | Nom API de l'objet parent. Ex : `Account` |
| `TEKCO_ParentLookupFieldApiName__c` | Nom API du champ de lookup sur l'objet enfant pointant vers le parent. |
| `TEKCO_ParentRecordTypeDeveloperName__c` | Record Type de l'objet parent utilisé comme filtre. |

#### Comportement sur l'historique

| Champ | Description |
|---|---|
| `TEKCO_DeleteHistory__c` | Si coché, l'historique des modifications de ce champ (`FieldHistory`) sera supprimé après anonymisation. Par défaut décoché pour les champs sans enjeu de traçabilité. |

---

### 7.3 Ajouter une nouvelle règle — procédure pas à pas

1. Aller dans **Setup → Custom Metadata Types → TEKCO Anonymization Field Config → Manage Records**.
2. Cliquer sur **New**.
3. Renseigner un **Label** explicite (ex : `Patient PersonEmail`) et un **Developer Name** unique (ex : `Patient_PersonEmail`).
4. Renseigner les champs obligatoires : objet, champ, pattern, et cocher `TEKCO_IsActive__c`.
5. Optionnel : renseigner le Record Type si la règle ne s'applique qu'à une population.
6. Optionnel : cocher `TEKCO_DeleteHistory__c` si l'historique de ce champ doit être purgé.
7. Sauvegarder.

La règle est immédiatement prise en compte lors du prochain lancement.

> **Aucun déploiement de code n'est nécessaire** pour ajouter ou modifier une règle d'anonymisation. Les Custom Metadata sont modifiables directement en production.

---

### 7.4 Désactiver temporairement une règle

Pour suspendre une règle sans la supprimer, décochez simplement le champ `TEKCO_IsActive__c` sur l'enregistrement concerné. La règle n'apparaîtra plus dans l'interface et ne sera pas traitée.

---

### 7.5 Ordre de traitement des objets

Les objets sont traités dans l'ordre dans lequel ils sont retournés par les règles actives. Au sein d'un même objet, tous les champs configurés sont traités en une seule passe batch (un même enregistrement est mis à jour en une seule opération DML).
