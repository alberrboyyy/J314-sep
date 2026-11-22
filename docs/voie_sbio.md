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

## 8. Push DMA SIO — faisabilité depuis le proxyclient m1n1 (2026-11-22, tracer — LECTURE SEULE)

Question posée : peut-on, depuis un script du repo utilisant l'API m1n1 proxyclient, émettre vers le capteur
Mesa un **transfert SPI DMA contigu** d'environ 22 Ko sur spi2 (CS maintenu, comme macOS), au lieu du FIFO
scruté qui met ~2,2 s et que le capteur refuse (état reste `0x60`, n'atteint jamais `0x29`) ? Rien n'a été
envoyé au Mac ; aucun fichier sous `m1n1/` n'a été modifié (lecture seule, cf. `regles-m1n1-et-macos`). Garde-fou
upstream `m1n1/CLAUDE.md` respecté : lecture OK, zéro écriture dans leur code, rien poussé vers Asahi.

Convention : **VU** = lu dans `m1n1/` ou les traces ; **DÉDUIT** = raisonnement d'architecture.

### 8.1 VU — ce que le proxyclient a DÉJÀ (côté « préparer un buffer »)

- **Allouer un buffer physique contigu en RAM Mac** : `p.memalign(align, size)` / `u.heap.memalign(...)`
  (`m1n1/proxyclient/m1n1/proxy.py:1071`, `proxyutils.py:545`). Écriture en masse : `p.iface.writemem(pa, data)`.
- **Programmer un DART en écriture** : `DART.from_adt(u, "/arm-io/dart-sio")` puis `dart.iomap(stream, pa, size)`
  (alloc IOVA + mappe) ou `iomap_at(stream, iova, pa, size)`, et `dart.iowrite(stream, iova, data)`
  (`m1n1/proxyclient/m1n1/hw/dart.py:70-77,55-68` ; moteur `hw/dart8020.py:113` `iomap_at`, PTE `dart,t6000`).
  C'est l'exact motif utilisé par le driver audio ADMAC : `u.heap.memalign(...)` + `self.dart.iomap(dart_stream, phys, size)`
  (`m1n1/proxyclient/m1n1/hw/admac.py:387-391`). Donc **(a) allouer un buffer + le mapper dans `dart-sio`
  est FAISABLE** avec l'API existante.
- **Lire le bloc de contrôle et les descripteurs SIO** : `SepDartReader` (`hv/trace_sep_filtered.py:237-335`,
  **lecture seule**) ; et l'observateur `hv/trace_sep_spi_dma.py` sait déjà traduire `dart-sio` et extraire le
  descripteur (`+0x40 + DATA*0xc`, pointeur à `+8`, taille à `+0x10`) et les buffers des canaux 0x18/0x19.

### 8.2 VU — ce que le proxyclient N'A PAS (côté « armer le DMA »)

- **Aucun driver du coprocesseur SIO.** `ls m1n1/proxyclient/m1n1/fw/` : `afk` (epic, rbep), `asc` (base, crash,
  mgmt, oslog, syslog…), `aop`, `dcp`, `isp`… **pas de module `sio`**, et rien dans `fw/afk` n'est câblé à
  `/arm-io/sio`. La classe `ASCBaseEndpoint.send()` existe (`fw/asc/base.py:49`) mais il n'y a **aucun endpoint
  SIO instancié/possédé** par le proxyclient.
- **Le seul code SIO côté proxyclient est un OBSERVATEUR.** `hv/trace_mesa.py` et `hv/trace_sep_spi_dma.py`
  écoutent la boîte aux lettres ASC de `/arm-io/sio` en SYNC/ASYNC et **lisent** la mémoire via `dart-sio`
  (lecture seule). Ils décodent les types de message SIO — `2`=Start, `3`=Setup, `5`=Config, `6`=SetupIO,
  `0x65`=Ack, `0x68`=CompleteIO (`trace_mesa.py:85-162`) — et les canaux **0x18 (TX) / 0x19 (RX)**. Mais ils
  n'**écrivent jamais** un message dans l'INBOX. Ils observent un SIO **déjà démarré par macOS**.
- **`m1n1/src/sio.c` ne démarre PAS le SIO.** Il ne fait que **préparer les données de firmware SIO** (tunables
  `asio-ascwrap-tunables`, `dmashim` clés `SSPI`/`SUAR`/`SAUD`/`ADMA`/`AAUD`, `device-type` `dSPI`/`dUAR`/…,
  `map-range`, panic buffer) depuis l'ADT, pour les **passer au système invité** lors du hand-off hyperviseur
  (`sio_setup_fwdata`, `src/sio.c:148-229`). Ce sont les blobs que le **pilote SIO de l'OS invité** consomme —
  m1n1 ne boote ni ne pilote le coprocesseur lui-même.

### 8.3 DÉDUIT — qui fait tourner le SIO, et pourquoi ça change tout

- **Sous hyperviseur AVEC macOS** (le contexte des captures C17-C19) : c'est **macOS (AppleSIO)** qui a booté le
  coprocesseur SIO et qui **possède** sa boîte aux lettres. Le tracer peut observer sans risque ; **écrire** dans
  l'INBOX SIO depuis le proxyclient entrerait en collision avec l'état du firmware SIO de l'invité (séquences,
  descripteurs, tags) — ce n'est ni sûr ni « observe-only », et de toute façon **macOS n'est pas présent** sur la
  route native sbio.
