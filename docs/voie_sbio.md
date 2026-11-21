# Voie « SBIO directe » — pourquoi le 0x73 est muet sous m1n1, et est-ce une voie vers Touch ID ?

Analyste, 2026-11-18. Lecture seule sur `traces/`, aucune action matérielle, aucune écriture SEP.
Question : après SERVE_GL, l'EP **sbio (0x08)** est *annoncé* mais notre sonde **0x73** (1re commande
d'init sbio, sans doigt) reçoit **AUCUNE réponse** (B8 nul, aucun message EP 0x08). Pourquoi ? Et la voie
« piloter sbio directement sous m1n1 » est-elle plausible offline, ou bloquée ?

Convention : **VU** = valeurs/ordre lus dans les traces ou le code ; **INTERPRÉTÉ** = rôle supposé.
Statut des faits « kext » = `source: kext` (désassemblage, protocole uniquement). Rien ici n'est `vérifié`
au sens du projet (aucune expérience ne l'a tranché).

---

## 1. VU — le message et l'OOL de notre sonde sont IDENTIQUES à macOS

- macOS, 1er message sbio (c12, `traces/20261108-032454_c12-boot-ho/sep.log` **L318**) :
  `> EP=0x08 TAG=0xfc TYPE=0x73 PARAM=0x00 DATA=0x00000000`.
- Notre sonde (`pending/sep_xart_replay.sh:830`) envoie
  `SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x73, PARAM=0, DATA=0)` → **mot 64 bits identique** octet pour octet.
  (Encodage `SEPMessage`, `m1n1/.../hw/sep.py:24-29` : TAG=bits 8-15, TYPE=16-23, PARAM=24-31, DATA=32-63.)
- Le `gt_packet_t` écrit dans A8 est rejoué octet pour octet depuis la capture (`000300_08_A.bin`), avec
  `+0x00=1` et **opcode `+0x14=0x73`** (format VÉRIFIÉ, `kext_sepmanager.md` §13b). La sonde vérifie
  `a_bytes[0x14]==0x73 and a_bytes[0]==1` avant d'envoyer (`sep_xart_replay.sh:792`).

INTERPRÉTÉ : ni le mot mailbox, ni le contenu de l'OOL ne sont la cause du silence — ils reproduisent
exactement ce que macOS envoie. La cause est **ailleurs** (DART, état du SEP, ou endpoint non armé).

## 2. VU — la réponse macOS de référence, et notre silence total

- macOS (c12) répond au 0x73 en 8 ms : **L320** `< EP=0x08 TAG=0x04 TYPE=0x00 PARAM=0x00 DATA=0x00000000`
  (message mailbox **pur**, sans OOL — `messageClients(0xe3ff800c)`, `kext §6` TAG 0x04), puis L321-322
  un `< TAG=0xfc TYPE=0x73` avec B8 = `gt_packet` (`+0x14=0x73`).
- Nous (3 runs SERVE_GL, `traces/20261118-082622`, `…085250`, `…075343`) : les 4 CNTL d'ouverture
  (A8/B8 taille+adresse, PARAM=0x08, IOVA 0x54000/0x5c000) sont **acquittés**, puis **RIEN** :
  aucun message EP 0x08, et `sbio_probe_B.bin` = **16384 octets, 0 non nul** dans les 3 runs. Reproductible n=3.

INTERPRÉTÉ (important) : le `< TAG=0x04` de macOS est un message **mailbox pur** (aucune lecture d'OOL
requise). Nous ne recevons **même pas ça**. Donc le SEP ne **commence pas** à traiter notre 0x73 — ce
n'est pas « il traite mais la réponse OOL se perd ». Cela ne tranche pas à lui seul entre « OOL illisible
(il faut lire A8 avant d'émettre le 0x04) » et « l'endpoint n'est pas armé pour accepter 0x73 ».

## 3. VU — le DART de l'EP 0x08 (sbio) vs l'EP 0x13 (xART)

- `dart-sep` (ADT, `traces/20261109-210517_sep_peek/adt_sep.txt` **L58-87**) : `compatible dart,t6000`,
  `page-size 16384`, **`sids = 32769` = 0x8001** → deux streams valides : **sid 0 et sid 15**.
- m1n1 ne programme **qu'un seul stream** : `hw/sep.py:72` `dart_init(self.dart_base, 0)` (device/sid=0) ;
  `m1n1/src/dart.c:89-91` `DART_TCR(dart)`/`DART_TTBR(dart,idx)` indexent par `dart->device`. Donc
  **tous** les mappings SEP de m1n1 (firmware, shmem, xART A/B, sbio A8/B8) vont dans **stream 0**.
  `m1n1/src/sep.c` ne touche à aucun autre sid.
- EP 0x13 (xART) : A/B à IOVA **0x2c000 / 0x38000**, mappés en stream 0 (replay : « A sid=0 | B sid=0 »).
  Le SEP **lit A et écrit B** en stream 0 — observé (lockers servis, 14 écritures de A, réponses du SEP ;
  c24 `traces/20261111-013303_c24-xart-ool/sep.log` L17-23 : EP 0x13 OOL `xlat=miss` au 1er accès puis `hit`).
- EP 0x08 (sbio) : A/B à IOVA **0x54000 / 0x5c000**, taille 0x4000, PARAM=0x08
  (c12 sep.log L127-136 ; c4-shmem L136-144). Sous **macOS**, le traceur **lit** ces tampons **au sid 0**
  (`docs/journal.md` L1443-1445 : « dart-sep dart,t6000 **sid 0** » pour le buffer PARAM=0x08) ; c12 L319+
  `xlat=hit` sur 147 accès EP 0x08 (seulement 2 `miss` au tout 1er accès = artefact de cache du traceur :
  en L319 `xlat=miss` et pourtant le SEP répond L320 → le `miss` est côté traceur, pas côté SEP).

INTERPRÉTÉ sur le stream DART :
- Le traceur fait `find_sid` en **scannant sid 0 d'abord** (`hv/trace_sep_filtered.py:284`). « Lu au sid 0 »
  prouve que le tampon sbio **est mappé** en stream 0 sous macOS — **pas** que le SEP, pour sbio, émet sa
  DMA via le stream 0 : XNU/`IODARTMapper` peut mapper dans **les deux** streams (0 et 15), et le SEP
  pourrait DMA-er sbio via sid 15.
- Faisceau **contre** « sbio sur un autre stream » (cause i) : le **mailbox/shmem** (tous les messages) et
  l'**OOL xART** fonctionnent en stream 0 sous m1n1 ; l'OOL sbio **est** mappé en stream 0 sous macOS ;
  même `dart-sep`, même cœur SEP. Rien dans l'ADT, les kexts ou le code ne rattache sbio à un sid distinct.
- Faisceau **résiduel pour** la cause (i) : `sids=0x8001` déclare **deux** streams, et m1n1 n'en programme
  qu'un (0). Pourquoi déclarer sid 15 s'il ne sert jamais ? On **ne peut pas** exclure, offline, que la DMA
  OOL de sbio passe par sid 15 (non programmé par m1n1 → lecture de A8 en faute silencieuse).
- **Bilan stream** : la cause (i) est **affaiblie** (sbio lisible au sid 0 comme xART), **pas éliminée**
  (sid 15 déclaré et non programmé par m1n1). C'est l'inconnu le plus **net et testable**.

## 4. VU — la vraie séquence d'init de sbio dans les captures macOS

Ordre macOS (c12, `kext §5` et §7) jusqu'au 1er 0x73 **fonctionnel** :
1. Boot ROM + IMG4 + shmem (`hv_uart` L645-646 : « SEP booting », shmbuf slave 0x580000/0x1c000).
2. Annonce 0xFD : `sbio` = 0x08 (c12 L107-108 `< EP=0xfd … PARAM=0x08 DATA=0x7362696f`).
3. Ouverture sbio : **4 CNTL** A/B taille+adresse, PARAM=0x08, 0x4000 (c12 L127-136 ; `kext §5`).
   Aucun message *vers* l'EP 0x08 n'est requis pour « ouvrir » ; la 1re commande est 0x73 (`kext §5.4`).
4. **Seulement bien plus tard** : 1er `> 0x73` à t=…737 (c12 L318), soit **~26 s après** l'annonce (t=…711).
   Entre les deux : activité **EP 0x12 (keystore/SKS)** (c12 L182, L300-302 : `> EP=0x12 … TYPE 0x15/0x16`)
   et xART. Puis `0x73 → <0x04 → <0x73`, puis `0x17` (n° série capteur), `0x15/0x16` (échange de clé de
   session **avec le capteur** par SPI), `0x42/0x18`, `0x5f` (patch), `0x5d/0x5c/0x6a`, `0x5b` (calibration,
   blob espace utilisateur), `0x6d` (catacomb, blob scellé), … (`kext §7 B`, format fil VÉRIFIÉ §13b).

INTERPRÉTÉ : on ne **saute** aucune étape *entre l'ouverture et le 0x73* — macOS n'envoie, lui non plus,
rien d'autre à l'EP 0x08 avant le 0x73. **Différence réelle** : dans SERVE_GL on envoie le 0x73
immédiatement après l'ouverture, alors que l'**état interne** du SEP diffère de celui de macOS à t=…737 :
- **xART non scellé** : en SERVE_GL on s'**arrête sur le SAVE sans l'acquitter** (compteur non avancé,
  anti-brick) — c'est voulu. macOS, lui, a **terminé et scellé** xART avant le 1er 0x73.
- **Keystore (EP 0x12) jamais initialisé** sous m1n1 (on ne le pilote pas).
- `D2` (`kext §7`) : le keybag **conditionne le match (0x09) et le lockState**, pas a priori la *poignée*
  0x73. Donc « keystore absent » explique mal le silence sur 0x73 ; « xART non scellé / endpoint non armé »
  l'explique mieux.

## 5. INTERPRÉTÉ — les trois causes, triées

- **(i) stream/sid DART différent** (A8 non lu car sbio DMA via sid 15, non programmé par m1n1) :
  **possible mais affaibli**. Pour : `sids=0x8001` déclare sid 15, m1n1 ne programme que sid 0. Contre :
  mailbox + OOL xART marchent en sid 0, et l'OOL sbio est mappé/lu en sid 0 sous macOS. **Testable** (§6 E1).
- **(ii) sbio exige un état préalable** (xART **scellé**, ou endpoint armé plus tard dans le boot) :
  **plausible**. Le 0x73 n'arrive qu'après xART complet chez macOS ; nous, on s'arrête avant le SAVE.
  « Annoncé » (tâche SEPOS chargée) ≠ « armé » (prêt à traiter un 0x73). Le silence **total** (même pas le
  `<0x04` mailbox pur) colle à « la tâche sbio n'accepte pas encore de commande ».
- **(iii) l'état restauré sous m1n1 ne rend pas sbio fonctionnel** : recouvre (ii). sbio est annoncé mais
  le contexte (xART non scellé, pas de passage « OS déverrouillé ») peut le laisser inerte.

On **ne peut pas** trancher (i) vs (ii)/(iii) offline : les deux produisent le même silence total.

## 6. CONCLUSION — la voie « sbio directe » est PLAUSIBLE à tester, pas prouvée bloquée

Ce qui est **acquis** : le **protocole fil sbio est connu et VÉRIFIÉ** (`kext §13b` : message `0xfc`,
`gt_packet_t`, opcode `+0x14`) ; la **séquence d'ouverture jusqu'au 0x73** est connue et on la reproduit
**octet pour octet** ; le DART de sbio est **identifié** (IOVA 0x54000/0x5c000, même `dart-sep` que xART,
lu au sid 0 sous macOS). Il **ne manque donc ni le format, ni la séquence d'amorçage du 0x73**.

Donc la voie « piloter sbio directement sous m1n1 » est **PLAUSIBLE pour la poignée de main 0x73**
(à trancher par une expérience), **pas** démontrée bloquée par un secret. Deux expériences discriminent,
à écrire dans `pending/` pour Albert (je ne les lance pas, je ne touche pas `pending/`) :

- **E1 — stream DART (teste la cause i). IMPLÉMENTÉE + RELUE (2026-11-19).** Programme **aussi le stream 15**
  du `dart-sep` (`dart_init(base, 15)`) et **mappe A8/B8 dans les deux streams (0 et 15)**, puis renvoie le
  0x73 identique. Code : `pending/sep_xart_replay.sh` (`SBIO_STREAM15=1`, l.849-942). Lanceur :
  `pending/probe_sbio_stream15_go.sh`. Nature de l'action : `dart_map`/`dart_init` écrivent les **tables DART
  côté AP** (même classe que le stream 0 de chaque boot), **pas** une écriture vers le SEP (pas
  0x12/0x13/0x10/0x15, pas de gigalocker, pas d'IMG4). **Sceptique 2026-11-19 : sûreté OK** (aucun SAVE
  acquitté possible — fail-closed `return served, False` ; seules écritures en plus = tables DART côté AP).
  Réserve de sûreté non bloquante : « sid 15 ne perturbe pas sid 0 » est une hypothèse (lecture m1n1
  interdite en écriture ; argument d'ordonnancement → pire cas = « non concluant », pas brick).
  - **Protocole en 2 RUNS (sinon E1 seul ne tranche pas) :** (1) E1 avec stream 15 ; (2) **cold-boot** ;
    (3) run de contrôle SANS stream 15 (`pending/probe_sbio_control_go.sh`) ; (4) comparer. Vérifier dans
    CHAQUE run : sbio annoncé + 4 CNTL acquittés + 0x73 envoyé (sinon comparaison faussée).
  - **Mesure directe ajoutée (2026-11-19) : lecture seule du registre de faute du `dart-sep`**
    (`DART_ERROR=0x40`, sid fauté = bits 27:24, cause READ_FAULT = bit 4 ; source lecture m1n1
    `hw/dart8020.py` l.11-23/67-69, `src/dart.c` l.17-39). Lue avant/après le 0x73. Discriminant net :
    au **run de contrôle** (sans stream 15), une **faute de LECTURE neuve sur sid 15** = preuve **directe**
    que le SEP lit l'OOL sbio via sid 15 → cause (i) **confirmée**, même si sbio reste muet. Latch : exige
    un baseline `FLAG=0` (d'où le cold-boot) ; si le drapeau est déjà levé, le run ne tranche pas (imprimé).
- **E2 — état (teste la cause ii/iii).** Comparer la réponse au 0x73 selon que xART a été **scellé** ou non.
  Mais **sceller xART = acquitter le SAVE = avancer le compteur = ÉCRITURE SEP = ligne rouge** : cette
  branche reste un script `pending/` lancé par Albert, pas un essai agent. Variante **sans écriture SEP** :
  envoyer le 0x73 **à différents moments** du boot (avant/après le service du coffre) pour voir si l'instant
  d'armement de sbio change quelque chose — informatif, sans rien sceller.

**Limite à ne pas masquer** : même si E1/E2 font répondre le 0x73, un **vrai** Touch ID par cette voie
reste un gros chantier **au-delà** : `0x17` (n° de série **lu sur le capteur** par SPI), `0x15/0x16`
(échange de clé de session **produit par le SEP avec le capteur**, SPI), `0x5b` (calibration signée),
`0x6d` (catacomb scellé) — tous dépendants du **lien SPI capteur réel** et/ou de **blobs** qu'on ne peut
que **rejouer**. La poignée 0x73 est testable ; le match complet ne l'est **pas** par sbio seul sans le
capteur et ces secrets.

**Pour le sceptique** : rien ci-dessus n'est `vérifié` (aucun run réel). Le point décisif est « silence total =
endpoint non armé (ii) » vs « A8 illisible en stream 0 (i) ». **Relecture faite 2026-11-19** : E1 les sépare
proprement et sans écriture SEP, **à condition** du run de contrôle (2 runs) + du cold-boot ; la lecture du
registre de faute DART (sid fauté) rend le verdict direct au lieu d'ambigu (muet/pas-muet). Reste à lancer
par Albert (écriture via SERVE_GL = ligne rouge).

## 7. RÉSULTAT E1 + CONTRÔLE (2026-11-19, runs d'Albert) — cause (i) « canal DART » ÉCARTÉE par l'expérience

Deux runs sur **boots frais** (cold-boot entre les deux), SERVE_GL jusqu'à l'arrêt sur SAVE (compteur non
avancé), puis sonde 0x73 :
- **E1 (stream 15 ouvert)** : A8 mappé en sid **[0, 15]** (confirmé par le diagnostic). 0x73 → **B8 nul, aucun
  message EP 0x08**. Registre de faute `dart-sep` : `FLAG=0` avant ET après (aucune faute neuve).
- **Contrôle (sans stream 15)** : A8 en sid **[0]** seulement. 0x73 → **B8 nul**. Registre de faute :
  `FLAG=0` avant/après — **aucune faute de lecture sur sid 15**. (Baseline `ERROR=0x0a000400 FLAG=0` = bits
  rémanents sans faute active, identique dans les deux runs.)

VU : silence **identique** dans les deux cas ; ouvrir le stream 15 ne change rien ; et sans stream 15 le SEP
ne **faute pas** sur sid 15.

INTERPRÉTÉ : cause (i) (le SEP lirait l'OOL sbio via sid 15, non programmé par m1n1) **écartée par
l'expérience** — s'il lisait via sid 15, le contrôle aurait fauté sur sid 15, et E1 (sid 15 ouvert) aurait
répondu. Reste la cause **(ii)/(iii) : l'ÉTAT** — sbio annoncé mais **pas armé**, très probablement tant que
**xART n'est pas scellé**.

Réserves (honnêteté) : E1 n=1 (contrôle/baseline muet désormais n=4) → reproduire E1 n≥3 pour clouer ;
« aucune faute DART » suppose que le DMA de l'OOL sbio passe par ce `dart-sep` et que la faute serait latchée
(non prouvé, cf. §6). Faisceau net malgré ces réserves : **ce n'est pas le canal, c'est l'état.**

Conséquence : la prochaine marche (E2) = tester si sbio s'arme quand xART est **scellé**. Or sceller =
acquitter le SAVE = **avancer le compteur = écriture SEP = ligne rouge** (c'est ce qui a bické le Mac en
voie C). La variante **sans écriture** (envoyer le 0x73 à différents instants du boot) est peu prometteuse
(macOS n'envoie rien d'autre à 0x08 avant son propre 0x73 ; la vraie différence est xART scellé). Donc le
test décisif de l'état est un **script `pending/` risqué, lancé par Albert**, pas un essai agent.

---

### Sources
- Traces : `20261118-082622`, `…085250`, `…075343` (SERVE_GL + PROBE_SBIO, B8 nul ×3) ;
  `20261108-032454_c12-boot-ho/sep.log` (L107-136, L318-322) ; `20261111-013303_c24-xart-ool/sep.log`
  (L12-23) ; `20261109-210517_sep_peek/adt_sep.txt` (L58-87, dart-sep `sids=0x8001`).
- Code : `m1n1/proxyclient/m1n1/hw/sep.py` (L24-29, L72), `m1n1/src/dart.c` (L89-91),
  `hv/trace_sep_filtered.py` (L284), `pending/sep_xart_replay.sh` (L792, L797-830).
- Docs : `kext_sepmanager.md` §5, §7, §13/§13b (`source: kext`) ; `messages.md` SBIO (EP 0x08) ;
  `journal.md` L1443-1445 (sbio OOL lu au sid 0).
