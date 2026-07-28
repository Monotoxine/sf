# Anonymization Hardening — Test Plan

Verification guide for the changes between commits `2d7553c` and `74861b0`.

Each case states the symptom that existed before, what changed, how to reproduce it, and
what you should now see. Work through them in order — the setup cases at the top make the
later ones easier.

**Deploy first:**

```bash
sf project deploy start --manifest anonymization/manifest/package-hardening.xml \
  --dry-run --test-level RunLocalTests
```

Drop `--dry-run` once it validates clean.

---

## Case 0 — Deployment and unit tests

**Test**

```bash
sf project deploy start --manifest anonymization/manifest/package-hardening.xml
sf apex run test --test-level RunLocalTests --result-format human --code-coverage --wait 20
```

**Expected**: all classes deploy; the anonymization test classes pass.

**Note**: this code has never been compiled against a real org — everything below was
verified by static analysis only. Expect to fix a compile error or two on the first deploy.
That is the single most valuable thing you can do before testing anything else.

---

# Group A — Errors you were actually seeing

## Case 1 — "Batchable instance is too big"

**Symptom before**: intermittent emails reading
`System.LimitException: Batchable instance is too big: TEKCO_AnonymizationBatch`.
The batch stopped partway; records already processed stayed anonymized, the rest were never
touched, and Phases 2 and 3 never ran.

**Cause**: `Database.Stateful` serializes every instance variable between each `execute()`
chunk. The batch carried full `TEKCO_AnonymizationFieldConfig__mdt` SObject lists
(`fieldConfigs`, `contentDocConfigs`, `historyConfigs`) plus a growing `accumulatedErrors`
list. The combination crossed the platform limit — which is why it appeared on error-heavy
runs and not on clean ones.

**Change**: only `DeveloperName` strings are held in state; the CMDT objects are re-queried
where actually needed (`start()` / `finish()`). CMDT is platform-cached, so the re-query is
effectively free. Applied to **both** chains.

**Test**
1. Launch a By Criteria run over several objects with a large scope — ideally one that
   previously produced the error.
2. Watch **Setup → Apex Jobs**.

**Expected**: no "Batchable instance is too big"; the job progresses through every object and
chains into Phase 2 and Phase 3.

**Still possible**: on a **By ID** run only, the record-ID maps are still passed through the
chain and do scale with resolved record count. See Case 16.

---

## Case 2 — "invalid parameter value" on Address records

**Symptom before**: audit log errors like
`0017T000002hsV3QAI: invalid parameter value`.

**Cause**: some records store a base64 external ID such as
`￾A3V000000HOpx9qTwhACXrdZav9Yk3DPFn7UxEWfQ/OYkT8/DugsYlq8=￿`. Fed into an email or name
pattern, that produced a value Salesforce rejected.

**Change**: `getExternalId()` now rejects anything outside `[a-zA-Z0-9_-]` and returns empty,
so the existing fallback chain takes over: external ID → functional ID → Salesforce record Id
(always safe).

**Test**
1. Find a record whose external ID field holds a base64 value (Address records, `0017T` prefix).
2. Run anonymization over it with an `EMAIL_PLUS_EXTERNALID` or `NAME_FIRST_LETTER` pattern.
3. Inspect the resulting field value.

**Expected**: no "invalid parameter value"; the anonymized value contains the **Salesforce
record Id** instead of the base64 string. Records with clean alphanumeric external IDs
(`EXT001`, `ALH-12345`) are unchanged from before.

---

# Group B — Wrong numbers in the audit log

## Case 3 — Failure count only reported the last object

**Symptom before**: a run across 8 objects failing thousands of records showed only the last
object's failures in `TEKCO_RecordsFailed__c`. Processed counts were correct, which made the
discrepancy easy to miss.

**Cause**: every `finish()` totalled `accumulatedRecordsProcessed + recordsProcessed` but
passed the **local** `recordsFailed`. No `accumulatedRecordsFailed` parameter existed anywhere.

**Change**: added to all six batch constructors and totalled the same way as processed.

**Test**
1. Run By Criteria over **at least two objects** where both will produce failures.
   (Easiest on the Portugal org, where validation rules fire because bypass is disabled.)
2. Open the audit log record.

**Expected**: `TEKCO_RecordsFailed__c` is the **sum across all objects**, not just the last.
Cross-check against the number of distinct record IDs in `TEKCO_ErrorMessage__c`.

---

## Case 4 — Counts frozen during Phase 2 and Phase 3

**Symptom before**: during long document/history deletion phases the audit log showed stale
numbers until the whole chain finished.

**Cause**: only Phase 1 called `markRunning()` after chaining.

**Change**: added to all four delete batches, with an explicit `return` in the terminal branch
so it cannot overwrite a finished status.

**Test**
1. Launch a run with a large `DELETE_CONTENT_DOCUMENT` scope.
2. Refresh the audit log record repeatedly while Phase 2 runs.

