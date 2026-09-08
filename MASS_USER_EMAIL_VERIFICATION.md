# Vérification d'email en masse pour les utilisateurs créés par API

## Le problème

Créer un utilisateur par API (Talend, Data Loader, Bulk API) n'envoie **aucun**
mail de vérification d'adresse. Résultat :

- l'utilisateur reste **non vérifié** ;
- l'action **Verify** subsiste à côté de son email dans Setup → Users ;
- Salesforce refuse d'envoyer des mails en son nom
  (`The current user's email address isn't verified`) ;
- sans outil, il faut cliquer ce lien **fiche par fiche**.

La création ne déclenche pas la vérification, et Salesforce n'expose pas de bouton
« tout vérifier » dans l'interface. D'où le travail manuel.

## La solution

Salesforce documente une API dédiée, l'**async email verification** :

```apex
System.UserManagement.sendAsyncEmailConfirmation(
    userId,          // Id de l'utilisateur
    emailTemplateId, // template personnalisé, ou null pour le mail standard
    networkId,       // site Experience Cloud, ou null pour les users internes
    startUrl         // page d'atterrissage après le clic, ou null
);
```

C'est **exactement l'action du bouton Verify**, appelable par code. Reste à
l'appeler pour N utilisateurs sans exploser les limites : c'est le rôle de
`MassUserEmailVerificationBatch`.

Le batch **ne modifie aucune adresse email**. Il envoie les liens, les
utilisateurs cliquent une fois, et passent en `Email Verified`.

---

## Déploiement

⚠️ **`Invalid type: MassUserEmailVerificationBatch` ?** La classe n'est pas encore
dans l'org. Un script anonyme ne peut référencer qu'une classe déjà déployée.

```bash
sf project deploy start \
  --source-dir force-app/main/default/classes/MassUserEmailVerificationBatch.cls \
  --source-dir force-app/main/default/classes/MassUserEmailVerificationBatch.cls-meta.xml \
  --source-dir force-app/main/default/classes/MassUserEmailVerificationBatch_Test.cls \
  --source-dir force-app/main/default/classes/MassUserEmailVerificationBatch_Test.cls-meta.xml \
  --target-org <alias>
```

En **production**, le déploiement exige l'exécution des tests :

```bash
sf project deploy start --source-dir force-app/main/default/classes \
  --test-level RunSpecifiedTests --tests MassUserEmailVerificationBatch_Test \
  --target-org <alias>
```

### Sans rien déployer

Pour un essai immédiat ou un volume modeste, un script autonome fait le même
travail sans aucune classe à déployer :

```bash
sf apex run --file scripts/apex/user-email/00-standalone-send-verification.apex
```

Il traite `MAX_PER_RUN` utilisateurs par exécution et affiche combien il en reste —
à relancer jusqu'à zéro. Il affiche aussi le nombre d'invocations email
consommées, ce qui permet de mesurer le coût réel d'un appel avant d'augmenter le
lot. Le batch reste préférable au-delà de quelques centaines d'utilisateurs.

---

## Utilisation

### 1. Auditer

```bash
sf apex run --file scripts/apex/user-email/01-audit-users-email.apex
```

Liste les utilisateurs actifs non vérifiés et rappelle le réglage de
délivrabilité à contrôler.

### 2. Simuler

```apex
MassUserEmailVerificationBatch b = new MassUserEmailVerificationBatch();
b.dryRun = true;              // compte les cibles, n'envoie rien
b.onlyUnverified = true;
Database.executeBatch(b, 50);
```

### 3. Run pilote sur un seul utilisateur

Pour **un seul** utilisateur, le batch est surdimensionné : il s'exécute en
asynchrone, donc ses compteurs partent dans un autre log que celui du lancement.
Un appel direct suffit et remonte l'erreur immédiatement :

```apex
System.UserManagement.sendAsyncEmailConfirmation('005XXXXXXXXXXXXXXX', null, null, null);
```

