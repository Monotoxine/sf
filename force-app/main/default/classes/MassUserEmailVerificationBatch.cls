/**
 * Envoi en masse des liens de verification d'adresse email utilisateur.
 *
 * Contexte : un utilisateur cree par API (Talend, Data Loader, ...) possede une
 * adresse email NON verifiee au sens "expediteur". Tant qu'elle n'est pas
 * verifiee, Salesforce refuse d'envoyer des emails au nom de cet utilisateur
 * ("The current user's email address isn't verified").
 *
 * Ce batch appelle System.UserManagement.sendAsyncEmailConfirmation() pour
 * chaque utilisateur cible : Salesforce envoie un lien de verification que
 * l'utilisateur clique une seule fois.
 *
 * Ce batch NE modifie AUCUNE adresse email : il ne fait qu'envoyer les liens,
 * exactement comme le bouton "Verify" de Setup > Users, mais en masse. C'est
 * donc le remplacement direct du clic manuel utilisateur par utilisateur.
 *
 * Si, dans votre org, ce clic retire aussi le suffixe ".invalid", ce batch
 * suffit a lui seul : laisser includeInvalidAddresses = true (defaut).
 * Sinon, corriger d'abord les adresses via scripts/apex/user-email/.
 *
 * Exemple d'appel :
 *   Database.executeBatch(new MassUserEmailVerificationBatch(), 50);
 *
 * Exemple cible (uniquement un domaine, uniquement les non verifies) :
 *   MassUserEmailVerificationBatch b = new MassUserEmailVerificationBatch();
 *   b.emailDomainFilter = 'mondomaine.com';
 *   b.onlyUnverified = true;
 *   Database.executeBatch(b, 50);
 */
public with sharing class MassUserEmailVerificationBatch
    implements Database.Batchable<sObject>, Database.Stateful {

    /** Ne cible que les utilisateurs dont l'email se termine par ce domaine. Null = tous. */
    public String emailDomainFilter;

    /** Restreint aux utilisateurs dont l'email n'est pas encore verifie. */
    public Boolean onlyUnverified = true;

    /** Template d'email personnalise (facultatif). Null = template standard. */
    public Id emailTemplateId;

    /** Network Experience Cloud (facultatif). Null = utilisateurs internes. */
    public Id networkId;

    /** Page d'atterrissage apres le clic de verification (facultatif). */
    public String startUrl;

    /** Mode simulation : compte les cibles sans envoyer d'email. */
    public Boolean dryRun = false;

    /**
     * Inclure les adresses se terminant par ".invalid" dans le scope.
     *
     * Defaut : true. Plusieurs orgs rapportent que l'action "Verify" retire le
     * suffixe une fois le lien clique par l'utilisateur ; ce comportement n'est
     * pas documente publiquement, mais le pari asymetrique penche clairement du
     * cote de l'inclusion : si l'org ne decape pas le suffixe, le message part
     * vers un TLD reserve (RFC 2606) et bounce, sans effet de bord ; si elle le
     * decape, exclure ces adresses ecarterait precisement les utilisateurs a
     * traiter.
     *
     * Passer a false pour ne cibler que les adresses deja propres.
     */
    public Boolean includeInvalidAddresses = true;

    public Integer sentCount = 0;
    public Integer skippedCount = 0;
    public Integer failedCount = 0;
    private List<String> errors = new List<String>();

    private static Boolean hasVerifiedEmailFieldCache;

    /**
     * True si le champ standard User.HasUserVerifiedEmail est disponible.
     * Detecte a l'execution : le champ n'existe pas dans toutes les orgs, et son
     * absence ne doit pas faire echouer le batch (repli sur TwoFactorMethodsInfo).
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
        String soql =
            'SELECT Id, Username, Email FROM User ' +
            'WHERE IsActive = true ' +
            'AND Email != null';

        if (includeInvalidAddresses == false) {
            soql += ' AND (NOT Email LIKE \'%.invalid\')';
        }

        // Filtrage a la source quand le champ standard est disponible : plus
        // efficace que le repli TwoFactorMethodsInfo, et sans permission
        // "Manage Multi-Factor Authentication in API".
        if (onlyUnverified == true && hasVerifiedEmailField()) {
            soql += ' AND HasUserVerifiedEmail = false';
        }

        // Declaree hors du bloc : la variable doit rester dans la portee au
        // moment ou Database.getQueryLocator resout le bind :domainLike.
        String domainLike = '%@' + emailDomainFilter;
        if (String.isNotBlank(emailDomainFilter)) {
            soql += ' AND Email LIKE :domainLike';
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

        for (User u : scope) {
            if (!targets.contains(u.Id)) {
                skippedCount++;
                continue;
            }
            if (dryRun == true) {
                sentCount++;
                continue;
            }
            try {
                System.UserManagement.sendAsyncEmailConfirmation(
                    u.Id, emailTemplateId, networkId, startUrl
                );
                sentCount++;
            } catch (Exception e) {
                failedCount++;
                if (errors.size() < 50) {
                    errors.add(u.Username + ' : ' + e.getMessage());
                }
            }
        }
    }

    public void finish(Database.BatchableContext ctx) {
        System.debug('MassUserEmailVerificationBatch termine.');
        System.debug('  Liens envoyes : ' + sentCount);
        System.debug('  Ignores (deja verifies) : ' + skippedCount);
        System.debug('  Echecs : ' + failedCount);
        for (String err : errors) {
            System.debug('  !! ' + err);
        }
    }

    /**
     * Repli pour les orgs ou le champ standard User.HasUserVerifiedEmail n'est
     * pas disponible : ne conserve que les utilisateurs non verifies.
     * TwoFactorMethodsInfo requiert la permission
     * "Manage Multi-Factor Authentication in API" ; si la lecture echoue, on
     * conserve l'ensemble des cibles (l'envoi a un utilisateur deja verifie
     * est sans effet de bord).
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
