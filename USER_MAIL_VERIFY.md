# User Mail Verify

An admin tab for bulk email verification and password reset, filtered by brand.
Several brands can be processed in one pass.

## Why it exists

Users provisioned through the Talend integration land in Salesforce with an
**unverified email address**. Until it is verified, Salesforce refuses to send
mail on their behalf: workflow alerts, Flow _Send Email_ elements, Email-to-Case.

Without this tab, the _Verify_ action has to be clicked one record at a time in
Setup → Users.

Two buttons, each sending one email:

| Button                        | Apex                                               | Effect                                                                                   |
| ----------------------------- | -------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| **Verify**                    | `System.UserManagement.sendAsyncEmailConfirmation` | the user clicks a link, `HasUserVerifiedEmail` flips                                     |
| **Verify and reset password** | `System.resetPassword`                             | credentials mailed; clicking the link and setting the password also verifies the address |

Resetting a password verifies the address as a side effect, once the user has
clicked the link and completed the reset. It is not a way to verify without the
user acting; it replaces two emails with one.

**The reset button appears in sandboxes only.** In production, users sign in
through SSO and have no Salesforce password, so a reset would mail out
credentials nobody can use. The controller refuses it there as well: hiding a
button is not an access control.

Creating a user through the API triggers **neither** of them.

## How a run works

```
Selection ──► TEKCO_UserMailVerifyController ──► TEKCO_UserMailVerify_QBL
                  (permission + cap)          chunk 1 ─► chunk 2 ─► ... ─► notification
```

Everything runs asynchronously, one chunk per transaction. Counters travel from
one link of the chain to the next, so a **single** completion notification is
sent at the end of the whole run rather than one per chunk. It reaches the
Salesforce bell and the mobile app, and arrives even if the administrator closed
the tab.

A run has one phase. It never rewrites an address.

## Who can use it

Access rests entirely on Salesforce configuration: **Apex class access** to
`TEKCO_UserMailVerifyController`, plus tab visibility, both granted through the
permission set for the Run Team Tools app. There is no check in the code.

That places one requirement on whoever maintains the org. `@AuraEnabled` methods
are callable directly, without going through the component: hiding the tab hides
the entrance, not the door. So the class must be granted through that permission
set and nothing else. If a profile or another permission set ever grants access
to it, the tool opens up with no warning, and re-checking that is part of any
change to the permission model here.

## Fixed values

`TEKCO_UserMailVerifyConstants` holds what the feature tunes. **One of these
numbers is imposed by the platform, the rest are judgement calls**, and the
difference is what matters when someone wants to change one.

| Constant             | Value                               | Origin                                            |
| -------------------- | ----------------------------------- | ------------------------------------------------- |
| `RESET_HARD_LIMIT`   | 10                                  | **imposed**: platform cap per transaction         |
| `MAX_USERS_PER_RUN`  | 200                                 | chosen: guardrail against an accidental mass send |
| `CHUNK_SIZE_VERIFY`  | 50                                  | chosen: CPU margin, no published cap on the send  |
| `MAX_ROWS_DISPLAYED` | 500                                 | chosen: this is a picking list, not a report      |
| `NOTIFICATION_TYPE`  | `TEKCO_UserMailVerify_Run_Complete` | fixed: names the notification type shipped here   |

**`RESET_HARD_LIMIT`, 10.** The only one nobody may touch. Salesforce refuses
more than ten `System.resetPassword` calls in a single transaction, so the
reset chunk is clamped to it rather than merely defaulted. Raising it would not
buy speed, it would make every reset past the tenth fail at runtime, in the
middle of a run, after mails have already gone out.

**`MAX_USERS_PER_RUN`, 200.** The blocking cap, refused server-side rather than
only greyed out in the screen. The number answers one question: how many users
would a realistic batch of Talend-provisioned accounts contain, and where does
a misclick stop being recoverable. Two hundred covers the first comfortably
while keeping the blast radius of a wrong selection legible. It costs four
chained transactions on the verify path and twenty on the reset path, both
acceptable. It cannot be a _daily_ cap: nothing is persisted, so there is no
way to know how many sends already happened today.

