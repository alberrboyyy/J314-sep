# SKS (EP 0x12) en Linux natif — transport vu, inconnues, expériences graduées

Rédigé le 2026-11-22 (agent driver, session ALARM), depuis les traces macOS c1/c3/c8/c9/c11/c12 (`sep.log`, sans OOL
pour 0x12/0x17/0x0a), `kext_sepmanager.md` §10/§14/§15 (`source: kext`), `messages.md` (lignes 0x12) et les journaux
natifs `logs/20261122-*`. Usages visés : (A) Track B, persistance : sur un boot chaîné, sbio ouvre mais le 0x73 reste
muet (J3d) ; (B) D2 : le SEP a répondu TAG 0xff au 0x03 d'enrôlement (J6a), gating SKS possible.
Notation : **VU** = lu dans une trace, chiffres à l'appui ; **hypothèse** = interprétation ; outils de comptage
reproductibles : `sep-proto/tests/replay.rs` (`j7a_*`, 3 tests verts).

## 1. Transport 0x12 tel que VU

### 1.1 Ouverture (VU c1, c12 ; test `j7a_keystore_cntl_opens_c1_c12`)
- CNTL `> EP 0x00`, PARAM 0x12, TYPE **04** (taille A = 0x8000), **02** (IOVA A >> 12), **05** (taille B = 0x8000),
  **03** (IOVA B >> 12), chacun acquitté `< TYPE 0x01` même TAG. c12 L170-177 (TAG 8, IOVA 0x74000 / 0x80000),
  c1 L163-170. Taille = annonce FD TYPE 1 `0x02010201` (pages [1, 2, 1, 2] → max 2 × 0x4000).
- Même forme pour skdl 0x17 (0x4000/0x4000, c12 L140-147) et scrd 0x0a (0x4000/0x4000, c12 L212-219).
- Ordre macOS (c1 et c12) : **skdl, puis sks, puis scrd**. Rien n'est envoyé à un de ces EP avant son ouverture.
- Aucun SECMODE de plus (un seul, global, avant 0x13).

### 1.2 Mot de requête et de réponse (VU)
- Requête `> EP 0x12 TAG t TYPE n PARAM 0 DATA len << 16` : PARAM = 0 et DATA & 0xffff = 0 sur **579/579** (c1),
  **1955/1955** (c3), **90/90** (c12) requêtes.
- Réponse `< EP 0x12 TAG t | 0x80 TYPE n PARAM s DATA len << 16 | flag` : appariée à la dernière requête de même TYPE,
  avec TAG | 0x80, sur **579/579, 1955/1955, 90/90**. PARAM ≠ 0 (0xfd, 0xfb, 0xff, 0xfe, 0xed) toujours avec DATA = 0
  (c1 : 53 × 0xfd, 5 × 0xfb, 2 × 0xff, 2 × 0xfe, 1 × 0xed). Flag (DATA bit 0) = 1 dans 5 réponses de c1, 28 de c3
  (dont la toute 1re, `cd … 005c0001`).
- Notifications SEP → AP (TAG < 0x80, sans requête) : TAG **0x00** (déverrouillage, DATA = handle), **0x01**
  (verrouillage), **0x09** (TYPE 0 DATA 0, rôle inconnu) ; c1 : (0,0,1)×3, (0,0,0)×2, (0,1,0)×1, (9,0,0)×2 ; c3 en plus
  (1,0,·)×12, (5,1,0)×1 ; c12 : une seule, L707 `TAG 0x00 PARAM 1 DATA 0xbacdd03f`, **après** le 0x73.
  Appariement avec le log noyau macOS « Sending lock change … » : `messages.md` (C8 29/29, C3 34/34).

### 1.3 Résolution de l'incohérence TAG / TYPE
`messages.md` dit « TAG = commande, TYPE = compteur » ; `sks_sequence_c12.md` dit « TYPE = opcode séquentiel ». Les
deux décrivent la même observation (TYPE +1 par requête) ; **la bonne lecture est celle de `messages.md`** :
- **TYPE = compteur de transaction global au boot, modulo 256.** Une fois déroulé (wrap 0xff → 0x00 : 3 fois en c1,
  17 fois en c3), TYPE vaut exactement 1..n : c1 1..579, c3 1..1955, c3a (035422) 1..340, c8 1..1390, c12 1..90 —
  **aucun trou, aucun doublon** ; seuls des échanges locaux d'ordre (≤ 1 en c1/c12, ≤ 3 en c3, ≤ 9 en c8 ; ex. c12
  `01 02 03 05 04 06`) : requêtes concurrentes émises dans le désordre, pas des opcodes sautés. Les « 25 opcodes
  0x01→0x19 » de `sks_sequence_c12.md` §2 sont donc simplement **les 25 premières transactions** (compteur 1 à 25).
