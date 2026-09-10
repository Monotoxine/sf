/**
 * Does the ".invalid" strip apply if the user is deactivated first?
 *
 * The hypothesis: Email Change Verification exists to protect a live login.
 * A deactivated user has none, so the platform may write the address straight
 * away instead of holding it pending a confirmation nobody can complete.
 *
 * Sequence, each step its own DML so a rejection can be attributed:
 *   1. IsActive = false
 *   2. remove the ".invalid" suffix
 *   3. IsActive = true
 *   4. System.resetPassword, which mails to whatever address the record holds
 *
 * Every update runs with allOrNone = false and its errors are printed at the
 * end. This org has heavy User triggers (CORE_SM_User), and a deactivation can
 * be refused by checkSalesRepRelatedRecords: better a printed message than a
 * stack trace that hides the following steps.
 *
 * Read the COMMITTED result afterwards with 06-strip-and-reset-step2.apex, in
 * a separate execution. A read inside this transaction proves nothing.
 *
 * Sandbox only. Pick a user that is NOT you: changing your own address always
 * requires a confirmation, which would confound the result.
 */

Id userId = '005XXXXXXXXXXXXXXX'; // <-- the test user

if (![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox) {
  throw new IllegalArgumentException('Refusing to run outside a sandbox.');
}
if (userId == UserInfo.getUserId()) {
  throw new IllegalArgumentException(
    'Pick another user: a self-service email change always needs a confirmation.'
  );
}

User before = [
  SELECT Id, Username, Email, IsActive, HasUserVerifiedEmail
  FROM User
  WHERE Id = :userId
];
System.debug(
  LoggingLevel.ERROR,
  'BEFORE     email=' +
    before.Email +
    ' active=' +
    before.IsActive +
    ' verified=' +
    before.HasUserVerifiedEmail
);

List<String> labels = new List<String>();
List<Database.SaveResult> results = new List<Database.SaveResult>();

labels.add('DEACTIVATE');
results.add(Database.update(new User(Id = userId, IsActive = false), false));

String stripped = before.Email;
if (stripped != null && stripped.endsWithIgnoreCase('.invalid')) {
  stripped = stripped.removeEndIgnoreCase('.invalid');
  System.debug(LoggingLevel.ERROR, 'STRIP      target ' + stripped);
  labels.add('STRIP');
  results.add(Database.update(new User(Id = userId, Email = stripped), false));
} else {
  System.debug(LoggingLevel.ERROR, 'STRIP      skipped, no .invalid suffix');
}

labels.add('REACTIVATE');
results.add(Database.update(new User(Id = userId, IsActive = true), false));

for (Integer i = 0; i < results.size(); i++) {
  if (results[i].isSuccess()) {
    System.debug(LoggingLevel.ERROR, labels[i] + ' ok');
    continue;
  }
  for (Database.Error err : results[i].getErrors()) {
    System.debug(
      LoggingLevel.ERROR,
      labels[i] + ' FAILED: ' + err.getMessage()
    );
  }
}

try {
  System.resetPassword(userId, true);
  System.debug(LoggingLevel.ERROR, 'RESET      credentials requested');
} catch (Exception e) {
  System.debug(LoggingLevel.ERROR, 'RESET      failed: ' + e.getMessage());
}
