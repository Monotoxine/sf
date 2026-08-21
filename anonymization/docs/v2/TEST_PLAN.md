# Data Anonymization — Manual Test Plan

What to run by hand in a sandbox to validate the tool before trusting it with real data.
Written against what is actually implemented today; every expected result below comes from the
code, not from intent.

Companion to [`DEPLOYMENT_AND_USAGE.md`](DEPLOYMENT_AND_USAGE.md). Where a case fails, that guide
and [`DEPLOYMENT_NON_STANDARD_ORG.md`](DEPLOYMENT_NON_STANDARD_ORG.md) carry the remediation.

---

## Before you start

**This code has never been compiled against an org.** Everything was verified by static analysis.
Expect to fix a compile error or two on the first deployment — that is the single most valuable
thing you can do before testing anything else.

### What you need

| | |
|---|---|
| **Org** | A sandbox. Nothing can be launched in production; the guard blocks every entry point. |
| **User** | One holding **TEKCO Anonymization Admin**, and a second **without** it, for case 3. |
| **Data** | A handful of records per configured object, with the target fields populated — names, e-mails, phones, addresses. At least one record carrying a **file**, and at least one whose tracked field has **history rows**. |
| **Two browser tabs** | For the concurrency case. |
| **Setup access** | Custom Metadata Types, Custom Settings, Apex Jobs, Developer Console. |

### Take a snapshot first

Before any run, record the current values you are about to destroy — the anonymization is
irreversible and this tool restores nothing. Developer Console → Query Editor:

```sql
SELECT Id, FirstName, LastName, PersonEmail, Phone, PersonMailingStreet
FROM Account WHERE Id IN ('001...','001...')
```

Export the result. Several cases below compare against it.

### How to read a case

Each case states its **intent** (what would be broken if it failed), the **steps**, and the
**expected** result. Run them in order: the early ones set up the later ones.

---

# Group A — Deployment

## A1 — The deployment validates

**Intent**: nothing else is meaningful until the package compiles in this org.

**Steps**

Check first that no run is in flight — a chained run holds a serialized batch instance, and
redeploying the class it points at kills it mid-chain with the bypass left raised:

```sql
SELECT Id, Status, ApexClass.Name, CreatedDate FROM AsyncApexJob
WHERE Status IN ('Queued','Processing','Preparing','Holding') AND ApexClass.Name LIKE 'TEKCO_%'
```

Then, for a standard TEKCO org:

```bash
sf project deploy start --manifest anonymization/manifest/package-architecture-v2.xml \
    --dry-run --target-org <alias>
```

For Portugal, use `package-architecture-v2-Portugal.xml`.

**Expected**: the dry-run passes. Drop `--dry-run` and deploy.

## A2 — The five superseded classes are gone

**Intent**: the chain merge deleted five classes. Left behind, they still compile against code
that no longer exists and confuse anyone reading the org.

**Steps**: if this org carried the pre-merge version, deploy with the destructive companion:

```bash
sf project deploy start --manifest anonymization/manifest/package-architecture-v2.xml \
    --post-destructive-changes anonymization/manifest/destructiveChanges-architecture.xml \
    --target-org <alias>
```

Then **Setup → Apex Classes**, search `TEKCO_`.

**Expected**: no `TEKCO_AnonymizationBatch`, `TEKCO_AnonymizationByIdBatch`,
`TEKCO_ContentDocumentByIdBatch`, `TEKCO_FieldHistoryByIdBatch`, `TEKCO_AnonymizationBatchUtils`.
Twenty production classes remain.

## A3 — The unit tests pass

```bash
sf apex run test --test-level RunLocalTests --result-format human --code-coverage --wait 20
```

**Expected**: the 15 anonymization test classes pass. On Portugal they are not deployed at all —
they are written against the TEKCO schema and would not compile there.

---

# Group B — Access

## B1 — The tab opens for an authorised user

**Steps**: open **TEKCO Data Anonymization** as a user holding the permission set.

