# Data Anonymization — Deployment and Usage

---

## 1.1 Prerequisites

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

## 1.2 Deploying the Package

Deployment is performed using the Salesforce CLI (`sf`) with the `package.xml` manifest located at `anonymization/manifest/package.xml`.

### What the package contains

| Metadata type | Components included |
|---|---|
| **ApexClass** | `TEKCO_AnonymizationBatch`, `TEKCO_AnonymizationController`, `TEKCO_AnonymizationPatternService`, `TEKCO_AnonymizationExecuteService`, `TEKCO_AnonymizationBatchUtils`, `TEKCO_AnonymizationAuditService`, `TEKCO_AnonymizationBypassService`, `TEKCO_ContentDocumentBatch`, `TEKCO_FieldHistoryBatch`, `TEKCO_AnonymizationByIdBatch`, `TEKCO_ContentDocumentByIdBatch`, `TEKCO_FieldHistoryByIdBatch`, `TEKCO_AnonymizationByIdController`, `TEKCO_AnonymizationOrgConfigService` |
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

## 1.3 Post-Deployment Steps

### Step 1 — Assign the permission set

Grant the **TEKCO Anonymization Admin** permission set to every user who needs access to the tool.

1. Go to **Setup → Users**.
2. Open the target user.
3. In the **Permission Set Assignments** section, click **Edit Assignments**.
4. Add **TEKCO Anonymization Admin** and save.

### Step 2 — Add the tab to the navigation app

1. Go to **Setup → App Manager**.
2. Edit the Lightning app where the tool should appear (e.g. **Run Teams Tools**).
3. Under **Navigation Items**, add the **TEKCO Data Anonymization** tab.
4. Save.

---

## 1.4 Sandbox Refresh Checklist

After each sandbox refresh, the org reverts to production state. Repeat the following:

- [ ] Redeploy the package: `sf project deploy start --manifest anonymization/manifest/package.xml --target-org <org-alias>`
- [ ] Reassign the **TEKCO Anonymization Admin** permission set to relevant users.
- [ ] Re-enable **Delete Field History** at org level (Setup → User Interface) and on the permission set.
- [ ] Verify the tab appears in the navigation app.
- [ ] Run a preview to confirm rules and record counts are as expected before launching.

---

## 1.5 Accessing the Interface

The tool is accessible from the **TEKCO Data Anonymization** tab in the Salesforce navigation bar.

> **Prerequisite:** you must hold the **TEKCO Anonymize Data** custom permission. If you see a red error banner at the top of the page, contact your Salesforce administrator to be granted this permission via the **TEKCO Anonymization Admin** permission set.

The interface is divided into two tabs:
- **By Criteria** — standard anonymization by brand, object, and record type
- **By ID (DataMig)** — targeted anonymization by explicit record ID list

---

## 1.6 Understanding the Filters

*This section applies to the **By Criteria** tab.*

### Brands

Restricts processing to records belonging to specific brands.

- Move one or more brands from the **Available** column to the **Selected** column.
- The **Select All** button selects all available brands in one click.
- If no brand is selected, **all records** are included with no brand restriction.

> For objects that do not have a `TEKCO_Brand__c` field but have `TEKCO_Country__c`, the system automatically derives the relevant country values from the selected brands using the `TEKCO_CountryBrandSetting__mdt` mapping (standard orgs) or directly from the brand object (orgs configured with `TEKCO_BrandObjectApiName__c`).

### Objects

Selects which Salesforce objects will be processed.

- The list only shows objects for which anonymization rules have been defined.
- If no object is selected, **all configured objects** are processed.
- Selecting an object automatically refreshes the available Record Types list.

### Record Types

This filter only appears when the selected objects have configurations specific to certain Record Types.

- Leave this filter empty to process **all Record Types**.
- Select one or more Record Types to restrict processing to those populations only.

---

## 1.7 Previewing the Scope

*This section applies to the **By Criteria** tab.*

Before launching, click the **Preview Scope** button.

This action does two things simultaneously:

1. **Counts the records** that will be impacted for each selected object, applying the brand and Record Type filters.
2. **Loads the list of fields** that will be anonymized, so you can review them before confirming.

Results appear as a summary table showing, per object, the number of records in scope.

