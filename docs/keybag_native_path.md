# Chemin natif minimal EP 0x12 : de « getcap + set_env » à « keybag prêt pour authentication_token_create »

2026-11-23 — agent reverseur (session ALARM, Opus 4.8, capstone, hors-ligne). **Cible** : le chemin le plus court,
octets près, qui, après `open EP 0x12 + get_capabilities + set_env` (acquis matériel J9a/J9b/J9c), amène le SEP à
l'état « un keybag EXISTE et est DÉVERROUILLÉ » tel que `authentication_token_create` (jeton d'enrôlement, cf.
`acm_token.md`) fonctionnerait. **Portée protocole/format uniquement. Aucune clé, aucun secret, aucun passcode, aucune
dérivation extraits. Aucun code Apple copié.** Rien lancé, rien passé en `vérifié`.

**Source binaire** : kernelcache `macos/kc/26B131__MacBookPro18,4/kernelcache.release.Mac13,1_2_MacBookPro18,1_2_3_4`
(27.2.1), bundle `com.apple.driver.AppleSEPKeyStore`. **`source: kext` (27.2.1)**.
**Convention** : **VU** = lu au désassemblage (adresse/symbole/immédiat) ; **DÉDUIT** = interprété d'après noms/flot ;
**INCONNU** = non tranché par ce binaire. Réf. croisées : `sks_keybag_unlock.md` (lot A : 0x32/0x48/0x41/0x18 =
FileVault, contournables), `acm_token.md` (jeton forgé par le SEP), `sks_protocol.md` §1.6 (en-tête IPC), journal J9c.

Primitives de codec IPC identifiées cette session (symboles VU, communes à tous les `_code_ipc_*`) :
`__ipc_header` @0xcec768, `__ipc_msg_process_header` @0xcecc70, `__ipc_msg_process_extended_header` @0xcff530,
`__word` (u32 LE) @0xcff1c0, `__lword` (u64 LE) @0xcff38c, `__blob` (ptr+len) @0xcff218, `_gen_ipc_header` @0xcec458.
Submit = `blraa x<obj>, x17` avec `x17=#0x392e` (vmethod d'émission de l'instance endpoint) ; **le `w1` du submit = le
TAG fil EP 0x12** (recoupé trace c12 pour 0x32/0x48/0x41/0x18, cf. `sks_keybag_unlock.md` §0).

---

## 1. `make_system_keybag` (op/TAG **0x0d**) — VU / DÉDUIT / INCONNU

- **TAG fil EP 0x12 = 0x0d** — VU. Builder `__ipc_make_system_keybag_v1` @0xcdbce4 : `mov w1,#0xd ; blraa x19,x17`
  (x17=0x392e) @0xcdbdd8-0xcdbde0. Codec `_code_ipc_make_system_keybag` @0xce0134.
- **Codec = struct C plate, PAS du DER** — VU. Le codec sérialise, après l'en-tête IPC (0x50 o, via
  `__ipc_msg_process_extended_header`), un **mot d'état** `__word` à +0x50 (`ldur w8,[x21,#0x50]`, branche 0/1), puis
  `__lword` +0x58, `__word` +0x60, `__word` +0x64, `__blob` +0x68/+0x70, avec une branche d'itération (+0x58.. bis).
  **Même gabarit générique que `authentication_token_create`** (`acm_token.md` §1.3). Aucun SET/SEQUENCE DER, aucun `rk`,
  aucun `acmh`.
- **Ce que le builder pose dans la struct (0x80 o) avant submit** — VU @0xcdbd98-0xcdbdb4 :
  - +0x50 `__lword` = **constante 1** (chargée de `__const` 0x770fec8 = `01 00 00 00 00 00 00 00`) — VU.
  - +0x58 `__lword` = **handle de keybag** (arg x2 du builder) — VU (cf. appelants).
  - +0x60 `__word` = arg x3 ; +0x64 `__word` = arg x4 (= **type de keybag**, DÉDUIT) — VU champs.
  - +0x68/+0x70 `__blob` = {ptr=arg x5, len=arg x6} = **données de keybag** (peut être vide) — VU.
  - +0x78 `__lword` = arg x7 (flag ; vaut **0x100** ou 0 selon un booléen appelant) — VU.
