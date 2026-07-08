# Anonymization by Record ID — Proposed Solution

## Overview

The **By ID** flow is a second entry point to the TEKCO anonymization system. Instead of scoping anonymization by brand / object / record type, an operator provides raw Salesforce record IDs directly. The system resolves direct records **and** their configured child objects automatically, then runs the same three-phase batch chain as the existing "By Criteria" flow.

Designed for **DataMig scenarios** where specific records must be anonymized after a migration, independently of brand filters.

---

## Architecture

### New Components

| Component | Type | Role |
|-----------|------|------|
| `TEKCO_AnonymizationByIdController` | Apex (AuraEnabled) | Parse IDs, resolve scope, launch batch |
| `TEKCO_AnonymizationByIdBatch` | Apex Batch — Phase 1 | Anonymize fields on explicit record IDs |
| `TEKCO_ContentDocumentByIdBatch` | Apex Batch — Phase 2 | Delete ContentDocuments / Attachments / ServiceReports |
| `TEKCO_FieldHistoryByIdBatch` | Apex Batch — Phase 3 | Delete field history records |
| `tekcoDataAnonymizationAdmin` (modified) | LWC | New "By ID (DataMig)" tab |

### Zero-Regression Constraint

No existing class was modified. The three new batch classes are independent. Their `execute()` methods are exact copies of their counterparts in the existing chain; only `start()` differs — using an explicit `WHERE Id IN :recordIds` instead of brand/parent subquery filters.

---

## ID Resolution Logic

### Input

The operator pastes a list of Salesforce record IDs (one per line, or comma/semicolon-separated). IDs can belong to different SObject types and be mixed together.

### Step 1 — Parse & Group

Each raw string is cast to `Id`. Salesforce's type system resolves the SObject type:

```apex
Id.getSObjectType().getDescribe().getName()
```

IDs are grouped into `Map<String, List<Id>> directIdsByObject`.

### Step 2 — Validate Against CMDT

All active `TEKCO_AnonymizationFieldConfig__mdt` records are loaded (1 SOQL). IDs whose SObject type has no active CMDT config are reported as invalid — displayed in the UI and excluded from processing.

### Step 3 — Resolve Child Objects

The same CMDT records encode parent-child relationships via:

- `TEKCO_ParentObjectApiName__c` — the parent SObject API name (e.g. `Account`)
- `TEKCO_ParentLookupFieldApiName__c` — the lookup field on the child (e.g. `AccountId`)

`buildChildRelationMap()` produces `Map<String childObjectApiName, ChildRelationInfo>`. For each child object whose parent was provided, one SOQL is executed:

```sql
SELECT Id FROM ChildObject WHERE ParentLookupField IN :parentIds
```

> **Bulk-safe**: one SOQL per child object type, regardless of how many parent IDs are provided.

> **Note on CMDT reuse**: In "By Criteria", `TEKCO_ParentObjectApiName__c` is used as a *filter* — to restrict children by brand/record type. In the By ID flow, the same field is used in the *opposite direction* — to discover children given parent IDs. Same metadata, complementary logic, no conflict.

### Step 4 — Preview (`resolveIds`)

A dedicated `@AuraEnabled` method returns a `ResolveResultDTO` without launching any batch:

```json
{
  "directObjects": [{ "objectApiName": "Account", "recordCount": 2, "sourceLabel": "direct" }],
  "childObjects":  [{ "objectApiName": "Contact", "recordCount": 5, "sourceLabel": "via Account.AccountId" }],
  "invalidIds":    ["XXXXX (SomeObject — not configured)"],
  "totalValid":    7
}
```

---

## Batch Chain

```
TEKCO_AnonymizationByIdBatch        (Phase 1 — field anonymization, one batch per SObject)
    → TEKCO_ContentDocumentByIdBatch    (Phase 2 — ContentDocuments/Attachments, one batch per SObject)
        → TEKCO_FieldHistoryByIdBatch       (Phase 3 — field history, one batch per SObject)
            → TEKCO_AnonymizationAuditService.finalize()
```

State is forwarded between phases via constructor parameters:

| Parameter | Purpose |
|-----------|---------|
| `Map<String, List<Id>> remainingObjectIds` | Objects still to process in Phase 1 |
| `Map<String, List<Id>> contentDocIdsByObject` | Parent IDs for Phase 2 |
| `Map<String, List<Id>> historyIdsByObject` | Parent IDs for Phase 3 |
| `BypassSnapshot bypassSnapshot` | Active bypass state to restore on completion |
| `List<String> accumulatedErrors` | Rolling error list for the audit log |
| `Integer accumulatedRecordsProcessed` | Rolling record count for the audit log |