- **TAG = opération** : un même TAG revient avec la même longueur de requête : TAG 0x19 = 0x68 (c1 195/195, c3 915/915,
  c12 18/18), 0x04 = 0x6c (45/45, 256/256, 15/15), 0x32 = 0x94 (6/6 ×3), 0x45 = 0x98 (69/69, 170/170). TAG 0x48 et 0x41
  ont 2-5 longueurs (DER de taille variable). c1 : 26 TAG distincts pour 579 requêtes ; c12 : 15 pour 90.
- **La séquence de bring-up est déterministe** : les 13 premières requêtes (TAG:longueur) sont identiques sur **6 boots**
  (c1, c3, c8, c9, c11, c12) : `4d:64 2a:470 22:8c 22:90 0a:60 32:94 48:1dc 48:230 41:240 48:230 47:244 10:b8 10:b8`,
  et les 13 premières réponses aussi (`cd:00:005c0001 aa:00:580000 a2:00:14c0000 a2:00:b80000 8a:ff:0 b2:00:b40000
  c8:00:1100000 c8:00:1100000 c1:00:a00000 c8:00:1100000 c7:00:600000 90:fe:0 90:00:ec0000`). Au-delà, l'ordre varie
  (clients concurrents).
- Lien avec le kext (`kext_sepmanager.md` §15.2, `source: kext`) : l'opération AKS réelle et ses arguments sont dans le
  DER (champ `o`) ; le TAG fil serait posé par la couche endpoint (non décompilée, §15.8-1/3). **Hypothèse** : TAG =
  sélecteur de « commande endpoint » (famille kAppleKeyStore*), DER = paramètres. Correction faite dans
  `sks_sequence_c12.md` §2 (renvoi ici).

### 1.4 Apport de la session PC (décompilation AppleSEPKeyStore 13.5) — `source: kext`, NON vérifié
Reçu de l'orchestrateur le 2026-11-22 ; détail annoncé dans `docs/sks_ipc_negotiation.md` (côté PC, pas encore dans ce
dépôt). Recoupe §1.3 sans en dépendre :
- requête : **TAG = code d'opération IPC** (table de 0x54 opérations) : 0x4d `get_capabilities`, 0x2a `set_env`,
  0x22 `perform_operation`, 0x0a `null_d_key`, 0x48 `fv_get_blob_state`, 0x19 `get_device_state` ; **TYPE = compteur de
  séquence 1 octet démarrant à 1** (pas un opcode : `messages.md` avait raison, `sks_sequence_c12.md` §2 se trompait) ;
  DATA octets 6-7 = longueur de la requête ;
- réponse : TAG = op | 0x80, TYPE = même séquence, PARAM = statut (≠ 0 = échec), DATA = len << 16 | drapeaux (bit 0 =
  « invalider le cache » : le flag 1 de §1.2) ;
- 1er message `get_capabilities` (0x64 o) = en-tête 0x54 (longueur 0x50, version 1, SHA-256 tronqué à 16 o, horodatage
  µs, drapeaux, pid, cdhash) + statut (4 o) + u64 = 1 + blob vide (4 o). En échec, l'AP log « defaulting to v1 » et la
  suite continue.
Accord avec les traces (VU) : 1re transaction de chaque boot = `4d:64 → cd:00:005c0001` (6/6), cohérent avec
get_capabilities + bit « invalider le cache » ; 0x19 (get_device_state, 0x68) = la requête la plus fréquente (poll).
Non vérifié tant qu'aucune expérience ne l'a confirmé. Note : l'en-tête contient horodatage, pid, cdhash → **pas un
blob constant à rejouer** ; il faudra le construire depuis le format (doc PC) — et le SHA-256 tronqué reste à comprendre
(sur quoi est-il calculé ?) avant tout envoi.

## 2. Contenu DER : connu / inconnu