> Objects whose only configured action is file deletion (ContentDocument) are visually distinguished with a dark badge. Their record count reflects parent records that have linked files — not the number of files themselves.

---

## 1.8 Reviewing the Fields to Process

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

## 1.9 Launching Anonymization

*This section applies to the **By Criteria** tab.*

Once the scope has been reviewed, click the red **Launch Anonymization** button.

A confirmation dialog opens and summarizes the brands, objects, Record Types, excluded fields, and fields whose history will not be deleted.

> **WARNING: this operation is irreversible.** Data will be permanently overwritten and cannot be restored from this tool.

Click **Confirm Launch** to start processing, or **Cancel** to return without making any changes.

> **Automation bypass**: immediately before the first batch job starts, the tool sets every boolean flag on the `TEKCO_BypassSettings__c` Hierarchy Custom Setting to `true` for the running user. This suppresses all triggers and automation rules for the duration of the entire processing chain. Once the last phase completes — whether successfully or with an error — the original flag values are restored exactly as they were before the run.

---

## 1.10 Monitoring Execution

Processing runs in the background via Salesforce batch jobs. The interface refreshes automatically every 5 seconds as long as a run is in progress. Click the **↺** button to force a manual refresh.

The **Recent Runs** table shows execution history. In the By Criteria tab, only By Criteria runs are shown. In the By ID tab, only By ID runs are shown (filtered by `TEKCO_BrandFilter__c LIKE 'BY_ID%'`).

| Column | Description |
|---|---|
| **Log #** | Unique identifier of the execution in the audit log. |
| **Object(s)** | Objects processed during this run. |
| **Brands** | Brand filter applied (or `BY_ID (N record(s))` for By ID runs). |
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

### ⚠️ Aborting a run — you must restore the bypass settings by hand

**Read this before aborting a job from Setup → Apex Jobs.**

When you click **Launch Anonymization**, the tool switches **every** bypass checkbox on the `TEKCO_BypassSettings__c` hierarchy custom setting to `true` for **the user who launched the run**. This is deliberate: validation rules, triggers and flows would otherwise block the anonymization DML. The original values are captured first and put back automatically when the batch chain finishes — successfully or with errors.

**That automatic restore only happens in the batch's `finish()` method.** If you abort the job from **Setup → Apex Jobs → Abort**, `finish()` never runs, so **the bypass flags stay switched on indefinitely**.

**Why this matters:** the flags are scoped to your user, not to the batch. Until you clear them, *every* subsequent action you take in that sandbox — manual record edits, data loads, other tooling — runs with all automation bypassed. Nothing warns you, and the effect persists across sessions.

**To restore them after an abort:**

1. Go to **Setup → Custom Settings → TEKCO Bypass Settings → Manage**.
2. Find the record whose owner is **your user**.
3. Either uncheck every checkbox to match what it was before the run, or **delete the user-level record** entirely if you did not have one before — the hierarchy then falls back to the org default.
4. Confirm by editing any record that should fire a trigger, and check that it does.

**When this does not apply:** if the org's `TEKCO_AnonymizationOrgConfig__mdt` record has `TEKCO_BypassEnabled__c = false` (currently the case for the Portugal / ALH org), the tool never touches the bypass settings at all, and aborting has no side effect on them. See section 1.14 for the per-org configuration.

**Preferred alternative to aborting:** let the chain finish. Anonymization is idempotent — Phase 1 only writes a field when the anonymized value differs from the current one — so a run that completes with errors is safe, and re-launching afterwards processes only what remains. Abort only when you genuinely need to stop immediately, and clear the flags straight afterwards.

---

## 1.11 Configuring Anonymization Rules

The tool's behavior is entirely driven by two Custom Metadata types, accessible from **Setup → Custom Metadata Types**.

### Available Patterns — `TEKCO_AnonymizationPattern__mdt`

