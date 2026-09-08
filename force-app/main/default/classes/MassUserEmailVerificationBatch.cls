/**
 * Declenche en masse la verification d'adresse email des utilisateurs.
 *
 * PROBLEME RESOLU
 * ---------------
 * Creer un utilisateur par API (Talend, Data Loader, ...) n'envoie AUCUN mail de
 * verification d'adresse. L'utilisateur reste "non verifie", l'action "Verify"
 * subsiste a cote de son email dans Setup > Users, et Salesforce refuse d'envoyer
 * des mails en son nom ("The current user's email address isn't verified").
 * Sans outil, il faut cliquer ce lien fiche par fiche.
 *
 * Ce batch est l'equivalent en masse de ce clic. Il enveloppe la methode
 * officielle d'async email verification :
 *
 *   System.UserManagement.sendAsyncEmailConfirmation(
 *       userId, emailTemplateId, networkId, startUrl);
 *
 * Chaque utilisateur cible recoit le lien de verification standard et clique une
 * fois. Aucune adresse email n'est modifiee par ce batch.
 *
 * REINITIALISATION DU MOT DE PASSE
 * --------------------------------
 * Creer un utilisateur par API ne declenche pas non plus l'envoi des
 * identifiants. Dans l'interface, cocher "Generate new password and notify user
 * immediately" couvre ce second besoin ; en masse, activer sendPasswordReset :
 *
 *   MassUserEmailVerificationBatch b = new MassUserEmailVerificationBatch();
 *   b.sendPasswordReset = true;
 *   Database.executeBatch(b, 10);   // <-- 10 IMPERATIVEMENT, voir ci-dessous
 *
 * System.resetPassword est plafonne a 10 appels par transaction. Avec
 * sendPasswordReset actif, la taille de lot DOIT donc valoir 10 au maximum.
 * Au-dela, les utilisateurs excedentaires de chaque lot sont comptes en echec
 * avec un message explicite plutot que traites silencieusement : rien n'est
 * perdu, mais il faut relancer avec la bonne taille de lot.
 *
 * Le mot de passe existant est invalide par l'operation. A n'activer qu'en
 * connaissance de cause, et jamais sur un perimetre plus large que voulu.
 *
 * EXEMPLES
 * --------
 * Tous les utilisateurs actifs non verifies :
 *   Database.executeBatch(new MassUserEmailVerificationBatch(), 50);
 *
 * Seulement le lot charge aujourd'hui par l'integration :
 *   MassUserEmailVerificationBatch b = new MassUserEmailVerificationBatch();
 *   b.createdSince = System.now().addDays(-1);
 *   Database.executeBatch(b, 50);
 *
 * Une liste d'Id precise (run pilote) :
 *   MassUserEmailVerificationBatch b = new MassUserEmailVerificationBatch();
 *   b.userIds = new Set<Id>{ '005...' };
 *   Database.executeBatch(b, 50);
 *
 * LIMITES
 * -------
 * Les envois vers les utilisateurs INTERNES de l'org ne sont pas plafonnes.
 * Le plafond de 5 000 mails/jour ne vise que les adresses externes : le prendre
 * en compte pour un parc d'utilisateurs Experience Cloud.
 */