- **Deux appelants, deux régimes d'entrée** — VU (`callers`) :
  1. **`AppleKeyStore::set_device_keybag` @0xcc7c48** → builder avec **blob NON vide** : le blob = `OSData`
     (`getBytesNoCopy`/`getLength`, vtable +0x198/+0x160) venant de l'**userspace**. → **import d'un keybag fourni**.
  2. **`AppleKeyStore::identity_load` @0xcf79a8** → builder avec **x5=0, x6=0 (blob VIDE)** @0xcf7b44-0xcf7b4c : **aucune
     donnée AP**, uniquement des scalaires (handle, un entier résolu, type). → **le SEP fabrique le keybag d'identité
     d'appareil lui-même** (matériel de clé interne au SEP). C'est le chemin « system keybag ».
- **Le SEP fabrique-t-il un keybag d'appareil SANS secret AP ?** **OUI — DÉDUIT fort** (VU que `identity_load` n'envoie
  aucun blob/secret ; seul le SEP a la clé d'appareil). C'est la piste la plus prometteuse pour Linux.
- **Rend-il un handle réutilisable ?** `set_device_keybag`/`identity_load` **reçoivent** un handle `y` en entrée (arg x1)
  et opèrent dessus ; le handle est attribué par `load_keybag`/`create_keybag` en amont. → le keybag est **désigné par
  un handle** réutilisable par les ops suivantes (dont `authentication_token_create`, qui prend un bag handle). DÉDUIT.
- **Entrées exactes (seed ? uuid ? device key ?)** : `identity_load` vérifie une `OSData` de **16 o** (`cmp w0,#0x10`
  @0xcf7a28, DÉDUIT = **uuid**) et un entier de type dans la plage négative (`cmn w21,#0xa ; b.gt` → type ≥ -10). Aucun
  seed ni device key côté AP (interne SEP). → entrées = **uuid (16 o) + type**, pas de secret. VU champs, DÉDUIT sens.
