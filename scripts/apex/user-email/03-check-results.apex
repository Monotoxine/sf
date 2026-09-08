/**
 * CONTROLE : resultat d'un batch et etat de verification des utilisateurs.
 *
 * Execution : sf apex run --file scripts/apex/user-email/03-check-results.apex
 *
 * Le batch tourne en asynchrone : ses compteurs (sentCount, failedCount) sont
 * ecrits dans le log de l'execution asynchrone, pas dans celui du lancement.
 * Ce script recupere l'essentiel sans avoir a fouiller les logs.
 */

// --- 1. Etat des derniers batchs lances -----------------------------------
System.debug('=== DERNIERS JOBS MassUserEmailVerificationBatch ===');
for (AsyncApexJob j : [
    SELECT Id, Status, JobItemsProcessed, TotalJobItems, NumberOfErrors,
           ExtendedStatus, CreatedDate, CompletedDate
    FROM AsyncApexJob
    WHERE ApexClass.Name = 'MassUserEmailVerificationBatch'
    ORDER BY CreatedDate DESC
    LIMIT 5
]) {
    System.debug('  ' + j.Id + ' | ' + j.Status
        + ' | lots ' + j.JobItemsProcessed + '/' + j.TotalJobItems
        + ' | erreurs ' + j.NumberOfErrors
        + ' | ' + j.CreatedDate);
    if (String.isNotBlank(j.ExtendedStatus)) {
        System.debug('     -> ' + j.ExtendedStatus);
    }
}

// --- 2. Etat de verification d'utilisateurs precis -------------------------
// Renseigner les Id cibles pour verifier que le clic a bien bascule l'etat.
final Set<Id> WATCHED = new Set<Id>{
    // '005G500000aenrnIAA'
};

if (!WATCHED.isEmpty()) {
    Boolean hasField = Schema.SObjectType.User.fields.getMap()
        .containsKey('hasuserverifiedemail');
    String fields = hasField
        ? 'Id, Username, Email, HasUserVerifiedEmail'
        : 'Id, Username, Email';

    System.debug('=== ETAT DES UTILISATEURS SURVEILLES ===');
    for (User u : Database.query(
        'SELECT ' + fields + ' FROM User WHERE Id IN :WATCHED'
    )) {
        System.debug('  ' + u.Username + ' | ' + u.Email
            + (hasField ? ' | verifie=' + u.get('HasUserVerifiedEmail') : ''));
    }
    if (!hasField) {
        System.debug('  (User.HasUserVerifiedEmail absent : verifier dans Setup > Users)');
    }
}

// --- 3. Volume restant -----------------------------------------------------
Boolean canCount = Schema.SObjectType.User.fields.getMap()
    .containsKey('hasuserverifiedemail');
if (canCount) {
    Integer remaining = Database.countQuery(
        'SELECT COUNT() FROM User WHERE IsActive = true '
        + 'AND Email != null AND HasUserVerifiedEmail = false'
    );
    System.debug('=== Utilisateurs actifs encore non verifies : ' + remaining);
}
