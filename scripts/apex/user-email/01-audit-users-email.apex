/**
 * AUDIT : quels utilisateurs ont encore une adresse email non verifiee ?
 *
 * Execution : sf apex run --file scripts/apex/user-email/01-audit-users-email.apex
 *
 * A lancer avant et apres le batch de verification en masse, pour mesurer
 * l'avancement. Le suffixe ".invalid" est aussi compte : il ne concerne que les
 * sandboxes rafraichies (voir annexe-suffixe-invalid/), et une adresse suffixee
 * ne peut recevoir aucun lien de verification.
 */

// --- 1. Emails non verifies (verification "expediteur") --------------------
// Source privilegiee : le champ standard User.HasUserVerifiedEmail.
// Repli : TwoFactorMethodsInfo, qui exige la permission
// "Manage Multi-Factor Authentication in API".
Boolean hasField = Schema.SObjectType.User.fields.getMap()
    .containsKey('hasuserverifiedemail');

if (hasField) {
    List<User> unverified = Database.query(
        'SELECT Id, Username, Email FROM User ' +
        'WHERE HasUserVerifiedEmail = false AND IsActive = true ' +
        'ORDER BY Username LIMIT 10000'
    );
    System.debug('=== Utilisateurs actifs avec email NON verifie : ' + unverified.size());
    for (User u : unverified) {
        System.debug('   ' + u.Username + '  ->  ' + u.Email);
    }
} else {
    try {
        Set<Id> unverifiedIds = new Set<Id>();
        for (TwoFactorMethodsInfo i : [
            SELECT UserId
            FROM TwoFactorMethodsInfo
            WHERE HasUserVerifiedEmailAddress = false
            LIMIT 10000
        ]) {
            unverifiedIds.add(i.UserId);
        }
        List<User> unverified = [
            SELECT Id, Username, Email
            FROM User
            WHERE Id IN :unverifiedIds AND IsActive = true
            ORDER BY Username
        ];
        System.debug('=== Utilisateurs actifs avec email NON verifie : ' + unverified.size());
        for (User u : unverified) {
            System.debug('   ' + u.Username + '  ->  ' + u.Email);
        }
    } catch (Exception e) {
        System.debug('!! Lecture TwoFactorMethodsInfo impossible : ' + e.getMessage());
        System.debug('!! Ajouter la permission "Manage Multi-Factor Authentication in API".');
    }
}

// Equivalent sans code, pour un suivi au quotidien :
//   Setup > Users > Create New View, en ajoutant les colonnes de verification
//   (dont "Email Verified"). Permet de suivre l'avancement sans relancer ce script.

// --- 2. Emails en .invalid -------------------------------------------------
List<User> invalidUsers = [
    SELECT Id, Username, Email, IsActive, Profile.Name
    FROM User
    WHERE Email LIKE '%.invalid'
      AND IsActive = true
    ORDER BY Username
    LIMIT 10000
];
System.debug('=== Utilisateurs actifs avec email .invalid : ' + invalidUsers.size());
System.debug('    (artefact de refresh de sandbox - ces adresses ne recevront rien)');
for (User u : invalidUsers) {
    System.debug('   ' + u.Username + '  ->  ' + u.Email);
}

// --- 3. Rappel deliverabilite ----------------------------------------------
// Non lisible en Apex : verifier manuellement
//   Setup > Deliverability > Access to Send Email
// En sandbox la valeur par defaut est "System email only", ce qui bloque
// AUSSI les emails de verification. Passer a "All email" avant toute campagne.
System.debug('=== Verifier Setup > Deliverability > Access to Send Email = All email');