- **Reproductible depuis Linux ?** `make_system_keybag` **via `identity_load`** : gabarit d'octets = en-tête IPC négocié
  (même mur que getcap, `sks_protocol.md` §1.6) + scalaires + blob vide. **Pas de blob secret à inventer** → **INCERTAIN
  mais plausible** : seul manque la valeur exacte des scalaires (uuid d'appareil, type) et le fait que l'op soit
  acceptée brute sur 0x12 (comme `null_d_key` l'a été en J9c). `make_system_keybag` **via `set_device_keybag`** exige un
  **blob de keybag valide** (format INCONNU) → mur.

## 2. Où vit le keybag après création — DÉDUIT / INCONNU

- **Mécanisme observable in-kext = NOTIFICATION userland, pas un SAVE xART automatique** — VU (symboles) :
  `AppleKeyStore::tickle_system_keybag_update_port[_gated]` @0xcc6624/… + `set_systembag_notify_port` : l'userland
  **enregistre un port** ; quand le system keybag change, le kext « tickle » ce port → l'userland **relit et persiste le
  blob keybag sur DISQUE**. → DÉDUIT : la **persistance du system keybag est pilotée par l'userland (sur le volume de
  données)**, pas scellée en xART par ce kext.
- **Scellement SEP / xART (EP 0x13 SAVE)** : **INCONNU depuis ce bundle**. `AppleSEPKeyStore` n'émet **aucun** SAVE 0x13
  visible sur le chemin create/`make_system`. Le stash/escrow existe mais dans une **autre classe** : `AppleFDEKeyStore`
  (`commitStash` @0x94a2d90, `setStashKey`/`getStashKey`, `aks_stash_type_t`) — c'est le stash **FileVault**, pas le
  system keybag d'identité. Le vocabulaire ACL porte `escrow_passcode_period`/`escrow_token_period` (constantes VU) mais
  l'évaluation est côté SEP.
- **Survit-il à un reboot ?** **DÉDUIT** : le matériel de clé du system keybag étant **interne au SEP** (identité
  d'appareil), il survit côté SEP ; le **blob** correspondant doit être **re-fourni** à chaque boot par l'hôte (via
  `load_keybag`/`set_device_keybag`) — c'est justement le sens du notify-port de persistance. → pour Linux : il faudrait
  **stocker le blob et le recharger chaque boot** (keybag re-créé/rechargé à chaque démarrage, pas « posé une fois »).
  Le fait que le SEP re-scelle (xART) ou non après `make_system_keybag` reste **INCONNU** (hors bundle, côté SEPManager).

## 3. Déverrouillage par passcode d'un keybag d'APPAREIL (≠ FileVault) — VU / DÉDUIT / INCONNU

- **Op = `device_state_transition` (TAG 0x18)**, enveloppée par `AppleKeyStore::unlock_the_device` @0xcc3bc8 — VU.
  - `unlock_the_device(this, y /*handle*/, int, OSData* /*secret*/, u64)` : lit `getBytesNoCopy`/`getLength` de l'OSData
    secret (x23=ptr, x6=len) puis appelle `device_state_transition(this, y, int, 0, u64, ptr, len)` @0xcc3c78. VU.
  - `device_state_transition` @0xcc3b44 → builder `__ipc_device_state_transition` @0xcfb078 → `mov w1,#0x18 ; blraa`
    @0xcfb108-0xcfb110. **Submit TAG = 0x18** — VU.
- **Le passcode entre comme un BLOB OOL positionnel {ptr,len}** — VU. Ce n'est pas un champ texte séparé. Le builder
  0x18 est enrobé de wrappers PAC (helpers 0xcebxxx) → les **offsets exacts du corps 0x18 restent INCONNU** (jamais
  capturé non plus), mais le chemin ptr/len du secret est VU de bout en bout.
- **Clair ou dérivé côté AP ?** — **`source: kext` : AppleSEPKeyStore NE DÉRIVE PAS** (aucun PBKDF2/itération dans
  `unlock_the_device` ; il relaie les **octets bruts de l'OSData**). Toute dérivation éventuelle est **userland
  (coreauthd/ACM) ou interne SEP** — hors de ce bundle. Sel/itérations : **non présents ici, donc non extractibles ici**
  (et non extraits par principe). DÉDUIT : la vérification/dérivation finale est dans le SEP.
- **Ce que rend le SEP** — VU : le builder écrit **deux mots d'état u64** en sortie ([sp+0x88]/[sp+0x90]) recopiés vers
  les pointeurs de sortie, puis `handle_device_state_return` @0xcc37d0. Ensuite `unlock_the_device` relit un **mot d'état
  de verrouillage caché dans l'objet kext à [this+0x81f4]** et teste `w8 & ~0x4 == 0` → **déverrouillé** (sinon erreur
  `0xe00002d8`). → l'**état déverrouillé est LISIBLE côté AP** (mot caché, alimenté par les notifs SEP, cf.
  `notify_kern_lock_state` @0xcc33d8). C'est le `sls`/`ss` de `sks_protocol.md` §2. VU.
- **Reproductible depuis Linux avec le passcode d'Albert fourni à l'exécution ?** **INCERTAIN** : le gabarit (OSData =
  octets du passcode → blob OOL de 0x18) est connu en **structure** mais pas en **offsets de corps** (INCONNU, jamais
  capturé) ; et il reste à savoir si le SEP accepte 0x18 brut sur un keybag d'appareil Linux. Le passcode lui-même, s'il
  est relayé en clair par le kext, serait fourni **à l'exécution** par Albert (jamais stocké/extrait).

## 3b. Un keybag d'appareil NEUF doit-il être « déverrouillé » ? — DÉDUIT / INCONNU

- **DÉDUIT** : un keybag créé par `make_system_keybag`/identité est fabriqué par le SEP **dans un état défini par le SEP**.
  Le passcode sert principalement à **SCELLER une classe de protection** (dériver la clé de classe liée au passcode),
  pas forcément à « déverrouiller » un bag neuf. Mais `authentication_token_create` exige (VU, `acm_token.md` §2.1) un
  **secret/credential** (`secretFromInput`) + un **bag handle** (`effective_bag_handle_actual`) — donc **un passcode est
  requis au moment de la forge du jeton**, que ce soit pour déverrouiller ou pour prouver la possession du code.
- **INCONNU (décisif, à trancher matériel)** : si `authentication_token_create` accepte un bag **neuf jamais
  déverrouillé** (passcode fourni seulement à la forge) ou exige un **`device_state_transition` 0x18 préalable**. Les
  deux scénarios passent par le **même passcode** ; la différence est le **nombre d'ops** (voir §5).

## 4. Lien avec le gating bio — observable ? — VU / DÉDUIT / INCONNU

- **Signal LISIBLE côté AP** — VU : le kext **cache un mot d'état de verrouillage d'appareil** ([this+0x81f4], relu
  après 0x18) et reçoit des notifs `notify_kern_lock_state`/`notify_change_device_state`. → l'AP **voit** si le keybag
  d'appareil est verrouillé/déverrouillé (`sls`). C'est le seul verdict SEP clairement observable sur ce chemin.
- **MAIS le lien keybag→autorisation bio n'est PAS lu dans ce kext** — DÉDUIT. Le vocabulaire ACL (VU,
  `___acm_der_key_acl_param_bio_*` : `bio`, `bio_uuids`, `bio_catacomb_uuid`, `bio_database_hash`, `require_passcode`,
  `sec_lvl`…) montre que la politique bio est **encodée dans un ACL évalué par le SEP**, pas renvoyée au noyau comme un
  « oui/non enrôlement autorisé ». → **la décision d'autoriser l'enrôlement/le jeton est une politique 100 % interne au
  SEP**, non observable ici au-delà de l'état `sls`. **Seul le matériel tranchera** si un keybag d'appareil déverrouillé
  (côté Linux) suffit à ungate sbio/forge le jeton. INCONNU.