---

## Guards & Safety

| Guard | Implementation |
|-------|---------------|
| Custom permission | `FeatureManagement.checkPermission('TEKCO_AnonymizeData')` in `startAnonymizationByIds()` |
| Sandbox-only | `TEKCO_AnonymizationPatternService.assertIsSandbox()` called in every batch's `start()` and in the controller |
| Bypass activation | `TEKCO_AnonymizationBypassService.activate()` before batch launch, `restore()` in every `finish()` and error handler |
| Audit log | `TEKCO_AnonymizationAuditLog__c` created with `TEKCO_BrandFilter__c = 'BY_ID (N record(s))'` before batch launch |

---

## Audit Log Separation

By ID runs are identified by `TEKCO_BrandFilter__c LIKE 'BY_ID%'`. The "By ID" tab fetches and auto-refreshes only those entries (every 5 seconds while at least one run is `Running`). The "By Criteria" tab is unaffected.

---

## LWC Integration

The existing `tekcoDataAnonymizationAdmin` component was wrapped in a `<lightning-tabset>`:

- **Tab 1 "By Criteria"**: unchanged existing behaviour
- **Tab 2 "By ID (DataMig)"**: new panel

### Tab 2 — UI Flow

1. Paste IDs in textarea → real-time count
2. **Preview Scope** → calls `resolveIds()`, displays direct records + resolved children (with `sourceLabel`) + skipped IDs
3. **Launch Anonymization** (destructive, disabled until `totalValid > 0`) → opens confirmation modal
4. Confirmation → calls `startAnonymizationByIds()` → audit log table auto-refreshes every 5 s

Both modals (By Criteria and By ID) are placed outside the `<lightning-tabset>` so they overlay the full card correctly.

---

## REGEX Pattern Type

A generic `REGEX` type was added to `TEKCO_AnonymizationPattern__mdt`, allowing field transformations to be configured entirely in CMDT without code changes.

### New CMDT Fields

| Field | Type | Usage |
|-------|------|-------|
| `TEKCO_RegexFind__c` | Text(255) | Regex pattern to find (blank = full replacement) |
| `TEKCO_RegexReplace__c` | Text(255) | Replacement string; supports `$1`, `$2` capture groups |

### Behaviour

- If `TEKCO_RegexFind__c` is blank → the entire value is replaced by `TEKCO_RegexReplace__c`
- If the regex is invalid → the field value is left unchanged, no batch error

### Example Configurations

| Use-case | RegexFind | RegexReplace |
|----------|-----------|--------------|
| Replace all digits with 0 | `\d` | `0` |
| Fixed value `ANONYMIZED` | *(blank)* | `ANONYMIZED` |
| Mask email, keep domain | `[^@]+@` | `anon@` |
| Mask digits after first 4 | `(?<=^.{4})[\s\S]` | `0` |
| Clear field (empty) | `[\s\S]*` | *(blank)* |

> **Implementation note**: `applyRegex()` uses `System.Pattern.compile()` (fully qualified) to avoid shadowing by the `pattern` parameter of type `TEKCO_AnonymizationPattern__mdt`.

---

## Multi-Org Configuration (`TEKCO_AnonymizationOrgConfig__mdt`)

A custom metadata type allows per-org adaptation without code changes. The correct record is selected by matching `TEKCO_OrgDomain__c` against the current org's domain prefix.

| Field | Purpose | Default |
|-------|---------|---------|
| `TEKCO_OrgDomain__c` | Org domain prefix to match | — |
| `TEKCO_FunctionalIdField__c` | API name of the functional ID field | `TEKCO_FunctionalId__c` |
| `TEKCO_BypassEnabled__c` | Whether trigger bypass is active | `true` |
| `TEKCO_BrandObjectApiName__c` | Brand SObject API name (blank = picklist mode) | *(blank)* |
| `TEKCO_BrandCodeField__c` | Field holding brand code on the brand object | — |
| `TEKCO_BrandCountryField__c` | Field holding country on the brand object | — |
| `TEKCO_BrandLookupFieldOnRecord__c` | Lookup from anonymized object to brand object | — |
| `TEKCO_ExternalIdFields__c` | Comma-separated extra external ID fields offered in the By ID tab | `TEKCO_DataMigrationId__c,TEKCO_ExternalId__c,TEKCO_FhirId__c` |

When no matching record is found, the service falls back to the default TEKCO/Air Liquide standard config (backward-compatible).