**Expected**: two tabs, **By Criteria** and **By ID (DataMig)**. No red banner.

## B2 — It refuses an unauthorised user

**Intent**: every endpoint reads PII across arbitrary objects. The gate is checked server-side on
read-only endpoints too, not only on launch.

**Steps**: open the tab as the user **without** the permission set.

**Expected**: a red banner naming the **TEKCO Anonymize Data** custom permission. No brand list,
no object list, no data of any kind.

---

# Group C — Configuration check

*New in v2. This is the first button on the By Criteria tab, and the cheapest test in this plan.*

## C1 — A healthy configuration reports clean

**Steps**: click **Check Configuration**.

**Expected**: a green banner — *"Configuration checked: every object, field, pattern and filter
resolves."*

**If it is not green**, work through the findings before running anything else. Each one names a
config's DeveloperName and describes a field that would keep its PII on a run reporting `Success`.

## C2 — A non-existent object is reported

**Intent**: this is the failure the check exists for. Without it, a typo in an object name means
every config on that object is skipped at batch start, silently.

**Steps**: **Setup → Custom Metadata Types → TEKCO Anonymization Field Config → Manage Records**.
Pick an inactive config, or create one; set `TEKCO_ObjectApiName__c` to `No_Such_Object__c` and
`TEKCO_IsActive__c` to true. Save. Back in the tool, click **Check Configuration**.

**Expected**: a warning naming `No_Such_Object__c`, saying every config on it is silently skipped,
and naming the first one.

**Then undo it** — set `TEKCO_IsActive__c` back to false.

## C3 — A non-existent field is reported

**Steps**: same, but keep a real object and set `TEKCO_FieldApiName__c` to `No_Such_Field__c`.

**Expected**: a warning naming `<Object>.No_Such_Field__c` and the config that carries it. Undo.

## C4 — An unknown pattern type is reported

**Intent**: a pattern DeveloperName is a dispatch key, not a label. An unrecognised one falls
through to the regex default and, with no regex configured, returns the value **unchanged** on a
run that still reports `Success`.

**Steps**: set a config's `TEKCO_PatternType__c` to `NOT_A_PATTERN`. Check Configuration.

**Expected**: a warning naming the unknown type. Undo.

## C5 — A malformed additional filter is reported

**Intent**: `TEKCO_AdditionalFilter__c` is the one string that reaches dynamic SOQL without
validation. Malformed, it used to fail hours into a run.

**Steps**: set `TEKCO_AdditionalFilter__c` to `CreatedDate >>> TODAY` on
`Contact_Patient_Email` — whose filter is shared by five configs. Check Configuration.

**Expected**: **one** warning, naming the **configuration records** and not just the object —
*"the additional filter of Contact Patient Email, Contact Patient FirstName, Contact Patient
LastName (+2) is not a valid condition on Contact…"*. The object alone would not say which of
the five to open in Setup. Undo.

## C6 — `KEEP` is *not* reported

**Intent**: `KEEP` needs no pattern record — it is a deliberate no-op, skipped before the
transformation runs. Flagging it would cry wolf on the very first check.

**Steps**: with the standard TEKCO configuration in place (six Account configs use `KEEP`), click
**Check Configuration**.

**Expected**: nothing about `KEEP`. Same for `DELETE_CONTENT_DOCUMENT` and `EMAIL_MESSAGE_LOREM`,
both handled by their own phase.

---

# Group D — Scope and preview

## D1 — Preview counts are plausible

**Steps**: select one object, no brand, no record type. **Preview Scope**.

**Expected**: a count per object. Compare against the same filter in Query Editor:

```sql
SELECT COUNT() FROM Account WHERE ...
```

**Expected**: the two agree.

## D1b — The count now includes the additional filter

**Intent**: the scope count never applied `TEKCO_AdditionalFilter__c`. It announced more records
than the run would touch on every filtered object — `Contact`, `User`, `Address`,
`ALH_Address__c`. It now uses the same condition as the launch.

