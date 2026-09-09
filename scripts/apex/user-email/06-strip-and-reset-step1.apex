/**
 * Step 1 of 3 - strip the ".invalid" suffix and report what happened.
 *
 * Run this, then 06-...-step2 in a SEPARATE execution, then step3.
 * Splitting matters: anonymous Apex is one transaction, and the whole point is
 * to see whether the address change survives the commit or stays pending
 * behind Email Change Verification.
 *
 * Requires TEKCO_UserMailVerifyService to be deployed.
 * If the org does not expose HasUserVerifiedEmail, drop it from both SELECTs.
 */

Id userId = '005XXXXXXXXXXXXXXX'; // <-- the test user

User before = [
  SELECT Id, Username, Email, HasUserVerifiedEmail
  FROM User
  WHERE Id = :userId
];
System.debug(
  LoggingLevel.ERROR,
  'BEFORE   email=' +
    before.Email +
    ' verified=' +
    before.HasUserVerifiedEmail
);

List<TEKCO_UserMailVerifyService.ActionOutcome> outcomes = TEKCO_UserMailVerifyService.stripInvalidSuffix(
  new List<Id>{ userId }
);

if (outcomes.isEmpty()) {
  System.debug(
    LoggingLevel.ERROR,
    'STRIP    nothing to do - the address does not end in .invalid'
  );
}
for (TEKCO_UserMailVerifyService.ActionOutcome o : outcomes) {
  System.debug(
    LoggingLevel.ERROR,
    'STRIP    success=' + o.success + ' message=' + o.message
  );
}

// Read back inside the same transaction. If this shows the stripped address
// but step 2 shows ".invalid" again, the change was held pending.
User inTxn = [
  SELECT Id, Email, HasUserVerifiedEmail
  FROM User
  WHERE Id = :userId
];
System.debug(
  LoggingLevel.ERROR,
  'IN-TXN   email=' + inTxn.Email + ' verified=' + inTxn.HasUserVerifiedEmail
);
