/**
 * NETTOYAGE du jeu de test.
 *
 * Execution : sf apex run --file scripts/apex/user-email/05-deactivate-test-users.apex
 *
 * Salesforce ne permet PAS de supprimer un utilisateur : la seule sortie est la
 * desactivation, qui libere la licence. Ce script desactive les utilisateurs
 * portes par le marqueur Department = 'TEST-VERIF'.
 */

final Boolean DRY_RUN = true;

List<User> testUsers = [
    SELECT Id, Username, Email, IsActive
    FROM User
    WHERE Department = 'TEST-VERIF'
      AND IsActive = true
];

System.debug('=== A desactiver : ' + testUsers.size() + ' (DRY_RUN=' + DRY_RUN + ')');
for (User u : testUsers) {
    System.debug('   ' + u.Username);
    u.IsActive = false;
}

if (!DRY_RUN && !testUsers.isEmpty()) {
    List<Database.SaveResult> results = Database.update(testUsers, false);
    Integer ok = 0;
    for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
            ok++;
        } else {
            System.debug('!! ' + testUsers[i].Username + ' : ' + results[i].getErrors());
        }
    }
    System.debug('=== Desactives : ' + ok + ' / ' + results.size());
}