**Steps**: **Preview Scope** on `Contact`, then run the equivalent query by hand:

```sql
SELECT COUNT() FROM Contact WHERE Account.RecordType.DeveloperName = 'ACCCO_Patient'
```

**Expected**: the two agree, and the displayed count is **lower** than what the previous version
showed. It did not become wrong — it was wrong on the high side.

## D2 — The brand filter narrows the scope

**Steps**: preview with no brand, note the count. Select one brand, preview again.

**Expected**: the second count is lower, or equal if every record carries that brand. It must
never be **higher** — no brand selected means no brand restriction, which is the widest scope.

## D3 — The record type filter narrows the scope

**Steps**: same, with a record type.

**Expected**: strictly narrower or equal.

## D4 — A file-only object shows a parent count

**Steps**: preview an object whose only configured action is `DELETE_CONTENT_DOCUMENT`.

**Expected**: a dark badge on that line. The number is the count of **parent records that have
linked files**, not the number of files.

## D5 — Unticking a rule never widens the scope

**Intent**: the additional filter belongs to the rule, and an object's scope is the `OR` of the
filters of the rules still ticked. Removing a term from an `OR` can only narrow. The previous
shape kept one filter per object and had to read it *before* the exclusion check, or unticking
one field dropped the object's only filter and **widened** the run.

**Steps**: pick an object whose rules carry a `TEKCO_AdditionalFilter__c` — the **Scope** column
shows which. Preview scope, note the count. Untick one rule of that object. Preview again.

**Expected**: the count **falls, or stays equal**. Equal is normal when another ticked rule
carries the same filter, or when a ticked rule carries none. **It must never grow.**

---

# Group E — Before/after sample

*New in v2. It exists because a misconfigured pattern once produced a run reported `Success` with
the targeted e-mails left intact.*

## E1 — The sample shows real values

**Steps**: after a preview, pick an object in **Object to sample**, click **Show sample**.

**Expected**: a table of `Record · Field · Pattern · Before · After` for **one** record, one row
per configured field. `Before` matches what Query Editor returns for that Id. Twenty is the
server-side ceiling, not the value used.

## E2 — The sample writes nothing

**Intent**: this is the one claim that must not be taken on faith.

**Steps**: note `LastModifiedDate` for a sampled record before showing the sample:

```sql
SELECT Id, LastModifiedDate, PersonEmail FROM Account WHERE Id = '001...'
```

Show the sample. Re-run the query.

**Expected**: `LastModifiedDate` and the field values are **identical**. The sample performs no
DML at all.

## E3 — The sample matches what the run writes

**Intent**: the sample shares its transformation code with the batch. If the two ever diverge, the
sample stops being a safeguard.

**Steps**: sample an object and screenshot the `After` column. Launch a run over the same scope.
When it finishes, query the same records.

**Expected**: the stored values equal the `After` column, field for field — except for
`ADDRESS_STREET_RANDOM`, which shifts the street number by a fresh random offset each time and
will differ in the number while matching in shape.

> The sample used to pick the **first** additional filter it found on the object while the run
> combined them all, so on `Address` it described a scope the run did not have. Both now call the
> same function. Sampling `Address` is the case that exercises it.

## E4 — Identifiers key on the right field

**Intent**: `EMAIL_PLUS_EXTERNALID` resolves its identifier through a four-step chain. Falling to
the last step silently substitutes the Salesforce Id.

**Steps**: sample an object carrying an `EMAIL_PLUS_EXTERNALID` config.

**Expected**: `After` reads `base+<externalId>@domain`, where `<externalId>` is the record's own
external identifier. **If it carries a Salesforce Id instead** (starts `001`, `003`, 15 or 18
characters), the chain fell through — on a non-standard org, check
`TEKCO_ExternalIdFields__c` on the org config record.

---

# Group F — Field selection

## F1 — An unticked field is not anonymized

**Intent**: exclusion travels as the configuration's `DeveloperName`, sent by the server and
echoed back unchanged, so an unticked rule is the rule the server skips.

