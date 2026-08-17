# Deploying to a Non-Standard Org

## When to use this document

`DEPLOYMENT_AND_USAGE.md` covers deployment to a **standard org** — one that follows the
TEKCO schema conventions: brands as a picklist on `Account`, `TEKCO_FunctionalId__c` as the
functional identifier, `TEKCO_BypassSettings__c` driving automation bypass.

Use **this** document when the target org departs from any of those conventions. It replaces
sections 1.2, 1.3 and 1.15 of the standard guide for such orgs; everything else there —
using the interface, configuring rules, monitoring runs — still applies unchanged.

The Portugal (ALH) org is the worked example throughout, but nothing here is Portugal-specific:
the same procedure onboards any org with its own schema.

---

## 1. What makes an org non-standard

The package absorbs three kinds of divergence through configuration alone. No code fork is
needed, and none should ever be created.

| Axis | Standard org | Non-standard example (Portugal) |
|---|---|---|
| **Brand** | `TEKCO_Brand__c` picklist on `Account` | records of a lookup object, `ALH_Brand__c` |
| **Identifiers** | `TEKCO_FunctionalId__c`, `TEKCO_ExternalId__c` | `ALH_FunctionalId__c`, `ALH_ExternalSystemID__c` |
| **Automation bypass** | `TEKCO_BypassSettings__c` hierarchy custom setting | not used at all |

Anything beyond these three axes — a different set of objects and fields to anonymize — is
expressed with `TEKCO_AnonymizationFieldConfig__mdt` records, exactly as in a standard org.

---

## 2. How the mechanism works

`TEKCO_AnonymizationOrgConfigService.getConfig()` reads the running org's domain prefix and
looks for the matching `TEKCO_AnonymizationOrgConfig__mdt` record:

```apex
URL.getOrgDomainUrl().getHost().substringBefore('.')   // e.g. "airliquidehomecare--preprod"
```

It then queries `TEKCO_AnonymizationOrgConfig__mdt WHERE TEKCO_OrgDomain__c = :currentDomain`.
The result is cached for the transaction.

> **The single most important consequence:** when no record matches, the service falls back to
> the standard TEKCO defaults **silently**. There is no error, no warning, and no log entry.
> A typo in `TEKCO_OrgDomain__c` therefore does not fail — it produces an org that behaves as
> if it were standard: an empty brand list, the wrong functional ID field, and a bypass
> attempt against an object that does not exist.
>
> When something looks inexplicably "not configured", check the domain value first.

Confirm the resolved domain from **Developer Console → Execute Anonymous**:

```apex
System.debug(URL.getOrgDomainUrl().getHost().substringBefore('.'));
```

Note that the domain prefix changes with the sandbox name. **Every sandbox refresh or rename
requires this value to be re-checked**, and the record redeployed if it changed.

---

## 3. `TEKCO_AnonymizationOrgConfig__mdt` field reference

| Field | Required | Purpose | Portugal value |
|---|---|---|---|
| `TEKCO_OrgDomain__c` | Yes | Domain prefix this record applies to | `airliquidehomecare--preprod` |
| `TEKCO_FunctionalIdField__c` | Yes | Functional identifier field on anonymized records | `ALH_FunctionalId__c` |
| `TEKCO_BypassEnabled__c` | Yes | Whether to raise the bypass flags during a run | `false` |
| `TEKCO_BrandObjectApiName__c` | If brand is a lookup | Brand SObject. Leave blank for picklist mode | `ALH_Brand__c` |
| `TEKCO_BrandCodeField__c` | If brand object set | Field holding the brand code shown in the UI | `Name` |
| `TEKCO_BrandCountryField__c` | If brand object set | Field holding the country | `Country__c` |
| `TEKCO_BrandLookupFieldOnRecord__c` | If brand object set | Relationship field on anonymized records pointing at the brand | `ALH_Brand__r` |
| `TEKCO_ExternalIdFields__c` | Optional | Comma-separated external ID fields for this org | `ALH_ExternalSystemID__c` |

`TEKCO_BrandLookupFieldOnRecord__c` is the **relationship** name (`__r`), because it is used
for cross-object traversal in SOQL. The code derives the `__c` form when it needs the field
itself.

---

## 4. What the configuration actually drives

Useful when a value looks wrong and you need to know where it takes effect.

| Field | Where it acts |
|---|---|
| `TEKCO_BrandObjectApiName__c`, `TEKCO_BrandCodeField__c`, `TEKCO_BrandCountryField__c` | `TEKCO_AnonymizationController.getBrands()` — populates the Brands multi-select; and `getCountriesForBrands()` |
| `TEKCO_BrandLookupFieldOnRecord__c` | Scope building in `TEKCO_AnonymizationBatch`, `TEKCO_ContentDocumentBatch`, `TEKCO_FieldHistoryBatch` and the preview count — becomes `ALH_Brand__r.Name IN (...)` |
| `TEKCO_FunctionalIdField__c` | `TEKCO_AnonymizationPatternService`, second step of the identifier chain |
| `TEKCO_ExternalIdFields__c` | The By ID tab's external ID selector, **and** the identifier fallback (below) |
| `TEKCO_BypassEnabled__c` | `TEKCO_AnonymizationBypassService` — when false, the service is inert end to end |

