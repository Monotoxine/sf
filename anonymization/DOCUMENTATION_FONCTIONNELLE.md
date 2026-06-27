# Functional Documentation — TEKCO Anonymization System

## Overview

The TEKCO anonymization system masks or deletes personally identifiable information (PII) in a Salesforce sandbox org. It is driven by an LWC administration interface and executes through a chain of asynchronous Batch Apex jobs.

**Core security constraint**: the system is hard-blocked on production orgs. Any attempt to run outside a sandbox throws an exception and immediately stops all processing, with no data modified.

---

## General Architecture

```
LWC Interface (tekcoDataAnonymizationAdmin)
        │
        ▼
TEKCO_AnonymizationController  (Apex @AuraEnabled)
        │
        ▼
Phase 1 — TEKCO_AnonymizationBatch         (field anonymization)
        │
        ▼
Phase 2 — TEKCO_ContentDocumentBatch       (attached file deletion)
        │
        ▼
Phase 3 — TEKCO_FieldHistoryBatch          (field history deletion)
```

The three phases chain automatically: each batch launches the next one in its `finish()` method. If no objects are configured for a given phase, it is skipped and the next one starts immediately.

---

## Custom Metadata Type (CMT) Configuration

### TEKCO_AnonymizationFieldConfig__mdt — Field Configuration

Each record represents one anonymization rule for a given field.

| Field | Purpose |
|---|---|
| `TEKCO_ObjectApiName__c` | Salesforce object API name (e.g. `Account`) |
| `TEKCO_FieldApiName__c` | API name of the field to anonymize (e.g. `PersonEmail`) |
| `TEKCO_PatternType__c` | Pattern identifier to apply (e.g. `EMAIL_PLUS_SFID`) |
| `TEKCO_IsActive__c` | Enables or disables the rule without deleting it |
| `TEKCO_RecordTypeDeveloperName__c` | Restricts the rule to a specific Record Type (optional) |
| `TEKCO_DeleteHistory__c` | If `true`, the field's history is deleted in Phase 3 |

**Special case `DELETE_CONTENT_DOCUMENT`**: when `TEKCO_PatternType__c = 'DELETE_CONTENT_DOCUMENT'`, the record does not represent a field rule but instead instructs Phase 2 to delete `ContentDocument` records linked to the object's records. This config type is never processed in Phase 1.

### TEKCO_AnonymizationPattern__mdt — Pattern Definition

Each record describes how a pattern transforms a value.

| Field | Purpose |
|---|---|
| `TEKCO_IsActive__c` | Whether the pattern is active |
| `TEKCO_BaseEmail__c` | Base email address for email patterns (optional) |
| `TEKCO_ExternalIdField__c` | Field used as the external identifier (optional) |
| `TEKCO_SsnLength__c` | Target length for the `SSN_SEQUENTIAL` pattern (optional) |
| `TEKCO_RegexFind__c` | Regular expression to search for, used by the `REGEX` pattern (optional — if blank, the entire field value is replaced) |
| `TEKCO_RegexReplace__c` | Replacement string for the `REGEX` pattern; supports capture groups (`$1`, `$2`, …) |
| `TEKCO_Description__c` | Human-readable description of the pattern |

---

## Available Anonymization Patterns

### Name patterns

| Pattern | Algorithm | Example |
|---|---|---|
| `NAME_FIRST_LETTER` | First letter + value of the configured ExternalId field | `Jean` + `EXT001` → `JEXT001` |
| `NAME_FIRST_LETTER_SFID` | First letter + Salesforce record Id | `Jean` + `0035g00000XyZAA` → `J0035g00000XyZAA` |

### Email patterns

