# Jeton d'enrôlement Touch ID (AuthToken / CredentialSet) — fabrication et vérification (source: kext + userland)

2026-11-23 — agent reverseur (session ALARM, Opus 4.8, capstone). **Cible** : comprendre, octet/format près, comment
est fabriqué le **jeton** que le SEP exige dans `commandStartEnroll` (sbio 0x03, 32 o à +0x10 de `enroll_indata_v2_t`),
et si un hôte Linux peut le produire. **Portée protocole/format uniquement. Aucune clé, aucun secret, aucune donnée
cryptographique extraite. Aucun code Apple copié.** Désassemblage hors-ligne, rien lancé, rien passé en `vérifié`.

**Convention** : **VU** = lu au désassemblage (adresse/symbole/immédiat) ou dans une chaîne ; **DÉDUIT** = interprété
d'après noms/structure ; **INCONNU** = non déterminé. `source: kext` (kernelcache 27.2.1
`macos/kc/26B131__MacBookPro18,4/kernelcache.release.*`, bundle `com.apple.driver.AppleSEPKeyStore`) /
`source: userland` (`biometrickitd` extrait + chaînes ; cache dyld non re-disassemblé cette session, cf. §Limites).

Réf. croisées : `docs/biometrickit_protocol.md` (§a/§A : la struct 0x03 et « biometrickitd ne fait que relayer »),
`docs/sks_protocol.md` §2 (DER, `acmh`) / §5 (chemin ACM), `docs/j6_enroll_match_protocol.md` (0x03, J6a jeton nul → `0xff`).

---

## 0. Résultat central (VU, décisif)

**Le jeton n'est PAS calculé par l'AP : il est FORGÉ PAR LE SEP.** Le keystore du noyau expose une opération IPC
dédiée `authentication_token_create` : l'AP fournit des entrées (handle de keybag + un secret), le **SEP** renvoie le
jeton (un blob opaque). Le même keystore expose `authentication_token_verify` (le SEP sait aussi **vérifier** un jeton).
→ Le jeton porte une garantie tenue par une clé que **seul le SEP détient** : il n'est **pas fabricable côté AP/Linux**.
Un hôte Linux ne peut que **le demander au SEP** après un déverrouillage keybag réussi — pas le forger hors-ligne.

Symboles VU (kernelcache 27.2.1) :
- `AppleKeyStore::authentication_token_create(unsigned long long, unsigned int, int, OSData*, OSData**)` @0xfffffe0009cc709c
- `AppleKeyStore::authentication_token_verify(unsigned long long, unsigned int, int, OSData*, unsigned int*)` @0xfffffe0009cc71f0
- builders `__ipc_authentication_token_create` @0xfffffe0009cfb52c / `__ipc_authentication_token_verify` @0xfffffe0009cdc67c
- codecs OOL `_code_ipc_authentication_token_create` @0xfffffe0009ce2644 / `_code_ipc_authentication_token_verify` @0xfffffe0009ce283c

---

## 1. Format du jeton (Q1)

### 1.1 Côté AP : un blob opaque — VU
La méthode C++ @0xcc709c (VU, désassemblée) :
1. prend l'OSData d'entrée `in` (arg4), lit `getBytesNoCopy`/`getLength` (slots vtable +0x198/+0x160) → (ptr, len) ;
2. appelle `__ipc_authentication_token_create(aks, 0, arg1_u64, arg2_u32, arg3_int, ptr, len, &outPtr, &outLen)` ;
3. au retour, enveloppe `(outPtr,outLen)` en **OSData** (via `OSData::withBytes`, @0xfffffe0009d0231c) et le pose dans
   `*arg5`. → **le jeton = ce blob de sortie `out`** ; l'AP ne lit JAMAIS sa structure interne (il le relaie tel quel).
**Donc le contenu interne du jeton (champs, nonce, horodatage, MAC) est INCONNU côté binaire AP — il est interne au SEP.**

### 1.2 Les 32 octets à +0x10 du 0x03 — VU (userland) + DÉDUIT
`biometrickit_protocol.md` §A.1 (chaîne ObjC VU) : `{?="usingAuthToken"I"tokenLength"I"token"[32C]}`. Le blob `out` de
§1.1 est posé dans ce champ `token` (≤ 32 o, longueur réelle dans `tokenLength`). **Le SEP consommateur (sbio 0x03) le
recoupe avec son état interne** : un 0x03 à jeton nul est refusé (`TAG 0xff`, J6a VU, `biometrickit_protocol.md` §c).

