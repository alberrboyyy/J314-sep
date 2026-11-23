# Déverrouillage keybag (0x18) & forge du jeton (`authentication_token_create`) — disposition octet

2026-11-23 — agent reverseur (session **PC**, Opus 4.8, capstone, hors-ligne). **Cible** : lever les deux `INCONNU`
du chemin keybag natif (`keybag_native_path.md` §C/§D) laissés par la session Mac —
(1) la **disposition octet du corps OOL de `device_state_transition` (TAG 0x18)**, déverrouillage d'un keybag
d'appareil par passcode (enrobé par `unlock_the_device`), et (2) le **TAG fil EP 0x12 + la disposition OOL** de
`authentication_token_create`. **Portée protocole/format uniquement. Aucune clé, aucun secret, aucun passcode, aucune
dérivation extraits. Aucun code Apple copié.** Désassemblage seul, rien lancé, rien passé en `vérifié`.

**Source binaire** : kernelcache 27.2.1 `macos/kc/26B131__…/kernelcache.release.Mac13,1_2_MacBookPro18,1_2_3_4`
(sha256 `4bf084db6847069542a2a5500d0281676eab753d5170dc1d9c8812700a4bf10f`, **identique au Mac** — recoupé ALARM),
bundle `com.apple.driver.AppleSEPKeyStore`. **`source: kext` (27.2.1).** Adresses **courtes** = VA − `0xfffffe0009000000`
(VA pleine = `0xfffffe0009______`). **Convention** : **VU** = lu au désassemblage (adresse/symbole/immédiat) ;
**DÉDUIT** = interprété d'après noms/flot/signature ; **INCONNU** = non tranché par ce binaire.

Réf. croisées : `keybag_native_path.md` §3 (marquait ces offsets « INCONNU, builder PAC-wrappé »), `acm_token.md`
§1.3/§6 (codec partiel ; TAG « INCONNU »), `sks_protocol.md` §1.3 (table TAG) / §1.6 (en-tête IPC) / §2 (`sls`/`ss`).

## 0. Résumé (décisif, ≤ 15 lignes)

