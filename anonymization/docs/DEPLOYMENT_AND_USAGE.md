# Data Anonymization — Deployment and Usage

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Deploying the Package](#2-deploying-the-package)
3. [Post-Deployment Steps](#3-post-deployment-steps)
4. [Sandbox Refresh Checklist](#4-sandbox-refresh-checklist)
5. [Accessing the Interface](#5-accessing-the-interface)
6. [Using the By Criteria Tab](#6-using-the-by-criteria-tab)
   - 6.1 [Understanding the Filters](#61-understanding-the-filters)
   - 6.2 [Previewing the Scope](#62-previewing-the-scope)
   - 6.3 [Reviewing the Fields to Process](#63-reviewing-the-fields-to-process)
   - 6.4 [Launching Anonymization](#64-launching-anonymization)
   - 6.5 [Monitoring Execution](#65-monitoring-execution)
7. [Using the By ID Tab](#7-using-the-by-id-tab)
   - 7.1 [Pasting IDs](#71-pasting-ids)
   - 7.2 [Previewing Scope](#72-previewing-scope)
   - 7.3 [Reviewing the Fields to Process](#73-reviewing-the-fields-to-process)
   - 7.4 [Launching Anonymization](#74-launching-anonymization)
   - 7.5 [Monitoring Execution](#75-monitoring-execution)
8. [Configuring Anonymization Rules](#8-configuring-anonymization-rules)
9. [Configuring a New Org (Multi-Org Setup)](#9-configuring-a-new-org-multi-org-setup)
10. [Known Limitations](#10-known-limitations)
11. [Testing](#11-testing)

---

## 1. Prerequisites

The following must be in place before deploying or using the tool.

### Enable Field History Deletion *(required for Phase 3)*

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

## 2. Deploying the Package

Deployment is performed using the Salesforce CLI (`sf`) with the `package.xml` manifest located at `anonymization/manifest/package.xml`.

### What the package contains

| Metadata type | Components included |
|---|---|
| **ApexClass** | `TEKCO_AnonymizationBatch`, `TEKCO_AnonymizationController`, `TEKCO_AnonymizationPatternService`, `TEKCO_AnonymizationAuditService`, `TEKCO_AnonymizationBypassService`, `TEKCO_ContentDocumentBatch`, `TEKCO_FieldHistoryBatch`, `TEKCO_AnonymizationByIdBatch`, `TEKCO_ContentDocumentByIdBatch`, `TEKCO_FieldHistoryByIdBatch`, `TEKCO_AnonymizationByIdController`, `TEKCO_AnonymizationOrgConfigService` |
| **LightningComponentBundle** | `tekcoDataAnonymizationAdmin` |
| **CustomObject** | `TEKCO_AnonymizationAuditLog__c`, `TEKCO_AnonymizationFieldConfig__mdt`, `TEKCO_AnonymizationPattern__mdt`, `TEKCO_AnonymizationOrgConfig__mdt` |
| **CustomField** | `TEKCO_AnonymizationPattern__mdt.TEKCO_RegexFind__c`, `TEKCO_AnonymizationPattern__mdt.TEKCO_RegexReplace__c`, all `TEKCO_AnonymizationOrgConfig__mdt` fields |
| **CustomMetadata** | All configured pattern records, field rules, and org config records |
| **CustomPermission** | `TEKCO_AnonymizeData` |
| **PermissionSet** | `TEKCO_AnonymizationAdmin` |
| **CustomTab** | `TEKCO_Data_Anonymization` |

### Deploy command

From the root of the repository, run:

```bash
sf project deploy start --manifest anonymization/manifest/package.xml --target-org <org-alias>
```

> **Note:** the tool includes a built-in sandbox guard that blocks execution in production orgs. Deploying to production is safe — the batch cannot be triggered there.

---

## 3. Post-Deployment Steps

### Step 1 — Assign the permission set

Grant the **TEKCO Anonymization Admin** permission set to every user who needs access to the tool.

1. Go to **Setup → Users**.
2. Open the target user.
3. In the **Permission Set Assignments** section, click **Edit Assignments**.
4. Add **TEKCO Anonymization Admin** and save.

### Step 2 — Add the tab to the navigation app

1. Go to **Setup → App Manager**.
2. Edit the Lightning app where the tool should appear.
3. Under **Navigation Items**, add the **TEKCO Data Anonymization** tab.
4. Save.

### Step 3 — Configure the org config record *(non-standard orgs only)*

If the org does not use the standard TEKCO naming convention (e.g. Portugal ALH), create or deploy a `TEKCO_AnonymizationOrgConfig__mdt` record. See [Section 9 — Configuring a New Org](#9-configuring-a-new-org-multi-org-setup).

### Step 4 — Configure anonymization rules *(new org only)*

If deploying to an org that does not yet have any rules configured:

1. Deploy or create `TEKCO_AnonymizationPattern__mdt` records (the algorithms).
2. Create `TEKCO_AnonymizationFieldConfig__mdt` records to define which fields on which objects to anonymize.

See [Section 8 — Configuring Anonymization Rules](#8-configuring-anonymization-rules) for the full reference.

---

## 4. Sandbox Refresh Checklist

After each sandbox refresh, the org reverts to production state. Repeat the following:

- [ ] Redeploy the package: `sf project deploy start --manifest anonymization/manifest/package.xml --target-org <org-alias>`
- [ ] Reassign the **TEKCO Anonymization Admin** permission set to relevant users.
- [ ] Re-enable **Delete Field History** at org level (Setup → User Interface) and on the permission set.
- [ ] Verify the tab appears in the navigation app.
- [ ] Run a preview to confirm rules and record counts are as expected before launching.

---

## 5. Accessing the Interface

The tool is accessible from the **TEKCO Data Anonymization** tab in the Salesforce navigation bar.

> **Prerequisite:** you must hold the **TEKCO Anonymize Data** custom permission. If you see a red error banner at the top of the page, contact your Salesforce administrator to be granted this permission.

The interface is divided into two tabs:
- **By Criteria** — standard anonymization by brand, object, and record type
- **By ID (DataMig)** — targeted anonymization by explicit record ID list

---

## 6. Using the By Criteria Tab

### 6.1 Understanding the Filters

#### Brands

Restricts processing to records belonging to specific brands.

- Move one or more brands from the **Available** column to the **Selected** column.
- The **Select All** button selects all available brands in one click.
- If no brand is selected, **all records** are included with no brand restriction.

> For objects that do not have a `TEKCO_Brand__c` field but have `TEKCO_Country__c`, the system automatically derives relevant country values from the selected brands using the `TEKCO_CountryBrandSetting__mdt` mapping (standard orgs) or directly from the brand object (orgs configured with `TEKCO_BrandObjectApiName__c`).

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

### 6.2 Previewing the Scope

Before launching, click the **Preview Scope** button.

This action does two things simultaneously:

1. **Counts the records** that will be impacted for each selected object, applying the brand and Record Type filters.
2. **Loads the list of fields** that will be anonymized, so you can review them before confirming.

Results appear as a summary table showing, per object, the number of records in scope.

> Objects whose only configured action is file deletion (ContentDocument) are visually distinguished with a dark badge. Their record count reflects parent records that have linked files — not the number of files themselves.

---

### 6.3 Reviewing the Fields to Process

After previewing, the **Fields to Anonymize** table lists all fields that will be modified, grouped by object.

| Column | Description |
|---|---|
| **Run** | Checkbox — uncheck a field to **exclude it from this run only** (the rule itself is not deleted). |
| **Field** | API name of the Salesforce field that will be modified. |
| **Pattern** | Anonymization algorithm applied. |
| **Record Type** | Record Type targeted by this rule. Empty = all populations. |
| **Del. History** | If checked, the field change history will be deleted after anonymization. Uncheck to keep history for this run only. |
| **Description** | Functional description of the applied pattern. |

Use **Run: Select All / Deselect All** and **Del. History: Select All / Deselect All** to adjust in bulk.

---

### 6.4 Launching Anonymization

Once the scope has been reviewed, click the red **Launch Anonymization** button.

A confirmation dialog opens and summarizes the brands, objects, Record Types, excluded fields, and fields whose history will not be deleted.

> **WARNING: this operation is irreversible.** Data will be permanently overwritten and cannot be restored from this tool.

Click **Confirm Launch** to start processing, or **Cancel** to return without making any changes.

> **Automation bypass**: immediately before the first batch job starts, the tool sets every boolean flag on the `TEKCO_BypassSettings__c` Hierarchy Custom Setting to `true` for the running user. This suppresses all triggers and automation rules for the duration of the entire processing chain. Once the last phase completes — whether successfully or with an error — the original flag values are restored exactly as they were before the run.

---

### 6.5 Monitoring Execution

Processing runs in the background via Salesforce batch jobs. The interface refreshes automatically every 5 seconds as long as a run is in progress.

The **Recent Runs** table shows execution history for By Criteria runs only.

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

**Status meanings:**

| Status | Meaning |
|---|---|
| `Running` | At least one batch phase is still in progress. |
| `Success` | All records processed without errors. |
| `Partial` | Processing completed but some records failed. Check the error column. |
| `Failed` | A chain-level error stopped execution before completion. |

**How the Processed count is calculated:** a record is counted only when at least one field value was actually changed. Records that were already anonymized, did not match any rule, or had all target fields blank are not counted. Phase 2 and 3 deletions are also excluded from the count.

---

## 7. Using the By ID Tab

The **By ID (DataMig)** tab is designed for DataMig scenarios where specific records must be anonymized by providing their IDs directly, without using a brand filter.

### 7.1 Pasting IDs

In the **Record IDs** textarea, paste the Salesforce IDs of the records to anonymize. Accepted formats:
- One ID per line
- Comma-separated
- Semicolon-separated
- Mixed (IDs from different SObject types can be pasted together)

The component displays a real-time count of detected IDs as you type.

### 7.2 Previewing Scope

Click **Preview Scope** to resolve the full scope without starting any batch.

The system performs the following steps:

1. Parses and groups IDs by SObject type.
2. Validates each SObject type against the active CMDT configuration.
3. Resolves child objects: for each provided parent ID, queries child objects linked via `TEKCO_ParentObjectApiName__c` / `TEKCO_ParentLookupFieldApiName__c` in CMDT.

The result panel shows three sections:

| Section | Content |
|---------|---------|
| **Direct objects** | Objects whose IDs were provided directly, with record count |
| **Resolved children** | Objects discovered through parent-child CMDT relationships, with count and source label (e.g. `via Account.AccountId`) |
| **Skipped IDs** | IDs that could not be parsed or whose SObject type has no CMDT configuration |

> No data is modified at this step.

### 7.3 Reviewing the Fields to Process

After previewing, the **Fields to Anonymize** table works identically to the By Criteria tab.

Use **Run: Select All / Deselect All** and **Del. History: Select All / Deselect All** to adjust in bulk. Note that **Del. History: Select All** only restores history deletion for fields originally configured with `TEKCO_DeleteHistory__c = true` — it does not enable history deletion for fields that were not configured for it.

The **Target object** dropdown at the top of the By ID tab shows the SObject API names of configured objects. Labels do not include the parent name in parentheses, since the parent/child context is resolved differently in this mode.

### 7.4 Launching Anonymization

Click **Launch Anonymization** (disabled until `totalValid > 0`). A confirmation modal displays the resolved scope summary.

Click **Confirm Launch** to start. An audit log entry is created immediately with `TEKCO_BrandFilter__c = 'BY_ID (N record(s))'`.

The same automation bypass and production guard as the By Criteria tab apply.

### 7.5 Monitoring Execution

The **Recent Runs** table in the By ID tab shows only By ID runs, filtered by `TEKCO_BrandFilter__c LIKE 'BY_ID%'`. It auto-refreshes every 5 seconds while a run is in progress.

The columns and status meanings are identical to the By Criteria tab.

---

## 8. Configuring Anonymization Rules

The tool's behavior is entirely driven by two Custom Metadata types, accessible from **Setup → Custom Metadata Types**.

### Available Patterns — `TEKCO_AnonymizationPattern__mdt`

| Developer Name | Behavior |
|---|---|
| `NAME_FIRST_LETTER` | Keeps only the first letter of the value, followed by the external ID, then the configured functional ID field, then the Salesforce Id as a last resort. e.g. `Jean Dupont` → `J0035g00000XyZAA` |
| `NAME_FIRST_LETTER_SFID` | Keeps the first letter followed by the Salesforce Id (forced — no fallback). e.g. `Jean` → `J0035g00000XyZAA` |
| `EMAIL_PLUS_EXTERNALID` | Generates an email with a `+` alias containing the external ID. e.g. `sf_sap+EXT001@airliquide.com` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Same as above with the sandbox org subdomain appended. |
| `EMAIL_PLUS_SFID` | Generates an email with a `+` alias containing the Salesforce Id. |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | Same as above with the sandbox org subdomain appended. |
| `SSN_SEQUENTIAL` | Replaces the value with a sequential digit string of the same length. |
| `ADDRESS_STREET_RANDOM` | Finds the first number in the address and adds a random offset (1–20). |
| `REGEX` | Configurable find/replace using `TEKCO_RegexFind__c` and `TEKCO_RegexReplace__c`. |
| `DELETE_CONTENT_DOCUMENT` | Deletes all files linked to the record. Handled in Phase 2. |
| `EMAIL_MESSAGE_LOREM` | For EmailMessage: Draft records get Lorem Ipsum body; non-Draft records are deleted. |
| `KEEP` | No change — keeps the original value. |

**Pattern configuration fields:**

| Field | Description |
|---|---|
| `TEKCO_Description__c` | Functional description displayed in the interface. |
| `TEKCO_IsActive__c` | Enabled / disabled. |
| `TEKCO_BaseEmail__c` | Base email address for `EMAIL_PLUS_*` patterns. |
| `TEKCO_ExternalIdField__c` | API name of the field used as external identifier. |
| `TEKCO_SsnLength__c` | Target length for `SSN_SEQUENTIAL` (fallback if the original value is blank). |
| `TEKCO_RegexFind__c` | Regular expression to match (for `REGEX` type). Blank = full replacement. |
| `TEKCO_RegexReplace__c` | Replacement string (for `REGEX` type). Supports `$1`, `$2` groups. |

### Field Rules — `TEKCO_AnonymizationFieldConfig__mdt`

**Required fields:**

| Field | Description |
|---|---|
| `TEKCO_ObjectApiName__c` | API name of the target Salesforce object. |
| `TEKCO_FieldApiName__c` | API name of the field to anonymize. |
| `TEKCO_PatternType__c` | Developer Name of the pattern to apply. |
| `TEKCO_IsActive__c` | Must be checked for the rule to be picked up. |

**Filtering fields:**

| Field | Description |
|---|---|
| `TEKCO_RecordTypeDeveloperName__c` | Restricts the rule to records of a specific Record Type. Leave empty for all. |
| `TEKCO_AdditionalFilter__c` | Additional SOQL condition appended to the WHERE clause. |

**Child object fields:**

| Field | Description |
|---|---|
| `TEKCO_ParentObjectApiName__c` | API name of the parent object. |
| `TEKCO_ParentLookupFieldApiName__c` | API name of the lookup field on the child object pointing to the parent. |
| `TEKCO_ParentRecordTypeDeveloperName__c` | Record Type of the parent used as a filter. |

**History behavior:**

| Field | Description |
|---|---|
| `TEKCO_DeleteHistory__c` | If checked, field change history will be deleted in Phase 3. |

### Adding a New Rule — Step by Step

1. Go to **Setup → Custom Metadata Types → TEKCO Anonymization Field Config → Manage Records**.
2. Click **New**.
3. Enter a meaningful **Label** (e.g. `Patient PersonEmail`) and a unique **Developer Name** (e.g. `Patient_PersonEmail`).
4. Fill in the required fields: object, field, pattern, and check `TEKCO_IsActive__c`.
5. Optional: fill in the Record Type if the rule applies to one population only.
6. Optional: check `TEKCO_DeleteHistory__c` if the field history should be purged.
7. Save.

> **No code deployment is required** to add or modify an anonymization rule. Custom Metadata records can be edited directly.

To temporarily disable a rule without deleting it, uncheck `TEKCO_IsActive__c`. The rule disappears from the interface and is not processed until re-enabled.

---

## 9. Configuring a New Org (Multi-Org Setup)

Use this section when deploying the tool in an org that does not follow the standard TEKCO naming convention — for example, an org where the brand is stored as a lookup object rather than a picklist field, or where field names differ.

### Step 1 — Identify the org domain prefix

Run the following in **Developer Console → Execute Anonymous**:

```apex
System.debug(URL.getOrgDomainUrl().getHost().substringBefore('.'));
```

Note the value — this is what you will set in `TEKCO_OrgDomain__c`.

### Step 2 — Create the CMDT record

1. Go to **Setup → Custom Metadata Types → TEKCO Anonymization Org Config → Manage Records**.
2. Click **New**.
3. Enter a **Label** (e.g. `Portugal ALH`) and **Developer Name** (e.g. `Portugal_ALH`).
4. Fill in the fields according to your org's configuration (see reference table below).
5. Save.

Alternatively, create a `.md-meta.xml` file in `anonymization/main/default/customMetadata/` and deploy it via `sf project deploy start`.

### Field reference

| Field | Required | Notes |
|-------|----------|-------|
| `TEKCO_OrgDomain__c` | Yes | Domain prefix from Step 1. e.g. `airliquide-pt--sandbox` |
| `TEKCO_FunctionalIdField__c` | Yes | e.g. `ALH_FunctionalId__c` or `TEKCO_FunctionalId__c` |
| `TEKCO_BypassEnabled__c` | Yes | Set to `true` if `TEKCO_BypassSettings__c` is deployed and configured in this org |
| `TEKCO_BrandObjectApiName__c` | If brand is a lookup | API name of the brand SObject (e.g. `ALH_Brand__c`). Leave blank to use picklist mode |
| `TEKCO_BrandCodeField__c` | If brand object set | Field holding the brand code label (e.g. `Name`) |
| `TEKCO_BrandCountryField__c` | If brand object set | Field holding the country value (e.g. `ALH_Country__c`) |
| `TEKCO_BrandLookupFieldOnRecord__c` | If brand object set | Relationship name on anonymized records (e.g. `ALH_Brand__r`) |
| `TEKCO_ExternalIdFields__c` | Optional | Comma-separated external ID fields shown in the By ID tab. e.g. `ALH_ExternalSystemID__c` |

### Step 3 — Verify

1. Open the **TEKCO Data Anonymization** tab.
2. In the **By Criteria** tab, verify that the brand dropdown shows the correct brands from the brand object (or picklist, depending on the mode).
3. In the **By ID** tab, verify that the external ID selector shows the expected fields.
4. Run a **Preview Scope** with a small set of IDs to confirm resolution logic is correct.

### Troubleshooting

**Org config not picked up:**
Confirm that `TEKCO_OrgDomain__c` matches exactly what `URL.getOrgDomainUrl().getHost().substringBefore('.')` returns. Even a single character difference causes the fallback to default config.

**Brand dropdown is empty in brand object mode:**
Verify that `TEKCO_BrandObjectApiName__c`, `TEKCO_BrandCodeField__c`, and `TEKCO_BrandCountryField__c` are all set and that the running user has read access to the brand SObject.

**Children not resolved in By ID mode:**
Verify that `TEKCO_ParentObjectApiName__c` on the child's CMDT row matches the exact API name of the parent SObject, and that `TEKCO_ParentLookupFieldApiName__c` is the API name of the lookup field (e.g. `AccountId`, not `Account`).

---

## 10. Known Limitations

### Asset Files cannot be deleted (Phase 2)

**Error message**: `We can't delete this file because it's an asset file being referenced by one or more objects. To delete it, first remove all references to it.`

**When it occurs**: During Phase 2 (ContentDocument deletion), when a file linked to a target record is flagged as an Asset File by Salesforce (stored on `ContentVersion.IsAsset`).

**Why it cannot be bypassed**: Salesforce enforces this restriction at the platform level, regardless of user permissions or the `allOrNothing` DML setting.

**Current behavior**: The file is counted as a failed record and the error message is written to the audit log's error column. The rest of the batch continues normally.

**What to do**: Identify the asset file via the error in the audit log, then either remove its asset references manually (Setup → CMS or Experience Cloud assets) before re-running, or accept that these specific files will not be deleted.

---

## 11. Testing

### Testing Strategy

Testing should be performed in UAT before any production data handling. A phased approach is recommended: test one representative object at a time before running the full scope.

**Recommended test objects:**

| Object | Why |
|---|---|
| `Account` | High volume, standard object, no linked files — baseline Phase 1 timing |
| `Case` | Has ContentDocument links — covers Phase 2 |
| `EmailMessage` | Mixed update/delete logic — covers the `EMAIL_MESSAGE_LOREM` pattern |

### Recommended Test Protocol — By Criteria

1. Select **one object only** (e.g. Account) and **one brand**.
2. Click **Preview Scope** and note the record count.
3. Click **Launch Anonymization** and note the start time.
4. Run the monitoring queries below every 2 minutes to track progress.
5. Once completed, record: duration, records processed, errors.
6. Repeat for Case (covers Phase 2) and EmailMessage (covers special delete logic).

### Recommended Test Protocol — By ID

1. Provide 2–3 IDs from different objects (e.g. one Account, one Contact).
2. Click **Preview Scope** — verify the direct objects and resolved children are correct.
3. Verify that invalid or unconfigured IDs appear in the skipped list.
4. Click **Launch Anonymization** and confirm.
5. Verify `TEKCO_AnonymizationAuditLog__c` was created with `BrandFilter LIKE 'BY_ID%'`.
6. Verify anonymized fields on direct records and CMDT-resolved children.
7. Switch back to the **By Criteria** tab and verify it still functions correctly (no regression).

### Monitoring Queries

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

#### Read the audit log

```sql
SELECT Name, TEKCO_Status__c, TEKCO_RecordsProcessed__c,
       TEKCO_RecordsFailed__c, TEKCO_BrandFilter__c,
       TEKCO_ObjectApiName__c, TEKCO_StartTime__c, TEKCO_EndTime__c,
       TEKCO_TriggeredBy__r.Name, TEKCO_ErrorMessage__c
FROM TEKCO_AnonymizationAuditLog__c
ORDER BY TEKCO_StartTime__c DESC
LIMIT 10
```

### Expected Batch Sizes

| Phase | Batch class | Batch size | Expected chunks for 100 000 records |
|---|---|---|---|
| Phase 1 — Fields | `TEKCO_AnonymizationBatch` / `TEKCO_AnonymizationByIdBatch` | 2 000 | 50 |
| Phase 2 — Files | `TEKCO_ContentDocumentBatch` / `TEKCO_ContentDocumentByIdBatch` | 500 | 200 |
| Phase 3 — History | `TEKCO_FieldHistoryBatch` / `TEKCO_FieldHistoryByIdBatch` | 2 000 | 50 |

### Test Checklist

#### Before launch

- [ ] Sandbox guard is active — confirm org is a sandbox (`IsSandbox = true` on the Organization record)
- [ ] Bypass settings are configured — `TEKCO_BypassSettings__c` custom setting exists
- [ ] Preview Scope returns correct counts for selected filters
- [ ] Fields to Anonymize table shows expected fields
- [ ] Org config record exists and is matched (if non-standard org) — check brand dropdown is populated correctly

#### During execution

- [ ] `AsyncApexJob` shows `TEKCO_AnonymizationBatch` (or `ByIdBatch`) with Status `Processing`
- [ ] `TotalJobItems` matches expected chunk count
- [ ] Status transitions from `Running` to `Success` / `Partial` in the audit log

#### After execution — Phase 1 (fields)

- [ ] Sample records show anonymized values (not original personal data)
- [ ] Record count in audit log matches expected volume
- [ ] No unexpected `Failed` records

#### After execution — Phase 2 (files)

- [ ] ContentDocuments linked to processed records are deleted
- [ ] Attachments (legacy files) are deleted
- [ ] `CombinedAttachment` view on a processed record is empty

#### After execution — Phase 3 (history)

- [ ] Field history for anonymized fields is empty
- [ ] Fields not marked `Del. History` still have their history

#### Regression

- [ ] Bypass settings restored to pre-run state
- [ ] Audit log status is `Success` or `Partial`
- [ ] Unselected brands are untouched — spot-check a record from a non-selected brand
- [ ] By Criteria tab works correctly after a By ID run (and vice versa)

#### If Phase 3 silently skips history deletion

Verify the **Delete Field History** permission is enabled (see [Section 1 — Prerequisites](#1-prerequisites)). If missing, history records are not deleted and no error is raised.
