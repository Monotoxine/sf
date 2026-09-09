/**
 * Sandbox escape hatch - set a test user's password directly, no email.
 *
 * Why this exists. Stripping ".invalid" puts the address change in a pending
 * state, so System.resetPassword mails the credentials to the old ".invalid"
 * address and they never arrive. Confirming the change needs a session as that
 * user, and there is no password to open one with after a sandbox refresh.
 * This breaks that loop: setPassword sends nothing and needs no mailbox.
 *
 * Sandbox only, and only for users you own. Requires "Manage Users" or
 * "Reset User Passwords and Unlock Users".
 *
 * Then: log in as that user with this password, and click the address-change
 * confirmation link from the mailbox. If the link has expired, re-run the
 * strip first to have a fresh one sent.
 */

Id userId = '005XXXXXXXXXXXXXXX'; // <-- the test user
String newPassword = 'PutSomethingHere1!'; // 8+ chars, letters and digits

if (![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox) {
  throw new IllegalArgumentException('Refusing to run outside a sandbox.');
}

System.setPassword(userId, newPassword);
System.debug(LoggingLevel.ERROR, 'PASSWORD set for ' + userId);
