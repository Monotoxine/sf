# Data Anonymization — User Guide

## Table of Contents

1. [Business Need](#1-business-need)
2. [Solution Overview](#2-solution-overview)
3. [Accessing the Interface](#3-accessing-the-interface)
4. [Understanding the Filters](#4-understanding-the-filters)
5. [Previewing the Scope](#5-previewing-the-scope)
6. [Reviewing the Fields to Process](#6-reviewing-the-fields-to-process)
7. [Launching Anonymization](#7-launching-anonymization)
8. [Monitoring Execution](#8-monitoring-execution)
9. [Deployment](#9-deployment)
10. [Prerequisites — Enabling Field History Deletion](#10-prerequisites--enabling-field-history-deletion)
11. [Configuring Anonymization Rules](#11-configuring-anonymization-rules)

---

## 1. Business Need

Organizations that use Salesforce to store personal data — such as patient records, customer contact details, social security numbers, or medical history — are subject to strict data protection regulations (GDPR and equivalent frameworks). These regulations require that personal data held in non-production environments (sandboxes, UAT, training orgs) be anonymized before the environment is made available to users who do not have a legitimate need to access real data.

Without a dedicated tool, anonymizing data in Salesforce is a manual, error-prone process that is difficult to audit, hard to repeat consistently across refreshes, and impossible to target by brand or population segment.

The specific challenges addressed by this tool are:

- **Volume**: production orgs can contain hundreds of thousands of personal records across multiple objects. Manual anonymization is not feasible at scale.
- **Repeatability**: every sandbox refresh restores production data. Anonymization must be repeatable and reliable each time.
- **Traceability**: data protection officers need evidence that anonymization was performed, by whom, and on what scope.
- **Flexibility**: different teams or brands may need to anonymize different populations. A one-size-fits-all approach creates either over-anonymization (data no longer useful for testing) or under-anonymization (residual risk).
- **Completeness**: personal data is not limited to standard fields. It may exist in field history, attached files, legacy notes, and custom fields — all of which must be covered.

---

## 2. Solution Overview

The anonymization tool is a fully configurable, metadata-driven solution built natively on Salesforce. It replaces or destroys personal data across multiple objects in a single, controlled operation, without requiring any code changes to add or modify anonymization rules.

**How it works:**

The solution is built on two layers:

- **A configuration layer** — two Custom Metadata types define which fields on which objects should be anonymized, using which algorithm. Administrators configure rules directly in Salesforce Setup with no deployment required.
- **An execution layer** — a Salesforce batch engine processes records in bulk, applying the configured rules, then automatically chaining four successive cleanup phases: field anonymization, file deletion, field history purge, and legacy attachment deletion.

**Key capabilities:**

| Capability | Description |
|---|---|
| Brand-level targeting | Anonymize only records belonging to selected brands, leaving other brands untouched. |
| Record Type filtering | Apply different anonymization rules per Record Type within the same object. |
| Per-run field exclusion | Temporarily exclude specific fields from a single run without modifying the configuration. |
| Scope preview | Count impacted records before launching, to validate the scope. |
| Full audit trail | Every execution is logged with its scope, status, record count, and triggering user. |
| No-code configuration | Adding or updating a rule requires only editing a Custom Metadata record in Setup — no Apex deployment. |
| Chained cleanup | Files, field history, and legacy attachments are automatically cleaned up after field anonymization, in sequence. |

---

## 3. Accessing the Interface

The tool is accessible from the **TEKCO Data Anonymization** tab in the Salesforce navigation bar.

> **Prerequisite**: you must hold the **TEKCO Anonymize Data** custom permission. If you see a red error banner at the top of the page, contact your Salesforce administrator to be granted this permission.

---

## 4. Understanding the Filters

The interface provides three filters to precisely target the scope of an anonymization run.

### Brands

Restricts processing to records belonging to specific brands.

- Move one or more brands from the **Available** column to the **Selected** column.
- The **Select All** button selects all available brands in one click.
- If no brand is selected, **all records** in the organization are included with no brand restriction.

> Brands correspond to the values of the `TEKCO_Brand__c` picklist field on configured objects. For objects that do not have this field but have a country field (`TEKCO_Country__c`), the system automatically derives the relevant country values from the selected brands.

### Objects

Selects which Salesforce objects will be processed.

- The list only shows objects for which anonymization rules have been defined.
- If no object is selected, **all configured objects** are processed.
- Selecting an object automatically refreshes the available Record Types list.

### Record Types

This filter only appears when the selected objects have configurations specific to certain Record Types.

- Leave this filter empty to process **all Record Types** of the object.
- Select one or more Record Types to restrict processing to those populations only.

---

## 5. Previewing the Scope

Before launching, it is strongly recommended to click the **Preview Scope** button.

This action does two things simultaneously:

1. **Counts the records** that will be impacted for each selected object, applying the brand and Record Type filters.
2. **Loads the list of fields** that will be anonymized, so you can review them before confirming.

Results appear as a summary table showing, per object, the number of records in scope.

> Objects whose only configured action is file deletion (ContentDocument) are visually distinguished with a dark badge.

---

## 6. Reviewing the Fields to Process

After previewing, the **Fields to Anonymize** table lists all fields that will be modified, grouped by object.

| Column | Description |
|---|---|
| **Run** | Checkbox — uncheck a field to **exclude it from this run only** (the rule itself is not deleted). |
| **Field** | API name of the Salesforce field that will be modified. |
| **Pattern** | Anonymization algorithm applied (see section 11 for the full pattern reference). |
| **Record Type** | Record Type targeted by this rule. Empty = all populations. |
| **Del. History** | If checked, the field change history will be deleted after anonymization. You can uncheck this to keep history for this run only. |
| **Description** | Functional description of the applied pattern. |

---

## 7. Launching Anonymization

Once the scope has been reviewed, click the red **Launch Anonymization** button.

A confirmation dialog opens and summarizes:

- The **brands** selected (or "ALL" if none selected)
- The **objects** that will be processed
- The **Record Types** in scope
- Any **excluded fields** for this run (rows unchecked at the previous step)
- Any **fields whose history will not be deleted** for this run

> **WARNING: this operation is irreversible.** Data will be permanently overwritten and cannot be restored from this tool.

Click **Confirm Launch** to start processing, or **Cancel** to return to the interface without making any changes.

---

## 8. Monitoring Execution

Processing runs in the background via Salesforce batch jobs. The interface refreshes automatically every 5 seconds as long as a run is in progress.

The **Recent Runs** table shows execution history with the following information:

| Column | Description |
|---|---|
| **Log #** | Unique identifier of the execution in the audit log. |
| **Object(s)** | Objects processed during this run. |
| **Brands** | Brand filter applied. |
| **Status** | Execution status: `Running`, `Success`, `Partial`, `Failed`. |
| **Processed** | Total number of records processed. |
| **Failed** | Number of records that encountered an error. |
| **By** | User who triggered the anonymization. |
| **Started** | Start date and time. |

The **↺** button at the top right of the table allows manual refresh.

### Processing Sequence

Anonymization runs in three successive automatic phases:

1. **Phase 1 — Field anonymization**: field values are updated according to configured patterns.
2. **Phase 2 — File deletion**: ContentDocuments linked to processed records are deleted (if configured).
3. **Phase 3 — History deletion**: field change history is purged for fields marked with Del. History.

Each phase starts automatically when the previous one completes.

---

## 9. Deployment

This section describes how to deploy the anonymization tool to a new Salesforce org (sandbox or production). Deployment is performed using the **Salesforce CLI** (`sf`) against the `anonymization` source directory.

> **Important**: the tool includes a sandbox guard that prevents it from running in production. Deploying the Apex classes to production is safe — the batch cannot be triggered outside a sandbox environment.

---

### 9.1 Components Deployed

The following metadata types are included in the deployment package:

| Type | Components |
|---|---|
| **Apex Classes** | `TEKCO_AnonymizationBatch`, `TEKCO_AnonymizationController`, `TEKCO_AnonymizationPatternService`, `TEKCO_AnonymizationAuditService`, `TEKCO_AnonymizationBypassService`, `TEKCO_AnonymizationSandboxGuard`, `TEKCO_ContentDocumentBatch`, `TEKCO_FieldHistoryBatch` |
| **Lightning Web Component** | `tekcoDataAnonymizationAdmin` |
| **Custom Metadata Types** | `TEKCO_AnonymizationPattern__mdt`, `TEKCO_AnonymizationFieldConfig__mdt`, `TEKCO_CountryBrandSetting__mdt` |
| **Custom Metadata Records** | All configured pattern and field rules |
| **Custom Object** | `TEKCO_AnonymizationAuditLog__c` (audit log) |
| **Custom Permission** | `TEKCO_AnonymizeData` |
| **Permission Set** | `TEKCO Anonymization Admin` |
| **Tab** | `TEKCO Data Anonymization` |

---

### 9.2 Deploying with Salesforce CLI

#### Full deployment

From the root of the repository, run:

```bash
sf project deploy start --source-dir anonymization/main/default --target-org <org-alias>
```

#### Selective deployment (individual components)

Deploy only the Apex classes:

```bash
sf project deploy start --source-dir anonymization/main/default/classes --target-org <org-alias>
```

Deploy only the LWC:

```bash
sf project deploy start --source-dir anonymization/main/default/lwc --target-org <org-alias>
```

Deploy only the custom metadata records (rules):

```bash
sf project deploy start --source-dir anonymization/main/default/customMetadata --target-org <org-alias>
```

---

### 9.3 Post-Deployment Steps

After the deployment completes, the following steps must be performed manually in the target org.

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

#### Step 3 — Enable field history deletion *(if Phase 3 is used)*

See [Section 10](#10-prerequisites--enabling-field-history-deletion) for the required org-level setting and permission set configuration.

#### Step 4 — Configure anonymization rules *(new org)*

If deploying to an org that does not yet have any rules configured:

1. Deploy or create `TEKCO_AnonymizationPattern__mdt` records (the algorithms).
2. Create `TEKCO_AnonymizationFieldConfig__mdt` records to define which fields on which objects to anonymize.

See [Section 11](#11-configuring-anonymization-rules) for the full configuration reference.

---

### 9.4 Verifying the Deployment

After completing the steps above:

1. Open the **TEKCO Data Anonymization** tab in the org.
2. Confirm the interface loads without errors.
3. Click **Preview Scope** — the system should return record counts without errors.
4. If the **"You need the TEKCO Anonymize Data custom permission"** banner appears, verify that the permission set is correctly assigned.

---

### 9.5 Sandbox Refresh Checklist

After each sandbox refresh, repeat the following steps:

- [ ] Redeploy the package (refresh restores the org from production, erasing previous deployments).
- [ ] Reassign the **TEKCO Anonymization Admin** permission set to relevant users.
- [ ] Re-enable the **Delete Field History** permission (Setup → User Interface, then Permission Set).
- [ ] Verify that the tab appears in the navigation app.
- [ ] Run a preview to confirm rules and record counts are as expected.

---

## 10. Prerequisites — Enabling Field History Deletion

Phase 3 (field history deletion) requires a Salesforce user permission that is **not enabled by default**. Without it, history records will silently not be deleted even if the **Del. History** checkbox is checked.

### Required one-time setup

**Step 1 — Enable the permission at org level**

1. Go to **Setup → User Interface**.
2. Check **Enable "Delete Field History" User Permission**.
3. Save.

**Step 2 — Grant the permission to the anonymization permission set**

1. Go to **Setup → Permission Sets → TEKCO Anonymization Admin**.
2. Click **System Permissions**.
3. Find **Delete Field History** and enable it.
4. Save.

> This setup must be performed once per org (or after each sandbox refresh). Without it, Phase 3 will be skipped silently.

---

## 11. Configuring Anonymization Rules

The tool's behavior is entirely driven by two Custom Metadata types, accessible from **Setup → Custom Metadata Types**.

---

### 9.1 Available Patterns — `TEKCO_AnonymizationPattern__mdt`

A pattern defines **how** a field value will be transformed. Available patterns:

| Developer Name | Behavior |
|---|---|
| `NAME_FIRST_LETTER` | Keeps only the first letter of the value, followed by the external ID, then `TEKCO_FunctionalId__c`, then the Salesforce Id as a last resort. e.g. `Jean Dupont` → `J0035g00000XyZAA` |
| `NAME_FIRST_LETTER_SFID` | Keeps the first letter followed by the Salesforce Id (forced — no fallback). e.g. `Jean` → `J0035g00000XyZAA` |
| `EMAIL_PLUS_EXTERNALID` | Generates an email with a `+` alias containing the external ID. e.g. `sf_sap+EXT001@airliquide.com` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Same as above with the sandbox org subdomain appended. e.g. `sf_sap+EXT001@airliquide.com.fr.mmedlej` |
| `EMAIL_PLUS_SFID` | Generates an email with a `+` alias containing the Salesforce Id. e.g. `sf_sap+0035g00000XyZAA@airliquide.com` |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | Same as above with the sandbox org subdomain appended. |
| `PHONE_MASK` | Masks the phone number while preserving its format. |
| `SSN_SEQUENTIAL` | Replaces the social security number with a unique sequential number. |
| `ADDRESS_STREET_RANDOM` | Replaces the street address with a randomly generated one. |
| `LOREM_IPSUM` | Replaces text content with Lorem Ipsum. |
| `CLEAR` | Empties the field (sets it to null if not already empty). |
| `DELETE_CONTENT_DOCUMENT` | Deletes all files (ContentDocuments) linked to the record. Handled in Phase 2. |
| `KEEP` | No change — keeps the original value as-is. |

#### Pattern configuration fields

| Field | Description |
|---|---|
| `TEKCO_Description__c` | Functional description displayed in the interface. |
| `TEKCO_IsActive__c` | Enabled / disabled. An inactive pattern cannot be used in a field rule. |
| `TEKCO_BaseEmail__c` | Base email address for `EMAIL_PLUS_*` patterns. e.g. `sf_sap@airliquide.com` |
| `TEKCO_ExternalIdField__c` | API name of the field used as an external identifier for `EMAIL_PLUS_EXTERNALID` and `NAME_FIRST_LETTER` patterns. |
| `TEKCO_SsnLength__c` | Length of the sequential number generated by the `SSN_SEQUENTIAL` pattern. |

---

### 9.2 Field Rules — `TEKCO_AnonymizationFieldConfig__mdt`

A field rule defines **which field** on **which object** will be anonymized using **which pattern**.

#### Required fields

| Field | Description |
|---|---|
| `TEKCO_ObjectApiName__c` | API name of the target Salesforce object. e.g. `Account`, `Contact`, `Case` |
| `TEKCO_FieldApiName__c` | API name of the field to anonymize. e.g. `FirstName`, `PersonEmail`, `ACCCO_Email__c` |
| `TEKCO_PatternType__c` | Developer Name of the pattern to apply. Must match an active `TEKCO_AnonymizationPattern__mdt` record. |
| `TEKCO_IsActive__c` | Must be checked for the rule to be picked up. |

#### Filtering fields

| Field | Description |
|---|---|
| `TEKCO_RecordTypeDeveloperName__c` | Restricts the rule to records of a specific Record Type. Leave empty to apply to all Record Types. |
| `TEKCO_AdditionalFilter__c` | Additional SOQL condition appended to the WHERE clause of the query. e.g. `ACCCO_RelatedAccount__r.RecordType.DeveloperName = 'ACCCO_Patient'` |

#### Child object fields

Use these when the field to anonymize is on a child object and filtering must go through a parent object.

| Field | Description |
|---|---|
| `TEKCO_ParentObjectApiName__c` | API name of the parent object. e.g. `Account` |
| `TEKCO_ParentLookupFieldApiName__c` | API name of the lookup field on the child object pointing to the parent. |
| `TEKCO_ParentRecordTypeDeveloperName__c` | Record Type of the parent object used as a filter. |

#### History behavior

| Field | Description |
|---|---|
| `TEKCO_DeleteHistory__c` | If checked, the field change history (`FieldHistory`) will be deleted after anonymization. Leave unchecked for fields where audit trail is not a concern. |

---

### 9.3 Adding a New Rule — Step by Step

1. Go to **Setup → Custom Metadata Types → TEKCO Anonymization Field Config → Manage Records**.
2. Click **New**.
3. Enter a meaningful **Label** (e.g. `Patient PersonEmail`) and a unique **Developer Name** (e.g. `Patient_PersonEmail`).
4. Fill in the required fields: object, field, pattern, and check `TEKCO_IsActive__c`.
5. Optional: fill in the Record Type if the rule applies to one population only.
6. Optional: check `TEKCO_DeleteHistory__c` if the field history should be purged.
7. Save.

The rule is immediately taken into account on the next run.

> **No code deployment is required** to add or modify an anonymization rule. Custom Metadata records can be edited directly in production.

---

### 9.4 Temporarily Disabling a Rule

To suspend a rule without deleting it, simply uncheck `TEKCO_IsActive__c` on the record. The rule will no longer appear in the interface and will not be processed.

---

### 9.5 Processing Order

Objects are processed in the order returned by the active rules. Within a single object, all configured fields are processed in a single batch pass — one record is updated in a single DML operation regardless of how many fields are configured for it.