| Developer Name | Behavior |
|---|---|
| `NAME_FIRST_LETTER` | Keeps only the first letter, followed by: external ID → functional ID field → Salesforce Id (fallback chain). e.g. `Jean Dupont` → `J0035g00000XyZAA` |
| `NAME_FIRST_LETTER_SFID` | First letter followed by Salesforce Id (forced). e.g. `Jean` → `J0035g00000XyZAA` |
| `EMAIL_PLUS_EXTERNALID` | Email with a `+` alias containing the external ID. e.g. `sf_sap+EXT001@airliquide.com` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Same with the sandbox subdomain appended. |
| `EMAIL_PLUS_SFID` | Email with a `+` alias containing the Salesforce Id. |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | Same with the sandbox subdomain appended. |
| `SSN_SEQUENTIAL` | Replaces with a sequential digit string of the same length. Equivalent REGEX: `RegexFind = \d`, `RegexReplace = 0`. |
| `ADDRESS_STREET_RANDOM` | Finds the first number in the address and adds a random offset (1–20). |
| `PHONE_MASK` | Keeps the first 4 characters and replaces the rest with `0`. Equivalent REGEX: `RegexFind = (?<=^.{4})[\s\S]`, `RegexReplace = 0`. |
| `LOREM_IPSUM` | Replaces the entire value with Lorem Ipsum text. Equivalent REGEX: blank `RegexFind`, `RegexReplace = Lorem ipsum…`. |
| `CLEAR` | Sets the field to empty. Equivalent REGEX: `RegexFind = [\s\S]*`, blank `RegexReplace`. |
| `REGEX` | Configurable find/replace using `TEKCO_RegexFind__c` and `TEKCO_RegexReplace__c`. Replaces `PHONE_MASK`, `LOREM_IPSUM`, and `CLEAR` as the recommended approach for new transformations. |
| `DELETE_CONTENT_DOCUMENT` | Deletes all files linked to the record. Handled in Phase 2. No field change in Phase 1. |
| `EMAIL_MESSAGE_LOREM` | For EmailMessage: Draft records get Lorem Ipsum body; non-Draft records are deleted entirely. |
| `KEEP` | No-op — keeps the original value. |

**Pattern configuration fields:**

| Field | Description |
|---|---|
| `TEKCO_Description__c` | Functional description displayed in the interface. |
| `TEKCO_IsActive__c` | Must be checked for the pattern to be usable. |
| `TEKCO_BaseEmail__c` | Base email address for `EMAIL_PLUS_*` patterns. e.g. `sf_sap@airliquide.com` |
| `TEKCO_ExternalIdField__c` | API name of the field used as external identifier. |
| `TEKCO_SsnLength__c` | Target length for `SSN_SEQUENTIAL` (fallback if the original value is blank). |
| `TEKCO_RegexFind__c` | Regular expression to match (for `REGEX` type). Blank = full replacement. |
| `TEKCO_RegexReplace__c` | Replacement string (for `REGEX` type). Supports capture groups `$1`, `$2`. |

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
| `TEKCO_ParentObjectApiName__c` | API name of the parent object. Used in By Criteria mode as a filter, and in By ID mode to discover child records. |
| `TEKCO_ParentLookupFieldApiName__c` | API name of the lookup field on the child object pointing to the parent (e.g. `AccountId`). |
| `TEKCO_ParentRecordTypeDeveloperName__c` | Record Type of the parent used as a filter (By Criteria mode only). |

**History behavior:**

| Field | Description |
|---|---|
| `TEKCO_DeleteHistory__c` | If checked, field change history will be deleted in Phase 3. |

### Adding a new rule — step by step

1. Go to **Setup → Custom Metadata Types → TEKCO Anonymization Field Config → Manage Records**.
2. Click **New**.
3. Enter a meaningful **Label** (e.g. `Patient PersonEmail`) and a unique **Developer Name** (e.g. `Patient_PersonEmail`).
4. Fill in the required fields: object, field, pattern type, and check `TEKCO_IsActive__c`.
5. Optional: fill in the Record Type if the rule applies to one population only.
6. Optional: check `TEKCO_DeleteHistory__c` if the field history should be purged.
7. Save.

> **No code deployment is required** to add or modify an anonymization rule.

### Temporarily disabling a rule

Uncheck `TEKCO_IsActive__c`. The rule disappears from the interface and is not processed until re-enabled.

### Processing order

When multiple rules apply to the same field (different Record Types), they are processed independently, one per batch execution. The batch size is **200 records per chunk** for Phase 1 (intentionally conservative — see section 1.12 for the heap size rationale).

