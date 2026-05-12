# Data Anonymization

## Table of Contents

1. [Needs](#1-needs)
2. [Proposed Solution](#2-proposed-solution)
   - 2.1 [Solution Overview](#21-solution-overview)
   - 2.2 [Technical Architecture](#22-technical-architecture)
   - 2.3 [Processing Chain](#23-processing-chain)
   - 2.4 [Anonymization Patterns Reference](#24-anonymization-patterns-reference)
   - 2.5 [Configuring Anonymization Rules](#25-configuring-anonymization-rules)
3. [Deployment and Usage](#3-deployment-and-usage)
   - 3.1 [Prerequisites](#31-prerequisites)
   - 3.2 [Deploying the Package](#32-deploying-the-package)
   - 3.3 [Post-Deployment Steps](#33-post-deployment-steps)
   - 3.4 [Sandbox Refresh Checklist](#34-sandbox-refresh-checklist)
   - 3.5 [Accessing the Interface](#35-accessing-the-interface)
   - 3.6 [Understanding the Filters](#36-understanding-the-filters)
   - 3.7 [Previewing the Scope](#37-previewing-the-scope)
   - 3.8 [Reviewing the Fields to Process](#38-reviewing-the-fields-to-process)
   - 3.9 [Launching Anonymization](#39-launching-anonymization)
   - 3.10 [Monitoring Execution](#310-monitoring-execution)
   - 3.11 [Configuring Anonymization Rules](#311-configuring-anonymization-rules)
   - 3.12 [Known Limitations](#312-known-limitations)
4. [Testing](#4-testing)
   - 4.1 [Testing Strategy](#41-testing-strategy)
   - 4.2 [Recommended Test Protocol](#42-recommended-test-protocol)
   - 4.3 [Monitoring Queries](#43-monitoring-queries)
   - 4.4 [Interpreting Results](#44-interpreting-results)
   - 4.5 [Test Checklist](#45-test-checklist)

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

---

## 2. Proposed Solution

### 2.1 Solution Overview

The anonymization tool is a fully configurable, metadata-driven solution built natively on Salesforce. It replaces or destroys personal data across multiple objects in a single, controlled operation, without requiring any code changes to add or modify anonymization rules.

**How it works:**

The solution is built on two layers:

- **A configuration layer** — two Custom Metadata types define which fields on which objects should be anonymized, using which algorithm. Administrators configure rules directly in Salesforce Setup with no deployment required.
- **An execution layer** — a Salesforce batch engine processes records in bulk, applying the configured rules, then automatically chaining three successive cleanup phases: field anonymization, file deletion, and field history purge.

**Key capabilities:**

| Capability | Description |
|---|---|
| Brand-level targeting | Anonymize only records belonging to selected brands, leaving other brands untouched. |
| Record Type filtering | Apply different anonymization rules per Record Type within the same object. |
| Per-run field exclusion | Temporarily exclude specific fields from a single run without modifying the configuration. |
| Scope preview | Count impacted records before launching, to validate the scope. |
| Full audit trail | Every execution is logged with its scope, status, record count, and triggering user. |
| No-code configuration | Adding or updating a rule requires only editing a Custom Metadata record in Setup — no Apex deployment. |
| Chained cleanup | Files (ContentDocuments and legacy Attachments), field history are automatically cleaned up after field anonymization, in sequence. |
| Production guard | A built-in sandbox check prevents the tool from ever running in a production org. |

---

### 2.2 Technical Architecture

The solution is composed of the following Salesforce components:

| Type | Component | Role |
|---|---|---|
| **Apex Class** | `TEKCO_AnonymizationBatch` | Phase 1 — field anonymization batch |
| **Apex Class** | `TEKCO_ContentDocumentBatch` | Phase 2 — file and attachment deletion batch |
| **Apex Class** | `TEKCO_FieldHistoryBatch` | Phase 3 — field history deletion batch |
| **Apex Class** | `TEKCO_AnonymizationController` | AuraEnabled controller for the LWC interface |
| **Apex Class** | `TEKCO_AnonymizationPatternService` | Shared utility: applies patterns, field checks, sandbox guard |
| **Apex Class** | `TEKCO_AnonymizationAuditService` | Writes and finalizes the audit log record |
| **Apex Class** | `TEKCO_AnonymizationBypassService` | Activates and restores automation bypass settings |
| **LWC** | `tekcoDataAnonymizationAdmin` | User interface component |
| **Custom Metadata** | `TEKCO_AnonymizationPattern__mdt` | Defines anonymization algorithms |
| **Custom Metadata** | `TEKCO_AnonymizationFieldConfig__mdt` | Maps fields to patterns |
| **Custom Metadata** | `TEKCO_CountryBrandSetting__mdt` | Maps brands to country values |
| **Custom Object** | `TEKCO_AnonymizationAuditLog__c` | Stores execution history |
| **Custom Setting** | `TEKCO_BypassSettings__c` | Automation bypass flags |
| **Custom Permission** | `TEKCO_AnonymizeData` | Access gate for the tool |
| **Permission Set** | `TEKCO Anonymization Admin` | Bundles all required permissions |
| **Tab** | `TEKCO Data Anonymization` | Navigation entry point |

---

### 2.3 Processing Chain

Anonymization runs as a chain of three sequential batch jobs. Each phase completes fully before the next one starts.

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
- Phases 1 and 3 use size 2 000 (the Salesforce maximum): each execute() performs a single-object DML update or delete with no risk of hitting row limits.
- Phase 2 uses size 500: each execute() queries ContentDocumentLinks and Attachments for the parent records in scope. A larger batch size risks exceeding the 50 000 SOQL rows governor limit for objects with many linked files.

**Automation bypass:**
Before the first batch starts, `TEKCO_AnonymizationBypassService` sets all boolean flags on `TEKCO_BypassSettings__c` to `true` for the running user, suppressing triggers and automations during processing. The original settings are restored once the entire chain completes (or fails).

**Audit log:**
A `TEKCO_AnonymizationAuditLog__c` record is created at launch and updated throughout the chain. `TEKCO_RecordsProcessed__c` reflects the number of source records anonymized in Phase 1. File and history deletions in Phases 2 and 3 are not counted separately.

---

### 2.4 Anonymization Patterns Reference

Patterns are defined in `TEKCO_AnonymizationPattern__mdt`. Each pattern defines **how** a field value is transformed.

| Developer Name | Behavior |
|---|---|
| `NAME_FIRST_LETTER` | Keeps only the first letter, followed by: external ID field → `TEKCO_FunctionalId__c` → Salesforce record Id (fallback chain). e.g. `Jean Dupont` → `J0035g00000XyZAA` |
| `NAME_FIRST_LETTER_SFID` | First letter followed by Salesforce Id (no fallback). e.g. `Jean` → `J0035g00000XyZAA` |
| `EMAIL_PLUS_EXTERNALID` | Email with a `+` alias containing the external ID. e.g. `sf_sap+EXT001@airliquide.com` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Same with the sandbox subdomain appended. e.g. `sf_sap+EXT001@airliquide.com.fr.mmedlej` |
| `EMAIL_PLUS_SFID` | Email with a `+` alias containing the Salesforce Id. e.g. `sf_sap+0035g00000XyZAA@airliquide.com` |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | Same with the sandbox subdomain appended. |
| `PHONE_MASK` | Keeps the first 4 characters and replaces the rest with zeros. e.g. `+33123456789` → `+33100000000` |
| `SSN_SEQUENTIAL` | Replaces with a sequential digit string of the same length as the original value. |
| `ADDRESS_STREET_RANDOM` | Finds the first number in the address and adds a random offset (1–20). |
| `LOREM_IPSUM` | Replaces text with a fixed Lorem Ipsum string. |
| `CLEAR` | Sets the field to null (empty). |
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

---

### 2.5 Configuring Anonymization Rules

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

**Adding a new rule — step by step:**

1. Go to **Setup → Custom Metadata Types → TEKCO Anonymization Field Config → Manage Records**.
2. Click **New**.
3. Enter a meaningful **Label** (e.g. `Patient PersonEmail`) and a unique **Developer Name**.
4. Fill in the required fields: object, field, pattern, and check `TEKCO_IsActive__c`.
5. Optional: fill in the Record Type if the rule applies to one population only.
6. Optional: check `TEKCO_DeleteHistory__c` if field history should be purged.
7. Save.

> **No code deployment is required** to add or modify an anonymization rule. Custom Metadata records can be edited directly in production and take effect on the next run.

**Disabling a rule temporarily:** uncheck `TEKCO_IsActive__c`. The rule disappears from the interface and is not processed until re-enabled.

---

## 3. Deployment and Usage

### 3.1 Prerequisites

The following must be in place before deploying or using the tool.

#### Enable Field History Deletion *(required for Phase 3)*

Phase 3 (field history deletion) requires a Salesforce permission that is **not enabled by default**. Without it, history records are silently not deleted even if `TEKCO_DeleteHistory__c` is checked.

**Step 1 — Enable at org level:**

1. Go to **Setup → User Interface**.
2. Check **Enable "Delete Field History" User Permission**.
3. Save.

**Step 2 — Grant to the permission set:**

1. Go to **Setup → Permission Sets → TEKCO Anonymization Admin**.
2. Click **System Permissions**.
3. Find **Delete Field History** and enable it.
4. Save.

> This step must be repeated after each sandbox refresh.

---

### 3.2 Deploying the Package

Deployment is performed using the Salesforce CLI (`sf`) with the `package.xml` manifest located at `anonymization/manifest/package.xml`.

#### What the package contains

The manifest groups all components required by the tool into a single deployable unit:

| Metadata type | Components included |
|---|---|
| **ApexClass** | `TEKCO_AnonymizationBatch`, `TEKCO_AnonymizationController`, `TEKCO_AnonymizationPatternService`, `TEKCO_AnonymizationAuditService`, `TEKCO_AnonymizationBypassService`, `TEKCO_ContentDocumentBatch`, `TEKCO_FieldHistoryBatch` |
| **LightningComponentBundle** | `tekcoDataAnonymizationAdmin` |
| **CustomObject** | `TEKCO_AnonymizationAuditLog__c`, `TEKCO_AnonymizationFieldConfig__mdt`, `TEKCO_AnonymizationPattern__mdt` |
| **CustomMetadata** | All configured pattern records and field rules |
| **CustomPermission** | `TEKCO_AnonymizeData` |
| **PermissionSet** | `TEKCO_AnonymizationAdmin` |
| **CustomTab** | `TEKCO_Data_Anonymization` |
| **Layout** | `TEKCO_AnonymizationAuditLog__c` audit log layout |

#### Deploy command

From the root of the repository, run:

```bash
sf project deploy start --manifest anonymization/manifest/package.xml --target-org <org-alias>
```

> **Note:** the tool includes a built-in sandbox guard (`TEKCO_AnonymizationPatternService.assertIsSandbox()`) that blocks execution in production orgs. Deploying to production is safe — the batch cannot be triggered there.

---

### 3.3 Post-Deployment Steps

After the deployment completes, the following manual steps are required.

#### Step 1 — Assign the permission set

Grant the **TEKCO Anonymization Admin** permission set to every user who needs access to the tool.

1. Go to **Setup → Users**.
2. Open the target user.
3. In the **Permission Set Assignments** section, click **Edit Assignments**.
4. Add **TEKCO Anonymization Admin** and save.

#### Step 2 — Add the tab to the navigation app

1. Go to **Setup → App Manager**.
2. Edit the Lightning app where the tool should appear.
3. Under **Navigation Items**, add the **TEKCO Data Anonymization** tab.
4. Save.

#### Step 3 — Configure anonymization rules *(new org only)*

If deploying to an org that does not yet have any rules configured:

1. Deploy or create `TEKCO_AnonymizationPattern__mdt` records (the algorithms).
2. Create `TEKCO_AnonymizationFieldConfig__mdt` records to define which fields on which objects to anonymize.

See [Section 3.11 — Configuring Anonymization Rules](#311-configuring-anonymization-rules) for the full reference.

---

### 3.4 Sandbox Refresh Checklist

After each sandbox refresh, the org reverts to production state. Repeat the following:

- [ ] Redeploy the package: `sf project deploy start --manifest anonymization/manifest/package.xml --target-org <org-alias>`
- [ ] Reassign the **TEKCO Anonymization Admin** permission set to relevant users.
- [ ] Re-enable **Delete Field History** at org level (Setup → User Interface) and on the permission set.
- [ ] Verify the tab appears in the navigation app.
- [ ] Run a preview to confirm rules and record counts are as expected before launching.

---

### 3.5 Accessing the Interface

The tool is accessible from the **TEKCO Data Anonymization** tab in the Salesforce navigation bar.

> **Prerequisite:** you must hold the **TEKCO Anonymize Data** custom permission. If you see a red error banner at the top of the page, contact your Salesforce administrator to be granted this permission.

---

### 3.6 Understanding the Filters

The interface provides three filters to precisely target the scope of an anonymization run.

#### Brands

Restricts processing to records belonging to specific brands.

- Move one or more brands from the **Available** column to the **Selected** column.
- The **Select All** button selects all available brands in one click.
- If no brand is selected, **all records** are included with no brand restriction.

> For objects that do not have a `TEKCO_Brand__c` field but have `TEKCO_Country__c`, the system automatically derives relevant country values from the selected brands using the `TEKCO_CountryBrandSetting__mdt` mapping.

#### Objects

Selects which Salesforce objects will be processed.

- The list only shows objects for which anonymization rules have been defined.
- If no object is selected, **all configured objects** are processed.
- Selecting an object automatically refreshes the available Record Types list.

#### Record Types

This filter only appears when the selected objects have configurations specific to certain Record Types.

- Leave this filter empty to process **all Record Types**.
- Select one or more Record Types to restrict processing to those populations only.

---

### 3.7 Previewing the Scope

Before launching, click the **Preview Scope** button.

This action does two things simultaneously:

1. **Counts the records** that will be impacted for each selected object, applying the brand and Record Type filters.
2. **Loads the list of fields** that will be anonymized, so you can review them before confirming.

Results appear as a summary table showing, per object, the number of records in scope.

> Objects whose only configured action is file deletion (ContentDocument) are visually distinguished with a dark badge. Their record count reflects parent records that have linked files — not the number of files themselves.

---

### 3.8 Reviewing the Fields to Process

After previewing, the **Fields to Anonymize** table lists all fields that will be modified, grouped by object.

| Column | Description |
|---|---|
| **Run** | Checkbox — uncheck a field to **exclude it from this run only** (the rule itself is not deleted). |
| **Field** | API name of the Salesforce field that will be modified. |
| **Pattern** | Anonymization algorithm applied. |
| **Record Type** | Record Type targeted by this rule. Empty = all populations. |
| **Del. History** | If checked, the field change history will be deleted after anonymization. Uncheck to keep history for this run only. |
| **Description** | Functional description of the applied pattern. |

---

### 3.9 Launching Anonymization

Once the scope has been reviewed, click the red **Launch Anonymization** button.

A confirmation dialog opens and summarizes:

- The **brands** selected (or "ALL" if none selected)
- The **objects** that will be processed
- The **Record Types** in scope
- Any **excluded fields** for this run
- Any **fields whose history will not be deleted** for this run

> **WARNING: this operation is irreversible.** Data will be permanently overwritten and cannot be restored from this tool.

Click **Confirm Launch** to start processing, or **Cancel** to return without making any changes.

---

### 3.10 Monitoring Execution

Processing runs in the background via Salesforce batch jobs. The interface refreshes automatically every 5 seconds as long as a run is in progress.

The **Recent Runs** table shows execution history:

| Column | Description |
|---|---|
| **Log #** | Unique identifier of the execution in the audit log. |
| **Object(s)** | Objects processed during this run. |
| **Brands** | Brand filter applied. |
| **Status** | `Running`, `Success`, `Partial`, `Failed` |
| **Processed** | Number of source records anonymized in Phase 1. |
| **Failed** | Number of records that encountered an error. |
| **By** | User who triggered the anonymization. |
| **Started** | Start date and time. |

The **↺** button at the top right allows manual refresh.

**Status meanings:**

| Status | Meaning |
|---|---|
| `Running` | At least one batch phase is still in progress. |
| `Success` | All records processed without errors. |
| `Partial` | Processing completed but some records failed. Check the error column. |
| `Failed` | A chain-level error stopped execution before completion. |

---

### 3.11 Configuring Anonymization Rules

The tool's behavior is entirely driven by two Custom Metadata types, accessible from **Setup → Custom Metadata Types**.

#### Available Patterns — `TEKCO_AnonymizationPattern__mdt`

A pattern defines **how** a field value will be transformed.

| Developer Name | Behavior |
|---|---|
| `NAME_FIRST_LETTER` | Keeps only the first letter of the value, followed by the external ID, then `TEKCO_FunctionalId__c`, then the Salesforce Id as a last resort. e.g. `Jean Dupont` → `J0035g00000XyZAA` |
| `NAME_FIRST_LETTER_SFID` | Keeps the first letter followed by the Salesforce Id (forced — no fallback). e.g. `Jean` → `J0035g00000XyZAA` |
| `EMAIL_PLUS_EXTERNALID` | Generates an email with a `+` alias containing the external ID. e.g. `sf_sap+EXT001@airliquide.com` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Same as above with the sandbox org subdomain appended. e.g. `sf_sap+EXT001@airliquide.com.fr.mmedlej` |
| `EMAIL_PLUS_SFID` | Generates an email with a `+` alias containing the Salesforce Id. e.g. `sf_sap+0035g00000XyZAA@airliquide.com` |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | Same as above with the sandbox org subdomain appended. |
| `PHONE_MASK` | Masks the phone number while preserving its format. e.g. `+33123456789` → `+33100000000` |
| `SSN_SEQUENTIAL` | Replaces the social security number with a unique sequential number of the same length. |
| `ADDRESS_STREET_RANDOM` | Finds the first number in the address and adds a random offset (1–20). |
| `LOREM_IPSUM` | Replaces text content with Lorem Ipsum. |
| `CLEAR` | Empties the field (sets it to null if not already empty). |
| `DELETE_CONTENT_DOCUMENT` | Deletes all files (ContentDocuments and Attachments) linked to the record. Handled in Phase 2. |
| `EMAIL_MESSAGE_LOREM` | For EmailMessage: Draft records have body replaced by Lorem Ipsum; non-Draft records are deleted entirely. |
| `KEEP` | No change — keeps the original value as-is. |

**Pattern configuration fields:**

| Field | Description |
|---|---|
| `TEKCO_Description__c` | Functional description displayed in the interface. |
| `TEKCO_IsActive__c` | Enabled / disabled. An inactive pattern cannot be used in a field rule. |
| `TEKCO_BaseEmail__c` | Base email address for `EMAIL_PLUS_*` patterns. e.g. `sf_sap@airliquide.com` |
| `TEKCO_ExternalIdField__c` | API name of the field used as external identifier for `EMAIL_PLUS_EXTERNALID` and `NAME_FIRST_LETTER` patterns. |
| `TEKCO_SsnLength__c` | Target length for `SSN_SEQUENTIAL` (used as fallback if the original value is blank). |

---

#### Field Rules — `TEKCO_AnonymizationFieldConfig__mdt`

A field rule defines **which field** on **which object** will be anonymized using **which pattern**.

**Required fields:**

| Field | Description |
|---|---|
| `TEKCO_ObjectApiName__c` | API name of the target Salesforce object. e.g. `Account`, `Contact`, `Case` |
| `TEKCO_FieldApiName__c` | API name of the field to anonymize. e.g. `FirstName`, `PersonEmail`, `ACCCO_Email__c` |
| `TEKCO_PatternType__c` | Developer Name of the pattern to apply. Must match an active `TEKCO_AnonymizationPattern__mdt` record. |
| `TEKCO_IsActive__c` | Must be checked for the rule to be picked up. |

**Filtering fields:**

| Field | Description |
|---|---|
| `TEKCO_RecordTypeDeveloperName__c` | Restricts the rule to records of a specific Record Type. Leave empty to apply to all Record Types. |
| `TEKCO_AdditionalFilter__c` | Additional SOQL condition appended to the WHERE clause. e.g. `ACCCO_RelatedAccount__r.RecordType.DeveloperName = 'ACCCO_Patient'` |

**Child object fields** *(use when filtering must go through a parent object)*:

| Field | Description |
|---|---|
| `TEKCO_ParentObjectApiName__c` | API name of the parent object. e.g. `Account` |
| `TEKCO_ParentLookupFieldApiName__c` | API name of the lookup field on the child object pointing to the parent. |
| `TEKCO_ParentRecordTypeDeveloperName__c` | Record Type of the parent object used as a filter. |

**History behavior:**

| Field | Description |
|---|---|
| `TEKCO_DeleteHistory__c` | If checked, the field change history (`FieldHistory`) will be deleted after anonymization. Leave unchecked for fields where audit trail is not a concern. |

---

#### Adding a New Rule — Step by Step

1. Go to **Setup → Custom Metadata Types → TEKCO Anonymization Field Config → Manage Records**.
2. Click **New**.
3. Enter a meaningful **Label** (e.g. `Patient PersonEmail`) and a unique **Developer Name** (e.g. `Patient_PersonEmail`).
4. Fill in the required fields: object, field, pattern, and check `TEKCO_IsActive__c`.
5. Optional: fill in the Record Type if the rule applies to one population only.
6. Optional: check `TEKCO_DeleteHistory__c` if the field history should be purged.
7. Save.

The rule is immediately taken into account on the next run.

> **No code deployment is required** to add or modify an anonymization rule. Custom Metadata records can be edited directly in production.

#### Temporarily Disabling a Rule

To suspend a rule without deleting it, simply uncheck `TEKCO_IsActive__c` on the record. The rule will no longer appear in the interface and will not be processed.

#### Processing Order

Objects are processed in the order they appear in the selected objects list. Within a single object, all configured fields are processed in a single batch pass — one record is updated in a single DML operation regardless of how many fields are configured for it.

---

### 3.12 Known Limitations

#### Asset Files cannot be deleted (Phase 2)

**Error message**: `We can't delete this file because it's an asset file being referenced by one or more objects. To delete it, first remove all references to it.`

**When it occurs**: During Phase 2 (ContentDocument deletion), when a file linked to a target record is flagged as an **Asset File** by Salesforce. A file becomes an Asset File when it is used as a managed content asset — for example by Experience Cloud, CMS, or other Salesforce platform features. This flag is stored on `ContentVersion.IsAsset`.

**Why it cannot be bypassed**: Salesforce enforces this restriction at the platform level, regardless of user permissions or the `allOrNothing` DML setting. There is no API to delete an Asset File directly.

**Current behavior**: The file is counted as a failed record and the error message is written to the audit log's error column. The rest of the batch continues normally.

**What to do if you encounter it**: Identify the asset file via the error in the audit log, then either remove its asset references manually in Salesforce (Setup → CMS or Experience Cloud assets) before re-running, or accept that these specific files will not be deleted by the anonymization process.

---

## 4. Testing

### 4.1 Testing Strategy

Testing should be performed in UAT before any production data handling. Given the volumes involved (potentially millions of records), a phased approach is recommended: test one representative object at a time before running the full scope.

**Recommended test objects (by profile):**

| Object | Why |
|---|---|
| `Account` | High volume, standard object, no linked files — baseline Phase 1 timing |
| `Case` | Has ContentDocument links — covers Phase 2 |
| `EmailMessage` | Mixed update/delete logic — covers the `EMAIL_MESSAGE_LOREM` pattern |

---

### 4.2 Recommended Test Protocol

1. In the interface, select **one object only** (e.g. Account) and **one brand**.
2. Click **Preview Scope** and note the record count.
3. Click **Launch Anonymization** and note the start time.
4. Run the monitoring queries below every 2 minutes to track progress.
5. Once completed, record: duration, records processed, errors.
6. Repeat for Case (covers Phase 2) and EmailMessage (covers special delete logic).

Use the results from these three objects to extrapolate the full-run duration for the team report.

---

### 4.3 Monitoring Queries

Run these queries in **Developer Console → Query Editor** or via SOQL in Workbench.

#### Track batch progress in real time

```sql
SELECT ApexClass.Name, Status, JobItemsProcessed, TotalJobItems,
       CreatedDate, ExtendedStatus
FROM AsyncApexJob
WHERE ApexClass.Name LIKE 'TEKCO_%Batch'
ORDER BY CreatedDate DESC
LIMIT 10
```

- `TotalJobItems` = total number of chunks (records ÷ batch size)
- `JobItemsProcessed / TotalJobItems` = % completion
- `ExtendedStatus` shows any runtime errors

#### Measure duration per phase after completion

```sql
SELECT ApexClass.Name, Status, JobItemsProcessed, TotalJobItems,
       CreatedDate, CompletedDate
FROM AsyncApexJob
WHERE ApexClass.Name LIKE 'TEKCO_%Batch'
  AND Status = 'Completed'
ORDER BY CreatedDate DESC
LIMIT 20
```

`CompletedDate − CreatedDate` (in seconds) = duration of that phase.

#### Read the audit log (total duration + errors)

```sql
SELECT Name, TEKCO_Status__c, TEKCO_RecordsProcessed__c,
       TEKCO_RecordsFailed__c, TEKCO_BrandFilter__c,
       TEKCO_ObjectApiName__c, TEKCO_StartTime__c, TEKCO_EndTime__c,
       TEKCO_TriggeredBy__r.Name, TEKCO_ErrorMessage__c
FROM TEKCO_AnonymizationAuditLog__c
ORDER BY TEKCO_StartTime__c DESC
LIMIT 5
```

`TEKCO_EndTime__c − TEKCO_StartTime__c` = total elapsed time for the full chain.

---

### 4.4 Interpreting Results

**Expected batch sizes in the async job log:**

| Phase | Batch class | Batch size | Expected chunks for 100 000 records |
|---|---|---|---|
| Phase 1 — Fields | `TEKCO_AnonymizationBatch` | 2 000 | 50 |
| Phase 2 — Files | `TEKCO_ContentDocumentBatch` | 500 | 200 |
| Phase 3 — History | `TEKCO_FieldHistoryBatch` | 2 000 | 50 |

**Identifying a stuck run:**

If `Status = 'Processing'` and `JobItemsProcessed` has not changed in more than 10 minutes, check for:
- A CPU timeout error in `ExtendedStatus`
- A governor limit error (SOQL rows, DML rows)
- A queue full situation (other batch jobs filling the Flex Queue)

**If Phase 3 silently skips history deletion:**

Verify the **Delete Field History** permission is enabled (see [Section 3.1](#31-prerequisites)). If the permission is missing, history records are not deleted and no error is raised.

---

### 4.5 Test Checklist

#### Before launch

- [ ] Sandbox guard is active — confirm org is a sandbox (`IsSandbox = true` on the Organization record)
- [ ] Bypass settings are configured — `TEKCO_BypassSettings__c` custom setting exists
- [ ] Preview Scope returns correct counts for selected filters
- [ ] Fields to Anonymize table shows expected fields

#### During execution

- [ ] `AsyncApexJob` shows `TEKCO_AnonymizationBatch` with Status `Processing`
- [ ] `TotalJobItems` matches expected chunk count (records ÷ 2 000)
- [ ] Status transitions from `Running` to `Success` / `Partial` in the audit log

#### After execution — Phase 1 (fields)

- [ ] Sample records show anonymized values (not original personal data)
- [ ] Record count in audit log matches expected volume
- [ ] No unexpected `Failed` records

#### After execution — Phase 2 (files)

- [ ] ContentDocuments linked to processed records are deleted
- [ ] Attachments (legacy files created via integration API) are deleted
- [ ] `CombinedAttachment` view on a processed record is empty

#### After execution — Phase 3 (history)

- [ ] Field history for anonymized fields is empty
- [ ] Fields not marked `Del. History` still have their history

#### Regression

- [ ] Bypass settings restored to pre-run state (`TEKCO_BypassSettings__c`)
- [ ] Audit log status is `Success` or `Partial` (not `Running` or `Failed`)
- [ ] Unselected brands are untouched — spot-check a record from a non-selected brand
