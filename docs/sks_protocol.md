# SKS / EP 0x12 — protocole de messages pour un pilote Linux natif

Rédigé le 2026-11-23 (agent driver, session ALARM). **But** : réunir ce qu'il faut pour, sous Linux natif, (1) parler
à SKS (EP 0x12) correctement, (2) déverrouiller le keybag utilisateur avec le mot de passe, (3) produire/obtenir un
AuthToken ou un CredentialSet acceptable pour sbio 0x03 (enrôlement/match).

Référence croisée : `sks_native_plan.md` (transport vu, inconnues, plan d'expériences gradué — ce doc le complète côté
**protocole**), `kext_sepmanager.md` §14/§14b/§15 (architecture AKS, enveloppe noyau, schéma DER — fait sur macOS 13.5),
`sks_sequence_c12.md` (séquence de bring-up chaîné), `biometrickit_protocol.md` (jeton 0x03 = AuthToken/CredentialSet,
relayé par biometrickitd depuis le client XPC — macOS 27.2.1).

**Convention** : **VU** = lu dans une trace (chiffres) ou dans le désassemblage/les symboles (adresse/symbole/immédiat) ;
**DÉDUIT** = interprété d'après noms/contexte ; **INCONNU** = non déterminé. `source: kext` (kernelcache) /
`source: userland` (dyld). Rien d'inventé ; « je ne sais pas » est une réponse.

**Sources binaires (27.2.1, la version installée)** : kernelcache `macos/kc/26B131__MacBookPro18,4/kernelcache.release.*`,
bundle `com.apple.driver.AppleSEPKeyStore` (désassemblé via `ipsw macho disass -t … -s …` et `analysis/kext/kdis.py`).
Les symboles **libaks C** sont présents en 27.2.1 (`_aks_params_*`, `__ipc_get_capabilities`, `_kern_perform_operation`,
`__aks_operation`, `_ref_key_op_der_to_enum`, `_der_dict_*`, la table `_code_ipc_*`) ; les méthodes C++ de plus haut
niveau (`verify_password`, `load_keybag`…) **ne sont PAS symbolisées** en 27.2.1 (elles l'étaient dans le `kernel.macho`
13.5 de §15, binaire aujourd'hui supprimé).

> **Note de session (2026-11-23, mission PC c9)** : une tentative de décompilation *fraîche* de l'en-tête IPC octet
> par octet **sur 27.2.1** avait été **interrompue par un classifieur de sûreté** (aucun résultat ; aucun contournement
> tenté). En revanche l'en-tête OOL et `get_capabilities` ont été **entièrement dérivés sur le binaire 13.5
> `macos/kernel.macho`** (agent reverseur, `docs/sks_ipc_negotiation.md`), et cette session a **re-vérifié
> indépendamment** les points porteurs de ce document contre le binaire : les 10 symboles cités résolvent **à
> l'adresse exacte** (`init_sep_endpoint` …9950dbc, `__ipc_get_capabilities` …99671c4, `_code_ipc_get_capabilities`
> …9973eb0, `__payload_hash` …9975a50, `sep_deliver_msg(ipc_callback_ctx_t*,u32,void*)` …99453f8, `_get_process_table`
> …9967ca4…), et la **table d'opérations** se décode exactement (base `0xfffffe0007004000`, entrées de 0x48 o : entrée
> `0x4d` = code 0x4d, `ctxsize` 0x88, pointeur +0x10 → `_code_ipc_get_capabilities`). Donc §1.4 et **§1.6 (nouveau)**
> ci-dessous sont `source: kext` **sur 13.5, re-vérifiés au binaire** — mais **non confirmés matériel** (rien lancé) et
> **non re-dérivés octet par octet sur 27.2.1** (les symboles et la table existent en 27.2.1 d'après la passe 27.2.1 ;
> l'en-tête lui-même n'y a pas été relu). La passe **DER (§2)** a, elle, abouti **sur 27.2.1** (conteneur SET, types,
> table param_id, codes de clé, sélecteurs `o` — corrige §15.3). Table des opérations IPC par **nom de symbole** et
> séquence de bring-up **ancrée sur trace** : établies.

---

## 1. Format fil EP 0x12 (Q1)

### 1.1 Ouverture de l'endpoint (CNTL) — VU (trace c12, c1)
`sks` (EP 0x12) est ouvert par 4 mots CNTL sur EP 0x00, PARAM = 0x12, **exactement** (c12 L170-176, octets réels) :

| mot | TYPE | PARAM | DATA | sens |
|---|---|---|---|---|
| `> EP=0x00 TAG=t TYPE=0x04 PARAM=0x12 DATA=0x00008000` | 0x04 | 0x12 | 0x8000 | taille tampon A (OOL requête) = 0x8000 |
| `> … TYPE=0x02 PARAM=0x12 DATA=0x00000074` | 0x02 | 0x12 | 0x74 | IOVA tampon A >> 12 (= 0x74000) |
| `> … TYPE=0x05 PARAM=0x12 DATA=0x00008000` | 0x05 | 0x12 | 0x8000 | taille tampon B (OOL réponse) = 0x8000 |
| `> … TYPE=0x03 PARAM=0x12 DATA=0x00000080` | 0x03 | 0x12 | 0x80 | IOVA tampon B >> 12 (= 0x80000) |

Chacun est acquitté `< EP=0x00 TAG=t TYPE=0x01 …` (même DATA). Taille 0x8000 = annonce FD TYPE 1 `0x02010201`
(pages [1,2,1,2] → max 2×0x4000). Ordre macOS : **skdl (0x17), puis sks (0x12), puis scrd (0x0a)** ; rien n'est
envoyé à un EP avant son ouverture. Les IOVA (0x74000/0x80000) sont **ceux de la trace macOS** ; en natif, ce sont
nos propres tampons DMA (valeurs libres, cf. `sks_native_plan.md` §5).