**Expected**: `TEKCO_DocumentsDeleted__c` climbs during the phase; status stays `Running` until
the chain genuinely ends, then flips to `Success`/`Partial` **once** and stops changing.

---

## Case 5 — ServiceReport deletions invisible

**Symptom before**: ServiceReports were deleted but never counted, and their failures never
appeared anywhere.

**Change**: their `DeleteResult`s are now counted into `recordsDeleted` and failures captured
with a `ServiceReport <id>:` prefix.

**Test**: run Phase 2 against an object with ServiceReports attached.

**Expected**: `TEKCO_DocumentsDeleted__c` includes them; any failure appears in the error
column tagged `ServiceReport`.

---

# Group C — Silent failures now surfaced

## Case 6 — Misconfigured pattern type did nothing, silently

**Symptom before**: a field configured with a typo'd `TEKCO_PatternType__c`, or one whose
pattern record had been deactivated, was **skipped entirely**. The field kept its real PII and
nothing anywhere said so. This is the most dangerous bug fixed in this batch.

**Cause**: one line in `TEKCO_AnonymizationExecuteService` —
`if (pattern == null || !pattern.TEKCO_IsActive__c) continue;`

**Change**: both controllers call `validatePatternTypes()` at launch and seed warnings into the
audit log. The run still processes the valid configs.

**Test**
1. Edit a `TEKCO_AnonymizationFieldConfig__mdt` record and set `TEKCO_PatternType__c` to
   something that does not exist, e.g. `NOT_A_PATTERN`.
2. Launch a run covering that object.
3. Open the audit log's `TEKCO_ErrorMessage__c`.

**Expected**: a warning naming the type and an example field:
`Config warning: pattern type "NOT_A_PATTERN" has no active TEKCO_AnonymizationPattern__mdt
record. Fields using it will be left unchanged (e.g. Account.Name).`
Other fields still anonymize normally.

**Also worth testing**: deactivate a real pattern record (`TEKCO_IsActive__c = false`) and
confirm the same warning appears.

---

## Case 7 — Production guard left runs orphaned

**Symptom before**: if `assertIsSandbox()` tripped inside a batch, the job died with the audit
log stuck on `Running` forever **and every bypass flag left switched on** for that user.

**Change**: the guard now closes the log as `Failed`, restores bypass, and returns an empty
locator. A follow-up fix (found by the new tests) stops `finish()` from then re-finalizing the
same log as `Success`.

**Test** — safest in a sandbox using the test class, since you should not run this against
production. `TEKCO_AnonymizationBatchTest.batch_onProduction_closesLogAsFailed` covers it by
stubbing `isSandboxCached = false`.

**Expected**: status `Failed`, error message mentioning production, and — critically — the
status does **not** later flip to `Success`.

---

## Case 8 — Empty catch blocks

**Symptom before**: nine `catch (Exception e) {}` blocks swallowed everything. The worst was
`TEKCO_AnonymizationAuditService.persist()` — if the audit log update itself failed, the run
reported nothing at all and left no trace.

**Change**: every one now logs at `ERROR` or `WARN`.

**Test**: enable Apex debug logs for your user and run an anonymization.

**Expected**: any bypass-restore or audit-persist failure appears in the log rather than
vanishing. On a healthy run you should see nothing — absence of output is the good case here.

---

# Group D — Security

## Case 9 — Unauthenticated endpoint with SOQL injection

**Symptom before**: `resolveIds()` had **no permission check at all** and passed
client-supplied object and field names straight into `Database.query()`. Any authenticated
user with Apex access could read arbitrary objects and fields.

**Change**: all 12 `@AuraEnabled` methods now call `assertCanAnonymize()` first. Object names
are resolved against the configured set; field names are checked with describe.

**Test**
1. Log in as a user **without** the `TEKCO_AnonymizeData` custom permission.
2. Open the anonymization tab and try the By ID tab.

**Expected**: a clear "Permission denied" message rather than data. Confirm a user **with**
the permission still works normally — this is the regression risk.

**Also test**: with permission, enter an object in the By ID external-ID mode that is not in
your CMDT config. Expect `Object is not configured for anonymization: X` rather than a query.

---

## Case 10 — Sharing declarations

**Change**: the six batches are now explicitly `without sharing`, with a comment explaining
why — anonymization must reach every record in scope, and running `with sharing` would
silently skip records the launching user cannot see, leaving PII in place. The six services are
`inherited sharing`; both controllers stay `with sharing`.

**Test**: run anonymization as a user whose sharing rules hide some records in scope.

**Expected**: those records **are** anonymized. If you would rather they be skipped, tell me —
this was my judgement call and it is a one-line change per class to reverse.

---

# Group E — Limits and performance

## Case 11 — Phase 2 hitting the DML ceiling

**Symptom before**: an execute chunk covering 500 parents that each owned many files could
resolve more than 10 000 documents and die on the DML row limit, killing the chunk.

