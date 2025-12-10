# CSV Data Extractor - Documentation

## 📋 Vue d'ensemble

Solution Salesforce complète pour extraire dynamiquement des données Parent-Enfant en CSV avec gestion automatique des Governor Limits.

### Fonctionnalités clés:
✅ Upload CSV avec liste d'IDs (DataMigrationId__c)
✅ Sélection dynamique d'objets Master/Child
✅ Détection automatique des relations Lookup/Master-Detail
✅ Batch Apex Stateful avec monitoring de Heap Size
✅ Split automatique en plusieurs fichiers si nécessaire
✅ Génération de fichiers CSV (Master + Child)
✅ Sauvegarde en ContentVersion

---

## 🏗️ Architecture

```
csvExtractor (LWC)
  ↓
CSVExtractionController (Apex)
  ↓
CSVExtractionBatch (Batch Stateful)
  → ContentVersion (CSV files)
```

### Composants:

| Composant | Type | Description |
|-----------|------|-------------|
| **csvExtractor** | LWC | Interface utilisateur (wizard 4 étapes) |
| **CSVExtractionController** | Apex | Contrôleur pour lancer le batch |
| **CSVExtractionBatch** | Batch Apex | Extraction avec monitoring Governor Limits |

---

## 📂 Structure des fichiers

```
force-app/main/default/
├── classes/
│   ├── CSVExtractionBatch.cls
│   ├── CSVExtractionBatch.cls-meta.xml
│   ├── CSVExtractionController.cls
│   └── CSVExtractionController.cls-meta.xml
└── lwc/
    └── csvExtractor/
        ├── csvExtractor.html
        ├── csvExtractor.js
        ├── csvExtractor.css
        └── csvExtractor.js-meta.xml
```

---

## 🚀 Installation & Configuration

### Prérequis:

1. **Champ personnalisé requis**: `DataMigrationId__c` (Text) sur les objets Master
2. **Permissions**:
   - Lecture sur tous les objets à extraire
   - Création de ContentVersion
   - Exécution de Batch Apex

### Déploiement:

```bash
# Déployer les classes Apex
sf project deploy start --source-path force-app/main/default/classes/CSVExtractionBatch.cls
sf project deploy start --source-path force-app/main/default/classes/CSVExtractionController.cls

# Déployer le LWC
sf project deploy start --source-path force-app/main/default/lwc/csvExtractor
```

### Ajouter le composant à une App Page:

1. Lightning App Builder → Edit Home Page
2. Drag & Drop **csvExtractor** component
3. Save & Activate

---

## 📖 Guide d'utilisation

### Étape 1: Upload CSV

1. Préparez un fichier CSV avec les DataMigration IDs:
   ```csv
   a0X1234567890ABC
   a0X1234567890DEF
   a0X1234567890GHI
   ```

2. Uploadez le fichier dans l'interface
3. Le système affiche le nombre d'IDs trouvés

### Étape 2: Sélection des objets

1. **Master Object** (requis):
   - Sélectionnez l'objet qui contient le champ `DataMigrationId__c`
   - Exemple: `TherapyType__c`

2. **Child Object** (optionnel):
   - Sélectionnez un objet enfant avec une relation vers le Master
   - Exemple: `WorkType__c`
   - Le système détecte automatiquement le champ de relation

3. **Validation de la relation**:
   - ✅ Success: "TherapyType__c (Master-Detail)"
   - ⚠️ Warning: "No relationship found"

### Étape 3: Review & Launch

1. Vérifiez le résumé:
   - Fichier CSV
   - Nombre d'IDs
   - Objets sélectionnés
   - Type de relation

2. Cliquez sur **Launch Extraction**

### Étape 4: Extraction Progress

1. **Monitoring en temps réel**:
   - Statut du batch
   - Barre de progression (%)
   - Mise à jour toutes les 3 secondes

2. **Completion**:
   - Message de succès
   - Les fichiers CSV sont sauvegardés dans "Files"

---

## 🔧 Gestion des Governor Limits

### Heap Size Monitoring

Le batch surveille constamment la taille du heap:

```apex
private static final Integer MAX_HEAP_SIZE = 6000000; // 6MB max
private static final Integer FLUSH_THRESHOLD = 5000000; // Flush à 5MB
```

**Comportement**:
- Si heap > 5MB → Sauvegarde le fichier CSV partiel
- Libère la mémoire
- Continue le traitement
- Génère `Master_Part1.csv`, `Master_Part2.csv`, etc.

### Batch Size

```apex
Database.executeBatch(batch, 200); // 200 records par batch
```

Ajustez si nécessaire:
- **Plus petit** (50-100): Si objets avec beaucoup de champs
- **Plus grand** (500-1000): Si objets simples

---

## 📦 Structure des fichiers CSV générés

### Master CSV:

```csv
Id,Name,DataMigrationId__c,CreatedDate,...
a0X123,Therapy A,TH-001,2025-01-01,...
a0X456,Therapy B,TH-002,2025-01-02,...
```

### Child CSV:

```csv
Id,Name,TherapyType__c,DataMigrationId__c,...
a0Y789,Work Type 1,a0X123,WT-001,...
a0Y012,Work Type 2,a0X123,WT-002,...
```

**Tous les champs** de l'objet sont inclus (sauf compound fields).

