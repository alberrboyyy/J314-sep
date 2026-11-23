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
| **2** | **J9a, codée** (§6, `pending/j9a_sks_getcap_chained.sh STORE`, `allow_sks=2`) — à l'origine candidate de la session PC : J7a + UNE transaction sks `get_capabilities` (`> 0x12 TAG 0x4d TYPE 0x01 DATA 0x00640000`, OOL A = 0x64 o construits d'après `sks_ipc_negotiation.md`), écoute de la réponse, rien d'autre | classe neuve (écriture 0x12) → go ; prérequis : doc PC reçu, format relu, champs non constants (horodatage, pid, cdhash, SHA tronqué) compris ; aucun secret | le SEP répond-il `cd … 5c flag 1` (négociation v2) ; débloque-t-il quoi que ce soit (FD sks déjà requis : si sks n'est pas annoncé en chaîné, à faire d'abord sur seal frais) |
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

## 6. Expérience 2 codée : J9a = UN `get_capabilities` sur boot chaîné (`allow_sks=2`) — 2026-11-23, rien lancé

Sources : `sks_protocol.md` §1.6 et `sks_ipc_negotiation.md` §3-§4 (`source: kext` 13.5, **non vérifié matériel**),
trace c12 L178-179 (`> 0x12 TAG 0x4d TYPE 0x01 PARAM 0 DATA 0x00640000` → `< TAG 0xcd TYPE 0x01 PARAM 0 DATA
0x005c0001`, 1,25 ms), J7b n=2 (skdl/sks/scrd ouverts, 0 mot reçu en 10 s). Rien de ce qui suit n'est `vérifié`.

**Chemin** = J7b (boot chaîné, lockers sans UUID, CNTL de skdl/sks/scrd) puis, si les TROIS sont ouverts :
1. le noyau attend ≤ 20 s la requête sur `/dev/sep_sks` (créé au probe ; EAGAIN avant le bon moment, EALREADY après) ;
2. porte noyau `sep-proto::sks_ipc::check_getcap` sur les 0x64 o : longueur exacte ; constantes 0x50 @0x00, 1 @0x14,
   0 @0x20, 0 @0x24 (u64), 0 @0x4c (u64), 0 @0x54, 1 @0x58 (u64), 0 @0x60 ; **condensé recalculé dans le noyau**
   (SHA-256 sans clé, `sep-proto::hash`, sans allocation) ; cdhash = zéros OU SHA-1 des 8 o de l'uniqueid (les deux
   formes documentées côté AP ; toute autre valeur refusée). Refus = EINVAL, rien envoyé, pas de Halted ;
3. copie dans A12, relue ; UN mot `> 0x12 TAG 0x4d TYPE 0x01 PARAM 0 DATA 0x00640000` (porte `GetcapGate` : ce mot
   exact, une fois par boot ; tout autre mot vers 0x12/0x17/0x0a reste refusé) ;
4. écoute 10 s : la 1re réponse appariée comme le kext (TAG bit 7, TYPE 0x01 ; les 7 bits bas du TAG ne sont pas
   comparés, journalisés seulement) → instantané de B12 (0x80 o) ; jamais de réponse du pilote ;
5. « VERDICT sks getcap : RÉPONDU (PARAM 0, état 0, theirs …) » / « ERREUR » (PARAM ≠ 0, état ≠ 0 ou B12 non
   décodable) / « SILENCE » / « NON ENVOYÉ » ; `read` de `/dev/sep_sks` rend le même résultat (enregistrement
   `SKG1`, 0x98 o) ; puis le 0x73 sbio comme J7b.
Écart volontaire avec macOS (c12) : macOS envoie le get_capabilities juste après le CNTL de sks, **avant** d'ouvrir
scrd (7,6 s plus tard) ; J9a l'envoie après les trois ouvertures (chemin J7b inchangé, seule l'étape 0x12 est ajoutée).