**Steps**: untick exactly one field. Note its current value on a record in scope. Launch. When the
run finishes, query that record.

**Expected**: every other configured field changed; **the unticked one is untouched**.

## F2 — The same, on a field scoped to a record type

**Intent**: a record-type-scoped rule must be excludable on its own, without touching the other
rules on the same field.

**Steps**: repeat F1 with a config carrying `TEKCO_RecordTypeDeveloperName__c`, on a record of
that record type.

**Expected**: untouched.

## F3 — The field table filters work

**Steps**: use **Filter by field** with a partial API name, then **Record Type**.

**Expected**: the table narrows; the ticks you had set are preserved through filtering.

## F4 — Two rules on the same field are told apart, and ticked apart

**Intent**: `Address.Street` is carried by two configurations differing only by their additional
filter. They used to render as two identical rows sharing one exclusion key, so unticking either
unticked both, and no choice between them existed.

**Steps**: select `Address` and preview.

**Expected**: two rows for `Street`, distinguished by the **Rule** column (`IndividualP Address`
/ `Patient Address`) and by **Scope**, which shows each one's filter.

Untick `IndividualP Address`.

**Expected**: `Patient Address` **stays ticked**. Preview again — the count falls.

Re-tick it and untick `Patient Address` instead.

**Expected**: the mirror image. Each rule is independently selectable.

## F5 — A rule covering several record types *(after consolidation)*

**Intent**: `TEKCO_RecordTypeDeveloperName__c` now holds a **list**. The 98 records still carry
one name each, so this case only becomes runnable once they are merged — the code is ready, the
data is not.

**Steps**: on a rule covering several populations, e.g. `ACCCO_IndividualPerson,ACCCO_Patient`:
select its object and preview.

**Expected**: **one** row for that field, its **Record Type** column showing both names. The
**Record Types** selector at the top of the page offers each name separately, and ticking either
one keeps the rule in the table.

Untick the rule.

**Expected**: it is excluded for **both** populations — it is one rule.

---

# Group G — A By Criteria run, end to end

## G1 — The run completes

**Steps**: choose a small scope. **Launch Anonymization** → confirm.

**Expected**: the confirmation dialog summarizes brands, objects, record types, excluded fields
and history exclusions. After launch the Recent Runs table shows `Running`, refreshing every
5 seconds, then `Success`.

## G2 — The bypass is raised during, and restored after

**Intent**: the flags are scoped to your user, not to the batch. Left raised, every later action
you take in the sandbox runs with automation disabled and nothing warns you.

*Skip this case where `TEKCO_BypassObjectApiName__c` is blank — Portugal, for one. The tool never
touches the bypass there.*

**Steps**: **Setup → Custom Settings → TEKCO Bypass Settings → Manage**. Note the state of your
user's record, or its absence. Launch a run and re-open it **while it is running**. Re-open once
more after it completes.

**Expected**: during the run, every checkbox is ticked. Afterwards, exactly the state you noted
first — including the record being absent again if it was.

## G3 — The counters are right

**Steps**: read the Recent Runs row.

**Expected**: **Processed** counts source records where **at least one value actually changed**.
Records already anonymized, matching no rule, or with every target field blank are not counted.
File and history deletions have their own counters and are not folded into Processed.

## G4 — The run is idempotent

**Intent**: this is what makes re-launching after a failure safe.

**Steps**: launch the identical scope a second time.

**Expected**: `Success` with **Processed = 0**, or close to it. A field is only written when the
anonymized value differs from the current one.

**Exception**: `ADDRESS_STREET_RANDOM` shifts the number again on every run, so objects carrying
it report a non-zero count. Expected, and worth knowing before it surprises you.

## G5 — The audit log is complete

**Steps**: open the audit log record.

**Expected**: `TEKCO_Status__c`, start and end time, the launching user, the job Id, the object
list, the brand filter, `TEKCO_RunMode__c = 'BY_CRITERIA'`, and the counters. Errors, if any, are
truncated at 200 characters, capped at 50 per step and 200 for the run — the counters stay exact
past those ceilings, the individual identities do not.

