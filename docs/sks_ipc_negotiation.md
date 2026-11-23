# SKS (EP 0x12) — négociation IPC du premier message (`get_capabilities`, TAG 0x4d)

2026-11-22, agent reverseur (Opus 5.5). **Protocole uniquement, aucune clé ni secret, aucun code Apple copié.**
Tout ce qui suit est `source: kext`. Statut matériel : **rien n'est `vérifié`** (lecture de binaire + recoupement avec
la trace c12, aucune écriture SEP).

> **Re-vérification (2026-11-23, mission PC c9, Opus 4.8)** : les points porteurs de ce document ont été recontrôlés
> indépendamment contre `macos/kernel.macho`. Les symboles résolvent **à l'adresse exacte** citée : `init_sep_endpoint`
> …9950dbc, `__ipc_get_capabilities` …99671c4, `_code_ipc_get_capabilities` …9973eb0, `__payload_hash` …9975a50,
> `sep_deliver_msg` …99453f8 (signature `ipc_callback_ctx_t*,u32,void*` → le « gabarit » est bien un `ipc_callback_ctx_t`),
> `sep_deliver_msg_gated` …994f360, `_get_process_table` …9967ca4, `_msg_header_set_negotiated_version` …9967c90,
> `__ipc_header_size` …9975324. La **table d'opérations** se décode exactement : base `0xfffffe0007004000`, entrées de
> 0x48 o, `entrée[0x4d].code == 0x4d`, `ctxsize == 0x88`, pointeur +0x10 → `_code_ipc_get_capabilities`. Aucune
> divergence. De plus `__payload_hash` et `_gen_ipc_header` (@…99751a0) ont été re-désassemblés (capstone) : le range
> du condensé (§3.3) et le chemin cdhash (§3.2) sont confirmés, et **l'horodatage = `_get_usec_time` (@…995f670) =
> `mach_continuous_time()` ÷ 1000 = µs depuis le boot, horloge MONOTONE (pas un temps epoch)** — précision ajoutée au
> point ouvert §8-1. Intégré dans `docs/sks_protocol.md` §1.3/§1.4/§1.6.

- Binaire : `macos/kernel.macho`, bundle `com.apple.driver.AppleSEPKeyStore`. Chaîne de version lue dans le binaire :
  `Darwin Kernel Version 22.6.0: Wed Jul  5 22:22:05 PDT 2023; root:xnu-8796.141.3~6/RELEASE_ARM64_T6000`
  → **macOS 13.5** (Darwin 22.6.0 / xnu-8796.141.3), noyau T6000 (M1 Pro/Max). Chemins de build
  `BuildRoots/8ca92091-1d5a-11ee-…` (juillet 2023), cohérents.
- Méthode : `ksyms.py` (noms), `kdis.py func/callers` (listings non commités), lecture d'octets de `__const`/`__data`
  par un script jetable du scratchpad. Pointeurs de la table en chained fixups décodés avec la base
  `0xfffffe0007004000` (même technique que pour sbio).
- Trace : `traces/20261108-032454_c12-boot-ho/sep.log` L178-181.
- Légende : **VU** = lu dans le désassemblage (adresse donnée) ; **hyp.** = interprétation.

## 0. Résumé

