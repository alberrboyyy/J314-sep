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
