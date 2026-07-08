# Anonymization by Record ID — Deployment & Usage Guide

## Prerequisites

Before deploying, confirm the following are in place in the target org:

- Salesforce sandbox (anonymization is blocked on production orgs)
- `TEKCO_AnonymizationFieldConfig__mdt` records exist for the target objects
- For child resolution: `TEKCO_ParentObjectApiName__c` and `TEKCO_ParentLookupFieldApiName__c` are populated on child-object CMDT rows
- The operator has a profile or permission set where `TEKCO_AnonymizeData` custom permission can be assigned

---

## Deployment Checklist

### 1. Apex Classes

Deploy the four new classes and their `-meta.xml` files:

```
anonymization/main/default/classes/TEKCO_AnonymizationByIdController.cls
anonymization/main/default/classes/TEKCO_AnonymizationByIdBatch.cls
anonymization/main/default/classes/TEKCO_ContentDocumentByIdBatch.cls
anonymization/main/default/classes/TEKCO_FieldHistoryByIdBatch.cls
```

### 2. LWC

Deploy the updated component:

```
anonymization/main/default/lwc/tekcoDataAnonymizationAdmin/
```

### 3. Custom Metadata — New Fields

Deploy the two new fields on `TEKCO_AnonymizationPattern__mdt`:

```
anonymization/main/default/objects/TEKCO_AnonymizationPattern__mdt/fields/TEKCO_RegexFind__c.field-meta.xml
anonymization/main/default/objects/TEKCO_AnonymizationPattern__mdt/fields/TEKCO_RegexReplace__c.field-meta.xml
```

Deploy the new fields on `TEKCO_OrgConfig__mdt`:

```
anonymization/main/default/objects/TEKCO_OrgConfig__mdt/fields/TEKCO_ExternalIdFields__c.field-meta.xml
anonymization/main/default/objects/TEKCO_OrgConfig__mdt/fields/TEKCO_BrandObjectApiName__c.field-meta.xml
anonymization/main/default/objects/TEKCO_OrgConfig__mdt/fields/TEKCO_BrandCodeField__c.field-meta.xml
anonymization/main/default/objects/TEKCO_OrgConfig__mdt/fields/TEKCO_BrandCountryField__c.field-meta.xml
anonymization/main/default/objects/TEKCO_OrgConfig__mdt/fields/TEKCO_BrandLookupFieldOnRecord__c.field-meta.xml
```

### 4. Custom Metadata — OrgConfig Record

Create or update a `TEKCO_OrgConfig__mdt` record for the target org. Set `TEKCO_OrgDomain__c` to the org's domain prefix (e.g. `airliquide-pt--sandbox`).

The template record is at:

```
anonymization/main/default/customMetadata/TEKCO_OrgConfig.Portugal_ALH.md-meta.xml
```

Replace `REPLACE_WITH_PORTUGAL_ORG_DOMAIN` with the actual domain prefix before deploying.

### 5. Permissions

Assign the `TEKCO_AnonymizeData` custom permission to the operator's profile or permission set.

Via the `TEKCO_AnonymizationAdmin` permission set (already included in the package).

---

## Deploying with Salesforce CLI

Full package deploy (recommended for initial setup):

```bash
sf project deploy start \
  --manifest anonymization/manifest/package.xml \
  --target-org <your-org-alias>
```

Targeted deploy (incremental updates):

```bash
sf project deploy start \
  --source-dir anonymization/main/default/classes \
  --source-dir anonymization/main/default/lwc/tekcoDataAnonymizationAdmin \
  --target-org <your-org-alias>
```

---

## OrgConfig Setup

The `TEKCO_OrgConfig__mdt` record controls how the system behaves in a specific org. Fill in the fields relevant to your org:

| Field | Required | Notes |
|-------|----------|-------|
| `TEKCO_OrgDomain__c` | Yes | Domain prefix, e.g. `airliquide-pt--sandbox` |
| `TEKCO_FunctionalIdField__c` | Yes | e.g. `ALH_FunctionalId__c` or `TEKCO_FunctionalId__c` |
| `TEKCO_BypassEnabled__c` | Yes | Set to `true` to activate trigger bypass during anonymization |
| `TEKCO_BrandObjectApiName__c` | If brand is a lookup | e.g. `ALH_Brand__c`; leave blank if brand is a picklist on the record |
| `TEKCO_BrandCodeField__c` | If brand object set | Field on brand object holding the brand code (e.g. `Name`) |
| `TEKCO_BrandCountryField__c` | If brand object set | Field on brand object holding the country (e.g. `ALH_Country__c`) |
| `TEKCO_BrandLookupFieldOnRecord__c` | If brand object set | Relationship field on anonymized records pointing to the brand (e.g. `ALH_Brand__r`) |
| `TEKCO_ExternalIdFields__c` | Optional | Comma-separated external ID fields shown in the By ID tab dropdown |

If no `TEKCO_OrgConfig__mdt` record matches the current org, the system falls back to the TEKCO/Air Liquide default config automatically.

---

## Configuring REGEX Patterns

To add a new field transformation without touching Apex, create a `TEKCO_AnonymizationPattern__mdt` record with `TEKCO_PatternType__c = REGEX` and fill in the two new fields:

| Field | Value |
|-------|-------|
| `TEKCO_RegexFind__c` | The regex to match (blank = replace entire value) |
| `TEKCO_RegexReplace__c` | The replacement string (supports `$1`, `$2` groups) |

Then reference the pattern in a `TEKCO_AnonymizationFieldConfig__mdt` record as usual.