## 5. VERDICT — suite d'ops EP 0x12 la plus courte, et faisabilité Linux

**Chaîne candidate minimale (après `open 0x12` + `get_capabilities` 0x4d + `set_env` 0x2a, déjà acquis J9a/J9b) :**

| # | op (symbole) | TAG fil | statut octets | entrées | source |
|---|---|---|---|---|---|
| A | `load_keybag` ou `create_keybag` (obtenir un handle) | 0x01 pour `create_keybag` (VU `mov w1,#1`) | **gabarit INCONNU** (blob keybag à fournir) | blob keybag OU rien | kext |
| B | `make_system_keybag` via identité | **0x0d** (VU) | **struct plate VU**, scalaires ; blob VIDE possible | uuid 16 o + type (valeurs INCONNU) | kext |
| C | `device_state_transition` (unlock) | **0x18** (VU) | **offsets corps INCONNU** | handle + **passcode en blob OOL** | kext |
| D | `authentication_token_create` | TAG **INCONNU** (`acm_token.md` §6) | gabarit codec VU, TAG non résolu | bag handle + secret | kext |

- **Ce qui est byte-connu** : les **TAG** 0x0d (make_system_keybag), 0x18 (device_state_transition/unlock), 0x01
  (create_keybag) — VU ; le **gabarit struct plate** de 0x0d (header IPC + const 1 + handle + 2×u32 + blob + flag) — VU ;
  le fait que le passcode voyage en **blob OOL positionnel** dans 0x18 — VU ; l'en-tête IPC négocié (§1.6) — déjà
  reproduit en Rust (J9c).