| Pattern | Algorithm | Example |
|---|---|---|
| `EMAIL_PLUS_EXTERNALID` | Base email with `+ExternalId` alias | `sf_sap+EXT001@airliquide.com` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Same + org sandbox subdomain suffix | `sf_sap+EXT001@airliquide.com.fr.mmedlej` |
| `EMAIL_PLUS_SFID` | Base email with `+SalesforceId` alias | `sf_sap+0035g00000XyZAA@airliquide.com` |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | Same + org sandbox subdomain suffix | `sf_sap+0035g00000XyZAA@airliquide.com.fr.mmedlej` |

Notes on email patterns:
- If `TEKCO_BaseEmail__c` is set on the pattern CMT record, that email is used as the base.
- Otherwise, the current field value is used as the base.
- The subdomain suffix is derived automatically from the org domain (`URL.getOrgDomainUrl()`).

### Phone patterns

| Pattern | Algorithm | Example |
|---|---|---|
| `PHONE_MASK` | Keeps the first 4 characters and replaces the rest with zeros | `+33123456789` → `+33100000000` |

> **REGEX equivalent**: `TEKCO_RegexFind__c = (?<=^.{4})\d`, `TEKCO_RegexReplace__c = 0`

### Address patterns

| Pattern | Algorithm | Example |
|---|---|---|
| `ADDRESS_STREET_RANDOM` | Finds the first number in the string and adds a random value between 1 and 20 | `123 Rue de la Paix` → `137 Rue de la Paix` |

### General patterns

| Pattern | Algorithm | Example |
|---|---|---|
| `SSN_SEQUENTIAL` | Generates a cyclic 1–9 digit sequence at the same length as the original value | `123456789` (9 chars) → `123456789` |
| `LOREM_IPSUM` | Replaces the value with a fixed Lorem Ipsum text | *(fixed text)* |
| `KEEP` | No-op — field value is left unchanged | *(unchanged)* |
| `CLEAR` | Sets the field to null (empty) | *(blank)* |

> **REGEX equivalents**:
> - `SSN_SEQUENTIAL` → `TEKCO_RegexFind__c = \d`, `TEKCO_RegexReplace__c = 0` (replaces every digit with 0)
> - `LOREM_IPSUM` → `TEKCO_RegexFind__c = [\s\S]*`, `TEKCO_RegexReplace__c = Lorem ipsum dolor sit amet…`

### REGEX pattern (generic, configurable in CMDT)

| Pattern | Algorithm |
|---|---|
| `REGEX` | Applies a configurable find/replace regular expression to the field value. No code change required — fully driven by CMDT fields `TEKCO_RegexFind__c` and `TEKCO_RegexReplace__c`. |

**Behaviour:**
- If `TEKCO_RegexFind__c` is **blank**: the entire field value is replaced by `TEKCO_RegexReplace__c` (fixed replacement).
- If `TEKCO_RegexFind__c` is set: the regex is compiled and applied via `replaceAll()`. Capture groups are supported (`$1`, `$2`, …).
- If the regex is **invalid**: the field is left unchanged (no error raised, batch continues).
- If `TEKCO_RegexReplace__c` is blank: matched portions are replaced with an empty string.

**Configuration examples:**

| Use case | `TEKCO_RegexFind__c` | `TEKCO_RegexReplace__c` | Result |
|---|---|---|---|
| Replace all digits with 0 | `\d` | `0` | `AB12CD34` → `AB00CD00` |
| Fixed value `ANONYMIZED` | *(blank)* | `ANONYMIZED` | any value → `ANONYMIZED` |
| Mask email — keep domain only | `[^@]+` | `anon` | `user@company.com` → `anon@company.com` |
| Keep first 2 digits, zero the rest | `(\d{2})\d+` | `${1}0000000000` | `+33123456789` → `+330000000000` |
| Mask after 4th character | `(?<=^.{4})[\s\S]*` | *(blank)* | `ABCDEFGH` → `ABCD` |
| 5-char fixed zero string | `[\s\S]*` | `00000` | any value → `00000` |

### Special patterns (batch-level behaviour)