public with sharing class MassUserEmailVerificationBatch
    implements Database.Batchable<sObject>, Database.Stateful {

    /** Restreint aux utilisateurs dont l'email n'est pas encore verifie. */
    public Boolean onlyUnverified = true;

    /** Ne cible que les utilisateurs crees depuis cette date. Null = pas de filtre. */
    public Datetime createdSince;

    /** Liste d'Id explicite. Non vide = ignore les autres filtres de selection. */
    public Set<Id> userIds;

    /** Ne cible que les emails de ce domaine (ex. 'mondomaine.com'). Null = tous. */
    public String emailDomainFilter;

    /** Template d'email personnalise. Null = mail de verification standard. */
    public Id emailTemplateId;

    /** Site Experience Cloud. Null pour les utilisateurs internes. */
    public Id networkId;

    /** Page d'atterrissage apres le clic de verification. Null = accueil de l'org. */
    public String startUrl;

    /** Envoie le lien de verification d'adresse. */
    public Boolean sendVerification = true;

    /**
     * Reinitialise le mot de passe et envoie les identifiants.
     * Equivalent de "Generate new password and notify user immediately".
     * INVALIDE le mot de passe existant : activation explicite uniquement,
     * et taille de lot limitee a 10 (cf. en-tete).
     */
    public Boolean sendPasswordReset = false;

    /** Notifier l'utilisateur lors du reset. False = reset silencieux. */
    public Boolean notifyUserOnReset = true;

    /** Compte les cibles sans rien envoyer. A utiliser pour le premier run. */
    public Boolean dryRun = false;

    /**
     * Inclure les adresses se terminant par ".invalid" (artefact de refresh de
     * sandbox). Ces adresses ne peuvent rien recevoir : les exclure evite des
     * envois vains. Sans effet hors sandbox.
     */
    public Boolean includeInvalidAddresses = true;

    /** Plafond Salesforce : 10 appels a System.resetPassword par transaction. */
    private static final Integer MAX_PASSWORD_RESETS_PER_CHUNK = 10;

    public Integer sentCount = 0;
    public Integer resetCount = 0;
    public Integer skippedCount = 0;
    public Integer failedCount = 0;
    public Integer resetFailedCount = 0;
    private List<String> errors = new List<String>();

    private static Boolean hasVerifiedEmailFieldCache;

    /**
     * True si le champ standard User.HasUserVerifiedEmail est disponible.
     * Detecte a l'execution : son absence ne doit pas faire echouer le batch,
     * un repli sur TwoFactorMethodsInfo prend alors le relais.
     */
    @TestVisible
    private static Boolean hasVerifiedEmailField() {
        if (hasVerifiedEmailFieldCache == null) {
            hasVerifiedEmailFieldCache = Schema.SObjectType.User.fields.getMap()
                .containsKey('hasuserverifiedemail');
        }
        return hasVerifiedEmailFieldCache;
    }

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        // Binds declares hors des blocs conditionnels : ils doivent rester dans
        // la portee au moment ou Database.getQueryLocator les resout.
        Set<Id> ids = userIds;
        Datetime since = createdSince;
        String domainLike = '%@' + emailDomainFilter;

        String soql = 'SELECT Id, Username, Email FROM User WHERE Email != null';

        if (ids != null && !ids.isEmpty()) {
            // Selection explicite : elle prime sur tous les autres filtres.
            soql += ' AND Id IN :ids';
        } else {
            soql += ' AND IsActive = true';

            if (onlyUnverified == true && hasVerifiedEmailField()) {
                // Filtrage a la source : plus efficace que le repli par lot, et
                // sans permission "Manage Multi-Factor Authentication in API".
                soql += ' AND HasUserVerifiedEmail = false';
            }
            if (since != null) {
                soql += ' AND CreatedDate >= :since';
            }
            if (String.isNotBlank(emailDomainFilter)) {
                soql += ' AND Email LIKE :domainLike';
            }
            if (includeInvalidAddresses == false) {
                soql += ' AND (NOT Email LIKE \'%.invalid\')';
            }
        }
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext ctx, List<User> scope) {
        Set<Id> targets = new Set<Id>();
        for (User u : scope) {
            targets.add(u.Id);
        }

        // Deja filtre par la requete si User.HasUserVerifiedEmail est disponible.
        if (onlyUnverified == true && !hasVerifiedEmailField()) {
            targets = filterUnverified(targets);
        }

        Integer resetsThisChunk = 0;

        for (User u : scope) {
            if (!targets.contains(u.Id)) {
                skippedCount++;
                continue;
            }
            if (dryRun == true) {
                sentCount++;
                if (sendPasswordReset == true) {
                    resetCount++;
                }
                continue;
            }

            if (sendVerification == true) {
                try {
                    System.UserManagement.sendAsyncEmailConfirmation(
                        u.Id, emailTemplateId, networkId, startUrl
                    );
                    sentCount++;
                } catch (Exception e) {
                    failedCount++;
                    logError(u.Username + ' (verification) : ' + e.getMessage());
                }
            }

            if (sendPasswordReset == true) {
                if (resetsThisChunk >= MAX_PASSWORD_RESETS_PER_CHUNK) {
                    // Compte en echec plutot que traite silencieusement : rien
                    // n'est perdu, mais il faut relancer avec une taille de lot
                    // de 10 pour couvrir ces utilisateurs.
                    resetFailedCount++;
                    logError(u.Username + ' (reset) : limite de '
                        + MAX_PASSWORD_RESETS_PER_CHUNK
                        + ' resets par transaction atteinte. Relancer avec '
                        + 'Database.executeBatch(batch, 10).');
                    continue;
                }
                try {
                    System.resetPassword(u.Id, notifyUserOnReset);
                    resetsThisChunk++;
                    resetCount++;
                } catch (Exception e) {
                    resetFailedCount++;
                    logError(u.Username + ' (reset) : ' + e.getMessage());
                }
            }
        }
    }

    private void logError(String message) {
        if (errors.size() < 50) {
            errors.add(message);
        }
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('MassUserEmailVerificationBatch termine.');
        System.debug('  Liens de verification envoyes : ' + sentCount);
        System.debug('  Mots de passe reinitialises   : ' + resetCount);
        System.debug('  Ignores (deja verifies)       : ' + skippedCount);
        System.debug('  Echecs verification           : ' + failedCount);
        System.debug('  Echecs reset                  : ' + resetFailedCount);
        for (String err : errors) {
            System.debug('  !! ' + err);
        }
    }

    /**
     * Repli pour les orgs qui n'exposent pas User.HasUserVerifiedEmail.
     * TwoFactorMethodsInfo exige la permission "Manage Multi-Factor
     * Authentication in API" ; si la lecture echoue, toutes les cibles sont
     * conservees : renvoyer un lien a un utilisateur deja verifie est sans
     * effet de bord.
     */
    private Set<Id> filterUnverified(Set<Id> candidates) {
        Set<Id> unverified = new Set<Id>();
        try {
            for (TwoFactorMethodsInfo info : [
                SELECT UserId
                FROM TwoFactorMethodsInfo
                WHERE UserId IN :candidates
                  AND HasUserVerifiedEmailAddress = false
            ]) {
                unverified.add(info.UserId);
            }
        } catch (Exception e) {
            System.debug('Lecture TwoFactorMethodsInfo impossible : ' + e.getMessage());
            return candidates;
        }
        return unverified;
    }
}