- **1er octet/op INCONNU qui bloque** :
  1. **Les scalaires de `make_system_keybag`** (uuid d'appareil 16 o, valeur de type, flag) — valeurs INCONNU (jamais
     capturées ; l'uuid d'appareil est un identifiant, pas un secret, mais sa valeur reste à obtenir).
  2. **Les offsets du corps de `device_state_transition` 0x18** — INCONNU (builder enrobé PAC, jamais capturé OOL).
  3. **Le TAG fil de `authentication_token_create`** — INCONNU (non résolu dans la table d'ops top-level, `acm_token.md`).
- **Le passcode d'Albert est-il nécessaire, et quand ?** **OUI, à l'étape C (unlock 0x18) et/ou D (forge du jeton)** :
  `authentication_token_create` exige un secret/credential (VU). Il est **fourni à l'exécution** (jamais stocké/extrait).
  La création du keybag (B) et l'obtention d'un handle (A) **ne demandent pas** le passcode (DÉDUIT).
- **Réaliste depuis Linux natif ?** **INCERTAIN, mais sans mur cryptographique dur sur la voie identité** (contrairement
  à FileVault 0x32/0x41, qui dépend de blobs de volume macOS absents — `sks_keybag_unlock.md` §5). Ici, aucun secret que
  seul macOS possède n'est requis **pour fabriquer** le keybag d'appareil (le SEP a la clé). Les murs restants sont
  **des valeurs/offsets à obtenir** (uuid, type, corps 0x18, TAG du token) et **une politique SEP non observable**
  (le SEP acceptera-t-il la forge sur un keybag d'appareil recréé par Linux ?). **À trancher sur matériel** (classe
  neuve → go d'Albert), pas au désassemblage.

### Points ouverts (honnêtes)
- Valeurs des scalaires `make_system_keybag` (uuid d'appareil, type, flag) : INCONNU (jamais capturé).
- Offsets exacts du corps `device_state_transition` 0x18 : INCONNU (PAC-wrappé ; pas de capture OOL).
- TAG fil EP 0x12 de `authentication_token_create`/`_verify` : INCONNU (`acm_token.md` §6).
- `make_system_keybag`/identité déclenche-t-il un SAVE xART et survit-il au reboot ? INCONNU (hors bundle ; mécanisme
  observé = notify-port de persistance DISQUE côté userland).
- Un keybag d'appareil NEUF peut-il forger le jeton avec le passcode fourni seulement à la forge (sans 0x18 préalable) ? INCONNU.
- Le SEP ungate-t-il sbio sur un keybag d'appareil recréé par Linux, ou exige-t-il l'identité d'appareil d'origine ? INCONNU (politique interne SEP).

---

## J10 : `make_system_keybag` byte-exact (voie identité) — 2026-11-23, reverseur (Opus 4.8, capstone, hors-ligne)

**Source binaire** : kernelcache `macos/kc/26B131__MacBookPro18,4/kernelcache.release.*` (27.2.1), bundle
`com.apple.driver.AppleSEPKeyStore`. **`source: kext` (27.2.1)**. VU = lu au désassemblage ; DÉDUIT = interprété ;
INCONNU = non tranché par ce binaire. Rien lancé, rien `vérifié`, aucun octet de clé/secret extrait.

### J10.0 Correction de la §1 : la voie identité fait DEUX ops fil, pas une — VU

`AppleKeyStore::identity_load` (@0xfffffe0009cf79a4, sig `identity_load(y, OSData* uuid, int type)`) enchaîne **deux
transactions fil EP 0x12** (VU, désassemblage octet) :

1. **`load_keybag` (TAG fil 0x03)** via `identity_open` (@0xcf7160) → `AppleKeyStore::load_keybag` (@0xcc6c3c) →
   builder `__ipc_load_keybag` (@0xcdb934, submit `mov w1,#3`). **C'est l'op qui REND un handle.** Elle **importe le
   blob de 16 o** (l'OSData `uuid`) comme données de keybag (`load_keybag(y, uuid_ptr, 16, &handle)` ; `w3=#0x10`
   VU @0xcf7180).
2. **`make_system_keybag` (TAG fil 0x0d)** via builder `__ipc_make_system_keybag_v1` (@0xcdbce4, submit `mov w1,#0xd`).
   **Elle ne rend QUE un statut**, pas de handle (VU : le builder fait `mov x19,x0` = statut, puis efface la struct
   via le thunk bzero @0xd027cc, et `ret` x19 ; aucun champ de réponse relu).

→ **Rectifie la §1** : la voie identité ne « fabrique pas un keybag ex nihilo ». Le keybag est **désigné/importé par
un blob de 16 o fourni via `load_keybag` 0x03** ; `make_system_keybag` 0x0d ne fait ensuite que **marquer** ce keybag
comme « system ». Le blob de `make_system_keybag` est bien **vide** sur cette voie (VU x5=x6=0), mais les 16 o ont
déjà transité par `load_keybag`. (Corrige aussi `sks_keybag_unlock.md` §3.2 : la 1re op identité est `load_keybag`
0x03, pas `create_keybag` 0x01.)

### J10.1 D'où viennent les 3 scalaires — VU : du USERLAND, pas du kext

`identity_load` n'a **qu'un seul appelant** (VU `callers`) : le userclient **`kAppleKeyStoreKeyBagCreateWithData`**
(@0xcd0844, entitlement `com.apple.keystore.keybag.create`, cf. `sks_keybag_unlock.md` §3.1). Au site d'appel
(@0xcd411c) les trois entrées sont lues du **dictionnaire de requête userland** (VU) :

- **`uuid` (OSData 16 o)** = `x2`, objet extrait du dict (helpers `0xcbe490/0xcbe6b4`). Validé **= 16 o exactement**
  (`cmp w0,#0x10 ; b.ne` @0xcf7a28 dans `identity_load`, et @0xcf7264 dans le chemin large). **Valeur INCONNU** (choisie
  par le démon userland, pas lue d'un ADT/global/constante par le kext).
- **`handle y` (u64)** = `ldr x1,[sp,#0xc8]` @0xcd4114 → un **handle de keybag parent/session** choisi par l'appelant.
  **Valeur INCONNU.**
- **`type` (int)** = `ldr w3,[sp,#0xf0]` @0xcd4110. Contrainte VU : `identity_load` rejette si `type > -10`
  (`cmn w21,#0xa ; b.gt`→erreur @0xcf7a30) → **type doit être ≤ -10**. **Valeur exacte INCONNU** (choisie par
  l'appelant dans la plage autorisée).

→ **Aucun de ces trois champs n'est dérivable du binaire.** Ce ne sont pas des secrets (un uuid/identifiant, un
handle, un petit entier), mais leurs **valeurs** sont posées par la politique userland (coreauthd/keystored), que ce
kernelcache ne contient pas. L'ADT capturé (`traces/20261108-162919_adt/adt.txt`) a bien un `apfs-preboot-uuid`
(16 o : `EFF3C698-A740-4F41-AB86-99C85C0EB880`) et un `unique-chip-id`/ECID (8 o) — **candidats PLAUSIBLES** pour le
blob de 16 o, mais **aucune preuve VU** que `load_keybag` attende précisément celui-là (le kext ne le lit pas) → **INCONNU**.

### J10.2 Gabarit d'octets COMPLET de `make_system_keybag` (TAG 0x0d) — VU struct / VU codec

Builder `__ipc_make_system_keybag_v1` @0xcdbce4 (VU) : en-tête IPC via `_gen_ipc_header` (@0xcec458), puis struct :
`+0x50` ← `ldr d0,[0x770fec8]` = **u64 1** (VU, const lue : `01 00 00 00 00 00 00 00`) ; `+0x58`←arg2 ; `w+0x60`←arg3 ;
`w+0x64`←arg4 ; blob `+0x68/+0x70`←{arg5,arg6} ; `+0x78`←arg7. Submit `x0=arg1, w1=#0xd, blraa [global+0x150]`.
Codec `_code_ipc_make_system_keybag` @0xce0134 (VU) : lit `+0x50` en **u32** (= 1), prend la **branche state==1**
(@0xce028c) et sérialise **dans cet ordre** : `__lword +0x58`, `__word +0x60`, `__word +0x64`, `__blob +0x68/+0x70`,
`__lword +0x78`. (La branche state==0 omettrait le `+0x78` ; ici state=1 car le builder force la const 1.)

Valeurs posées par `identity_load` (@0xcf7b30-0xcf7b50, VU) : arg2=`y` (handle), arg3=handle rendu par `load_keybag`,
arg4=`type`, arg5=arg6=**0** (blob vide), arg7=**0** (flag).

| off. OOL | taille | primitive | champ | valeur (voie identité) | statut |
|---|---|---|---|---|---|
| 0x00 | 0x54 | `__ipc_header`+en-tête | en-tête IPC négocié (§1.6/§1.7) | len=0x50 + 0x50 o (condensé, version, horodatage µs, flags=0, bloc proc) | **VU** gabarit ; **contextuel** (à construire, pas secret) |
| 0x54 | 4 | `__word` | état | **1** (const @0x770fec8) | **VU** |
| 0x58 | 8 | `__lword` | **handle `y`** (keybag parent) | = `identity_load` arg1 = userland `sp[0xc8]` | **VU** champ ; **valeur INCONNU** (userland) |
| 0x60 | 4 | `__word` | **handle du keybag chargé** | = sortie de `load_keybag` 0x03 (**lue à l'exécution, PAS à inventer**) | **VU** champ ; valeur **dynamique** |
| 0x64 | 4 | `__word` | **type** | = `identity_load` arg3 ; contrainte VU **≤ -10** | **VU** champ+contrainte ; **valeur INCONNU** (userland) |
| 0x68 | 4 | `__blob` len | longueur blob | **0** (vide sur voie identité) | **VU** |
| (0x6c) | 0 | `__blob` data | données blob | — (vide) | **VU** |
| 0x6c | 8 | `__lword` | **flag** | **0** (identity_load passe x7=0) | **VU** |

Longueur fil requête ≈ **0x74** (0x54 en-tête + 0x20 corps) — **DÉDUIT** de l'ordre du codec (OOL 0x12 jamais capturé,
donc non confirmé trace). **Byte-connu OUI pour le GABARIT** (offsets, types, ordre, const 1, blob vide, flag 0 : tout
VU). **Byte-connu NON pour le MESSAGE complet** : il reste **2 valeurs à obtenir hors binaire** — `handle y` (+0x58) et
`type` (+0x64) — plus, en amont, le **blob 16 o** de `load_keybag`. Le champ +0x60 n'est PAS à inventer (il vient de la
réponse `load_keybag`).

### J10.3 Gabarit de `load_keybag` (TAG 0x03) — VU, l'op qui REND le handle

Builder `__ipc_load_keybag` @0xcdb934 (VU) ; codec `_code_ipc_load_keybag` @0xcde92c (VU). Requête (branche
« encode », VU) :

| off. OOL | taille | primitive | champ | valeur (voie identité) | statut |
|---|---|---|---|---|---|
| 0x00 | 0x54 | en-tête IPC | négocié (§1.6/§1.7) | — | **VU** gabarit |
| 0x54 | 4 | `__word` | état | **0** (builder : `stp xzr,x24` @0xcdb9dc) | **VU** |
| 0x58 | 8 | `__lword` | **handle `y`** | = userland `sp[0xc8]` | **VU** champ ; valeur **INCONNU** |
| 0x60 | 4 | `__blob` len | longueur blob | **16** (`w3=#0x10`) | **VU** |
| 0x64 | 16 | `__blob` data | **le blob de 16 o** (uuid) | = OSData userland | **VU** champ ; **valeur INCONNU** (userland ; candidats ADT §J10.1 non prouvés) |

**Réponse** : codec branche « decode » → `__word` à `+0x6c` = **le handle attribué par le SEP** (VU : le builder
`load_keybag` recopie `[sp+0x6c]` vers `*outHandle` après un retour OK @0xcdba28). → **C'est le handle observable
côté AP pour juger « RÉPONDU / handle obtenu ».**

### J10.4 Réponses attendues — VU côté AP / DÉDUIT côté fil

- **`load_keybag` 0x03** : mot mailbox réponse `< EP=0x12 TAG=0x83 TYPE=seq PARAM=s DATA=(len<<16|flag)` (TAG = requête
  |0x80, convention §1.6.4). PARAM=0 = OK. **Charge OOL B** = en-tête + état(u32, doit être 0) + **handle u32 à +0x6c**.
  Côté AP, `load_keybag` renvoie ce handle (VU). **C'est le signal « handle obtenu ».** (Longueur exacte INCONNU, OOL
  jamais capturé.)
- **`make_system_keybag` 0x0d** : réponse `< TAG=0x8d TYPE=seq PARAM=s …`. Côté AP **seul le statut w0 est lu** (VU :
  builder ne relit aucun champ) → PARAM=0 = « marqué system OK », PARAM≠0 = refus (ex. 0xff). **Aucun handle** rendu
  par 0x0d (le handle vient de 0x03). Longueur réponse INCONNU (jamais capturé).

### J10.5 Ordre et prérequis — VU / DÉDUIT

- **Séquence minimale réelle (VU)** : `load_keybag` 0x03 (importe le blob 16 o → rend un handle) **PUIS**
  `make_system_keybag` 0x0d (marque system, statut seul). `create_keybag` 0x01 (@0xcf9a34, submit `mov w1,#1`, VU) est
  un **chemin DISTINCT** (import d'un keybag complet + 9 args, autre userclient) : **PAS requis** sur la voie identité.
- **`make_system_keybag` juste après `set_env` ?** **NON** tel quel — il exige d'abord le **handle rendu par
  `load_keybag`** (son champ +0x60), lequel exige le blob 16 o. Donc l'ordre est **`set_env` → `load_keybag` 0x03 →
  `make_system_keybag` 0x0d** (contrairement à `null_d_key` J9c qui, lui, pouvait suivre `set_env` directement).
- **Passcode ?** **AUCUN** sur toute cette voie (load_keybag/make_system_keybag ne prennent pas d'OSData secret, VU).
  Conforme à l'objectif « sans mot de passe ». Le passcode n'entre qu'à l'unlock 0x18 / forge du jeton (hors J10).

### J10.6 Verdict J10 — byte-connu ?

- **GABARITS** `load_keybag` 0x03 et `make_system_keybag` 0x0d : **byte-connus** (offsets, primitives, ordre, const,
  blob vide, flag — tous VU).
- **MESSAGE complet : NON byte-connu.** Trois valeurs **à obtenir hors de ce binaire** (toutes userland, non secrètes
  mais non déductibles ici) :
  1. **le blob de 16 o** de `load_keybag` (uuid d'identité) — INCONNU (candidats ADT non prouvés) ;
  2. **`handle y`** (+0x58 des deux ops) — INCONNU ;
  3. **`type`** (+0x64 de 0x0d), seule contrainte VU = **≤ -10** — valeur exacte INCONNU.
- **Risque sémantique** : `load_keybag` = « charger » ; un uuid **arbitraire** risque un refus SEP « keybag not found »
  si le SEP attend une identité **déjà enregistrée**. Que le SEP crée à la volée depuis un uuid neuf, ou exige une
  identité pré-existante, est **INCONNU** (politique SEP, non lisible ici). → À trancher **matériel** (classe neuve →
  go d'Albert) : un `load_keybag` 0x03 avec un uuid candidat et lecture du handle rendu est l'expérience la moins chère,
  mais **au moins 3 valeurs restent à fixer** avant tout envoi.
