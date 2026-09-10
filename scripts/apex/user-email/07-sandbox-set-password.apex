/**
 * The manual sandbox path for removing a ".invalid" suffix.
 *
 * Why it is manual. Changing the address from Apex leaves the change pending
 * an Email Change Verification, and the confirmation mail can only be honoured
 * from a session as that user. After a sandbox refresh nobody has a password
 * to open one with, and the reset mail goes to the dead ".invalid" address, so
 * the loop never closes.
 *
 * The one sequence that works: set a password here, log in as that user, then
 * change the address. Setting a password sends nothing and needs no mailbox.
 * The Setup equivalent is editing the user, removing the suffix and ticking
 * "Generate new password and notify user immediately" in the same save.
 *
 * The screen deliberately does none of this. It never rewrites an address; it
 * only lets you filter suffixed users in or out of the list.
 *
 * Sandbox only, and only for users you own. Requires "Manage Users" or
 * "Reset User Passwords and Unlock Users".
 */

Id userId = '005XXXXXXXXXXXXXXX'; // <-- the test user
String newPassword = 'PutSomethingHere1!'; // 8+ chars, letters and digits

if (![SELECT IsSandbox FROM Organization LIMIT 1].IsSandbox) {
  throw new IllegalArgumentException('Refusing to run outside a sandbox.');
}

System.setPassword(userId, newPassword);
System.debug(LoggingLevel.ERROR, 'PASSWORD set for ' + userId);