| Pattern | Behaviour |
|---|---|
| `DELETE_CONTENT_DOCUMENT` | Triggers deletion of `ContentDocument` records linked to the object's records in Phase 2. Never applied in Phase 1. |
| `EMAIL_MESSAGE_LOREM` | On `EmailMessage` records: if status is `Draft` → applies Lorem Ipsum to the field. Any other status → deletes the record entirely. Scoping is done via `Parent.TEKCO_Brand__c` (polymorphic relationship to the parent Case). |

---

## Administration Interface (LWC)

### Available filters

**Brands**: multi-select from the `TEKCO_Brands` Global Picklist Value Set. Labels are displayed, not API values. If no brand is selected, the run applies to all records with no brand filter.

**Objects**: multi-select of the objects to process. If no object is selected, all objects configured in the CMT are included.

**Record Types**: visible only if at least one configured field for the selected objects has a `TEKCO_RecordTypeDeveloperName__c` value. The Record Type filter acts on CMT configs, not on records directly — see the known limitation below.

> **Known limitation**: selecting a Record Type in the LWC removes CMT configs whose `TEKCO_RecordTypeDeveloperName__c` does not match. However, configs with no Record Type restriction always run on all records regardless of the selection. No `WHERE RecordType.DeveloperName` filter is added to the batch SOQL query.

### Scope preview

The **Preview Scope** button estimates the number of records that will be processed per object, applying the same brand and Record Type filters. One independent Apex call is made per object in parallel (`Promise.all`). The brand filter is skipped if the object does not have a `TEKCO_Brand__c` field; the Record Type filter is skipped if the object does not have a `RecordTypeId` field.

> **Note**: the preview is an upper-bound estimate. It does not account for parent filters (`parentFiltersByObject`), additional SOQL filters (`additionalFiltersByObject`), or field-level Record Type restrictions in the CMT.

### Field configuration table

Displays all active rules for the selected objects. Each row can be checked or unchecked to temporarily exclude a field from the current run without modifying the CMT configuration. The **Del. History** column indicates whether the field's history will be deleted in Phase 3.

### Launch

Clicking **Start** opens a confirmation modal summarising the selected objects, brands and Record Types. Confirming triggers the `startAnonymization` Apex call.

### Run log

Displays the last 20 runs with status (`Running`, `Success`, `Partial`, `Failed`), records processed/failed count, triggering user and timestamp.

---

## Batch Processing Chain

### Phase 1 — TEKCO_AnonymizationBatch

Processes the fields of each configured object's records.

**Record scoping:**
- If a parent filter is configured (`parentFiltersByObject`): records are filtered via a SOQL subquery on the parent object (e.g. `AccountId IN (SELECT Id FROM Account WHERE TEKCO_Brand__c IN :brands)`).
- Otherwise, if the object has `TEKCO_Brand__c`: direct filter on the field.
- `EMAIL_MESSAGE_LOREM` with no parent filter: filtered via `Parent.TEKCO_Brand__c` (polymorphic relationship to Case).

**Per-record processing:**
- For each active configured field, the pattern is applied only if the new value differs from the current one.
- If `TEKCO_RecordTypeDeveloperName__c` is set on a config, the field is only modified if the record's Record Type matches.
- Modified records are updated via `Database.update(allOrNone=false)`.
- Non-Draft `EmailMessage` records are deleted via `Database.delete(allOrNone=false)`.

**Chaining**: after the last object, if `DELETE_CONTENT_DOCUMENT` configs exist, Phase 2 starts. Otherwise, if `DeleteHistory` configs exist, Phase 3 starts. Otherwise, the run is finalised.

### Phase 2 — TEKCO_ContentDocumentBatch

Deletes `ContentDocument` records linked to records of the object configured with `DELETE_CONTENT_DOCUMENT`.

- Queries `ContentDocumentLink` to retrieve linked document IDs.
- Deletes the corresponding `ContentDocument` records.
- If multiple objects are configured with `DELETE_CONTENT_DOCUMENT`, one batch is chained per object.

### Phase 3 — TEKCO_FieldHistoryBatch

