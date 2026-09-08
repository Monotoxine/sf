/**
 * 01 - AUDIT : etat des emails utilisateurs avant toute action de masse.
 *
 * Execution : sf apex run --file scripts/apex/user-email/01-audit-users-email.apex
 *
 * Repond a 3 questions :
 *   - combien d'utilisateurs ont encore un email en .invalid ?
 *   - combien d'utilisateurs ont un email NON verifie (au sens "expediteur") ?
 *   - la deliverabilite de l'org autorise-t-elle l'envoi des emails de verification ?
 *
 * Prerequis : permission "Manage Multi-Factor Authentication in API" pour lire
 * TwoFactorMethodsInfo (sinon la 2e section leve une exception, cf. try/catch).
 */

// --- 1. Emails en .invalid -------------------------------------------------
List<User> invalidUsers = [
    SELECT Id, Username, Email, IsActive, Profile.Name
    FROM User
    WHERE Email LIKE '%.invalid'
      AND IsActive = true
    ORDER BY Username
    LIMIT 10000
];
System.debug('=== Utilisateurs actifs avec email .invalid : ' + invalidUsers.size());
for (User u : invalidUsers) {
    System.debug('   ' + u.Username + '  ->  ' + u.Email);
}

// --- 2. Emails non verifies (verification "expediteur") --------------------
try {
    List<TwoFactorMethodsInfo> infos = [
        SELECT UserId, HasUserVerifiedEmailAddress
        FROM TwoFactorMethodsInfo
        WHERE HasUserVerifiedEmailAddress = false
        LIMIT 10000
    ];
    Set<Id> unverifiedIds = new Set<Id>();
    for (TwoFactorMethodsInfo i : infos) {
        unverifiedIds.add(i.UserId);
    }

    List<User> unverified = [
        SELECT Id, Username, Email
        FROM User
        WHERE Id IN :unverifiedIds
          AND IsActive = true
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

// --- 3. Rappel deliverabilite ----------------------------------------------
// Non lisible en Apex : verifier manuellement
//   Setup > Deliverability > Access to Send Email
// En sandbox la valeur par defaut est "System email only", ce qui bloque
// AUSSI les emails de verification. Passer a "All email" avant toute campagne.
System.debug('=== Verifier Setup > Deliverability > Access to Send Email = All email');