### Common patterns

| Transformation | RegexFind | RegexReplace |
|----------------|-----------|--------------|
| Replace all digits with 0 | `\d` | `0` |
| Fixed value | *(blank)* | `ANONYMIZED` |
| Mask phone after first 4 digits | `(?<=^.{4})[\s\S]` | `0` |
| Mask email local part | `[^@]+@` | `anon@` |
| Clear field | `[\s\S]*` | *(blank)* |
| Lorem ipsum replacement | *(blank)* | `Lorem ipsum dolor sit amet…` |

---

## Using the By ID Tab

### Step 1 — Open the component

Navigate to the **TEKCO Data Anonymization** custom tab, then click the **By ID (DataMig)** tab.

### Step 2 — Select the target object

Choose the SObject type from the **Target object** dropdown. Only objects that have active `TEKCO_AnonymizationFieldConfig__mdt` records appear.

### Step 3 — Paste IDs

Paste Salesforce record IDs into the textarea. Accepted formats:

- One ID per line
- Comma-separated
- Semicolon-separated
- Mixed types (Account IDs and Contact IDs together)

The component counts detected IDs in real time.

### Step 4 — Preview scope

Click **Preview Scope**. The system resolves:

- **Direct objects**: IDs you provided whose SObject type is configured in CMDT
- **Resolved children**: objects discovered via CMDT parent-child relationships (e.g. Contacts linked to provided Account IDs)
- **Skipped IDs**: IDs that could not be parsed or whose SObject type has no CMDT configuration

Review the scope before proceeding. No data is modified at this step.

### Step 5 — Configure fields

In the **Fields to Anonymize** table, review which fields will be anonymized and whether field history will be deleted. Use the **Select All / Deselect All** buttons for both **Run** and **Del. History** columns to adjust in bulk.

Only fields whose `originalDeleteHistory` is `true` (as configured in CMDT) can be re-selected after a Deselect All on history.

### Step 6 — Launch

Click **Launch Anonymization**. A confirmation modal displays the scope summary. Confirm to start the batch.

An audit log entry is created immediately with status `Running` and `TEKCO_BrandFilter__c = 'BY_ID (N record(s))'`. The table auto-refreshes every 5 seconds until the run completes.

---

## Monitoring Runs

The **Recent Runs** table in the By ID tab shows only By ID runs (filtered by `TEKCO_BrandFilter__c LIKE 'BY_ID%'`). The By Criteria tab's audit log is unaffected.

| Status | Meaning |
|--------|---------|
| `Running` | Batch is in progress; table refreshes automatically |
| `Success` | All phases completed without errors |
| `Error` | One or more errors occurred; check the `TEKCO_Errors__c` field on the log record |

---

## Testing Checklist

### Resolve step

- [ ] Provide 2 Account IDs + 1 Contact ID → Preview Scope shows Account (2, direct), Contact (1, direct), plus any children resolved via CMDT
- [ ] Provide an ID from an unconfigured object → it appears in the skipped list
- [ ] Provide a malformed string → it appears in the skipped list

### Full anonymization

- [ ] Launch anonymization → `TEKCO_AnonymizationAuditLog__c` created with `BrandFilter LIKE 'BY_ID%'`
- [ ] Status transitions to `Success`
- [ ] Anonymized fields are updated on direct records and CMDT-resolved children
- [ ] ContentDocuments deleted if `DELETE_CONTENT_DOCUMENT` pattern is configured for those objects
- [ ] Field history deleted if `TEKCO_DeleteHistory__c = true` in CMDT
- [ ] Trigger bypass was active during anonymization and restored after

### No regression

- [ ] Switch to "By Criteria" tab after a By ID run → works exactly as before
- [ ] A By Criteria run does not appear in the By ID audit log, and vice versa

### REGEX pattern

- [ ] Partial replacement (`RegexFind = \d`, `RegexReplace = 0`) → only digits replaced
- [ ] Total replacement (blank `RegexFind`, `RegexReplace = ANONYMIZED`) → entire field value replaced
- [ ] Invalid regex → field value unchanged, batch does not error

---

## Troubleshooting

**Preview Scope returns no records**
- Verify `TEKCO_AnonymizationFieldConfig__mdt` has active records for the SObject type you selected.
- Check that `TEKCO_ParentObjectApiName__c` and `TEKCO_ParentLookupFieldApiName__c` are populated for child objects.

**"Sandbox only" error on launch**
- Anonymization is blocked on production orgs by design. Use a sandbox.

**"Insufficient permissions" error**
- Assign the `TEKCO_AnonymizeData` custom permission to the operator's profile or permission set.

**Audit log stuck on `Running`**
- Check Apex Jobs (Setup → Apex Jobs) for the batch status. If the job failed silently, the audit log record's `TEKCO_Errors__c` field will contain details after the next batch `finish()` call.

**Children not resolved**
- Verify `TEKCO_ParentObjectApiName__c` on the child's CMDT row matches the exact API name of the parent SObject you provided IDs for.
- Verify `TEKCO_ParentLookupFieldApiName__c` is the API name of the lookup field on the child (e.g. `AccountId`, not `Account`).

**OrgConfig not picked up**
- Confirm `TEKCO_OrgDomain__c` on the CMDT record matches exactly the subdomain returned by `URL.getOrgDomainUrl().getHost().substringBefore('.')`. You can check this value in Execute Anonymous: `System.debug(URL.getOrgDomainUrl().getHost().substringBefore('.'));`
