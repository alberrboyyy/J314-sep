# Le coffre xART sur disque (fichier gigalocker) — format décodé

2026-11-17 — Claude (Opus 4.8). **Source : lecture SEULE du disque** (`tools/read_xart.sh`), fichier
`traces/20261117-224724_xart_read/xart__74980DEE-AD6A-5674-B233-B7E10A7FD0CB.gl.bin` (le coffre de la puce
réparée + Touch ID ré-enrôlé, macOS 27.2.1). Aucun macOS, aucun hyperviseur, aucune écriture.

Statuts : **VU** = lu/parsé directement dans le dump (reproductible avec les scripts du scratchpad). **INTERPRÉTÉ** =
rapprochement avec la doc Asahi publique (`public_linux_state.md §B`) et nos notes (`kext_sepmanager.md §8`, handoff). Rien
n'est « vérifié » au sens expérimental (aucune expérience n'a encore rejoué ce coffre à la puce).

## Où vit le coffre (VU)
- Un volume APFS de **rôle xART (0x100)**, nommé `xART`, dans le conteneur `69646961-…` (#0, « iBootSystemContainer »).
  Les autres conteneurs (macOS, ALARM, UEFI, Recovery) n'ont **pas** de volume xART.
- Ce volume contient **un** fichier : `<UUID>.gl` (ici `74980DEE-…-.gl`), **6 291 456 o (0x600000)**, très creux
  (**18912 o non nuls**). `get_gigalocker` de m1n1 lit ce fichier (mais le m1n1 en place est trop ancien pour l'op ;
  `tools/read_xart.sh` le lit par portage Python de `apfs.rs`).

## Structure du fichier (VU)
- Le fichier est un tableau de **slots de 0x9000 octets**. Chaque locker occupe un slot : slot `k` = offset `k*0x9000`.
- **12 lockers** présents (slots 0,1,3,4,5,6,7,8,9,10,11,12). Les slots 2 et 13+ sont **vides** (zéros).
- En-tête d'un locker (au début de son slot) :

| offset (dans le slot) | champ | VU |
|---|---|---|
| +0x00 | 0 (réservé) | toujours 0 |
| +0x01 | **type** (u8) | 0x01, 0x02, 0x03 ou 0x04 (voir plus bas) |
| +0x02 .. +0x12 | **UUID** (16 o) — *seulement pour les gigalockers (type 0x03/0x04)* ; zéro pour les maîtres | — |
| +0x12 .. +0x16 | **longueur** de la charge (u32 LE) | = taille réelle du locker (recoupe la dernière zone non nulle du slot) |
| +0x16 .. +0x1a | **CRC** (u32 LE) | **VÉRIFIÉ** : `CRC-32/ISO-HDLC` (= `zlib.crc32`) de la **charge seule** `[0x22:0x22+longueur]` — reproduit les **12/12** CRC du coffre réel (analyse 2026-11-20, `driver/sepreplay/xart.py:slot_crc`) |
| +0x1a .. +0x1c | u16 LE **inconnu** | présent, varie par locker ; **PAS** un CRC-16 courant de la charge ni une longueur (variantes écartées 2026-11-20) ; rôle à déterminer |
| +0x1c .. +0x22 | 6 o à zéro | VU (toujours nuls dans le coffre réel) |
| +0x22 .. | **charge** (payload scellé, `longueur` octets) | blob chiffré par le SEP |

Taille d'un locker = `0x22 + longueur`. (Cohérent avec la description publique Asahi : UUID vers 0x01, longueur 0x12,
CRC 0x16, charge à partir de 0x22.)

