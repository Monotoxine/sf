/**
 * VERSION AUTONOME - aucun deploiement requis.
 *
 * Execution :
 *   sf apex run --file scripts/apex/user-email/00-standalone-send-verification.apex
 *   ou copier/coller dans Developer Console > Debug > Open Execute Anonymous Window
 *
 * A utiliser si vous ne voulez pas deployer MassUserEmailVerificationBatch, ou
 * pour un premier essai immediat. Le batch reste preferable pour un gros volume :
 * ce script travaille en une seule transaction, donc sous les limites synchrones.
 *
 * FONCTIONNEMENT : traite au plus MAX_PER_RUN utilisateurs par execution, puis
 * affiche combien il en reste. Relancer jusqu'a atteindre zero.
 *
 * Prerequis : Setup > Deliverability > Access to Send Email = "All email".
 */

// Nombre d'utilisateurs traites par execution.
// Demarrer BAS (1 a 5) pour valider, puis augmenter prudemment : le cout de
// sendAsyncEmailConfirmation vis-a-vis des limites d'envoi n'est pas documente.
// Le compteur d'invocations affiche en fin de script permet de le mesurer.
final Integer MAX_PER_RUN = 5;

// true = liste les cibles sans rien envoyer.
final Boolean DRY_RUN = true;

// Filtres facultatifs. Laisser a null pour ne pas filtrer.
final String EMAIL_DOMAIN = null;               // ex. 'mondomaine.com'
final Datetime CREATED_SINCE = null;            // ex. System.now().addDays(-1)

// -------------------------------------------------------------------------

Boolean hasField = Schema.SObjectType.User.fields.getMap()
    .containsKey('hasuserverifiedemail');

String soql = 'SELECT Id, Username, Email FROM User '
    + 'WHERE IsActive = true AND Email != null '
    + 'AND (NOT Email LIKE \'%.invalid\')';

if (hasField) {
    soql += ' AND HasUserVerifiedEmail = false';
} else {
    System.debug('!! User.HasUserVerifiedEmail absent de cette org.');
    System.debug('!! Toutes les cibles seront traitees, y compris les deja verifiees.');
    System.debug('!! Un renvoi a un utilisateur deja verifie est sans effet de bord.');
}

Datetime since = CREATED_SINCE;
if (since != null) {
    soql += ' AND CreatedDate >= :since';
}
String domainLike = '%@' + EMAIL_DOMAIN;
if (String.isNotBlank(EMAIL_DOMAIN)) {
    soql += ' AND Email LIKE :domainLike';
}

Integer remaining = Database.countQuery(
    soql.replace('SELECT Id, Username, Email FROM User', 'SELECT COUNT() FROM User')
);
System.debug('=== Utilisateurs a traiter au total : ' + remaining);

List<User> batch = Database.query(soql + ' ORDER BY CreatedDate DESC LIMIT ' + MAX_PER_RUN);
System.debug('=== Traites dans cette execution : ' + batch.size()
    + ' (DRY_RUN=' + DRY_RUN + ')');

Integer emailInvocationsBefore = Limits.getEmailInvocations();
Integer sent = 0;
Integer failed = 0;

for (User u : batch) {
    System.debug('   ' + u.Username + '  ->  ' + u.Email);
    if (DRY_RUN) {
        continue;
    }
    try {
        System.UserManagement.sendAsyncEmailConfirmation(u.Id, null, null, null);
        sent++;
    } catch (Exception e) {
        failed++;
        System.debug('   !! ' + u.Username + ' : ' + e.getMessage());
    }
}

System.debug('=== Envoyes : ' + sent + ' | Echecs : ' + failed);

// Revele si sendAsyncEmailConfirmation consomme le quota d'envoi de la
// transaction : si le compteur n'a pas bouge, il ne compte pas, et MAX_PER_RUN
// peut etre augmente franchement.
System.debug('=== Invocations email consommees : '
    + (Limits.getEmailInvocations() - emailInvocationsBefore)
    + ' (limite transaction : ' + Limits.getLimitEmailInvocations() + ')');

if (!DRY_RUN) {
    System.debug('=== Restant apres cette execution : ' + (remaining - sent));
    System.debug('=== Relancer le script jusqu a atteindre zero.');
}
