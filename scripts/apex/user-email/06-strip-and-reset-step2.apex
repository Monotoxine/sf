/**
 * Step 2 of 3 - read the COMMITTED state, in its own execution.
 *
 * This is the line that decides everything:
 *   - address without ".invalid"  -> the change applied, go to step 3
 *   - address still with ".invalid" -> the change is pending confirmation,
 *     and anything sent from here goes to a dead address
 */

Id userId = '005XXXXXXXXXXXXXXX'; // <-- the same test user

User u = [
  SELECT Id, Username, Email, HasUserVerifiedEmail
  FROM User
  WHERE Id = :userId
];
System.debug(
  LoggingLevel.ERROR,
  'COMMITTED email=' + u.Email + ' verified=' + u.HasUserVerifiedEmail
);
