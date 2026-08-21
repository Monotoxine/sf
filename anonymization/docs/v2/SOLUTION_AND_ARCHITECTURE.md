# Data Anonymization — Solution and Architecture

Reference for how the tool is built. For deploying and operating it, see
[`DEPLOYMENT_AND_USAGE.md`](DEPLOYMENT_AND_USAGE.md); for an org that is not a standard TEKCO org, see
[`DEPLOYMENT_NON_STANDARD_ORG.md`](DEPLOYMENT_NON_STANDARD_ORG.md).

---

## 1. What the tool does

It replaces personal data in a sandbox with values that are stable, reversible in meaning
but not in content, and safe to keep in a non-production org. It works from a configuration
held in Custom Metadata, so adding a field to anonymize is an administrative act, not a
deployment.

Two ways in, both reaching the same engine:

| | Scope | Typical use |
|---|---|---|
| **By Criteria** | brands, objects, record types | full sweep after a sandbox refresh |
| **By ID** | an explicit list of record IDs or external IDs, plus their configured children | a targeted request, a data-migration follow-up |

The two differ **only** in how the set of records is resolved. Everything after that —
loading the configuration, planning the phases, raising the automation bypass, opening the
audit log, running the chain — is one code path.

---

## 2. Architecture

### 2.1 Layers

The package follows the layering Salesforce documents: thin controllers, a service layer
carrying business logic, a selector owning data access. No class is named `Utils`.

| Layer | Class | Responsibility |
|---|---|---|
| **Controller** | `TEKCO_AnonymizationController` | By Criteria endpoints. Validates the object list, then delegates. |
| | `TEKCO_AnonymizationByIdController` | By ID endpoints. Parses IDs, resolves external IDs, walks parent-to-child links, bounds the result, then delegates. |
| **Service** | `TEKCO_AnonymizationLaunchService` | Turns a resolved scope into a running chain. The single launch path. |
| | `TEKCO_AnonymizationPreviewService` | Before/after sample on a bounded set of records, with no DML. |
| | `TEKCO_AnonymizationExecuteService` | The transformation itself, and the DML that persists it. |
| | `TEKCO_AnonymizationPatternService` | One algorithm per pattern type. |
| | `TEKCO_AnonymizationBypassService` | Raises and restores the automation bypass. |
| | `TEKCO_AnonymizationAuditService` | Writes the audit log. |
| | `TEKCO_ContentDocumentDeleteService` | Deletes files: ServiceReport, then ContentDocument, then Attachment. |
| | `TEKCO_FieldHistoryDeleteService` | Deletes field-history rows. |
| **Selector** | `TEKCO_AnonymizationConfigSelector` | Every Custom Metadata query, with per-transaction caching. |
| **Guard** | `TEKCO_AnonymizationGuard` | Everything the tool refuses, plus the configuration health check. |
| **Orchestration** | `TEKCO_AnonymizationRunContext` | State shared by every batch of one run, and the plan of what is left to do. |
| | `TEKCO_AnonymizationChainRunner` | Single owner of what runs next. |
| | `TEKCO_AnonymizationScopeQueryBuilder` | Pure functions deciding what a run reads. |
| **Batch** | `TEKCO_AnonymizationFieldBatch` | Field-level anonymization of one object. |
| | `TEKCO_ContentDocumentBatch` | File deletion for one config. |
| | `TEKCO_FieldHistoryBatch` | History deletion for one object. |
| **Config** | `TEKCO_AnonymizationOrgConfigService` | Per-org resolution: domain, brand model, bypass setting, external ID fields. |
| **Entry** | `TEKCO_AnonymizationScheduler` | Schedulable wrapper for a post-refresh routine. |

Twenty production classes, fifteen test classes.

### 2.2 One chain, not two

Each batch serves **both** By Criteria and By ID. The mode is read from `RunContext.byId`;
only the scope query differs, and both variants live in
`TEKCO_AnonymizationScopeQueryBuilder`.

This replaced six classes that were near-identical in pairs. That duplication had produced
five separate defects where a fix landed on one chain and not its twin — a missing heap
fix, a missing error cap, a missing `Field IN ()` guard, a missing object-existence guard,
and two divergent batch sizes. With one class per phase the whole family is structurally
impossible.

### 2.3 The step plan

`TEKCO_AnonymizationLaunchService` builds a list of compact descriptors:

```
FIELD:Account   FIELD:Contact   CD:Case_ContentDocument   HISTORY:Account
```