## G6 — The two tabs do not mix

**Steps**: look at Recent Runs in both tabs.

**Expected**: By Criteria runs only on the left, By ID runs only on the right. The discriminant is
`TEKCO_RunMode__c`; logs written before that field existed fall back to the old brand-filter test.

## G7 — Both Address populations are anonymized

**Intent**: the defect that motivated the change. Only one of the two `Address.Street` filters
was ever applied — whichever the platform returned first, with no `ORDER BY` deciding it — so one
population kept its street numbers, silently, on a run reporting `Success`.

**Steps**: before the run, note the street of one address whose parent Account is an
`ACCCO_IndividualPerson` **and** one whose parent is an `ACCCO_Patient`:

```sql
SELECT Id, Street, ACCCO_RelatedAccount__r.RecordType.DeveloperName FROM Address
WHERE ACCCO_RelatedAccount__r.RecordType.DeveloperName IN ('ACCCO_IndividualPerson','ACCCO_Patient')
```

Run with both `Address` rules ticked. Re-query.

**Expected**: **both** street numbers have shifted. If one is untouched, the `OR` did not reach
it — compare the two rows' **Scope** values against the record's parent record type.

> `ADDRESS_STREET_RANDOM` shifts by a random 1–20, so compare that the number *changed*, not what
> it became.

## G8 — Coverage is respected per population *(after consolidation)*

**Intent**: a rule covering only part of an object's populations must not reach the others. On
ALH, 11 rules are in that case — `ALH_FiscalNumber__c` concerns Hospital only, `Description`
Patient only.

**Steps**: run over an object whose rules have uneven coverage. Then query one record of a
population a given rule does **not** cover.

**Expected**: the field that rule drives is **untouched** on that record, while the fields driven
by rules covering it did change.

---

# Group H — History and files

## H1 — Field history is deleted where configured

**Intent**: this validates the phase ordering. Anonymizing a tracked field *creates* the history
row holding the old value; the history step runs afterwards precisely to catch it. If the order
ever changed, the replaced PII would sit in the history table.

**Prerequisite**: **Delete Field History** enabled at org level *and* on the permission set.
Without it, history is silently left in place.

**Steps**: pick a record whose tracked, history-enabled field has rows:

```sql
SELECT Id, Field, OldValue, NewValue, CreatedDate FROM AccountHistory
WHERE AccountId = '001...' ORDER BY CreatedDate DESC
```

Run over it, then re-query.

**Expected**: no history rows for the anonymized fields — **including the row the run itself just
created**. That last point is the whole test.

## H2 — Unticking Del. History keeps the history

**Steps**: untick **Del. History** for one field, run, re-query.

**Expected**: history rows for that field survive; the others are gone.

## H3 — Del. History: Select All does not over-reach

**Steps**: click **Del. History: Deselect All**, then **Select All**.

**Expected**: only fields originally configured with `TEKCO_DeleteHistory__c = true` come back
ticked. It never enables history deletion for a field that was not configured for it.

## H4 — Files are deleted

**Steps**: note the files on a record configured with `DELETE_CONTENT_DOCUMENT`:

```sql
SELECT ContentDocumentId, ContentDocument.Title FROM ContentDocumentLink
WHERE LinkedEntityId = '001...'
```

Run, re-query.

**Expected**: gone. The audit log's documents-deleted counter matches.

## H5 — An asset file fails without stopping the run

**Steps**: if the org has one, include a record whose file is an asset file.

**Expected**: the run finishes `Partial`. The audit log error column carries *"We can't delete
this file because it's an asset file…"*. Every other file was still deleted. This is a platform
restriction, not a permissions problem.

---

# Group I — By ID

## I1 — Pasting IDs, every accepted format

**Steps**: in **Resolution mode = ID**, paste in turn: one Id per line; comma-separated;
semicolon-separated; a mix of the three with stray spaces; 15-character and 18-character forms;
Ids of two different object types together.