**Change**: deletes are sliced against the **remaining** DML row budget and stop when it is
exhausted, reporting the shortfall instead of throwing. Batch scope also dropped from 500
parents to 100.

**Test**: run Phase 2 against an object whose records own many attachments/files.

**Expected**: no `LimitException`. If the budget is exhausted you get an explicit message:
`ContentDocument: DML row limit reached, N record(s) not deleted. Re-run the anonymization to
remove the remainder.` Re-running then clears the rest.

---

## Case 12 — Describe calls in loops

**Change**: `hasField()` now caches its field maps (it was called 3× per object in preview
counts, in a loop in external-ID resolution, and repeatedly in every batch `start()`). The
bypass service describes its fields once instead of per field per call.

**Test**: open the anonymization tab and select many objects, then hit Preview.

**Expected**: preview returns noticeably faster, same numbers as before. Purely an internal
change — no behaviour should differ.

---

# Group F — Refactors to sanity-check for regressions

These changed no behaviour by intent. Test them to confirm that is true.

## Case 13 — Phase 2 and Phase 3 logic extracted into services

Both By-ID delete batches previously held byte-identical copies of their By-Criteria twins'
`execute()` — the comments literally read *"Identical to ..."*. Now shared via
`TEKCO_ContentDocumentDeleteService` and `TEKCO_FieldHistoryDeleteService`.

**Test**: run a full chain **on both tabs** (By Criteria and By ID) with content-document and
history configs active.

**Expected**: identical deletion behaviour and counts on both paths.

## Case 14 — `TEKCO_FieldHistoryByIdBatch.start()` crash

Unlike its twin it had no `try/catch` and emitted `WHERE Field IN ()` when no history fields
were configured — a `QueryException` that killed the batch with no audit update and no bypass
restore.

**Test**: run a By ID anonymization where the object has `TEKCO_DeleteHistory__c = true` but no
field API names resolve.

**Expected**: the phase is skipped with
`No history fields configured for object, skipped: X` and the chain continues.

## Case 15 — Shared helpers consolidated

`toDevNames`, `cap`, `loadFieldConfigs`, `loadFieldConfigsByDevNames`, `buildPatternMap` and
`popConfigsForObject` now live only in `TEKCO_AnonymizationBatchUtils`; `getFieldConfigs()`
lost a duplicated SELECT.

**Test**: open the admin UI. Confirm the brand, object, record-type and field-config pickers
all populate, and that selecting no objects still lists **all** configured objects (that path
changed from a separate query to a bound filter).

---

# Known limitations — not fixed

## Case 16 — By ID record maps still scale with scope

`contentDocIdsByObject`, `historyIdsByObject` and `remainingObjectIds` are still passed through
the By ID chain and serialized on every chunk. At ~50 000 resolved records that is roughly
900 KB per chunk. The scope is **not** bounded by what you paste, because `resolveChildIds()`
expands to child records without a limit — 100 pasted Account IDs can become tens of thousands.

**Watch for**: "Batchable instance is too big" on By ID runs specifically. If you see it,
measure `TEKCO_RecordsProcessed__c` on recent By ID runs; fixing it means persisting the scope
to a staging object rather than carrying it in state.

## Case 17 — Preview counts can disagree with processed counts

`getPreviewCounts()` applies a Record Type filter that the batches do not, so previewed numbers
may exceed what actually gets processed. The underlying cause is that the brand / country /
parent-lookup WHERE-clause logic is written **four separate times** and has drifted.
Consolidating it into one filter builder is the remaining review item.

**Watch for**: preview saying N, audit log reporting fewer.

## Case 18 — Testability of field transformation

The serialization fix means batches re-query CMDT inside `execute()`. Custom Metadata cannot be
inserted in a test, so the batch tests cannot control what those re-queries return and do not
assert field-level transformation. That is covered instead by
`TEKCO_AnonymizationExecuteServiceTest`, which takes configs as parameters. Batch chaining is
likewise untested — only one `Database.executeBatch` may run per test.

---

# Quick regression checklist

| # | Case | Pass |
|---|------|------|
| 0 | Deploys and unit tests pass | ☐ |
| 1 | Large multi-object run, no "instance too big" | ☐ |
| 2 | Base64 external ID falls back to record Id | ☐ |
| 3 | Failure count sums across all objects | ☐ |
| 4 | Counts update during Phase 2/3 | ☐ |
| 5 | ServiceReport deletions counted | ☐ |
| 6 | Bad pattern type warns in audit log | ☐ |
| 7 | Production guard closes log as Failed | ☐ |
| 9 | User without permission is blocked | ☐ |
| 9b | User with permission still works | ☐ |
| 11 | Many-file object completes Phase 2 | ☐ |
| 13 | By Criteria and By ID delete identically | ☐ |
| 15 | Admin UI pickers all populate | ☐ |