`TEKCO_AnonymizationChainRunner.startNext()` pops the next one, starts the right batch, and
when the list is empty restores the bypass and finalizes the audit log. Every `finish()` is
the same three lines: fold the chunk's results into the context, then call `startNext()`.

**The order is a correctness requirement, not a convenience.** Anonymizing a tracked field
*creates* a history row holding the old value. The history phase runs afterwards, and its
QueryLocator is built at that moment, which is what makes it capture those rows. Reordering
or parallelizing the phases would leave the replaced PII in the history table.

### 2.4 What crosses a chunk boundary

Batches are `Database.Stateful`. Only lightweight values are kept: developer names, ID
lists, counters. Custom Metadata rows are **never** held in stateful fields — doing so
caused heap and serialization failures. Each `execute()` reloads them through the
per-transaction cache in `TEKCO_AnonymizationConfigSelector`, which is why concentrating
the SOQL there matters.

### 2.5 Batch sizes

| Phase | Records per chunk | Why |
|---|---|---|
| Field | 200 | Heap: each record carries every selected field. |
| ContentDocument | 500 By Criteria / **100 By ID** | One parent can own hundreds of files, and a chunk can resolve more than the 10 000-row DML ceiling. The delete service stops at the remaining budget and reports the shortfall. A smaller chunk truncates less often; a larger one is faster. |
| Field history | 2000 | Rows are small and the operation is a plain delete. |

The ContentDocument disagreement was never a decision: the commit that introduced the DML
budget set 100 on one side and left 500 on the other. `batchSizeFor(Boolean byId)` keeps
both values with the reason written down, pending a measured choice.

---

## 3. Safety mechanisms

### 3.1 Sandbox only

`assertIsSandbox()` runs at launch, and again inside every batch `start()` through
`assertSandboxOrClose()` — which, if it trips, closes the audit log and restores the bypass
rather than letting the job die with the log stuck on `Running`.

### 3.2 Only one run at a time

Two concurrent runs corrupt the bypass. `activate()` snapshots the **current** state of the
hierarchy setting as the "original" one: a second run started while the first is up records
`true` as the original and, on finishing, restores `true` — leaving the org's automation
disabled with nothing left to switch it back. The other ordering is as bad: the first to
finish restores `false` and the second carries on writing PII with every trigger firing.

`assertNoRunInProgress()` refuses a launch while a run is genuinely in flight. It
corroborates each `Running` audit log against the real `AsyncApexJob` status, so a log left
behind by a job that died without reaching `finish()` cannot lock the tool out for good.

### 3.3 Nothing reaches dynamic SOQL unchecked

Object names go through `requireConfiguredObject()`, field names through
`requireFieldOnObject()`. The one exception is `TEKCO_AdditionalFilter__c`, which is
administrator-authored and concatenated as written — it is now parsed at launch instead of
failing hours into a run.

### 3.4 The configuration is checkable before use

`validateConfiguration()` reports objects that do not exist in this org, fields that do not
exist on their object, pattern types with no active record, and filters that will not
parse. Each of those is silently "skipped" at run time today, leaving the field it was
meant to protect with its PII and no visible signal.

### 3.5 The before/after sample

`previewSample` reads **one record** by default — 20 is the hard ceiling, whatever the caller
asks for — applies the patterns in memory and throws the result away — **no DML, ever**. It
shares `applyPatternsTo()` with the run, so what it shows is what the run will do. One record
already fills the table: the panel renders a row per configured field, so a single case read
vertically is the useful unit.

It exists because of a real incident: a misconfigured pattern produced a run reported as
`Success` with the targeted e-mails left intact, and nothing revealed it until the data was
gone elsewhere.

### 3.6 Bounded state

| Ceiling | Value | Owner |
|---|---|---|
| Error message length | 200 characters | `RunContext.cap()` |
| Errors per producer | 50 | `RunContext.MAX_CAPTURED_ERRORS` |
| Errors per run | 200 | `RunContext.MAX_ACCUMULATED_ERRORS` |
| Records per By ID run | 50 000 | `TEKCO_AnonymizationByIdController.MAX_BY_ID_RECORDS` |
| Records per preview | 1 by default, 20 maximum | `TEKCO_AnonymizationPreviewService.DEFAULT_SAMPLE_SIZE` / `MAX_SAMPLE_SIZE` |

### 3.7 `without sharing`, deliberately

The batches and the preview run `without sharing`. Anonymization must reach every record in
scope; running with sharing would silently skip records the launching user cannot see,
leaving PII in place with no error. Access is gated upstream by the
`TEKCO_AnonymizeData` custom permission on every `@AuraEnabled` endpoint — read-only ones
included.