- **Route native sbio (SEPOS seul, PAS de macOS)** — notre contexte réel : **personne ne boote le SIO.** Le FIFO
  scruté marche justement parce qu'il n'exige aucun coprocesseur (`mesa_hello` l'a prouvé, `sensor_hw.md` §essai).
  Mais le chemin **DMA SIO est mort** tant que le coprocesseur n'est pas amené à la vie. Or le proxyclient **n'a
  aucun code** pour ce bring-up RTKit (charger le firmware/les params `sio.c`-style, démarrer l'ASC, établir les
  endpoints, séquence Start/Setup/Config). Il faudrait **écrire un driver SIO complet, à partir de zéro**.

### 8.4 Réponses aux questions précises

1. **Buffer contigu + mapping DART : OUI** (8.1). **Armer spi2 en DMA via un descripteur SIO : NON** — aucun
   moyen existant ; il faut **piloter le coprocesseur SIO par sa mailbox ASC**, ce qui suppose d'abord de le
   **booter** (RTKit). Cette brique n'existe pas dans le proxyclient.
2. **`trace_sep_spi_dma.py` révèle-t-il les registres/descripteurs à ÉCRIRE pour ÉMETTRE ?** **Partiellement.** Il
   donne le **dernier maillon** : layout du descripteur dans le bloc de contrôle (`+0x40 + DATA*0xc`, ptr `+8`,
   taille `+0x10`), les types de message (2/3/5/6/0x68) et les canaux (0x18 TX). Il **ne révèle PAS** le bring-up
   à froid : chargement firmware SIO, paramètres exacts des messages `Setup` (TYPE 3 : PARAM 1 = IOVA du bloc de
   contrôle `<<12`, PARAM 2 = taille, PARAM 0xd/0xe = région capteur — tout cela **observé** mais **non rejouable
   en émission** sans l'état d'un SIO démarré). Il observe un SIO déjà vivant, pas comment le réveiller.
3. **DART de spi2** : oui, il faut une entrée de traduction dans **`dart-sio`** pour que l'IOVA du descripteur et
   du buffer pointent notre RAM. L'API existe (`dart.iomap`/`iomap_at`/`iowrite`, 8.1). (Nuance : sous hv+macOS,
   programmer `dart-sio` percuterait l'usage invité ; en natif on en serait propriétaire.)

### 8.5 VERDICT — BLOQUÉ avec l'outillage actuel (brique manquante = un driver SIO)

**Push DMA SIO reproductible depuis le proxyclient = BLOQUÉ en l'état.** Les briques « préparer » (alloc buffer,
map `dart-sio`, écrire la RAM) **existent** ; la brique « armer/piloter le DMA » **n'existe pas** : il n'y a aucun
driver du coprocesseur SIO dans le proxyclient, et en route native personne ne l'a démarré. Rendre cette voie
praticable = **écrire un pilote SIO RTKit complet** (bring-up + boîte aux lettres Start/Setup/Config/SetupIO,
canal 0x18, descripteur) — gros chantier, et qui toucherait du code côté AP (zone à cadrer vis-à-vis des règles
m1n1 : un **payload du repo** chargé via le proxy, PAS une modif de `m1n1/`).

