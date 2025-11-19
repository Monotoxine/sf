# 🏗️ ARCHITECTURE - NIM-OS Case Creation

## 📋 Table des matières

1. [Vue d'ensemble](#vue-densemble)
2. [Architecture globale](#architecture-globale)
3. [Composants](#composants)
4. [Flux utilisateur](#flux-utilisateur)
5. [Modèle de données](#modèle-de-données)
6. [Changements vs ancienne architecture](#changements-vs-ancienne-architecture)

---

## 🎯 Vue d'ensemble

Cette architecture permet de créer des Cases via le bouton **"New"** avec un flow personnalisé basé sur le **Record Type** sélectionné.

### Objectifs

- ✅ Surcharger le bouton "New" standard
- ✅ Router vers le bon OmniScript selon le Record Type
- ✅ Pré-remplir le contexte (Division, Account, Applications/Services)
- ✅ Limiter les saisies manuelles via des picklists dépendantes
- ✅ Architecture modulaire et scalable

---

## 🏗️ Architecture globale

### Pattern: Router → Picker (LWC in OmniScript) → Form

```
User clicks "New Case"
↓
Standard Salesforce RT Selection Modal
↓
╔═══════════════════════════════════════════════════════╗
║  nimOsNewCaseOverride (Aura)                          ║
║  └── Required wrapper for lightning:actionOverride    ║
╚═══════════════════════════════════════════════════════╝
↓
╔═══════════════════════════════════════════════════════╗
║  nimOsNewCaseRouter (LWC)                             ║
║  • Lit recordTypeId depuis CurrentPageReference       ║
║  • Mapping RT → OmniScript                            ║
║  • Navigate directement vers OmniScript               ║
╚═══════════════════════════════════════════════════════╝
↓
┌─────────────────────────────────────────────────────────┐
│  RT = "NIM-OS IT Support"                               │
│  └─→ OmniScript: ITSM/ITSupport/English/1              │
│      ├── Step 1: applicationPicker (LWC)               │
│      │   • Application → Module                         │
│      │   • Source: Contracts → Provisioned Apps        │
│      ├── Step 2: Set Values (récupère picker data)     │
│      ├── Step 3+: Formulaire IT Support                │
│      └── DataRaptor Post: Créer Case                   │
└─────────────────────────────────────────────────────────┘
↓
┌─────────────────────────────────────────────────────────┐
│  RT = "NIM-OS Support"                                  │
│  └─→ OmniScript: ITSM/Support/English/1                │
│      ├── Step 1: servicePicker (LWC)                   │
│      │   • Category → Subcategory → Service            │
│      │   • Source: Product2 via Account relationships  │
│      ├── Step 2: Set Values (récupère picker data)     │
│      ├── Step 3+: Formulaire Support                   │
│      └── DataRaptor Post: Créer Case                   │
└─────────────────────────────────────────────────────────┘
↓
┌─────────────────────────────────────────────────────────┐
│  RT = "NIM-OS Change"                                   │
│  └─→ OmniScript: ITSM/Change/English/1                 │
│      ├── (Pas de picker pour le moment)                │
│      ├── Step 1+: Formulaire Change                    │
│      └── DataRaptor Post: Créer Case                   │
└─────────────────────────────────────────────────────────┘
↓
┌─────────────────────────────────────────────────────────┐
│  RT = Autre (non NIM-OS)                                │
│  └─→ Navigate to Standard Case Creation                │
│      • Avec nooverride=1 (évite boucle infinie)        │
└─────────────────────────────────────────────────────────┘
```

---

## 🧩 Composants

### 1. Aura Component

#### `nimOsNewCaseOverride`
- **Rôle**: Wrapper requis pour `lightning:actionOverride`
- **Raison**: LWC ne peut pas implémenter `lightning:actionOverride` directement
- **Contenu**: Juste `<c:nimOsNewCaseRouter />`

---

### 2. Lightning Web Components

#### `nimOsNewCaseRouter` (Router)

**Responsabilités:**
- Lire `recordTypeId` depuis `CurrentPageReference`
- Résoudre le Developer Name du Record Type
- Router vers le bon OmniScript via mapping

**Mapping RT → OmniScript:**
```javascript
OMNISCRIPT_MAPPING = {
    'NIM-OS_IT_Support': {
        type: 'ITSM',
        subType: 'ITSupport',
        language: 'English',
        version: 1
    },
    'NIM-OS_Support': {
        type: 'ITSM',
        subType: 'Support',
        language: 'English',
        version: 1
    },
    'NIM-OS_Change': {
        type: 'ITSM',
        subType: 'Change',
        language: 'English',
        version: 1
    }
};
```

**Navigation:**
```javascript
this[NavigationMixin.Navigate]({
    type: 'standard__featurePage',
    attributes: {
        featureName: 'omnistudio',
        pageName: 'omniscript'
    },
    state: {
        omniscript__type: config.type,
        omniscript__subType: config.subType,
        omniscript__language: config.language,
        omniscript__version: config.version,
        omniscript__seedData: encodedContextData
    }
});
```

---

#### `applicationPicker` (IT Support)

**Responsabilités:**
- Afficher picklists: Application → Module
- Charger données depuis `ITSupportController`
- Émettre event `selectionchange` avec les sélections

**Données émises:**
```javascript
{
    applicationName: String,
    moduleId: String,
    moduleName: String,
    accountId: String,
    userDivision: String
}
```

**Usage:**
- Embedded dans OmniScript IT Support (Step 1)
- Custom LWC element: `c-applicationPicker`

---

#### `servicePicker` (Support non-applicatif)

**Responsabilités:**
- Afficher picklists: Category → Subcategory → Service
- Charger données depuis `ITSMInitController`
- Émettre event `selectionchange` avec les sélections

**Données émises:**
```javascript
{
    serviceId: String,
    serviceName: String,
    category: String,
    subcategory: String,
    accountId: String,
    userDivision: String
}
```

**Usage:**
- Embedded dans OmniScript Support (Step 1)
- Custom LWC element: `c-servicePicker`

---

### 3. Apex Controllers

#### `ITSupportController`

**Méthode principale:**
```apex
@AuraEnabled(cacheable=true)
public static ResponseDTO getITSupportData()
```

**Flow de données:**
```
User.Division__c
→ Account (WHERE Legal_Name__c = Division)
→ Contract (WHERE AccountId = Account AND Status = 'Activated')
→ Provisioned_Application__c (WHERE Contract__c IN Contracts)
→ Application__c
→ Module__c (Master-Detail to Application)
```

**Response DTO:**
```apex
{
    applications: List<String>,              // ["App1", "App2"]
    modulesByApplication: Map<String, List<ModuleDTO>>,  // {"App1": [{id, name}]}
    userDivision: String,
    accountId: String,
    accountName: String
}
```

---

#### `ITSMInitController`

**Méthode principale:**
```apex
@AuraEnabled(cacheable=true)
public static ResponseDTO getITSMInitData()
```

**Flow de données:**
```
User.Division__c
→ Account (WHERE Legal_Name__c = Division)
→ Account_Service_Relationship__c (WHERE Account__c = Account)
→ Product2 (via Service__c)
→ Service_Setup__c (child of Product2)
```

**Response DTO:**
```apex
{
    categories: List<String>,                 // ["Category1", "Category2"]
    subcategoriesByCategory: Map<String, List<String>>,  // {"Cat1": ["Sub1", "Sub2"]}
    servicesByCatSubcat: Map<String, List<ServiceDTO>>,  // {"Cat1||Sub1": [{id, name}]}
    serviceSetups: List<ServiceSetupDTO>,
    userDivision: String,
    accountId: String,
    accountName: String
}
```

---

### 4. OmniScripts

#### IT Support OmniScript
- **Type**: ITSM
- **SubType**: ITSupport
- **Language**: English
- **Version**: 1

**Steps:**
1. Custom LWC → `c-applicationPicker`
2. Set Values → Récupère applicationName, moduleId, etc.
3. Formulaire IT Support (champs métier)
4. DataRaptor Post → Créer Case

---

#### Support OmniScript
- **Type**: ITSM
- **SubType**: Support
- **Language**: English
- **Version**: 1

**Steps:**
1. Custom LWC → `c-servicePicker`
2. Set Values → Récupère serviceId, category, etc.
3. Formulaire Support (champs métier)
4. DataRaptor Post → Créer Case

---

#### Change OmniScript
- **Type**: ITSM
- **SubType**: Change
- **Language**: English
- **Version**: 1

**Steps:**
1. Formulaire Change (champs métier)
2. DataRaptor Post → Créer Case

---

## 🔄 Flux utilisateur

### IT Support Flow

```
1. User clique "New Case"
2. Sélectionne RT "NIM-OS IT Support"
3. → Router détecte RT → Navigate vers OmniScript IT Support
4. OmniScript charge → Step 1: applicationPicker s'affiche
5. applicationPicker charge les données (wire Apex)
   ├── Affiche Applications (depuis Contracts actifs)
   └── User sélectionne Application
6. applicationPicker affiche Modules (filtré par Application)
   └── User sélectionne Module
7. applicationPicker émet event 'selectionchange'
8. OmniScript Step 2: Set Values récupère les données
9. OmniScript affiche le formulaire IT Support (pré-rempli)
10. User remplit les champs et soumet
11. DataRaptor Post crée la Case
12. Navigation vers la Case créée
```

### Support Flow

```
1. User clique "New Case"
2. Sélectionne RT "NIM-OS Support"
3. → Router détecte RT → Navigate vers OmniScript Support
4. OmniScript charge → Step 1: servicePicker s'affiche
5. servicePicker charge les données (wire Apex)
   ├── Affiche Categories
   └── User sélectionne Category
6. servicePicker affiche Subcategories (filtré par Category)
   └── User sélectionne Subcategory
7. servicePicker affiche Services (filtré par Category + Subcategory)
   └── User sélectionne Service
8. servicePicker émet event 'selectionchange'
9. OmniScript Step 2: Set Values récupère les données
10. OmniScript affiche le formulaire Support (pré-rempli)
11. User remplit les champs et soumet
12. DataRaptor Post crée la Case
13. Navigation vers la Case créée
```

---

## 🗄️ Modèle de données

### IT Support (Applicatif)

```
User
└── Division__c (Text)
    ↓
Account
└── Legal_Name__c = User.Division__c
    ↓
Contract (Standard)
└── Status = 'Activated'
    ↓
Provisioned_Application__c (Junction)
├── Contract__c (Lookup → Contract)
└── Application__c (Lookup → Application__c)
    ↓
Application__c (Custom)
├── Name
└── Description__c
    ↓
Module__c (Custom - Master-Detail)
├── Application__c (Master-Detail → Application__c)
├── Name
└── Description__c
```

---

### Support non-applicatif

```
User
└── Division__c (Text)
    ↓
Account
└── Legal_Name__c = User.Division__c
    ↓
Account_Service_Relationship__c (Junction)
├── Account__c (Lookup → Account)
└── Service__c (Lookup → Product2)
    ↓
Product2 (Standard)
├── Family → Category
├── SubCategory__c (Custom)
├── Name → Service Name
└── IsActive = true
    ↓
Service_Setup__c (Child)
├── Product2__c (Lookup → Product2)
├── RelatedSupportForm__c (Text)
└── RelatedChangeForm__c (Text)
```

---

## 🔄 Changements vs ancienne architecture

### ❌ Ancienne architecture

```
nimOsNewCaseOverride (Aura)
└── nimOsNewCaseRouter (LWC)
    └── itsmFlowContainer (LWC)
        ├── Choix Support/Change (boutons)
        ├── Picklists: Category → Subcategory → Service
        ├── Parse Service_Setup__c
        └── Navigate → OmniScript (selon Support ou Change)
```

**Problèmes:**
- ❌ 1 seul RT supporté ("NIM_OS_Support")
- ❌ Choix Support/Change dans le LWC (devrait être géré par RT)
- ❌ Pas de support IT (Applications/Modules)
- ❌ Navigation complexe (LWC → parse → navigate)
- ❌ Logique métier dans le LWC (mauvaise séparation)

---

### ✅ Nouvelle architecture

```
nimOsNewCaseOverride (Aura)
└── nimOsNewCaseRouter (LWC)
    ├── RT = "NIM-OS IT Support" → Navigate → OmniScript IT Support
    │   └── Contient: applicationPicker (LWC)
    ├── RT = "NIM-OS Support" → Navigate → OmniScript Support
    │   └── Contient: servicePicker (LWC)
    └── RT = "NIM-OS Change" → Navigate → OmniScript Change
```

**Avantages:**
- ✅ 3 RT supportés (IT Support, Support, Change)
- ✅ Record Type détermine le flow (plus de choix Support/Change)
- ✅ Support IT avec Applications/Modules
- ✅ Navigation directe et simple
- ✅ Logique métier dans OmniScript (bonne séparation)
- ✅ Pickers LWC réutilisables et testables
- ✅ Facile d'ajouter un nouveau RT

---

### Comparaison détaillée

| Aspect | Ancienne | Nouvelle |
|--------|----------|----------|
| **Record Types supportés** | 1 (NIM_OS_Support) | 3 (IT Support, Support, Change) |
| **Choix Support/Change** | Dans LWC | Via RT (plus propre) |
| **Applications/Modules** | ❌ Non supporté | ✅ Supporté (IT Support) |
| **Navigation** | LWC → parse → navigate | Router → direct OmniScript |
| **Logique métier** | LWC + OmniScript | OmniScript uniquement |
| **Pickers** | 1 container (itsmFlowContainer) | 2 pickers modulaires |
| **Réutilisabilité** | Faible | Élevée |
| **Testabilité** | Difficile | Facile |
| **Ajout nouveau RT** | Modifier code LWC | Ajouter mapping + OmniScript |
| **Configuration** | Code LWC | OmniScript Designer |

---

### Mapping des composants

| Fonctionnalité | Ancienne | Nouvelle |
|----------------|----------|----------|
| **Button Override** | nimOsNewCaseOverride | nimOsNewCaseOverride _(inchangé)_ |
| **Router** | nimOsNewCaseRouter | nimOsNewCaseRouter _(simplifié)_ |
| **Choix Support/Change** | itsmFlowContainer | ❌ Supprimé (géré par RT) |
| **Picklists Product2** | itsmFlowContainer | servicePicker (LWC in OS) |
| **Picklists Applications** | ❌ N'existait pas | applicationPicker (LWC in OS) |
| **Parse Service_Setup** | itsmFlowContainer | ❌ Supprimé (pas nécessaire) |
| **Navigate OmniScript** | itsmFlowContainer | nimOsNewCaseRouter |
| **Formulaire métier** | OmniScript | OmniScript _(inchangé)_ |

---

## 🎯 Bonnes pratiques

### 1. Séparation des responsabilités

- **Router**: Détecte RT + Navigate
- **Pickers (LWC)**: Affiche picklists + Émet données
- **OmniScript**: Formulaire + Validation + Case creation

### 2. Communication LWC ↔ OmniScript

Les pickers émettent des **Custom Events** avec `bubbles: true` et `composed: true`:

```javascript
const event = new CustomEvent('selectionchange', {
    detail: { serviceId, serviceName, category, subcategory },
    bubbles: true,
    composed: true
});
this.dispatchEvent(event);
```

OmniScript les récupère via **Set Values**:
```
ServiceId = {customLWC.detail.serviceId}
ServiceName = {customLWC.detail.serviceName}
```

### 3. Gestion des erreurs

Tous les composants incluent:
- Loading spinner
- Error display
- Toast notifications
- Console logs (avec emojis pour faciliter debug)

### 4. Performance

- **Apex cacheable**: `@AuraEnabled(cacheable=true)`
- **1 appel Apex** par picker (pas de N+1 queries)
- **Filtrage côté client** pour les picklists dépendantes

---

## 🚀 Scalabilité

### Ajouter un nouveau Record Type

1. Créer l'OmniScript dans OmniStudio
2. Ajouter le mapping dans `nimOsNewCaseRouter`:
   ```javascript
   OMNISCRIPT_MAPPING = {
       ...existing,
       'New_RT_DevName': {
           type: 'ITSM',
           subType: 'NewSubType',
           language: 'English',
           version: 1
       }
   }
   ```
3. Si besoin d'un nouveau picker → Créer LWC + Apex controller
4. Configurer l'OmniScript avec le picker

**Aucune modification des autres RT nécessaire!** ✅

---

## 📊 Diagramme de déploiement

```
┌─────────────────────────────────────────────┐
│  Salesforce Org                             │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │  Button Override                      │ │
│  │  Case.New → nimOsNewCaseOverride      │ │
│  └───────────────────────────────────────┘ │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │  Aura Component                       │ │
│  │  • nimOsNewCaseOverride               │ │
│  └───────────────────────────────────────┘ │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │  Lightning Web Components             │ │
│  │  • nimOsNewCaseRouter                 │ │
│  │  • applicationPicker                  │ │
│  │  • servicePicker                      │ │
│  └───────────────────────────────────────┘ │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │  Apex Classes                         │ │
│  │  • ITSupportController                │ │
│  │  • ITSMInitController                 │ │
│  │  • OmniScriptSeedDecoder (optional)   │ │
│  └───────────────────────────────────────┘ │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │  OmniScripts                          │ │
│  │  • ITSM/ITSupport/English/1           │ │
│  │  • ITSM/Support/English/1             │ │
│  │  • ITSM/Change/English/1              │ │
│  └───────────────────────────────────────┘ │
│                                             │
│  ┌───────────────────────────────────────┐ │
│  │  Custom Objects                       │ │
│  │  • Application__c                     │ │
│  │  • Module__c                          │ │
│  │  • Provisioned_Application__c         │ │
│  │  • Account_Service_Relationship__c    │ │
│  │  • Service_Setup__c                   │ │
│  └───────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

---

## 📝 Conclusion

Cette architecture offre:

✅ **Flexibilité** - Facile d'ajouter de nouveaux RT
✅ **Maintenabilité** - Séparation claire des responsabilités
✅ **Scalabilité** - Composants réutilisables
✅ **Configuration** - Admins gèrent via OmniStudio
✅ **Performance** - Caching Apex + filtrage client

**Prochaine étape**: Voir `OMNISCRIPT_SETUP_GUIDE.md` pour configurer les OmniScripts! 🚀
