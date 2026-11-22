# Mission — agent Claude côté Mac (sous Linux)

> Rédigé 2026-11-22 par la session d'orchestration (Opus 4.8) pour l'agent Claude qu'Albert lance **sur/près
> du Mac quand il est booté sous Linux**. But : tu exécutes le travail hardware côté Linux ; la session
> d'orchestration tient le protocole (docs/) et te passe les séquences exactes. **Tu me rends compte, tu ne
> franchis pas seul les lignes rouges.**

## 0. Contexte en une phrase
Objectif final du projet : **Touch ID sous Linux natif sur le MacBook Pro M1 Max (j314c), SANS tether**
(plus de PC branché en USB + m1n1-proxy). m1n1 reste l'échafaudage de reverse ; le livrable = un pilote Linux.
Décision d'Albert 2026-11-22 ([[cible-linux-natif-sans-tether]]). Lis `docs/linux_roadmap.md` (roadmap J0→J6)
et `CLAUDE.md` (règles) avant d'agir.

## 1. Lignes rouges qui TE concernent (CLAUDE.md, « Exception : Linux sur le Mac », MAJ 2026-11-22)
- ⚠️ **Plus de Linux de test jetable** : on est sur la **partition Linux PRINCIPALE d'Albert (ALARM), NON jetable**
  (priorité « ne pas perdre Linux »). Albert a fait un **snapshot** (protège les FICHIERS, PAS un brick SEP/boot).
  Tu tournes soit localement sur le Mac, soit l'orchestrateur te relaie via `tools/linux_ssh.sh`.
- **SEP AUTORISÉ depuis ce Linux** (ouvert 2026-11-22) : sbio 0x08, SKS 0x12, xART 0x13, 0x10/0x15,
  gigalockers, boot SEPOS (IMG4), DMA capteur via apple-sio — MAIS avec la **même discipline** que sous m1n1 :
  - **fail-closed** à la 1re incohérence ; **filet AVANT toute écriture SEP** = image disque OS `alarm_p5.img` +
    backup perso d'Albert + DFU. macOS **sacrifiable** (Albert : les écritures xART/enrôlement cassent
    probablement le Touch ID macOS + FileVault → accepté, récupérable DFU + ré-enrôlement).
  - **tout 1er run d'une classe neuve OU d'un script neuf = « go » d'Albert.** Les re-runs d'un script déjà
    éprouvé = autonomes. Tu me signales ce que tu veux lancer ; je fais remonter à Albert ; tu attends le go.
  - **power-cycle physique = toujours Albert** (le reboot logiciel fige le PMU).
  - **JAMAIS** le Secure Element « Stockholm » en direct (brick définitif, [[stockholm-se-brick-definitif]]).
- **Toujours interdit même là** : partitionner, `dd`, `bputil`/`kmutil`/`csrutil`/`nvram`, toucher à **m1n1**
  (install/upgrade), à la **boot policy**, à **macOS** ; rien vers Asahi ; aucun matériel Apple leaké.
- ⚠️ **Outil à ajuster** : `tools/linux_ssh.sh` a un filtre `DENY` qui bloque encore `sep|xart|gigalocker|0x1[0235]`.
  Il PRÉCÈDE l'ouverture 2026-11-22 et bloquera les commandes SEP légitimes. **Ne le contourne pas** : signale-le,
  Albert/l'orchestrateur le mettra à jour pour n'interdire que disques/boot/m1n1/Stockholm. Tant que non fait,
  les tâches J0/J1 (capteur + offline) passent ; les tâches SEP (J2+) attendent cet ajustement + le go d'Albert.

## 2. Ce qui EST déjà acquis (ne pas refaire)
- **Capteur depuis Linux (J0)** : `driver/linux/mesa_transport.h` (couche transport réutilisable) +
  `mesa_probe.c`/`mesa_statloop.c`/`mesa_irqwatch.c`. Séquence « bonjour » **vérifiée 2× sous m1n1**
  (`docs/verification_status.md` SPI-3). Préparé mais **jamais lancé sous Linux** → c'est ta 1re tâche.
- **Transport SEP hors-ligne (J1, Python)** : `driver/sepreplay/` = mailbox (mot 64 bits EP/TAG/TYPE/PARAM/DATA),
  `gt.py` (gt_packet_t), `discovery.py`, `xart.py`/`xart_responder.py`, 29 tests offline. C'est la **référence**
  du format fil ; le pilote noyau le réimplémentera.