## Réponse de l'AP à un FETCH — et le cas « introuvable » (source: kext, 2026-11-21)
Désassemblage de `AppleSEPXART::_handle_sep_driven_msg` (kernel.macho, `com.apple.driver.AppleSEPManager`).
La réponse est écrite **dans la struct XARTMessage** (ses 8 premiers octets = le mot mailbox) :
- octet 2 = **TYPE** (`strb` du code retour ; 0 = succès) ;
- octets 3-4 = **longueur** (`sturh`) → **PARAM = longueur&0xff, DATA[octet0] = longueur>>8** (confirme le codec `length = PARAM | (DATA0<<8)` depuis le binaire) ;
- octet 5 = **sélecteur** (DATA[octet1]) — ré-émis depuis la requête (bit0 : 0→USER type 0x01, 1→SEP type 0x02 ; gigalockers type 0x03/0x04).
- **Un FETCH maître** initialise la longueur à **0x11** (préfixe maître) puis ajoute la taille de la charge lue.
- **CRC-16** (table CCITT `0x1021` à `__const`+0x940) calculé sur la charge, pour le log « Fetched …-xART with CRC », **pas** envoyé dans le message.

**« Introuvable » n'est PAS un code d'erreur** — macOS répond un FETCH normal (TYPE=0x00) :
| cas | TYPE | longueur (PARAM / DATA0) | tampon A |
|---|---|---|---|
| **maître** introuvable (ou erreur de lecture) | 0x00 | **0x11** (PARAM=0x11, DATA0=0) | 0x11 octets de **préfixe** (zéros), pas de charge |
| **gigalocker** introuvable / supprimé | 0x00 | **0** (PARAM=0, DATA0=0) | vide |

(Branche maître : `str xzr,[sp,#0x30]` → taille 0, longueur reste 0x11 → envoi. Branche gigalocker : `sturh wzr,[x19,#3]`
→ longueur 0 → envoi. Les deux passent par le même `_xmsgSend`, log « Replied to xART app: 0x%016llx ».)
⚠️ **Conséquence pour la route native** : pour signaler « pas de xART Linux » il faut ces réponses-là (TYPE=0x00), **pas** l'op 0x07. Le recon natif n°1 (0x07) a fait **caler** le SEP ; corrigé dans `pending/sep_native_0x13.sh` (ABSENT_FORM=kext).

**Préfixe maître (confirmé kext)** : avant la charge, l'AP écrit en tête du tampon A **0x11 octets à zéro**
(`strb wzr,[x21],#0x11` + `memset(A+1, 0x10, 0)`), puis la charge. Longueur = 0x11 + taille charge. Pour un
maître absent, la charge est vide → A = **0x11 zéros**.