**`CHUNK_SIZE_VERIFY`, 50.** Unlike the reset, no published limit constrains
`sendAsyncEmailConfirmation`. What bounds a chunk is CPU time, sixty seconds in
an asynchronous transaction, and the cost of one call has never been measured
here. Fifty is a margin, not a computed optimum. It also keeps the blast radius
small: a transaction killed by a governor limit stops the whole chain, and with
fifty at most one chunk is lost. To make it an informed number, run fifty users
and read the CPU time in the job log.

**`MAX_ROWS_DISPLAYED`, 500.** The screen is a list you pick from, not a report
you read. Past a few hundred rows nobody scrolls, they filter, which is why the
brand, status and address filters exist. Exceeding the cap is signalled rather
than silent, so the administrator knows to narrow rather than assuming the list
is complete.

Two further numbers live outside the class, next to the code that needs them.

**`QUERY_CEILING`, 2000, in the selector.** The `LIMIT` on the candidate query,
before frozen users, the running user and the in-memory status filter are
subtracted. It sits at four times `MAX_ROWS_DISPLAYED` on purpose: those
filters can discard three quarters of the candidates and the screen still
fills.

**`MAX_REPORTED_ERRORS`, 10, in the queueable.** How many failure messages are
kept for the completion notification, whose body is truncated at 750
characters. Ten lines of roughly seventy characters is what fits. The failure
_count_ is never capped, every failure reaches the debug log, and the summary
says how many more there are.

These were held in a custom metadata type at first. That was over-engineering:
none of them is expected to change, the reset chunk size cannot legally differ
from the platform cap, and the notification type names a component this feature
ships itself. Configuration for values nobody will edit only bought an extra
SOQL query per transaction and a layer of indirection. Changing one is now a
code change, reviewed and deployed like the rest.

## Email volume

Sends to **internal** users are **not capped** by Salesforce. The 5,000 a day
ceiling applies to external addresses only, so nothing here throttles a run
against staff accounts. The per-run cap above is therefore the only volume
guardrail, and it exists to stop a misclick rather than to stay under a quota.

## Deployment

The feature has its own manifest, so it can be deployed and retrieved as a unit
without touching the rest of the project:

```bash
sf project deploy start --manifest manifest/user-mail-verify-package.xml --target-org <alias>
sf project retrieve start --manifest manifest/user-mail-verify-package.xml --target-org <alias>
```

Add `--dry-run` to validate without deploying.

`TEKCO_UserMailVerifyBatch` is listed in that manifest although it predates
the tab: it now delegates its unit actions to `TEKCO_UserMailVerifyService` and no
longer compiles without it.

Then, in Setup:

1. Add the **User Mail Verify** tab to the TEKCO_RunTeamTools app.
2. Add the tab and the `TEKCO_UserMailVerify*` Apex classes to the permission set.
3. Check `Setup → Deliverability → Access to Send Email` is **All email**. In a
   sandbox the default is `System email only`, which silently blocks every send
   while the run still reports success.

## Org-side prerequisites

Not in this repository, expected to exist in the org:

- `User.TEKCO_Brand__c`, a picklist backed by the `Brands` global value set
- the permission set granting the TEKCO_RunTeamTools app

## Design notes

**Frozen users** are resolved through `UserLogin` filtered on `IsFrozen = true`,
never `IsFrozen = false`: a user with no `UserLogin` record is not frozen, and
the negative filter would wrongly drop them.

**An address filter** sits with them: _All addresses_, _With .invalid_ or
_Without .invalid_. Unlike the verification predicate, this one is a plain LIKE
on Email and is always safe to push into the query.

**A verification-status filter** sits next to the brands: _Not verified_
(default), _Verified_, or _All_. The query no longer hard-codes
`HasUserVerifiedEmail = false`. Since completing a reset is what verifies an
address, an already verified user is a legitimate target for a reset, and the
screen has to be able to show them. A Verified column reports the state per row,
with `?` when the org exposes no signal.

Brands and status are stacked in a half-width column, the picker capped at four
visible entries: at full height it took as much room as the table it filters.
The search box sits directly above the table instead, so it reads as belonging
to the list it narrows rather than to the query that built it.

