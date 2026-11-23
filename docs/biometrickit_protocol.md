# BiometricKit / Mesa — protocole d'enrôlement 0x03 & réponse d'erreur GT (source: kext + userland, macOS 27.2.1)

2026-11-23 — session PC (ALARM, agent exécuté sur le Mac sous Linux). Mission `docs/mission_pc_biometrickit.md`.
But : établir, pour préparer un `0x03` (commandStartEnroll) **accepté** par le SEP, le contenu réel de
`enroll_indata_v2_t` (surtout le **jeton** à +0x10) et le sens de la réponse `TAG 0xff` vue en J6a. **Portée
protocole/séquence/format uniquement. Aucune clé, aucun secret, aucune donnée biométrique, aucun code Apple copié.**

## Sources (IPSW public Apple, pas de matériel leaké)
- **IPSW** : `UniversalMac_27.2.1_26B131_Restore.ipsw` (apple,j314c = MacBookPro18,4), **la version installée sur le Mac**
  (handoff, `~/mac-dfu/…27.2.1_26B131…`), téléchargée via l'outil open source `ipsw` v3.1.750 (blacktop), source
  `updates.cdn-apple.com`. Déposée dans `macos/` (gitignoré, `git check-ignore macos/` = OK).
- **kernelcache** : `macos/kc/26B131__MacBookPro18,4/kernelcache.release.Mac13,1_2_MacBookPro18,1_2_3_4` (fileset
  MH_FILESET arm64e). Désassemblé avec `ipsw macho disass -t <bundle> -s <symbole>`.