---

## ⚡ Performance & Limitations

| Limite | Valeur | Impact |
|--------|--------|--------|
| **Heap Size** | 6 MB | Auto-split en plusieurs fichiers |
| **CPU Time** | 10s per batch | 200 records par batch → OK |
| **SOQL Queries** | 100 | 1 query Master + 1 query Child par batch → OK |
| **DML Statements** | Aucune en batch | Seulement insert ContentVersion en finish() |

### Capacité estimée:

- **Petits objets** (10-20 champs): ~100,000 records
- **Objets moyens** (50 champs): ~50,000 records
- **Gros objets** (100+ champs): ~20,000 records

**Note**: Si le volume dépasse, le système créera automatiquement des fichiers Part1, Part2, etc.

---

## 🐛 Troubleshooting

### Problème: "No relationship found"

**Cause**: Aucun champ Lookup/Master-Detail du Child vers le Master

**Solution**:
1. Vérifiez dans l'Object Manager
2. Créez une relation si nécessaire
3. Ou laissez Child vide (extrait seulement le Master)

### Problème: "No objects available"

**Cause**: Aucun objet n'a le champ `DataMigrationId__c`

**Solution**:
1. Ajoutez le champ `DataMigrationId__c` (Text, External ID) sur vos objets
2. Rafraîchissez la page

### Problème: Batch échoue (Failed)

**Cause**: Erreur SOQL ou permission manquante

**Solution**:
1. Allez dans Setup → Apex Jobs
2. Cliquez sur le Job ID
3. Vérifiez l'error message
4. Common fixes:
   - Ajouter FLS (Field-Level Security)
   - Vérifier les noms d'objets
   - Augmenter/Réduire le batch size

### Problème: Fichiers introuvables

**Cause**: Sauvegardés dans "My Files" de l'utilisateur qui a lancé le batch

**Solution**:
1. Allez dans **Files** (Lightning)
2. Filtrer par **Owned by Me**
3. Rechercher: `[ObjectName]_Part1.csv`

---

## 🔬 Code Highlights

### Détection dynamique de relation:

```apex
private String findRelationshipField(String childObj, String masterObj) {
    Schema.DescribeSObjectResult childDescribe = Schema.getGlobalDescribe()
        .get(childObj)
        .getDescribe();

    for (Schema.SObjectField field : childDescribe.fields.getMap().values()) {
        Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

        if (fieldDescribe.getType() == Schema.DisplayType.REFERENCE) {
            List<Schema.SObjectType> references = fieldDescribe.getReferenceTo();

            for (Schema.SObjectType refType : references) {
                if (refType.getDescribe().getName() == masterObj) {
                    return fieldDescribe.getName();
                }
            }
        }
    }
    return null;
}
```

### SOQL dynamique:

```apex
private String buildDynamicQuery(String objectName, Set<String> ids) {
    Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe()
        .get(objectName)
        .getDescribe()
        .fields
        .getMap();

    List<String> fieldNames = new List<String>();
    for (String fieldName : fieldMap.keySet()) {
        Schema.DescribeFieldResult fieldDescribe = fieldMap.get(fieldName).getDescribe();

        if (!fieldDescribe.isAccessible()) continue;
        if (fieldDescribe.isCompound()) continue;

        fieldNames.add(fieldName);
    }

    String query = 'SELECT ' + String.join(fieldNames, ', ') + ' FROM ' + objectName;

    if (ids != null && !ids.isEmpty()) {
        query += ' WHERE DataMigrationId__c IN :masterIds';
    }

    return query;
}
```

### Heap size check & flush:

```apex
private void processMasterRecords(List<SObject> records) {
    for (SObject record : records) {
        String row = buildCSVRow(record) + '\n';

        // Check heap before adding
        if (checkHeapSize()) {
            saveMasterCSVPart(); // Flush to file
        }

        masterCSV += row;
    }
}
```

---

## 🎯 Améliorations futures

### Version 1.1 (Recommandé):

- [ ] Email notification avec liens de téléchargement
- [ ] Support pour relations polymorphiques (WhoId, WhatId)
- [ ] Export en Excel (.xlsx) en plus de CSV
- [ ] Filtre additionnel (ex: CreatedDate > ...)

### Version 2.0 (Avancé):

- [ ] Support pour relations N-niveaux (Grand-Parent → Parent → Child)
- [ ] Compression ZIP des fichiers générés
- [ ] Scheduling récurrent
- [ ] Dashboard d'historique des extractions

---

## 📞 Support

### Debug logs:

Le code inclut des logs détaillés avec emojis:

```
🔵 Batch initialized: Master=TherapyType__c, Child=WorkType__c, IDs=150
📍 Relationship field: TherapyType__c
🔍 Query: SELECT Id, Name, ... FROM TherapyType__c WHERE ...
⚙️ Processing batch: 200 records
📦 Found 450 child records
📊 Current Heap Size: 3456789 bytes
💾 Saved Master CSV Part 1
✅ Batch finished - saving final files
```

**Activer debug logs**:
1. Setup → Debug Logs
2. User Trace Flags → New
3. User = [Your User]
4. Debug Level = SFDC_DevConsole

---

**Version**: 1.0
**Date**: 2025-12-10
**Auteur**: AI Assistant
**Salesforce API Version**: 65.0