### The identifier resolution chain

Patterns that embed an identifier (`EMAIL_PLUS_EXTERNALID`, its `_SUBDOMAIN` variant, and
`NAME_FIRST_LETTER`) resolve it in this order:

1. The field named on the pattern record (`TEKCO_ExternalIdField__c`, normally `TEKCO_ExternalId__c`)
2. **The fields listed in this org's `TEKCO_ExternalIdFields__c`**
3. The functional ID field — `NAME_FIRST_LETTER` only
4. The Salesforce record Id, as a last resort

Step 2 is what lets a non-standard org key on its own identifier without any per-org pattern
record. Candidate values are rejected unless they match `^[a-zA-Z0-9_\-]+$`, so an unsafe
value degrades to the next step rather than corrupting an email address.

Patterns that name `Id` outright — `EMAIL_PLUS_SFID`, `NAME_FIRST_LETTER_SFID` and the
subdomain variants — are excluded from step 2 by design: they mean the record Id, and must
never drift onto a business identifier.

---

## 5. Metadata the package tolerates being absent

Two objects belong to the wider TEKCO configuration and are **not** deployed by this package:

| Object | Used for | Behaviour when absent |
|---|---|---|
| `TEKCO_BypassSettings__c` | Raising automation bypass flags for the duration of a run | The bypass step is skipped entirely |
| `TEKCO_CountryBrandSetting__mdt` | Brand-to-country mapping in picklist brand mode | Country resolution returns nothing |

Both are reached **dynamically**, by API name behind a describe guard, so the package compiles
and deploys in orgs that do not own them.

> **Rule, not a preference:** never reintroduce a typed Apex reference to either object. Apex
> resolves those at compile time, so a branch that never executes at runtime is still enough
> to make the whole package undeployable in an org that lacks the object. The runtime guards
> (`TEKCO_BypassEnabled__c = false`, `usesBrandObject()`) do not protect against this.

---

## 6. Pattern authoring rule

`TEKCO_AnonymizationPatternService` dispatches with `switch on patternType` over **hard-coded
string literals**. A pattern's `DeveloperName` is therefore a dispatch key, not a label.

A `TEKCO_AnonymizationPattern__mdt` record whose DeveloperName is not one of the recognised
values falls through to the implicit `REGEX` default. If that record carries no
`TEKCO_RegexFind__c` and no `TEKCO_RegexReplace__c`, the value is returned **unchanged** — the
field is not anonymized, the run still reports **Success**, and nothing anywhere reports a
problem.

**Never create an org-specific copy of a pattern** (`ALH_EMAIL_PLUS_EXTERNALID` and the like).
To adapt a pattern to an org, use configuration: the identifier chain in section 4 already
covers the common case. Recognised DeveloperNames are the ones listed in the header comment of
`TEKCO_AnonymizationPatternService`.

---

## 7. Onboarding a new non-standard org

### Step 1 — Read the org domain prefix

Run in Execute Anonymous on the target org:

```apex
System.debug(URL.getOrgDomainUrl().getHost().substringBefore('.'));
```

### Step 2 — Create the org config record

Add `anonymization/main/default/customMetadata/TEKCO_AnonymizationOrgConfig.<Name>.md-meta.xml`,
filling the fields from section 3. Use the value from step 1 verbatim.

### Step 3 — Create the field configs

One `TEKCO_AnonymizationFieldConfig__mdt` record per field to anonymize, naming the org's own
objects, fields and record types. Prefix the DeveloperNames (e.g. `ALH_`) so they are easy to
select in a manifest and never collide with the standard set.

Do **not** deploy the standard TEKCO field configs to this org: they name objects and fields
that do not exist there.

### Step 4 — Supply any missing custom permissions

`TEKCO_AnonymizationAdmin` grants custom permissions that may belong to other applications
(`CXFCO_BypassCustomValidations`, `CXFCO_BypassOutboundSynchronization`). If the target org
does not own them, the permission set fails to deploy with:

```
In field: customPermission - no CustomPermission named ... found
```

Ship the missing definitions in this org's manifest. A `CustomPermission` file is four lines,
and with no assignment and no rule consulting it, an unused one is inert.

### Step 5 — Build a dedicated manifest

Create `anonymization/manifest/package-<Org>.xml`: a **standalone** package containing the
Apex classes, the LWC, the objects and layouts, the permission set, the tab, the custom
permissions, this org's field configs and its org config record.

