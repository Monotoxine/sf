/**
 * 00 - DIAGNOSTIC : d'ou vient reellement le ".invalid" ?
 *
 * Execution : sf apex run --file scripts/apex/user-email/annexe-suffixe-invalid/diagnose-invalid-origin.apex
 *
 * A lancer AVANT toute correction de masse. Trois hypotheses possibles, ce
 * script les departage :
 *
 *   H1 - le suffixe est deja dans la charge utile envoyee par Talend
 *   H2 - un trigger / flow maison sur User l'ajoute a l'insert
 *   H3 - comportement plateforme au moment du refresh/clone de sandbox
 *        (seul cas documente par Salesforce)
 */

// --- A. Type d'org et date de creation/refresh de la sandbox ---------------
Organization org = [
    SELECT Id, Name, IsSandbox, InstanceName, OrganizationType, CreatedDate
    FROM Organization
    LIMIT 1
];
System.debug('=== ORG ===');
System.debug('  IsSandbox    : ' + org.IsSandbox);
System.debug('  Type         : ' + org.OrganizationType);
System.debug('  CreatedDate  : ' + org.CreatedDate);
System.debug('  -> sur une sandbox, CreatedDate = date du dernier refresh/clone.');

// --- B. Les users en .invalid sont-ils anterieurs ou posterieurs ? ---------
// H3 ne peut expliquer QUE les utilisateurs presents lors du refresh.
// Un utilisateur cree APRES cette date et porteur d'un .invalid elimine H3.
List<User> invalids = [
    SELECT Id, Username, Email, CreatedDate, CreatedBy.Name
    FROM User
    WHERE Email LIKE '%.invalid'
    ORDER BY CreatedDate DESC
    LIMIT 50
];
System.debug('=== 50 DERNIERS USERS EN .invalid ===');
Integer createdAfterOrg = 0;
for (User u : invalids) {
    if (u.CreatedDate > org.CreatedDate) {
        createdAfterOrg++;
    }
    System.debug('  ' + u.CreatedDate + ' | par ' + u.CreatedBy.Name + ' | ' + u.Email);
}
System.debug('  -> crees APRES la creation/refresh de l org : ' + createdAfterOrg);
System.debug('  -> si > 0, H3 est ecartee : le suffixe vient de H1 ou H2.');

// --- C. H2 : du code maison sur User ? ------------------------------------
System.debug('=== TRIGGERS APEX SUR USER ===');
for (ApexTrigger t : [
    SELECT Name, Status, TableEnumOrId
    FROM ApexTrigger
    WHERE TableEnumOrId = 'User'
]) {
    System.debug('  ' + t.Name + ' (' + t.Status + ')');
}

System.debug('=== FLOWS DECLENCHES SUR USER ===');
try {
    for (FlowDefinitionView f : [
        SELECT ApiName, Label, TriggerType, IsActive
        FROM FlowDefinitionView
        WHERE TriggerObjectOrEvent = 'User'
    ]) {
        System.debug('  ' + f.Label + ' | ' + f.TriggerType + ' | actif=' + f.IsActive);
    }
} catch (Exception e) {
    System.debug('  Lecture FlowDefinitionView impossible : ' + e.getMessage());
}
System.debug('  -> tout trigger/flow liste ici est a inspecter : un guard maison');
System.debug('     "securite sandbox" qui suffixe les emails est un grand classique.');

// --- D. H1 : test decisif -------------------------------------------------
// Le vrai depart entre H1 et (H2/H3) ne se joue pas en SOQL mais a l ecriture.
// Creer UN utilisateur a la main dans Setup > Users, avec une adresse propre,
// puis relire la valeur reellement stockee :
//
//   SELECT Id, Username, Email, CreatedDate FROM User ORDER BY CreatedDate DESC LIMIT 1
//
//   - email propre en base  -> le suffixe vient de la charge Talend        (H1)
//   - email suffixe en base -> le suffixe est ajoute cote org        (H2 ou H3)
//
// Ce test coute deux minutes et rend toute discussion inutile.
System.debug('=== TEST DECISIF : creer un user a la main dans Setup > Users,');
System.debug('    avec une adresse propre, puis relire la valeur stockee. ===');
