# Feature: Anonymization by Record ID (DataMig Mode)

## Overview

The **By ID** flow is a second entry point to the TEKCO anonymization system. Rather than scoping anonymization by brand / object / record type, an operator provides raw Salesforce record IDs directly. The system resolves direct records **and** their configured child objects automatically, then runs the same three-phase batch chain as the existing "By Criteria" flow.

This feature was designed for **DataMig scenarios** where specific records must be anonymized after a migration, independently of brand filters.

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

**No existing class was modified.** The three new batch classes are independent. Their `execute()` methods are exact copies of their counterparts in the existing chain; only `start()` differs (explicit `WHERE Id IN :recordIds` instead of brand/parent subquery filters).

---

## ID Resolution Logic

### Input

The operator pastes a list of Salesforce record IDs (one per line, or comma/semicolon-separated). IDs can belong to different SObject types and be mixed together.

### Resolution Steps (all performed in the controller, before launching any batch)

**Step 1 — Parse & group**

Each raw string is cast to `Id`. Salesforce's type system resolves the SObject type:
```apex
Id sfId = (Id) trimmed;
String obj = sfId.getSObjectType().getDescribe().getName();
```
IDs are grouped into `Map<String, List<Id>> directIdsByObject`.

**Step 2 — Validate against CMDT**

All active `TEKCO_AnonymizationFieldConfig__mdt` records are loaded (1 SOQL). IDs whose SObject type has no active CMDT config are reported as invalid — displayed in the UI, excluded from processing.

**Step 3 — Resolve child objects**

The same CMDT records encode parent-child relationships via two fields:
- `TEKCO_ParentObjectApiName__c` — the parent SObject API name (e.g. `Account`)
- `TEKCO_ParentLookupFieldApiName__c` — the lookup field on the child (e.g. `AccountId`)

`buildChildRelationMap()` produces `Map<String childObjectApiName, ChildRelationInfo>`. For each child object whose parent was provided, one SOQL is executed:
```soql
SELECT Id FROM ChildObject WHERE ParentLookupField IN :parentIds
```
This is **bulk-safe**: one SOQL per child object type regardless of how many parent IDs are provided.

> **Note on CMDT reuse**: In the existing "By Criteria" batch, `TEKCO_ParentObjectApiName__c` is used as a *filter* — it generates a subquery to restrict children by their parent's brand/record type. In the By ID flow, the same field is used in the *opposite direction* — to discover which children to include given parent IDs. Same metadata, complementary logic, no conflict.

**Step 4 — Preview (`resolveIds`)**

A dedicated `@AuraEnabled(cacheable=false)` method returns a `ResolveResultDTO` without launching any batch:
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
TEKCO_AnonymizationByIdBatch  (Phase 1 — field anonymization, one batch execution per SObject)
    → TEKCO_ContentDocumentByIdBatch  (Phase 2 — ContentDocuments/Attachments, one batch per SObject)
        → TEKCO_FieldHistoryByIdBatch  (Phase 3 — field history, one batch per SObject)
            → TEKCO_AnonymizationAuditService.finalize()