- **ADMAC n'est PAS une alternative** : c'est un **autre** contrôleur (`hw/admac.py`), câblé à l'audio (MCA/
  speaker/aop, `experiments/*`, `tools/admac_stream.py`), stream DART 2 par défaut. L'ADT rattache spi2 au **SIO**
  (dma-channels 0x18/0x19, clé `SSPI` du `dmashim`), pas à l'ADMA. On ne peut donc pas détourner l'ADMAC vers spi2.
- **Alternative sans DMA, à garder en tête (DÉDUIT, non chiffré)** : le mur FIFO n'est pas la mécanique FIFO
  elle-même mais **les allers-retours tunnel UART par remplissage de 16 o**. Un **payload AP exécuté localement**
  (via `p.call()` d'un petit blob du repo qui boucle remplir-FIFO/attendre-vide sans repasser par le tunnel,
  CS tenu par `SHIFTCFG.OVERRIDE_CS`/`PINCFG.KEEP_CS`) rapprocherait du « burst rapide ». Mais **(a)** CS tenu sur
  22 Ko en FIFO reste non prouvé (`sbio_session.md` §4), **(b)** écrire ce blob AP est la même zone grise que le
  driver SIO. À évaluer comme repli si le driver SIO est jugé trop lourd.

### 8.6 Étapes concrètes d'un futur `pending/sep_native_sbio_dma.sh` (si on décide d'écrire le driver SIO)

Niveau registres/API, dans l'hypothèse d'un SIO à booter en route native (**à faire relire + lancer par Albert ;
c'est du neuf → `pending/` avec en-tête but/risque/résultat, et « go » d'Albert**) :

1. **Bring-up SIO (brique MANQUANTE)** : instancier l'ASC `/arm-io/sio`, charger les params firmware façon
   `src/sio.c` (`sio_setup_fwdata` : tunables, dmashim `SSPI`, device-type `dSPI`, map-range), démarrer le
   coprocesseur (RTKit), attendre l'endpoint applicatif (0x20). **Rien de tout ça n'existe — à écrire.**
2. **DART** : `dart = DART.from_adt(u, "/arm-io/dart-sio")` ; mapper (i) le **bloc de contrôle** et (ii) le
   **buffer patch** (~22 Ko) : `iova = dart.iomap(sid, pa, size)` ; invalider le stream.
3. **Buffer** : `pa = p.memalign(0x4000, len)` ; `p.iface.writemem(pa, bloc_patch_du_SEP)` (les octets viennent du
   SEP, relais — **non rejouables**, à relayer vivants, cf. `sbio_session.md` §5).
4. **Descripteur + Setup** : écrire dans le bloc de contrôle à `+0x40 + DATA*0xc` : pointeur IOVA `+8`, taille
   `+0x10` ; envoyer les messages mailbox `Setup` (TYPE 3 : PARAM 1 = ctrl_iova`>>12`, PARAM 2 = taille), `Config`
   (TYPE 5), puis **`SetupIO` (TYPE 6) sur canal 0x18** avec DATA = index du descripteur.
