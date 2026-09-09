/**
 * Mirrors the manual Setup trick in Apex, in ONE transaction.
 *
 * The manual workaround that works is: edit the user, remove ".invalid" from
 * the address AND tick "Generate new password and notify user immediately",
 * then Save. One save, address applied, credentials mailed to the new address.
 *
 * This script reproduces that combination: the email update and the
 * notification happen in the same transaction, instead of being split across
 * two as TEKCO_UserMailVerify_QBL does today.
 *
 * What to observe:
 *   - which address the mail reaches
 *   - whether a separate execution still reports ".invalid" on the record
 *
 * If this works, the queueable must merge its two phases rather than chain
 * them, and the current design comment about committing the address first is
 * wrong. If it does not, the strip cannot be automated at all.
 */

Id userId = '005XXXXXXXXXXXXXXX'; // <-- the test user
Boolean useReset = true; // true mirrors the checkbox; false tries the verify path

User u = [SELECT Id, Username, Email FROM User WHERE Id = :userId];
System.debug(LoggingLevel.ERROR, 'BEFORE    ' + u.Email);

if (u.Email != null && u.Email.endsWithIgnoreCase('.invalid')) {
  u.Email = u.Email.removeEndIgnoreCase('.invalid');
  update u;
  System.debug(LoggingLevel.ERROR, 'STRIPPED  to ' + u.Email);
} else {
  System.debug(LoggingLevel.ERROR, 'STRIPPED  skipped, no .invalid suffix');
}

if (useReset) {
  System.resetPassword(userId, true);
  System.debug(LoggingLevel.ERROR, 'RESET     credentials requested');
} else {
  System.UserManagement.sendAsyncEmailConfirmation(userId, null, null, null);
  System.debug(LoggingLevel.ERROR, 'VERIFY    confirmation requested');
}