---

## 1.12 Known Limitations

### Heap size and stateful serialization — why CMDT configs are not kept in batch state

**Context**: The batch chain (`TEKCO_AnonymizationBatch` → `TEKCO_ContentDocumentBatch` → `TEKCO_FieldHistoryBatch`) uses `Database.Stateful`, which means Salesforce serializes the entire batch instance — all instance variables — between every `execute()` chunk. This serialized payload counts against two separate platform limits: the **12 MB async heap limit** (memory consumed when deserializing state at the start of each chunk) and the **"Batchable instance is too big"** limit (the serialized byte size itself, evaluated after each chunk completes).

**Why CMDT SObjects cannot be kept as stateful fields**: Each `TEKCO_AnonymizationFieldConfig__mdt` or `TEKCO_AnonymizationPattern__mdt` object is a full Salesforce SObject carrying many fields. Lists of 50+ such records, multiplied by the number of phases that need them (`fieldConfigs`, `contentDocConfigs`, `historyConfigs`), produce a serialized batch state that is large enough to trigger the "Batchable instance is too big" `LimitException` mid-run — even before any data errors accumulate. When this happens, the batch aborts at the current chunk, remaining records are not processed, and the chain (Phase 2, Phase 3) never runs.

**The design choice**: CMDT records (Custom Metadata Types) are cached by the Salesforce platform and re-queried at near-zero cost within the same transaction context. The batch classes therefore store only the `DeveloperName` strings of the relevant configs as stateful fields — a handful of short strings — and re-query the full CMDT objects locally in `execute()` and `finish()` only when needed. This eliminates the serialization overhead entirely while keeping the same filtering logic.

**Impact on behavior**: None. The CMDT data returned by a re-query within the same batch run is identical to what would have been deserialized from state. Chaining, filtering, and error handling are unchanged.

**Applies to both chains**: the same pattern is used in the By Criteria chain (`TEKCO_AnonymizationBatch` → `TEKCO_ContentDocumentBatch` → `TEKCO_FieldHistoryBatch`) and the By ID chain (`TEKCO_AnonymizationByIdBatch` → `TEKCO_ContentDocumentByIdBatch` → `TEKCO_FieldHistoryByIdBatch`). Constructors still accept full `List<TEKCO_AnonymizationFieldConfig__mdt>` parameters and convert to DeveloperNames on entry, so callers are unaffected. Error strings are likewise truncated via `TEKCO_AnonymizationBatchUtils.cap()` and the accumulated error list is capped at `TEKCO_AnonymizationBatch.MAX_ACCUMULATED_ERRORS` in both chains. Keep the two chains symmetric when modifying either.

**Resuming after a heap abort**: The anonymization is **idempotent** — Phase 1 only updates a record when the anonymized value differs from the current value. If a batch aborts mid-way, re-launching with the same parameters is safe: records already anonymized are detected and skipped automatically. Only the remaining records are processed.

### Aborting a job leaves the bypass flags enabled

The bypass settings are restored in the batch's `finish()` method. Aborting from **Setup → Apex Jobs** skips `finish()`, so all bypass checkboxes remain `true` for the launching user until cleared by hand — meaning that user's later work in the sandbox also runs with automation bypassed. Full instructions in section 1.10, *Aborting a run*.

The same applies to any failure severe enough that `finish()` never executes at all. Failures the batch handles internally do restore the flags — both the terminal branch and the chain-error handler call `restore()`.

### ADDRESS_STREET_RANDOM — values with no valid street number

If the field contains only a very large number (e.g. a phone number incorrectly stored in an address field), the pattern returns the value unchanged rather than raising an error. This is logged as a normal record with no modification.

### Asset Files cannot be deleted (Phase 2)

**Error message**: `We can't delete this file because it's an asset file being referenced by one or more objects. To delete it, first remove all references to it.`

**When it occurs**: During Phase 2 (ContentDocument deletion), when a file linked to a target record is flagged as an Asset File by Salesforce (`ContentVersion.IsAsset = true`).

**Why it cannot be bypassed**: Salesforce enforces this restriction at the platform level, regardless of user permissions or the `allOrNothing` DML setting.