**OS-UUID (op 0x13, source: kext `_determineOsUuidGated`)** : l'UUID d'OS vient d'`apfs-preboot-uuid` (`/chosen`).
- UUID présent → l'AP écrit **16 o** en A et répond **TYPE=0x00**.
- **UUID absent** (flag interne à 0 ; p.ex. chaîne tout-à-zéro) → l'AP répond **TYPE=0x02**, **rien** en A.
→ Pour Linux (pas d'`apfs-preboot-uuid`), le cas fidèle est **TYPE=0x02** ; `sep_native_0x13.sh` l'expose via `OS_UUID_MODE=none` (défaut `fixed` = on sert un UUID Linux, pour ne changer qu'une variable au recon n°2).

## Les 12 lockers (VU ; noms de type = INTERPRÉTÉ)

Type +0x01 : **0x01 = USER-xART (maître)**, **0x02 = SEP-xART (maître)** — sans UUID (le champ UUID est nul) ;
**0x03 / 0x04 = gigalocker** — avec un UUID de 16 o. (Rapproché du handoff : « SEP-xART et USER-xART sans étiquette ;
Credential Manager = étiquette 8624497a » ; « SEP-xART + Credential Manager variables, USER-xART stable ».)

| slot | type | UUID (gigalockers) | longueur | rôle (INTERPRÉTÉ) | UUID vu dans captures pré-DFU ? |
|---|---|---|---|---|---|
| 0 | 0x04 | `2438821b3dc0faf876d7aad6ca4dc668` | 0x01b9 | gigalocker | **oui** (c21/c23/c24) |
| 1 | 0x03 | `38adff1d0c61ca6cd43bd10dd9b3a248` | 0x00b2 | gigalocker | non (sous-ensemble non capturé) |
| 3 | 0x04 | `276377ed2009be0562de50954a060ad7` | 0x0040 | gigalocker | non |
| 4 | 0x04 | `9133c5d52d8f276460f2ff4851d26065` | 0x0028 | gigalocker | **oui** |
| 5 | 0x04 | `9af32c69e0ddb2f7d209280d5edbf51d` | 0x2014 | gigalocker | **oui** |
| 6 | 0x02 | — | 0x0352 | **SEP-xART (maître)** | — |
| 7 | 0x04 | `7233c4d571671e3e4a464d18533242fa` | 0x0080 | gigalocker | non |
| 8 | 0x04 | `e01e3b5e2c38f5960968a4d52ae2b22b` | 0x02b1 | gigalocker | **oui** |
| 9 | 0x01 | — | 0x0540 | **USER-xART (maître)** | — |
| 10 | 0x04 | `407e94c4f60495b3f2fbf5a8a31ae719` | 0x0fb4 | gigalocker | **oui** |
| 11 | 0x04 | `8624497a8c2ff2582625a036fab3b8e3` | 0x00a9 | **gigalocker « Credential Manager »** | **oui** (6×) |
| 12 | 0x03 | `52a82f34c5d81780b4c378a4e20c9fbe` | 0x0a15 | gigalocker | non |

## Fait marquant : les UUID sont STABLES à travers le DFU Restore (VU)
- **6 des 10** UUID de gigalockers ci-dessus (slots 0,4,5,8,10,11) se retrouvent **à l'octet près** dans les tampons OOL
  des captures `c21`/`c23`/`c24` du **2026-11-11** — c.-à-d. de la puce **d'AVANT** le DFU Restore du 16/11.
  Recherche : scripts scratchpad `gl_v2.py`/`lbl.py` (recherche binaire exacte des 16 o).
- → Les UUID des lockers sont **liés à l'appareil, pas à l'état scellé** : ils survivent à un effacement complet +
  ré-enrôlement. Confirme [[voie-c-xart-fraicheur]] (« UUID constant, rejouable ») et le handoff.
- Les 4 UUID « non vus » (slots 1,3,7,12) ne sont pas une contradiction : c21/c23/c24 ne capturaient qu'un **sous-ensemble**
  de l'échange (le SEP ne réclame pas tous les lockers à chaque boot).

## Pourquoi c'est utile (INTERPRÉTÉ)
- Ce `.gl` est le coffre **qui colle à la puce actuelle** (lu en direct, Touch ID ré-enrôlé). Il contient **tout** ce que le
  SEP se fait rendre au boot : les **2 maîtres** (SEP-xART 0x02, USER-xART 0x01) **et les 10 gigalockers par UUID**.
- Le « mur » de l'essai FOLLOW (`hypotheses.md` : « le SEP réclame un gigalocker (op 0x05) qu'on ne sert pas ») devient
  **franchissable** : quand le SEP (démarré par m1n1) FETCH un UUID, on le cherche ici (`UUID → slot → charge à +0x22`) et
  on le lui rend. Les UUID stables garantissent que les demandes du SEP correspondront aux slots.
- **Réserve de fond (inchangée)** : même en servant le bon locker, l'anti-rejeu interne du SEP (nonce de fraîcheur, généré
  par le SEP, non réglable côté AP — cf. `verification_status.md` xART-CHAIN) peut refuser. La fraîcheur vit probablement
  dans le **maître SEP-xART (type 0x02, slot 6)** — c'est le candidat à surveiller. Lire le coffre **ne prouve pas** que le
  rejeu passe ; ça donne un coffre **qui colle** pour enfin tester proprement.

