# Data Anonymization — Proposed Solution

## Table of Contents

1. [Needs](#1-needs)
2. [Solution Overview](#2-solution-overview)
3. [Technical Architecture](#3-technical-architecture)
4. [Processing Chains](#4-processing-chains)
   - 4.1 [By Criteria — Standard Chain](#41-by-criteria--standard-chain)
   - 4.2 [By ID — DataMig Chain](#42-by-id--datamig-chain)
5. [Anonymization Patterns Reference](#5-anonymization-patterns-reference)
6. [Configuring Anonymization Rules](#6-configuring-anonymization-rules)
7. [Multi-Org Configuration](#7-multi-org-configuration)

---

## 1. Needs

Organizations that use Salesforce to store personal data — such as patient records, customer contact details, social security numbers, or medical history — are subject to strict data protection regulations (GDPR and equivalent frameworks). These regulations require that personal data held in non-production environments (sandboxes, UAT, training orgs) be anonymized before the environment is made available to users who do not have a legitimate need to access real data.

Without a dedicated tool, anonymizing data in Salesforce is a manual, error-prone process that is difficult to audit, hard to repeat consistently across refreshes, and impossible to target by brand or population segment.

The specific challenges addressed by this tool are:

- **Volume**: production orgs can contain millions of personal records across multiple objects. Manual anonymization is not feasible at scale.
- **Repeatability**: every sandbox refresh restores production data. Anonymization must be repeatable and reliable each time.
- **Traceability**: data protection officers need evidence that anonymization was performed, by whom, and on what scope.
- **Flexibility**: different teams or brands may need to anonymize different populations. A one-size-fits-all approach creates either over-anonymization (data no longer useful for testing) or under-anonymization (residual risk).
- **Completeness**: personal data is not limited to standard fields. It may exist in field history, attached files, legacy notes, and custom fields — all of which must be covered.
- **DataMig scenarios**: after a data migration, specific records may need to be anonymized immediately and individually, without waiting for a full brand-scoped run.

---

## 2. Solution Overview

The anonymization tool is a fully configurable, metadata-driven solution built natively on Salesforce. It replaces or destroys personal data across multiple objects in a single, controlled operation, without requiring any code changes to add or modify anonymization rules.

**How it works:**

The solution is built on two layers:

- **A configuration layer** — Custom Metadata types define which fields on which objects should be anonymized, using which algorithm. Administrators configure rules directly in Salesforce Setup with no deployment required.
- **An execution layer** — a Salesforce batch engine processes records in bulk, applying the configured rules, then automatically chaining three successive cleanup phases: field anonymization, file deletion, and field history purge.

The tool provides **two independent entry points** in the same administration interface:

| Mode | Entry point | Scope definition | Typical use |
|------|-------------|-----------------|-------------|
| **By Criteria** | Tab 1 | Brand + Object + Record Type filters | Periodic sandbox refresh anonymization |
| **By ID** | Tab 2 | Explicit list of Salesforce record IDs | DataMig post-migration targeted anonymization |

Both modes run the same three-phase batch chain and share the same configuration, audit, and safety infrastructure.

**Key capabilities:**

| Capability | Description |
|---|---|
| Brand-level targeting | Anonymize only records belonging to selected brands, leaving other brands untouched. |
| Record Type filtering | Apply different anonymization rules per Record Type within the same object. |
| ID-based targeting | Provide a list of record IDs directly — the system resolves direct records and their configured child objects automatically. |
| Per-run field exclusion | Temporarily exclude specific fields from a single run without modifying the configuration. |
| Scope preview | Count impacted records before launching, to validate the scope. |
| Full audit trail | Every execution is logged with its scope, status, record count, and triggering user. |
| No-code configuration | Adding or updating a rule requires only editing a Custom Metadata record in Setup — no Apex deployment. |
| Configurable patterns | A generic REGEX pattern type allows new field transformations to be defined entirely in CMDT. |
| Chained cleanup | Files (ContentDocuments and legacy Attachments) and field history are automatically cleaned up after field anonymization, in sequence. |
| Production guard | A built-in sandbox check prevents the tool from ever running in a production org. |
| Multi-org support | A dedicated CMDT record adapts the tool's behavior per org (functional ID field, brand object, external ID fields) without code changes. |

---

## 3. Technical Architecture

### 3.1 Component Inventory

| Type | Component | Role |
|------|-----------|------|
| **Apex Class** | `TEKCO_AnonymizationBatch` | Phase 1 — field anonymization batch (By Criteria) |
| **Apex Class** | `TEKCO_ContentDocumentBatch` | Phase 2 — file and attachment deletion batch (By Criteria) |
| **Apex Class** | `TEKCO_FieldHistoryBatch` | Phase 3 — field history deletion batch (By Criteria) |
| **Apex Class** | `TEKCO_AnonymizationByIdBatch` | Phase 1 — field anonymization batch (By ID) |
| **Apex Class** | `TEKCO_ContentDocumentByIdBatch` | Phase 2 — file and attachment deletion batch (By ID) |
| **Apex Class** | `TEKCO_FieldHistoryByIdBatch` | Phase 3 — field history deletion batch (By ID) |
| **Apex Class** | `TEKCO_AnonymizationController` | AuraEnabled controller for the By Criteria tab |
| **Apex Class** | `TEKCO_AnonymizationByIdController` | AuraEnabled controller for the By ID tab |
| **Apex Class** | `TEKCO_AnonymizationPatternService` | Shared utility: applies patterns, field checks, sandbox guard |
| **Apex Class** | `TEKCO_AnonymizationAuditService` | Writes and finalizes the audit log record |
| **Apex Class** | `TEKCO_AnonymizationBypassService` | Activates and restores automation bypass settings |
| **Apex Class** | `TEKCO_AnonymizationOrgConfigService` | Loads per-org configuration from `TEKCO_AnonymizationOrgConfig__mdt` |
| **LWC** | `tekcoDataAnonymizationAdmin` | User interface — two-tab component |
| **Custom Metadata** | `TEKCO_AnonymizationPattern__mdt` | Defines anonymization algorithms |
| **Custom Metadata** | `TEKCO_AnonymizationFieldConfig__mdt` | Maps fields to patterns |
| **Custom Metadata** | `TEKCO_AnonymizationOrgConfig__mdt` | Per-org configuration (naming conventions, brand object) |
| **Custom Metadata** | `TEKCO_CountryBrandSetting__mdt` | Maps brands to country values (standard orgs only) |
| **Custom Object** | `TEKCO_AnonymizationAuditLog__c` | Stores execution history |
| **Custom Setting** | `TEKCO_BypassSettings__c` | Automation bypass flags |
| **Custom Permission** | `TEKCO_AnonymizeData` | Access gate for the tool |
| **Permission Set** | `TEKCO Anonymization Admin` | Bundles all required permissions |
| **Tab** | `TEKCO Data Anonymization` | Navigation entry point |

### 3.2 Zero-Regression Design

The By ID batch classes are entirely independent from the By Criteria batch classes. Their `execute()` methods are exact copies; only `start()` differs — using `WHERE Id IN :recordIds` instead of brand/parent subquery filters. No existing class was modified when the By ID feature was added.

---

## 4. Processing Chains

### 4.1 By Criteria — Standard Chain

Triggered from the **By Criteria** tab by selecting brands, objects, and optionally record types.

```
startAnonymization()
       │
       ▼
┌─────────────────────────────────────────────┐
│  Phase 1 — TEKCO_AnonymizationBatch         │  Batch size: 2 000
│  Field values anonymized per configured     │
│  patterns. EmailMessage records without     │
│  Draft status are deleted outright.         │
│  Runs once per configured object.           │
└────────────────────┬────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│  Phase 2 — TEKCO_ContentDocumentBatch       │  Batch size: 500
│  Deletes all ContentDocuments and legacy    │
│  Attachments linked to processed records.   │
│  Runs only for objects configured with      │
│  the DELETE_CONTENT_DOCUMENT pattern.       │
└────────────────────┬────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│  Phase 3 — TEKCO_FieldHistoryBatch          │  Batch size: 2 000
│  Deletes FieldHistory records for fields    │
│  where TEKCO_DeleteHistory__c = true.       │
│  Runs once per object with history rules.   │
└────────────────────┬────────────────────────┘
                     │
                     ▼
             Audit log finalized
             Bypasses restored
```

**Batch size rationale:**
- Phases 1 and 3 use size 2 000 (the Salesforce maximum): each `execute()` performs a single-object DML update or delete with no risk of hitting row limits.
- Phase 2 uses size 500: each `execute()` queries ContentDocumentLinks for the parent records in scope. A larger batch size risks exceeding the 50 000 SOQL rows governor limit for objects with many linked files.

**Automation bypass:** Before the first batch starts, `TEKCO_AnonymizationBypassService` sets all boolean flags on `TEKCO_BypassSettings__c` to `true` for the running user, suppressing triggers and automations during processing. The original settings are restored once the entire chain completes (or fails).

**Audit log:** A `TEKCO_AnonymizationAuditLog__c` record is created at launch with `TEKCO_BrandFilter__c` containing the selected brands. It is updated throughout the chain and closed when all phases finish.

---

### 4.2 By ID — DataMig Chain

Triggered from the **By ID (DataMig)** tab by pasting a list of Salesforce record IDs.

#### ID Resolution (before any batch is launched)

The controller resolves the full scope before starting any batch:

**Step 1 — Parse and group**

Each raw string is cast to `Id`. Salesforce's type system resolves the SObject type via `Id.getSObjectType().getDescribe().getName()`. IDs are grouped by object into `Map<String, List<Id>> directIdsByObject`.

**Step 2 — Validate against CMDT**

All active `TEKCO_AnonymizationFieldConfig__mdt` records are loaded (1 SOQL). IDs whose SObject type has no active CMDT config are reported as invalid — displayed in the UI and excluded from processing.

**Step 3 — Resolve child objects**

The same CMDT records encode parent-child relationships via:
- `TEKCO_ParentObjectApiName__c` — the parent SObject API name (e.g. `Account`)
- `TEKCO_ParentLookupFieldApiName__c` — the lookup field on the child (e.g. `AccountId`)

For each child object whose parent was provided, one SOQL is executed:

```sql
SELECT Id FROM ChildObject WHERE ParentLookupField IN :parentIds
```

> **Bulk-safe**: one SOQL per child object type, regardless of the number of parent IDs provided.

> **Note on CMDT reuse**: In By Criteria mode, `TEKCO_ParentObjectApiName__c` is used as a *filter* — to restrict children by brand/record type. In By ID mode, the same field is used in the *opposite direction* — to discover children given parent IDs. Same metadata, complementary logic, no conflict.

**Step 4 — Preview (`resolveIds`)**

A dedicated method returns a preview payload without launching any batch:

```json
{
  "directObjects": [{ "objectApiName": "Account", "recordCount": 2, "sourceLabel": "direct" }],
  "childObjects":  [{ "objectApiName": "Contact", "recordCount": 5, "sourceLabel": "via Account.AccountId" }],
  "invalidIds":    ["XXXXX (SomeObject — not configured)"],
  "totalValid":    7
}
```

#### Batch Chain

```
startAnonymizationByIds()
       │
       ▼
┌────────────────────────────────────────────────┐
│  Phase 1 — TEKCO_AnonymizationByIdBatch        │  Batch size: 2 000
│  Same logic as By Criteria Phase 1, but        │
│  WHERE Id IN :recordIds instead of brand       │
│  subquery. Runs once per resolved object.      │
└────────────────────┬───────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────┐
│  Phase 2 — TEKCO_ContentDocumentByIdBatch      │  Batch size: 500
│  Same as By Criteria Phase 2, scoped to        │
│  the explicit parent IDs.                      │
└────────────────────┬───────────────────────────┘
                     │
                     ▼
┌────────────────────────────────────────────────┐
│  Phase 3 — TEKCO_FieldHistoryByIdBatch         │  Batch size: 2 000
│  Same as By Criteria Phase 3, scoped to        │
│  the explicit record IDs.                      │
└────────────────────┬───────────────────────────┘
                     │
                     ▼
             Audit log finalized
             (BrandFilter = 'BY_ID (N record(s))')
             Bypasses restored
```

**Audit log separation:** By ID runs set `TEKCO_BrandFilter__c` to `BY_ID (N record(s))`. The By ID tab's audit table filters on `LIKE 'BY_ID%'` so the two modes never mix in the UI.

**State forwarding between phases:** each batch receives the remaining work via constructor parameters: `remainingObjectIds`, `contentDocIdsByObject`, `historyIdsByObject`, a bypass snapshot, and accumulated error/record counters.

---

## 5. Anonymization Patterns Reference

Patterns are defined in `TEKCO_AnonymizationPattern__mdt`. Each pattern defines **how** a field value is transformed. The `TEKCO_PatternType__c` field on a `TEKCO_AnonymizationFieldConfig__mdt` record references the `DeveloperName` of a pattern record.

| Developer Name | Behavior |
|---|---|
| `NAME_FIRST_LETTER` | Keeps only the first letter, followed by: external ID field → configured functional ID field → Salesforce record Id (fallback chain). e.g. `Jean Dupont` → `J0035g00000XyZAA` |
| `NAME_FIRST_LETTER_SFID` | First letter followed by Salesforce Id (forced — no fallback). e.g. `Jean` → `J0035g00000XyZAA` |
| `EMAIL_PLUS_EXTERNALID` | Email with a `+` alias containing the external ID. e.g. `sf_sap+EXT001@airliquide.com` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Same with the sandbox subdomain appended. e.g. `sf_sap+EXT001@airliquide.com.fr.mmedlej` |
| `EMAIL_PLUS_SFID` | Email with a `+` alias containing the Salesforce Id. e.g. `sf_sap+0035g00000XyZAA@airliquide.com` |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | Same with the sandbox subdomain appended. |
| `SSN_SEQUENTIAL` | Replaces with a sequential digit string of the same length as the original value. |
| `ADDRESS_STREET_RANDOM` | Finds the first number in the address and adds a random offset (1–20). |
| `REGEX` | Configurable find/replace using regular expressions (see below). |
| `DELETE_CONTENT_DOCUMENT` | Marks the object for file deletion in Phase 2. No field value is changed in Phase 1. |
| `KEEP` | No-op — field value is left unchanged. |
| `EMAIL_MESSAGE_LOREM` | For EmailMessage: Draft records have body replaced by Lorem Ipsum; non-Draft records are deleted entirely. |

**Pattern configuration fields:**

| Field | Description |
|---|---|
| `TEKCO_Description__c` | Functional description displayed in the interface. |
| `TEKCO_IsActive__c` | Must be checked for the pattern to be usable. |
| `TEKCO_BaseEmail__c` | Base email address for `EMAIL_PLUS_*` patterns. e.g. `sf_sap@airliquide.com` |
| `TEKCO_ExternalIdField__c` | API name of the field used as external identifier for `EMAIL_PLUS_EXTERNALID` and `NAME_FIRST_LETTER`. |
| `TEKCO_SsnLength__c` | Target length for `SSN_SEQUENTIAL` (used as fallback if the original value is blank). |
| `TEKCO_RegexFind__c` | Regular expression to match (for `REGEX` type). Leave blank for a total replacement. |
| `TEKCO_RegexReplace__c` | Replacement string (for `REGEX` type). Supports capture groups `$1`, `$2`. |

### REGEX Pattern Type

The `REGEX` pattern type allows any field transformation to be configured entirely in CMDT, without code changes. It replaces `PHONE_MASK`, `LOREM_IPSUM`, and `CLEAR` as the recommended approach for new transformations.

**Behavior:**
- If `TEKCO_RegexFind__c` is blank → the entire field value is replaced by `TEKCO_RegexReplace__c` (fixed replacement).
- If the regex is invalid → the field value is left unchanged; the batch does not raise an error.

**Common configurations:**

| Transformation | `TEKCO_RegexFind__c` | `TEKCO_RegexReplace__c` |
|----------------|----------------------|-------------------------|
| Replace all digits with 0 | `\d` | `0` |
| Fixed value `ANONYMIZED` | *(blank)* | `ANONYMIZED` |
| Mask phone after first 4 characters | `(?<=^.{4})[\s\S]` | `0` |
| Mask email local part | `[^@]+@` | `anon@` |
| Clear field (empty) | `[\s\S]*` | *(blank)* |
| Lorem ipsum replacement | *(blank)* | `Lorem ipsum dolor sit amet…` |

---

## 6. Configuring Anonymization Rules

Field rules are defined in `TEKCO_AnonymizationFieldConfig__mdt`. Each record maps a field on an object to a pattern.

**Required fields:**

| Field | Description |
|---|---|
| `TEKCO_ObjectApiName__c` | API name of the target object. e.g. `Account`, `Contact`, `Case` |
| `TEKCO_FieldApiName__c` | API name of the field to anonymize. e.g. `FirstName`, `PersonEmail` |
| `TEKCO_PatternType__c` | Developer Name of the pattern to apply. |
| `TEKCO_IsActive__c` | Must be checked for the rule to be picked up. |

**Filtering fields:**

| Field | Description |
|---|---|
| `TEKCO_RecordTypeDeveloperName__c` | Restricts the rule to a specific Record Type. Leave empty for all. |
| `TEKCO_AdditionalFilter__c` | Additional SOQL condition appended to the WHERE clause. e.g. `Status = 'Active'` |

**Parent filter fields** *(for child objects filtered through a parent)*:

| Field | Description |
|---|---|
| `TEKCO_ParentObjectApiName__c` | API name of the parent object. e.g. `Account` |
| `TEKCO_ParentLookupFieldApiName__c` | API name of the lookup field on the child pointing to the parent. |
| `TEKCO_ParentRecordTypeDeveloperName__c` | Record Type of the parent used as a filter. |

**History behavior:**

| Field | Description |
|---|---|
| `TEKCO_DeleteHistory__c` | If checked, the field change history will be deleted in Phase 3. |

> **Note for By ID mode**: `TEKCO_ParentObjectApiName__c` and `TEKCO_ParentLookupFieldApiName__c` serve a dual purpose. In By Criteria mode they filter children by parent attributes. In By ID mode the same fields are read in the opposite direction to *discover* child records from provided parent IDs.

---

## 7. Multi-Org Configuration

### Why it exists

The tool was originally designed for TEKCO/Air Liquide orgs with a specific naming convention: brand stored as a picklist field `TEKCO_Brand__c` on Account, functional IDs stored in `TEKCO_FunctionalId__c`, external IDs in `TEKCO_DataMigrationId__c`, etc.

Orgs that do not follow this convention — for example the Portugal (ALH) org, where brand is a separate lookup object (`ALH_Brand__c`) and the functional ID field is `ALH_FunctionalId__c` — previously required code changes to adapt the tool.

The `TEKCO_AnonymizationOrgConfig__mdt` Custom Metadata type removes this requirement. One CMDT record per org controls all naming adaptations, deployed alongside the standard package. No Apex is modified.

### How it works

At startup, `TEKCO_AnonymizationOrgConfigService` resolves the current org's domain prefix via `URL.getOrgDomainUrl()` and queries for a matching `TEKCO_AnonymizationOrgConfig__mdt` record (field `TEKCO_OrgDomain__c`). If a match is found, its values are used. If not, the standard TEKCO defaults apply — meaning existing orgs need no CMDT record and are not affected.

### Configuration fields

| Field | Purpose | Standard default |
|-------|---------|-----------------|
| `TEKCO_OrgDomain__c` | Org domain prefix to match (e.g. `airliquide-pt--sandbox`) | — |
| `TEKCO_FunctionalIdField__c` | API name of the field used as functional identifier on records | `TEKCO_FunctionalId__c` |
| `TEKCO_BypassEnabled__c` | Whether trigger bypass via `TEKCO_BypassSettings__c` is active | `true` |
| `TEKCO_BrandObjectApiName__c` | SObject API name of the brand object. **Blank = picklist mode** (standard behavior). | *(blank)* |
| `TEKCO_BrandCodeField__c` | Field on the brand object holding the brand code displayed in the UI | — |
| `TEKCO_BrandCountryField__c` | Field on the brand object holding the country value | — |
| `TEKCO_BrandLookupFieldOnRecord__c` | Relationship field on anonymized records pointing to the brand object (e.g. `ALH_Brand__r`) | — |
| `TEKCO_ExternalIdFields__c` | Comma-separated list of external ID fields offered in the By ID tab's external ID selector | `TEKCO_DataMigrationId__c,TEKCO_ExternalId__c,TEKCO_FhirId__c` |

### Brand modes

**Picklist mode** (standard, `TEKCO_BrandObjectApiName__c` is blank):
- Brands are read from the picklist field `TEKCO_Brand__c` on Account.
- Countries are derived via `TEKCO_CountryBrandSetting__mdt`.
- The By Criteria filter displays the picklist values.

**Brand object mode** (`TEKCO_BrandObjectApiName__c` is set):
- Brands are records of a dedicated SObject (e.g. `ALH_Brand__c`).
- The brand code displayed in the UI is read from `TEKCO_BrandCodeField__c`.
- Countries are read directly from `TEKCO_BrandCountryField__c` on the brand record.
- Records are linked to their brand via the relationship field `TEKCO_BrandLookupFieldOnRecord__c`.
- `TEKCO_CountryBrandSetting__mdt` is not used.

### Example — Portugal (ALH) org

```xml
<CustomMetadata>
    <label>Portugal ALH</label>
    <values>
        <field>TEKCO_OrgDomain__c</field>
        <value>airliquide-pt--sandbox</value>
    </values>
    <values>
        <field>TEKCO_FunctionalIdField__c</field>
        <value>ALH_FunctionalId__c</value>
    </values>
    <values>
        <field>TEKCO_BypassEnabled__c</field>
        <value>false</value>
    </values>
    <values>
        <field>TEKCO_BrandObjectApiName__c</field>
        <value>ALH_Brand__c</value>
    </values>
    <values>
        <field>TEKCO_BrandCodeField__c</field>
        <value>Name</value>
    </values>
    <values>
        <field>TEKCO_BrandCountryField__c</field>
        <value>ALH_Country__c</value>
    </values>
    <values>
        <field>TEKCO_BrandLookupFieldOnRecord__c</field>
        <value>ALH_Brand__r</value>
    </values>
    <values>
        <field>TEKCO_ExternalIdFields__c</field>
        <value>ALH_ExternalSystemID__c</value>
    </values>
</CustomMetadata>
```