**Current behavior**: The file is counted as a failed record and the error message is written to the audit log's error column. The rest of the batch continues normally.

**What to do**: Identify the asset file via the error in the audit log, then either remove its asset references manually (Setup → CMS or Experience Cloud assets) before re-running, or accept that these specific files will not be deleted.

---

## 1.13 Using the By ID (DataMig) Tab

The **By ID (DataMig)** tab is designed for scenarios where specific records must be anonymized by providing their Salesforce IDs directly, without using a brand filter. It is the recommended approach after a data migration.

### Step 1 — Select the target object

Choose the SObject type from the **Target object** dropdown. Only objects that have active `TEKCO_AnonymizationFieldConfig__mdt` records appear. Labels show the SObject API name without any parent suffix.

### Step 2 — Paste IDs

In the **Record IDs** textarea, paste the Salesforce IDs of the records to anonymize. Accepted formats:
- One ID per line
- Comma-separated
- Semicolon-separated
- Mixed (IDs from different SObject types can be pasted together)

The component displays a real-time count of detected IDs as you type.

### Step 3 — Preview Scope

Click **Preview Scope** to resolve the full scope without starting any batch.

The system:
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

### Step 4 — Review fields

The **Fields to Anonymize** table works identically to the By Criteria tab (see section 1.8).

Use **Run: Select All / Deselect All** and **Del. History: Select All / Deselect All** to adjust in bulk. **Del. History: Select All** only restores history deletion for fields originally configured with `TEKCO_DeleteHistory__c = true` — it does not enable history deletion for fields that were not configured for it.

### Step 5 — Launch

Click **Launch Anonymization** (disabled until at least one valid ID is resolved). A confirmation modal displays the resolved scope summary.

Click **Confirm Launch** to start. An audit log entry is created immediately with `TEKCO_BrandFilter__c = 'BY_ID (N record(s))'`.

The same automation bypass and production guard as the By Criteria tab apply.

### Monitoring

The **Recent Runs** table in the By ID tab shows only By ID runs, filtered by `TEKCO_BrandFilter__c LIKE 'BY_ID%'`. It auto-refreshes every 5 seconds while a run is in progress. Columns and status meanings are identical to section 1.10.

---

## 1.14 Configuring a New Org (Multi-Org Setup)

Use this section when deploying the tool in an org that does not follow the standard TEKCO naming convention — for example, an org where the brand is stored as a lookup object rather than a picklist field, or where field names differ.

### Step 1 — Identify the org domain prefix

Run the following in **Developer Console → Execute Anonymous**:

```apex
System.debug(URL.getOrgDomainUrl().getHost().substringBefore('.'));
```

Note the returned value — this is what you will set in `TEKCO_OrgDomain__c`.

### Step 2 — Create the CMDT record

1. Go to **Setup → Custom Metadata Types → TEKCO Anonymization Org Config → Manage Records**.
2. Click **New**.
3. Enter a **Label** (e.g. `Portugal ALH`) and **Developer Name** (e.g. `Portugal_ALH`).
4. Fill in the fields according to your org's configuration (see reference table below).
5. Save.

Alternatively, create a `.md-meta.xml` file in `anonymization/main/default/customMetadata/` and deploy it:

```bash
sf project deploy start \
  --source-dir anonymization/main/default/customMetadata \
  --target-org <org-alias>
```

### Field reference

| Field | Required | Notes |
|-------|----------|-------|
| `TEKCO_OrgDomain__c` | Yes | Domain prefix from Step 1. e.g. `airliquide-pt--sandbox` |
| `TEKCO_FunctionalIdField__c` | Yes | API name of the functional ID field. e.g. `ALH_FunctionalId__c` |
| `TEKCO_BypassEnabled__c` | Yes | Set to `true` if `TEKCO_BypassSettings__c` is deployed and configured in this org |
| `TEKCO_BrandObjectApiName__c` | If brand is a lookup | API name of the brand SObject (e.g. `ALH_Brand__c`). Leave blank to use picklist mode |
| `TEKCO_BrandCodeField__c` | If brand object set | Field on the brand object holding the brand code label (e.g. `Name`) |
| `TEKCO_BrandCountryField__c` | If brand object set | Field on the brand object holding the country value (e.g. `ALH_Country__c`) |
| `TEKCO_BrandLookupFieldOnRecord__c` | If brand object set | Relationship field on anonymized records pointing to the brand object (e.g. `ALH_Brand__r`) |
| `TEKCO_ExternalIdFields__c` | Optional | Comma-separated external ID fields shown in the By ID tab. e.g. `ALH_ExternalSystemID__c` |

