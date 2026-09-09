/**
 * Step 3 of 3 - reset the password, in its own execution.
 *
 * Only worth running once step 2 showed an address free of ".invalid".
 * System.resetPassword mails the credentials to whatever address the record
 * carries, so on a pending change it would post into the void.
 *
 * Completing the reset also verifies the address, but only after the user has
 * clicked the link and set a password.
 */

Id userId = '005XXXXXXXXXXXXXXX'; // <-- the same test user

User u = [SELECT Id, Username, Email FROM User WHERE Id = :userId];
System.debug(LoggingLevel.ERROR, 'TARGET   email=' + u.Email);

TEKCO_UserMailVerifyService.ActionOutcome o = TEKCO_UserMailVerifyService.resetPassword(
  userId,
  u.Username,
  true
);
System.debug(
  LoggingLevel.ERROR,
  'RESET    success=' + o.success + ' message=' + o.message
);