---

## 4. Performance

The hot path runs once per configured field **and** per record. On an object carrying 69
active configurations that is roughly 67 regex compilations per record — over thirteen
thousand per chunk of 200 — for patterns that are constant for the whole run. A batch
transaction has 60 seconds of CPU.

Everything constant is now compiled or computed once per transaction:

- the external-ID format check, a literal, is a static `System.Pattern`;
- regexes coming from Custom Metadata are compiled once each, cached by the regex itself;
- `ADDRESS_STREET_RANDOM` compiled twice per call and now compiles none;
- the `SSN_SEQUENTIAL` sequence depends only on its length and is memoised by length;
- the org suffix used by the `_SUBDOMAIN` patterns is computed once;
- `getExternalIdFieldsOn()` split a string — compiling a regex — on every record along the
  fallback path, and is now cached per object.

These are memoisations of pure computations on statics that reset each transaction, so
nothing survives from one chunk to the next.

**Parallelizing the chain is not on the table.** The gain is bounded by the longest single
step, which is one object; and it would break both the bypass (section 3.2) and the phase
ordering (section 2.3).

---

## 5. Pattern reference

Fourteen pattern records, plus `KEEP`.

| Pattern | Effect |
|---|---|
| `NAME_FIRST_LETTER` | First letter + external ID → functional ID → record ID |
| `NAME_FIRST_LETTER_SFID` | First letter + record ID |
| `EMAIL_PLUS_EXTERNALID` | `base+externalId@domain` |
| `EMAIL_PLUS_EXTERNALID_SUBDOMAIN` | idem, suffixed with `country.sandbox` |
| `EMAIL_PLUS_SFID` | `base+recordId@domain` |
| `EMAIL_PLUS_SFID_SUBDOMAIN` | idem, suffixed with `country.sandbox` |
| `PHONE_MASK` | Digits masked past the fourth character |
| `SSN_SEQUENTIAL` | Sequential digits, cycling 1–9, to the source length |
| `ADDRESS_STREET_RANDOM` | Street number shifted by 1–20 |
| `LOREM_IPSUM`, `CLEAR`, `ZERO_MASK` | Regex replacements |
| `EMAIL_MESSAGE_LOREM` | Draft e-mail → lorem text; non-draft → record deleted |
| `DELETE_CONTENT_DOCUMENT` | Handled by the ContentDocument phase, not a field transformation |
| `KEEP` | Explicit no-op. Needs no pattern record. |

### Two traps worth knowing

**`TEKCO_BaseEmail__c` must stay filled** on the `EMAIL_PLUS_*` patterns. Blank, the base
falls back to the record's own value: the pattern appends rather than replaces, a second
run yields `base+ID+ID@…`, and eventually the field length is exceeded and the DML fails.
The configuration check warns about this.

**`ADDRESS_STREET_RANDOM` is not idempotent.** Each run shifts the number again. Harmless,
but a record anonymized three times has drifted three times.

---

## 6. Configuration model

### `TEKCO_AnonymizationPattern__mdt`

One record per pattern type. Carries the regex (`TEKCO_RegexFind__c`,
`TEKCO_RegexReplace__c`), the base e-mail, the SSN length, the external ID field, and
`TEKCO_IsActive__c`.

### `TEKCO_AnonymizationFieldConfig__mdt`

One record per field to process. `TEKCO_ObjectApiName__c`, `TEKCO_FieldApiName__c`,
`TEKCO_PatternType__c`, optionally `TEKCO_RecordTypeDeveloperName__c`,
`TEKCO_DeleteHistory__c`, `TEKCO_AdditionalFilter__c`, and the parent link fields used by
the By ID chain to reach children.

**The config key is the `DeveloperName`.** It travels to the interface on the field DTO,
comes back as `excludedFields` / `disabledHistoryFields`, and
`TEKCO_AnonymizationConfigSelector.configKey()` compares it to decide what to skip. The client
never builds it — it echoes back what the server sent — so there is no format for the two sides
to disagree about.

It used to be `Object.Field.RecordType`, built independently in Apex and in the LWC. Two
problems, both real. The format was a hand-kept contract whose breach was silent: untick a
field, watch the UI show it excluded, watch the run anonymize it anyway. And it **collided** —
`Address.Street` is carried by two configurations that differ only by their additional filter,
so both produced `Address.Street.` and unticking either unticked both.