| Point | Réponse | Statut |
|---|---|---|
| TAG 0x4d | **code d'opération IPC** = `get_capabilities` (index 0x4d de la table des opérations) | VU |
| TYPE 0x01 | **numéro de séquence** u8 de l'AppleKeyStore, vaut 1 au démarrage, +1 par requête | VU |
| PARAM requête | 0 | VU |
| DATA 0x00640000 | octets 6-7 du mot = **longueur de la requête dans l'OOL d'envoi** (0x64) ; octets 4-5 = 0 | VU |
| 0x64 | 0x54 (en-tête IPC) + 4 (mot d'état) + 8 (u64 = 1) + 4 (blob vide) | VU |
| TAG 0xcd | `0x4d | 0x80` ; le kext ne teste **que le bit 7** (c'est une réponse) et que TYPE = séquence envoyée | VU |
| PARAM réponse | **statut signé** ; ≠ 0 → la requête échoue avec ce code, rien n'est décodé | VU |
| DATA 0x005c0001 | `0x005c` = **longueur de la réponse dans l'OOL de réception** ; `0x0001` = **drapeaux d'appel**, bit 0 = « invalider le cache d'état » | VU |
| Valeur extraite | u64 « theirs » = version d'en-tête IPC du SEP ; version retenue = min(theirs, 2) | VU |
| Version négociée sur ce Mac | **v2** probable (tailles des réponses suivantes) | hyp. |
| Message suivant | `set_env` (TAG 0x2a), TYPE 0x02, requête 0x470 o, envoyé **même si la négociation échoue** | VU (+ trace) |

## 1. Qui envoie quoi (chaîne d'appel)

1. `AppleKeyStore::init_sep_endpoint()` (`0x9950dbc`) — VU :
   - copie un gabarit de 0x18 o lu à `0x74a1f30` sur la pile, puis ajoute un u64 nul juste après (champ de sortie) ;
   - appelle `__ipc_get_capabilities(fn=[this+0x148], gabarit, 1, NULL, 0, &theirs, NULL, NULL)` (`0x9950e1c`).
     `[this+0x148]` est rempli par `AppleKeyStore::start` (`0x9945118`) avec `AppleKeyStore::sep_deliver_msg`
     (`0x99453f8`).
2. Gabarit `0x74a1f30` (octets lus, VU) : `00×8 | 00×8 | 01 00 00 00 00 00 00 00`. Rôle des champs, lu dans les
   fonctions qui les consomment (VU) :
   - `+0x08` (u64) = objet commande préalloué facultatif (`sep_deliver_msg_gated` lit `[gabarit+8]`, `0x994f44c`) ; ici 0
     → pris dans le pool ;
   - `+0x10` (u32) = **version d'en-tête IPC imposée** (`__ipc_get_capabilities` lit `[gabarit+0x10]`, `0x9967248`) ; si 0,
     c'est la version globale négociée `_msg_negotiated_header_version` (`0xb881448`, valeur initiale **1** dans `__data`).
     Ici **1** : la requête de négociation part toujours en en-tête v1.
3. `__ipc_get_capabilities` (`0x99671c4`) — VU : construit un contexte de 0x88 o (taille confirmée par l'entrée 0x4d
   de la table), appelle `_gen_ipc_header(version)` puis `fn(gabarit, 0x4d, ctx)` (`mov w1,#0x4d`, `0x99672a0`).
   Champs du contexte : `+0x50` u32 état = 0, `+0x58` u64 = 1 (3e argument), `+0x60/+0x68` blob envoyé = (NULL, 0),
   `+0x70` u64 « theirs » (sortie), `+0x78/+0x80` blob reçu (sortie ; ici jeté et effacé car l'appelant passe NULL).
4. `sep_deliver_msg` (`0x99453f8`) — VU : **chemin d'ENVOI** (et non de réception, à corriger dans
   `kext_sepmanager.md` §15.1) : exécute `sep_deliver_msg_gated(gabarit, code, ctx)` sous la command gate
   (`[this+0x81b8]`, méthode +0x1e8).
5. `sep_deliver_msg_gated` (`0x994f360`) — VU : séquence, encodage, envoi du mot, attente, décodage (sections 2-4).

## 2. Table des opérations (TAG fil = code IPC) — VU

`_get_process_table(code)` (`0x9967ca4`) : table à `0x7dbda70`, entrées de 0x48 o, `code < 0x54` sinon NULL.
Entrée : `+0x00` u32 code, `+0x04` u32 taille du contexte, `+0x08` u64 (petit entier 0-3, sens non lu), `+0x10`
pointeur du codeur `_code_ipc_*`, `+0x44` u32 drapeaux (bit 0 lu par `gated`, sens non lu — sert au moins au traçage).
Le TAG du mot est `code & 0x7f` (`0x994fa18`). Table complète décodée :

| TAG | opération | TAG | opération | TAG | opération |
|---|---|---|---|---|---|
| 0x00 | hello | 0x1c | authentication_token_create | 0x38 | smartcard_unlock |
| 0x01 | create_keybag | 0x1d | authentication_token_verify | 0x39 | get_s_key |
| 0x02 | copy_keybag | 0x1e | recover_with_escrow_bag | 0x3a | set_s_key |
| 0x03 | load_keybag | 0x1f | backup_pfk_data | 0x3b | migrate_s_key |
| 0x04 | change_lock_state | 0x20 | fdr_hmac_data | 0x3c | invalidate_sync_bags |
| 0x05 | unload_keybag | 0x21 | verify_secret | 0x3d | copy_volume_cookie |
| 0x06 | copy_keybag_uuid | 0x22 | perform_operation | 0x3e | absinthe_collection |
| 0x07 | change_secret | 0x23 | get_configuration | 0x3f | absinthe_generate |
| 0x08 | kc_wrap | 0x24 | set_configuration | 0x40 | fv_new_vek |
| 0x09 | unwrap_pfk_data | 0x25 | remote_session_operate | 0x41 | fv_unwrap_vek |
| 0x0a | null_d_key | 0x26 | remote_session | 0x42 | fv_new_kek |
| 0x0b | create_d_key | 0x27 | create_signing_key | 0x43 | fv_rewrap_kek |
| 0x0c | unwrap_d_key | 0x28 | sign_remote_signing_key | 0x44 | fv_get_size |
| 0x0d | make_system_keybag | 0x29 | escrow_stash_enable | 0x45 | kc_unwrap |
| 0x0e | set_public_backup_keybag | 0x2a | **set_env** | 0x46 | drop_auxiliary_auth |
| 0x0f | rewrap_pfk_data | 0x2b | escrow_stash_persist | 0x47 | fv_set_protection |
| 0x10 | new_pfk_data | 0x2c | escrow_keys_unlock | 0x48 | fv_get_blob_state |
| 0x11 | make_public_backup_bag | 0x2d | public_backup_handle_for_handle | 0x49 | invalidate_keybag |
| 0x12 | escrow_keys_create | 0x2e | unload_public_backup_keybag | 0x4a | keybag_persona_create |
| 0x13 | escrow_stash_create | 0x2f | handle_timer_fire | 0x4b | keybag_persona_delete |
| 0x14 | escrow_stash_load | 0x30 | unload_session_keybags | 0x4c | keybag_persona_list |
| 0x15 | escrow_stash_commit | 0x31 | new_media_key | **0x4d** | **get_capabilities** |
| 0x16 | escrow_stash_destroy | 0x32 | unwrap_media_key | 0x4e | fv_new_sibling_vek |
| 0x17 | drain_backup_keys | 0x33 | remote_peer_get_state | 0x4f | fairplay_operation |
| 0x18 | device_state_transition | 0x34 | remote_peer_drop | 0x50 | volume_backup_operation |
| 0x19 | get_device_state | 0x35 | smartcard_register | 0x51 | identity_operation |
| 0x1a | generic_operation | 0x36 | smartcard_unregister | 0x52 | identity_migrate_handle0 |
| 0x1b | client_terminate | 0x37 | smartcard_request_unlock | 0x53 | last_user_operation |

Conséquence : le **TAG** des messages 0x12 de nos traces **est l'opération** (0x2a set_env, 0x22 perform_operation,
0x0a null_d_key, 0x32 unwrap_media_key, 0x48 fv_get_blob_state, 0x19 get_device_state…) et le **TYPE** n'est qu'un
compteur. Ceci corrige `sks_sequence_c12.md` §2 (« TYPE = opcode séquentiel ») et lève le point ouvert §15.8-3 de
`kext_sepmanager.md`.

## 3. Message sortant `> EP=0x12 TAG=0x4d TYPE=0x01 PARAM=0x00 DATA=0x00640000`

### 3.1 Mot mailbox (8 o construits dans `sep_deliver_msg_gated`, `0x994fa18`-`0x994fa2c`) — VU

| octet | champ | valeur | origine |
|---|---|---|---|
| 0 | endpoint | 0 dans le kext | mis à zéro (`stur xzr`) ; rempli par la classe `AppleSEPEndpoint` (hors kext) — hyp. |
| 1 | TAG | `code & 0x7f` = 0x4d | `and w8,w25,#0x7f` ; `sturb w8,[fp-0x5f]` |
| 2 | TYPE | séquence = 0x01 | `OSIncrementAtomic8(this+0x188)` (`0x994f400`) rend l'**ancienne** valeur ; le constructeur `AppleKeyStore::AppleKeyStore` met `this+0x188 = 1` (`0x9944614`). u8 : repasse à 0 après 0xff. |
| 3 | PARAM | 0 | jamais écrit |
| 4-5 | DATA[15:0] | 0 | jamais écrit |
| 6-7 | DATA[31:16] | 0x0064 | `sturh` de la longueur rendue par le codeur (`0x994fa2c`) |

Envoi : méthode +0x1e8 de l'objet endpoint, arguments (mot, 0, 1) (`0x994fa74`). Code retour ≠ 0 → échec (section 5).

### 3.2 Charge dans l'OOL d'envoi (0x64 o) — VU

Le codeur (`_code_ipc_get_capabilities`, `0x9973eb0`, mode encodage `w0=1`) écrit dans le tampon du descripteur
`[this+0x168]` (OOL d'envoi ; hyp. : c'est notre tampon A, AP→SEP). Primitives (VU) : `__word` = u32 LE (+4),
`__lword` = u64 LE (+8), `__blob` = u32 longueur + données alignées sur 4, `__ipc_header` = u32 longueur (**toujours
0x50 à l'encodage**) + 0x50 o d'en-tête, `__ipc_header_size` = 0x54.

| offset | taille | champ | valeur pour ce message |
|---|---|---|---|
| 0x00 | 4 | longueur de l'en-tête | 0x50 |
| 0x04 | 16 | condensé d'intégrité (3.3) | calculé |
| 0x14 | 4 | version d'en-tête | 1 |
| 0x18 | 8 | horodatage µs (`_get_usec_time`) | variable |
| 0x20 | 4 | drapeaux (bit 0 = chiffré, bit 1 = en-tête étendu présent) | 0 |
| 0x24 | 8 | champ ctx+0x20 | 0 (non écrit sur ce chemin) |
| 0x2c | 8 | `proc_uniqueid(proc_self())` | processus appelant (ici le noyau — hyp.) |
| 0x34 | 4 | champ de la cred du processus (`[cred+0x80]+0x24`) | hyp. : identifiant utilisateur |
| 0x38 | 20 | cdhash du processus (`cs_get_cdhash`), zéros s'il n'y en a pas ; si pas de processus : SHA-1 des 8 o de 0x2c | variable |
| 0x4c | 8 | ctx+0x48..0x4f | 0 (couvert par le condensé seulement en v2) |
| 0x54 | 4 | mot d'état | 0 |
| 0x58 | 8 | u64 | **1** (3e argument d'`__ipc_get_capabilities`, constant aux 2 appels : `init_sep_endpoint` et `tdm_negotiate_msg_capabilities`) |
| 0x60 | 4 | longueur du blob | 0 (aucune donnée) |

Total 0x64 = la valeur de DATA. Sens du u64 = 1 : **hyp.** (plus petite version acceptée par l'AP, ou sélecteur
« capacité = version d'en-tête ») ; ce n'est pas la version maximale de l'AP, qui est 2 (voir 4.3).

En-tête étendu (`__ipc_msg_process_extended_header`, VU) : seulement si version ≥ 2 ; à l'encodage le bit 1 des
drapeaux est effacé et rien n'est écrit. Au décodage, si le bit 1 est posé, un blob est lu (journaux « invalid charging »,
« invalid soc » : état batterie) — sans objet pour la requête de négociation (v1).

### 3.3 Condensé d'intégrité (`__payload_hash`, `0x9975a50`) — VU

SHA-256 (`ccsha256_di`), **sans clé**, tronqué à 16 o, sur, dans cet ordre : version (4) ‖ horodatage (8) ‖ drapeaux (4)
‖ champ +0x20 (8) ‖ bloc processus (0x20 o en v1 = ctx+0x28..0x47 ; 0x28 o en v2 = ctx+0x28..0x4f) ‖ charge (tout
ce qui suit l'en-tête). Encodage : écrit à ctx+0x00 puis copié à l'offset 0x04. Décodage : recalcul et comparaison sur
16 o, échec → `ipc digest failed`. Version ≠ 1 et ≠ 2 → `unexpected version %d` (code -0xf).
C'est un contrôle d'intégrité du cadre, pas un secret. Si le drapeau « chiffré » (bit 0) est posé, le chemin du kext
finit en erreur (-0xd) : ce mode n'est pas utilisé ici (VU `0x997597c`).

## 4. Réponse `< EP=0x12 TAG=0xcd TYPE=0x01 PARAM=0x00 DATA=0x005c0001`

### 4.1 Réception et appariement — VU

- `sep_action` (`0x9950bd0`, callback posé par `sep_endpoint` avec la case `this+0x180`) : si l'octet TAG a le **bit 7**,
  le mot entier est copié dans `this+0x180` puis la gate est réveillée (méthode +0x208). Sinon c'est une notification :
  TAG 3 → `notify_keys_available(DATA u32, TYPE)`, TAG 7 → `notify_se_recovery`, autre → `event_enqueue`.
- `sep_deliver_msg_gated` attend (`commandSleep`, échéance = `getAdjustedTimeout(6000)` ms, donc 6 s × multiplicateur
  SEP) puis accepte la case si `TAG` (octet 0x181) a le bit 7 **et** `TYPE` (0x182) = la séquence envoyée
  (`0x994fd7c`-`0x994fd90`). **Les 7 bits bas du TAG ne sont pas comparés** : 0xcd = 0x4d | 0x80 est la convention SEP,
  pas un contrôle du kext.

### 4.2 Champs du mot — VU

| octet | lu comme | valeur | traitement |
|---|---|---|---|
| 3 | PARAM, **int8 signé** (`ldrsb`, `0x994fd9c`) | 0 | ≠ 0 → pas de décodage, la requête rend ce code (ex. 0xff → -1) |
| 4-5 | u16 « drapeaux d'appel » (`0x994fd98`) | 0x0001 | `_msg_process_ipc_call_flags` (`0x9975330`) : bit 0 → met à zéro l'indicateur global « cache d'état valide » (`0xb8815fc`) et journalise `invalidated cache (sync)` |
| 6-7 | u16 longueur de réponse (`0x994fd94`) | 0x005c | doit être ≤ longueur du descripteur de réception `[this+0x170]`, sinon échec |

Le bit 0 des drapeaux est traité **avant** le test de PARAM, donc aussi pour une réponse en erreur (VU, `0x994fe5c`).
Sens exact du cache : celui de l'état device (`kext_msg_cache_device_state`) — hyp. raisonnable d'après les noms.

### 4.3 Charge reçue (0x5c o dans l'OOL de réception ; hyp. : notre tampon B) — VU pour l'algorithme

Décodage par le même codeur (`w0=0`) :
1. en-tête : u32 longueur L, copie de min(L, 0x50) o dans le contexte, avance de 4 + L arrondi à 4 ;
2. condensé vérifié (3.3), selon la version **lue dans l'en-tête du SEP** ;
3. en-tête étendu si version ≥ 2 et drapeau bit 1 ;
4. u32 état : **doit être 0**, sinon échec ;
5. u64 « theirs » → ctx+0x70 ; blob → ctx+0x78/+0x80 (alloué si non vide, puis effacé et libéré par l'appelant) ;
6. **les octets consommés doivent égaler exactement la longueur annoncée**, sinon échec.

Disposition attendue pour 0x5c (**hyp.**, déduite des tailles) : L = **0x48** (en-tête v1 : condensé + version +
horodatage + drapeaux + champ 0x20 + bloc processus de 0x20 o, soit exactement la zone couverte par le condensé v1) ;
0x4c état ; 0x50 u64 theirs ; 0x58 longueur de blob = 0. 0x4c + 4 + 8 + 4 = 0x5c. Avec L = 0x50, le minimum serait 0x64 :
impossible. Le SEP renvoie donc un en-tête plus court que l'AP (l'AP écrit toujours L = 0x50).

### 4.4 Ce qui est fait de « theirs » — VU

`init_sep_endpoint` (`0x9950ea0`-`0x9950eb0`) : si l'appel rend 0, `négociée = theirs < 2 ? theirs : 2`, stockée par
`_msg_header_set_negotiated_version` dans `_msg_negotiated_header_version` (`0xb881448`), et journal
`negotiated to ipc header theirs:v%llu, ours:v%u -> negotiated:v%llu` avec **ours = 2** (constante). Cette version sert
d'en-tête à **toutes** les requêtes suivantes dont le gabarit est NULL ou a `+0x10 = 0` (ex. `__ipc_set_env`,
`0x9963f2c`-`0x9963f38`). Ce n'est **pas** une taille de tampon partagé (les tailles OOL viennent du CNTL : A = B =
0x8000, trace L170-176).

Version effectivement négociée sur ce Mac : **v2 probable (hyp.)**. Raisonnement : la réponse à `set_env` ne contient
que l'en-tête + le u32 d'état (branche de décodage de `_code_ipc_set_env`, `0x996ed3c`-`0x996ed80`, VU) ; sa longueur
est 0x58 (trace L181) → en-tête de 0x54 → L = 0x50 = en-tête v2. La réponse de négociation, elle, a un en-tête v1
(L = 0x48) parce que la requête était v1. Donc le SEP a répondu theirs ≥ 2. Non confirmé par le contenu (OOL 0x12 non
capturé).

## 5. Conditions d'échec — VU

Dans `sep_deliver_msg_gated` (code rendu à `__ipc_get_capabilities` puis à `init_sep_endpoint`) :

| cas | adresse | code |
|---|---|---|
| pas d'endpoint SKS (`no sks endpoint to send to`) | `0x9950324`, `0x99503a0` | 0xe00002bc / 0xe00002d8 |
| arrêt en cours, endpoint désactivé (`we're on our way down…`) | `0x9950080` | 0xe00002d8 |
| code ≥ 0x54 (pas d'entrée de table) | `0x99503c8` | 0xe00002bc |
| encodage négatif | `0x99503c4` | 0xe00002bc |
| erreur de l'envoi du mot (méthode +0x1e8) | `0x994fac0` | code de l'endpoint |
| délai : 6 s × multiplicateur par tentative, `sks timeout strike %d`, relève manuelle possible (`manually picked up response`) ; **20 tentatives** → `sks request timeout` (arrêt) | `0x994fc6c`, `0x995040c` | — |
| PARAM ≠ 0 | `0x994fe9c` | PARAM signé |
| longueur de réponse > tampon de réception | `0x99503d4` | 0xe00002bc |
| décodage en échec (état ≠ 0, condensé faux, version inconnue, taille non exacte) | `0x99503e0` | 0xe00002bc |

Dans `init_sep_endpoint` : **tout** code ≠ 0 → `failed to negotiate, defaulting to v1`, version globale = 1. Les deux
branches se rejoignent ensuite (`0x9950f38`) : la suite est la même.

## 6. Message suivant

VU (`0x9950f40`-`0x9950f4c`) : après le journal, `AppleKeyStore::set_env(false)` puis
`AppleKeyStore::add_class_f_entropy_to_kernel_prng()`. `set_env` (`0x9954248`) appelle `__ipc_set_env` (TAG **0x2a**)
avec un gabarit NULL (donc la version négociée) et un blob de **0x40c o** : `+0x00` u32 = 1, `+0x04` u32 =
propriété `cpx-encryption-mode` de `IODeviceTree:/defaults` (0 si absente), `+0x08` u32 = 4 (6 si l'argument est vrai ;
ici 4), reste à zéro. Sens des champs : non lu (hyp. : environnement/mode de protection de contenu).
Requête attendue : 0x54 + 4 + 8 + 4 + 0x40c = **0x470** ; trace L180 : `> TAG=0x2a TYPE=0x02 DATA=0x04700000`,
réponse L181 `< TAG=0xaa TYPE=0x02 PARAM=0x00 DATA=0x00580000` → **recoupe** (`source: kext` + trace).
Le message suivant de la trace (TAG 0x22 perform_operation, TYPE 0x03) vient probablement de
`add_class_f_entropy_to_kernel_prng` : **hyp.**, non lu.

## 7. Pour un driver Linux (dérivé de ce document, rien de `vérifié`)

Pour reproduire le 1er échange il faudrait : mot `TAG=0x4d, TYPE=seq, PARAM=0, DATA=len<<16` ; OOL d'envoi
= en-tête de 0x54 o (L = 0x50, version 1, horodatage, champs processus) + état 0 + u64 1 + blob vide, avec le condensé
SHA-256/16 correct ; lire la réponse dans l'OOL de réception, vérifier le condensé, état = 0, puis prendre min(theirs, 2).
**Écriture vers l'EP 0x12 = classe jamais testée → script `pending/` + « go » d'Albert.**

## 8. Points ouverts

1. Le SEP **vérifie-t-il** le condensé et les champs processus (uniqueid, cdhash) de la requête ? Non observable dans le
   kext. Valeurs à mettre côté Linux (zéros ?) : inconnu.
2. Sens du u64 = 1 de la requête ; valeur exacte de « theirs » (OOL non capturé : le tracer n'a pas 0x12 dans
   `full_types`). Une trace avec le contenu des OOL 0x12 trancherait (lecture seule).
3. Disposition exacte de l'en-tête SEP de 0x48 o : déduite des tailles, non lue.
4. Champ `+0x08` des entrées de table (0-3) et drapeau `+0x44` : sens non lu.
5. Octet 0 du mot (endpoint) et éventuelle retouche du mot par `AppleSEPEndpoint` (hors de ce kext) : non relus ici.
6. Une seule case de réponse (`this+0x180`) alors que la trace montre des requêtes entrelacées (TYPE 5 avant 4) :
   mécanisme de concurrence non étudié.