That column is aligned left, sharing its edge with the first table column. It
was centred while it was the only thing on screen, but once rows load the table
sets the page edge and a block floating in the middle reads as unrelated to the
list it builds. It stays narrow rather than stretched: a picker is not improved
by matching the width of a full-width table.

**Brands are picked several at a time**, through a dual listbox. The rows carry a
Brand column, since a list can now mix them, and the query orders by brand before
name.

**The name column links to the user record**, opened in a new tab. The selection
lives in memory, so navigating away in place would discard it.

**The search box filters client-side.** The rows for one brand are already
loaded, so a server round-trip per keystroke would buy nothing. It matches on
name, username, email and profile.

A selection survives filtering. `lightning-datatable` only reports the rows it
currently shows, so selections outside the active filter are preserved and only
the visible ones are replaced; the counter reads against every loaded row, not
just the visible ones.

**Nothing removes the `.invalid` suffix.** An earlier version did, and it could
not work. Changing the address from Apex leaves the change pending an Email
Change Verification, and that confirmation can only be honoured from a session
as the user in question. After a sandbox refresh nobody has a password to open
one with, and the reset mail goes to the dead address, so the loop never closes.
Setting a password first does break it, but a screen called _Verify_ has no
business setting passwords on accounts it does not own.

The suffix is a sandbox artefact, added by Salesforce at refresh. Production
addresses are real and merely unverified, which is exactly what the verify
button handles. So the screen surfaces suffixed users and lets you filter them
in or out, and removing a suffix stays a manual gesture in Setup: edit the user,
remove the suffix and tick _Generate new password and notify user immediately_
in the same save. `scripts/apex/user-email/07-sandbox-set-password.apex` covers
the case where you need a password without a mailbox first.

**An already verified address is skipped by the verify button**, and reported
as skipped rather than as a success. Asking someone to confirm what they have
already confirmed is noise. The reset button skips nobody: a verified user is a
legitimate target for a password reset, which is exactly why the screen can list
verified users at all.

**The running user is always excluded** from the list. The same screen resets
passwords, and locking yourself out of an admin tool is not recoverable.

**`HasUserVerifiedEmail` filterability is undocumented.** Nothing guarantees a
read-only standard field accepts a `WHERE`, so the selector tries the clause
first and falls back to filtering in memory. That fallback answers a real
uncertainty and stays.

A second fallback used to read `TwoFactorMethodsInfo` when the field was absent
from the org altogether. It is gone. Nobody could name an org where a modern
User lacks the field, the path never ran, and it was subtly wrong: it collected
the unverified, so a user with no `TwoFactorMethodsInfo` record read as
verified. What remains is a describe guard that keeps the field out of the
`SELECT` where it does not exist, which turns a broken screen into one showing
`?` in every Verified cell.

**The platform calls sit directly in the service.** They were behind an
injectable interface so the orchestration could be asserted against a test
double, which is what made it possible to check that three users produced three
links, that a completed run notified once rather than once per chunk, and that a
failure reached the summary. That seam was removed for readability, and those
assertions went with it: the queueable and service tests now cover the address
cleanup only, which writes to the database and is observable without it.
Reintroducing the interface is what brings the rest back.

**`emailTemplateId` has no effect for internal users.** Salesforce sends its own
standard verification email whatever template is passed; customisation only
works for Experience Cloud users. Users therefore receive an unbranded generic
message asking them to click a link, which is the shape of a phishing attempt —
announce a bulk run out of band before launching it.

**Failure detail is not persisted.** Per-user errors live in the notification
body (truncated to the first 10) and the Apex debug logs. If auditing bulk
password resets becomes a requirement, that needs a persistence layer.

## Testing

```bash
npm run test:unit                                          # LWC
sf apex run test --class-names TEKCO_UserMailVerify*_Test        # Apex
```

`scripts/data/users-test-verification.csv` provisions throwaway users, and
`scripts/apex/user-email/05-deactivate-test-users.apex` deactivates them
afterwards — Salesforce users cannot be deleted.

## Related

`MASS_USER_EMAIL_VERIFICATION.md` documents the anonymous Apex scripts, now
diagnostic tools rather than the supported path, plus the org-level alternative
(**Authorized Email Domains**) that removes the user click entirely.