Vérifier ensuite que le mail arrive, puis que la fiche passe en `Email Verified`
après le clic.

### 4. Le lot chargé par l'intégration

```apex
MassUserEmailVerificationBatch b = new MassUserEmailVerificationBatch();
b.createdSince = System.now().addDays(-1);
Database.executeBatch(b, 50);
```

C'est le mode à câbler en routine après chaque chargement Talend.

### 5. Rattrapage de tout le parc

```apex
Database.executeBatch(new MassUserEmailVerificationBatch(), 50);
```

Script prêt à l'emploi et commenté :
`scripts/apex/user-email/02-send-bulk-email-verification.apex`
(ou `00-standalone-send-verification.apex` si vous ne déployez pas la classe)

### 6. Contrôler le résultat

```bash
sf apex run --file scripts/apex/user-email/03-check-results.apex
```

Le batch étant asynchrone, ses compteurs `sentCount` / `failedCount` sont écrits
dans le log de l'exécution asynchrone, **pas** dans celui du lancement — qui ne
montre que l'Id du job. Ce script récupère l'état des derniers jobs
(`AsyncApexJob`), l'état de vérification d'utilisateurs précis, et le volume
restant, sans avoir à fouiller les logs.

Équivalent dans l'interface : **Setup → Apex Jobs**.

---

## Paramètres

| Paramètre | Défaut | Rôle |
|---|---|---|
| `dryRun` | `false` | compte les cibles sans rien envoyer |
| `onlyUnverified` | `true` | ignore les utilisateurs déjà vérifiés |
| `userIds` | `null` | sélection explicite, **prime sur tous les autres filtres** |
| `createdSince` | `null` | ne cible que les utilisateurs créés depuis cette date |
| `emailDomainFilter` | `null` | restreint à un domaine d'adresses |
| `emailTemplateId` | `null` | template personnalisé, sinon mail standard |
| `networkId` | `null` | site Experience Cloud, sinon utilisateurs internes |
| `startUrl` | `null` | page d'atterrissage après le clic |
| `includeInvalidAddresses` | `true` | garde les adresses en `.invalid` (voir annexe) |

---

## Points de vigilance

**Délivrabilité.** `Setup → Deliverability → Access to Send Email` doit être sur
**All email**. En sandbox le défaut est `System email only`, et dans ce cas aucun
mail ne part — ni en manuel, ni en masse. C'est la cause n°1 d'un batch qui
signale des envois sans que personne ne reçoive rien.

**Limites d'envoi.** Les envois vers les utilisateurs **internes** de l'org ne
sont pas plafonnés. Le plafond de 5 000 mails/jour ne concerne que les adresses
externes : à prendre en compte pour un parc Experience Cloud.

**Détection des non vérifiés.** Le batch et l'audit utilisent en priorité le champ
standard `User.HasUserVerifiedEmail`, qui n'exige aucune permission particulière.
Ils ne retombent sur `TwoFactorMethodsInfo` que si l'org n'expose pas ce champ —
et cet objet exige alors la permission *Manage Multi-Factor Authentication in API*.

**Suivi sans code.** Setup → Users → Create New View, en ajoutant les colonnes de
vérification (dont *Email Verified*). Permet de suivre l'avancement sans relancer
de script.