**Expected**: the live counter under the box matches what you pasted, in every format.

## I2 — Unusable values are reported, not swallowed

**Steps**: add a line of nonsense, and an Id of an object with no configuration.

**Expected**: **Preview Scope** lists them under **Skipped IDs**. The valid ones still resolve.

## I3 — Children are resolved

**Steps**: paste parent Ids only — Accounts, say — where a child object is configured with
`TEKCO_ParentObjectApiName__c` and `TEKCO_ParentLookupFieldApiName__c`.

**Expected**: **Resolved children** lists the child object with a count and its source, e.g.
`via Account.AccountId`.

**If children do not appear**: `TEKCO_ParentLookupFieldApiName__c` must be the lookup field's API
name — `AccountId`, not `Account`. This is the most common configuration error on this path.

## I4 — Resolution by external ID

**Steps**: switch **Resolution mode** to `EXTERNAL_ID`. Pick a **Target object** and an
**External ID field**, paste external identifier values.

**Expected**: the field list offers only that org's configured external ID fields. Preview
resolves the matching records; values matching nothing land in Skipped.

## I5 — The run is scoped to exactly those records

**Intent**: a By ID run must never widen to the whole object.

**Steps**: launch on three records. Query a fourth, in the same object and record type, that you
did **not** list.

**Expected**: the fourth is untouched.

## I6 — The audit log identifies the mode

**Expected**: `TEKCO_RunMode__c = 'BY_ID'`, brand filter reading `BY_ID (N record(s))`, and the
row appears only in the By ID tab.

## I7 — The cap holds

*Optional, only if you can produce the volume.* Paste enough Ids that parents **and their
resolved children together** exceed 50 000, then launch.

**Expected**: the launch is refused with the resolved count and the ceiling — *"… records
resolved (parents and children), maximum 50000. Narrow the ID list, or use the By Criteria tab
for a scope of this size."* The check happens at launch, not at preview, and counts children:
a few thousand parents with a fan-out can trip it.

---

# Group J — One run at a time

*New in v2, and the case most worth running: two concurrent runs corrupt the automation bypass in
a way nothing reports.*

## J1 — A second launch is refused while the first runs

**Steps**: launch a run large enough to last a minute. In a **second browser tab**, open the tool
and try to launch anything.

**Expected**: a refusal naming the run, who started it and when — *"An anonymization run is
already in progress (…, started by … on …). Two runs at once would leave the automation bypass in
an inconsistent state. Wait for it to finish."*

## J2 — Across users, not just across tabs

**Steps**: repeat with a second authorised user while the first user's run is in flight.

**Expected**: same refusal. The check is org-wide.

## J3 — Both tabs are covered

**Steps**: with a By Criteria run in flight, try to launch from the **By ID** tab, and the
converse.

**Expected**: refused both ways. There is one launch path; both tabs go through it.

## J4 — A finished run stops blocking

**Steps**: wait for the run to reach `Success`. Launch again.

**Expected**: it starts normally.

## J5 — A stale log does not lock the tool out for ever

**Intent**: a log left on `Running` by a job that died without reaching `finish()` must not
condemn the tool. The guard corroborates each log against the real `AsyncApexJob` status.

**Steps**: Developer Console → Execute Anonymous, forge a stale log:

```apex
insert new TEKCO_AnonymizationAuditLog__c(
    TEKCO_Status__c    = 'Running',
    TEKCO_StartTime__c = Datetime.now().addHours(-2),
    TEKCO_JobId__c     = '707000000000000AAA'   // a job that does not exist
);
```

Try to launch.

**Expected**: the launch **is allowed** — the job is unknown, so the log is stale.

Now the other half: insert a log with `TEKCO_StartTime__c = Datetime.now()` and **no**
`TEKCO_JobId__c`. Try to launch.

**Expected**: refused — a launch under five minutes old with no job yet is treated as live. Wait
past five minutes, try again: allowed.

**Clean up both forged logs afterwards.**

