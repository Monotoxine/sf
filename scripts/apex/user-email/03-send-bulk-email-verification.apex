/**
 * 03 - VERIFICATION EN MASSE : envoie les liens de verification d'email.
 *
 * Execution : sf apex run --file scripts/apex/user-email/03-send-bulk-email-verification.apex
 *
 * Prerequis :
 *   - les adresses ne doivent plus contenir ".invalid" (cf. script 02)
 *   - Setup > Deliverability > Access to Send Email = "All email"
 *
 * Commencer IMPERATIVEMENT par un run en dryRun = true, puis par un domaine
 * de test, avant de lancer sur l'ensemble des utilisateurs.
 */

MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();

// true = compte les cibles sans rien envoyer.
batch.dryRun = true;

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