- Les deux corps OOL sont désormais **byte-connus** (offsets + types + rôle du handle et du blob), via les **codecs**
  `_code_ipc_*` (que §3 de `keybag_native_path.md` n'avait pas lus — il regardait le builder PAC-wrappé).
- **`device_state_transition` : TAG fil = 0x18** (VU, submit `mov w1,#0x18`, recoupé trace c12 cf. `keybag_native_path` §0).
  Corps requête (après en-tête IPC 0x50) : `+0x50` état=0, `+0x58` **handle keybag** (u64), `+0x60` code d'état cible
  (u32), `+0x64` réservé=0 (u32), `+0x68` u64 (sens INCONNU), `+0x70/+0x78` **blob {ptr,len} = passcode brut**.
  Réponse : `+0x80`/`+0x88` = deux mots d'état (`sls`/`ss`).
- **`authentication_token_create` : TAG fil = 0x1c** (VU, submit `mov w1,#0x1c` @0xcfb594 — **non trouvé par la session
  Mac car elle regardait la table de réception, pas le builder d'émission**). Corps requête : `+0x50` état=0, `+0x58`
  u64 session/ctx (INCONNU sens), `+0x60` **handle keybag** (u32), `+0x64` sélecteur int (INCONNU sens), `+0x68/+0x70`
  **blob {ptr,len} = secret/credential** (entrée). Réponse : `+0x78/+0x80` **blob = jeton** (opaque, forgé par le SEP).
- **Gabarit d'octets** : **OUI** pour les deux (offsets/types connus) ; le passcode/secret voyage en **blob OOL
  positionnel brut** (AppleSEPKeyStore ne dérive pas). **NON** = seulement les **valeurs** de scalaires (code d'état
  `+0x60` de 0x18, u64 `+0x58`/`+0x68`, sélecteur `+0x64` de 0x1c) et l'acceptation brute sur EP 0x12 → **matériel**.
- Pas de collision 0x1c : le `0x1c` de `sks_protocol.md` §2.1 (ligne « oke ») est un **énum d'op interne** du champ `o`
  de `perform_operation`, **autre namespace** que le TAG fil de message.

---

## 1. Cible 1 — `device_state_transition` (TAG fil **0x18**), déverrouillage par passcode

### 1.1 Chaîne d'appel (VU)
`unlock_the_device` @0xcc3bc8 → `device_state_transition` (C++) @0xcc3b44 → builder
`__ipc_device_state_transition` @0xcfb078 → **submit** `mov w1,#0x18 ; mov x17,#0x392e ; blraa x19,x17` @0xcfb108 →
codec OOL `_code_ipc_device_state_transition` @0xce1da0.
Primitives de codec (communes, VU) : en-tête `__ipc_header` @0xcec768 + `__ipc_msg_process_extended_header` @0xcff530
(= en-tête IPC négocié 0x50 o, `sks_protocol.md` §1.6) ; `__word` (u32 LE) @0xcff1c0 ; `__lword` (u64 LE) @0xcff38c ;
`__blob` (ptr+len) @0xcff218.

### 1.2 Flot des arguments — VU
- `unlock_the_device(this, handle, int code, OSData* secret, u64)` @0xcc3bc8 : lit `getBytesNoCopy` (vtable +0x198) →
  **ptr** et `getLength` (+0x160) → **len** du `secret`, puis
  `device_state_transition(this, handle, code, w3=0, u64, ptr, len)` @0xcc3c60-0xcc3c78 — VU.
- `device_state_transition` C++ @0xcc3b44 charge l'objet keystore singleton (`[[0xcbb8cf0]+0x150]`), pose **deux
  pointeurs de sortie** sur la pile ([sp]/[sp+8] → slots [sp+0x10]/[sp+0x18]) et appelle le builder avec
  `(keystore, x1=0, x2=handle, x3=code, x4=0, x5=u64, x6=ptr, x7=len)` — VU.
- Au retour (w0==0), relit `sls` caché à `[this+0x81f4]` et teste `w8 & ~0x4 == 0` → **déverrouillé** (sinon
  `0xe00002d8`) — VU (inchangé vs `keybag_native_path.md` §3).

### 1.3 Corps OOL — disposition octet (VU, codec @0xce1da0 ; valeurs via builder @0xcfb078)
Le codec sérialise séquentiellement ; l'offset struct = l'offset fil (l'en-tête occupe 0x00..0x50). Le builder écrit
chaque champ à `ctx = sp+8` (d'où `[sp+0x58]↔+0x50`, …). **Branche requête** = champs `+0x58..+0x78` ;
**branche réponse** = `+0x80/+0x88` (sélection `cmp w22,w23` = direction encode/décode).

| offset fil | primitive | contenu | statut |
|---|---|---|---|
| 0x00–0x4f | `__ipc_header`+ext | en-tête IPC négocié (= `get_capabilities`/`set_env`, `sks_protocol.md` §1.6) | VU |
| **+0x50** | `__word` u32 | **état** — doit valoir **0** pour continuer (`ldur w8,[x21,#0x50]; cbz`) ; builder pose `xzr` | VU |
| **+0x58** | `__lword` u64 | **handle de keybag** (arg `x2`) | VU champ / DÉDUIT fort rôle |
| **+0x60** | `__word` u32 | **code d'état/transition cible** (arg `code` d'`unlock_the_device`) — p.ex. −501 (`sks_protocol.md` §1.3) | VU champ / DÉDUIT rôle ; **valeur INCONNU** |
| **+0x64** | `__word` u32 | réservé/flags = **0** (const `w3=0` posée par le wrapper C++) | VU |
| **+0x68** | `__lword` u64 | u64 (arg `x5` d'`unlock_the_device`) | VU champ / **sens INCONNU** |
| **+0x70 / +0x78** | `__blob` {ptr,len} | **passcode/secret = octets bruts de l'`OSData`** (relayés tels quels, pas de PBKDF2 ici) | VU |
| **+0x80 / +0x88** | `__lword` ×2 (réponse) | **deux mots d'état** renvoyés → recopiés vers les ptr de sortie = `sls`/`ss` | VU |

**Gabarit d'octets : OUI** (offsets + types + rôle handle/blob connus). Le point « offsets INCONNU, jamais capturé »
de `keybag_native_path.md` §3 est **levé** : il ne faut pas de capture OOL, le **codec** donne la grammaire.
**INCONNU résiduel (à fournir/trancher)** : la **valeur** du code `+0x60` (transition cible) et de l'u64 `+0x68` ;
le passcode d'Albert est fourni **à l'exécution** dans le blob `+0x70/+0x78` (jamais stocké/extrait) ; et
l'acceptation brute de 0x18 sur un keybag d'appareil Linux = **matériel** (classe neuve → go d'Albert).

---

## 2. Cible 2 — `authentication_token_create` (TAG fil **0x1c**)

### 2.1 Chaîne d'appel et TAG — VU
C++ `authentication_token_create(this, u64 arg1, u32 arg2, int arg3, OSData* secret, OSData** out)` @0xcc709c
(`this` inutilisé : keystore = singleton `[[0xcbb8cf0]+0x150]`) → builder `__ipc_authentication_token_create` @0xcfb52c
→ **submit** `mov w1,#0x1c ; mov x17,#0x392e ; blraa x20,x17` @0xcfb594 (et branche jumelle @0xcfb5b4) → codec
`_code_ipc_authentication_token_create` @0xce2644.

**TAG fil = 0x1c — VU** (immédiat du submit, même mécanisme que 0x18/0x19/0x0d). Validation croisée : le builder situé
**juste après** `__ipc_device_state_transition` soumet `w1=0x19` = `get_device_state` (`sks_protocol.md` §1.3) → la
correspondance « immédiat submit = TAG fil » est cohérente sur des TAG connus. **Pourquoi la session Mac l'a manqué**
(`acm_token.md` §6) : elle cherchait un codec de **réception** (table `_get_process_table`, base 0x8295290) ; le TAG
d'**émission** vit dans le builder. **Non recoupé sur trace** (aucune capture OOL 0x12) → VU-désassemblage, pas `vérifié`.

### 2.2 Flot des arguments — VU
C++ @0xcc709c : lit `getBytesNoCopy`/`getLength` du `secret` (arg4) → (ptr `x24`, len `x6`), puis appelle le builder
`(keystore, x1=0, x2=arg1, x3=arg2, x4=arg3, x5=ptr, x6=len, x7=&outptr, [sp]=&outlen)` @0xcc7150-0xcc7174 — VU.
Côté dispatch userclient (VU, `acm_token.md` §2.1) : **arg2 = handle de keybag** (`effective_bag_handle_actual`),
**secret** = `secretFromInput`, entitlement `com.apple.keystore.auth-token` exigé.

### 2.3 Corps OOL — disposition octet (VU, codec @0xce2644)
Même famille de primitives que §1.3. Un **seul blob** dont l'emplacement struct dépend de la direction :
requête → `+0x68/+0x70` ; réponse → `+0x78/+0x80` (`cmp w22,w23; b.eq`).

| offset fil | primitive | contenu | statut |
|---|---|---|---|
| 0x00–0x4f | `__ipc_header`+ext | en-tête IPC négocié (= §1.6) | VU |
| **+0x50** | `__word` u32 | **état** — doit valoir **0** (`ldur w8,[x21,#0x50]; cbz`) | VU |
| **+0x58** | `__lword` u64 | arg1 (session/contexte ; = `[sp+0xc8]` du dispatch, `acm_token.md` §2.1) | VU champ / **sens INCONNU** |
| **+0x60** | `__word` u32 | **handle de keybag** (arg2 = `effective_bag_handle_actual`) | VU champ / DÉDUIT fort |
| **+0x64** | `__word` u32 | sélecteur/flag (arg3 = `input[8]`) | VU champ / **sens INCONNU** |
| **+0x68 / +0x70** | `__blob` (requête) | **secret/credential en entrée** {ptr,len} (dérivé du code côté ACM/userland, borné ≤ 0x1000) | VU |
| **+0x78 / +0x80** | `__blob` (réponse) | **jeton en sortie** {ptr,len} — **blob opaque** (enveloppé en `OSData`, posé dans `*out`) | VU |

**Gabarit d'octets : OUI** pour la requête (offsets/types/handle/blob connus). **Structure interne du jeton**
(`+0x78/+0x80`) = **INCONNU** (opaque côté AP, interne SEP ; forgé + revérifié par le SEP, non calculable hors SEP —
`acm_token.md` §3). **INCONNU résiduel** : valeurs de `+0x58` (u64 session) et `+0x64` (sélecteur) ; et si l'op passe
**brute sur EP 0x12** ou exige un état ACM posé par coreauthd (`acm_token.md` §5) = **matériel**.

---

## 3. Verdict par cible + INCONNU qui bloque

| cible | TAG fil | gabarit d'octets du corps | ce qui reste INCONNU (précis) |
|---|---|---|---|
| `device_state_transition` (unlock) | **0x18** (VU, recoupé c12) | **OUI** : état=0, handle(+0x58), code(+0x60), rés=0(+0x64), u64(+0x68), blob passcode(+0x70/+0x78) ; réponse +0x80/+0x88 | **valeur** du code d'état `+0x60` (p.ex. −501) et de l'u64 `+0x68` ; acceptation brute sur keybag Linux = **matériel** |
| `authentication_token_create` | **0x1c** (VU submit, **non** recoupé trace) | **OUI (requête)** : état=0, u64(+0x58), handle(+0x60), sél(+0x64), blob secret(+0x68/+0x70) ; jeton réponse +0x78/+0x80 | **valeur** u64 `+0x58`/sél `+0x64` ; **contenu interne du jeton** (opaque, interne SEP) ; dépendance à un état ACM/coreauthd = **matériel** |

**Aucun champ d'offset ne reste indéterminé** : les codecs donnent l'intégralité de la grammaire des deux messages.
Les seuls blancs sont (a) des **valeurs de scalaires** fixées par l'appelant (code de transition, u64/sélecteurs de
session), (b) le **contenu opaque du jeton** (hors binaire AP, interne SEP), (c) des questions **100 % matériel**
(le SEP accepte-t-il ces ops brutes sur EP 0x12, sur un keybag recréé par Linux ?) — classe neuve, **go d'Albert**.
Le passcode/secret d'Albert reste fourni **à l'exécution**, jamais stocké ni extrait.
