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
| +0x16 .. +0x1a | **CRC** (u32 LE) | présent ; algo non vérifié |
| +0x22 .. | **charge** (payload scellé, `longueur` octets) | blob chiffré par le SEP |

Taille d'un locker = `0x22 + longueur`. (Cohérent avec la description publique Asahi : UUID vers 0x01, longueur 0x12,
CRC 0x16, charge à partir de 0x22.)

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
| — | — | *puis le SEP annonce sbio/skdl/sse/sks/scrd (TYPE 0x1d)* |
| TAG 0x05 TYPE **0x05** PARAM 0x10 | FETCH gigalocker | **UUID 16 o lu en B** → **locker** écrit en A ; réponse |

Donc pour **rendre le coffre actuel** à une puce démarrée par m1n1, il faut, à chaque requête :
- op **0x0e** → acquitter (comme aujourd'hui) ;
- op **0x13** → écrire l'UUID d'OS (16 o) en A ;
- op **0x00** → écrire le **maître** du `.gl` : slot 6 (SEP-xART) si bit SEP, slot 9 (USER-xART) si bit USER (octet 5 bit 0) ;
- op **0x05** → lire l'UUID (16 o) en B, trouver le slot `.gl` d'UUID égal (+0x02), écrire sa **charge** (+0x22) en A ;
- op **0x06** (SAVE) → à décider (acquitter = laisser la puce avancer son état ; c'est l'écriture risquée).

### Format de la réponse FETCH — DÉCODÉ (VU, corrélation sur c24)

Message de réponse AP→SEP : `> EP=0x13 TAG=<même que la requête> TYPE=0x00 PARAM=<lo> DATA=<...>`.
- **Longueur totale écrite dans A** = `PARAM | (DATA[octet0] << 8)` (halfword « octets 3-4 » du kext §8). Vérifié :
  maître SEP `PARAM=0x64 DATA0=0x03` → 0x364 = 0x11+0x353 (payload) ; maître USER `0x14/0x08` → 0x814 = 0x11+0x803 ;
  gigalocker `0x0c/0x0c` → 0xc0c. **Le driver doit donc RECALCULER PARAM/DATA0 depuis la taille du blob servi** (on ne
  peut pas rejouer la valeur capturée : le blob diffère).
- `DATA[octet1]` = **sélecteur SEP/USER** (bit 0), à **ré-émettre** tel que reçu dans la requête. `DATA[octet2,3]` = 0.
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
