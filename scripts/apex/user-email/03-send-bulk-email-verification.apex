/**
 * 03 - VERIFICATION EN MASSE : envoie les liens de verification d'email.
 *
 * Execution : sf apex run --file scripts/apex/user-email/03-send-bulk-email-verification.apex
 *
 * C'EST L'EQUIVALENT EN MASSE DU BOUTON "Verify" DE SETUP > USERS.
 * Meme action, declenchee par lot au lieu d'un clic par fiche.
 *
 * Prerequis : Setup > Deliverability > Access to Send Email = "All email".
 * En sandbox le defaut "System email only" bloque tout envoi.
 *
 * PREMIER RUN = TEST DECISIF. Cibler UN SEUL utilisateur en .invalid via
 * emailDomainFilter, avec dryRun = false, puis observer :
 *   - le mail arrive-t-il a la vraie adresse ?
 *   - le suffixe .invalid disparait-il apres le clic ?
 * Si oui, ce script seul remplace tout le travail manuel et il n'y a pas de
 * correction d'adresses a faire. Si non, passer par le script 02.
 */

MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();

// true = compte les cibles sans rien envoyer.
batch.dryRun = true;

// true (defaut) = garde les adresses en .invalid dans le scope.
// Cf. en-tete : c'est precisement ce que le test decisif doit trancher.
batch.includeInvalidAddresses = true;

// null = tous les domaines. Renseigner pour cibler un lot.
batch.emailDomainFilter = null;

// true = ignore les utilisateurs dont l'email est deja verifie.
batch.onlyUnverified = true;

// Facultatif : template d'email et page d'atterrissage apres verification.
batch.emailTemplateId = null;
batch.networkId = null;
batch.startUrl = null;

Id jobId = Database.executeBatch(batch, 50);
System.debug('Batch lance : ' + jobId);
System.debug('Suivi : Setup > Apex Jobs, ou SELECT Status, JobItemsProcessed, '
    + 'TotalJobItems, NumberOfErrors FROM AsyncApexJob WHERE Id = \'' + jobId + '\'');