Keep it separate from `package.xml`. Manifest-driven deploys only take listed members, so the
org-specific records can never leak into a standard org, and the standard field configs never
reach this one.

### Step 6 — Deploy

```bash
sf project deploy start --manifest anonymization/manifest/package-<Org>.xml --target-org <alias>
```

### Step 7 — Assign and verify

Assign `TEKCO_AnonymizationAdmin`, then confirm, in this order:

1. The **TEKCO Data Anonymization** tab opens — proves `TEKCO_AnonymizeData` is granted, since
   the LWC reads `@salesforce/customPermission/TEKCO_AnonymizeData`.
2. The **Brands** list is populated — proves the domain matched and brand resolution works.
   An empty list almost always means the domain does not match.
3. **Preview Scope** returns plausible counts — proves scope building and the brand traversal.
4. A run on a handful of records produces the expected values — see section 9.

---

## 8. Worked example — Portugal (ALH)

### Configuration

Record `ALH_Portugal` in
`anonymization/main/default/customMetadata/TEKCO_AnonymizationOrgConfig.ALH_Portugal.md-meta.xml`:

| Field | Value |
|---|---|
| `TEKCO_OrgDomain__c` | `airliquidehomecare--preprod` |
| `TEKCO_FunctionalIdField__c` | `ALH_FunctionalId__c` |
| `TEKCO_BypassEnabled__c` | `false` |
| `TEKCO_BrandObjectApiName__c` | `ALH_Brand__c` |
| `TEKCO_BrandCodeField__c` | `Name` |
| `TEKCO_BrandCountryField__c` | `Country__c` |
| `TEKCO_BrandLookupFieldOnRecord__c` | `ALH_Brand__r` |
| `TEKCO_ExternalIdFields__c` | `ALH_ExternalSystemID__c` |

### Deployment

```bash
sf project deploy start --manifest anonymization/manifest/package-Portugal.xml --target-org <portugal-alias>
```

`package-Portugal.xml` is standalone: it carries the Apex, the LWC, the objects and layouts,
the `Data_Anonymization` application, the tab, the permission set, the three custom permissions
(including the two CXFCO definitions), the shared patterns, and the 21 `ALH_*` field configs
plus the `ALH_Portugal` record.

### Field configs

21 records, covering 4 objects.

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
section 4 — rather than degrading to the Salesforce Id.

---

## 9. Known items to review

Observed in this repository at the time of writing. None of them breaks a deployment; all are
worth cleaning up.

1. **Two org config records coexist.** `ALH_Portugal` is the live one. `Portugal_ALH` is an
   earlier draft still carrying the `REPLACE_WITH_PORTUGAL_ORG_DOMAIN` placeholder. It matches
   no org so it is inert, but `manifest/package.xml` still deploys it to standard orgs.
2. **`package-Portugal.xml` has duplicate `<types>` blocks** — `CustomField` and
   `CustomMetadata` each appear twice.
3. **The header comment of `package-Portugal.xml`** still instructs the reader to fill in
   `TEKCO_OrgDomain__c`, which is already set in `ALH_Portugal`.

---

## 10. Troubleshooting

**The Brands list is empty.**
The domain in `TEKCO_OrgDomain__c` does not match the org (silent fallback — see section 2), or
`TEKCO_BrandCodeField__c` / `TEKCO_BrandCountryField__c` do not match the real field API names
on the brand object. Check the domain first; it is by far the more common cause.

**Deployment fails with `no CustomPermission named ... found`.**
The permission set grants a custom permission owned by another application that the target org
does not have. Ship the definition in this org's manifest — see step 4.

**`STORAGE_LIMIT_EXCEEDED` when launching a run.**
The org is at 100% data storage. `insert auditLog` runs *before* `Database.executeBatch()` in
`startAnonymization()`, so the run never starts and no audit log record is created at all.
Free space with a Bulk API **hard delete**, which bypasses the recycle bin — an ordinary delete
frees nothing until the bin is emptied. Note that anonymization cannot free storage itself: it
performs updates, not deletes.

**Fields come through a run unchanged, yet the status is Success.**
The pattern's DeveloperName is not recognised by the dispatch and fell through to `REGEX` with
no regex configured — see section 6. Compare field values before and after; do not rely on the
run status.

**An error toast with no usable message.**
The exception may come from the Lightning container rather than from Apex — a stack made
entirely of `aura_prod.js` frames is platform noise, not a tool failure. Confirm with a debug
log: no `EXCEPTION_THROWN` or `FATAL_ERROR` means Apex raised nothing.

**Children not resolved in By ID mode.**
`TEKCO_ParentObjectApiName__c` must be the exact parent SObject API name, and
`TEKCO_ParentLookupFieldApiName__c` the lookup field's API name (`AccountId`, not `Account`).
