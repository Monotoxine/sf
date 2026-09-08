/**
 * VERIFICATION D'EMAIL EN MASSE (+ reset de mot de passe optionnel).
 *
 * Execution : sf apex run --file scripts/apex/user-email/02-send-bulk-email-verification.apex
 *
 * Equivalent en masse de deux gestes de Setup > Users :
 *   - le bouton "Verify" a cote de l'adresse email
 *   - la case "Generate new password and notify user immediately"
 *
 * Prerequis : Setup > Deliverability > Access to Send Email = "All email".
 * En sandbox le defaut "System email only" bloque tout envoi.
 *
 * Deroule recommande :
 *   1. dryRun = true          -> compte les cibles, n'envoie rien
 *   2. userIds = { un Id }    -> un seul utilisateur, verifier qu'il recoit bien
 *   3. createdSince           -> le lot charge par l'integration
 *   4. sans filtre            -> rattrapage de tout le parc
 *
 * ATTENTION TAILLE DE LOT : avec sendPasswordReset = true, le second argument de
 * Database.executeBatch DOIT valoir 10 (plafond Salesforce de 10 appels a
 * System.resetPassword par transaction). Sans reset, 50 convient.
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

// --- Actions a declencher -------------------------------------------------
// Lien de verification d'adresse.
batch.sendVerification = true;

// Reinitialisation du mot de passe + envoi des identifiants.
// INVALIDE le mot de passe existant. Impose une taille de lot de 10.
batch.sendPasswordReset = false;
batch.notifyUserOnReset = true;

// Pour un reset SEUL, mettre sendVerification = false ET onlyUnverified = false,
// sinon les utilisateurs deja verifies seraient ecartes de la selection.

// --- Options d'envoi ------------------------------------------------------
batch.emailTemplateId = null;  // null = mail de verification standard
batch.networkId = null;        // null = utilisateurs internes
batch.startUrl = null;         // null = accueil de l'org apres le clic

// 10 des que sendPasswordReset est actif, 50 sinon.
Integer scopeSize = batch.sendPasswordReset == true ? 10 : 50;
Id jobId = Database.executeBatch(batch, scopeSize);
System.debug('Batch lance : ' + jobId);
System.debug('Suivi : Setup > Apex Jobs, ou');
System.debug('  SELECT Status, JobItemsProcessed, TotalJobItems, NumberOfErrors '
    + 'FROM AsyncApexJob WHERE Id = \'' + jobId + '\'');