## Protocole de service des FETCH (VU dans la capture snew-reel + kext §8)

Séquence d'un boot (capture `snew-reel`, EP 0x13), chaque requête SEP `<` suivie de la réponse AP `>` de même TAG :

| le SEP demande (`<`) | op | l'AP répond (`>`) — ce qu'il écrit dans A |
|---|---|---|
| TAG 0x02 TYPE **0x0e** | état fw-boot | A vide, réponse (acquittement) |
| TAG 0x01 TYPE **0x13** | UUID d'OS | **16 o d'UUID d'OS** écrits en A@0 (= `apfs-preboot-uuid`) |
| TAG 0x03 TYPE **0x00** | FETCH maître (bit SEP/USER) | **blob maître** écrit en A@0 (ici ~847 o = SEP-xART) |
| TAG 0x04 TYPE **0x00** | FETCH maître (l'autre) | **blob maître** écrit en A@0 (USER-xART) |
| TAG 0x00 TYPE **0x1d** | **annonce d'endpoint** (sbio/skdl/sse/sks/scrd) | `> TYPE=0x16 PARAM=0x00 DATA=(DATA & 0xFFFFFF00)` (ack ; snew-reel L46-54) |
| TAG 0x05 TYPE **0x05** PARAM 0x10 | FETCH gigalocker | **UUID 16 o lu en B** → **locker** écrit en A ; réponse |

Donc pour **rendre le coffre actuel** à une puce démarrée par m1n1, il faut, à chaque requête :
- op **0x0e** → acquitter (comme aujourd'hui) ;
- op **0x13** → écrire l'UUID d'OS (16 o) en A ;
- op **0x00** → écrire le **maître** du `.gl` : **sel=1 → SEP-xART (type 0x02, slot 6)** ; **sel=0 → USER-xART (type 0x01, slot 9)**
  (octet 5 bit 0). ⚠️ Sens **tranché par les logs macOS** (cf. kext §8 L260 corrigé) ; le mapping inverse servait les maîtres croisés
  → SAVE@TAG05 (bug corrigé dans SERVE_GL le 2026-11-18) ;
- op **0x05** → lire l'UUID (16 o) en B, trouver le slot `.gl` d'UUID égal (+0x02), écrire sa **charge** (+0x22) en A ;
- op **0x1d** (annonce d'endpoint) → **acquitter** `> TYPE=0x16 DATA=(DATA & 0xFFFFFF00)` et **continuer** (le nom = DATA[16:8:0]+PARAM) ;
  *leçon 2026-11-18 : cette op n'était pas gérée → faux-arrêt « inconnue → STOP » au 1er run du vrai coffre (cf. docs/journal.md 2026-11-18). Corrigé.*
- op **0x06** (SAVE) → à décider (acquitter = laisser la puce avancer son état ; c'est l'écriture risquée).

### Format de la réponse FETCH — DÉCODÉ (VU, corrélation sur c24)

Message de réponse AP→SEP : `> EP=0x13 TAG=<même que la requête> TYPE=0x00 PARAM=<lo> DATA=<...>`.
- **Longueur totale écrite dans A** = `PARAM | (DATA[octet0] << 8)` (halfword « octets 3-4 » du kext §8). Vérifié :
  maître SEP `PARAM=0x64 DATA0=0x03` → 0x364 = 0x11+0x353 (payload) ; maître USER `0x14/0x08` → 0x814 = 0x11+0x803 ;
  gigalocker `0x0c/0x0c` → 0xc0c. **Le driver doit donc RECALCULER PARAM/DATA0 depuis la taille du blob servi** (on ne
  peut pas rejouer la valeur capturée : le blob diffère).
- `DATA[octet1]` = **drapeau à RÉ-ÉMETTRE tel quel depuis la requête**, pour **toutes** les ops (maître ET gigalocker), pas seulement
  les maîtres. Maître (op 0x00) : c'est le **sélecteur** sel=1→SEP / sel=0→USER (cf. §ci-dessus). Gigalocker (op 0x05) : drapeau
  **0x00/0x01** (VU 17/17 dans snew-reel : resp byte1 == req byte1). `DATA[octet2,3]` = 0. ⚠️ Le script SERVE_GL ne l'écho­ait PAS
  pour les gigalockers (byte1=0 → décalage sur 13 lockers) → **corrigé le 2026-11-18**.
- Le **CRC** n'est PAS dans le message : il est **dans le blob** (le `.gl` le porte à +0x16) ; le SEP le revérifie en interne.

### Point ENCORE ouvert (bloquant pour un code byte-correct) : l'en-tête du tampon A
- **Maître (op 0x00)** : A = `[0x11 octets]` (16 nuls + 1 octet nul observé) **puis** la charge (payload à +0x11). VU : seq94/96.
- **Gigalocker (op 0x05)** : A observé commence **directement à l'offset 0** par la charge (seq133 : `e2fa4b48…`, **pas** l'UUID,
  **pas** 16 nuls). VU.
- → **Incohérence non résolue** : maître préfixé de 0x11, gigalocker non. Et l'appariement exact « quel UUID (tampon B) ↔ quelle
  réponse A » est brouillé par la réutilisation des tampons (`changed=none`). **On ne peut pas lever ça sur les captures
  pré-DFU** (contenu d'une autre puce) **ni capturer la puce actuelle** (hyperviseur = 13.5, perdu). C'est le seul octet-près
  qui manque pour écrire un service **garanti** correct. Un mode « servir » codé sur la meilleure hypothèse resterait **sûr**
  (échec FERMÉ sur SAVE : si le SEP rejette un blob mal emballé, il émet un SAVE → on s'arrête sans acquitter → compteur non
  avancé, pas de brick), mais un emballage faux = **essai non concluant** (un power-cycle d'Albert « gâché »).

**Liste complète des hypothèses du mode `SERVE_GL`** (toutes fail-closed → au pire non concluant, jamais brick) :
(a) charge fil = charge `.gl` (+0x22) à l'octet près ; (b) préfixe maître = exactement 0x11 octets nuls ; (c) ordre
d'octets de l'UUID d'OS servi à l'op 0x13 ; (d) valeurs **fixes** des réponses op 0x0e (`DATA=0x100`) et op 0x13
(`DATA=0`), copiées d'une capture ; (e) l'UUID réclamé (op 0x05) se lit à l'**offset 0** du tampon B ; (f) la réponse
gigalocker n'émet **aucun** sélecteur (`DATA` octet1 = 0). Un SAVE au lancement **ne tranche pas** entre « une de ces
hypothèses est fausse » (non concluant, voie C ouverte) et « vrai refus anti-rejeu » (voie C fermée) — le log dit à quelle
transaction ça diverge, ce qui permet de corriger l'emballage et relancer.

## La vraie question que ça permet enfin de tester (honnête)
- L'essai FOLLOW d'avant (puce **d'avant** le DFU, coffre **périmé**) : après les 2 maîtres, le SEP **re-scellait** (op 0x01)
  au lieu de réclamer les gigalockers (op 0x05). Lecture (`hypotheses.md` HV1-B) : l'état rendu n'était **pas jugé courant**.
- Un anti-rejeu classique protège contre le **rollback** (rendre un **vieux** état), pas contre rendre le **dernier** état.
  Ce `.gl` est, lui, le **dernier état sauvé** de la puce actuelle. **SI** le compteur/nonce interne du SEP n'a pas avancé
  depuis cette sauvegarde (pas de SAVE SEP entre-temps), le servir **pourrait être accepté** → le SEP irait au bout
  (FETCH gigalockers, sbio **fonctionnel**). **SI** le nonce est régénéré à chaque boot et lié à `pnon` (0x15), même le
  dernier état serait périmé au boot suivant → refus. **C'est précisément ce qui n'a jamais été testé** (on n'avait jamais
  de coffre qui colle). Première fois possible. `hypothèse`, à trancher par l'essai (écriture SEP → `pending/`, Albert, image disque).

## 2026-11-18 — Claude (analyste) — Structure du blob RE-SCELLÉ au SAVE (essai SERVE_GL)

**But** : quand on sert le coffre, la puce finit par émettre un **SAVE (op 0x01 TYPE 0x01, TAG 0x05)** et dépose
un blob à re-sceller dans le tampon B (dumpé en `*/follow_B/001_tag05_op01.bin`). On regarde la **structure
observable** (pas de déchiffrement) pour discriminer : (A) la puce **répare** notre input (→ emballage faux de
notre part) vs (B) elle repart d'un **état neuf/défaut** (→ anti-rejeu, elle ignore ce qu'on a servi).

Blobs analysés (tous en lecture seule) :
- SERVE_GL 11-18 : `traces/20261118-082622_xart_replay/follow_B/001_tag05_op01.bin` (maîtres **croisés**, nz=127,
  head `da87a669…`) et `traces/20261118-085250_xart_replay/follow_B/001_tag05_op01.bin` (maîtres **corrects**, nz=126,
  head `1dad4bb6…`).
- FOLLOW 11-12 (puce d'AVANT le DFU, coffre périmé) : `traces/20261112-215313_xart_replay/follow_B/001_tag05_op01.bin`
  (nz=125) et `traces/20261112-223837_xart_replay/follow_B/001_tag05_op01.bin` (nz=127). Ces dossiers contiennent
  **toute la rafale** de 13 SAVE (001..013).

### VU (mesuré sur les dumps + logs)
1. **Les 4 blobs « premier SAVE » font tous ~126-127 octets** de contenu (offsets 0..126, l'octet +0x7f = 0),
   le reste du tampon de 32768 o est nul. Contenu **haute entropie** (97-107 valeurs d'octets distinctes sur 127),
   **aucun en-tête lisible**, aucun champ longueur en clair.
2. **Nos 2 blobs SERVE_GL (croisés vs corrects) ne sont PAS identiques** : **0** position d'octet commune sur 127,
   127/127 octets diffèrent, têtes totalement différentes. Entre **les 4** runs : 125-127 octets sur 127 diffèrent,
   **aucun octet** n'est constant aux 4. Autrement dit **tout varie d'un run à l'autre**, y compris entre les deux
   runs 11-12 (même binaire, même coffre servi) → le contenu re-scellé est **régénéré à chaque fois**, non déterministe
   vis-à-vis de l'input.
3. **Le head de nos re-scellés ne correspond à AUCUN UUID du `.gl`** (`da87a669…`, `1dad4bb6…` ∉ les 10 UUID de
   gigalockers). Combiné au TYPE 0x01 du message, ce **premier SAVE est un SAVE-xART (maître), pas un SAVE-locker** :
   un SAVE-locker, lui, commence son tampon B **par l'UUID 16 o** du gigalocker (VU en FOLLOW 11-12 : TAG 0x09 head
   `9133c5d5…` = `.gl` slot 4 ; TAG 0x0c head `e01e3b5e…` = slot 8 ; TAG 0x10 head `2438821b…` = slot 0).
4. **127 octets (0x7f) ne correspond à AUCUN slot du coffre actuel** : maîtres SEP-xART 0x352 (850 o), USER-xART 0x540
   (1344 o) ; gigalockers 0x28..0x2014. Le re-scellé est **~1/7 de la taille du maître SEP-xART stocké**. C'est une
   **petite structure**, pas une copie (même partielle) d'un maître du `.gl`.
5. **La rafale complète (FOLLOW 11-12)** alterne SAVE-xART (TYPE 0x01, sans UUID, tailles 127/223/323/419…) et
   SAVE-locker (TYPE 0x06, tampon préfixé d'un UUID du `.gl`) sur 13 messages. Le **premier** SAVE est **toujours** un
   SAVE-xART de ~127 o. Le champ **DATA du SAVE** = demi-mot bas `0x0100` (drapeau/compteur, passe à `0x0101`/`0x0102`
   plus loin) + demi-mot haut = **CRC-16 du blob** (`0x2f21`, `0x8c8f`, `0x58e0`…). La **longueur n'est pas dans DATA**
   (implicite = étendue non nulle du tampon). Ce CRC-16 recoupe les lignes macOS « Saving SEP-xART with CRC: 0xXXXX ».
6. **Côté macOS « normal » (puce d'avant DFU, capture c6)** : sur un SAVE piloté SEP, le kext logue
   `Saving SEP-xART with CRC: 0xf55c` puis `gl_rec_write … type: 2 … at idx 13` — macOS persiste un **enregistrement
   complet** (maître type 2 / gigalocker type 4) à un index de slot. **Pas de dump propre** isolant la taille du blob
   que le SEP écrit lors de ce SAVE (les captures avec les lignes « Saving » — p.ex. `20261107_h2-notrace` — n'ont
   pas de tampons OOL ; celles avec OOL n'isolent pas l'appariement SAVE↔tampon ici). **Donc on n'a pas, en capture,
   un blob de re-scellement macOS directement comparable octet-à-octet** — on n'a que sa taille persistée (maître
   complet) et son CRC-16.

### INTERPRÉTÉ (rapprochements, non prouvé — aucun déchiffrement possible)
- Le premier SAVE est un **SAVE-xART maître** de **127 o, haute entropie, régénéré à chaque run** et **sans lien de
  taille ni d'octet** avec le maître SEP-xART servi (850 o). C'est l'**opposé** de ce qu'on attendrait d'une
  « réparation » de notre input (qui donnerait une sortie de forme/taille proche du maître fourni, et au moins
  partiellement reproductible). → Oriente vers l'**hypothèse (B)** : la puce **repart d'une racine neuve/par défaut**
  et **ignore** ce qu'on a servi, plutôt que de rapiécer notre emballage.
- **Argument de contrôle fort** : maîtres **croisés** (082622) et **corrects** (085250) donnent le **même comportement**
  (premier SAVE-xART ~127 o, contenu différent) — le sens du sélecteur maître **ne change pas** l'issue. Et le FOLLOW
  11-12 (rejeu brut du coffre, sans aucun service structuré) produit **le même premier SAVE-xART ~127 o**. Trois
  emballages différents (croisé / correct / rejeu brut) → **même réponse** : cela **n'est pas** le profil d'un échec
  d'emballage qu'on corrigerait côté AP.
- **Limite honnête (ne tranche pas (A) vs (B) au sens expérimental)** : (i) les blobs sont **opaques** — « régénéré »
  et « état neuf » restent une lecture de structure, pas une preuve de contenu ; (ii) on **n'a pas** de blob de
  re-scellement macOS directement comparable (seulement taille persistée + CRC-16) ; (iii) un emballage faux **commun
  aux trois** modes (p.ex. préfixe maître, offsets, valeurs fixes 0x0e/0x13) pourrait, en théorie, déclencher le même
  SAVE — l'uniformité ci-dessus **réduit** mais n'**élimine** pas cette possibilité. Reste donc **`hypothèse`** : un
  faisceau structurel penche nettement vers (B) « état neuf, anti-rejeu », **sans** le certifier. À trancher par
  l'expérience (écriture SEP → `pending/`, Albert, image disque), comme indiqué plus haut.

> Rappel protocole (déjà noté) : la règle « on s'arrête sans acquitter le SAVE » tient — le compteur du SEP **n'a pas
> avancé** (pas de brick). Cette analyse ne change rien à la sûreté, elle lit seulement les tampons déjà dumpés.
