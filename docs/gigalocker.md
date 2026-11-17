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

## À faire ensuite (préparation d'un essai lancé par Albert)
- Étendre `pending/sep_xart_replay.sh` (ou un nouveau mode) pour **servir les FETCH depuis ce `.gl`** : à chaque op 0x05
  (FETCH gigalocker, UUID lu en tampon B) et op 0x00 (FETCH maître), répondre avec la charge du slot correspondant, au lieu
  de rejouer un OOL périmé. Écriture SEP → script `pending/`, **lancé par Albert**.
- Reste à cadrer avant de coder (règle « protocole complet avant de répondre ») : format EXACT de la réponse FETCH (en-tête
  tampon A, où va la charge, l'UUID est-il ré-émis), lu depuis une capture macOS + `kext_sepmanager.md §8`.
