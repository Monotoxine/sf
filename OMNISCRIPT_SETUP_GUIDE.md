# 📝 GUIDE DE CONFIGURATION - OmniScripts NIM-OS

## 📋 Table des matières

1. [Prérequis](#prérequis)
2. [OmniScript 1: IT Support](#omniscript-1-it-support)
3. [OmniScript 2: Support](#omniscript-2-support)
4. [OmniScript 3: Change](#omniscript-3-change)
5. [DataRaptor Configuration](#dataraptorconfiguration)
6. [Testing](#testing)
7. [Troubleshooting](#troubleshooting)

---

## ✅ Prérequis

Avant de commencer, vérifie que:

- ✅ OmniStudio est installé dans ton org
- ✅ Les LWC sont déployés (`applicationPicker`, `servicePicker`)
- ✅ Les Apex controllers sont déployés (`ITSupportController`, `ITSMInitController`)
- ✅ Le router est configuré (`nimOsNewCaseRouter`)
- ✅ Les objets custom existent (Application__c, Module__c, etc.)
- ✅ Les Record Types Case existent:
  - NIM-OS IT Support
  - NIM-OS Support
  - NIM-OS Change

---

## 🔧 OmniScript 1: IT Support

### Informations générales

| Propriété | Valeur |
|-----------|--------|
| **Type** | `ITSM` |
| **Sub Type** | `ITSupport` |
| **Language** | `English` |
| **Version** | `1` |
| **Active** | ✅ Yes |

### Structure

```
OmniScript: ITSM / ITSupport / English / 1
├── Step 1: Application Selection
│   └── Custom Lightning Web Component: applicationPicker
├── Step 2: Set Values (Capture Selection)
│   ├── ApplicationName
│   ├── ModuleId
│   ├── ModuleName
│   ├── AccountId
│   └── UserDivision
├── Step 3: IT Support Form
│   ├── Text Input: Subject
│   ├── Text Area: Description
│   ├── Radio: Priority
│   ├── Date: Needed By Date
│   └── (autres champs métier)
├── Step 4: Review & Submit
│   └── Display Summary
└── Step 5: Create Case
    └── DataRaptor Post Action
```

---

### Configuration détaillée

#### **Step 1: Application Selection**

**Element Type:** `Custom Lightning Web Component`

| Property | Value |
|----------|-------|
| **Name** | `ApplicationPicker` |
| **Lightning Web Component** | `c-applicationPicker` |
| **Element Label** | `Select Application & Module` |
| **Show Element** | `True` |

**Properties (si exposées):**
- `recordTypeId`: `%recordTypeId%` (si tu passes le RT)

**Events:**
- Listen to: `selectionchange`

---

#### **Step 2: Set Values**

**Element Type:** `Set Values`

| Property | Value |
|----------|-------|
| **Name** | `CaptureApplicationSelection` |

**Mappings:**

| Key (Node) | Value | Type |
|------------|-------|------|
| `ApplicationName` | `%ApplicationPicker.detail.applicationName%` | String |
| `ModuleId` | `%ApplicationPicker.detail.moduleId%` | String |
| `ModuleName` | `%ApplicationPicker.detail.moduleName%` | String |
| `AccountId` | `%ApplicationPicker.detail.accountId%` | String |
| `UserDivision` | `%ApplicationPicker.detail.userDivision%` | String |
| `RecordTypeId` | `%seedData.recordTypeId%` | String |

**Note:** Les valeurs `%ApplicationPicker.detail.*%` proviennent de l'event `selectionchange` émis par le LWC.

---

#### **Step 3: IT Support Form**

**Element Type:** `Step`

**Child Elements:**

##### Text Input: Subject
| Property | Value |
|----------|-------|
| **Type** | `Text` |
| **Name** | `Subject` |
| **Label** | `Subject *` |
| **Required** | `True` |
| **Help Text** | `Brief description of your IT request` |

##### Text Area: Description
| Property | Value |
|----------|-------|
| **Type** | `Text Area` |
| **Name** | `Description` |
| **Label** | `Description *` |
| **Required** | `True` |
| **Rows** | `5` |
| **Help Text** | `Detailed description of your IT request` |

##### Radio: Priority
| Property | Value |
|----------|-------|
| **Type** | `Radio` |
| **Name** | `Priority` |
| **Label** | `Priority *` |
| **Required** | `True` |
| **Options** | `High`, `Medium`, `Low` |
| **Default** | `Medium` |

##### Date: Needed By
| Property | Value |
|----------|-------|
| **Type** | `Date` |
| **Name** | `NeededByDate` |
| **Label** | `Needed By Date` |
| **Required** | `False` |

##### Display: Selected Application (read-only)
| Property | Value |
|----------|-------|
| **Type** | `Text` |
| **Name** | `SelectedApplication` |
| **Label** | `Application` |
| **Read Only** | `True` |
| **Default** | `%ApplicationName%` |

##### Display: Selected Module (read-only)
| Property | Value |
|----------|-------|
| **Type** | `Text` |
| **Name** | `SelectedModule` |
| **Label** | `Module` |
| **Read Only** | `True` |
| **Default** | `%ModuleName%` |

---

#### **Step 4: Review & Submit**

**Element Type:** `Step`

**Child Element: Display Text**
| Property | Value |
|----------|-------|
| **Type** | `Display Text` |
| **Name** | `Summary` |
| **Label** | `Please review your request` |
| **Value (HTML)** | See below |

**HTML Value:**
```html
<div class="slds-box slds-theme_shade">
    <h3 class="slds-text-heading_medium">Application</h3>
    <p><strong>%ApplicationName%</strong> - %ModuleName%</p>

    <h3 class="slds-text-heading_medium slds-m-top_medium">Request Details</h3>
    <p><strong>Subject:</strong> %Subject%</p>
    <p><strong>Priority:</strong> %Priority%</p>
    <p><strong>Description:</strong> %Description%</p>

    <h3 class="slds-text-heading_medium slds-m-top_medium">Context</h3>
    <p><strong>Division:</strong> %UserDivision%</p>
</div>
```

---

#### **Step 5: Create Case**

**Element Type:** `DataRaptor Post Action`

| Property | Value |
|----------|-------|
| **Name** | `CreateITSupportCase` |
| **DataRaptor Bundle** | `DR_CreateITSupportCase` _(à créer, voir section DataRaptor)_ |
| **Show Step** | `False` (exécute en background) |

**Input Map:**
```json
{
  "Subject": "%Subject%",
  "Description": "%Description%",
  "Priority": "%Priority%",
  "Status": "New",
  "RecordTypeId": "%RecordTypeId%",
  "AccountId": "%AccountId%",
  "Application__c": "%ApplicationName%",
  "Module__c": "%ModuleId%",
  "Needed_By_Date__c": "%NeededByDate%",
  "Origin": "Web"
}
```

**Response:**
- Store Case ID in: `%CaseId%`

---

#### **Navigation After Submit**

**Add Post Action: Navigate to Record**

| Property | Value |
|----------|-------|
| **Type** | `Navigate to Record` |
| **Record ID** | `%CaseId%` |
| **Action** | `View` |

---

## 🔧 OmniScript 2: Support

### Informations générales

| Propriété | Valeur |
|-----------|--------|
| **Type** | `ITSM` |
| **Sub Type** | `Support` |
| **Language** | `English` |
| **Version** | `1` |
| **Active** | ✅ Yes |

### Structure

```
OmniScript: ITSM / Support / English / 1
├── Step 1: Service Selection
│   └── Custom Lightning Web Component: servicePicker
├── Step 2: Set Values (Capture Selection)
│   ├── ServiceId
│   ├── ServiceName
│   ├── Category
│   ├── Subcategory
│   ├── AccountId
│   └── UserDivision
├── Step 3: Support Form
│   ├── Text Input: Subject
│   ├── Text Area: Description
│   ├── Radio: Priority
│   ├── Date: Needed By Date
│   └── (autres champs métier)
├── Step 4: Review & Submit
│   └── Display Summary
└── Step 5: Create Case
    └── DataRaptor Post Action
```

---

### Configuration détaillée

#### **Step 1: Service Selection**

**Element Type:** `Custom Lightning Web Component`

| Property | Value |
|----------|-------|
| **Name** | `ServicePicker` |
| **Lightning Web Component** | `c-servicePicker` |
| **Element Label** | `Select Service` |
| **Show Element** | `True` |

**Events:**
- Listen to: `selectionchange`

---

#### **Step 2: Set Values**

**Element Type:** `Set Values`

| Property | Value |
|----------|-------|
| **Name** | `CaptureServiceSelection` |

**Mappings:**

| Key (Node) | Value | Type |
|------------|-------|------|
| `ServiceId` | `%ServicePicker.detail.serviceId%` | String |
| `ServiceName` | `%ServicePicker.detail.serviceName%` | String |
| `Category` | `%ServicePicker.detail.category%` | String |
| `Subcategory` | `%ServicePicker.detail.subcategory%` | String |
| `AccountId` | `%ServicePicker.detail.accountId%` | String |
| `UserDivision` | `%ServicePicker.detail.userDivision%` | String |
| `RecordTypeId` | `%seedData.recordTypeId%` | String |

---

#### **Step 3: Support Form**

**Element Type:** `Step`

**Child Elements:** _(similaire à IT Support, adapter les champs selon tes besoins)_

##### Text Input: Subject
| Property | Value |
|----------|-------|
| **Type** | `Text` |
| **Name** | `Subject` |
| **Label** | `Subject *` |
| **Required** | `True` |

##### Text Area: Description
| Property | Value |
|----------|-------|
| **Type** | `Text Area` |
| **Name** | `Description` |
| **Label** | `Description *` |
| **Required** | `True` |
| **Rows** | `5` |

##### Radio: Priority
| Property | Value |
|----------|-------|
| **Type** | `Radio` |
| **Name** | `Priority` |
| **Label** | `Priority *` |
| **Required** | `True` |
| **Options** | `High`, `Medium`, `Low` |
| **Default** | `Medium` |

##### Display: Selected Service (read-only)
| Property | Value |
|----------|-------|
| **Type** | `Text` |
| **Name** | `SelectedService` |
| **Label** | `Service` |
| **Read Only** | `True` |
| **Default** | `%Category% > %Subcategory% > %ServiceName%` |

---

#### **Step 4: Review & Submit**

**Element Type:** `Step`

**Child Element: Display Text**
```html
<div class="slds-box slds-theme_shade">
    <h3 class="slds-text-heading_medium">Service</h3>
    <p><strong>%Category%</strong> → %Subcategory% → %ServiceName%</p>

    <h3 class="slds-text-heading_medium slds-m-top_medium">Request Details</h3>
    <p><strong>Subject:</strong> %Subject%</p>
    <p><strong>Priority:</strong> %Priority%</p>
    <p><strong>Description:</strong> %Description%</p>

    <h3 class="slds-text-heading_medium slds-m-top_medium">Context</h3>
    <p><strong>Division:</strong> %UserDivision%</p>
</div>
```

---

#### **Step 5: Create Case**

**Element Type:** `DataRaptor Post Action`

| Property | Value |
|----------|-------|
| **Name** | `CreateSupportCase` |
| **DataRaptor Bundle** | `DR_CreateSupportCase` _(à créer)_ |
| **Show Step** | `False` |

**Input Map:**
```json
{
  "Subject": "%Subject%",
  "Description": "%Description%",
  "Priority": "%Priority%",
  "Status": "New",
  "RecordTypeId": "%RecordTypeId%",
  "AccountId": "%AccountId%",
  "Product__c": "%ServiceId%",
  "Category__c": "%Category%",
  "Subcategory__c": "%Subcategory%",
  "Origin": "Web"
}
```

**Navigation:** Navigate to created Case

---

## 🔧 OmniScript 3: Change

### Informations générales

| Propriété | Valeur |
|-----------|--------|
| **Type** | `ITSM` |
| **Sub Type** | `Change` |
| **Language** | `English` |
| **Version** | `1` |
| **Active** | ✅ Yes |

### Structure

```
OmniScript: ITSM / Change / English / 1
├── Step 1: Change Request Form
│   ├── Text Input: Subject
│   ├── Text Area: Description
│   ├── Text Area: Business Justification
│   ├── Radio: Change Type
│   ├── Date: Requested Implementation Date
│   └── (autres champs métier)
├── Step 2: Review & Submit
│   └── Display Summary
└── Step 3: Create Case
    └── DataRaptor Post Action
```

---

### Configuration détaillée

**Note:** Pas de picker pour Change (pour le moment). Formulaire direct.

#### **Step 1: Change Request Form**

**Element Type:** `Step`

**Child Elements:**

##### Text Input: Subject
| Property | Value |
|----------|-------|
| **Type** | `Text` |
| **Name** | `Subject` |
| **Label** | `Change Subject *` |
| **Required** | `True` |

##### Text Area: Description
| Property | Value |
|----------|-------|
| **Type** | `Text Area` |
| **Name** | `Description` |
| **Label** | `Change Description *` |
| **Required** | `True` |
| **Rows** | `5` |

##### Text Area: Business Justification
| Property | Value |
|----------|-------|
| **Type** | `Text Area` |
| **Name** | `BusinessJustification` |
| **Label** | `Business Justification *` |
| **Required** | `True` |
| **Rows** | `3` |

##### Radio: Change Type
| Property | Value |
|----------|-------|
| **Type** | `Radio` |
| **Name** | `ChangeType` |
| **Label** | `Change Type *` |
| **Required** | `True` |
| **Options** | `Standard`, `Normal`, `Emergency` |
| **Default** | `Normal` |

##### Date: Implementation Date
| Property | Value |
|----------|-------|
| **Type** | `Date` |
| **Name** | `RequestedImplementationDate` |
| **Label** | `Requested Implementation Date *` |
| **Required** | `True` |

---

#### **Step 2: Review & Submit**

```html
<div class="slds-box slds-theme_shade">
    <h3 class="slds-text-heading_medium">Change Request</h3>
    <p><strong>Type:</strong> %ChangeType%</p>
    <p><strong>Subject:</strong> %Subject%</p>

    <h3 class="slds-text-heading_medium slds-m-top_medium">Details</h3>
    <p><strong>Description:</strong> %Description%</p>
    <p><strong>Justification:</strong> %BusinessJustification%</p>

    <h3 class="slds-text-heading_medium slds-m-top_medium">Timeline</h3>
    <p><strong>Requested Date:</strong> %RequestedImplementationDate%</p>
</div>
```

---

#### **Step 3: Create Case**

**Element Type:** `DataRaptor Post Action`

| Property | Value |
|----------|-------|
| **Name** | `CreateChangeCase` |
| **DataRaptor Bundle** | `DR_CreateChangeCase` _(à créer)_ |
| **Show Step** | `False` |

**Input Map:**
```json
{
  "Subject": "%Subject%",
  "Description": "%Description%",
  "Priority": "Medium",
  "Status": "New",
  "RecordTypeId": "%seedData.recordTypeId%",
  "Type": "Change Request",
  "Change_Type__c": "%ChangeType%",
  "Business_Justification__c": "%BusinessJustification%",
  "Requested_Implementation_Date__c": "%RequestedImplementationDate%",
  "Origin": "Web"
}
```

**Navigation:** Navigate to created Case

---

## 🗄️ DataRaptor Configuration

Tu dois créer 3 **DataRaptor Post** pour créer les Cases.

### DataRaptor 1: DR_CreateITSupportCase

**Type:** `Turbo Extract`

**Object:** `Case`

**Interface Type:** `REST API`

#### Extract Configuration

| Output Path | Extract From | Object/Field |
|-------------|--------------|--------------|
| `CaseId` | `Id` | Case |

#### Transform (Extract → Load)

| Input | Output | SObject Field |
|-------|--------|---------------|
| `Subject` | `Subject` | Case.Subject |
| `Description` | `Description` | Case.Description |
| `Priority` | `Priority` | Case.Priority |
| `Status` | `Status` | Case.Status |
| `RecordTypeId` | `RecordTypeId` | Case.RecordTypeId |
| `AccountId` | `AccountId` | Case.AccountId |
| `Application__c` | `Application__c` | Case.Application__c _(custom field)_ |
| `Module__c` | `Module__c` | Case.Module__c _(custom field)_ |
| `Needed_By_Date__c` | `Needed_By_Date__c` | Case.Needed_By_Date__c _(custom field)_ |
| `Origin` | `Origin` | Case.Origin |

**Formula Fields (si applicable):**
- `OwnerId` = Formula to assign to appropriate queue

---

### DataRaptor 2: DR_CreateSupportCase

**Type:** `Turbo Extract`

**Object:** `Case`

#### Transform

| Input | Output | SObject Field |
|-------|--------|---------------|
| `Subject` | `Subject` | Case.Subject |
| `Description` | `Description` | Case.Description |
| `Priority` | `Priority` | Case.Priority |
| `Status` | `Status` | Case.Status |
| `RecordTypeId` | `RecordTypeId` | Case.RecordTypeId |
| `AccountId` | `AccountId` | Case.AccountId |
| `Product__c` | `Product__c` | Case.Product__c _(lookup to Product2)_ |
| `Category__c` | `Category__c` | Case.Category__c _(custom field)_ |
| `Subcategory__c` | `Subcategory__c` | Case.Subcategory__c _(custom field)_ |
| `Origin` | `Origin` | Case.Origin |

---

### DataRaptor 3: DR_CreateChangeCase

**Type:** `Turbo Extract`

**Object:** `Case`

#### Transform

| Input | Output | SObject Field |
|-------|--------|---------------|
| `Subject` | `Subject` | Case.Subject |
| `Description` | `Description` | Case.Description |
| `Priority` | `Priority` | Case.Priority |
| `Status` | `Status` | Case.Status |
| `RecordTypeId` | `RecordTypeId` | Case.RecordTypeId |
| `Type` | `Type` | Case.Type |
| `Change_Type__c` | `Change_Type__c` | Case.Change_Type__c _(custom field)_ |
| `Business_Justification__c` | `Business_Justification__c` | Case.Business_Justification__c _(custom field)_ |
| `Requested_Implementation_Date__c` | `Requested_Implementation_Date__c` | Case.Requested_Implementation_Date__c _(custom field)_ |
| `Origin` | `Origin` | Case.Origin |

---

## 🧪 Testing

### Checklist de tests

#### IT Support Flow
- [ ] Cliquer "New Case"
- [ ] Sélectionner RT "NIM-OS IT Support"
- [ ] Vérifier que applicationPicker s'affiche
- [ ] Sélectionner une Application
- [ ] Vérifier que Modules se remplissent
- [ ] Sélectionner un Module
- [ ] Vérifier que Step 2 affiche les valeurs sélectionnées
- [ ] Remplir le formulaire
- [ ] Soumettre
- [ ] Vérifier que Case est créée avec les bons champs

#### Support Flow
- [ ] Cliquer "New Case"
- [ ] Sélectionner RT "NIM-OS Support"
- [ ] Vérifier que servicePicker s'affiche
- [ ] Sélectionner Category
- [ ] Vérifier que Subcategories se remplissent
- [ ] Sélectionner Subcategory
- [ ] Vérifier que Services se remplissent
- [ ] Sélectionner Service
- [ ] Vérifier que Step 2 affiche les valeurs sélectionnées
- [ ] Remplir le formulaire
- [ ] Soumettre
- [ ] Vérifier que Case est créée avec les bons champs

#### Change Flow
- [ ] Cliquer "New Case"
- [ ] Sélectionner RT "NIM-OS Change"
- [ ] Vérifier que formulaire Change s'affiche directement
- [ ] Remplir tous les champs
- [ ] Soumettre
- [ ] Vérifier que Case est créée

---

## 🐛 Troubleshooting

### OmniScript ne se charge pas

**Symptômes:** Écran blanc après sélection RT

**Causes possibles:**
1. OmniScript pas activé
2. Mauvais mapping dans `nimOsNewCaseRouter`
3. Mauvais namespace OmniStudio

**Solutions:**
1. Vérifier que l'OmniScript est **Active** dans OmniStudio
2. Vérifier le mapping dans `nimOsNewCaseRouter.js`:
   ```javascript
   'NIM-OS_IT_Support': {
       type: 'ITSM',  // Doit matcher exactement
       subType: 'ITSupport',
       language: 'English',
       version: 1
   }
   ```
3. Vérifier le namespace dans la console browser

---

### Picker LWC ne s'affiche pas

**Symptômes:** OmniScript charge mais pas de picker

**Causes possibles:**
1. LWC pas déployé
2. Mauvais nom de composant
3. Apex controller erreur

**Solutions:**
1. Vérifier déploiement: `sf project deploy start --source-path force-app/main/default/lwc/`
2. Vérifier nom exact: `c-applicationPicker` (pas `c-application-picker`)
3. Ouvrir console browser → voir erreurs Apex

---

### Event pas capturé par Set Values

**Symptômes:** Step 2 ne récupère pas les valeurs du picker

**Causes possibles:**
1. Mauvais nom d'event
2. Mauvais path dans Set Values

**Solutions:**
1. Vérifier que le LWC émet `selectionchange` (pas `selection-change`)
2. Vérifier le path: `%ApplicationPicker.detail.applicationName%`
   - `ApplicationPicker` = Name du Custom LWC element
   - `detail` = property de l'event
   - `applicationName` = property dans event.detail

---

### DataRaptor erreur

**Symptômes:** Case pas créée, erreur dans OmniScript

**Causes possibles:**
1. Champ required manquant
2. Mauvais RecordTypeId
3. Field-level security

**Solutions:**
1. Vérifier tous les champs required de Case
2. Vérifier que `%RecordTypeId%` est bien passé
3. Vérifier FLS pour l'utilisateur

---

### Console Debugging

Ouvre la **Console Browser** (F12) pour voir les logs:

```
🔵 CurrentPageReference changed: ...
📍 RecordTypeId from page state: 012...
✅ NIM-OS RT detected → Navigating to OmniScript
🚀 Navigating to OmniScript page...
📦 ITSM Context: {applicationName: "App1", ...}
📤 Emitting selection: {applicationName: "App1", ...}
```

---

## ✅ Validation finale

Une fois les 3 OmniScripts configurés:

1. **Activer** chaque OmniScript
2. **Tester** chaque flow end-to-end
3. **Vérifier** que les Cases sont créées avec les bons champs
4. **Documenter** les champs custom utilisés
5. **Former** les utilisateurs finaux

---

## 📚 Ressources

- **OmniStudio Documentation**: https://help.salesforce.com/s/articleView?id=sf.os_omniscript_designer.htm
- **DataRaptor Documentation**: https://help.salesforce.com/s/articleView?id=sf.os_data_raptors.htm
- **Custom LWC in OmniScript**: https://help.salesforce.com/s/articleView?id=sf.os_add_custom_lwc.htm

---

**Prochaine étape:** Créer et activer les OmniScripts! 🚀
