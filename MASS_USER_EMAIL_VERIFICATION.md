# Vérification en masse des emails utilisateurs (users créés via Talend)

Guide opérationnel pour débloquer des utilisateurs Salesforce créés par API dont
l'adresse email est en `.invalid` et/ou non vérifiée, **sans passer par l'interface
Salesforce user par user**.

---

## 0. Le cas concret : users créés par Talend, `.invalid` qui ne part jamais

**Symptôme.** Talend crée l'utilisateur. L'adresse porte `.invalid`. Aucun mail
de confirmation ne part. Seule solution trouvée jusqu'ici : rouvrir chaque
utilisateur dans **Setup → Users**, éditer l'email à la main, un par un.

**Pourquoi rien ne part.** Email Change Verification se déclenche sur un
**changement** d'adresse, pas sur une création. À l'insert, Salesforce pose
l'adresse telle quelle et n'a **rien à confirmer** — d'où le silence. Quand vous
éditez ensuite l'utilisateur dans l'interface, vous produisez ce changement, et le
mail part. C'est la seule différence entre les deux chemins.

### D'où vient le suffixe ? Trois hypothèses, un test décisif

C'est le point à trancher, et il ne se tranche que dans votre org :

| | Hypothèse | Correction |
|---|---|---|
| **H1** | le suffixe est déjà dans la charge utile envoyée par Talend | mapping Talend |
| **H2** | un trigger / flow maison sur `User` l'ajoute à l'insert | désactiver ou conditionner ce code |
| **H3** | comportement plateforme au refresh/clone de sandbox | ne concerne que les users **présents lors du refresh** |

**H3 est le seul comportement documenté par Salesforce**, et il s'applique aux
utilisateurs *copiés* au moment de la création, du refresh ou du clonage de la
sandbox — pas aux utilisateurs créés après. La documentation ne décrit aucun ajout
de `.invalid` à l'insert d'un nouvel utilisateur.

Cela dit, H2 est fréquent en entreprise : un `before insert` maison sur `User` qui
suffixe les emails est un garde-fou « sécurité sandbox » très classique, et de
l'extérieur il est indiscernable d'un comportement standard.

**Test décisif, deux minutes.** Créez **un** utilisateur à la main dans
Setup → Users avec une adresse propre, puis relisez la valeur réellement stockée :

```sql
SELECT Id, Username, Email, CreatedDate FROM User ORDER BY CreatedDate DESC LIMIT 1
```

- adresse **propre** en base → le suffixe vient de Talend (**H1**)
- adresse **suffixée** en base → il est ajouté côté org (**H2** ou **H3**)

Le script `scripts/apex/user-email/00-diagnose-invalid-origin.apex` automatise le
reste : type d'org, date du dernier refresh, comparaison avec le `CreatedDate` des
users concernés, et inventaire des triggers et flows actifs sur `User`.

> **Ce diagnostic ne bloque rien.** Quelle que soit l'hypothèse retenue, la méthode
> de rattrapage de masse ci-dessous est **identique**. Le diagnostic sert
> uniquement à savoir s'il faudra refaire ce rattrapage au prochain lot.

### Les deux réponses à apporter

**① Le stock (utilisateurs déjà créés) → update de masse.**

Modifier `User.Email` par API déclenche **exactement le même mail de confirmation**
que votre édition manuelle. L'API ne contourne rien, mais elle ne saute rien non
plus. 500 utilisateurs corrigés en une passe = 500 mails de confirmation envoyés,
au lieu de 500 éditions à la main. C'est le remplacement 1:1 de votre travail
manuel.

- Data Loader : `scripts/soql/users-invalid-email.soql` (export → nettoyage du CSV → Update)
- ou Apex : `scripts/apex/user-email/02-strip-invalid-emails.apex`

Chaque utilisateur reçoit le lien à sa vraie adresse et clique une fois (72 h).
L'ancienne adresse reste affichée jusqu'au clic.