| élément | statut |
|---|---|
| OOL A (requête) / B (réponse) de 0x12 | **jamais capturé** (aucune trace n'a 0x12 dans les EP à OOL ; c13-c16 `live_eps 0x08,0x12` mais `ool=off`) |
| Enveloppe kernel (ref_key handle, constante 3, ptr/len DER, sortie) | `source: kext` §15.2 ; la forme sur le fil (dans l'OOL) n'est pas connue |
| Dictionnaire DER : clés UTF8String courtes (`o`, `rk`, `bc`, `d`, `ad`…, état `ss`, `sls`…) | `source: kext` §15.3 ; enveloppe racine, ordre, types des valeurs : inconnus (§15.8-2) |
| Valeurs de `o` (`oc`, `oe`, `od`, `osgn`…) | `source: kext` §15.4 ; correspondance avec les TAG fil : inconnue |
| Négociation de version d'en-tête IPC avant tout `aks_*` (v1/v2) | `source: kext` §15.5 ; **hypothèse** : c'est la 1re transaction `4d:64 → cd:5c flag 1` (même forme sur 6 boots) |
| Longueurs par transaction | VU (§1.3) |
| Lien des RPC avec le keybag utilisateur (handle -501, volume) | VU (notifs, C8) ; contenu des requêtes 0x41/0x18 (mot de passe) : inconnu, **probablement secret** (dérivé du code) |

Conséquence : aucun RPC sks ne peut être écrit aujourd'hui sans inventer du DER. Ce qui est rejouable un jour : seulement
ce qu'une capture montrerait **constant entre boots** et **non secret** (candidat : la 1re transaction 0x4d `get_capabilities`, à CONSTRUIRE plutôt que rejouer, cf. §1.4).

## 3. skdl (0x17) et scrd (0x0a) — VU exact dans c12

### 3.1 skdl (test `j7a_skdl_scrd_c12`)
| ligne | t (s) | mot |
|---|---|---|
| L112-114 | 711.352 | FD : 0x17 = 'skdl', tailles 0x01010101 |
| L140-147 | 711.398-.404 | CNTL 04/02/05/03 PARAM 0x17 (0x4000, 0x64, 0x4000, 0x6c), 4 acks |
| L149 | 711.414 | `> 0x17 TAG 0xfc TYPE 0x01 PARAM 0 DATA 0` |
| L165-166 | 711.715 | FD : 0x12 = 'sks ' (après les FETCH locker TAG 0x05-0x0b) |
| L167 | 711.717 | `< 0x17 TAG 0xfc TYPE 0x01 PARAM 0 DATA 0` (**303 ms** après la requête, 2 ms après l'annonce sks) |
| L168-169 | 711.718-.719 | `> TYPE 0x06` → `< TYPE 0x06` (1,5 ms), tout DATA 0 |
- c1 : même schéma (L141 → L168 : 267 ms, réponse 1,5 ms après l'annonce FD de sks) ; plus tard `< 0x17 TAG 0x02 DATA
  0xffffffff` (L700), `> 0xfc TYPE 0x03` / `<` (L734/741), `< TAG 0x01 DATA 0x1f` (L1129).
- **OOL : jamais capturé** (aucune trace n'a 0x17 dans `live_eps`). Or TAG 0xfc + DATA 0 est exactement le cadre
  GenericTransfer de sbio, dont l'opcode et la charge sont dans un `gt_packet` en OOL A (`kext_sepmanager.md` §13,
  vérifié pour 0x08). **On ne peut donc pas affirmer que le ping skdl est « sans OOL »** ; il ne sera pas envoyé.
- Coïncidence VU 2/2 (c1, c12) : la réponse au ping 0x01 arrive juste après l'annonce FD de sks. Hypothèse : le SEP
  retient la réponse skdl tant que sks n'est pas prêt (ou l'inverse : le ping débloque la suite).

### 3.2 scrd (66 mots dans c12, tous TAG 0x01, DATA 0)
- Ouverture L212-219 (t = 719.343, **7,6 s après** l'ouverture de sks, après la transaction sks n° 0x0d).
- Requêtes (TYPE) → réponses (TYPE) : 0x08 → 0x00 ; 0x09 → 0x01 ; 0x0c → 0x01, 0x15 ou 0x00 ; 0x17 (PARAM 1) → 0x00 ;
  0x18 → 0x00 ; 0x42 → 0xb0 ; 0x55 → 0xb0. 2e `> 0x08` (L226) sans réponse immédiate ; `< TYPE 0x0f PARAM 1` arrive
  seul 415 ms plus tard (L242).
- OOL : jamais capturé ; DATA = 0 partout (présence d'un OOL inconnue). Sens : inconnu (« credentials », doc Asahi).

### 3.3 Chronologie c12 (boot macOS chaîné) jusqu'au 0x73
0x1d sbio 711.337 → CNTL 0x08 711.371 → CNTL 0x17 711.398 → ping skdl 711.414 → FETCH locker TAG 0x05-0x0b
(711.360-.714, 7 opérations dont un 0x07) → FD sks 711.715 → réponse skdl 711.717 → CNTL 0x12 711.720 → sks n° 1-8
(711.73-.82) → sks n° 9-0x0d (713.36-.48) → CNTL 0x0a 719.343 → scrd + sks n° 0x0e-0x19 + pnon 0x15 → dernier mot
avant le 0x73 = `< 0x12 TAG 0x99 TYPE 0x19 PARAM 0xfd` (737.461) → **`> 0x08 0x73` 737.730** (26,4 s après le CNTL 0x08).

### 3.4 Fait nouveau (relecture des journaux natifs) : sks ne s'annonce PAS en boot chaîné natif
- **Seal frais natif** (J4, J3c, J5, J5b, J5c, J5d, J5e, J6a : n=8) : `découverte : EP 0x12 = 'sks'`, tailles
  0x02010201, après le dernier SAVE (J3c : `kernel.log` L147, après seq 22).
- **Boot chaîné natif** (J3 18:56, J3b 19:04, J3d 19:57 : n=3) : le 0x1d 'sks ' arrive et est acquitté, mais **aucune
  annonce FD de 0x12** dans les ~8 s journalisés après (J3d : table finale de 11 EP sans 'sks'). Le SEP ne demande que
  le locker 407e94c4… deux fois (TAG 0x05/0x06), puis se tait. macOS chaîné (c12) : 7 opérations locker, PUIS FD sks.
- Conséquence : en chaîné natif, **on ne peut même pas ouvrir 0x12** aujourd'hui. Le blocage est peut-être EN AMONT de
  SKS (lockers suivants jamais demandés ; skdl pas ouvert ni pingé avant le 1er FETCH locker, contrairement à c12).
  Statut : VU (n=3 vs n=8) ; cause : hypothèse.

## 4. Expériences graduées (la moins chère d'abord)

| # | expérience | coût / classe | ce qu'elle tranche |
|---|---|---|---|
| 0 | (fait, hors matériel) relecture J3/J3b/J3d vs seal frais | rien | sks non annoncé en chaîné natif (n=3) : §3.4 |
| **1** | **J7a, codée** (`pending/j7a_sks_open_chained.sh`, `allow_sks=1`) : boot chaîné (store servi), CNTL 0x08 précoce (= J3d), puis CNTL **seul** de skdl, sks, scrd dans l'ordre/tailles de c12, chacun seulement annoncé au bon numéro + tailles + 0x1d acquitté (30 s max chacun), écoute passive 10 s, puis 0x73 | écriture SEP, **classe neuve** (ouverture CNTL 0x17/0x12/0x0a) → go d'Albert ; aucun mot aux EP keystore | (a) sks s'annonce-t-il en chaîné si skdl est ouvert tôt et si l'on attend 30 s ? (b) si oui, l'ouverture sans contenu suffit-elle au 0x73 (VIVANT) ? (c) le SEP parle-t-il seul sur 0x17/0x12/0x0a (notifs, B écrit) ? |
| **1b** | **J7b, codée** (`pending/j7b_sks_open_chained_nouuid.sh STORE`, `sepd.j7b --locker-strip-uuid`) : J7a à l'identique, mais chaque locker servi SANS ses 16 o d'UUID (A = B[16..] du SAVE). Motif : J7a (n=4 chaînés, ABSENT et verbatim = même effet) | écriture SEP, **script neuf** (seul le contenu du A FETCH locker change) → go d'Albert ; SAVE possibles (store copié avant) | le SEP demande-t-il le locker suivant (9133c5d5…) puis annonce-t-il sks en FD ? sinon l'emballage n'est pas la cause |
| 2 | **candidate (proposée par la session PC)** : J7a + UNE transaction sks `get_capabilities` (`> 0x12 TAG 0x4d TYPE 0x01 DATA 0x00640000`, OOL A = 0x64 o construits d'après `sks_ipc_negotiation.md`), écoute de la réponse, rien d'autre | classe neuve (écriture 0x12) → go ; prérequis : doc PC reçu, format relu, champs non constants (horodatage, pid, cdhash, SHA tronqué) compris ; aucun secret | le SEP répond-il `cd … 5c flag 1` (négociation v2) ; débloque-t-il quoi que ce soit (FD sks déjà requis : si sks n'est pas annoncé en chaîné, à faire d'abord sur seal frais) |
| 2b | capture macOS (`tools/boot_and_trace.sh`) avec OOL de **0x17, 0x12, 0x0a** (boot seulement, **sans login ni mot de passe**) | lecture pour nous ; mais macOS re-scelle le xART → **le store chaîné Linux devient invalide** (seal frais à refaire) ; l'OOL 0x12 peut contenir du matériel lié aux clés → à traiter comme sensible, décision d'Albert | contenu du ping skdl (gt_packet ? constant ?), contenu réel du get_capabilities (contrôle du doc PC), DER des 13 transactions déterministes, nature de la 1re (négociation IPC ?), présence d'OOL pour scrd |
| 3 | J7b : J7a + ping skdl `0x01` puis `0x06` avec le contenu de l'exp. 2b (seulement s'il est constant sur ≥ 2 boots) | classe neuve (mot vers 0x17) → go | le ping skdl débloque-t-il les FETCH locker suivants / l'annonce de sks en chaîné ? |
| 4 | J7c : transactions suivantes déterministes (`2a` set_env, `22` perform_operation…) | classe neuve (écriture 0x12) → go ; exige le DER (exp. 2b ou doc PC) | jusqu'où va le bring-up sans keybag utilisateur |
| 5 | variante D2 sur seal frais : J6a (pass2 + 0x03) avec 0x12/0x17/0x0a ouverts avant (étendre `allow_sks` au chemin relais) | classe neuve (combinaison) → go | le TAG 0xff du 0x03 dépend-il de l'ouverture SKS (sans contenu) ? |
| 6 | bring-up sks complet (13+ transactions) | impossible sans DER (exp. 2) et sans comprendre le lien keybag/session ; probablement non rejouable tel quel | persistance réelle (Track B) |

Règle (CLAUDE.md) : chaque 1er run = go d'Albert ; fail-closed ; power-cycle par Albert ; filet `alarm_p5.img` + DFU.

## 5. Ce que fait exactement `allow_sks=1` (expérience 1)
Exige `allow_sbio=1 sbio_open=1 allow_sbio_relay=0` (sinon probe refusé). Après l'ouverture précoce de 0x08 :
1. pour skdl, puis sks, puis scrd : attendre (≤ 30 s chacun) FD TYPE 0 au numéro attendu (0x17 / 0x12 / 0x0a) **et**
   FD TYPE 1 = tailles attendues (`01010101` / `02010201` / `01010101`) **et** l'ack de son 0x1d ; annoncé ailleurs ou
   tailles autres → arrêt sans rien envoyer de plus (pas de 0x73) ; pas prêt à temps → « VERDICT <ep> : NON PRÊT »,
   ni lui ni les suivants ne sont ouverts ;
2. 4 CNTL `04/02/05/03` PARAM ep (taille = 0x4000 / 0x8000 / 0x4000, IOVA de tampons DMA dédiés, A jamais écrit),
   chacun attendant son ack (5 s, sinon Halted) ; la porte d'envoi n'admet que ces 4 mots exacts, une fois, pendant
   l'ouverture de cet EP (`sep-proto::ks_gate::OpenGate`) ; **tout mot vers EP 0x17/0x12/0x0a est refusé** ;
3. écoute passive 10 s : chaque mot reçu sur 0x17/0x12/0x0a est journalisé (`keystore < …`, étiquette `ks_gate::classify`),
   jamais répondu, jamais de Halted ; dump de B (0x80 o + octets non nuls) après un nouveau mot (4 par EP) et en fin ;
4. « VERDICT keystore », puis le 0x73 comme J3d (xART calme 2 s) → « VERDICT sbio : VIVANT / MUET » et bilan.