---

# Group K — Failure paths

## K1 — Production is refused

**Steps**: if you have a way to reach a production org with the package deployed, open the tab and
try to launch.

**Expected**: refused. Deploying to production is harmless; nothing can be run there.

## K2 — Aborting leaves the bypass raised

**Intent**: this is a real operational hazard and the recovery must be rehearsed once, not
discovered during an incident.

*Skip where `TEKCO_BypassObjectApiName__c` is blank.*

**Steps**: launch a run, then **Setup → Apex Jobs → Abort**. Open
**Setup → Custom Settings → TEKCO Bypass Settings → Manage**.

**Expected**: every checkbox on your user's record is **still ticked**. `finish()` never ran, so
nothing restored them. The audit log stays on `Running`.

**Then recover**, and confirm the recovery: untick every box, or delete the user-level record if
you had none before. Edit a record that should fire a trigger and check that it does.

**Then confirm the guard recovers too**: the abandoned `Running` log must not block the next
launch — the aborted job reads `Aborted`, so the guard treats the log as stale. Launch again; it
should start.

## K3 — A run with errors still restores the bypass

**Steps**: engineer a failure — a validation rule the bypass does not cover, or a required field
emptied by a `CLEAR` config. Launch.

**Expected**: the run ends `Partial` or `Failed`, the errors are in the audit log, and the bypass
is restored. Handled failures still reach `finish()`.

## K4 — A launch that fails before starting restores the bypass

**Intent**: the bypass is raised just before the first batch. If the audit log insert fails —
storage limit — it must be put back before the error surfaces.

**Steps**: reproducible only in an org at 100% data storage. If you have hit
`STORAGE_LIMIT_EXCEEDED` before, check the bypass state afterwards.

**Expected**: the error is shown, no run starts, no audit log is created, and the bypass flags are
**not** left raised.

## K5 — An empty scope changes nothing

**Steps**: build a filter combination that matches no record — a brand with no data, say — and
launch.

**Expected**: a "nothing to do" message. **No audit log is created, and the bypass is never
raised** — it is only raised after that check passes.

---

# Group L — Scheduling

*New in v2.*

## L1 — A scheduled run starts

**Steps**: Developer Console → Execute Anonymous, a few minutes out:

```apex
System.schedule('TEKCO Anonymization Test', '0 35 14 * * ?', new TEKCO_AnonymizationScheduler());
```

Watch **Setup → Scheduled Jobs**, then **Apex Jobs**.

**Expected**: at the appointed minute a run starts over **every configured object and every
brand** — a scheduled run narrows nothing. An audit log appears with
`TEKCO_RunMode__c = 'BY_CRITERIA'`.

## L2 — The guards still apply to it

**Steps**: schedule one for a minute when a manual run is deliberately in flight.

**Expected**: no second run starts. The refusal is written to the debug log, not to the audit log —
the audit log only exists once a run actually starts. A `Schedulable` that swallows its exception
leaves nothing else to read.

**Then unschedule the test job.**

---

# Sign-off

| Group | Cases | Result | Notes |
|---|---|---|---|
| A — Deployment | A1–A3 | | |
| B — Access | B1–B2 | | |
| C — Configuration check | C1–C6 | | |
| D — Scope and preview | D1, D1b, D2–D5 | | |
| E — Before/after sample | E1–E4 | | |
| F — Field selection | F1–F5 | | |
| G — By Criteria run | G1–G8 | | |
| H — History and files | H1–H5 | | |
| I — By ID | I1–I7 | | |
| J — One run at a time | J1–J5 | | |
| K — Failure paths | K1–K5 | | |
| L — Scheduling | L1–L2 | | |

## If you can only run six

**C1** the configuration is clean · **E2** the sample writes nothing · **E3** the sample matches
the run · **D5** unticking a rule never widens the scope · **G7** both Address populations are
reached · **G2** the bypass comes back down · **J1** a second launch is refused.

Those six cover the failures that are both plausible and silent. Everything else announces itself.