5. **spi2** : régler CFG `0x40042` (mode DMA) au lieu de `0x40002` (FIFO), CLKDIV 3, SHIFTCFG `0x80c07`
   (valeurs VU `sensor_hw.md` §transport) ; CS maintenu (le contrôleur le tient en DMA). Précéder du prélude
   `80 60 00 07` (commande à part, 7 o, `sbio_session.md` §3b Q1).
6. **Fin** : attendre `CompleteIO` (TYPE 0x68) côté SIO, puis **acquitter par l'ÉTAT capteur** (octet[1]==`0x29`,
   `sbio_session.md` §3b Q4), pas de read-back. Surveiller l'IRQ gpio0 195.

### 8.7 Risques (si ce script voit le jour)

- **Sûreté SEP** : aucune écriture 0x12/0x13/gigalocker/IMG4 ici — c'est du **transport SPI vers le capteur**, pas
  une écriture SEP. Mais c'est une **classe JAMAIS testée** (1er run d'un script neuf + bring-up SIO) → ligne rouge
  « écriture classe neuve » : **go d'Albert obligatoire**, fail-closed, filet DFU/`alarm_p5.img`.
- **DART** : un mauvais mapping `dart-sio` (IOVA/alignement 16 Ko) fait fauter le SIO ; vérifier via le registre
  d'erreur DART (`hw/dart8020.py` `R_ERROR`) avant/après.
- **CS / alignement / taille** : le bloc est **auto-décrit** (2 premiers octets = longueur interne,
  `sbio_session.md` §3b) ; pousser **exactement `fwLen`** octets, rien avant/après ; alignement page 16 Ko du buffer.
- **Collision invité** : ne JAMAIS tenter ce bring-up si un SIO est déjà vivant (hv+macOS) — réservé à la route
  native SEPOS-seul.
- **Incertitude de fond** : même réussi, le mur peut être (C) session/compteur non alignés et pas (A) le timing
  (`sbio_session.md` §3b (A)/(C) : indécidable depuis le binaire). Le DMA ne tranche que l'hypothèse (A).

### Sources (section 8)
- Code m1n1 (lecture seule) : `proxyclient/m1n1/hw/dart.py` (55-77), `hw/dart8020.py` (113 `iomap_at`),
  `hw/admac.py` (367-396), `hw/spi.py` (R_CFG, R_SHIFTCFG, R_PINCFG), `fw/asc/base.py` (49 `send`),
  `proxy.py:1071`/`proxyutils.py:545` (`memalign`), `src/sio.c` (148-229 `sio_setup_fwdata`),
  `hv/trace_mesa.py` (85-162 types/canaux SIO), `hv/trace_sep_spi_dma.py` (layout descripteur),
  `hv/trace_sep_filtered.py` (237-335 `SepDartReader`). `ls fw/` (pas de module `sio`).
- Docs : `sensor_hw.md` (§transport : CFG 0x40042/0x40002, canaux 0x18/0x19, descripteur) ;
  `sbio_session.md` §3b (chaîne kext DMA, prélude, critère 0x29), §4 (verdict FIFO vs DMA), §5 (rejouabilité).

---

### Sources
- Traces : `20261118-082622`, `…085250`, `…075343` (SERVE_GL + PROBE_SBIO, B8 nul ×3) ;
  `20261108-032454_c12-boot-ho/sep.log` (L107-136, L318-322) ; `20261111-013303_c24-xart-ool/sep.log`
  (L12-23) ; `20261109-210517_sep_peek/adt_sep.txt` (L58-87, dart-sep `sids=0x8001`).
- Code : `m1n1/proxyclient/m1n1/hw/sep.py` (L24-29, L72), `m1n1/src/dart.c` (L89-91),
  `hv/trace_sep_filtered.py` (L284), `pending/sep_xart_replay.sh` (L792, L797-830).
- Docs : `kext_sepmanager.md` §5, §7, §13/§13b (`source: kext`) ; `messages.md` SBIO (EP 0x08) ;
  `journal.md` L1443-1445 (sbio OOL lu au sid 0).