**Anomalie connue Summer '26.** Sur le flux de *changement* d'adresse, le clic sur
*Verify Email Address* peut renvoyer vers la page de login sans appliquer le
changement — [Issue a02Ka00000mGGGyIAO](https://help.salesforce.com/s/issue?language=en_US&id=a02Ka00000mGGGyIAO).
Ne concerne pas la vérification d'une adresse inchangée, mais à connaître si un
utilisateur signale un lien qui ne fait rien.

---

## Supprimer complètement le clic utilisateur

Le batch envoie les liens ; l'utilisateur clique quand même une fois. Pour que la
vérification ne soit plus requise du tout sur un domaine que vous possédez :

**Setup → Authorized Email Domains**

1. Ajouter le domaine, publier l'enregistrement **DNS TXT** de preuve de propriété.
2. Éditer le domaine → désactiver **« Require email verification »**.

Variante équivalente : une **clé DKIM active** sur le domaine plus l'option de
bypass correspondante dans les réglages de délivrabilité.

> **⚠️ Impact sécurité.** Le bypass s'applique à *toutes* les adresses du domaine.
> Salesforce pourra envoyer au nom de n'importe quelle adresse de ce domaine, et
> toute personne pouvant créer des utilisateurs pourra en usurper une. À réserver
> aux domaines dont vous contrôlez strictement la création de comptes.

À noter également : l'ancienne exemption obtenue par case Support (désactivation
d'« Email Change Verification ») **est en cours de retrait**, échéance annoncée au
1er décembre 2026, au profit de ce mécanisme. Ne pas construire dessus.

---

## Annexe — le suffixe `.invalid`

Sans rapport avec le problème ci-dessus, mais fréquemment confondu avec lui.

À la **création, au refresh ou au clonage** d'une sandbox, Salesforce suffixe les
emails des utilisateurs *copiés* en `.invalid`, pour que les users de production
ne reçoivent pas les mails de la sandbox. Ces adresses ne peuvent rien recevoir
(`.invalid` est un TLD réservé par la [RFC 2606](https://datatracker.ietf.org/doc/html/rfc2606)),
donc y envoyer un lien de vérification est vain.

Deux repères : le **username** est lui aussi modifié, et l'utilisateur qui a lancé
le refresh est exempté. Le mécanisme ne touche que les utilisateurs présents au
moment du refresh — jamais ceux créés après.

Outils dans `scripts/apex/user-email/annexe-suffixe-invalid/` :

- `diagnose-invalid-origin.apex` — d'où vient le suffixe : données source de
  l'intégration, trigger/flow maison sur `User`, ou refresh de sandbox
- `strip-invalid-emails.apex` — retrait en masse du suffixe (dry-run par défaut)
- `users-invalid-email.soql` — même opération via Data Loader

⚠️ Retirer le suffixe est un **changement** d'adresse : cela déclenche Email
Change Verification, et l'adresse ne bascule qu'après le clic de l'utilisateur.
C'est un flux différent de la vérification traitée plus haut.

---

## Sources

- [Verify Email Addresses with Async Email](https://help.salesforce.com/s/articleView?id=xcloud.emailadmin_async_email_verification.htm&language=en_US&type=5)
- [Send Asynchronous Email Verifications](https://help.salesforce.com/s/articleView?language=en_US&id=release-notes.rn_identity_async_email.htm&release=218&type=5)
- [User Email Verification](https://help.salesforce.com/s/articleView?id=sf.security_user_email_verification.htm&language=en_US&type=5)
- [Verify User Email Addresses](https://help.salesforce.com/s/articleView?id=release-notes.rn_security_verify_user_email_addresses.htm&language=en_US&release=244&type=5)
- [Bypass User Email Verification for Domains That You Own](https://help.salesforce.com/s/articleView?id=release-notes.rn_bypass_user_email_verification.htm&language=en_US&release=256&type=5)
- [Use a Verified Domain for User-Level Email Verification](https://help.salesforce.com/s/articleView?id=xcloud.security_email_verification_user_bypass.htm&language=en_US&type=5)
- [Single Email Daily Limits for Emails Sent Using Apex](https://help.salesforce.com/s/articleView?id=000384947&language=en_US&type=1)
- [TwoFactorMethodsInfo – Object Reference](https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_twofactormethodsinfo.htm)
- [Sandbox: User Email Addresses Appended With '.invalid'](https://help.salesforce.com/s/articleView?id=Sandbox-email-addresses-appended-with-invalid-on-User-records-post-refresh&language=en_US&type=1)