- **Toute la chaîne SEP prouvée sous m1n1** (à REFAIRE nativement, docs à l'appui) : persist (route native 0x13),
  sbio vivant (0x73), key exchange (0x15/0x16), compteur (0x42/0x18), réception patch (0x5f, 22158 o). Le mur =
  pousser le patch au capteur (voir §4).

## 3. TES PREMIÈRES TÂCHES (mobiles, AUTORISÉES sans nouvelle écriture SEP)
Quand le Mac est booté sous Linux et joignable (`tools/linux_ssh.sh run "uname -a"`), fais, dans l'ordre, et
rends-moi les sorties brutes :

**T1 — État de l'environnement (lecture seule, aucun SEP).** Rapporte :
- `uname -r` ; version linux-asahi.
- `ls /proc/device-tree/soc/ | grep -i spi` ; spi2 (`spi@39b108000`) présent/activé ? `spi-apple` lié ?
  (`dmesg | grep -i spi`, `/sys/bus/spi/devices/`).
- **SIO/DMA** : nœuds `sio` et `dart-sio` présents/activés ? driver `apple-sio` chargé ?
  (`dmesg | grep -iE "sio|dma"`, `/proc/device-tree/.../sio*`, `lsmod | grep -i sio`). ← décisif pour le DMA.
- GPIO : gpio0 196 (alim mesa) et 195 (IRQ) accessibles ?

**T2 — Bring-up capteur (J0), autorisé (capteur = SPI de l'AP, PAS le SEP).**
- Compiler + charger l'overlay spi2 + `mesa_probe` (`driver/linux/README.md` décrit la séquence et le Makefile).
- Confirmer l'identité capteur == celle lue sous macOS :
  `80d4001b00000000700219c05c0fd2aa349a81c76e030200d87576`. Rapporter `dmesg` complet du module.
- **But** : prouver que l'environnement Linux pilote le capteur comme m1n1 le faisait. Zéro ligne rouge.

**T3 — (si T1 montre apple-sio vivant) Sonder le chemin DMA, SANS rien envoyer de sensible.**
- Décrire ce que `apple-sio` expose (canaux dmaengine, `/sys/class/dma/`). Rappel (roadmap §2.1) : `apple-sio`
  **boote** le SIO (≠ m1n1) mais est **cyclique/TX-only** ; `spi-apple` n'est **pas** client dmaengine. L'écart
  « push one-shot 22 Ko » reste à coder. Ta sonde sert à confirmer ces faits sur matériel, pas à pousser un patch.

NE LANCE PAS encore : J2 (boot SEPOS/IMG4), J3 (sbio), J4 (xART/SKS), J5 (patch/match). Ce sont des écritures
SEP de classe neuve → script `pending/` + **go d'Albert**, et l'orchestrateur te fournira les séquences exactes.

## 4. Le mur de fond à connaître (pour ne pas t'épuiser dessus)
- **J4 (xART / Secure Storage Component)** = le vrai verrou. sbio reste muet tant que le xART n'est pas scellé ;
  la fraîcheur anti-rejeu vit dans une puce matérielle séparée accessible seulement par le SEP → rejouer le coffre
  disque est insuffisant par conception. Condition plausible = **état SEP propre natif** (DFU + ré-enrôlement
  macOS = matériel + Albert). `docs/voie_sbio.md` §7, `docs/public_linux_state.md` §H-K.
- **Push patch DMA (J5)** = écart à coder (spi-apple client dmaengine + apple-sio one-shot). `docs/voie_sbio.md` §8.

## 5. Protocole de coordination avec l'orchestrateur (moi)
- Je détiens le protocole SEP (docs/messages.md, sbio_session.md, sbio_keyexchange.md, kext_sepmanager.md) et je
  te passe les **séquences exactes** quand une tâche SEP est débloquée (go Albert + filtre ssh ajusté).
- Tu me renvoies **les sorties brutes** (dmesg, hexdumps, erreurs), pas des conclusions seules. Je tranche
  vérifié/hypothèse avec le sceptique.
- Toute écriture SEP = tu prépares, tu me montres, Albert donne le go, PUIS tu lances. Fail-closed partout.

## 6. Références clés
- `docs/linux_roadmap.md` — la roadmap complète J0→J6 + écarts à coder.
- `docs/public_linux_state.md` — état public SEP/SPI/AOP/capteur sous Linux.
- `docs/driver_plan.md` — plan driver (étapes 0-7), inconnues.
- `docs/voie_sbio.md` §7 (mur xART), §8 (DMA SIO faisabilité).
- `driver/linux/README.md` — modules capteur + Makefile + comment charger.
- `driver/sepreplay/` — transport SEP + format fil (offline, Python), 29 tests.
- `docs/sensor_hw.md` — réglages spi2 (CLKDIV 3, CFG FIFO 0x40002 / DMA 0x40042, SHIFTCFG 0x80c07), états capteur
  (`0x60` sans correctif / `0x29` chargé), broche 195.