**② Le flux (utilisateurs à venir) → dépend du diagnostic ci-dessus.**

- **H1** → corriger le mapping Talend pour insérer la **vraie** adresse. À
  l'insert il n'y a pas de vérification de changement : l'adresse est posée
  directement et définitivement. C'est la correction la moins chère.
- **H2** → conditionner ou désactiver le trigger/flow qui suffixe.
- **H3** → rien à corriger dans le flux : le suffixe ne reviendra qu'au prochain
  refresh de sandbox, et le rattrapage sera à rejouer à ce moment-là.

Sans cette étape, le rattrapage de masse est à refaire à chaque lot.

**③ Si vous voulez aussi supprimer le clic utilisateur** — pour que l'update de
masse s'applique immédiatement, sans que personne n'ait à cliquer : c'est la §3
(Authorized Email Domains), et uniquement elle.

---

## 1. Le point clé : il y a DEUX vérifications différentes

C'est la source de 90 % de la confusion sur ce sujet. Salesforce appelle les deux
« email verification », mais ce sont deux mécanismes distincts, avec deux solutions
distinctes.

| | **A. Email Change Verification** | **B. User-level Email Verification** |
|---|---|---|
| **Se déclenche quand** | on **modifie** `User.Email` (UI **et** API / Data Loader / Talend) | l'utilisateur **existe** avec une adresse jamais confirmée |
| **Symptôme** | l'update part sans erreur mais l'adresse reste l'ancienne ; mail « Verify your new Salesforce email address » envoyé à la **nouvelle** adresse, valable 72 h | `The current user's email address isn't verified` au moment d'envoyer un email |
| **Bloque** | le retrait du `.invalid` | l'envoi d'email *au nom de* l'utilisateur |
| **Indicateur** | — | `TwoFactorMethodsInfo.HasUserVerifiedEmailAddress` |
| **Solution de masse** | **Authorized Email Domains** (§3) | **`sendAsyncEmailConfirmation`** en batch (§5) |

Le blocage décrit dans la demande initiale est **circulaire** et relève du cas A :
l'adresse est en `.invalid` → le mail de confirmation part vers une adresse
inexistante → personne ne peut cliquer → le `.invalid` ne part jamais.

**On ne casse pas cette boucle avec un script.** Il faut d'abord désactiver
l'exigence de vérification au niveau du domaine (§3), *ensuite* le script de masse
fonctionne.

---

## 2. Le cas du refresh de sandbox (H3) en détail

Le seul ajout de `.invalid` documenté par Salesforce se produit à la **création,
au refresh ou au clonage** d'une sandbox : les emails des utilisateurs *copiés*
sont suffixés pour que les users de production ne reçoivent pas les mails de la
sandbox. `atester@uc.com` devient `atester@uc.com.invalid`.

Deux détails qui aident à reconnaître ce cas :

- le **username** est lui aussi modifié (suffixe du nom de la sandbox), alors que
  H1 et H2 ne touchent en général que l'email ;
- l'utilisateur **qui a lancé le refresh** est exempté : son adresse reste intacte.

Et le point qui tranche : ce mécanisme ne s'applique **qu'aux utilisateurs
présents au moment du refresh**. Des utilisateurs dont le `CreatedDate` est
postérieur à celui de l'org et qui portent malgré tout un `.invalid` écartent
définitivement H3.

```bash
sf apex run --file scripts/apex/user-email/00-diagnose-invalid-origin.apex
```

---

## 3. La solution de fond : Authorized Email Domains

C'est la méthode **officielle, self-service et scalable** pour ne plus dépendre
d'un clic utilisateur. Elle traite les cas A **et** B d'un coup, pour tout un
domaine.

**Setup → Authorized Email Domains**

