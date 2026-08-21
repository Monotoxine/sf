# Data Anonymization — Deployment and Usage

Standard TEKCO org. For an org that departs from the TEKCO schema conventions, read
[`DEPLOYMENT_NON_STANDARD_ORG.md`](DEPLOYMENT_NON_STANDARD_ORG.md) instead of sections 1
to 5 below. For how the tool is built, see
[`SOLUTION_AND_ARCHITECTURE.md`](SOLUTION_AND_ARCHITECTURE.md).

---

## At a glance

| # | Step | Frequency |
|---|---|---|
| **1** | [Prerequisites](#1-prerequisites) | Once, re-checked after each refresh |
| **2** | [Deploy the package](#2-deploying-the-package) | Each deployment |
| **3** | [Post-deployment steps](#3-post-deployment-steps) | Each deployment |
| **4** | [Sandbox refresh checklist](#4-sandbox-refresh-checklist) | After every refresh |
| **5** | [Access the interface](#5-accessing-the-interface) | Each deployment |

Sections 6 onwards are the working guide: checking the configuration, previewing, launching,
monitoring, scheduling, configuring rules, and the By ID tab.

---

# Part 1 — Deployment

## 1. Prerequisites

### The org must be a sandbox

Every entry point calls `TEKCO_AnonymizationOrgConfigService.assertIsSandbox()`, and every
batch re-checks it at `start()`. Deploying to production is harmless — nothing can be
launched there.

### Enable Field History Deletion

Deleting field history requires a Salesforce permission that is **not enabled by default**.
Without it, history records are silently left in place even where `TEKCO_DeleteHistory__c`
is checked.

1. **Setup → User Interface** → check **Enable "Delete Field History" User Permission** → Save.
2. **Setup → Permission Sets → TEKCO Anonymization Admin → System Permissions** → enable
   **Delete Field History** → Save.

> Both steps must be repeated after each sandbox refresh.

### The org must have free data storage

A run begins by inserting an audit log record. At 100% data storage that insert fails with
`STORAGE_LIMIT_EXCEEDED`; the launch service restores the bypass and rethrows, so the run
never starts. Free space with a Bulk API **hard delete** — an ordinary delete frees nothing
until the recycle bin is emptied. Anonymization cannot free storage itself: it performs
updates, not deletes.

### No run may be in flight during a deployment

A chained run holds a serialized `Database.Stateful` instance. Deploying over — or deleting —
a class that instance points at kills the run mid-chain, with the bypass left raised and the
audit log stuck on `Running`. Check first:

```apex
SELECT Id, Status, ApexClass.Name, CreatedDate FROM AsyncApexJob
WHERE Status IN ('Queued','Processing','Preparing','Holding') AND ApexClass.Name LIKE 'TEKCO_%'
```

---

## 2. Deploying the package

There are two manifests, and which one you need depends on what the org already has.

### 2.1 Full deployment — a new org, or one being brought up to date

```bash
sf project deploy start --manifest anonymization/manifest/package.xml --target-org <alias>
```

`package.xml` is the source of truth for what the package contains — 35 Apex classes
(20 production, 15 test), the LWC bundle, the four objects with their fields, the custom
permission, the permission set, the tab, and every Custom Metadata record. Read the manifest
rather than a list in a document: a list here would go stale, and one already did.

### 2.2 Delta deployment — an org already carrying the pre-merge version

The architectural work merged the By Criteria and By ID batch chains. **Five classes were
deleted**, and they must disappear in the same deployment that installs their replacements:

| Deleted | Replaced by |
|---|---|
| `TEKCO_AnonymizationBatch`, `TEKCO_AnonymizationByIdBatch` | `TEKCO_AnonymizationFieldBatch` |
| `TEKCO_ContentDocumentByIdBatch` | `TEKCO_ContentDocumentBatch` |
| `TEKCO_FieldHistoryByIdBatch` | `TEKCO_FieldHistoryBatch` |
| `TEKCO_AnonymizationBatchUtils` | `TEKCO_AnonymizationGuard` + `TEKCO_AnonymizationConfigSelector` |

```bash
sf project deploy start \
    --manifest anonymization/manifest/package-architecture.xml \
    --post-destructive-changes anonymization/manifest/destructiveChanges-architecture.xml \
    --dry-run --target-org <alias>
```

Drop `--dry-run` once it passes.

> **`--post-destructive-changes`, not `--pre-`.** The replacements must exist before the old
> classes go, or the deployment fails on classes that still reference them.

> **The delta is not small, and it cannot be.** A first attempt listed only the components
> the architectural commits touched and failed with 17 errors, all cascading from a method
> the org had never received. Closing the dependency graph pulls in the whole class set.
> `package-architecture.xml` deliberately excludes the CustomMetadata **records**, so an
> org's own field configs and patterns are left untouched.

---

## 3. Post-deployment steps

### Step 1 — Assign the permission set

Grant **TEKCO Anonymization Admin** to every user who needs the tool
(**Setup → Users → Permission Set Assignments**). It carries the `TEKCO_AnonymizeData`
custom permission, without which the interface does not render at all.

### Step 2 — Add the tab to the navigation app

**Setup → App Manager** → edit the Lightning app (e.g. **Run Teams Tools**) →
**Navigation Items** → add **TEKCO Data Anonymization** → Save.

### Step 3 — Enable Delete Field History

Both halves, per section 1.

### Step 4 — Check the configuration

Open the tool and click **Check Configuration** (section 6). This is the fastest proof the
deployment landed coherently, and it is the only thing that will tell you about a field
config naming an object or field that does not exist here.

---

## 4. Sandbox refresh checklist

After each refresh the org reverts to production state. Repeat:

- [ ] Redeploy: `sf project deploy start --manifest anonymization/manifest/package.xml --target-org <alias>`
- [ ] Reassign the **TEKCO Anonymization Admin** permission set.
- [ ] Re-enable **Delete Field History**, org level *and* permission set.
- [ ] Verify the tab appears in the navigation app.
- [ ] Click **Check Configuration** — it must come back clean.
- [ ] Run **Preview Scope**, and look at a **before/after sample** for at least one object,
      before launching anything.

---

## 5. Accessing the interface

The tool lives on the **TEKCO Data Anonymization** tab.

> **Prerequisite:** the **TEKCO Anonymize Data** custom permission. The LWC reads it directly
> (`@salesforce/customPermission/TEKCO_AnonymizeData`); without it the interface shows a red
> banner and nothing else. Every `@AuraEnabled` endpoint re-checks it server-side — read-only
> ones included, because they read PII across arbitrary objects.

Two tabs:

- **By Criteria** — anonymization by brand, object and record type
- **By ID (DataMig)** — targeted anonymization from an explicit list of record IDs or
  external IDs

Both reach the same engine. They differ only in how the set of records is resolved.

---

# Part 2 — Running the tool

## 6. Checking the configuration

**Check Configuration** is the first button on the By Criteria tab, and it is the one to press
after any change to the Custom Metadata.

It reports four things, each of which is **silently tolerated at run time** — the affected
field simply keeps its PII, the run still finishes `Success`, and nothing anywhere says so:

| Finding | What happens without the check |
|---|---|
| An object API name that does not exist in this org | Every config on that object is skipped at batch start |
| A field API name that does not exist on its object | That config is skipped |
| A pattern type with no active `TEKCO_AnonymizationPattern__mdt` record | Falls through to the `REGEX` default; with no regex configured the value is returned unchanged |
| A `TEKCO_AdditionalFilter__c` that will not parse | The step fails hours into the run, not at launch. The finding names the **configuration record**, not just the object: `Contact` carries five rules sharing one filter and `User` six, so the object alone would not say which record to open |
| Two different filters on one object whose rules do different things | Every rule is applied to the union of both, because a filter cannot be re-checked record by record — see §13.3.1 |

A clean configuration shows a green banner. Findings show as a warning list, one line each,
naming the config's DeveloperName so it can be found in Setup.

> **What it does not catch:** a filter that is syntactically valid but functionally wrong
> narrows the scope in silence, and a pattern that resolves but transforms the wrong way looks
> identical to a correct one. Only the before/after sample reveals those.

---

## 7. Choosing the scope *(By Criteria)*

### Brands

Restricts processing to records belonging to specific brands. Move brands from **Available**
to **Selected**, or use **Select All**. **No brand selected means no brand restriction** —
every record is in scope.

> Objects with no `TEKCO_Brand__c` field but with `TEKCO_Country__c` are filtered by country
> instead, derived from the selected brands through `TEKCO_CountryBrandSetting__mdt` (standard
> orgs) or through the brand object (orgs configured with `TEKCO_BrandObjectApiName__c`).

### Objects

Only objects with at least one active field config appear. **No object selected means all
configured objects.** Changing the selection refreshes the Record Types list.

### Record Types

Appears only when the selected objects have Record-Type-specific configs. Empty means all
record types.

---

## 8. Previewing

### 8.1 Scope preview — how many records

**Preview Scope** counts the records in scope per object, applying the brand and Record Type
filters, and loads the list of fields that would be modified.

> Objects whose only configured action is file deletion carry a dark badge. Their count is
> the number of **parent records that have linked files**, not the number of files.

### 8.2 Before/after sample — what the values become

Pick an object in **Object to sample** and click **Show sample**.

The tool reads **one record**, applies the patterns in memory, and shows a table of
`Record · Field · Pattern · Before · After` — one row per configured field. **Nothing is
written — the sample performs no DML at all.** It runs the same `applyPatternsTo()` the batch
runs, so what it shows is what the run will do.

One record is deliberate: the panel already renders a row per field, so a single case read
vertically is the useful unit. Twenty is the hard server-side ceiling, whatever is asked for.

> **This is the only defence against a pattern that is configured, active, resolvable — and
> functionally wrong.** It exists because of a real incident: a misconfigured pattern produced
> a run reported as `Success` with the targeted e-mail addresses left intact, and nothing
> revealed it until the data had already gone elsewhere. Look at the sample before every
> launch on a configuration you have not run before.

---

## 9. Reviewing the fields

The **Fields to Anonymize** table lists every field that would be modified, grouped by object.
Use **Filter by field** and **Record Type** to narrow a long list.

| Column | Meaning |
|---|---|
| **Run** | Uncheck to exclude the rule **from this run only**. The config is not modified. |
| **Rule** | Label of the configuration record behind the row. This is its identity — two rules can agree on object, field and record type and still be different records. It is also what a *Check Configuration* finding names, so a finding maps straight to a row. |
| **Field** | API name of the field. |
| **Pattern** | Algorithm applied. |
| **Record Type** | Record Types this rule covers — a **list** when it covers several, e.g. `ACCCO_IndividualPerson, ACCCO_Patient`. Empty = every record type. |
| **Scope** | The rule's `TEKCO_AdditionalFilter__c`, when it has one — the extra condition restricting it to part of the object. *By Criteria only*: a By ID run names its records explicitly and applies no filter, so the By ID table shows **Rule** but no **Scope**. |
| **Del. History** | Checked = the field's change history is deleted after anonymization. Uncheck for this run only. |
| **Description** | Functional description carried by the pattern record. |

**Run: Select All / Deselect All** and **Del. History: Select All / Deselect All** act in bulk.
**Del. History: Select All** only restores history deletion for fields originally configured
with `TEKCO_DeleteHistory__c = true`; it never enables it for a field that was not configured
for it.

> Unticking a rule excludes it by the configuration's **DeveloperName**, sent by the server and
> echoed back unchanged. Two rules on the same object and field are therefore excluded
> independently — which is exactly what the **Scope** column lets you tell apart. See the
> configuration model in [`SOLUTION_AND_ARCHITECTURE.md`](SOLUTION_AND_ARCHITECTURE.md).

---

## 10. Launching

Click the red **Launch Anonymization**. A confirmation dialog summarizes brands, objects,
record types, excluded fields and fields whose history will be kept.

> **WARNING: this operation is irreversible.** Data is permanently overwritten and cannot be
> restored from this tool.

### Only one run at a time

A launch is **refused** while another run is genuinely in flight, with a message naming the
run, who started it and when:

> *An anonymization run is already in progress (AL-000123, started by … on …). Two runs at
> once would leave the automation bypass in an inconsistent state. Wait for it to finish.*

This is not tidiness. The bypass service snapshots the **current** state of the hierarchy
setting as the "original" one. A second run started while the first is up records `true` as
the original and, when it ends, restores `true` — leaving automation disabled for that user
with nothing left to switch it back. The reverse ordering is as bad: the first run to finish
restores `false`, and the second carries on writing PII with every trigger and outbound sync
firing.

The check is org-wide, and it corroborates each `Running` audit log against the real
`AsyncApexJob` status. A log left behind by a job that died without reaching `finish()` is
recognised as stale and does not lock the tool out. A log inserted seconds ago whose batch has
not been enqueued yet is treated as live for **5 minutes**, then as stale.

### Automation bypass

Immediately before the first batch starts, every boolean flag on the bypass hierarchy custom
setting is set to `true` **for the launching user**, suppressing triggers, flows, validation
rules and outbound synchronization for the whole chain. The original values are captured first
and restored when the last step completes, successfully or not.

The bypass is raised **after** the "nothing to do" check, so a launch that resolves to an empty
scope never touches it. If the audit-log insert or the first `executeBatch` fails — storage
limit, for instance — the bypass is restored before the error is rethrown.

> In an org whose `TEKCO_AnonymizationOrgConfig__mdt` record leaves
> `TEKCO_BypassObjectApiName__c` blank (the Portugal / ALH case), the tool never touches the
> bypass at all.

---

## 11. Monitoring

Processing runs in the background. The interface refreshes every 5 seconds while a run is in
progress; **↺** forces a refresh.

The **Recent Runs** table shows the last 20 runs of that tab. The two tabs are separated by
`TEKCO_AnonymizationAuditLog__c.TEKCO_RunMode__c` — `BY_CRITERIA` or `BY_ID`. Logs written
before that field existed have it blank, and the queries fall back to the old discriminant
(a `LIKE 'BY_ID%'` on the brand-filter label) for those only.

| Column | Meaning |
|---|---|
| **Log #** | Audit log record name. |
| **Object(s)** | Objects processed. |
| **Brands** | Brand filter, or `BY_ID (N record(s))`. |
| **Status** | `Running`, `Success`, `Partial`, `Failed`. |
| **Processed** | Source records whose values actually changed. |
| **Failed** | Records that errored. |
| **By** | User who launched. |
| **Started** | Start date and time. |

| Status | Meaning |
|---|---|
| `Running` | At least one step is still in progress. |
| `Success` | Everything processed, no errors. |
| `Partial` | Completed, some records failed — read the error column. |
| `Failed` | A chain-level error stopped execution. |

**How Processed is counted:** a record counts only when at least one field value actually
changed. Records already anonymized, matching no rule, or with all target fields blank are not
counted. File and history deletions have their own counters.

**Error detail is bounded.** Messages are truncated to 200 characters, each step captures at
most 50 errors, and a run accumulates at most 200. The counters stay exact past those ceilings;
the individual identities do not.

### ⚠️ Aborting a run leaves the bypass raised — you must clear it by hand

**Read this before aborting a job from Setup → Apex Jobs.**

Launching switches **every** bypass checkbox to `true` for **the user who launched the run**.
The original values are captured first and put back automatically when the chain finishes —
successfully or with errors.

**That restore only happens in the batch's `finish()` method.** Aborting from
**Setup → Apex Jobs → Abort** skips `finish()`, so **the bypass flags stay on indefinitely**.

**Why this matters:** the flags are scoped to your user, not to the batch. Until you clear them,
*every* subsequent action you take in that sandbox — manual record edits, data loads, other
tooling — runs with all automation bypassed. Nothing warns you, and it persists across sessions.

**To restore them after an abort:**

1. **Setup → Custom Settings → TEKCO Bypass Settings → Manage**.
2. Find the record owned by **your user**.
3. Either uncheck every box to match what it was before the run, or **delete the user-level
   record** entirely if you did not have one before — the hierarchy then falls back to the org
   default.
4. Confirm by editing a record that should fire a trigger, and check that it does.

**Preferred alternative:** let the chain finish. Anonymization is idempotent for every pattern
but `ADDRESS_STREET_RANDOM` — a field is only written when the anonymized value differs from
the current one — so a run that completes with errors is safe, and re-launching afterwards
processes only what remains. Abort only when you genuinely must stop now, and clear the flags
straight afterwards.

---

## 12. Scheduling a run

`TEKCO_AnonymizationScheduler` wires the tool into a post-refresh routine.

```apex
System.schedule('TEKCO Anonymization', '0 0 2 * * ?', new TEKCO_AnonymizationScheduler());
```

Scope: **every configured object, every brand** — what the interface does when nothing is
narrowed. A narrower scope is a human decision and belongs in the interface.

No guard is bypassed: the sandbox check, the custom permission of the scheduling user, and the
concurrency refusal all still apply. A scheduled run is a run like any other.

> **What you give up:** nobody looks at the before/after sample first. Schedule this only
> against a configuration that has been verified interactively at least once, and re-verify it
> after any change to the field configs or patterns.

A refusal — production org, missing permission, another run in flight — is written to the debug
log, not to the audit log: the audit log only exists once a run actually starts.

---

# Part 3 — Configuration

## 13. Anonymization rules

Behaviour is driven entirely by Custom Metadata, from **Setup → Custom Metadata Types**.
**No code deployment is required to add or change a rule.**

### 13.1 Patterns — `TEKCO_AnonymizationPattern__mdt`

| Developer Name | Behaviour |
|---|---|
| `NAME_FIRST_LETTER` | First letter, then external ID → functional ID → Salesforce Id. `Jean Dupont` → `J0035g00000XyZAA` |
| `NAME_FIRST_LETTER_SFID` | First letter + Salesforce Id (forced). |
| `EMAIL_PLUS_EXTERNALID` | `base+externalId@domain`. |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | Idem, with the sandbox subdomain appended. |
| `EMAIL_PLUS_SFID` | `base+recordId@domain`. |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | Idem, with the sandbox subdomain appended. |
| `PHONE_MASK` | Keeps the first 4 characters, zeroes the rest. |
| `SSN_SEQUENTIAL` | Sequential digits of the same length as the source. |
| `ADDRESS_STREET_RANDOM` | Finds the first number and shifts it by 1–20. |
| `LOREM_IPSUM` | Replaces the whole value with Lorem Ipsum. |
| `CLEAR` | Empties the field. |
| `ZERO_MASK` | Regex-driven masking. |
| `EMAIL_MESSAGE_LOREM` | EmailMessage: Draft records get Lorem body, non-Draft records are deleted. |
| `DELETE_CONTENT_DOCUMENT` | Deletes the record's files. Handled by the file phase; no field change. |
| `KEEP` | Explicit no-op. Needs no pattern record. |

Anything that is not one of these names falls through to a `REGEX` default driven by
`TEKCO_RegexFind__c` / `TEKCO_RegexReplace__c` — which is how `ZERO_MASK` and any new
transformation work. **A name that is not recognised and carries no regex returns the value
unchanged, and the run still reports `Success`.** *Check Configuration* now reports this;
before it existed, nothing did.

**Pattern fields:**

| Field | Purpose |
|---|---|
| `TEKCO_Description__c` | Functional description shown in the interface. |
| `TEKCO_IsActive__c` | Must be checked for the pattern to be usable. |
| `TEKCO_BaseEmail__c` | Base address for `EMAIL_PLUS_*`. e.g. `sf_sap@airliquide.com.invalid` |
| `TEKCO_ExternalIdField__c` | Field used as the external identifier. |
| `TEKCO_SsnLength__c` | Target length for `SSN_SEQUENTIAL` when the source is blank. |
| `TEKCO_RegexFind__c` | Expression to match. Blank = replace the whole value. |
| `TEKCO_RegexReplace__c` | Replacement. Supports capture groups `$1`, `$2`. |

### 13.2 Two traps worth knowing

**`TEKCO_BaseEmail__c` must stay filled on every `EMAIL_PLUS_*` pattern.** Blank, the base
falls back to the record's *current* value: the pattern then appends instead of replacing, a
second run yields `base+ID+ID@…`, a third adds another, and eventually the field length is
exceeded and the DML fails. *Check Configuration* warns about this.

**`ADDRESS_STREET_RANDOM` is not idempotent.** Each run shifts the street number again.
Harmless, but a record anonymized three times has drifted three times. Every other pattern is
idempotent, which is what makes re-launching after a failure safe.

### 13.3 Field rules — `TEKCO_AnonymizationFieldConfig__mdt`

**Required:**

| Field | Purpose |
|---|---|
| `TEKCO_ObjectApiName__c` | Target object. |
| `TEKCO_FieldApiName__c` | Field to anonymize. Blank is normal for `DELETE_CONTENT_DOCUMENT`. |
| `TEKCO_PatternType__c` | DeveloperName of the pattern. |
| `TEKCO_IsActive__c` | Must be checked. |

**Filtering:**

| Field | Purpose |
|---|---|
| `TEKCO_RecordTypeDeveloperName__c` | **Comma-separated list** of the Record Type developer names this rule covers — `ACCCO_IndividualPerson,ACCCO_Patient`. A single name is a list of one. Empty = every record type. |
| `TEKCO_AdditionalFilter__c` | SOQL condition restricting **this rule** to part of the object. Shown in the **Scope** column. Administrator-authored and concatenated as written — validated at launch, not sanitized. |

### 13.3.1 Record types and the additional filter answer different questions

Both narrow a rule's scope, and both are needed.

**The record type list** says *which populations*. It is re-checked record by record during the
run, because a record carries its own `RecordTypeId` — which is why one rule can cover
`Patient,Prescriber` while another on the same object covers `Hospital` only, and each is applied
to the right records.

**The additional filter** says *which subset*, for the objects where the record type does not
discriminate. Every `Contact` shares one record type, so only
`Account.RecordType.DeveloperName = 'ACCCO_Patient'` isolates the contacts of patients. Same for
`Address`, whose populations are told apart by their parent account.

The trade-off to know: a filter is **not** re-checkable per record — it usually walks a
relationship, and Apex only sees the record itself. So if one object carried two different
filters whose rules did **different** things, every rule would be applied to the union of both.
*Check Configuration* reports that shape; no configuration in either org has it today, and
`Address` does not count — the same field and the same pattern sit behind both its filters, so
applying either rule to either population gives the same result.

> **Several rules on one object combine their filters with `OR`.** The object's scope is the
> union of the filters of the rules still ticked, so `Address.Street` — one rule filtered to
> `ACCCO_IndividualPerson`, another to `ACCCO_Patient` — reads both populations. A ticked rule
> carrying **no** filter means "no restriction" and lifts it for the whole object. Unticking a
> rule removes its term, which can only narrow the scope.

**Parent / child:**

| Field | Purpose |
|---|---|
| `TEKCO_ParentObjectApiName__c` | Parent object. Used as a filter in By Criteria, and to discover children in By ID. |
| `TEKCO_ParentLookupFieldApiName__c` | Lookup field on the child pointing at the parent (`AccountId`, not `Account`). |
| `TEKCO_ParentRecordTypeDeveloperName__c` | Parent Record Type used as a filter (By Criteria only). |

**History:**

| Field | Purpose |
|---|---|
| `TEKCO_DeleteHistory__c` | Checked = the field's change history is deleted after anonymization. |

### 13.4 Adding a rule

1. **Setup → Custom Metadata Types → TEKCO Anonymization Field Config → Manage Records → New**.
2. Label (e.g. `Patient PersonEmail`) and DeveloperName (e.g. `Patient_PersonEmail`).
3. Object, field, pattern type, `TEKCO_IsActive__c`.
4. Optional: Record Type, `TEKCO_DeleteHistory__c`, additional filter.
5. Save, then click **Check Configuration**, then look at a **before/after sample** for that
   object. Those two steps are what stand between a typo and a run that reports `Success`
   while leaving the field untouched.

Unchecking `TEKCO_IsActive__c` removes a rule from the interface and from processing without
deleting it.

### 13.5 How a run is ordered

The launch service builds a list of compact step descriptors and the chain runner executes them
one at a time:

```
FIELD:Account   FIELD:Contact   CD:Case_ContentDocument   HISTORY:Account
```

Field anonymization for every object first, then file deletion, then history deletion.

**The order is a correctness requirement.** Anonymizing a tracked field *creates* a history row
holding the old value. The history step runs afterwards and builds its query at that moment,
which is what makes it capture those rows. Reordering or parallelizing would leave the replaced
PII sitting in the history table.

Chunk sizes: **200** records for field anonymization (heap — each record carries every selected
field), **500** for file deletion by criteria and **100** by ID, **2000** for history rows.

---

## 14. Using the By ID (DataMig) tab

For anonymizing specific records without a brand filter — the recommended approach after a data
migration.

### Step 1 — Resolution mode

**Resolution mode** chooses what you are pasting:

- **ID** — Salesforce record IDs. Types may be mixed in one paste.
- **External ID** — values of an external identifier. Pick the **Target object** and the
  **External ID field**; the field list comes from that org's
  `TEKCO_ExternalIdFields__c` configuration.

### Step 2 — Paste the identifiers

One per line, comma-separated, semicolon-separated, or mixed. A live count of parsed values is
shown under the box. A run is capped at **50 000 records**.

### Step 3 — Preview Scope

Resolves the full scope without starting anything:

1. Parses and groups the values by SObject type.
2. Validates each type against the active configuration.
3. Resolves children: for each parent, queries the objects linked through
   `TEKCO_ParentObjectApiName__c` / `TEKCO_ParentLookupFieldApiName__c`.

| Section | Content |
|---|---|
| **Direct objects** | Objects whose IDs you supplied, with counts |
| **Resolved children** | Objects reached through parent-child configuration, with counts and source (e.g. `via Account.AccountId`) |
| **Skipped IDs** | Values that could not be parsed, or whose type has no configuration |

The **before/after sample** works here too, on the resolved records. **No data is modified at
this step.**

### Step 4 — Review fields

Identical to section 9, filters included.

### Step 5 — Launch

**Launch Anonymization** is disabled until at least one valid record is resolved. The
confirmation modal shows the resolved scope. The audit log is written with
`TEKCO_RunMode__c = 'BY_ID'` and a brand filter label of `BY_ID (N record(s))`.

The sandbox guard, the concurrency refusal and the automation bypass all apply exactly as in
the By Criteria tab — it is the same launch path.

---

## 15. Known limitations

### No resume after a failure

The step plan lives only in the serialized batch state. If the job dies — storage limit, a
deployment mid-run, a platform incident — the remaining plan goes with it and the run must be
restarted from the beginning. Restarting is safe: every pattern but `ADDRESS_STREET_RANDOM` is
idempotent, and only records that still differ are written.

### Failed records are not individually traceable past 200 errors

Counters stay exact. Identities do not, beyond the cap described in section 11.

### Coverage is whatever is configured

Nothing enumerates the PII the configuration does *not* cover. Task, Event and Chatter feeds,
for instance, are absent unless someone adds them. *Check Configuration* validates what is
configured; it cannot know what is missing.

### Asset Files cannot be deleted

> `We can't delete this file because it's an asset file being referenced by one or more
> objects. To delete it, first remove all references to it.`

Salesforce enforces this at the platform level, regardless of permissions or the `allOrNothing`
DML setting. The file is counted as failed, the message goes to the audit log, and the rest of
the step continues. Either remove the asset references (Setup → CMS or Experience Cloud assets)
before re-running, or accept that those files stay.

### File deletion can be truncated by the DML ceiling

One parent can own hundreds of files, and a chunk can resolve more rows than the 10 000-row DML
limit allows. The delete service stops at the remaining budget and reports the shortfall rather
than failing. Re-launching processes what was left.

### Aborting a job by hand leaves the bypass raised

`finish()` never runs, so nothing restores it. Manual recovery in section 11.

### `ADDRESS_STREET_RANDOM` on a value with no usable street number

If the field holds only a very large number — a phone number stored in an address field, say —
the pattern returns the value unchanged rather than erroring. It is recorded as a record with no
modification.

---

## 16. Where things live

| Concern | Class |
|---|---|
| By Criteria endpoints | `TEKCO_AnonymizationController` |
| By ID endpoints | `TEKCO_AnonymizationByIdController` |
| Turning a scope into a running chain | `TEKCO_AnonymizationLaunchService` |
| Everything the tool refuses, and the configuration check | `TEKCO_AnonymizationGuard` |
| Every Custom Metadata query | `TEKCO_AnonymizationConfigSelector` |
| What a run reads | `TEKCO_AnonymizationScopeQueryBuilder` |
| What runs next | `TEKCO_AnonymizationChainRunner` |
| Per-org resolution | `TEKCO_AnonymizationOrgConfigService` |
| Before/after sample | `TEKCO_AnonymizationPreviewService` |
| Scheduled entry point | `TEKCO_AnonymizationScheduler` |

Full architecture in [`SOLUTION_AND_ARCHITECTURE.md`](SOLUTION_AND_ARCHITECTURE.md).