Deletes history records (`__History`) for fields where `TEKCO_DeleteHistory__c = true`.

- Supports both standard objects (`AccountHistory`, parent field = `AccountId`) and custom objects (`__History`, parent field = `ParentId`).
- If field history tracking is not enabled for an object, the phase is skipped with a message in the log.
- Chained per object, like Phase 1.

### Scalability

All scope queries are built using `Database.getQueryLocator` (supports up to 50 million records). Parent filtering uses nested SOQL semi-joins (up to 2 levels, the Salesforce maximum), without ever loading IDs into memory.

---

## Cross-cutting Services

### TEKCO_AnonymizationBypassService — Automation bypass

Before the chain starts, all boolean fields on `TEKCO_BypassSettings__c` (Hierarchy Custom Setting) are set to `true` for the running user. This disables triggers, flows and validation rules that might block anonymization DML operations. The original state is restored at the end of the chain regardless of outcome (success or failure).

### TEKCO_AnonymizationSandboxGuard — Production block

Checked at the start of each `start()` method in all three batches. If `Organization.IsSandbox = false`, an exception is thrown immediately. This check is intentionally placed **outside** the try/catch block to guarantee a hard stop.

### TEKCO_AnonymizationAuditService — Audit log

Centralises updates to the `TEKCO_AnonymizationAuditLog__c` record throughout the chain.

| Method | Called by | Resulting status |
|---|---|---|
| `finalize(... recordsProcessed ...)` | AnonymizationBatch (end of chain) | `Success` or `Partial` |
| `finalize(... no count ...)` | ContentDocumentBatch, FieldHistoryBatch | `Success` or `Partial` |
| `markRunning(...)` | AnonymizationBatch (between objects) | `Running` |
| `closeFailed(... recordsProcessed ...)` | AnonymizationBatch (exception) | `Failed` |
| `closeFailed(... no count ...)` | ContentDocumentBatch, FieldHistoryBatch (exception) | `Failed` |

---

## Error Handling

- DML errors per record are captured and stored (maximum 50 per batch). They are aggregated in the `TEKCO_ErrorMessage__c` field of the log.
- If an object does not exist in the org or is not supported, the batch skips it and returns an empty `QueryLocator` (`SELECT Id FROM User WHERE Id = null`), allowing the chain to continue.
- If history tracking is not enabled for an object in Phase 3, it is skipped in the same way.
- If an exception occurs in `finish()`, the bypass is restored and the log is closed as `Failed`.

---

## Adding a New Object or Field

1. Create a `TEKCO_AnonymizationFieldConfig__mdt` record with the object, field, pattern and desired options.
2. If the object does not have `TEKCO_Brand__c` but needs to be filtered by brand via a parent, configure `parentFiltersByObject` in the controller (map: `objectApiName → [parentObject, lookupField, parentRecordType]`).
3. Activate the config (`TEKCO_IsActive__c = true`).
4. Deploy the metadata.

No code changes are required for standard cases.

## Adding a New Pattern

### Using the generic REGEX pattern (no code change required)

If the transformation can be expressed as a regular expression find/replace, use the `REGEX` pattern type:

1. Create a `TEKCO_AnonymizationPattern__mdt` record with `TEKCO_PatternType__c = 'REGEX'`.
2. Set `TEKCO_RegexFind__c` (leave blank for a full fixed replacement) and `TEKCO_RegexReplace__c`.
3. Activate (`TEKCO_IsActive__c = true`) and deploy. No Apex code change needed.

### Adding a custom algorithm (code change required)

Use this path only if the transformation cannot be expressed as a regex (e.g. it reads related records, uses randomness, or depends on runtime lookup).

1. Create a `TEKCO_AnonymizationPattern__mdt` record with the desired `DeveloperName` and configuration fields.
2. Add the corresponding `when 'PATTERN_NAME'` case in `TEKCO_AnonymizationPatternService.applyPattern()`.
3. Deploy.