```

State is forwarded between phases via constructor parameters (all `Database.Stateful`):

| Parameter | Phase | Description |
|-----------|-------|-------------|
| `Map<String, List<Id>> remainingObjectIds` | P1 | Objects still to process in Phase 1 |
| `Map<String, List<Id>> contentDocIdsByObject` | P1→P2 | Parent IDs for each Phase 2 object |
| `Map<String, List<Id>> historyIdsByObject` | P1→P2→P3 | Parent IDs for each Phase 3 object |
| `TEKCO_AnonymizationBypassService.BypassSnapshot` | All | Active bypass to restore on completion |
| `List<String> accumulatedErrors` | All | Rolling error list across phases |
| `Integer accumulatedRecordsProcessed` | All | Rolling count across phases |

### Batch sizes

| Batch | Default size |
|-------|-------------|
| `TEKCO_AnonymizationByIdBatch` | 2000 |
| `TEKCO_ContentDocumentByIdBatch` | 500 |
| `TEKCO_FieldHistoryByIdBatch` | 2000 |

---

## Controller — Public API

### `resolveIds(List<String> rawIds) : ResolveResultDTO`

- `@AuraEnabled(cacheable=false)`
- Performs Steps 1–4 above; returns preview DTO, no DML, no batch

### `startAnonymizationByIds(List<String> rawIds) : Id`

- `@AuraEnabled`
- Checks `TEKCO_AnonymizeData` custom permission + `assertIsSandbox()`
- Re-executes full resolution (direct + children)
- Separates configs into `configsByObject` / `contentDocIdsByObject` / `historyIdsByObject`
- Activates bypass → inserts `TEKCO_AnonymizationAuditLog__c` → launches batch chain
- Returns the audit log record Id

### `getAuditLogsByid() : List<TEKCO_AnonymizationAuditLog__c>`

- `@AuraEnabled(cacheable=false)`
- Returns last 20 runs filtered by `TEKCO_BrandFilter__c LIKE 'BY_ID%'`
- Separated from the By Criteria audit log query

---

## Guards & Safety

| Guard | Implementation |
|-------|---------------|
| Custom permission | `FeatureManagement.checkPermission('TEKCO_AnonymizeData')` in `startAnonymizationByIds()` |
| Sandbox-only | `TEKCO_AnonymizationPatternService.assertIsSandbox()` in every batch `start()` and in the controller |
| Bypass activation | `TEKCO_AnonymizationBypassService.activate()` before batch launch; `restore()` in every `finish()` and every `catch` block |
| Audit log | `TEKCO_AnonymizationAuditLog__c` created with `TEKCO_BrandFilter__c = 'BY_ID (N record(s))'` before the first batch executes |

---

## Audit Log Separation

By ID runs are identified by `TEKCO_BrandFilter__c LIKE 'BY_ID%'`. The "By ID (DataMig)" tab fetches and auto-refreshes only those entries (every 5 seconds while at least one run has status `Running`). The "By Criteria" tab poll is entirely independent.

---

## LWC Integration

The existing `tekcoDataAnonymizationAdmin` component was wrapped in a `<lightning-tabset>`:

- **Tab 1 "By Criteria"**: unchanged existing behaviour, same JS handlers and getters
- **Tab 2 "By ID (DataMig)"**: new panel with its own state properties

**New JS state (`@track`)**

| Property | Type | Description |
|----------|------|-------------|
| `byIdRawInput` | String | Raw textarea content |
| `byIdResolveResult` | Object | DTO returned by `resolveIds()` |
| `isByIdResolving` | Boolean | Spinner while resolving |
| `isByIdRunning` | Boolean | Spinner while batch is running |
| `showByIdConfirmPanel` | Boolean | Controls confirmation modal |
| `byIdConfirmSummaryLines` | Array | Rows shown in the modal table |
| `byIdAuditLogs` | Array | Enriched audit log rows |
| `byIdErrorMessage` | String | Error banner content |

**Tab 2 UI flow**

1. Paste IDs in textarea → `byIdParsedCountLabel` updates in real time
2. **Resolve IDs** → `handleByIdResolve()` → calls `resolveIds()` → displays direct records + resolved children (with `sourceLabel`) + skipped IDs
3. **Launch Anonymization** (destructive button, disabled until `totalValid > 0`) → `handleByIdLaunch()` → opens confirmation modal
4. Confirmation modal → `handleByIdConfirmLaunch()` → calls `startAnonymizationByIds()` → starts `_byIdAuditTimer` poll

Both modals (By Criteria and By ID) are placed **outside** the `<lightning-tabset>` so they overlay the full card correctly.

---

## Deployment Checklist

- [ ] Deploy 4 new Apex classes + meta.xml:
  - `TEKCO_AnonymizationByIdController`
  - `TEKCO_AnonymizationByIdBatch`
  - `TEKCO_ContentDocumentByIdBatch`
  - `TEKCO_FieldHistoryByIdBatch`
- [ ] Deploy updated LWC `tekcoDataAnonymizationAdmin` (html + js)
- [ ] Assign `TEKCO_AnonymizeData` custom permission to operator profile / permission set
- [ ] Verify `TEKCO_AnonymizationFieldConfig__mdt` has active records for the target objects
- [ ] For child resolution: verify `TEKCO_ParentObjectApiName__c` and `TEKCO_ParentLookupFieldApiName__c` are populated on child-object CMDT rows

---

## Testing Guide

### Manual — Resolve step

1. Provide 2 Account IDs + 1 Contact ID in the textarea
2. Click "Resolve IDs"
3. Expected: Account (2, direct), Contact (1, direct) + CMDT-resolved children (e.g. Contact 5 via Account.AccountId)
4. Provide an ID for an unconfigured object → expected: appears in "skipped" list with reason

### Manual — Full anonymization

1. Resolve IDs, confirm scope shows `totalValid > 0`
2. Click "Launch Anonymization" → confirm modal shows correct summary
3. Click "Confirm Launch"
4. Expected: `TEKCO_AnonymizationAuditLog__c` created with `TEKCO_BrandFilter__c = 'BY_ID (N record(s))'`; status transitions `Running` → `Success`
5. Verify anonymized fields on direct records and CMDT-resolved children
6. Verify ContentDocuments deleted if `DELETE_CONTENT_DOCUMENT` pattern configured for those objects
7. Verify field history deleted for fields where `TEKCO_DeleteHistory__c = true`

### Regression — By Criteria tab

8. Switch to "By Criteria" tab
9. Run a standard anonymization
10. Verify the By Criteria audit log is **not** polluted with BY_ID entries and vice-versa