**Valeurs des champs contextuels** (`sks_getcap`, choix documentés, rien de vérifié) :
| champ | valeur | justification |
|---|---|---|
| horodatage 0x18 | CLOCK_MONOTONIC en µs (au moment de l'écriture ; `--clock`, `--ts-us`) | l'horloge de `_get_usec_time` **n'est pas documentée** (INCONNU) ; monotone = analogue Linux le plus proche d'une horloge depuis le boot. La porte noyau ne la contrôle pas |
| uniqueid 0x2c | 0 | sous macOS la requête vient du noyau lui-même (`init_sep_endpoint`), pas d'un processus utilisateur : valeur neutre |
| uid 0x34 | 0 | idem (identifiant d'utilisateur DÉDUIT, 0 = root) |
| cdhash 0x38 | SHA-1(8 × 0x00) = `05fe4057…07c7e9` (`--cdhash zero` = zéros) | chemin AP « pas de processus » (§1.6.2 « à défaut ») ; l'autre chemin documenté (processus sans cdhash) = zéros. Lequel macOS prend pour un appel noyau : INCONNU (les deux documents diffèrent légèrement) |
| condensé 0x04 | SHA-256(octets 0x14..0x4c ‖ 0x54..0x64)[0..16] | base de §1.6.3 : version ‖ horodatage ‖ drapeaux ‖ champ +0x20 ‖ bloc processus (0x20 o, v1) ‖ charge ; les 8 o à 0x4c ne sont couverts qu'en v2 |

**Décodage de la réponse** (`sks_ipc::decode_getcap_reply`, noyau et outil) : u32 L ; version lue à 0x14 (1 ou 2, sinon
erreur) ; état à 4 + L arrondi, theirs (u64) ensuite, longueur de blob ; octets consommés = longueur annoncée ; condensé
recalculé selon la version lue (rapporté OK/FAUX). Disposition L = 0x48 pour 0x5c : **DÉDUITE** (§1.6.4).

**Tests hors matériel** : `sep-proto` (hash : vecteurs FIPS SHA-256/SHA-1 + flux découpé ; `sks_ipc` : disposition,
base du condensé reconstruite champ par champ, porte qui refuse chaque constante modifiée / condensé faux / cdhash
étranger, mot c12 L178, décodage réponse, porte un seul mot) ; `sks-getcap/tests/getcap.rs` : requête identique octet
pour octet à une construction Python/`hashlib` indépendante faite depuis la doc, relue par la porte, verdicts.

**Binaires** (`~/kbuild/j9`, compilés contre `~/kbuild/src/linux-asahi-7.2.12-3`, vermagic `7.2.12-3-1-ARCH`, build
reproductible) : `sep_native.ko` `145804d0b31871b0d5c6b266dce464770bb8467d9631384ed362ef5cb796f334`, `sks_getcap`
`c25a6193938b308dfafdde6e2f74382d1a7d1336aed83e68b247cc39ad0715c9` ; `sepd`, `sep_native_ovl.ko`, `sep-native.dtbo`
= copies de `~/kbuild/j5` (sha256 inchangés).

**Avant le run** : service désactivé (`/etc/sep-touchid/disabled` + reboot) ; STORE = copie chaînée
(`/var/lib/sepd-run-20261122-230441`, identique à `/var/lib/sepd` le 2026-11-23), jamais `/var/lib/sepd`. **Après** :
si 0 SAVE, `rm /etc/sep-touchid/disabled` + reboot ; sinon le store du service est périmé → décision d'Albert.
Classe neuve (écriture EP 0x12) → **1er run = « go » d'Albert**.


## 7. Expérience 3 codée : J9b = UN `set_env` après le `get_capabilities` (`allow_sks=3`) — 2026-11-23, rien lancé

Sources : `sks_protocol.md` §1.7 (set_env octet par octet, en-tête v2, `source: kext` 13.5, **non vérifié matériel**),
trace c12 L180-181 (`> 0x12 TAG 0x2a TYPE 0x02 PARAM 0 DATA 0x04700000` → `< TAG 0xaa TYPE 0x02 PARAM 0 DATA
0x00580000`, 1,1 ms), J9a (get_capabilities accepté, **theirs = 2** → v2 confirmée matériel). Rien de ce qui suit
n'est `vérifié`.

**Chemin** = J9a (boot chaîné, lockers sans UUID, CNTL de skdl/sks/scrd, UN get_capabilities) puis, **seulement si le
get_capabilities a RÉPONDU (état 0) et négocié la v2** :
1. le noyau attend ≤ 20 s la 2e requête sur `/dev/sep_sks` (2e écriture, 0x470 o ; EAGAIN tant que la réponse du
   get_capabilities n'est pas arrivée, EALREADY après) ;
2. porte noyau `sep-proto::sks_setenv::check_setenv` sur les 0x470 o : longueur exacte ; constantes d'en-tête (0x50
   @0x00, **2** @0x14, 0 @0x20, 0 @0x24, 0 @0x4c, 0 @0x54 état, 1 @0x58 u64, 0x40c @0x60 blob) ; constantes de blob
   (version de structure 1 @0x64, mode 4 @0x6c, **0x400 o réservés nuls** @0x70) ; **condensé v2 recalculé dans le
   noyau** (SHA-256/16, base §1.6.3 avec bloc processus 0x28 → en-tête complet 0x14..0x54 + charge, `sep-proto::hash`,
   sans allocation) ; cdhash = zéros OU SHA-1 des 8 o de l'uniqueid. **Seul `cpx-encryption-mode` (@0x68) est
   contextuel** (non contraint). Refus = EINVAL, rien envoyé, pas de Halted ;
3. copie dans A12, relue ; UN mot `> 0x12 TAG 0x2a TYPE 0x02 PARAM 0 DATA 0x04700000` (porte `SetenvGate` : ce mot
   exact, une fois par boot ; tout autre mot vers 0x12/0x17/0x0a reste refusé) ;
4. écoute : la 1re réponse appariée comme le kext (TAG bit 7, TYPE **0x02**) → instantané de B12 (0x80 o) ; jamais de
   réponse du pilote ;
5. « VERDICT sks setenv : ACCEPTÉ (PARAM 0, état 0 ; L 0x50, version d'en-tête 2 …) » / « ERREUR » (PARAM ≠ 0, état ≠ 0
   ou B12 non décodable) / « SILENCE » / « NON ENVOYÉ » ; `read` de `/dev/sep_sks` rend l'enregistrement
   get_capabilities **suivi** de l'enregistrement set_env (2 × 0x98 o) ; puis le 0x73 sbio comme J9a.

**`cpx-encryption-mode`** : le kext le lit dans `IODeviceTree:/defaults` (0 si absent). `sks_setenv run` lit
`/proc/device-tree/defaults/cpx-encryption-mode` (cellule u32 big-endian) à l'exécution, 0 si absent, `--cpx N` pour
forcer. L'arbre Asahi n'exporte **pas** `/defaults` → la lecture auto tombe sur 0 ; notre ADT
(`traces/20261108-162919_adt/adt.txt`) donne **2**, donc le script de run force `--cpx 2`.

**Décodage de la réponse** (`sks_setenv::decode_setenv_reply`, noyau et outil) : u32 L ; version lue à 0x14 ; état à
4 + L arrondi ; **octets consommés = longueur annoncée (0x58, sans u64 ni blob)** ; condensé recalculé selon la version
lue (OK/FAUX). Diffère de get_capabilities (dont la réponse porte theirs + blob).

**Tests hors matériel** : `sep-proto::sks_setenv` (disposition, base du condensé v2 reconstruite champ par champ, porte
qui refuse chaque constante modifiée / zone réservée non nulle / condensé faux / cdhash étranger, mot c12 L180, décodage
réponse 0x58, porte un seul mot) ; `sks-setenv/tests/setenv.rs` : requête identique octet pour octet à une construction
Python/`hashlib` indépendante (en-tête 0x70 + 0x400 o nuls, sha256 complet), relue par la porte, enregistrement
combiné getcap+setenv décodé.

**Binaires** (`~/kbuild/j10`, compilés contre `~/kbuild/src/linux-asahi-7.2.12-3`, vermagic `7.2.12-3-1-ARCH`) :
`sep_native.ko` `59bd81ff953182ab90c04c77f75774308cb4d0bc0bf572d9bbd01a8369aa07f3`, `sks_setenv`
`2e3cbf9f54c281d7f300ce2939f04f5bc0d7805acb3fee4fd27149224e6f439f` ; `sepd`, `sep_native_ovl.ko`, `sep-native.dtbo`
= copies de `~/kbuild/j9`/`j5` (sha256 inchangés).

**Avant le run** : service désactivé (`/etc/sep-touchid/disabled` + reboot) ; STORE = copie chaînée
(`/var/lib/sepd-run-20261122-230441`), jamais `/var/lib/sepd`. **Après** : si 0 SAVE, `rm /etc/sep-touchid/disabled` +
reboot ; sinon le store du service est périmé → décision d'Albert. Classe neuve (2e type de message EP 0x12) →
**1er run = « go » d'Albert** (`pending/j9b_sks_setenv_chained.sh`).

## 8. Expérience 4 codée : J9c = UN `null_d_key` en SAUTANT les deux `perform_operation` (`allow_sks=4`) — 2026-11-23, rien lancé

**Question centrale** : peut-on sauter les deux `perform_operation` (TAG 0x22, txn3/txn5 du bring-up macOS c12) et
envoyer directement `null_d_key` (TAG 0x0a, txn4) ? Si le SEP y répond quand même (apparié, en particulier PARAM 0xff
comme macOS), ces deux ops **ne sont pas un prérequis** et on peut avancer sans avoir à élucider leur DER (le « mur »
de `sks_protocol.md` §2.3.4). Sinon, elles le sont (ou l'ordre compte).

**Corps `null_d_key` = ÉTABLI AU BINAIRE (VU, PAS une hypothèse).** Kernelcache 27.2.1
(`macos/kc/26B131__MacBookPro18,4/kernelcache.release.*`, bundle `com.apple.driver.AppleSEPKeyStore`) :
- `__ipc_null_d_key` @0xfffffe0009cdbbd0 : construit un ctx sur la pile avec `ctx+0x50 = 0` (état) et `ctx+0x58 = arg2`,
  op code `w1 = 0xa` ; soumet via la routine de l'endpoint, puis **bzero 0x60 o** du tampon de requête.
- `_code_ipc_null_d_key` @0xfffffe0009cdfc38 : le codec générique écrit **uniquement** l'en-tête IPC (helper
  @0xcff530), puis un u32 depuis `ctx+0x50` (`__word` @0xcff1c0 = état) et un u64 depuis `ctx+0x58` (`__lword`
  @0xcff38c). **Aucun `__word` de longueur de blob, aucun `__blob`** — contrairement à `get_capabilities` (qui ajoute
  un mot de longueur de blob → 0x64) et à `set_env` (qui ajoute un blob → 0x470). Donc corps = en-tête (0x54) +
  état(4) + u64(8) = **0x60**, qui recoupe la trace c12 L186 (`> 0x12 TAG 0x0a TYPE 0x04 DATA 0x00600000`).
- Unique appelant `AppleKeyStore::effaceable_init(bool)` @0xfffffe0009cc6f20 : passe `x1 = 0` (session NULL → le SEP
  prend le handle de keybag par défaut d'un global) et `x2 = 1` → le u64 à OOL 0x58 est la **constante 1** (même valeur
  que get_capabilities et set_env). VU.

`null_d_key` étant la transaction qui suit `set_env`, son en-tête est en **version négociée v2** ; le corps est donc
**get_capabilities MOINS le mot de longueur de blob, en v2**. Dans J9c le compteur de transaction vaut : getcap = 1,
set_env = 2, **null_d_key = 3** (sur le fil macOS c'était 4, parce que les deux perform_operation prenaient 3 et 5 ;
ici ils sont sautés, le compteur n'a donc pas de trou : 1, 2, 3). TYPE de la réponse = 0x03.

**Chemin** = J9b (boot chaîné, getcap, set_env) puis, **seulement si le set_env a été ACCEPTÉ (état 0)** :
1. le noyau attend ≤ 20 s la 3e requête sur `/dev/sep_sks` (3e écriture, 0x60 o ; EAGAIN avant, EALREADY après) ;
2. porte noyau `sep-proto::sks_nulldkey::check_nulldkey` sur les 0x60 o : longueur exacte ; constantes (0x50 @0x00,
   **2** @0x14, 0 @0x20, 0 @0x24, 0 @0x4c, 0 @0x54 état, **1** @0x58 u64) ; **condensé v2 recalculé dans le noyau**
   (SHA-256/16, base = en-tête complet 0x14..0x54 + charge 0x54..0x60) ; cdhash = zéros OU SHA-1 des 8 o de l'uniqueid.
   Aucun champ contextuel autre que l'en-tête (pas de blob, pas de cpx). Refus = EINVAL, rien envoyé, pas de Halted ;
3. copie dans A12, relue ; UN mot `> 0x12 TAG 0x0a TYPE 0x03 PARAM 0 DATA 0x00600000` (porte `NulldkeyGate` : ce mot
   exact, une fois par boot ; tout autre mot vers 0x12/0x17/0x0a reste refusé) ; **aucun perform_operation jamais** ;
4. écoute : la 1re réponse appariée (TAG bit 7, TYPE **0x03**) → instantané de B12 (0x80 o) ; jamais de réponse du
   pilote ;
5. « VERDICT sks null_d_key : **RÉPONDU** (PARAM … ; macOS répond PARAM 0xff = -1, DATA 0, bénin « pas de d-key ») » —
   PARAM ≠ 0 n'est **PAS** une erreur ici (le kext macOS ne décode aucun corps sur PARAM ≠ 0, §1.6.4) — / « SILENCE »
   / « NON ENVOYÉ » (set_env non ACCEPTÉ). `read` de `/dev/sep_sks` rend getcap **puis** set_env **puis** null_d_key
   (3 × 0x98 o). Puis le 0x73 sbio comme J9b.

**Verdict attendu** : RÉPONDU avec PARAM 0xff = comme macOS ⇒ les perform_operation N'ÉTAIENT PAS un prérequis, on
peut avancer. RÉPONDU avec un autre PARAM apparié, SILENCE, ou Halted ⇒ ils le sont (ou l'ordre compte). Le PARAM 0xff
de macOS (`< 0x8a PARAM 0xff`, c12 L187) suggère que le SEP décode peu ou pas le corps de 0x0a ; notre corps étant de
toute façon celui de macOS (byte-exact, hors champs processus neutres), le test reste fidèle.

**Tests hors matériel** : `sep-proto::sks_nulldkey` (disposition et relecture par la porte ; base du condensé v2
reconstruite champ par champ ; **requête identique octet pour octet à une construction Python/`hashlib` indépendante**
— condensé `d51461e0ab398833f4f0e23b6ce34b18`, sha256 complet `e90ebe700cacdeb3a9081f10ecdf433ce0984a45cb2c4cbd77bc4f09d103dbfa` pour
ts=0x1122334455667788, uniqueid 0, uid 0, cdhash=sha1(8×0) ; mot c12 avec TYPE 0x03 ; porte qui refuse chaque constante
modifiée / condensé faux / cdhash étranger / longueur fausse ; appariement de la réponse PARAM 0xff ; porte un seul
mot) ; `sks-setenv` étendu (`build-nulldkey`, `check-nulldkey`, `run --nulldkey`, `decode` à 3 enregistrements ;
`NulldkeyVerdict`).

**Binaires** (`~/kbuild/j11`, compilés contre `~/kbuild/src/linux-asahi-7.2.12-3`, vermagic `7.2.12-3-1-ARCH`) :
`sep_native.ko` `4a5858a317274922adfa10b4293969c2c555a2981f9ea90c8db027f177182b49` (allow_sks=4), `sks_setenv`
`c81a45473926be0b03cb6a69f50a40baccbb87a90dafcbf5623b5dae373658e9` ; `sepd`, `sep_native_ovl.ko`, `sep-native.dtbo` =
copies de `~/kbuild/j10`/`j9`/`j5` (sha256 inchangés).

**Avant le run** : service désactivé (`/etc/sep-touchid/disabled` + reboot) ; STORE = copie chaînée
(`/var/lib/sepd-run-20261122-230441`), jamais `/var/lib/sepd` ; copie du store avant run. **Après** : si 0 SAVE,
`rm /etc/sep-touchid/disabled` + reboot ; sinon le store du service est périmé → décision d'Albert. Classe neuve (3e
type EP 0x12 : null_d_key) **ET ordre neuf** (perform_operation sautés) → **1er run = « go » d'Albert**
(`pending/j9c_sks_nulldkey_chained.sh`).

## 9. Expérience 5 recodée (SQUELETTE) : J10 = la voie identité `create_keybag` puis `make_system_keybag` (`allow_sks=5`) — 2026-11-23 (J13 ; corrigé J14), NON LANÇABLE

**Correction J14 (2026-11-23) : `create_keybag` −13 → VARIANTE 4.** Le run J10 (journal 18:44) a pris `< TAG 0x81 PARAM
0xf3` = **−0xd / −13**, longueur 0, pas de handle. Cause décodée au binaire (`docs/applekeystored_identity.md` **§8**,
`source: kext`) : `create_keybag` est un message **VERSIONNÉ** ; le 1er mot du corps (OOL 0x54 = ctx+0x50) est un
**DISCRIMINANT DE VARIANTE**, pas un « état ». Le squelette posait **0** avec un corps à 3 blobs (forme variante 3/4) →
le SEP décode en **variante 0** (1 blob) → cadre indécodable → −0xd (ce n'est **pas** une politique SEP ni un secret
manquant). macOS émet la **VARIANTE 4** (builder `__ipc_create_keybag_v4`, constante `04` à `__const` 0x7710098, §8.3).
**Correction appliquée (byte-exacte, §8.5)** : discriminant **4**, + un **`__fv_data` (len 0, u32 @0x74)** et un **u64
final (@0x78)** que le squelette omettait, à la place de l'ancien « flag » u64. Corps **0x2c (44 o)**, message **0x80**
⇒ **DATA 0x00800000** (était 0x007c0000), condensé v2 recalculé. Drapeaux d'en-tête (0x20) restent **0** (ne JAMAIS
poser le bit0 « chiffré » → −0xd garanti, §8.1). `make_system_keybag` **INCHANGÉ**. Si −0xd persiste après la variante
4 avec un cadre VALIDE, c'est alors seulement une sémantique SEPOS (classe/handle) — à trancher par capture macOS (§8.5).

**Changement vs la version J10 initiale (load→create).** Le squelette J10 envoyait `load_keybag` (TAG fil 0x03), qui
**importe** un keybag existant par uuid. Le reverse d'`applekeystored` (`docs/applekeystored_identity.md` §6, `source:
userland` + `source: kext`) a tranché : pour un hôte **non-macOS**, la vraie voie « *we will just create a new one* »
est **`create_keybag` (TAG fil 0x01) NU**, pas `load_keybag`. `load_keybag` a donc été **retiré** (de `sep-proto`, de
l'outil, du noyau) et remplacé par `create_keybag`. Conséquence pour l'uuid : `create_keybag` ne porte **pas** d'uuid
(il prend une **classe**) ; l'uuid 16 o est désormais le **blob de `make_system_keybag`** (`identity_load` exige une
OSData de 16 o, §6.3).

**But** : après `get_capabilities` + `set_env` (chemin `allow_sks=3` réutilisé tel quel), en **sautant**
`perform_operation` ET `null_d_key`, enchaîner les **deux** transactions de la voie identité d'appareil
(`docs/applekeystored_identity.md` §6, `source: kext` 27.2.1, gabarits VU) :

1. **`create_keybag` (TAG fil 0x01, TYPE 0x03, VARIANTE 4)** — `> EP 0x12 TAG 0x01 TYPE 0x03 PARAM 0 DATA 0x00800000`,
   OOL A12 = **0x80 o** : en-tête IPC v2 + **discriminant u32 = 4** (OOL 0x54, variante 4) + **handle_y u64** (OOL 0x58) +
   **class u32** (0x60) + **field2 u32** (0x64) + **trois blobs VIDES** (len 0 chacun, 0x68/0x6c/0x70) + **`__fv_data`
   len 0** (u32, 0x74) + **u64 final = 0** (0x78). Crée un keybag **NEUF** à
   partir de la classe et **REND un handle** (réponse TAG 0x81, PARAM 0 = OK ; handle u32 lu à **OOL B +0x6c**, offset
   **DÉDUIT**, OOL du create jamais capturé → à confirmer matériel). **Aucun passcode, aucun uuid** dans create.
2. **`make_system_keybag` (TAG fil 0x0d, TYPE 0x04)** — `> EP 0x12 TAG 0x0d TYPE 0x04 PARAM 0 DATA 0x00840000`, OOL A12
   = **0x84 o** : en-tête IPC v2 + **état u32 = 1** (const, branche état==1) + **handle_y u64** (0x58) + **handle chargé
   u32** (0x60, = la sortie de `create_keybag`) + **type u32** (0x64) + **blob {len 0x10, uuid 16 o}** (0x68/0x6c) +
   **flag u64 = 0** (0x7c). Lie le keybag à l'identité d'appareil (réponse TAG 0x8d ; PARAM 0 = marqué system OK,
   PARAM ≠ 0 = refus). **Aucun handle rendu** (le handle vient du 0x01).

**Valeurs userland** (`docs/applekeystored_identity.md` §6, `docs/sks_userland_values.md` du PC) — **requises, sans
défaut** : **uuid** (16 o, blob de `make_system_keybag`), **class** (u32, create_keybag 0x60), **type** (i32, 0x64 de
`make_system_keybag` ; contrainte VU **type ≤ -10**). **Avec défaut 0** : **handle_y** (u64, 0x58 — un create NEUF n'a
pas de handle de session parent) et **field2** (u32, 0x64 de create_keybag). Non dérivables du binaire → l'outil et le
script **refusent de tourner** si une **requise** manque. **AMBIGU (§6.2/§6.4, non tranché au binaire)** : lequel des
deux u32 de `create_keybag` (0x60/0x64) est la **classe** — codé `class`@0x60, `field2`@0x64 ; **si refus matériel,
échanger `--class`/`--field2`**. Le champ **handle chargé** (0x60 de `make_system_keybag`) n'est **pas** userland :
c'est le handle rendu par `create_keybag`, **lu à l'exécution** et placé par le noyau (`sks_keybag::finalize_mskb`, qui
recalcule aussi le condensé v2) — jamais inventé.

**Offsets DÉDUIT (à confirmer matériel)** : (a) le handle rendu lu à **OOL B +0x6c** (OOL du create jamais capturé) ;
(b) l'uuid dans le **blob de `make_system_keybag`** — §6.3 montre le corps IPC du make_system avec un blob **VIDE**,
l'uuid étant une entrée d'`identity_load` dont le placement IPC exact n'est pas épinglé ; on le place dans ce blob
(DÉDUIT) ; (c) l'affectation class↔0x60 (AMBIGU ci-dessus).

**Porte noyau** (`sks_keybag::check_createkeybag` / `check_mskb`) : longueur exacte, **champs constants** (en-tête ;
create = **discriminant 4** + trois blobs len 0 + fv_data len 0 + u64 final 0 ; make_system = état 1 + blob len 0x10 +
flag 0), **condensé v2 recalculé**,
forme du cdhash. **NON contrôlés** (libres) : uuid, class, field2, handle_y, type (et le handle chargé, dynamique).
Envoi : `create_keybag` d'abord ; `make_system_keybag` **seulement** si `create_keybag` a RÉPONDU PARAM 0 et rendu un
handle.

**Déroulé `allow_sks=5`** : getcap (txn1) → set_env (txn2) → create_keybag (txn3) → make_system_keybag (txn4). `read`
de `/dev/sep_sks` rend getcap **puis** set_env **puis** create_keybag **puis** make_system_keybag (**4 × 0x98 o**).
Verdicts dmesg : « VERDICT sks create_keybag : **handle=0x…** / REFUS » et « VERDICT sks make_system_keybag : **marqué
system** / REFUS (PARAM …) ». Rien d'autre vers 0x12/0x17/0x0a (Halted sinon). Puis le 0x73 sbio comme J9b.

**Verdict attendu** : create_keybag **RÉPONDU avec un handle** = le SEP accepte de créer un keybag neuf depuis Linux (la
voie identité s'ouvre) ; **REFUS** (PARAM ≠ 0) = politique SEP, ou classe inattendue (essayer l'autre u32). make_system
**marqué system** = le keybag est lié à l'identité d'appareil (uuid). SILENCE / figé = l'ordre ou la voie ne passent
pas. **INCONNU décisif** (non tranchable au binaire, `docs/applekeystored_identity.md` §5) : le SEP honore-t-il un
keybag/identité **forgé par Linux**, ou lie-t-il l'enrôlement à l'identité posée par macOS (politique interne) ?

**Tests hors matériel** : `sep-proto::sks_keybag` (disposition et relecture par la porte des deux frames ; base du
condensé v2 ; **requêtes identiques octet pour octet à une construction Python/`hashlib` indépendante** sur des valeurs
d'**exemple arbitraires** « PAS les vraies » — create_keybag (variante 4) condensé `d0427aebdce10db55b328ee85dd5d447`,
sha256 `982010bf12390b1c7c39070054c3ebfdc89730cebc5ad01fe5655588e9e31740` ; make_system_keybag (handle placeholder 0) condensé
`d186ead7fd1410b8151f600e73ea8e29` ; après `finalize_mskb(handle=0xdeadbeef)` condensé `c5fd84961b48bf2de20d818be48d391d`,
pour ts=0x1122334455667788, uniqueid 0, uid 0, cdhash=sha1(8×0), handle_y 0x4242424242424242, class 2, field2 0, type -16,
uuid 00..0f ; porte qui refuse chaque constante modifiée / condensé faux / longueur fausse, accepte les valeurs userland
libres ; **test dédié : ce que NOUS émettons porte le discriminant 4 et la taille 0x80 / DATA 0x00800000** ;
appariement des réponses 0x81/0x8d et lecture du handle à +0x6c ; portes un seul mot) ; `sks-setenv` étendu
(`build-createkeybag`, `build-mskb`, `check-createkeybag`, `check-mskb`, `run --keybag --uuid … --class … --type …
[--field2 …] [--handle …]`, `decode` à 4 enregistrements ; `CreatekeybagVerdict`, `MskbVerdict` ; uuid/class/type
**obligatoires**, erreur claire si absents). `cargo test` vert, clippy propre (`CLIPPY=1` pour le `.ko`).

**Binaires** (`~/kbuild/j14`, compilés contre `~/kbuild/src/linux-asahi-7.2.12-3`, vermagic `7.2.12-3-1-ARCH`) :
`sep_native.ko` `1c6f38bedbecdc872f608f9321994d0297d70a2a20760fc5a068943aeff5385a` (allow_sks=5, create_keybag **variante 4**),
`sks_setenv` `340c3f939c32bdfc33126015a8273ba3701c6cd13e10d8c8b4b6d614990eda09` ; `sepd`, `sep_native_ovl.ko`,
`sep-native.dtbo` = copies de `~/kbuild/j13` (sha256 inchangés).

**Avant le run** : service désactivé (`/etc/sep-touchid/disabled` + reboot) ; STORE = copie chaînée
(`/var/lib/sepd-run-20261122-230441`), jamais `/var/lib/sepd` ; copie du store avant run ; **les valeurs userland
requises fournies** (`UUID=`/`CLASS=`/`TYPE=` ou `--uuid`/`--class`/`--type` ; `FIELD2`/`HANDLE` ont un défaut 0), sinon
le script refuse. **Après** : si 0 SAVE, `rm /etc/sep-touchid/disabled` + reboot ; sinon store du service périmé →
décision d'Albert. Classes neuves (create_keybag + make_system_keybag) **ET ordre neuf** (perform_operation ET null_d_key
sautés) → **1er run = « go » d'Albert** (`pending/j10_sks_create_keybag_chained.sh`). **SQUELETTE : rien ne peut tourner
avant les valeurs userland requises.**

## 10. Expérience (PIVOT) : J11 = `make_system_keybag` STANDALONE, sans `create_keybag` (`allow_sks=6`) — 2026-11-23, rien lancé

**Pourquoi le pivot.** J10b (journal 2026-11-23, `docs/applekeystored_identity.md` §8/§9) a montré que `create_keybag`
(TAG fil 0x01) est un **import-AVEC-données** : il refuse −0xb (« argument requis nul ») quand les trois blobs sont
vides. Ce n'est donc **PAS** la création d'un keybag vide. La **vraie création à neuf** — le SEP fabrique le keybag
système avec sa **clé d'appareil**, blob VIDE — est **`make_system_keybag` (TAG fil 0x0d)** via `identity_load`
(selector 0x78). J11 l'émet **SEUL** (sans `create_keybag` avant) pour voir ce que le SEP répond. Le validateur réel
est dans SEPOS (non lisible) : seul le matériel tranche.

**Ce que J11 émet.** Chemin = J9b (boot chaîné, lockers sans UUID, CNTL de skdl/sks/scrd, UN get_capabilities ACCEPTÉ,
UN set_env ACCEPTÉ) puis, en SAUTANT perform_operation, null_d_key ET create_keybag, **UN SEUL**
`make_system_keybag` : `> EP 0x12 TAG 0x0d TYPE 0x03 PARAM 0 DATA 0x00840000`, OOL A12 = **0x84 o**, **corps
byte-identique** au make_system chaîné de §9 (état 1 + handle_y u64 @0x58 + handle chargé u32 @0x60 + type u32 @0x64 +
blob{len 0x10, uuid} @0x68 + flag u64 0 @0x7c, condensé v2). **La seule différence avec §9 est le compteur de
transaction** : make_system est ici la **3e** transaction (getcap=1, set_env=2, make_system=3), donc le mot porte
**TYPE 0x03** (et non 0x04) ; le TYPE n'est pas dans les octets condensés. Réponse appariée TAG 0x8d **TYPE 0x03**.

**Les entrées (userland).** `uuid` (16 o, blob) et `type` (i32, contrainte VU type ≤ −10) sont **requis** (inconnus,
reversés sur le PC). **Avec défaut 0** : `handle_y` (u64 @0x58) et surtout le **handle chargé** (u32 @0x60). Dans la
version chaînée (§9), ce handle venait de la réponse `create_keybag` (le noyau le posait via `finalize_mskb`). **En
standalone il n'y a pas d'op préalable : le handle chargé et `handle_y` deviennent des entrées userland** ; le noyau
n'insère RIEN et **ne recalcule pas** le condensé — il envoie la requête telle que l'outil l'a construite (condensé
userland déjà contrôlé par la porte `sks_keybag::check_mskb` : longueur, en-tête, état 1, blob len 0x10, flag 0,
condensé v2 ; uuid/type/handle chargé/handle_y **libres**, non contrôlés). Porte d'envoi : `MskbStandaloneGate` (ce mot
exact — TYPE 0x03 —, une fois ; tout autre mot vers 0x12/0x17/0x0a reste refusé → Halted).

**L'INCONNUE du handle (honnête, pas tranchée).** Un make_system standalone porte normalement un handle de keybag
**rendu par create/load**. Ici il n'y en a pas : on teste avec **0**. Deux issues possibles, toutes deux
informatives : (a) **marqué system** (PARAM 0) = le SEP crée le keybag système à partir de sa seule clé d'appareil, sans
handle préalable → la voie identité native s'ouvre ; (b) **REFUS** (PARAM ≠ 0) = un handle valide (ou une op préalable)
est requis d'abord → ça **confirme** qu'il faut une op avant (→ mur, ou capture macOS pour lire la séquence exacte).
Sur PARAM 0, le verdict lit aussi un éventuel handle à OOL B +0x6c (« handle=0x… si rendu », offset DÉDUIT ; un
make_system ne rend normalement PAS de handle).

**Déroulé `allow_sks=6`** : getcap (txn1) → set_env (txn2) → make_system_keybag STANDALONE (txn3). `read` de
`/dev/sep_sks` rend getcap **puis** set_env **puis** make_system standalone (**3 × 0x98 o**). Verdict dmesg « VERDICT sks
make_system_keybag (standalone) : marqué system (PARAM 0 ; handle=0x… si rendu) / REFUS (PARAM …) / SILENCE / NON
ENVOYÉ ». Rien d'autre vers 0x12/0x17/0x0a (Halted sinon). Puis le 0x73 sbio comme J9b. **allow_sks=5 (create_keybag
chaîné) reste disponible et intact.**

**Tests hors matériel** : `sep-proto::sks_keybag` (mot standalone TYPE 0x03 vs 0x04 chaîné ; corps identique à
`encode_mskb` ; appariement de la réponse 0x8d TYPE 0x03 ; `MskbStandaloneGate` un seul mot) ; **requête identique octet
pour octet à une construction Python/`hashlib` indépendante** sur valeurs d'EXEMPLE « PAS les vraies » (ts
0x1122334455667788, uuid 00..0f, type −16, handle_y 0x4242424242424242, handle chargé 0xdeadbeef → condensé
`c5fd84961b48bf2de20d818be48d391d`, sha256 `7cb9ba6138cf7464950f27feea9265f296123245f19c61eb5ae48f0bb2000018`) ;
`sks-setenv` étendu (`run --mskb`, `build-mskb --mskb`, `check-mskb --mskb`, `decode --mskb` ; uuid/type **obligatoires**).
`cargo test` vert, clippy propre (`CLIPPY=1` pour le `.ko`).

**Binaires** (`~/kbuild/j15`, compilés contre `~/kbuild/src/linux-asahi-7.2.12-3`, vermagic `7.2.12-3-1-ARCH`) :
`sep_native.ko` `8a395911a83d0e7faf8c452fa08b6bdd3cfe14f4327a049e6111c9e1c400bfe6` (allow_sks=6), `sks_setenv`
`c7b722ddcb5d8550cb72a16fd5cc629f4991c1ab97118bb412ebb751648f18f0` ; `sepd`, `sep_native_ovl.ko`, `sep-native.dtbo` =
copies de `~/kbuild/j14` (sha256 inchangés).

**Avant le run** : service désactivé (`/etc/sep-touchid/disabled` + reboot) ; STORE = copie chaînée
(`/var/lib/sepd-run-20261122-230441`), jamais `/var/lib/sepd` ; copie du store avant run ; **uuid et type fournis**
(`UUID=`/`TYPE=` ou `--uuid`/`--type` ; `MSKB_HANDLE`/`HANDLE_Y` ont un défaut 0), sinon le script refuse. **Après** :
si 0 SAVE, `rm /etc/sep-touchid/disabled` + reboot ; sinon store du service périmé → décision d'Albert. Classe/ordre
neufs (make_system émis SEUL, create_keybag sauté) → **1er run = « go » d'Albert**
(`pending/j11_sks_make_system_chained.sh`). **SQUELETTE : rien ne tourne avant uuid + type.**

## 11. Expérience (chaînon manquant) : J12 = `load_keybag` (uuid → handle) puis `make_system_keybag` chaîné (`allow_sks=7`) — 2026-11-23, rien lancé

**Pourquoi J12 (le cercle).** Les deux voies d'« identité à neuf » sont dans une impasse réciproque
(`docs/applekeystored_identity.md` §6/§8/§9, journal 2026-11-23) : `create_keybag` (TAG fil 0x01) exige des **DONNÉES**
(refus **−0xb** = « argument requis nul » quand le corps est vide → c'est un import-AVEC-données, pas une création à
neuf) ; `make_system_keybag` STANDALONE (J11, TAG fil 0x0d, sans create avant) exige un **HANDLE** (refus **−0xb**).
Chacun réclame ce que l'autre est censé produire. L'op **JAMAIS testée sur matériel** qui brise ce cercle est
`load_keybag` (**TAG fil 0x03**) : elle prend un uuid de 16 o et **doit RENDRE un handle** (réponse **TAG 0x83**,
PARAM 0 = OK, handle u32 à **OOL B +0x6c** — *DÉDUIT*, §6, à confirmer matériel). C'est le chaînon `uuid → handle →
make_system`. Le gabarit est *VU au binaire* (`__ipc_load_keybag` @0xcdb934 / `_code_ipc_load_keybag` @0xcde92c) et
**récupéré du squelette J10 initial** (git a9aadd0 : il codait déjà `load_keybag(0x03)` + `make_system` chaîné, avant le
pivot vers `create_keybag`). Rien n'est copié d'Apple.

**Ce que J12 émet.** Chemin = J9b (boot chaîné, lockers sans UUID, CNTL de skdl/sks/scrd, UN get_capabilities ACCEPTÉ
état 0 theirs 2 → v2, UN set_env ACCEPTÉ), puis en **SAUTANT** perform_operation (TAG 0x22), null_d_key (TAG 0x0a) **ET**
create_keybag (TAG 0x01) :

1. `load_keybag` (TAG fil 0x03, **TYPE 0x03**) : `> EP 0x12 TAG 0x03 TYPE 0x03 PARAM 0 DATA 0x00740000`, OOL A12 =
   **0x74 o** = en-tête IPC v2 + **état 0** (OOL 0x54) + **handle_y**(u64, 0x58) + **blob{len 0x10 (0x60), uuid 16 o
   (0x64)}** + condensé SHA-256/16 v2 recalculé + cdhash neutre. Le noyau contrôle les constantes (en-tête, état 0, blob
   0x10), le condensé et la forme du cdhash ; **uuid et handle_y sont libres** (userland, non contrôlés en valeur).
2. **Seulement si** `load_keybag` répond **TAG 0x83 PARAM 0** : le noyau lit le handle rendu à OOL B +0x6c et le pose
   dans `make_system_keybag` **CHAÎNÉ** (TAG 0x0d, **TYPE 0x04**, 0x84 o, `finalize_mskb` + recalcul du condensé) —
   **exactement le make_system de `allow_sks=5`** (même porte `MskbGate`, même corps, uuid dans le blob à 0x6c, type à
   0x64). Si load_keybag **REFUSE** (PARAM ≠ 0), make_system n'est **pas** émis.

**Les deux issues (ce que ce run tranche).** (a) `load_keybag` **rend un handle** (PARAM 0) → **cercle brisé** : une
identité d'appareil native, sans macOS, devient possible ; le make_system chaîné peut alors « marquer system ». (b)
`load_keybag` **refuse** (not found / −0xb) → une **identité pré-existante** (keybag posté par macOS) est requise → la
suite est une **capture sous macOS** pour voir la séquence exacte (quel uuid, quel ordre, quel create/import préalable).

**Portes noyau (allow_sks=7).** `sks_ipc::GetcapGate`, `sks_setenv::SetenvGate`, `sks_keybag::LoadkeybagGate` (mot
`> 0x12 0x03 0x03 … 0x00740000`, une fois), puis `sks_keybag::MskbGate` (TYPE 0x04, chaîné, une fois, seulement si le
handle a été rendu). Verdicts dmesg : « VERDICT sks load_keybag : handle=0x… (PARAM 0 … cercle brisé) / REFUS (PARAM …)
/ REFUS/SILENCE / NON ENVOYÉ » et « VERDICT sks make_system_keybag : marqué system (PARAM 0) / REFUS ». Rien d'autre vers
0x12/0x17/0x0a (Halted sinon). Puis le 0x73 sbio comme J9b. **allow_sks=5 (create chaîné) et 6 (make_system standalone)
restent disponibles et intacts.**

**Tests hors matériel** : `sep-proto::sks_keybag` (mot `load_keybag` TYPE 0x03 / TAG 0x03 ; corps 0x74 o relu ;
`LoadkeybagGate` un seul mot ; appariement de la réponse TAG bit 7 / TYPE 0x03) ; **requête identique octet pour octet
à une construction Python/`hashlib` indépendante** (`scratchpad/lkbvec.py`) sur valeurs d'EXEMPLE « PAS les vraies »
(ts 0x1122334455667788, uuid 00..0f, handle_y 0x4242424242424242 → condensé v2 `5fd02233027b4e0ab5d1197a292fcdcd`,
sha256 `0be85f870bd1271abc5d1578efa97b62ee5aa798c371e16fcd3d81cbc8602653`) ; `sks-setenv` étendu (`run --loadkeybag`,
`build-loadkeybag`, `check-loadkeybag`, `decode --loadkeybag` ; uuid/type **obligatoires**, pas de `--class`). `cargo
test` vert, clippy propre (`CLIPPY=1` pour le `.ko`).

**Binaires** (`~/kbuild/j16`, compilés contre `~/kbuild/src/linux-asahi-7.2.12-3`, vermagic `7.2.12-3-1-ARCH`) :
`sep_native.ko` `2dc610b21522d3ef9902872c9704130d0d7a58579882533fb5427d6d2dfd51dc` (allow_sks=7), `sks_setenv`
`842b89d6c3cd11ec6cf4ee0896de02ea23ab97fdb1643895a1078cd8d606463b` ; `sepd`, `sep_native_ovl.ko`, `sep-native.dtbo` =
copies de `~/kbuild/j15` (sha256 inchangés).

**Avant le run** : service désactivé (`/etc/sep-touchid/disabled` + reboot) ; STORE = copie chaînée
(`/var/lib/sepd-run-20261122-230441`), jamais `/var/lib/sepd` ; copie du store avant run ; **uuid et type fournis**
(`UUID=`/`TYPE=` ou `--uuid`/`--type` ; `HANDLE_Y` a un défaut 0, pas de `--class`), sinon le script refuse. **Après** :
si 0 SAVE, `rm /etc/sep-touchid/disabled` + reboot ; sinon store du service périmé → décision d'Albert. Classe neuve
(`load_keybag` jamais émis sur matériel) → **1er run = « go » d'Albert** (`pending/j12_sks_loadkeybag_chained.sh`).
**SQUELETTE : rien ne tourne avant uuid + type.**
