/**
 * PREPARATION du jeu de test - a lancer AVANT l'import du CSV.
 *
 * Execution : sf apex run --file scripts/apex/user-email/04-prepare-test-users.apex
 *
 * Fournit les deux valeurs a substituer dans
 * scripts/data/users-test-verification.csv :
 *   - REMPLACER_PROFILE_ID   -> un ProfileId valide de cette org
 *   - REMPLACER-DOMAINE.com  -> le domaine de vos usernames existants
 *
 * Verifie aussi qu'il reste des licences disponibles.
 */

// --- 1. Profils disponibles ------------------------------------------------
System.debug('=== PROFILS UTILISABLES (colonne ProfileId du CSV) ===');
for (Profile p : [
    SELECT Id, Name, UserType
    FROM Profile
    WHERE UserType = 'Standard'
    ORDER BY Name
    LIMIT 20
]) {
    System.debug('  ' + p.Id + '  ' + p.Name);
}

// --- 2. Licences restantes -------------------------------------------------
// Creer des utilisateurs consomme des licences, et elles ne se liberent qu'en
// desactivant les utilisateurs.
System.debug('=== LICENCES ===');
for (UserLicense l : [
    SELECT Name, TotalLicenses, UsedLicenses
    FROM UserLicense
    WHERE TotalLicenses > 0
    ORDER BY Name
]) {
    System.debug('  ' + l.Name + ' : ' + l.UsedLicenses + '/' + l.TotalLicenses
        + ' utilisees, ' + (l.TotalLicenses - l.UsedLicenses) + ' disponibles');
}

// --- 3. Domaine des usernames existants ------------------------------------
// Le Username doit etre unique sur TOUTES les orgs Salesforce, pas seulement la
// votre. Reutiliser le suffixe deja en place dans cette org est le plus sur.
System.debug('=== SUFFIXE D USERNAME EN USAGE ===');
for (User u : [
    SELECT Username
    FROM User
    WHERE IsActive = true
    ORDER BY CreatedDate DESC
    LIMIT 3
]) {
    System.debug('  exemple : ' + u.Username);
}
System.debug('  -> reprendre la partie apres le @ pour REMPLACER-DOMAINE.com');

// --- 4. Etat du jeu de test (a relancer apres import) -----------------------
Boolean hasField = Schema.SObjectType.User.fields.getMap()
    .containsKey('hasuserverifiedemail');
String fields = hasField
    ? 'Id, Name, Username, Email, IsActive, HasUserVerifiedEmail'
    : 'Id, Name, Username, Email, IsActive';

List<User> testUsers = Database.query(
    'SELECT ' + fields + ' FROM User WHERE Department = \'TEST-VERIF\' ORDER BY Username'
);
System.debug('=== UTILISATEURS DE TEST EXISTANTS : ' + testUsers.size());
for (User u : testUsers) {
    System.debug('  ' + u.Username + ' | ' + u.Email
        + ' | actif=' + u.IsActive
        + (hasField ? ' | verifie=' + u.get('HasUserVerifiedEmail') : ''));
}