### 1.3 Grammaire du message OOL `authentication_token_create` — VU (codec @0xce2644)
Le codec (générique encode `w0=0` / décode `w0=1`) écrit/lit, dans le tampon OOL, via les primitives VU
`__ipc_header` (0x50 o), `__ipc_msg_process_extended_header`, `__word` (u32 LE), `__lword` (u64 LE),
`__blob` (ptr+longueur). Disposition du corps après l'en-tête IPC (offsets dans la struct contexte, VU) :

| offset ctx | primitive | rôle (hypothèse) | statut |
|---|---|---|---|
| en-tête | `__ipc_header`+ext | en-tête IPC négocié (= même que `get_capabilities`/`set_env`, `sks_protocol.md` §1.6) | VU |
| +0x50 | `__word` | **état** — doit valoir **0** pour continuer (`ldur w8,[x21,#0x50]; cbz`) | VU |
| +0x58 | `__lword` | u64 (sens INCONNU ; plausible sélecteur/version, comme ailleurs = 1) | VU (champ) |
| +0x60 | `__word` | u32 | VU (champ) |
| +0x64 | `__word` | u32 | VU (champ) |
| +0x68 / +0x70 | `__blob` | blob {ptr,len} #1 | VU (champ) |
| +0x78 / +0x80 | `__blob` | blob {ptr,len} #2 (branche d'itération) | VU (champ) |

→ Le **jeton rendu** est l'un de ces blobs (extrait par le builder, posé dans `out`). **Le sens exact de +0x58/+0x60/
+0x64 et la ventilation des deux blobs (jeton vs données annexes) restent INCONNU** (pas de capture OOL 0x12 ; les noms
ne sont pas symbolisés).

### 1.4 Codec `authentication_token_verify` — VU (@0xce283c), confirme le modèle crée/vérifie
Mêmes primitives ; corps = état(+0x50, must=0) + u64(+0x58) + u32(+0x60) + u32(+0x64) + **blob(+0x68/+0x70) = le jeton à
vérifier** + **u32(+0x74) = résultat**. → le SEP reçoit un jeton et rend un verdict. **Ceci prouve que le jeton est une
valeur contrôlée par le SEP** (il la régénère/recompare en interne), pas une structure que l'AP valide.

---

## 2. Production du jeton (Q2)