1. Ajouter le domaine (ex. `mondomaine.com`).
2. Publier l'enregistrement **DNS TXT** fourni pour prouver la propriété du domaine.
3. Une fois le domaine vérifié : **Edit** sur le domaine → désactiver
   **« Require email verification »**.

Variante équivalente : une **clé DKIM active** sur le domaine, plus l'option de
bypass correspondante dans les réglages de délivrabilité — le bypass s'applique
alors à *tous* les domaines ayant une clé DKIM active.

Résultat : les utilisateurs dont l'adresse est sur ce domaine ne passent plus par
la vérification individuelle. Les mises à jour de masse par API deviennent
immédiates.

> **⚠️ Impact sécurité, à assumer explicitement.** Le bypass s'applique à *toutes*
> les adresses du domaine. Salesforce pourra envoyer des emails au nom de
> n'importe quelle adresse `@mondomaine.com`, et toute personne pouvant créer des
> utilisateurs pourra usurper une adresse de ce domaine. À réserver aux domaines
> dont vous contrôlez strictement la création de comptes.

---

## 4. ⚠️ L'ancienne méthode (case Support) est en fin de vie

Historiquement, on demandait au Support Salesforce de **désactiver « Email Change
Verification »** au niveau de l'org (case avec General Application Area =
*Feature Activation*).

**Cette exemption est en cours de retrait.** Elle est remplacée par les Authorized
Email Domains décrits en §3, avec une échéance d'application annoncée au
**1er décembre 2026**. Ne construisez pas votre processus dessus : si votre org
bénéficie encore de l'exemption, migrez vers §3.

---

## 5. Vérification en masse des emails (cas B)

Une fois les adresses correctes, il reste à faire passer les utilisateurs en
« email vérifié » pour qu'ils puissent envoyer des emails depuis Salesforce.

L'API Apex dédiée est :

```apex
System.UserManagement.sendAsyncEmailConfirmation(
    userId,          // Id de l'utilisateur
    emailTemplateId, // template personnalisé, ou null
    networkId,       // site Experience Cloud, ou null pour les users internes
    startUrl         // page d'atterrissage après le clic, ou null
);
```

Elle est encapsulée ici dans un batch gouverneur-safe :
`force-app/main/default/classes/MassUserEmailVerificationBatch.cls`.

```apex
MassUserEmailVerificationBatch b = new MassUserEmailVerificationBatch();
b.dryRun = true;                              // simulation d'abord
b.onlyUnverified = true;                      // ignore les déjà vérifiés
b.emailDomainFilter = 'mondomaine.com';       // null = tous les domaines
Database.executeBatch(b, 50);
```

Le batch exclut systématiquement les adresses en `.invalid` de son scope : envoyer
un lien de vérification à une adresse `.invalid` ne peut, par construction, pas
aboutir.

**Cette méthode envoie les liens en masse ; l'utilisateur clique quand même une
fois.** Pour supprimer complètement le clic, c'est §3 et uniquement §3.

---

## 6. Procédure recommandée, dans l'ordre

```
0. Diagnostic            scripts/apex/user-email/00-diagnose-invalid-origin.apex
                         + créer 1 user à la main et relire l'email stocké  (§0)
                         -> détermine H1 / H2 / H3
1. Audit                 scripts/apex/user-email/01-audit-users-email.apex
2. Délivrabilité         Setup > Deliverability > Access to Send Email = "All email"
                         (en sandbox la valeur par défaut "System email only"
                          bloque AUSSI les mails de confirmation : rien ne part)
3. Corriger la source    selon le diagnostic de l'étape 0                   (§0②)
                         -> évite d'avoir à rejouer le rattrapage au prochain lot
4. (optionnel) Domaine   Setup > Authorized Email Domains                   (§3)
                         -> uniquement si le clic utilisateur doit disparaître
5. Rattrapage du stock   Data Loader : scripts/soql/users-invalid-email.soql
                         ou Apex     : scripts/apex/user-email/02-strip-invalid-emails.apex
                         (DRY_RUN = true d'abord, puis un lot pilote)
6. Vérification en masse scripts/apex/user-email/03-send-bulk-email-verification.apex
                         (dryRun = true d'abord)
7. Contrôle              rejouer l'audit de l'étape 1
```