- **userland** : `biometrickitd` (volume système de l'IPSW, monté RO via `apfs-fuse` + extrait `7z`) et
  `BiometricKit.framework` / `BiometricSupport.framework` (cache dyld monté RO via `apfs-fuse`, lus `ipsw dyld
  macho --strings` / `class-dump`). Voir §A. (Le decmpfs type 14 / LZBITMAP du cache dyld n'est lisible qu'avec
  `apfs-fuse` — `7z` liste mais ne décompresse pas ce type ; `apfs-fuse` compilé localement, go d'Albert.)

**Convention de statut** : **VU** = lu dans le désassemblage (adresse/symbole/immédiat) ; **DÉDUIT** = interprété
d'après noms/contexte ; **INCONNU** = non déterminé. `source: kext` (kernelcache) / `source: userland` (dyld).

---

## c. Sens de la réponse `TAG 0xff` sur EP 0x08 (J6a) — VU, `source: kext` — **RÉPONSE : c'est l'erreur de la couche GenericTransfer**

J6a (journal 2026-11-22 23:04) : notre `> 0x08 TAG 0xfc TYPE 0x03` (68 o nuls) → `< 0x08 TAG 0xff TYPE 0x03`
(mot mailbox `0x000000000003ff08`), B8 non réécrit.

Le mot mailbox EP 0x08 a, bits 8-15, un **octet de type GenericTransfer** (kext §13 : `message = (tag<<48) |
(data<<16) | (type<<8) | endpoint`). Ce que la trace J6a nomme « TAG 0xff » **est cet octet de type = 0xff**.

**VU** (`com.apple.iokit.AppleSEPGenericTransfer`, `_gt_handle_generic_transaction` @0xfffffe0009cb5148, appelé par
`sepMessageHandler` @0xfffffe0009cb6c28) : le handler des messages **entrants** (SEP→AP) fait `ubfx w8, w1, #8, #8`
(= l'octet de type, bits 8-15) puis un switch :

| octet de type (bits 8-15) | branche VU | rôle |
|---|---|---|
| 0xfc | `_gt_read_first_packet` | 1er (ou seul) paquet d'un transfert — cas normal |
| 0xfd | `_gt_read_next_packet` | paquet suivant (fragment) |
| 0xfe | `_gt_write_next_packet` | le SEP réclame la suite des données à l'AP |
| **0xff** | **`_gt_read_error`** | **trame d'ERREUR de la couche GT** |
| autre | assert `AssertMacros … line 0x140` → erreur `0x102` | inconnu |

**Donc `TAG 0xff` = le SEP a répondu par une trame d'erreur GenericTransfer**, pas par un `0xfc` de données. La
transaction `0x03` a été **rejetée** au niveau GT/commande (confirme l'hypothèse « refus » du journal, maintenant VU).

**Où lire le code d'erreur (VU, `_gt_read_error` @0xfffffe0009cb5088)** : la fonction vérifie `oolBuffer != NULL` et
`oolBufferSize > 0x1c` (assert `"oolBufferSize > sizeof(header)"`), puis renvoie `w0 = *(u32*)(oolBuffer + 0x10)`.
→ **le code d'erreur de la trame 0xff est le u32 à l'offset +0x10 du `gt_packet_t` du buffer OOL de réponse**
(le champ jusque-là noté « réservé » en kext §13). Recoupé avec `_gt_read_first_packet` (@0xfffffe0009cb4a64), qui
sur un `0xfc` normal lit `ldp w23,w22,[x20,#0x14]` = **opcode (+0x14) + longueur de fragment (+0x18)** et prend le
payload à `+0x1c` (`add x1,x20,#0x1c`) — mêmes offsets que le `gt_packet_t` vérifié en trace (kext §13b). Donc sur
`0xff`, le même en-tête est présent mais c'est le mot `+0x10` qui porte le code d'erreur (et non l'opcode). En J6a,
**B8 n'a pas été réécrit** : soit le SEP a rejeté avant d'écrire l'OOL, soit la capture ne l'a pas vu → **le code
exact n'a pas été lu** (INCONNU pour ce run ; une capture avec B8 lu le donnerait). Les bits 16-23 du mot mailbox
(= « TYPE 0x03 ») sont le **contexte d'opcode** ré-émis, pas le code.

> Côté `AppleSEPGenericTransfer::transact` (@0xfffffe0009cb7048, l'émetteur), une trame d'erreur fait signaler la
> `GTCondition` et renvoyer un code `0xe00002c2`-famille (VU `_gt_transfer_error` @0xfffffe0009cb7acc : `0xe0000` |
> `0x2c2`, variantes `-6` …) à l'appelant `sepTransact` → à `commandStartEnroll`, qui log alors `err == 0` raté.

---

## a. `enroll_indata_v2_t` (0x44 o) & le jeton +0x10 — ce que fait le KEXT (VU, `source: kext`)

`AppleMesaSEPDriver::commandStartEnroll(enroll_indata_v2_t*)` @0xfffffe0009a43254 (bundle
`com.apple.driver.AppleMesaSEPDriver`, macOS 27.2.1) :
- **Gating local avant tout envoi (VU, 3 asserts)** : `enrollInit != NULL` (le pointeur d'entrée), `!_mesaDisabled`,
  `isMesaDeviceAvailable()`. Aucun autre contrôle (pas de vérif de jeton côté AP).
- **Lecture (VU)** : `ldr w8,[x20]` = 1er u32 de la struct (`+0x00`) ; `str w8,[x19,#0x1cf8]` (stocke la valeur
  entière) et `and w8,w8,#1 ; strb w8,[x21,#0x218]` (bit 0 → un drapeau d'état). **Seul ce bit 0 de +0x00 est lu
  par le kext.** Le reste des 68 octets n'est **pas** inspecté.
- **Envoi (VU)** : `mov w1,#0x3 ; mov x2,x20 ; mov w3,#0x44 ; mov w6,#1 ; blraa` (slot vtable `sepTransact`,
  discriminant PAC `#0x3d75`) = **`sepTransact(opcode=0x03, in=enroll_indata_v2_t, inLen=0x44, out=0, flag=1)`**.
  → **les 68 octets sont transmis TELS QUELS au SEP** (payload du `gt_packet_t` opcode 0x03, offset +0x1c).

**Côté dispatch (VU, `performSpecificCommandGated` @0xfffffe0009a3eb34)** : la commande d'enrôlement arrive de
l'userspace comme un `bm_cmd_t` (en-tête magique `0x4d42` « BM »/`0x4d43` « BMC », opcode à +0x2, payloadSize) avec un
**payload** ; le cas correspondant exige `payloadSize > 0x4b` (VU `cmp x24,#0x4b ; b.ls → erreur`), **copie 0x4c o du
payload userspace** sur la pile (VU : lectures `ldp q0,q1,[x8]`, `ldp q0,q1,[x8,#0x20]`, `ldur q0,[x8,#0x3c]` =
octets +0..+0x4c du payload), puis appelle `commandStartEnroll` avec ce tampon (les 0x44 premiers o = `enroll_indata_v2_t`). → **le contenu de `enroll_indata_v2_t`, jeton compris, est construit intégralement en espace utilisateur
(biometrickitd / BiometricKit) ; le kext ne fait que le relayer.** C'est pourquoi la réponse à « qui produit le
jeton à +0x10 » se trouve dans le userland (§A), pas dans le kext.

Structure (taille/offsets = VU en kext ; rôles des champs = `source: userland`, §A) :

| offset | taille | rôle | statut |
|---|---|---|---|
| +0x00 | u32 | flags (**bit 0 lu par le kext** → drapeau d'enrôlement) | VU (kext) |
| +0x04 | u32 | `userID` | **VU** (userland, struct identité) |
| +0x08 | u32 | `usingAuthToken` (1 = AuthToken, 0 = CredentialSet) | **VU** (userland, type encoding A.1) |
| +0x0c | u32 | `tokenLength` | **VU** (userland, A.1) |
| +0x10 | 32 o | **jeton** `token[32]` = AuthToken **ou** CredentialSet | **VU** (userland, A.1/A.2) |
| +0x30 | u32 | deviceGroup / type | DÉDUIT (hors structs vues) |
| +0x34 | 16 o | `uuid` | **VU** (userland, struct identité `{userID, uuid[16]}`) |

(Les champs +0x04/+0x34 proviennent du couple `{userID:I, uuid[16C]}` (identité) et +0x08..+0x2f du couple
`{usingAuthToken:I, tokenLength:I, token[32C]}` (authData) lus dans `biometrickitd` ; +0x30 non directement vu.)

---

## b. Préconditions avant `0x03` (VU, `source: kext`)

- **Gating AP de l'enrôlement** (commandStartEnroll, ci-dessus) : device Mesa **présent + non désactivé**,
  `enrollInit` non nul. **Aucune** vérif de keybag/jeton **côté AP** avant l'envoi 0x03 — le SEP est seul juge du jeton.
- **Aucun opcode sbio dédié avant 0x03** dans le flot d'enrôlement (VU `sbio_enroll.md` : les seuls opcodes fil de
  l'enroll sont 0x03, 0x1e, 0x08 ; l'acquisition d'image 0x23/0x06/0x65/0x07 est partagée avec le match). Le `0x27/0x25`
  (`commandStartMatch`, qui porterait un acmContext) n'apparaît sur aucune trace (VU négatif, `j6_enroll_match_protocol.md`).
- **DÉDUIT** : la précondition déterminante n'est pas un opcode fil mais **le jeton embarqué dans les 68 octets**
  (le SEP le valide en interne → trame 0xff si absent/invalide, cf. §c). D'où l'échec du J6a (68 o nuls = pas de jeton).
- **Indice (VU, `source: kext`)** : Mesa gère des **jetons d'autorisation par utilisateur** côté SEP —
  `dropUnlockToken(uint userID)` @0xfffffe0009a4dc74 émet `sepTransact(opcode=0x26, …)` et `dropBiometricTokens(uint)`
  @0xfffffe0009a4dd00 ; `getUnlockToken`/`setUnlockToken` existent aussi. Donc le SEP **mémorise** un « unlock token »
  lié à un userID : le jeton de l'enrôlement (+0x10) s'inscrit dans ce système d'autorisation (il autorise la création
  d'une identité). DÉDUIT : ce jeton est produit par la couche d'authentification de l'AP (ACM / LocalAuthentication),
  pas par Mesa (cf. §A).

---

## d. BONUS — xART op 0x05/0x06 (`AppleSEPXART::_handle_sep_driven_msg`) — confirmé en 27.2.1 (VU, `source: kext`)

Confirmation demandée du format FETCH/SAVE gigalocker. `_handle_sep_driven_msg`
(`__ZN12AppleSEPXART22_handle_sep_driven_msgEPNS_11XARTMessageE`, bundle `com.apple.driver.AppleSEPManager`,
macOS 27.2.1) : dispatch identique à la lecture 13.5 (`kext_sepmanager.md` §8) — mêmes chaînes de log VU :
`"Fetched %s-xART with CRC"` (op 0x00), `"Saving %s-xART with CRC"` (0x01), `"Fetched/Saving %s-xART Locker with CRC"`
(op 0x05 FETCH / 0x06 SAVE gigalocker), `"%s_XART_LOCKER with uuid %s %s"` (0x07 deleted/not found),
`_determineOsUuidGated` (op 0x13). **Op 0x05 lit l'UUID (16 o) en B et écrit le locker en A ; op 0x06 sauve le blob
rendu par le SEP.** → le fait matériel **vérifié n=2 (J7b, `messages.md`)** « A = B[16..] du SAVE, sans UUID » est
cohérent avec ce handler (la note `messages.md` disait « kext op 0x05/0x06 non relu » : **c'est désormais relu en
27.2.1 et cohérent**). Le CRC n'est pas dans le message (dans le blob, revérifié par le SEP).

---

## A. Userland — qui produit le jeton +0x10 (VU, `source: userland`)

**Binaires** : `biometrickitd` (`/usr/libexec/biometrickitd`, extrait du volume système de l'IPSW via `apfs-fuse`
monté RO + `7z`, Mach-O arm64e autonome) ; `BiometricKit.framework` et `BiometricSupport.framework` (lus **dans le
cache dyld** monté RO, `ipsw dyld macho --strings` / `class-dump`). macOS 27.2.1.

**A.1 Le jeton +0x10 = un `AuthData` ou un `CredentialSet` — VU.** Encodage de type ObjC lu dans `biometrickitd`
(`class-dump`) : `{?="usingAuthToken"I"tokenLength"I"token"[32C]}` (= `_extendEnrollmentAuthData`) et identité
`{?="userID"I"uuid"[16C]}` (= `_extendEnrollmentIdentity`). → **confirme octet-près l'hypothèse mission** :
`usingAuthToken` (u32), `tokenLength` (u32), `token[32]`, plus `userID` (u32) + `uuid[16]`. Ces champs composent
`enroll_indata_v2_t` (0x44 o).

**A.2 Deux formes de jeton, choisies par option client — VU (`BiometricKit.framework`, chaînes).** Clés d'option :
`BKOptionEnrollWithAuthToken` et `BKOptionEnrollWithCredentialSet` (enrôlement) ; `BKOptionAuthWithAuthToken` /
`BKOptionAuthWithCredentialSet` (match) ; `BKOptionMatchAuthTokenForExtendEnrollment`,
`BKOptionMatchCredentialSetForExtendEnrollment`, **`BKOptionMatchAuthTokenToBypassPasscodeBiolockout`**. → le jeton
d'enrôlement est **soit un AuthToken** (jeton d'autorisation, `usingAuthToken=1`) **soit un CredentialSet** (matériel
de credential du trousseau/keybag, `usingAuthToken=0`). VU.

**A.3 Qui produit le jeton : le CLIENT, pas biometrickitd — VU (décisif).** `biometrickitd` **ne lie AUCUN** framework
d'authentification ni keystore (liste `LC_LOAD_DYLIB` VU : Foundation/AppKit/IOKit/OpenDirectory + **BiometricKit** +
**BiometricSupport** + swift ; **ni** LocalAuthentication, **ni** AppleCredentialManager, **ni** Security/keystore). Il
se borne à **parser le jeton reçu de son client XPC** : méthode `-[BiometricKitXPCServerMesa parseAuthDict:toAuthData:]`
(VU) remplit la struct `authData` depuis le dictionnaire d'options de la requête ; `initEnrollOperation:biometricType:
userID:options:client:` (VU) prend ce jeton dans `options`. → **le jeton est produit en amont, par le processus
client authentifié** (couche LocalAuthentication/ACM : c'est elle qui tient `ACMKernContext*`, kext §a), **pas** par
biometrickitd. biometrickitd/BiometricKit ne font que **relayer** le blob opaque jusqu'au kext puis au SEP.

**A.4 À partir de quoi.** VU indirect : `BKOptionMatchAuthTokenToBypassPasscodeBiolockout` ⇒ l'**AuthToken dérive d'une
saisie de code** (il « bypass » le biolockout après code). Le **CredentialSet** = matériel de credential du
**keybag/keystore** (entitlements VU de biometrickitd : `com.apple.keystore.sik.access`, `com.apple.keystore.device`).
Dans les deux cas, biometrickitd ne voit **jamais le mot de passe en clair**, seulement le **jeton d'autorisation**
opaque fabriqué par la couche d'auth du client.

**A.5 Comment il arrive au SEP.** client (LA/ACM, authentifié) → dict d'options XPC (`BKOptionEnrollWith…`) →
`parseAuthDict:toAuthData:` → struct `authData` → BiometricKit/BiometricSupport assemblent `bm_cmd_t`/`enroll_indata_v2_t`
→ kext `commandStartEnroll` (relais, §a) → **SEP opcode 0x03**.

**A.6 EP 0x12 (SKS) ?** biometrickitd **ne parle pas** à SKS/keystore lui-même (aucun lien, A.3). Le **CredentialSet**
est néanmoins du **matériel de keybag** : sa production (côté client) et la **vérification du jeton par le SEP** passent
par le keystore/keybag — donc l'EP 0x12 est impliqué **en amont (client)** et **dans le SEP**, pas dans le trajet
biometrickitd→kext. VU (linkage) + DÉDUIT (rôle keystore).

**A.7 Vérifié par le SEP — VU (comportement) + §c.** Le refus `TAG 0xff` sur un 0x03 à jeton nul (J6a) = le SEP valide
le jeton avant d'accepter l'enrôlement. Un 0x03 **accepté** exige un `AuthToken`/`CredentialSet` **non nul et valide
pour le contexte courant**, que seul un client authentifié (code + keybag déverrouillé) peut fournir.

> Non épluché octet-près (hors protocole) : le corps de `parseAuthDict:toAuthData:` (clés exactes du dict) et
> l'assemblage de `enroll_indata_v2_t` dans BiometricSupport ; le `0x06` (match, 0xa7 o) utilise `acmContext`
> (`operation.acmContext…`, `MatchModeACM`, VU) — format/nonce non détaillés ici.

---

## Ce qu'il faudrait pour un `0x03` ACCEPTÉ (synthèse, sans rien lancer)
1. **Un `AuthToken` ou un `CredentialSet` non nul et valide à +0x10** (`usingAuthToken`+`tokenLength` cohérents) — le
   J6a nul → refus GT `0xff`. C'est le vrai bloquant (VU, §A).
2. Ce jeton est **produit par le processus client authentifié** (LocalAuthentication/ACM), **pas** par biometrickitd :
   l'**AuthToken** dérive d'une **saisie de code** ; le **CredentialSet** est du **matériel de keybag/keystore**. Notre
   route native n'a **jamais** ouvert SKS/keybag (EP 0x12). → produire un jeton valide suppose soit d'implémenter cette
   couche (keybag déverrouillé par code + ACM), soit de capturer/rejouer un jeton valide (anti-rejeu probable → risque
   d'échec).
3. Champs `userID`/`uuid` corrects (structs VU) ; +0x30 (deviceGroup) à caler.
4. Préconditions fil : device Mesa présent + init capteur faite (déjà VÉRIFIÉ natif, J8) ; **aucun** opcode sbio
   préalable requis avant 0x03 (VU). Le mur est le **jeton d'autorisation**, pas la séquence.
