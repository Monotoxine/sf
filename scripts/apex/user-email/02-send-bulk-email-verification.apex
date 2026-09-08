/**
 * VERIFICATION D'EMAIL EN MASSE - equivalent du bouton "Verify" de Setup > Users.
 *
 * Execution : sf apex run --file scripts/apex/user-email/02-send-bulk-email-verification.apex
 *
 * Chaque utilisateur cible recoit le mail de verification standard de Salesforce
 * et clique une fois. Aucune adresse email n'est modifiee.
 *
 * Prerequis : Setup > Deliverability > Access to Send Email = "All email".
 * En sandbox le defaut "System email only" bloque tout envoi.
 *
 * Deroule recommande :
 *   1. dryRun = true          -> compte les cibles, n'envoie rien
 *   2. userIds = { un Id }    -> un seul utilisateur, verifier qu'il recoit bien
 *   3. createdSince           -> le lot charge par l'integration
 *   4. sans filtre            -> rattrapage de tout le parc
 */

MassUserEmailVerificationBatch batch = new MassUserEmailVerificationBatch();

// --- Etape 1 : toujours commencer par une simulation ----------------------
batch.dryRun = true;

// --- Selection des cibles -------------------------------------------------
// true = ignore les utilisateurs dont l'email est deja verifie.
batch.onlyUnverified = true;

// Run pilote : un ou quelques Id precis. Prime sur tous les autres filtres.
// batch.userIds = new Set<Id>{ '005XXXXXXXXXXXXXXX' };

// Le lot charge par l'integration depuis 24h.
// batch.createdSince = System.now().addDays(-1);

// Restriction a un domaine d'adresses.
// batch.emailDomainFilter = 'mondomaine.com';

// --- Options d'envoi ------------------------------------------------------
batch.emailTemplateId = null;  // null = mail de verification standard
batch.networkId = null;        // null = utilisateurs internes
batch.startUrl = null;         // null = accueil de l'org apres le clic

Id jobId = Database.executeBatch(batch, 50);
System.debug('Batch lance : ' + jobId);
System.debug('Suivi : Setup > Apex Jobs, ou');
System.debug('  SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors '
    + 'FROM AsyncApexJob WHERE Id = \'' + jobId + '\'');
