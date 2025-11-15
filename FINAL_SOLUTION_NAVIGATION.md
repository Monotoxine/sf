# Solution Finale : Navigation vers OmniScript

## 🎯 Problème Résolu

**Erreur initiale** : `Attempting to reference cross-namespace module omnistudio-omniscriptStep`

**Cause racine** :
- LWC ne peut PAS référencer des composants d'un namespace différent (omnistudio)
- LWC ne peut PAS appeler des composants Aura (contrairement à l'inverse)

---

## ✅ SOLUTION FINALE : Navigation au lieu d'Embedding

Au lieu d'essayer d'**embarquer** l'OmniScript dans le LWC (impossible), on **navigue** vers la page OmniScript standard de Salesforce.

### Avantages ✅
- ✅ Pas de problème cross-namespace
- ✅ Simple et maintenable
- ✅ UX standard Salesforce
- ✅ Aucun wrapper Aura nécessaire
- ✅ Fonctionne out-of-the-box

### Inconvénients ⚠️
- ⚠️ L'utilisateur quitte la page de sélection ITSM
- ⚠️ Pas d'embedding visuel dans le même écran

---

## 🏗️ Architecture

### AVANT (Ne fonctionnait pas)
```
nimOsNewCaseOverride (Aura)
  └── nimOsNewCaseRouter (LWC)
      └── itsmFlowContainer (LWC)
          └── dynamicOmniscriptHost (LWC)
              └── <omnistudio-omniscript-step> ❌ CROSS-NAMESPACE ERROR
```

### APRÈS (Fonctionne)
```
nimOsNewCaseOverride (Aura)
  └── nimOsNewCaseRouter (LWC)
      └── itsmFlowContainer (LWC)
          └── NavigationMixin.Navigate() ✅
              → /apex/omnistudio__OmniScriptUniversalPage?params
```

---

## 📝 Changements Effectués

### 1. `itsmFlowContainer.js`

**Imports ajoutés** :
```javascript
import { NavigationMixin } from 'lightning/navigation';
```

**Classe modifiée** :
```javascript
export default class ItsmFlowContainer extends NavigationMixin(LightningElement) {
```

**Méthode `handleLaunchOmniScript()` modifiée** :
```javascript
handleLaunchOmniScript() {
    // ... validation ...

    // Parse OmniScript reference
    if (!this.parseOmniScriptReference(formField)) {
        return;
    }

    // Navigate to OmniScript (instead of showing embedded)
    this.navigateToOmniScript(); // ← Nouvelle méthode
}
```

**Nouvelle méthode `navigateToOmniScript()` ajoutée** :
```javascript
navigateToOmniScript() {
    const omniscriptUrl = `/apex/omnistudio__OmniScriptUniversalPage?` +
        `omniscriptType=${encodeURIComponent(this.omniscriptType)}` +
        `&omniscriptSubType=${encodeURIComponent(this.omniscriptSubType)}` +
        `&omniscriptLang=${encodeURIComponent(this.omniscriptLang)}` +
        `&omniscriptVersion=${this.omniscriptVersion}`;

    this[NavigationMixin.Navigate]({
        type: 'standard__webPage',
        attributes: {
            url: omniscriptUrl
        }
    });
}
```

**Variables supprimées** :
- ❌ `showOmniScript` (plus nécessaire)

**Méthodes supprimées** :
- ❌ `handleBack()` (plus nécessaire)
- ❌ `handleOmniScriptComplete()` (plus nécessaire)

### 2. `itsmFlowContainer.html`

**Section supprimée** :
```html
<!-- OmniScript Display - REMOVED -->
<!-- User is now redirected to OmniScript page -->
```

Plus besoin de :
- ❌ `<c-dynamic-omniscript-host>` (composant supprimé)
- ❌ Bouton "Back"
- ❌ Section conditionnelle `if:true={showOmniScript}`

### 3. Composants supprimés

Les composants suivants ont été **entièrement supprimés** (plus nécessaires) :

- ❌ `force-app/main/default/lwc/dynamicOmniscriptHost/` (LWC complet)
- ❌ `force-app/main/default/aura/omniscriptWrapper/` (Aura wrapper)
- ❌ `force-app/main/default/aura/omniscriptCompleteEvent/` (Event Aura)
- ❌ `force-app/main/default/aura/omniscriptErrorEvent/` (Event Aura)

---

## 🔄 Flow Utilisateur

### 1. Sélection du Record Type
User clique "New Case" → Sélectionne "NIM-OS Support" → Clique "Next"

### 2. Sélection du Service ITSM
User sélectionne :
- Type (Support/Change)
- Category
- Subcategory
- Service
→ Clique "Next"

### 3. Navigation vers OmniScript
Le système :
1. Parse le champ `RelatedSupportForm__c` ou `RelatedChangeForm__c`
   - Format : `CaseSupport:ITSupport:EN:1`
2. Construit l'URL : `/apex/omnistudio__OmniScriptUniversalPage?omniscriptType=CaseSupport&omniscriptSubType=ITSupport&omniscriptLang=EN&omniscriptVersion=1`
3. **Navigue** vers cette page (l'utilisateur quitte la page de sélection)

### 4. Complétion de l'OmniScript
User remplit le formulaire OmniScript → Soumet → Case créé ✅

---

## 🧪 Tests

### Test Manuel

1. ✅ Cliquez sur **"New Case"**
2. ✅ Sélectionnez **"NIM-OS Support"**
3. ✅ Cliquez **"Next"**
4. ✅ Sélectionnez Type, Category, Subcategory, Service
5. ✅ Cliquez **"Next"**
6. ✅ **Vous êtes redirigé vers la page OmniScript** (URL change)
7. ✅ Remplissez le formulaire OmniScript
8. ✅ Soumettez → Case créé

### Logs Console Attendus

```
📍 Type: CaseSupport
📍 SubType: ITSupport
📍 Lang: EN
📍 Version: 1
🚀 Navigating to OmniScript page...
📍 OmniScript URL: /apex/omnistudio__OmniScriptUniversalPage?omniscriptType=CaseSupport&omniscriptSubType=ITSupport&omniscriptLang=EN&omniscriptVersion=1
```

---

## 🚀 Déploiement

### Commandes

```bash
# Déployer le LWC modifié
sf project deploy start --source-path force-app/main/default/lwc/itsmFlowContainer

# Ou déployer tout
sf project deploy start --source-path force-app/main/default/
```

### Vérifications Post-Déploiement

- ✅ Pas d'erreur cross-namespace
- ✅ Navigation fonctionne vers OmniScript
- ✅ OmniScript s'affiche correctement
- ✅ Case créé après soumission

---

## 📊 Comparaison des Solutions

| Solution | Avantages | Inconvénients | Status |
|----------|-----------|---------------|--------|
| **Tag HTML direct** | Simple | ❌ Cross-namespace error | Échec |
| **Import JavaScript** | Type-safe | ❌ Cross-namespace error | Échec |
| **Aura wrapper dans LWC** | Contourne namespace | ❌ LWC ne peut pas appeler Aura | Échec |
| **Navigation (CHOISI)** | ✅ Fonctionne, Simple | ⚠️ Quitte la page | ✅ Succès |
| **Aura top-level** | ✅ Embedding possible | Complexe à migrer | Alternative |

---

## 🔧 URL OmniScript

### Format Standard Salesforce

```
/apex/omnistudio__OmniScriptUniversalPage?
  omniscriptType={Type}&
  omniscriptSubType={SubType}&
  omniscriptLang={Language}&
  omniscriptVersion={Version}
```

### Exemple Réel

```
/apex/omnistudio__OmniScriptUniversalPage?
  omniscriptType=CaseSupport&
  omniscriptSubType=ITSupport&
  omniscriptLang=EN&
  omniscriptVersion=1
```

### Variantes par Namespace

| Namespace | Page VF |
|-----------|---------|
| `omnistudio` | `/apex/omnistudio__OmniScriptUniversalPage` |
| `vlocity_cmt` | `/apex/vlocity_cmt__OmniScriptUniversalPage` |
| `vlocity_ins` | `/apex/vlocity_ins__OmniScriptUniversalPage` |

**Note** : La solution actuelle utilise `omnistudio__`. Si votre namespace est différent, modifiez ligne 201 de `itsmFlowContainer.js`.

---

## 💡 Améliorations Futures

### Option : Retour automatique après création de Case

Actuellement, après la création du Case dans OmniScript, l'utilisateur reste sur la page OmniScript.

**Amélioration possible** :
1. Configurer l'OmniScript pour rediriger vers le Case après complétion
2. Ou utiliser un paramètre `returnUrl` dans l'URL de navigation

**Exemple** :
```javascript
const omniscriptUrl = `/apex/omnistudio__OmniScriptUniversalPage?` +
    `omniscriptType=${this.omniscriptType}&` +
    `omniscriptSubType=${this.omniscriptSubType}&` +
    `omniscriptLang=${this.omniscriptLang}&` +
    `omniscriptVersion=${this.omniscriptVersion}&` +
    `returnUrl=/lightning/r/Case/VIEW`; // ← Retour automatique
```

### Option : Navigation modale (Lightning Quick Action)

Utiliser une Quick Action au lieu de navigation complète :
- Affiche l'OmniScript dans un modal
- Utilisateur reste sur la page de sélection
- Plus complexe à implémenter

---

## 🐛 Troubleshooting

### Erreur : "Page not found" après navigation

**Cause** : Namespace incorrect dans l'URL

**Solution** :
1. Vérifiez Setup → Installed Packages → OmniStudio
2. Modifiez `itsmFlowContainer.js` ligne 201 avec le bon namespace

### Erreur : OmniScript non trouvé

**Cause** : Type/SubType/Lang/Version incorrects

**Solution** :
1. Vérifiez le champ `RelatedSupportForm__c` dans Service_Setup__c
2. Format attendu : `Type:SubType:Lang:Version`
3. Vérifiez que l'OmniScript est Activé dans OmniStudio

### Navigation ne fonctionne pas

**Cause** : NavigationMixin non importé

**Solution** :
```javascript
import { NavigationMixin } from 'lightning/navigation';
export default class ItsmFlowContainer extends NavigationMixin(LightningElement) {
```

---

## ✅ Avantages de Cette Solution

1. **Simple** : Utilise la navigation standard Salesforce
2. **Maintenable** : Pas de code Aura complexe
3. **Performant** : Pas de rendering d'OmniScript dans LWC
4. **Standard** : Utilise la page OmniScript officielle
5. **Évolutif** : Facile à modifier ou étendre

---

## 📚 Références

- **Salesforce Navigation Service** : https://developer.salesforce.com/docs/component-library/bundle/lightning-navigation
- **OmniStudio Documentation** : Setup → OmniStudio → Documentation
- **Cross-Namespace Limitations** : LWC Developer Guide → Component References

---

**Auteur** : Claude (AI Assistant)
**Date** : 2025-11-15
**Status** : ✅ Solution Validée et Déployable