### 1.2 Mot de requête / de réponse (mailbox) — VU (trace, 579/579 c1, 90/90 c12)
- **Requête** `> EP=0x12 TAG=t TYPE=n PARAM=0 DATA=(len_req << 16)`. TAG = **code d'opération** (cf. §1.3) ;
  TYPE = **compteur de transaction** global au boot, mod 256, 1..n sans trou ; PARAM = 0 ; bits 16-31 de DATA =
  longueur de la requête en octets. Le **contenu réel (DER) est dans le tampon OOL A**, pas dans le mot.
- **Réponse** `< EP=0x12 TAG=(t|0x80) TYPE=n PARAM=s DATA=(len_resp << 16 | flag)`. TAG = requête | 0x80
  (0x4d→0xcd, 0x22→0xa2, 0x48→0xc8…) ; même TYPE ; PARAM = **statut** (0x00 = OK ; 0xff/0xfe/0xfd/0xfb/0xed = codes
  d'erreur/fin/pas-de-données, toujours avec DATA = 0) ; bit 0 de DATA = drapeau « invalider le cache ». DER de
  réponse dans l'OOL B.
- **Notifications SEP → AP** (TAG < 0x80, sans requête) : TAG 0x00 = déverrouillage (DATA = handle du keybag),
  TAG 0x01 = verrouillage, TAG 0x09 = (rôle inconnu). Corrélées au log noyau « Sending lock change… » (messages.md,
  vérifié pour les valeurs).
- **En-tête du tampon OOL A/B** : INCONNU au niveau octet. L'OOL 0x12 **n'a jamais été capturé** (aucune trace n'a
  0x12 dans `full_types`). Ce n'est **pas** le `gt_packet` de sbio (celui-ci est propre à EP 0x08). Côté kernel,
  `_kern_perform_operation` remet un pointeur DER + longueur à l'endpoint (§1.5) ; l'encodage mailbox+OOL exact est
  posé par la **classe endpoint d'`AppleSEPManager`** (hors de ce kext, non décompilée).

### 1.3 Table TAG fil → opération IPC — noms VU (symboles), valeurs numériques partiellement VU
Le kext expose une table d'opérations IPC comme symboles `_code_ipc_*` (**93 entrées VU** dans le binaire 27.2.1).
Chaque opération IPC a un **code numérique = le TAG fil**. Les noms (symboles) sont VU. Le **mapping nom↔numéro**
complet a été **décodé sur 13.5** (`docs/sks_ipc_negotiation.md` §2 : table `_get_process_table` @…9967ca4, 0x54 entrées
de 0x48 o ; `entrée[code].code == code`, et le pointeur +0x10 pointe le codeur `_code_ipc_<nom>` — re-vérifié cette
session pour 0x4d). Les lignes ci-dessous sont donc **VU (table 13.5)** et cohérentes avec la position de bring-up c12
(le numéro 27.2.1 pourrait en principe différer — non re-décodé sur 27.2.1) :

| TAG fil (VU trace) | opération IPC (nom symbole VU) | statut du mapping | req/resp c12 (×0x100 o) |
|---|---|---|---|
| 0x4d | `get_capabilities` | **VU (table 13.5)** ; 1re txn des 6 boots, resp `5c` flag 1 = négociation | 0x64 / 0x5c |
| 0x2a | `set_env` | VU (table 13.5) | 0x470 / 0x58 |
| 0x22 | `perform_operation` (= l'op AKS/DER générique, §2) | VU (table 13.5) | 0x8c / 0x14c ; 0x90 / 0xb8 |
| 0x0a | `null_d_key` | VU (table 13.5) | 0x60 / — (PARAM 0xff) |
| 0x48 | `fv_get_blob_state` (FileVault) | VU (table 13.5) | 0x1dc / 0x110 ; 0x230 / 0x110 |
| 0x19 | `get_device_state` | VU (table 13.5 ; = requête la plus fréquente = poll) | 0x68 / — |
| 0x41 | `fv_unwrap_vek` — **déverrouillage mot de passe, 1re étape (volume)** | nom **VU (table 13.5)** ; rôle = trace+uart (messages.md). Cohérent : déverrouiller un volume FileVault = « unwrap VEK » | 0x240 / 0xa0 |
| 0x18 | `device_state_transition` — **déverrouillage -501, 2e étape** | nom **VU (table 13.5)** ; rôle = trace+uart | — |
| 0x2f | `handle_timer_fire` — **verrouillage keybag/volume différé** | nom **VU (table 13.5)** ; rôle = trace (messages.md). Cohérent : minuterie → verrouillage différé (DÉDUIT) | — |
| 0x32 | `unwrap_media_key` | nom **VU (table 13.5)** ; rôle au bring-up c12 non interprété | 0x94 / 0xb4 |
| 0x47 | `fv_set_protection` | nom **VU (table 13.5)** | 0x244 / 0x60 |
| 0x10 | `new_pfk_data` | nom **VU (table 13.5)** | 0xb8 / … |

Table d'opérations IPC (extrait VU des symboles `_code_ipc_*`, = vocabulaire des TAG possibles) : `get_capabilities`,
`set_env`, `get_configuration`/`set_configuration`, `get_device_state`, `device_state_transition`, `perform_operation`,
`generic_operation`, `change_lock_state`, `change_secret`, `verify_secret`, `create_keybag`, `load_keybag`,
`unload_keybag`, `unload_session_keybags`, `copy_keybag`/`copy_keybag_uuid`, `invalidate_keybag`, `make_system_keybag`,
`keybag_persona_create/delete/list`, `create_d_key`/`null_d_key`/`unwrap_d_key`, `authentication_token_create`,
`authentication_token_verify`, `fv_get_blob_state`/`fv_get_size`/`fv_new_kek`/`fv_new_vek`/`fv_unwrap_vek`/
`fv_rewrap_kek`/`fv_set_protection`, `kc_wrap`/`kc_unwrap`, `escrow_stash_*`, `escrow_keys_unlock`, `smartcard_op_*`,
`remote_session*`, `identity_*`, etc. (noms = étiquettes de protocole, aucun secret).

### 1.4 Négociation d'en-tête IPC (get_capabilities) — source: kext 13.5, re-vérifié au binaire (§1.6), **non confirmé matériel**
Avant tout `perform_operation`, l'AP négocie une **version d'en-tête IPC** (v1/v2, plafond 2) via
`__ipc_get_capabilities` (@…99671c4 en 13.5 ; @0xfffffe0009cfdf6c en 27.2.1, VU present) +
`_msg_header_set_negotiated_version` (@…9967c90 en 13.5 ; @0xfffffe0009cde060 en 27.2.1). Chaînes :
`negotiated to ipc header theirs:v%llu ours:v%u -> negotiated:v%llu`, `failed to negotiate, defaulting to v1`,
`SEP timeout multiplier = %u`. La 1re transaction `0x4d` (req 0x64 o → resp `cd … 5c` drapeau 1) **est** cette
négociation (DÉDUIT, cohérent trace 6/6 boots). **`ours = 2` (constante VU)** ; version retenue = `min(theirs, 2)`.

Le format de l'en-tête OOL et des 0x64 o de `get_capabilities` est maintenant **établi octet par octet** — voir
**§1.6** (dérivé de 13.5, cross-ref `docs/sks_ipc_negotiation.md`). En résumé : l'en-tête OOL (0x54 o) contient des
champs **contextuels** (horodatage µs, identifiant de processus, cdhash) et un **SHA-256 tronqué 16 o** dont la **base
est connue** (§1.6.3). Ce n'est donc **pas un blob constant rejouable** : sous Linux il faut le **construire** (le
condensé n'est pas un secret, juste une empreinte de cadre). Sur les champs processus, le kext ne **lit jamais**, à la
réception, un verdict du SEP sur eux (§1.6.4) → un hôte non-macOS peut vraisemblablement les mettre à des valeurs
neutres (DÉDUIT ; seul le matériel tranchera).

### 1.5 Enveloppe de requête côté noyau (`_kern_perform_operation`) — source: kext (VU 27.2.1)
Le dispatcher `_kern_perform_operation` (@0xfffffe0009cf6f70) construit sur la pile, puis soumet à l'endpoint SKS :
`{+0x00 ptr contexte, +0x08 handle, +0x0c const, +0x10 ptr buffer DER, +0x18 len DER (w32), +0x20 ptr out, +0x28 ptr
out_len}`. **L'opération réelle et tous les arguments sont dans le buffer DER** (pas un opcode dans le mot) — confirme
§14b. Corrections 27.2.1 vs §15.2 (13.5), VU par l'agent DER :
- **+0x08 = handle de KEYBAG**, pas « ref_key handle » : initialisé à 0xffffffff puis rempli par
  `effective_bag_handle_for_kpi(handle, &+0x08)` (symbole `__ZL28effective_bag_handle_for_kpiiPi`, VU). L'arg `x0`
  du wrapper est donc un handle de keybag (DÉDUIT du nom + du flot de `create`).
- **+0x0c = 2** en 27.2.1 (constante VU), **pas 3** comme en 13.5 ; signification INCONNUE.
- Callback `AppleKeyStore::perform_operatation_gated(_ref_key_operation_args*)` (@0xfffffe0009cf6f20), soumis via la
  vmethod `+0x1e8` de l'instance endpoint. Codes d'erreur de garde : 0xe00002c2 ; fusion impossible : 0xe007c00a.
- Ouvert : le buffer DER part-il tel quel dans l'OOL, ou précédé d'un en-tête IPC (§1.4/§1.6) ? Symboles
  `__ipc_header_size`/`__ipc_header_effective_size`/`_msg_header_set_negotiated_version` VU → à trancher dans
  `perform_operatation_gated`. **Indice §1.6** : tout message IPC SKS (pas seulement `get_capabilities`) est encodé par
  le **même codeur générique** (en-tête de 0x54 o en tête de l'OOL, puis le corps propre à l'opération) ; le DER d'un
  `perform_operation` est donc très probablement précédé de cet en-tête IPC, et non posé nu (DÉDUIT, à confirmer).


### 1.6 En-tête OOL et `get_capabilities` octet par octet (Q1 + Q2) — source: kext 13.5, re-vérifié au binaire ; **non confirmé matériel**

Dérivé de `macos/kernel.macho` (13.5) et **re-vérifié cette session** (adresses + table d'opérations, cf. Note de
session). Référence complète, chaîne d'appel et conditions d'échec : `docs/sks_ipc_negotiation.md`. Statut de chaque
ligne : **VU** = lu au désassemblage (adresse) ; **DÉDUIT** = interprété ; **INCONNU**. Aucune valeur de clé/secret.

### 1.6.1 Disposition générale de l'OOL (Q1) — VU
Le mot mailbox ne porte **jamais** le contenu ; tout passe par l'OOL (tampon A = AP→SEP = requête ; tampon B =
SEP→AP = réponse). Le **même codeur** `_code_ipc_<op>` (@…9973eb0 pour 0x4d) écrit (mode `w0=1`) / lit (`w0=0`) dans
le descripteur `[this+0x168]` (A) / `[this+0x170]` (B) avec des primitives : `__word` = u32 LE (avance 4), `__lword` =
u64 LE (avance 8), `__blob` = u32 longueur + données **alignées sur 4**, `__ipc_header` = u32 longueur (**toujours 0x50
à l'encodage AP**) + 0x50 o d'en-tête. **Ordre : petit-boutien (little-endian)** pour tous les scalaires.

Structure générique d'un message IPC dans l'OOL :

| zone | taille | contenu |
|---|---|---|
| en-tête IPC | **0x54 o** = `__ipc_header_size` | u32 longueur (0x50) + 0x50 o d'en-tête (§1.6.2) |
| corps | variable | propre à l'opération (pour 0x4d : §1.6.2 bas) |

### 1.6.2 Les 0x64 o de la requête `get_capabilities` (Q2) — VU
`> EP=0x12 TAG=0x4d TYPE=seq PARAM=0 DATA=0x00640000` ; les 0x64 o de l'OOL A :

| offset | taille | champ | valeur / source | variable ? |
|---|---|---|---|---|
| 0x00 | 4 | longueur en-tête | **0x50** (constante à l'encodage) | constant |
| 0x04 | 16 | **condensé d'intégrité** = SHA-256 **tronqué 16 o** | calculé (§1.6.3) | contextuel |
| 0x14 | 4 | version d'en-tête | **1** (la requête de négociation part toujours en v1) | constant |
| 0x18 | 8 | horodatage µs (`_get_usec_time`) | horloge | **contextuel** |
| 0x20 | 4 | drapeaux (bit0 = chiffré, bit1 = en-tête étendu) | **0** | constant |
| 0x24 | 8 | champ ctx+0x20 | 0 (non écrit sur ce chemin) | constant |
| 0x2c | 8 | `proc_uniqueid(proc_self())` | identifiant du processus appelant | **contextuel** |
| 0x34 | 4 | champ de la cred (`[cred+0x80]+0x24`) | id utilisateur (DÉDUIT) | **contextuel** |
| 0x38 | 20 | cdhash du processus (`cs_get_cdhash`) ; **à défaut** SHA-1 des 8 o de 0x2c | signature du binaire appelant | **contextuel** |
| 0x4c | 8 | ctx+0x48..0x4f | 0 (couvert par le condensé seulement en v2) | constant |
| 0x54 | 4 | mot d'état | **0** | constant |
| 0x58 | 8 | u64 | **1** (3e arg d'`__ipc_get_capabilities`, constant aux 2 appels) ; sens exact INCONNU | constant |
| 0x60 | 4 | longueur de blob | **0** (aucune donnée) | constant |

Total = **0x64** = la valeur de DATA (recoupe la trace). L'en-tête étendu (offset variable) n'est écrit que si
version ≥ 2 ; en v1 le bit1 des drapeaux est effacé et rien n'est ajouté.

### 1.6.3 Ce que couvre le SHA-256 tronqué (Q2) — VU
`__payload_hash` (@…9975a50) : `ccsha256_di`, **sans clé** (ce n'est pas un MAC, aucun secret), **tronqué à 16 o**, sur,
**dans cet ordre** : version (4) ‖ horodatage (8) ‖ drapeaux (4) ‖ champ +0x20 (8) ‖ **bloc processus** (0x20 o en v1 =
ctx+0x28..0x47 ; 0x28 o en v2) ‖ **charge** (tout ce qui suit l'en-tête, ici l'état + u64 + blob). Le résultat est
écrit à l'offset 0x04. À la réception, le kext **recalcule et compare** 16 o ; échec → `ipc digest failed`. Version ≠ 1
et ≠ 2 → `unexpected version` (code -0xf). → **Base du SHA connue** ; reproductible côté Linux sans secret.

### 1.6.4 La réponse `< EP=0x12 TAG=0xcd TYPE=seq PARAM=s DATA=0x005c0001` (Q4) — VU
Appariement (`sep_deliver_msg_gated`) : le kext accepte la case `this+0x180` si l'octet TAG a le **bit 7** posé **et**
que l'octet TYPE = la séquence envoyée. **Les 7 bits bas du TAG ne sont PAS comparés** : `0xcd = 0x4d|0x80` est une
convention SEP, pas un contrôle. Attente = 6 s × multiplicateur, jusqu'à 20 tentatives (`sks request timeout`).

| octet du mot | lu comme | valeur | traitement |
|---|---|---|---|
| 3 | PARAM, **int8 signé** (`ldrsb`) | 0 | ≠ 0 → aucun décodage, la requête rend ce code (ex. 0xff → -1) |
| 4-5 | u16 « drapeaux d'appel » | **0x0001** | bit 0 → invalide le cache d'état global, journal `invalidated cache (sync)` — traité **avant** le test de PARAM |
| 6-7 | u16 longueur de réponse | **0x005c** | doit être ≤ taille du descripteur B, sinon échec |

Charge reçue (0x5c o dans l'OOL B) — algorithme VU : (1) u32 longueur L, copie min(L,0x50) ; (2) condensé vérifié selon
la **version lue dans l'en-tête du SEP** ; (3) en-tête étendu si v≥2 et bit1 ; (4) u32 état = **doit être 0** ; (5) u64
« theirs » (version d'en-tête du SEP) + blob (ici vide) ; (6) **octets consommés = longueur annoncée exactement**.
Disposition de 0x5c **DÉDUITE** des tailles : L = **0x48** (en-tête v1), état (4), theirs (8), long. blob = 0 →
0x4c+4+8 = 0x5c (avec L = 0x50 le minimum serait 0x64 : impossible → le SEP répond en en-tête plus court que l'AP).
Puis `init_sep_endpoint` : `négociée = min(theirs, 2)`, `ours = 2`. **La valeur réelle de « theirs » reste INCONNUE**
(OOL 0x12 jamais capturé) ; v2 est seulement **DÉDUIT** des tailles des réponses suivantes (`set_env` en 0x58 → en-tête
0x54 → L = 0x50 = v2).

### 1.6.5 Vérifications SEP et portabilité non-macOS (Q3) — VU (côté AP) + DÉDUIT
- **Côté AP, à la réception**, le kext ne lit du SEP qu'un **état (= 0)**, les **drapeaux d'appel**, un **condensé de
  cadre** (recalculé localement) et **theirs**. Il ne lit **aucun verdict** du SEP portant sur le pid / cdhash / uid
  qu'il a envoyés (VU). → **On ne peut pas savoir, depuis le kext, si le SEP vérifie ces champs processus.** (INCONNU.)
- Le **condensé** (SHA-256/16) est un contrôle d'**intégrité de cadre** sans clé : un hôte Linux peut le recalculer
  (base §1.6.3). Les champs **contextuels** (horodatage, pid, cdhash, uid) sont des métadonnées du processus appelant :
  un hôte non-macOS peut les remplir de valeurs neutres (p.ex. horodatage courant, pid/uid arbitraires, cdhash à zéro —
  le code gère déjà « pas de cdhash » via le SHA-1 des 8 o de 0x2c). **Reste à vérifier sur matériel** que le SEP ne
  rejette pas sur ces champs (DÉDUIT ; expérience « un seul `get_capabilities` » = classe neuve, `pending/` + go
  d'Albert). Un `get_capabilities` en **erreur** laisse quand même la négociation retomber sur **v1** sans bloquer la
  suite (`failed to negotiate, defaulting to v1`), donc l'expérience est **peu risquée côté logique** (le coût reste le
  run + power-cycle).

---

## 2. Schéma DER des paramètres (Q2) — source: kext (VU 27.2.1)

> Confirmé/corrigé sur 27.2.1 par l'agent DER (journal 2026-11-23). Symboles : `_aks_params_get_der` @0xcbf820
> (= saut vers `_encode_list_dict` @0xcffd88), `_aks_params_set_number` @0xcee628, `_aks_params_set_data` @0xcee700,
> `__params_get_der_key` @0xcbf5c4, `_der_dict_iterate` @0xcff954, `_ref_key_op_der_to_enum` @0xd0155c. Les stubs
> `ccder_*` (corecrypto) et `kx_qsort` sont résolus (VU).

**Conteneur racine = SET (`0x31`), PAS SEQUENCE** (corrige §15.3). VU : `_encode_list_dict` encode un
`ccder_sizeof(CONSTRUCTED|SET, …)` → tag 0x31 ; le décodeur `_der_dict_iterate` décode d'abord un SET (0x31) puis,
pour chaque entrée, une **paire = SEQUENCE (`0x30`) { clé, valeur }**, la clé étant un **UTF8String DER (tag 0x0c)**
portant un code court ASCII (la constante `___der_key_*` déjà encodée, recopiée telle quelle).
- **Ordre des paires** : déterministe = **ordre lexicographique de la chaîne de clé** (VU, `kx_qsort` + comparateur
  @0xd01d0c : compare tag de clé puis `memcmp`, la plus courte d'abord). Ce n'est **pas** le tri canonique X.690
  d'un SET OF. Chaque clé apparaît au plus une fois (`_encode_list_remove_key` avant chaque ajout, VU).
- **Types des valeurs** (VU) : **INTEGER (`0x02`)** par `_encode_list_add_number` (complément à deux minimal,
  big-endian, 1–8 o) ; **OCTET STRING (`0x04`)** par `_encode_list_add_data` ; **DER brut recopié** (`_encode_list_add_der`)
  pour `o`, `rk`, et certains `d`. Cas spéciaux de `set_data` (VU) : param_id 1 `ag` = la valeur DOIT déjà être une
  SEQUENCE (0x30) ; param_id 2 `ed` = la valeur DOIT déjà être un SET (0x31) = dictionnaire imbriqué ; sinon OCTET STRING.
  **BOOLEAN** : aucun encodeur dans le kext (le param_id type 3 `skni` n'a pas de setter → booléen posé côté userland,
  INCONNU).
- **La valeur de `o` est une UTF8String** (pas un entier) : VU (`__create_operation_list` ajoute la constante
  `___der_key_op_X` en DER brut ; `_ref_key_op_der_to_enum` compare par `_der_equal`). Exemple op=encrypt (DÉDUIT des
  constantes VU) : paire = `30 07 0c 01 6f 0c 02 6f 65` (SEQ{ UTF8"o", UTF8"oe" }).

Champs (nom → code fil, VU table `___der_key_*` @0xfffffe000770f6f0..febd, 116 entrées pas 0x12) :

| champ | code DER | rôle (hypothèse) | constant / contextuel |
|---|---|---|---|
| op | `o` | **sélecteur d'opération** (valeur = code §2.1) | constant par opération |
| ref_key | `rk` | handle/blob de clé scellée | **contextuel** |
| keybag_class | `bc` | classe de protection (A/B/C/D) | semi-constant |
| data | `d` | données d'entrée | **contextuel** |
| auth_data | `ad` | données d'authentification | **contextuel** |
| protected_data / external_data | `pd` / `ed` | | contextuel |
| acm_handle | `acmh` | **handle ACM** (contexte LAContext/auth — cf. §5) | **contextuel** |
| access_groups | `ag` | groupes d'accès keychain | contextuel |
| salt / flags / id | `salt` / `f` / `id` | | mixte |
| key type/version/uuid | `kt` / `kv` / `kid` | | contextuel |
| dst_keybag_handle | `dbh` | keybag de destination (transcrypt) | contextuel |
| **piège** | `kid` vs `uuid` | **`kid` = uuid de CLÉ** (`der_key_uuid`) ; **`uuid` = uuid UTILISATEUR** (`der_key_user_uuid`). Deux champs distincts | — |

**Codes nouveaux en 27.2.1** (absents de la doc 13.5 ; aucun code 13.5 n'a disparu — VU) :
- paramètres : `bh` (keybag_handle), `p` (passcode), `gp` (graceperiod), `bd` (backoff_delay), `epp`/`etp` (escrow
  passcode/token period), `pdp`/`pdps`/`pdpi`/`pdpt` (prederived_*), `uuuid` (config_user_uuid), `bk` (bind_kek),
  `uuid` (user_uuid), `guid` (group_uuid), `vuid` (volume_uuid), `lt` (lock_time), `ire` (inactivity_reboot_enabled),
  `oam` (oneness_automatic_mode), `seed`, `cxw` (cx_window), `vgsg` (vek_group_seed_generation).
- état : `sms` (more_state), `sllt`/`slpu`/`slpa`/`slmu`/`slma` (abs_lock_time, last passcode unlock/auth, last mesa
  unlock/auth). Noter **`p` (passcode)** : un code de clé DER dédié au passcode existe (pertinent Q4, §4).

**État renvoyé** (réponse / notif) : `ss` state, **`sls` state_lock_state** (clé du gating bio), `sb`/`sbo` backoff,
`sfa`/`sfao` failed_attempts, `sgs` generation, `sas` assertions, `srcd` recovery countdown, `refc`, `sr` + nouveaux
ci-dessus.

### 2.0 Table `aks_params` = 26 param_id typés (VU, `__params_get_der_key`)
`set_number` passe le type 1, `set_data` le type 2 ; la clé n'est rendue que si le type attendu concorde (VU) :

| id | clé | type | id | clé | type | id | clé | type |
|---|---|---|---|---|---|---|---|---|
| 0x01 | ag | 2 | 0x0a | si | 2 | 0x13 | skni | **3** |
| 0x02 | ed | 2 | 0x0b | si2 | 2 | 0x14 | rskt | 1 |
| 0x03 | acmh | 2 | 0x0c | tsi | 2 | 0x15 | rsct | 2 |
| 0x04 | salt | 2 | 0x0d | tsi2 | 2 | 0x16 | grko | 1 |
| 0x05 | d | 2 | 0x0e | tecdhs | 2 | 0x17 | spka | 1 |
| 0x06 | ecdhs | 2 | 0x0f | prsn | 2 | 0x18 | vuid | 2 |
| 0x07 | ecdhi | 2 | 0x10 | srkt | 1 | 0x19 | seed | 2 |
| 0x08 | ro | 1 | 0x11 | skcs | 2 | 0x1a | tf | 1 |
| 0x09 | rko | 1 | 0x12 | skos | 1 | | | |

### 2.1 Sélecteurs d'opération (valeur du champ `o`) — VU (table `___der_key_op_*`)
`oc` create, `ocwe` create_with_encrypt, `ocww` create_with_wrap, `odel` delete, `oe` encrypt, `od` decrypt,
`osgn` sign, `ow` wrap, `ouw` unwrap, `ock` compute_key, `oa` attest, `orwk` transcrypt, `ovk` validate_key,
`oskc` set_key_class, `oece`/`oecd`/`oect` ecies enc/dec/transcode, `osc`/`osa`/`ogss` sik collection/attest/status,
`oska`/`oskc2`/`oskgp`/`osko`/`osks` system_key attest/collect/get_public/operate/sign. `_ref_key_op_der_to_enum`
(@0xd0155c) mappe le code reçu → énum interne via une table de 30 entrées (VU, `__const` ≈0x7710088). Les valeurs
d'énum sont **internes au kext** (le fil transporte la chaîne UTF8 seule). Tous les codes §15.4 confirmés en 27.2.1 ;
**nouveaux** (VU) : `oke` kem_encapsulate (0x1c), `okd` kem_decapsulate (0x1d), `skck` system_key_compute_key (0x1e).

### 2.2 Composition par opération (VU) et rejouabilité (DÉDUIT)
Gabarit commun (VU) : `__create_operation_list(op)` (pose `o`) → `__get_merged_params` (@0xceeee8 : fusionne les
params stockés dans l'objet ref_key `ctx+0x30/+0x38` puis ceux de l'appel, et **retire `ed`**) → champs propres de l'op →
`_encode_list_dict` (SET) → `__aks_operation` → `_kern_perform_operation`. Champs ajoutés (VU) :

| opération | champs ajoutés |
|---|---|
| encrypt / sign / wrap | `d` (OCTET STRING) + `rk` (DER brut) |
| unwrap | `d` (DER brut) + `rk` |
| delete | `rk` seul |
| set_key_class | `bc` (INTEGER) + `rk` |
| transcrypt | `dbh` (INTEGER) + `rk` |
| compute_key | `pub` (OCTET STRING) + `rk` |
| decrypt | `d`/`rk` DER brut ; lit d'abord `tag`/`pd` dans le blob d'entrée (détail INCONNU) |
| attest | 2e merge, `d` = liste imbriquée + `rk` |
| create | `{o=oc, <merged>, bc INTEGER, kt INTEGER}`, envoyé avec le handle keybag=arg0 |
| system_key attest/collect/get_public | `skt` (+`skg`) |
| system_key operate / sign | `skt`, `sko` / `skt`, `skg`, `d` |

**`rk` = la réponse complète de `create`** (VU) : la réponse SET est conservée dans l'objet (`ctx+0`..`+0x10`), et `rk`
des opérations suivantes = ce blob entier recopié en DER brut ; `kt`/`kv`/`kid`/`pub`/`bc` s'y relisent par accesseurs.

**Rejouabilité (DÉDUIT)** : constant pour une op = la paire `o`, les noms de clé, le tag SET, l'ordre lexicographique.
Contextuel/non rejouable = `rk` (blob scellé par le SEP, propre à chaque clé — non inspecté, hors périmètre), `acmh`
(handle d'auth runtime), `d`/`pd`/`tag`, `salt`/`ecdh*`/`seed`/`skcs`, `dbh`, et le handle keybag hors DER. Semi-constants
= `bc`/`kt` (création), `skt`/`skg`/`sko`. **Une requête n'est rejouable octet pour octet que SANS `rk` ni `acmh`**
(ex. `system_key_get_public` avec `skt`/`skg` fixes) — hypothèse, non testée ; toute écriture 0x12 reste « go » d'Albert.

---

## 3. Séquence de bring-up macOS au boot (Q3) — VU (trace c12, chaîné) + DÉDUIT (noms)

Les ~25 premières transactions sks (avant le `> 0x08 0x73` qui réveille sbio) sont **déterministes** : les 13
premières (TAG:longueur) sont identiques sur **6 boots** (c1,c3,c8,c9,c11,c12). Noms = §1.3 (DÉDUIT).

| # (TYPE) | TAG | opération (DÉDUIT) | req/resp | rôle probable |
|---|---|---|---|---|
| 1 | 0x4d | get_capabilities | 0x64/0x5c(flag1) | **négociation en-tête IPC v1/v2** (§1.4) |
| 2 | 0x2a | set_env | 0x470/0x58 | pose l'environnement (pid/cdhash/droits ?) — gros payload |
| 3,4 | 0x22 | perform_operation | 0x8c/0x14c ; 0x90/0xb8 | 1res opérations AKS (DER) |
| 5 | 0x0a | null_d_key | 0x60/—(0xff) | — (data-key ?) |
| 6 | 0x32 | INCONNU | 0x94/0xb4 | — |
| 7,8 | 0x48 | fv_get_blob_state | 0x1dc/0x110 ; 0x230/0x110 | état FileVault (blob) |
| 9 | 0x41 | **déverrouillage volume (mot de passe/clé)** | 0x240/0xa0 | charge/déverrouille un keybag (cf. §4) |
| 10 | 0x48 | fv_get_blob_state | 0x230/0x110 | — |
| 11 | 0x47 | INCONNU | 0x244/0x60 | réponse 0x60 (c12 L : `< TAG 0xc7 DATA 0x00600000`, longueur = DATA>>16) |
| 12,13 | 0x10 | INCONNU | 0xb8/—(fe) ; 0xb8/0xec | — |

Au-delà, l'ordre varie (clients concurrents) ; usage courant = polling `0x19 get_device_state` (resp PARAM 0xfd).
**Quelles transactions chargent le keybag** : DÉDUIT — `0x41` (txn 9, 1,6 s plus tard) est le déverrouillage du
volume (role VU trace+uart, messages.md) ; les `0x48 fv_*` lisent l'état FileVault ; `create_keybag`/`load_keybag`
(ops IPC VU) ne sont **pas** identifiées sur une TAG précise ici (noms non mappés). **D'où vient le keybag** :
en chaîné, il est **sur le volume APFS macOS** (symboles VU `_apfs_keybag_create`,
`_apfs_keybag_set_create_update_record`, `_code_ipc_load_keybag`, `_code_ipc_set_public_backup_keybag`) — c.-à-d.
chargé du disque, pas du xART. **Fait natif critique** (`sks_native_plan.md` §3.4) : en **boot chaîné natif**, sks ne
s'annonce même pas en FD (n=3) → on ne peut pas encore ouvrir 0x12 ; blocage probablement **en amont** (lockers).

---

## 4. Déverrouillage par mot de passe (Q4)

- **Opération fil** : VU (trace+uart, messages.md, `verification_status.md`) — `> 0x12 TAG 0x41` (1re étape, volume,
  keybag -6) puis `> 0x12 TAG 0x18` (2e étape, keybag -501). Côté IPC, candidats symboles `verify_secret` /
  `change_lock_state` / `change_secret` (VU dans la table `_code_ipc_*`) — **mapping TAG↔nom non confirmé** (INCONNU).
- **Le mot de passe passe-t-il en clair au SEP ?** INCONNU au niveau octet (OOL 0x12 jamais capturé). Indices VU :
  symboles `_aks_setPassphrase`/`_aks_getPassphrase`/`_aks_setPassphraseGetUUID`, `_aks_deletePassphrase`, et chaînes
  ACM `ACMCredentialDataPassphraseEntered`/`…Extractable`. Le champ DER `d`/`ad` porterait le secret dérivé ou la
  passphrase. **Protocole uniquement — aucune clé/dérivation extraite, pas cherché.** DÉDUIT : la passphrase (ou un
  dérivé) est fournie **au SEP** dans l'OOL (le SEP détient la logique de déverrouillage) ; l'AP n'a pas la clé.
- **D'où vient le keybag** : fichier sur le volume macOS (APFS container/volume keybag), chargé par `load_keybag`
  (VU symbole) / `set_volume_keybag` (VU en 13.5 §15.7). Pas depuis le xART.
- **Chemin « keybag neuf » pour un OS sans keybag (Linux)** : VU — ops IPC `create_keybag`, `make_system_keybag`,
  `keybag_persona_create` existent (symboles `_code_ipc_create_keybag`, `com.apple.keystore.keybag.create`,
  `_apfs_keybag_create`). **DÉDUIT** : un OS Linux pourrait, en principe, **créer** son propre device/volume keybag
  via `create_keybag` plutôt que charger celui de macOS. Faisabilité réelle, paramètres DER, et conséquences xART :
  **INCONNU** (à instruire ; probable interaction avec le scellement SEP). C'est la piste la moins destructrice pour
  la persistance Linux (ne touche pas au keybag macOS).

---

## 5. Production du jeton pour Touch ID (Q5) — VU (kext+userland) + DÉDUIT

- **Quelle opération produit le jeton** : VU — ops IPC `authentication_token_create` et `authentication_token_verify`
  (symboles `_code_ipc_authentication_token_create/_verify`). Le jeton consommé par **sbio 0x03** (commandStartEnroll)
  est un **AuthToken** (`usingAuthToken=1`) **ou** un **CredentialSet** (`usingAuthToken=0`), 32 o à +0x10 de
  `enroll_indata_v2_t` (VU, `biometrickit_protocol.md` §a/§A).
- **Qui l'appelle** : VU (décisif, `biometrickit_protocol.md` §A.3) — **biometrickitd ne parle PAS à SKS** (aucun lien
  LocalAuthentication/keystore). Le jeton est **produit par le processus client authentifié** (couche
  LocalAuthentication / **ACM** = Access Control Manager), qui tient un `ACMKernContext*` (VU symboles
  `_ACMKernContextCreate`, `…AddCredentialWithScope`, `…VerifyPolicyAndCopyRequirementEx`,
  `ACMCredentialDataPassphraseEntered`). Le lien au keystore se fait par le champ DER **`acmh`** (acm_handle, §2) :
  un `perform_operation` porte le handle du contexte ACM qui **contient un credential passphrase** (saisie de code).
- **Anti-rejeu** : DÉDUIT — l'AuthToken dérive d'une **saisie de code** (chaîne VU
  `BKOptionMatchAuthTokenToBypassPasscodeBiolockout`) et est **vérifié par le SEP** (refus `TAG 0xff` sur jeton nul,
  J6a VU). Un contexte ACM est lié à une session/politique → un jeton capturé est **probablement non rejouable**
  (anti-rejeu via le contexte ACM + état keybag). Détail octet : INCONNU (pas de capture OOL).
- **Chaîne complète** (VU linkage) : client LA/ACM authentifié (code + keybag déverrouillé) → `ACMKernContext`
  (credential passphrase) → `authentication_token_create` (SKS) → AuthToken → dict XPC `BKOptionEnrollWithAuthToken`
  → biometrickitd `parseAuthDict:toAuthData:` → kext `commandStartEnroll` (relais) → **SEP sbio opcode 0x03**.

**Le mur** (synthèse) : produire un jeton 0x03 valide suppose la couche **keybag déverrouillé (code) + ACM**, que la
route native n'a jamais implémentée. Ordre logique pour Linux : ouvrir sks (§1.1) → négocier (§1.4) → déverrouiller le
keybag / en créer un neuf (§4) → créer un AuthToken via ACM (§5) → seulement alors 0x03.

---

## 6. Première expérience matériel la plus prudente (proposition — rien lancé)

Le `get_capabilities` (exp. 2 du plan) exige des **octets d'en-tête non encore confirmés sur 27.2.1** (horodatage,
pid, cdhash, SHA tronqué sur base inconnue ; décompilation halted) → **pas byte-exact aujourd'hui**. La première
expérience doit donc être **plus prudente encore** : l'**ouverture CNTL seule, sans AUCUN mot vers les EP keystore**
= `sks_native_plan.md` §4 **exp. 1 (J7a)**, déjà codée (`pending/j7a_sks_open_chained.sh`, `allow_sks=1`).

**Ce qu'elle envoie (octets exacts, VU trace c12) — uniquement 4 mots CNTL par EP, PARAM = l'EP, dans l'ordre
skdl→sks→scrd, au bon numéro FD et aux bonnes tailles, chacun attendant son ack ; AUCUN mot vers 0x17/0x12/0x0a** :

```
# sks (0x12), tampons DMA natifs (IOVA A, IOVA B = à nous) :
> EP=0x00 TYPE=0x04 PARAM=0x12 DATA=0x00008000     # taille A = 0x8000
> EP=0x00 TYPE=0x02 PARAM=0x12 DATA=0x000000<IOVA_A>>12>   # IOVA A
> EP=0x00 TYPE=0x05 PARAM=0x12 DATA=0x00008000     # taille B = 0x8000
> EP=0x00 TYPE=0x03 PARAM=0x12 DATA=0x000000<IOVA_B>>12>   # IOVA B
# idem pour skdl (0x17) et scrd (0x0a) avec tailles 0x4000 (DATA=0x00004000).
```

**Attendu** : chaque CNTL acquitté `< EP=0x00 TYPE=0x01` (même DATA). Puis **écoute passive** (10 s) : toute
notification SEP spontanée sur 0x17/0x12/0x0a est journalisée, jamais répondue. Tranche : (a) sks s'annonce-t-il en FD
en chaîné si skdl est ouvert tôt (le fait natif §3.4 dit non — c'est précisément ce qu'on teste) ; (b) le SEP
parle-t-il seul sur ces EP (B écrit) ; (c) l'ouverture sans contenu suffit-elle au `0x73` (sbio VIVANT). **Zéro octet
vers un EP keystore** → classe la plus prudente possible.

**Classe** : écriture SEP (ouverture CNTL d'EP keystore) = **classe neuve → « go » d'Albert requis** (1er run) ;
fail-closed ; filet `alarm_p5.img` + DFU ; power-cycle = Albert. (Le `get_capabilities` reste l'exp. suivante, une
fois son en-tête confirmé octet par octet.)