**The additional filter belongs to the configuration**, not to the object. An object's scope is
the OR of the filters of its **retained** configurations, parenthesised as a whole because
`whereClause()` joins conditions with `AND` and `AND` binds tighter than `OR`. A retained
configuration carrying no filter means "no restriction" and lifts it for the whole object.

`TEKCO_AnonymizationScopeQueryBuilder.combineAdditionalFilters()` is the single definition of
that rule, and the launch, the scope count and the before/after sample all call it. They used to
each have their own idea of the scope: the sample kept the first filter it found, and the count
ignored filters altogether and announced more records than the run would touch.

**`TEKCO_RecordTypeDeveloperName__c` holds a comma-separated list** — the populations a rule
covers. Blank means every record type; a single name is a list of one, which is why every
configuration written before the change behaves identically.
`TEKCO_AnonymizationConfigSelector.recordTypesOf()` is the only place the string is split.

**The user's record-type selection is a scope filter, exactly like the brands.** It rides on
`RunContext.selectedRecordTypes` and becomes a condition on all three scope queries through
`TEKCO_AnonymizationScopeQueryBuilder.recordTypeCondition()` — the same function the preview
count and the sample call.

It used to stop at the launch service, where it only decided which *rules* to keep. That was
enough while each rule named one record type, and stopped being enough the moment a rule could
cover two: selecting `ACCCO_Patient` kept a rule covering `ACCCO_IndividualPerson,ACCCO_Patient`,
the query read every Account, and both populations were anonymized — while the count and the
sample, which did honour the selection, showed only Patients.

The two fields answer different questions, and both are needed. The record type says *which
populations* — it is re-checkable per record, because the record carries its `RecordTypeId`. The
filter says *which subset*, for objects where the record type does not discriminate: every
`Contact` shares one record type, so only `Account.RecordType.DeveloperName = 'ACCCO_Patient'`
isolates the contacts of patients.

That shape replaced a first-wins map, and it fixes two things at once. `Address` used to keep
only whichever filter the platform happened to return first — no `ORDER BY` decided it — so one
of its two populations was never anonymized, silently, on a run reporting `Success`. And
unticking a field now removes a term from an `OR`, which can only narrow; the old shape had to
read the filter *before* the exclusion check or unticking one field dropped the object's only
filter and **widened** the run.

### `TEKCO_AnonymizationOrgConfig__mdt`

Per-org resolution, keyed on the org domain prefix. See [`DEPLOYMENT_NON_STANDARD_ORG.md`](DEPLOYMENT_NON_STANDARD_ORG.md).

### `TEKCO_AnonymizationAuditLog__c`

One record per run. `TEKCO_RunMode__c` (`BY_CRITERIA` / `BY_ID`) is the discriminant
between the two tabs. It replaced a `LIKE 'BY_ID%'` read of the brand-filter label — a
display field used as data, which renaming would have broken. Logs written before the field
existed have it blank, and the queries fall back to the old test for those.

---

## 7. Known limitations

- **No resume.** The step plan lives only in the serialized batch state. If the job dies —
  storage limit, a deployment mid-run, a platform incident — the remaining plan goes with
  it and the run must be restarted from the beginning.
- **Failed records are not individually traceable past 200 errors.** The counters are
  exact; the identities are not, beyond the cap.
- **Coverage is whatever is configured.** Nothing enumerates the PII the configuration does
  *not* cover. Objects such as Task, Event and Chatter feeds are absent unless someone adds
  them.
- **The ALH configuration is not consolidated.** The TEKCO set was merged — 26 pairs of
  `IndividualP_X` + `Patient_X` became one `Account_X` carrying both record types, 77 records
  down to 51. The 21 `ALH_*` records belong to the Portugal org and were left as they are; five
  of their `(object, field)` pairs are still spelled out once per record type and could be
  merged the same way whenever that org is ready.
- **Two different filters on one object are not discriminated per record.** A run reads their
  union and applies every rule to all of it, because Apex can re-check a record type but not a
  filter that walks a relationship. It is only observable when the rules behind the two filters
  do different things — `Address.Street` has the same field and pattern behind both, so nothing
  is wrong there. `validateFilterDiscrimination()` reports the case if it ever arises.
- **Asset Files cannot be deleted** by the ContentDocument phase.
- **Aborting a job by hand leaves the bypass raised.** `finish()` never runs, so nothing
  restores it — see [`DEPLOYMENT_AND_USAGE.md`](DEPLOYMENT_AND_USAGE.md) for the manual recovery.