### 2.1 Qui appelle, avec quoi — VU (dispatch userclient)
`authentication_token_create` (C++) est atteint **uniquement** par le dispatch `external method` de
`AppleKeyStoreUserClient` (fonction @0xfffffe0009cd0844, site d'appel @0xfffffe0009cd26a0 — `callers` VU). Au site :
- **Entitlement exigé (VU)** : la branche vérifie la chaîne **`com.apple.keystore.auth-token`**
  (@0xfffffe000770e2dc, via `copyClientEntitlement`-like @0xfffffe0009ccba00) **avant** de router vers cette op.
  → **seul un process portant `com.apple.keystore.auth-token` peut faire forger un AuthToken** (= coreauthd, DÉDUIT).
Signature VU : `authentication_token_create(this, u64 arg1, u32 arg2, int arg3, OSData* arg4, OSData** arg5)` (le `this`
n'est pas utilisé : l'objet keystore vient d'un singleton global, VU @0xcc70d0). Affectation des args au site de dispatch
(VU, désassemblé) :
- **arg2 (u32) = le handle de keybag du process appelant** : résolu par
  `AppleKeyStoreUserClient::effective_bag_handle_actual(uint,int,int*)` @0xfffffe0009ccfd20 (VU ; appelé avec le
  sélecteur `0x26` et `input[0]`, écrit le handle dans une variable, relue en `w2`). → le jeton est **rattaché à un
  keybag** ; sa création présuppose un keybag chargé pour le process (DÉDUIT : et déverrouillé, le SEP étant seul juge —
  cf. §3).
- **arg4 (OSData) = un SECRET** : construit par `AppleKeyStoreHelper::secretFromInput(u64,u64)` @0xfffffe0009cedd30
  (VU) à partir du blob d'entrée userspace (`input+0x10` ptr, `input+0x18` len), borné (copie ≤ 0x1000 o, VU). → l'AP
  passe au SEP **un credential/secret** (dérivé du code côté userland), pas le jeton tout fait.
- arg1 (u64) = une valeur sauvée plus haut dans le dispatch (`[sp+0xc8]` ; session/contexte — sens précis INCONNU) ;
  arg3 (int) = `input[8]` (sélecteur/flag du client, sens précis INCONNU).

### 2.2 D'où vient le secret : la couche ACM/LocalAuthentication (userland) — VU (linkage) + DÉDUIT
`biometrickitd` ne parle pas au keystore (VU, `biometrickit_protocol.md` §A.3). Le process qui tient l'entitlement
`com.apple.keystore.auth-token` et un contexte d'auth est **coreauthd** (LocalAuthentication / CoreAuthentication). Il :
1. obtient un **credential passcode** (saisie de code) et déverrouille le keybag (EP 0x12, `sks_protocol.md` §4) ;
2. appelle le userclient keystore `authentication_token_create` → le **SEP** forge l'AuthToken ;
3. le remet au client qui le place dans `BKOptionEnrollWithAuthToken` → `biometrickitd` relaie dans `enroll_indata_v2_t`.

### 2.3 Rôle du handle `acmh` (Q2) — VU (vocabulaire) + DÉDUIT
`acmh` (acm_handle, DER code §2 de `sks_protocol.md`) est le **handle d'un contexte ACM** (Access Control Manager). Le
noyau héberge le sous-système **AppleCredentialManager** (symboles VU : `_LibCall_ACMContextCreate`,
`…CreateWithExternalForm`, `…LoadFromImage`, `_Exec_ACMContextCredentialGetProperty`, `ACMRMIOState`) — un pont RMIO
vers coreauthd. Le contexte ACM porte un **ACL** dont la grammaire DER est VU (constantes `___acm_der_key_*`
@0xfffffe00074511c0…) :
- **contraintes** : `policy, kofn, user_passcode, user_passcode_not_set, bio, access_groups, payment_pin, btn, watch,
  capture, secure_state, idv, ap, key_ref, sip` ;
- **paramètres** : `credential_max_age, global_credential_max_age, kofn(_optional), credential_max_usage_count,
  max_operation_count, bio_apps, bio_catacomb_uuid, bio_database_hash, bio_uuids, bio_type, require_passcode,
  btn_max_prearm_age, sec_lvl, bio_continuity_unlock_max_age, up_offwrist(_acc), idv_access` ;
- **ops** : `op_default_acl, op_osgn, op_ocdg, op_oacl`.

DÉDUIT : dans un `perform_operation` keychain, `acmh` dit au SEP « cet appel est couvert par ce contexte ACM », et le
SEP évalue l'ACL (passcode/bio). Pour l'**enrôlement**, le même socle d'auth (keybag déverrouillé + credential) est ce
qui autorise `authentication_token_create`.

---

## 3. Comment le SEP vérifie (Q3)

- **Signé/vérifié par le SEP — VU (structure)** : l'existence conjointe de `authentication_token_create` **et**
  `authentication_token_verify` (deux ops IPC SEP, VU) montre que le jeton est une valeur dont **le SEP tient la clé** :
  il la forge et la revérifie. Un AP/Linux ne peut pas reproduire la valeur sans cette clé → **non forgeable hors SEP**.
  (La nature exacte — MAC symétrique scellé vs signature — est INCONNUE : interne au SEP, hors binaire AP.)
- **Liaison / anti-rejeu — DÉDUIT (depuis le vocabulaire ACL VU)** : les paramètres ACL
  `credential_max_age` / `global_credential_max_age` (fraîcheur, borne temporelle), `credential_max_usage_count` /
  `max_operation_count` (nombre d'usages), et surtout `bio_catacomb_uuid` + `bio_database_hash` + `bio_uuids`
  (liaison à **une base biométrique précise**) indiquent qu'un jeton/credential est **borné dans le temps, en usage, et
  lié à l'état de la base bio**. → un jeton capturé est **vraisemblablement non rejouable** (expire ; lié au catacomb/
  hash de la base enrôlée). Détail octet : INCONNU (pas de capture OOL 0x12 ; ACL évaluée dans le SEP).
- **Côté sbio** : le SEP refuse un 0x03 à jeton nul/invalide (`TAG 0xff`, J6a VU) — il valide avant d'entrer en enroll.

---

## 4. CredentialSet (Q4) — l'autre forme acceptée

- **VU (userland)** : `usingAuthToken=0` sélectionne un **CredentialSet** ; chaînes `forCredentialSet`,
  `!operation.forCredentialSet`, options `BKOptionEnrollWithCredentialSet` / `BKOptionAuthWithCredentialSet` /
  `BKOptionMatchCredentialSetForExtendEnrollment` (VU, `biometrickit_protocol.md` §A.2). Entitlements keybag de
  biometrickitd : `com.apple.keystore.sik.access`, `com.apple.keystore.device`.
- **DÉDUIT** : le CredentialSet est du **matériel de credential du keybag/keystore** (ensemble de credentials ACM d'une
  session authentifiée), alternative à l'AuthToken. Il **n'est pas plus simple à produire** : il dépend du même socle
  (keybag déverrouillé + credential passcode). Il n'allège donc **pas** le mur.
- **INCONNU** : sa construction octet-près (coreauthd/LocalAuthentication, non re-disassemblés cette session) et s'il
  est, lui aussi, scellé par le SEP ou simplement une collection de credentials transmise au SEP pour évaluation.

---

## 5. VERDICT (Q5) — un hôte Linux peut-il produire un 0x03 acceptable ?

**NON en local (forge hors-ligne impossible) ; OUI seulement en le FAISANT FORGER PAR LE SEP, ce qui exige d'abord le
déverrouillage keybag.** Le mur, précis :

1. **Le jeton est forgé et scellé par le SEP** (`authentication_token_create`, VU) avec une clé que seul le SEP détient,
   et vérifié par le SEP (`authentication_token_verify`, VU). → **aucun octet de jeton valide ne peut être calculé sur
   l'AP/Linux.** (C'est le mur dur, différent d'un simple format à remplir.)
2. **La forge exige en entrée** (VU) : (a) l'entitlement `com.apple.keystore.auth-token` sur le chemin userclient ;
   (b) un **handle de keybag** du process (`effective_bag_handle_actual`) — donc un **keybag chargé/déverrouillé** ;
   (c) un **secret/credential** (`secretFromInput`) dérivé d'une **saisie de code** côté ACM/LocalAuthentication.
3. **Anti-rejeu probable** (DÉDUIT, §3) : fraîcheur (`credential_max_age`) + liaison à la base bio
   (`bio_catacomb_uuid`/`bio_database_hash`) → on ne peut pas capturer un jeton macOS et le rejouer indéfiniment sur un
   autre état.

**Ordre logique imposé pour Linux (confirme `sks_protocol.md` §5) :**
`ouvrir EP 0x12 (sks)` → `négocier l'en-tête IPC (get_capabilities)` → `déverrouiller / créer un keybag (verify_secret /
fv_unwrap_vek, le passcode)` → `faire forger un AuthToken par le SEP via authentication_token_create` → **seulement
alors** `sbio 0x03` avec ce jeton. **Le préalable bloquant est le déverrouillage du keybag du lot keystore** — la route
native n'a jamais ouvert 0x12 en écriture. Le jeton n'est donc pas « un format à deviner » : c'est **une sortie du SEP
conditionnée à un unlock keybag réussi**.

**INCERTAIN** (à trancher seulement sur matériel, jamais en lecture seule) : si l'op `authentication_token_create` peut
être émise **brute sur EP 0x12** (son OOL utilise le **même en-tête IPC négocié** que `get_capabilities` — le mur
d'en-tête de `sks_protocol.md` §1.6), ou si elle dépend d'états ACM internes posés uniquement par le chemin
userclient/coreauthd. Les entrées exactes (arg2/arg3, forme du secret) ne sont pas capturées (pas de trace OOL 0x12).

---

## 6. Points ouverts / Limites honnêtes

- **TAG fil (EP 0x12) de create/verify = INCONNU.** Table d'ops IPC VU (base `0xfffffe0008295290`, stride `0x50`,
  `_get_process_table` @0xfffffe0009cde074) ; create (0xce2644) et verify (0xce283c) **ne sont pas** des codecs de code
  top-level de cette table (dispatch via une op générique ou sous-dispatch non résolu). Pas de capture OOL 0x12 non plus.
- **Structure interne du jeton = INCONNU** (opaque côté AP ; interne SEP). Sens de +0x58/+0x60/+0x64 et des deux blobs
  du codec = INCONNU.
- **Userland profond non re-disassemblé cette session** : `coreauthd` / `CoreAuthentication` / `LocalAuthentication`
  sont dans le **cache dyld compressé** (`macos/extract/dsc/**`, type decmpfs) ; `apfs-fuse` et `ipsw` ont été **effacés
  au reboot** (scratchpad volatil) et n'ont pas été reconstruits ici. Le linkage userland est donc repris de
  `biometrickit_protocol.md` §A (VU) + chaînes de `biometrickitd` (VU) ; la fabrication octet-près du secret/ACL côté
  coreauthd reste à faire (remonter apfs-fuse/ipsw).
- **Nonce/session exacts = INCONNU** : l'anti-rejeu est DÉDUIT du vocabulaire ACL, pas lu dans un flux.
- Rien ici n'est `vérifié` (statut matériel) : tout fait binaire est `source: kext`/`source: userland`.
</content>
</invoke>
