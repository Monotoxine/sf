# [Feature] Anonymisation DataMig : déclenchement par liste d'IDs Salesforce

---

## Contexte

Dans les scénarios de migration de données (DataMig), certains enregistrements doivent être anonymisés ponctuellement, sans lien avec un brand ou un critère de filtre existant. Le flux d'anonymisation actuel ("By Criteria") requiert de sélectionner des brands, des objets et des record types — ce qui ne correspond pas aux besoins d'une migration où l'on dispose d'une liste précise d'IDs à traiter.

---

## Solution

Ajout d'un nouvel onglet **"By ID (DataMig)"** dans le composant d'administration de l'anonymisation (`tekcoDataAnonymizationAdmin`), permettant à un opérateur autorisé de :

1. **Coller une liste d'IDs Salesforce** (un par ligne, ou séparés par virgule/point-virgule), tous types d'objets confondus.

2. **Résoudre le périmètre** avant de lancer : le système identifie automatiquement les enregistrements directs **et** leurs objets enfants configurés. Exemple : si des IDs Account sont fournis, les Contacts et Cases rattachés sont automatiquement inclus, selon la configuration CMDT `TEKCO_AnonymizationFieldConfig__mdt` existante.

3. **Visualiser le résultat de la résolution** avant tout déclenchement :
   - Enregistrements directs (objet + nombre)
   - Enfants résolus automatiquement (objet + nombre + relation source, ex. `via Account.AccountId`)
   - IDs ignorés avec la raison (ID invalide, objet non configuré)

4. **Lancer l'anonymisation** via une modale de confirmation dédiée, avec le même niveau de sécurité que le flux existant :
   - Permission custom `TEKCO_AnonymizeData` requise
   - Garde sandbox (impossibilité d'exécuter en production)
   - Bypass des triggers/validations pendant le traitement
   - Audit log automatique

5. **Suivre l'exécution** dans un tableau dédié qui se rafraîchit automatiquement toutes les 5 secondes tant qu'un run est en cours.

---

## Impact technique

- **Zéro modification** des classes batch et services existants — aucun risque de régression sur le flux "By Criteria".
- **Réutilisation complète** de la configuration CMDT, des services de pattern, bypass et audit existants.
- **Bulk-safe** : une seule SOQL par type d'objet enfant pour la résolution des enfants, quel que soit le volume d'IDs fournis.
- **Séparation des logs** : les runs BY_ID sont identifiables dans l'audit log via le filtre `TEKCO_BrandFilter__c LIKE 'BY_ID%'`.

---

## Composants livrés

| Composant | Type | Description |
|-----------|------|-------------|
| `TEKCO_AnonymizationByIdController` | Apex Controller | Résolution des IDs + lancement du batch |
| `TEKCO_AnonymizationByIdBatch` | Apex Batch | Phase 1 : anonymisation des champs |
| `TEKCO_ContentDocumentByIdBatch` | Apex Batch | Phase 2 : suppression des ContentDocuments |
| `TEKCO_FieldHistoryByIdBatch` | Apex Batch | Phase 3 : suppression de l'historique des champs |
| `tekcoDataAnonymizationAdmin` | LWC (modifié) | Nouvel onglet "By ID (DataMig)" |
