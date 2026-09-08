/**
 * 02 - CORRECTION EN MASSE : retire le suffixe ".invalid" des emails utilisateurs.
 *
 * Execution : sf apex run --file scripts/apex/user-email/02-strip-invalid-emails.apex
 *
 * C'EST LE REMPLACEMENT 1:1 DU TRAVAIL MANUEL DANS L'INTERFACE.
 *
 * Editer l'email d'un utilisateur dans Setup > Users declenche l'envoi du mail
 * "Verify your new Salesforce email address" a la nouvelle adresse. Faire le
 * meme changement par API (ce script, ou Data Loader en mode Update) declenche
 * EXACTEMENT le meme mail. L'API ne contourne rien, mais elle ne saute rien non
 * plus : 500 utilisateurs corriges = 500 mails de confirmation envoyes en une
 * passe, au lieu de 500 editions a la main.
 *
 * Comportement apres execution :
 *   - chaque utilisateur recoit le mail de confirmation a sa VRAIE adresse
 *   - l'adresse affichee reste l'ancienne (.invalid) tant que l'utilisateur
 *     n'a pas clique (lien valable 72h)
 *   - apres le clic, la nouvelle adresse remplace l'ancienne
 *
 * Pour supprimer AUSSI le clic utilisateur (application immediate) :
 *   Setup > Authorized Email Domains > <ton domaine> > Edit
 *     -> desactiver "Require email verification"
 *   (ou cle DKIM active sur le domaine + option de bypass dans Deliverability)
 *
 * Prerequis : Setup > Deliverability > Access to Send Email = "All email",
 * sinon aucun mail de confirmation ne part.
 *
 * Voir MASS_USER_EMAIL_VERIFICATION.md pour l'arbre de decision complet.
 */

// Passer a false pour ecrire reellement en base.
final Boolean DRY_RUN = true;

// Mettre a true pour nettoyer aussi le Username (le Username, lui, ne demande
// AUCUNE verification : c'est un simple identifiant de connexion).
final Boolean FIX_USERNAME = false;

final String SUFFIX = '.invalid';

List<User> users = [
    SELECT Id, Username, Email
    FROM User
    WHERE (Email LIKE '%.invalid' OR Username LIKE '%.invalid')
      AND IsActive = true
    LIMIT 10000
];

List<User> toUpdate = new List<User>();
for (User u : users) {
    Boolean changed = false;

    if (u.Email != null && u.Email.endsWith(SUFFIX)) {
        u.Email = u.Email.removeEnd(SUFFIX);
        changed = true;
    }
    if (FIX_USERNAME && u.Username != null && u.Username.endsWith(SUFFIX)) {
        u.Username = u.Username.removeEnd(SUFFIX);
        changed = true;
    }
    if (changed) {
        toUpdate.add(u);
        System.debug('   ' + u.Id + ' -> ' + u.Email + ' / ' + u.Username);
    }
}

System.debug('=== Utilisateurs a corriger : ' + toUpdate.size() + ' (DRY_RUN=' + DRY_RUN + ')');

if (!DRY_RUN && !toUpdate.isEmpty()) {
    // allOrNone = false : un utilisateur en erreur ne bloque pas les autres.
    List<Database.SaveResult> results = Database.update(toUpdate, false);
    Integer ok = 0;
    for (Integer i = 0; i < results.size(); i++) {
        if (results[i].isSuccess()) {
            ok++;
        } else {
            System.debug('!! ' + toUpdate[i].Username + ' : ' + results[i].getErrors());
        }
    }
    System.debug('=== Succes : ' + ok + ' / ' + results.size());
}
