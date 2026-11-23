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
- **userland** : cache dyld (`BiometricKit.framework`, `biometrickitd`, LocalAuthentication, …) — voir §A.

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

| offset | taille | rôle (hypothèse de départ, mission) | statut |
|---|---|---|---|
| +0x00 | u32 | flags (**bit 0 lu par le kext** → drapeau d'enrôlement) | VU (bit 0) |
| +0x04 | u32 | userID | à confirmer §A |
| +0x08 | u32 | `usingAuthToken` | à confirmer §A |
| +0x0c | u32 | `tokenLength` | à confirmer §A |
| +0x10 | 32 o | **jeton** (CredentialSet 1-32 o, ou AuthToken 0/16 o) | à confirmer §A |
| +0x30 | u32 | deviceGroup.type | à confirmer §A |
| +0x34 | 16 o | uuid | à confirmer §A |

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

## A. Userland — qui produit le jeton +0x10 (état : extraction en cours)

**Statut d'extraction (honnête).** L'IPSW public a été téléchargé et déchiffré (AEA, clés publiques `fcs-keys.json`).
Le cache dyld (`BiometricKit.framework`, LocalAuthentication, …) et `biometrickitd` vivent dans des DMG **APFS avec
compression decmpfs type 14 (LZBITMAP, propriétaire Apple)** : `7z` (26.06) liste mais **ne décompresse pas** le
type 14 ; le montage APFS natif d'`ipsw` exige `apfs-fuse` (absent, build non réalisé ici). Le lecteur natif
**`ipsw extract --ranged`** (lecture APFS par plages HTTP, décompresse le decmpfs en Go) **fonctionne** mais est
**très lent sur le lien tunnel** (latence par requête b-tree). `biometrickitd` était en cours d'extraction par cette
voie. → **la confirmation VU du userland reste à finaliser** ; ce qui suit est **DÉDUIT** du kext + doc publique +
session PC partielle antérieure, à **confirmer** sur le binaire.

**Ce qui est établi (VU, kext) et oriente la réponse :**
1. Le kext **ne construit ni ne vérifie** le jeton : il relaie 68 octets fournis par l'userspace (§a).
2. Le SEP gère des **unlock tokens par userID** (opcode 0x26 `dropUnlockToken`, §b) → un système d'autorisation.

**Réponse DÉDUITE à « qui produit le jeton, à partir de quoi, comment il arrive, est-il vérifié » :**
- **Qui** : la couche d'authentification de l'AP — `biometrickitd` obtient un **contexte/credential ACM**
  (`AppleCredentialManager`, kext VU : `ACMKernContextCreate` / `…CreateWithExternalForm` /
  `ACMKernContextVerifyPolicyAndCopyRequirementEx`, codec DER `acm_der_*`). Le jeton +0x10 est, selon l'hypothèse de
  la mission, soit un **CredentialSet** (1-32 o), soit un **AuthToken** (0/16 o) — forme externe d'un contexte ACM.
  L'alternative (SKS/AppleSEPKeyStore EP 0x12 directement, ou LocalAuthentication seul) **reste à départager sur le
  binaire** userland. `usingAuthToken` (+0x08) choisirait la forme ; `tokenLength` (+0x0c) donnerait la taille.
- **À partir de quoi** : un **contexte d'authentification** (déverrouillage de session / politique LA), lui-même adossé
  au keybag utilisateur — **pas** le mot de passe en clair (le SEP reçoit un jeton d'autorisation, jamais le secret).
- **Comment il arrive** : userspace (biometrickitd) → `enroll_indata_v2_t`+0x10 → kext (relais, §a) → SEP opcode 0x03.
- **Vérifié par le SEP ?** : **oui, DÉDUIT** — le refus `TAG 0xff` sur un 0x03 à jeton nul (J6a, §c) montre que le SEP
  valide bien ce contenu avant d'accepter l'enrôlement. Un 0x03 **accepté** exige donc un jeton d'autorisation **non
  nul et valide pour le contexte courant** (session déverrouillée), que seul l'AP authentifié peut produire.

> À FINALISER sur le binaire userland (dès extraction) : offsets exacts de `enroll_indata_v2_t` (confirmer
> +0x04 userID, +0x08 usingAuthToken, +0x0c tokenLength, +0x10 token[32], +0x30 deviceGroup, +0x34 uuid) ; l'API
> précise d'où biometrickitd tire le jeton (ACM vs SKS vs LA) ; le format du `0x06` (match, 0xa7 o) et son nonce.

---

## Ce qu'il faudrait pour un `0x03` ACCEPTÉ (synthèse, sans rien lancer)
1. **Un jeton d'autorisation non nul à +0x10** (le J6a nul → refus GT `0xff`). C'est le vrai bloquant.
2. Ce jeton doit être **produit par une authentification réussie de l'AP** (ACM/LocalAuthentication adossé au keybag
   déverrouillé) — notre route native n'a **jamais** ouvert SKS/keybag (EP 0x12). → produire un jeton valide suppose
   soit d'implémenter cette couche (SKS + ACM), soit de capturer/rejouer un contexte valide (anti-rejeu probable).
3. Les autres champs de `enroll_indata_v2_t` (userID, deviceGroup, uuid) correctement remplis (vs 68 o nuls).
4. Préconditions fil : device Mesa présent + init capteur faite (déjà VÉRIFIÉ natif, J8) ; **aucun** opcode sbio
   préalable requis avant 0x03 (VU). Le mur est le **jeton**, pas la séquence.
