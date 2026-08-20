# Deploying to a Non-Standard Org

## When to use this document

`DEPLOYMENT_AND_USAGE.md` covers deployment to a **standard org** — one following the TEKCO
schema conventions: brands as a picklist on `Account`, `TEKCO_FunctionalId__c` as the
functional identifier, `TEKCO_BypassSettings__c` driving automation bypass.

Use **this** document when the target org departs from any of those conventions. It replaces
sections 1.1 to 1.5 of the standard guide for such orgs. Everything after that — using the
interface, configuring rules, monitoring runs — applies unchanged.

The Portugal (ALH) org is the worked example throughout, but nothing here is Portugal-specific.

---

## At a glance

Five steps to get a non-standard org running. Do them in order; each is detailed below.

| # | Step | Frequency |
|---|---|---|
| **1** | [Prerequisites](#1-prerequisites) — permissions, storage, an org config record | Once, then re-check after each refresh |
| **2** | [Deploy the package](#2-deploying-the-package) — the org's own manifest, never `package.xml` | Each deployment |
| **3** | [Post-deployment steps](#3-post-deployment-steps) — permission set, tab, field history | Each deployment |
| **4** | [Sandbox refresh checklist](#4-sandbox-refresh-checklist) | After every refresh |
| **5** | [Access the interface](#5-accessing-the-interface) and verify | Each deployment |

Everything from section 6 onwards is reference material: how the configuration works, what
each field drives, the Portugal example, and troubleshooting.

---

# Part 1 — Deployment

## 1. Prerequisites

Everything in **§1.1 of `DEPLOYMENT_AND_USAGE.md`** still applies — in particular enabling
**Delete Field History**, without which history records are silently left in place. The
following are additional, and specific to a non-standard org.

### The org must be a sandbox

The tool refuses to run in production: `assertIsSandbox()` blocks every entry point. Deploying
to production is harmless, but nothing can be launched there.

### An org config record must exist and match this org's domain

A `TEKCO_AnonymizationOrgConfig__mdt` record must carry this org's domain prefix in
`TEKCO_OrgDomain__c`. Read the value from **Developer Console → Execute Anonymous**:

```apex
System.debug(URL.getOrgDomainUrl().getHost().substringBefore('.'));
```

> **If no record matches, nothing fails.** The service silently falls back to the standard
> TEKCO defaults, and the org behaves as if it were a standard one — empty brand list, wrong
> functional ID field. See [section 6](#6-what-makes-an-org-non-standard-and-how-it-is-resolved).

If this org has no config record yet, do [section 11](#11-onboarding-an-org-that-has-no-config-yet) first.

### Every custom permission the permission set grants must exist in the org

`TEKCO_AnonymizationAdmin` grants custom permissions that may belong to other applications
(`CXFCO_BypassCustomValidations`, `CXFCO_BypassOutboundSynchronization`). If the org does not
own them, deployment fails with:

```
In field: customPermission - no CustomPermission named ... found
```

The fix is to ship the missing definitions in this org's manifest — see
[section 11, step 4](#step-4--supply-any-missing-custom-permissions).

### The org must have free data storage

A run begins by inserting an audit log record. At 100% data storage that insert fails with
`STORAGE_LIMIT_EXCEEDED`, and since it precedes `Database.executeBatch()`, the run never
starts and leaves no audit record behind. See [section 14](#14-troubleshooting).

---

## 2. Deploying the package

A non-standard org is deployed from **its own standalone manifest**, in a single command:

```bash
sf project deploy start --manifest anonymization/manifest/package-<Org>.xml --target-org <alias>
```

For Portugal:

```bash
sf project deploy start --manifest anonymization/manifest/package-Portugal.xml --target-org <portugal-alias>
```

> **Do not deploy `package.xml` to a non-standard org.** It carries the standard TEKCO field
> configs, which name objects and fields that do not exist there, and the standard org config
> records. The org-specific manifest is self-contained: Apex, LWC, objects, layouts, the tab
> and application, the permission set, the custom permissions, the shared patterns, and this
> org's own field configs and org config record.

Because manifest-driven deploys only take the members they list, the separation works both
ways: org-specific records never leak into a standard org, and standard field configs never
reach this one.

---

## 3. Post-deployment steps

### Step 1 — Assign the permission set

Grant **TEKCO Anonymization Admin** to every user who needs the tool
(**Setup → Users → Permission Set Assignments**).

### Step 2 — Make the tab reachable

If the manifest ships a dedicated Lightning application — Portugal ships
`Data_Anonymization` — the **TEKCO Data Anonymization** tab is already in it, and there is
nothing to do. Otherwise add the tab to an existing app via **Setup → App Manager →
Navigation Items**.

### Step 3 — Enable Delete Field History

Org level (**Setup → User Interface**) *and* on the permission set (**System Permissions →
Delete Field History**). Both are required; see §1.1 of the standard guide.

### Step 4 — Confirm the org config matched

Open the tool and check that the **Brands** list is populated. This is the fastest proof that
`TEKCO_OrgDomain__c` matched: an empty list almost always means it did not.

---

## 4. Sandbox refresh checklist

After each refresh the org reverts to production state. Repeat:

- [ ] **Re-read the org domain prefix** — it changes with the sandbox name:
      `System.debug(URL.getOrgDomainUrl().getHost().substringBefore('.'));`
- [ ] **Update `TEKCO_OrgDomain__c`** in the org config record if the value changed, and commit it.
- [ ] Redeploy: `sf project deploy start --manifest anonymization/manifest/package-<Org>.xml --target-org <alias>`
- [ ] Reassign the **TEKCO Anonymization Admin** permission set.
- [ ] Re-enable **Delete Field History**, org level and permission set.
- [ ] Verify the tab appears in the navigation app.
- [ ] Confirm the **Brands** list is populated — proves the domain still matches.
- [ ] Run a **Preview Scope** to check counts before launching anything.

> The first two items are the ones that do not exist in the standard guide, and the ones most
> often missed. A refreshed sandbox with a stale domain value looks fully deployed and behaves
> like a standard org.

---

## 5. Accessing the interface

The tool lives on the **TEKCO Data Anonymization** tab.

> **Prerequisite:** you must hold the **TEKCO Anonymize Data** custom permission, granted by
> the **TEKCO Anonymization Admin** permission set. The LWC reads it directly
> (`@salesforce/customPermission/TEKCO_AnonymizeData`), so without it the interface does not
> render.

Two tabs, as in a standard org:

- **By Criteria** — anonymization by brand, object and record type
- **By ID (DataMig)** — targeted anonymization from an explicit list of IDs

Verify in this order, stopping at the first failure:

1. The tab opens → the custom permission is granted.
2. The **Brands** list is populated → the domain matched and brand resolution works.
3. **Preview Scope** returns plausible counts → scope building and brand traversal work.
4. A run on a handful of records produces the expected values → see
   [section 12](#12-worked-example--portugal-alh).

---

# Part 2 — Reference

## 6. What makes an org non-standard, and how it is resolved

The package absorbs three kinds of divergence through configuration alone. No code fork is
needed, and none should ever be created.

| Axis | Standard org | Non-standard example (Portugal) |
|---|---|---|
| **Brand** | `TEKCO_Brand__c` picklist on `Account` | records of a lookup object, `ALH_Brand__c` |
| **Identifiers** | `TEKCO_FunctionalId__c`, `TEKCO_ExternalId__c` | `ALH_FunctionalId__c`, `ALH_ExternalSystemID__c` |
| **Automation bypass** | `TEKCO_BypassSettings__c` hierarchy custom setting | not used at all |

Any other difference — a different set of objects and fields to anonymize — is expressed with
`TEKCO_AnonymizationFieldConfig__mdt` records, exactly as in a standard org.

### How the org is identified

`TEKCO_AnonymizationOrgConfigService.getConfig()` reads the running org's domain prefix and
queries `TEKCO_AnonymizationOrgConfig__mdt WHERE TEKCO_OrgDomain__c = :currentDomain`. The
result is cached for the transaction.

**When no record matches, the service falls back to the standard TEKCO defaults silently** —
no error, no warning, no log entry. A typo in `TEKCO_OrgDomain__c` therefore does not fail; it
produces an org that behaves as if it were standard. Whenever something looks inexplicably
"not configured", check this value first.

---

## 7. `TEKCO_AnonymizationOrgConfig__mdt` field reference

| Field | Required | Purpose | Portugal value |
|---|---|---|---|
| `TEKCO_OrgDomain__c` | Yes | Domain prefix this record applies to | `airliquidehomecare--preprod` |
| `TEKCO_BypassObjectApiName__c` | Optional | Hierarchy Custom Setting whose flags are raised during a run. **Blank = no bypass at all**; set = bypass through the named setting. Orgs without a config record default to `TEKCO_BypassSettings__c` | *(blank — no bypass)* |
| `TEKCO_FunctionalIdField__c` | Yes | Functional identifier field on anonymized records | `ALH_FunctionalId__c` |
| `TEKCO_BrandObjectApiName__c` | If brand is a lookup | Brand SObject. Leave blank for picklist mode | `ALH_Brand__c` |
| `TEKCO_BrandCodeField__c` | If brand object set | Field holding the brand code shown in the UI | `Name` |
| `TEKCO_BrandCountryField__c` | If brand object set | Field holding the country | `Country__c` |
| `TEKCO_BrandLookupFieldOnRecord__c` | If brand object set | Relationship field on anonymized records pointing at the brand | `ALH_Brand__r` |
| `TEKCO_ExternalIdFields__c` | Optional | Comma-separated external ID fields for this org | `ALH_ExternalSystemID__c` |

`TEKCO_BrandLookupFieldOnRecord__c` is the **relationship** name (`__r`), because it is used
for cross-object traversal in SOQL. The code derives the `__c` form where it needs the field.

---

## 8. What the configuration drives at runtime

Useful when a value looks wrong and you need to know where it takes effect.

| Field | Where it acts |
|---|---|
| `TEKCO_BrandObjectApiName__c`, `TEKCO_BrandCodeField__c`, `TEKCO_BrandCountryField__c` | `TEKCO_AnonymizationController.getBrands()` — populates the Brands multi-select; and `getCountriesForBrands()` |
| `TEKCO_BrandLookupFieldOnRecord__c` | Scope building in `TEKCO_AnonymizationBatch`, `TEKCO_ContentDocumentBatch`, `TEKCO_FieldHistoryBatch` and the preview count — becomes `ALH_Brand__r.Name IN (...)` |
| `TEKCO_FunctionalIdField__c` | `TEKCO_AnonymizationPatternService`, second step of the identifier chain |
| `TEKCO_ExternalIdFields__c` | The By ID tab's external ID selector, **and** the identifier fallback below |
| `TEKCO_BypassObjectApiName__c` | `TEKCO_AnonymizationBypassService` — blank makes the service inert end to end; set, it raises/restores that setting's flags around the run |

### The identifier resolution chain

Patterns that embed an identifier (`EMAIL_PLUS_EXTERNALID`, its `_SUBDOMAIN` variant, and
`NAME_FIRST_LETTER`) resolve it in this order:

1. The field named on the pattern record (`TEKCO_ExternalIdField__c`, normally `TEKCO_ExternalId__c`)
2. **The fields listed in this org's `TEKCO_ExternalIdFields__c`**
3. The functional ID field — `NAME_FIRST_LETTER` only
4. The Salesforce record Id, as a last resort

Step 2 is what lets a non-standard org key on its own identifier without any per-org pattern
record. Candidates are rejected unless they match `^[a-zA-Z0-9_\-]+$`, so an unsafe value
degrades to the next step rather than corrupting an email address.

Patterns naming `Id` outright — `EMAIL_PLUS_SFID`, `NAME_FIRST_LETTER_SFID` and the subdomain
variants — are excluded from step 2 by design: they mean the record Id and must never drift
onto a business identifier.

---

## 9. Metadata the package tolerates being absent

Two objects belong to the wider TEKCO configuration and are **not** deployed by this package:

| Object | Used for | Behaviour when absent |
|---|---|---|
| `TEKCO_BypassSettings__c` | Raising automation bypass flags during a run | The bypass step is skipped entirely |
| `TEKCO_CountryBrandSetting__mdt` | Brand-to-country mapping in picklist brand mode | Country resolution returns nothing |

Both are reached **dynamically**, by API name behind a describe guard, so the package compiles
and deploys in orgs that do not own them.

> **Rule, not a preference:** never reintroduce a typed Apex reference to either object. Apex
> resolves those at compile time, so a branch that never executes at runtime is still enough to
> make the whole package undeployable in an org lacking the object. The runtime guards
> (a blank `TEKCO_BypassObjectApiName__c`, `usesBrandObject()`) do not protect against this.

---

## 10. Pattern authoring rule

`TEKCO_AnonymizationPatternService` dispatches with `switch on patternType` over **hard-coded
string literals**. A pattern's `DeveloperName` is a dispatch key, not a label.

A `TEKCO_AnonymizationPattern__mdt` record whose DeveloperName is not one of the recognised
values falls through to the implicit `REGEX` default. If it carries no `TEKCO_RegexFind__c` and
no `TEKCO_RegexReplace__c`, the value is returned **unchanged** — the field is not anonymized,
the run still reports **Success**, and nothing reports a problem anywhere.

**Never create an org-specific copy of a pattern.** To adapt a pattern to an org, use
configuration: the identifier chain in section 8 already covers the common case. The
recognised DeveloperNames are listed in the header comment of
`TEKCO_AnonymizationPatternService`.

---

## 11. Onboarding an org that has no config yet

One-time setup, before the deployment described in Part 1.

### Step 1 — Read the org domain prefix

```apex
System.debug(URL.getOrgDomainUrl().getHost().substringBefore('.'));
```

### Step 2 — Create the org config record

Add `anonymization/main/default/customMetadata/TEKCO_AnonymizationOrgConfig.<Name>.md-meta.xml`,
filling the fields from section 7. Use the value from step 1 verbatim.

### Step 3 — Create the field configs

One `TEKCO_AnonymizationFieldConfig__mdt` record per field to anonymize, naming the org's own
objects, fields and record types. Prefix the DeveloperNames (e.g. `ALH_`) so they are easy to
select in a manifest and never collide with the standard set.

### Step 4 — Supply any missing custom permissions

If the permission set grants custom permissions the org does not own, add their definitions to
the repository and to this org's manifest. A `CustomPermission` file is four lines; with no
assignment and no rule consulting it, an unused one is inert.

### Step 5 — Build the manifest

Create `anonymization/manifest/package-<Org>.xml` as a standalone package: Apex classes, LWC,
objects and layouts, permission set, tab and application, custom permissions, shared patterns,
this org's field configs, and its org config record. Keep it separate from `package.xml`.

Then follow Part 1.

---

## 12. Worked example — Portugal (ALH)

### Configuration

Record `ALH_Portugal`, in
`anonymization/main/default/customMetadata/TEKCO_AnonymizationOrgConfig.ALH_Portugal.md-meta.xml`:

| Field | Value |
|---|---|
| `TEKCO_OrgDomain__c` | `airliquidehomecare--preprod` |
| `TEKCO_FunctionalIdField__c` | `ALH_FunctionalId__c` |
| `TEKCO_BrandObjectApiName__c` | `ALH_Brand__c` |
| `TEKCO_BrandCodeField__c` | `Name` |
| `TEKCO_BrandCountryField__c` | `Country__c` |
| `TEKCO_BrandLookupFieldOnRecord__c` | `ALH_Brand__r` |
| `TEKCO_ExternalIdFields__c` | `ALH_ExternalSystemID__c` |

### Field configs

21 records across 4 objects.

| Developer name | Object | Field | Record type | Pattern | History |
|---|---|---|---|---|---|
| `ALH_Patient_FirstName` | Account | `FirstName` | Patient | `NAME_FIRST_LETTER` | yes |
| `ALH_Patient_LastName` | Account | `LastName` | Patient | `NAME_FIRST_LETTER` | yes |
| `ALH_Patient_PersonEmail` | Account | `PersonEmail` | Patient | `EMAIL_PLUS_EXTERNALID` | yes |
| `ALH_Patient_PersonHomePhone` | Account | `PersonHomePhone` | Patient | `PHONE_MASK` | yes |
| `ALH_Patient_PersonMobilePhone` | Account | `PersonMobilePhone` | Patient | `PHONE_MASK` | yes |
| `ALH_Patient_PersonMailingStreet` | Account | `PersonMailingStreet` | Patient | `ADDRESS_STREET_RANDOM` | yes |
| `ALH_Patient_Description` | Account | `Description` | Patient | `LOREM_IPSUM` | yes |
| `ALH_Patient_SocialSecurityNumber` | Account | `ALH_SocialSecurityNumber__c` | Patient | `SSN_SEQUENTIAL` | yes |
| `ALH_Prescriber_Email` | Account | `ALH_Email__c` | Prescriber | `EMAIL_PLUS_EXTERNALID` | yes |
| `ALH_Prescriber_PersonEmail` | Account | `PersonEmail` | Prescriber | `EMAIL_PLUS_EXTERNALID` | yes |
| `ALH_Prescriber_Phone` | Account | `Phone` | Prescriber | `PHONE_MASK` | yes |
| `ALH_Prescriber_PersonMobilePhone` | Account | `PersonMobilePhone` | Prescriber | `PHONE_MASK` | yes |
| `ALH_Prescriber_PersonMailingStreet` | Account | `PersonMailingStreet` | Prescriber | `ADDRESS_STREET_RANDOM` | yes |
| `ALH_HCI_Email` | Account | `ALH_Email__c` | Hospital | `EMAIL_PLUS_EXTERNALID` | yes |
| `ALH_HCI_Phone` | Account | `Phone` | Hospital | `PHONE_MASK` | yes |
| `ALH_HCI_FiscalNumber` | Account | `ALH_FiscalNumber__c` | Hospital | `CLEAR` | yes |
| `ALH_IndustriesBusiness_Email` | Contact | `Email` | IndustriesBusiness | `EMAIL_PLUS_EXTERNALID` | yes |
| `ALH_Case_Description` | Case | `Description` | — | `LOREM_IPSUM` | no |
| `ALH_Case_ContentDocument` | Case | — | — | `DELETE_CONTENT_DOCUMENT` | yes |
| `ALH_Address` | `ALH_Address__c` | `Street__c` | Patient_Address_Record_Type | `ADDRESS_STREET_RANDOM` | yes |
| `ALH_Prescription_ContentDocument` | `ALH_Prescription__c` | — | — | `DELETE_CONTENT_DOCUMENT` | yes |

Because `TEKCO_ExternalIdFields__c` is set, the five `EMAIL_PLUS_EXTERNALID` configs and the two
`NAME_FIRST_LETTER` configs key on `ALH_ExternalSystemID__c` — step 2 of the chain in
section 8 — rather than degrading to the Salesforce Id.

---

## 13. Known items to review

Observed in this repository at the time of writing. None breaks a deployment; all are worth
cleaning up.

1. **Two org config records coexist.** `ALH_Portugal` is the live one. `Portugal_ALH` is an
   earlier draft still carrying the `REPLACE_WITH_PORTUGAL_ORG_DOMAIN` placeholder. It matches
   no org so it is inert, but `manifest/package.xml` still deploys it to standard orgs.
2. **`package-Portugal.xml` has duplicate `<types>` blocks** — `CustomField` and
   `CustomMetadata` each appear twice.
3. **The header comment of `package-Portugal.xml`** still instructs the reader to fill in
   `TEKCO_OrgDomain__c`, which is already set in `ALH_Portugal`.

---

## 14. Troubleshooting

**The Brands list is empty.**
The domain in `TEKCO_OrgDomain__c` does not match the org (silent fallback — see section 6), or
`TEKCO_BrandCodeField__c` / `TEKCO_BrandCountryField__c` do not match the real field API names
on the brand object. Check the domain first; it is by far the more common cause, and the most
likely one right after a sandbox refresh.

**Deployment fails with `no CustomPermission named ... found`.**
The permission set grants a custom permission owned by another application that the target org
does not have. Ship the definition in this org's manifest — section 11, step 4.

**`STORAGE_LIMIT_EXCEEDED` when launching a run.**
The org is at 100% data storage. `insert auditLog` runs *before* `Database.executeBatch()` in
`startAnonymization()`, so the run never starts and no audit log record is created at all.
Free space with a Bulk API **hard delete**, which bypasses the recycle bin — an ordinary delete
frees nothing until the bin is emptied. Anonymization cannot free storage itself: it performs
updates, not deletes.

**Fields come through a run unchanged, yet the status is Success.**
The pattern's DeveloperName is not recognised by the dispatch and fell through to `REGEX` with
no regex configured — section 10. Compare field values before and after; do not rely on the run
status.

**An error toast with no usable message.**
The exception may come from the Lightning container rather than from Apex — a stack made
entirely of `aura_prod.js` frames is platform noise, not a tool failure. Confirm with a debug
log: no `EXCEPTION_THROWN` or `FATAL_ERROR` means Apex raised nothing.

**Children not resolved in By ID mode.**
`TEKCO_ParentObjectApiName__c` must be the exact parent SObject API name, and
`TEKCO_ParentLookupFieldApiName__c` the lookup field's API name (`AccountId`, not `Account`).