### Step 3 — Verify

1. Open the **TEKCO Data Anonymization** tab.
2. In the **By Criteria** tab, verify that the brand dropdown shows the correct brands from the brand object (or picklist, depending on the mode).
3. In the **By ID** tab, verify that the external ID selector shows the expected fields.
4. Run a **Preview Scope** with a small set of IDs to confirm resolution logic is correct.

### Troubleshooting

**Org config not picked up:**
Confirm that `TEKCO_OrgDomain__c` matches exactly the value returned by `URL.getOrgDomainUrl().getHost().substringBefore('.')`. Even a single character difference causes the tool to fall back to default config.

**Brand dropdown is empty in brand object mode:**
Verify that `TEKCO_BrandObjectApiName__c`, `TEKCO_BrandCodeField__c`, and `TEKCO_BrandCountryField__c` are all set and that the running user has read access to the brand SObject.

**Children not resolved in By ID mode:**
Verify that `TEKCO_ParentObjectApiName__c` on the child's CMDT row matches the exact API name of the parent SObject, and that `TEKCO_ParentLookupFieldApiName__c` is the API name of the lookup field (e.g. `AccountId`, not `Account`).

---

## 1.15 Additional Deployment — Portugal (ALH) Org Only

> **This section applies exclusively to the Portugal (ALH) org.** Skip it for all other orgs.

The Portugal org uses a non-standard naming convention (brand as a lookup object, custom functional ID field) that requires a dedicated org configuration record. This is deployed separately from the main package using a targeted manifest.

### Step 1 — Find the org domain prefix

Run the following in **Developer Console → Execute Anonymous** on the Portugal org:

```apex
System.debug(URL.getOrgDomainUrl().getHost().substringBefore('.'));
```

Note the returned value (e.g. `airliquide-pt--sandbox`).

### Step 2 — Update the CMDT record file

Open the file:

```
anonymization/main/default/customMetadata/TEKCO_AnonymizationOrgConfig.Portugal_ALH.md-meta.xml
```

Replace the placeholder value:

```xml
<!-- Before -->
<value>REPLACE_WITH_PORTUGAL_ORG_DOMAIN</value>

<!-- After -->
<value>airliquide-pt--sandbox</value>  <!-- use the value from Step 1 -->
```

### Step 3 — Deploy the Portugal-specific package

After the main package has been deployed (section 1.2), run:

```bash
sf project deploy start --manifest anonymization/manifest/package-portugal-alh.xml --target-org <portugal-org-alias>
```

This package deploys only:
- The `TEKCO_AnonymizationOrgConfig__mdt` Custom Metadata Type and its 8 fields
- The `Portugal_ALH` configuration record

> **Do not deploy this package to other orgs.** It is scoped to Portugal and will have no effect on orgs that do not match the configured domain, but it is not necessary elsewhere.

### What this configures

| Setting | Value |
|---------|-------|
| Org domain match | Value from Step 1 |
| Functional ID field | `ALH_FunctionalId__c` |
| Automation bypass | Disabled (`false`) — `TEKCO_BypassSettings__c` is not used in this org |
| Brand mode | Object-based — brands are records of `ALH_Brand__c` |
| Brand code field | `Name` |
| Brand country field | `ALH_Country__c` |
| Brand lookup on record | `ALH_Brand__r` |
| External ID fields (By ID tab) | `ALH_ExternalSystemID__c` |

### Step 4 — Verify

1. Open the **TEKCO Data Anonymization** tab in the Portugal org.
2. Confirm the **Brands** list in the By Criteria tab shows brands from `ALH_Brand__c`.
3. Confirm the external ID selector in the By ID tab shows `ALH_ExternalSystemID__c`.
4. Run a **Preview Scope** with a known record ID to confirm scope resolution is correct.