L'étape 5 est la réponse directe au besoin « ne plus le faire user par user », et
elle ne dépend **pas** du résultat de l'étape 0. Les deux variantes (Data Loader et
Apex) sont **strictement équivalentes** du point de vue de Salesforce : mêmes mails
de confirmation envoyés, mêmes règles. Choisir selon l'outillage de l'équipe.

L'étape 6 ne concerne que la vérification « expéditeur » (cas B du §1) : elle est
inutile si le besoin s'arrête à faire disparaître le `.invalid`.

---

## 7. Points de vigilance

- **`Username` ≠ `Email`.** Le `Username` est un simple identifiant de connexion :
  il ne demande **aucune** vérification et peut être mis à jour librement en masse.
  Seul l'`Email` est soumis à vérification. En sandbox les deux sont suffixés.
- **Délivrabilité sandbox.** Tant que l'accès est sur `System email only`, aucun
  mail de vérification ne part — y compris ceux du script §5.
- **Permission requise** pour lire `TwoFactorMethodsInfo` :
  *Manage Multi-Factor Authentication in API*. Sans elle, le filtre « non
  vérifiés » est ignoré et le batch traite toutes les cibles.
- **Ne jamais** retirer le `.invalid` dans une sandbox contenant des adresses de
  production réelles sans avoir mesuré le volume d'emails automatiques qui va
  partir vers de vraies boîtes.
- **Pilote d'abord.** Toujours dérouler la procédure sur un lot restreint
  (`emailDomainFilter`, ou une poignée d'utilisateurs) avant l'ensemble du parc.

---

## Sources

- [Sandbox: User Email Addresses Appended With '.invalid' After Sandbox Refresh or Clone](https://help.salesforce.com/s/articleView?id=Sandbox-email-addresses-appended-with-invalid-on-User-records-post-refresh&language=en_US&type=1)
- [How to Change the Email Address of a Salesforce User – Individual, Bulk, and Sandbox Scenarios](https://help.salesforce.com/s/articleView?language=en_US&id=000340139&mode=1&type=1)
- [How to Mass Update User Email Addresses and Usernames](https://help.salesforce.com/s/articleView?id=000387708&language=en_US&type=1)
- [Bypass User Email Verification for Domains That You Own (Winter '26)](https://help.salesforce.com/s/articleView?id=release-notes.rn_bypass_user_email_verification.htm&language=en_US&release=256&type=5)
- [Use a Verified Domain for User-Level Email Verification](https://help.salesforce.com/s/articleView?id=xcloud.security_email_verification_user_bypass.htm&language=en_US&type=5)
- [Verify Email Addresses with Async Email](https://help.salesforce.com/s/articleView?id=xcloud.emailadmin_async_email_verification.htm&language=en_US&type=5)
- [Send Asynchronous Email Verifications](https://help.salesforce.com/s/articleView?language=en_US&id=release-notes.rn_identity_async_email.htm&release=218&type=5)
- [Disable 'Email Change Verification'](https://help.salesforce.com/s/articleView?id=000385107&language=en_US&type=1)
- [Salesforce Is Retiring the Email Change Verification Exemption](https://www.softwareinsights.dev/posts/salesforce-email-change-verification-retirement-authorized-email-domains/)
- [Salesforce's New Email Domain Verification Explained – Salesforce Ben](https://www.salesforceben.com/salesforces-new-email-domain-verification-explained/)
- [TwoFactorMethodsInfo – Object Reference](https://developer.salesforce.com/docs/atlas.en-us.object_reference.meta/object_reference/sforce_api_objects_twofactormethodsinfo.htm)
