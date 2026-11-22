# Cartographie publique → ROADMAP d'un pilote Linux natif Touch ID (j314c / t6001)

Documentaliste, **2026-11-22**. Objectif stratégique (décision Albert 2026-11-22) : livrable = **pilote Linux
natif** pour Touch ID sur MacBook Pro M1 Max, **sans tether** (plus de PC branché en USB + m1n1-proxy +
power-cycle). m1n1 reste l'**échafaudage de reverse** ; le montage tethered n'est PAS le livrable.

> ⚠️ **AVERTISSEMENT — étude documentaire.** Rien dans ce document n'a été **testé sur matériel**. C'est une
> cartographie des sources **publiques** autorisées, à confronter ensuite à l'expérience. Tout ce qui est « faisable »
> ici est une **lecture de code/doc**, pas une preuve.

## Sources (toutes publiques, autorisées phase 1/2) et dates de lecture
- **linux-asahi**, branche `asahi`, fichiers bruts `raw.githubusercontent.com/AsahiLinux/linux/asahi/...`, **lus le
  2026-11-22** : `drivers/soc/apple/sep.rs`, `drivers/dma/apple-sio.c`, `drivers/spi/spi-apple.c`. (Branche rebasée →
  numéros de ligne indicatifs.)
- **m1n1** : clone local `m1n1/`, lecture seule (interdit d'y écrire, `m1n1/CLAUDE.md`) : `proxyclient/m1n1/hw/sep.py`
  (lu 2026-11-22), `src/kboot.c`, `src/sio.c`, `src/sep.c` (cf. `docs/public_linux_state.md` et `docs/voie_sbio.md` §8).
- **Doc Asahi** : `https://asahilinux.org/docs/platform/feature-support/m1/` (lu 2026-11-22), `.../hw/soc/sep/`,
  `.../platform/security/` (lues antérieurement, cf. `public_linux_state.md`).
- **Nos docs internes** (NON publiques, à garder séparées) : `public_linux_state.md`, `driver_plan.md`,
  `voie_sbio.md` §8, `sensor_hw.md`, `verification_status.md`, `kext_sepmanager.md` (`source: kext`).

Légende : **[public]** = écrit tel quel dans une source publique citée ; **[déduit]** = notre lecture/raisonnement
(hypothèse) ; **[trace]** = vu dans nos captures (pas public) ; **[kext]** = désassemblage (protocole only, pas public).
**inconnu** = non trouvé dans les sources publiques consultées.

---

## 1. SEP sous Linux — le cœur du problème

### 1.1 Portée exacte de `drivers/soc/apple/sep.rs` (downstream uniquement)
- [public, lu 2026-11-22] `compatible = "apple,sep"` (l.332). **Absent du mainline** (confirmé antérieurement,
  `public_linux_state.md` §1.2 ; feature-support « SEP | WIP » pour T600x, §1.4 ci-dessous).
- [public, lu 2026-11-22] **C'est un amorceur, PAS un transport générique.** `process_message` (l.276-283) ne
  dispatche que **deux** endpoints : `EP_BOOT = 0xFF` (l.51, 279) et `EP_DISCOVER = 0xFD` (l.49, 280) ; `EP_SHMEM =
  0xFE` (l.50) sert **uniquement en émission** (`SET_SHMEM`, l.235). **Tout autre endpoint est jeté silencieusement**
  (`_ => {}`, l.281). Aucune trace de 0x08 (sbio), 0x12 (SKS), 0x13 (xART).
- [public, lu 2026-11-22] Le handler de découverte 0xFD (l.263) est **vide** (log commenté). Les sends sont
  **à vocation fixe** : `start()` (l.198-206) → `BOOT_TZ0` ; `load_fw_and_shmem()` (l.225-239) → `BOOT_IMG4` +
  `SET_SHMEM`. La `Mailbox` est **privée** dans un `Mutex<Option<Mailbox<SepData>>>` (l.176) ; **aucune méthode
  publique n'accepte un endpoint arbitraire**. La réception (`recv_message`, l.302-320) file tous les messages mais
  `process_message` n'en traite que 0xFF/0xFD.
- [public] Kconfig `APPLE_SEP` (cf. `public_linux_state.md` §1.2) : « controlling transparent disk encryption, secure
  boot, HDCP, biometric auth and probably more » — c'est une **ambition annoncée**, le code ne fait **que** l'amorçage.

**Réponse à la question « peut-on en dériver un transport ? »**
- [déduit] **Oui en principe, non en l'état.** Les primitives de bas niveau existent (le type `Mailbox<SepData>`
  encode/décode le mot 64 bits EP/TAG/TYPE/PARAM/DATA ; le DART SEP est attaché, cf. 1.3) ; mais il faudrait **ajouter
  du code** : exposer un `send`/`recv` par endpoint arbitraire, gérer les ACK CNTL (EP 0x00), allouer/mapper les
  buffers OOL A/B. Rien de cela n'existe publiquement. Le format fil (mot mailbox, encodage GT `gt_packet_t`,
  carte opcode↔opération EP 0x08) est connu **chez nous** (`messages.md`, `kext_sepmanager.md §13b`, `source: kext` /
  `vérifié (macOS)`), **pas** dans linux-asahi.

### 1.2 Boot de SEPOS sous Linux — que faut-il ?
Résumé du « SEP boot flow » public : [public] (Asahi `hw/soc/sep/`) iBoot **précharge** le firmware SEP dans une
région décrite par l'ADT ; **l'OS** (XNU, ou m1n1/Linux à terme) envoie `boottz0` puis un **IMG4** ; le SEP vérifie et
démarre SEPOS. ⚠️ [public] « sending a malformed or invalid IMG4 is a panic on SEP side ».

Chaîne concrète côté Linux :
1. **DT** : [public] le nœud `sep@396400000` (`t600x-die0.dtsi`) est `status = "disabled"` et **sans alias `sep`** sur
   j314/j316 (`public_linux_state.md` §1.3). Il faut **activer** (`status = "okay"`) **et** ajouter l'alias `sep`.
2. **Fourniture du firmware + manifestes** : [public] m1n1 `src/kboot.c` `dt_set_sep` (commit `62ff43f0`) : **si** le
   FDT a l'alias `sep`, m1n1 réserve la région ADT `SEPFW` (nœud `sep-firmware`, memory-region `sepfw`) et copie les
   manifestes `lpol`→`local-policy-manifest`, `ibot`→`iboot-manifest`. **Sans alias : m1n1 ne fait rien**
   (« sep alias not found in devtree »).
   - [déduit, IMPORTANT pour « sans tether »] `dt_set_sep` s'exécute quand **m1n1 agit comme BOOTLOADER** du FDT Linux,
     **pas** seulement en mode proxy. Donc un **m1n1 installé** (stage 2 `boot.bin`, boot normal d'ALARM, sans USB)
     fournit `sepfw`/manifestes **dès que le DT Linux porte l'alias `sep`**. → **le préchargement du firmware SEP
     n'exige PAS le tether** ; le tether ne sert qu'au reverse. (Lecture combinée kboot.c + tethered-boot ; non testé.)
3. **Amorçage** : [public] le stub `sep.rs` envoie `BOOT_TZ0` (EP 0xFF), attend l'ACK `0x69` puis `0xD2`, charge
   firmware+shmem, envoie `BOOT_IMG4` (EP 0xFF, DATA = IOVA firmware >>12) + `SET_SHMEM` (EP 0xFE, type 0x18), attend
   `0x6A`. Séquence identique à m1n1 `proxyclient/m1n1/hw/sep.py:104-125` (lu 2026-11-22 : `boot()` l.104-127, shmem
   `CINP`/`OPLA`/`IPIS`/`llun` l.86-102).
4. **EP 0xff/0xfe** : [public] c'est la ROM (SEPROM) qui répond `GET_STATUS 0x66`, `0x69`, `0x6A`, `0xD2` ; aucun EP
   « 0xfe/0xfd de boot SEPROM→SEPOS » distinct au-delà de ce que `sep.py`/`sep.rs` montrent. (Contradiction doc↔code sur
   le rôle 0xFE/0xFF : se fier au code, cf. `public_linux_state.md` §5.4.)

⚠️ **LIGNE ROUGE** : envoyer l'**IMG4** au SEP = **écriture SEP d'une classe jamais testée** → script `pending/`,
**go d'Albert** (CLAUDE.md « Écriture SEP »). Un IMG4 invalide **panique** le SEP (doc Asahi).

### 1.3 DART du SEP côté Linux (mapper les OOL / IOVA)
- [public] DT : `sep { iommus = <&sep_dart 0>; }` ; `dart-sep` est `compatible = "apple,t6000-dart"` géré par le
  driver **`drivers/iommu/apple-dart.c` (mainline)**. [trace] l'ADT `dart-sep` déclare `sids = 0x8001` (streams 0 et
  15) et `page-size = 16384` (`voie_sbio.md` §3).
- [déduit] Un transport sbio sous Linux allouerait ses buffers OOL via l'API DMA du **device `sep`** (p.ex.
  `dma_alloc_coherent`) : le framework programme alors le `sep_dart`. Le stub actuel ne mappe **que** le firmware et la
  shmem (via la mailbox RTKit) ; **aucun code public ne mappe d'OOL pour 0x08**. L'IOVA exacte et la question stream 0
  vs 15 : chez nous, l'expérience E1 a **écarté** le canal sid 15 (`voie_sbio.md` §7, [trace], n=1 à reconfirmer).

### 1.4 État de l'upstream / travail biométrique public
- [public, lu 2026-11-22] feature-support M1 : **SEP = « WIP »** (T600x) ; **Touch ID / fingerprint = « TBA »**
  (MacBook Pro 14/16 2021) — « TBA » = travail **pas en cours** ; **SPI = « 6.15 »** (upstream) ; SIO/DMA non listé.
- [public] Seul code SEP public = le **stub `sep.rs`** (downstream, non mainline). **Aucun `AppleSEPManager`-like,
  aucun driver biométrique/mesa, aucun pilote SKS/xART/sbio** trouvé dans linux-asahi ni m1n1 (grep antérieurs,
  `public_linux_state.md` §1.2, §2.2, §3). → **travail biométrique public : non trouvé (inconnu).** Ne pas prétendre
  qu'il en existe un.
- [public] James Calligeros (board Asahi) a dit Touch ID « faisable » mais « extremely involved » ([[touchid-linux-faisable-james]],
  propos de chat 2026-11-19 — pas une source doc). Rien de poussé vers Asahi (projet privé, [[asahi-ban-pas-secret]]).

---

## 2. SIO / DMA SPI — ce qui débloque le mur actuel (push patch ~22 Ko)

**Rappel du mur** [trace/kext] : la livraison du patch capteur (~22 Ko, op 0x5f→0x60) via le **FIFO scruté** (16 mots)
met ~2,2 s et le capteur **refuse** (état reste `0x60`, n'atteint jamais `0x29`) — `voie_sbio.md` §8, `sbio_session.md`.
Sous m1n1, le DMA SIO est **mort faute de driver SIO** (personne ne boote le coprocesseur, `voie_sbio.md` §8.5).

### 2.1 `drivers/dma/apple-sio.c` (linux-asahi) — EXISTE et boote le SIO
- [public, lu 2026-11-22] **C'est un vrai driver dmaengine RTKit.** `compatible = "apple,sio"`. Il **démarre le
  coprocesseur** : `writel(CPU_CONTROL_RUN, base+REG_CPU_CONTROL)`, `devm_apple_rtkit_init(...)`,
  `apple_rtkit_boot(sio->rtk)`, `apple_rtkit_start_ep(sio->rtk, EP_SIO)` avec **`EP_SIO = 0x20`** ; puis
  `sio_call(... MSG_START)` et envoi des paramètres firmware depuis la propriété DT **`apple,sio-firmware-params`**.
  → **C'est LA différence clé avec m1n1** : côté Linux, le SIO **est amené à la vie** ; côté m1n1 non (`voie_sbio.md`
  §8.3). [public] shmem 4 Ko (`dma_alloc_coherent`, IOVA>>12 via `MSG_SETUP`), descripteurs coproc 48 o à l'offset 56,
  64 slots.
- [public, lu 2026-11-22] Enregistre un provider dmaengine : `dma_async_device_register` +
  `of_dma_controller_register(... sio_dma_of_xlate ...)` → canaux exposés **par le DT** (`dma-channels`, max 0x80).
  Direction par **parité de canal** : `(channo & 1) ? DMA_DEV_TO_MEM : DMA_MEM_TO_DEV` (pair = TX mém→périf).
- ⚠️ [public, lu 2026-11-22] **LIMITE MAJEURE pour nous** : le driver n'annonce **que le TX** au niveau device
  (`dma->directions = BIT(DMA_MEM_TO_DEV)`) et **ne fait que du CYCLIQUE** (`device_prep_dma_cyclic`, « All
  transactions are cyclic (DMA_CYCLIC) », ≤ 4 descripteurs en vol). Il est **taillé pour l'audio** (flux cyclique),
  pas pour un **transfert unique (one-shot) de 22 Ko**.
  - [déduit] **inconnu** : savoir si un push one-shot de 22 Ko vers le capteur peut passer par ce chemin cyclique, et
    comment le RX (état/réponse capteur, canal impair) s'articule puisque seul le TX est annoncé. C'est un **écart réel
    à combler**, pas une brique prête.

### 2.2 `drivers/spi/spi-apple.c` — PIO uniquement (pas de client DMA)
- [public, lu 2026-11-22] **Toujours PIO.** Aucun `dmaengine`/`dma_request_chan`, **aucune** propriété
  `dmas`/`dma-names`, FIFO profondeur **16** (`APPLE_SPI_FIFO_DEPTH 16`). `APPLE_SPI_CFG_MODE_DMA = 2` est **défini mais
  jamais utilisé** ; l'init choisit `APPLE_SPI_CFG_MODE_IRQ`. Les transferts passent mot à mot par `APPLE_SPI_TXDATA`/
  `RXDATA` (`apple_spi_tx`/`apple_spi_rx`). Match OF : `apple,t8103-spi`, `apple,spi`.
- [déduit] Donc, **même avec `apple-sio` qui boote le SIO**, `spi-apple` **ne sait pas** router un transfert par DMA :
  il n'est pas client dmaengine. Pour pousser 22 Ko en DMA sur spi2 il faudrait **AJOUTER à `spi-apple`** : (a) le
  binding DT `dmas = <&sio 0x18>, <&sio 0x19>; dma-names = "tx", "rx";` (canaux SIO vus [trace] : 0x18 TX / 0x19 RX,
  `voie_sbio.md` §8.2), (b) le code client dmaengine (`dma_request_chan`, `dmaengine_prep_*`, `dmaengine_submit`), et
  (c) basculer `APPLE_SPI_CFG_MODE_DMA` + maintien du CS. **Rien de tout ça n'existe publiquement** (inconnu/à écrire),
  et il bute sur la limite cyclique de 2.1.

### 2.3 Capteur Mesa en DT — ce qui existe vs ce qu'on doit ajouter
- [public] Le DT linux-asahi **ne décrit ni spi2 ni de nœud mesa/biosensor/fingerprint** (`public_linux_state.md`
  §2.2) ; seul indice : Kconfig `SPI_APPLE` « … or fingerprint sensor ».
- [projet, NON public] Nos overlays `driver/linux/mesa-spi2-overlay.dts` et `t6001-j314c-mesa.dtsi` ajoutent **spi2**
  (`spi@39b108000`, IRQ AIC 1108, `ps_spi2`, `clkref` 24 MHz, pas de CS, CPHA=1) et l'enfant `biosensor,mesa`
  (`spi-max-frequency = 8000000`, `pwr-gpios = gpio0 196`). Statuts : spi2 adresse/IRQ/alim/CPHA/pwr-gpio = **VÉRIFIÉ**
  par MESA-HELLO ([trace], `verification_status.md` SPI-1..4) ; broches pinctrl, type d'IRQ gpio0 195, reset, 1,8 V =
  **inconnu**.
- [déduit] À **ajouter** pour le DMA : `dmas`/`dma-names` pointant les canaux SIO sur le nœud spi2 (dépend de 2.1/2.2),
  et activer le nœud `sio` + `dart-sio` dans le DT (présents dans l'ADT ; état d'activation Linux à vérifier).

---

## 3. ROADMAP ordonnée — « capteur seul en SSH » → « Touch ID sans tether »

Ordre = dépendances réelles. Pour chaque jalon : **À FAIRE**, **Public/faisable vs inconnu**, **RISQUE**,
**LIGNES ROUGES croisées**. Statut de départ repris de `driver_plan.md` (étapes 0-7) et `voie_sbio.md`.

> Tension stratégique à garder en tête : **le capteur (SPI, AP) et le SEP sont deux moitiés**. Linux « parle au
> capteur » **aujourd'hui** (J0), mais le capteur n'est **utile** que piloté par un **SEPOS vivant** qui fournit la clé
> de session, le patch 0x5f, la calibration — et le match. D'où l'ordre : capteur acquis, puis SEPOS, puis sbio, puis
> l'environnement xART/SKS (le vrai mur de fond), puis le relais complet.

### J0 — Capteur seul sous Linux (FAIT, non-tether, sur le Linux de test) ✅
- **État** : [trace/projet] `driver/linux/` (overlay spi2 + `mesa_probe`/`mesa_transport.h`) lit **identité + état** du
  capteur via `spi-apple` PIO, allumage par gpio0 196, sans SEP. `driver_plan.md` étape 3 « faite et vérifiée ».
- **Public/faisable** : [public] `spi-apple` upstream (6.15). **Inconnu** : rien de plus sans SEP.
- **RISQUE** : faible (lecture, AP-side). **LIGNES ROUGES** : aucune (aucun envoi SEP ; capteur = SPI de l'AP).

### J1 — Transport SEP générique (lecture seule) + découverte (hors ligne / lecture)
- **À FAIRE** : écrire la couche transport absente de `sep.rs` : send/recv par EP arbitraire, décodage mot mailbox +
  GT `gt_packet_t`, table découverte 0xFD (nom→EP). Validable **hors ligne** par rejeu des `traces/` (c'est déjà fait
  dans `driver/sepreplay/`, 29 tests, `driver_plan.md` MAJ 2026-11-09).
- **Public/faisable** : format fil = [public partiel] (sep.py/sep.rs) + [kext/vérifié] chez nous. **Inconnu public** :
  l'ouverture CNTL d'un EP, l'allocation OOL via DART SEP (aucun code public).
- **RISQUE** : nul (hors ligne / lecture). **LIGNES ROUGES** : aucune tant qu'on **n'émet pas** vers le SEP.

### J2 — Booter SEPOS sous Linux (DT `sep` okay + IMG4) ⚠️ ÉCRITURE
- **À FAIRE** : DT alias `sep` + `status="okay"` sur j314c ; vérifier que m1n1 installé fournit `sepfw`+manifestes
  (`dt_set_sep`, cf. 1.2 — **non-tether possible**) ; le stub `sep.rs` (ou notre transport) envoie TZ0/IMG4/SHMEM.
- **Public/faisable** : séquence [public] (sep.rs/sep.py). **Inconnu** : état réel du SEP au boot Linux (préchargé par
  iBoot ? cf. `public_linux_state.md` §5), et si SEPOS amorcé par ce stub a bien ses endpoints sans xART/SKS.
- **RISQUE** : **élevé** — IMG4 invalide = **panique SEP** (doc Asahi) ; interaction avec l'état FileVault/trousseau
  macOS. Filet : backup `alarm_p5.img` + DFU.
- **LIGNES ROUGES** : **IMG4 = écriture SEP classe jamais testée → `pending/` + go d'Albert** ; **sur le Linux de test
  `root@10.0.200.4`, tout envoi au SEP est INTERDIT** (CLAUDE.md « Exception 2e Linux ») → ce jalon ne se fait **pas**
  sur le Linux de test, mais via m1n1/`pending/` (reverse) tant que la règle ne change pas.

### J3 — Ouvrir sbio (EP 0x08) et la poignée 0x73 ⚠️ ÉCRITURE
- **À FAIRE** : CNTL (EP 0x00) pour ouvrir 0x08 (buffers A/B 0x4000 via DART SEP), envoyer le 0x73, lire la réponse.
- **Public/faisable** : séquence d'ouverture + format 0x73 = **reproduits octet pour octet** chez nous
  (`voie_sbio.md` §4/§6, [kext/trace]). **Inconnu décisif** : [trace] sous m1n1 le 0x73 reste **muet** ; E1 a écarté le
  canal DART → cause = **l'ÉTAT** (sbio non armé tant que **xART non scellé**, `voie_sbio.md` §7). Donc J3 dépend de J4.
- **RISQUE** : moyen (CNTL + OOL = écritures SEP « route native » déjà éprouvées en partie). **LIGNES ROUGES** :
  écriture SEP → `pending/` ; la classe « ouverture sbio / 0x73 » est proche de « route native » déjà testée, mais
  **tout 1er run neuf = go d'Albert** ; Linux de test interdit.

### J4 — Environnement xART / SKS (EP 0x13 / 0x12) — LE MUR DE FOND
- **À FAIRE** : amener le SEP à **sceller xART** (nécessaire à SKS et, semble-t-il, à l'armement de sbio) et initialiser
  le keystore.
- **Public/faisable** : [public] Asahi dit « 0x13 … needed for SKS to start ». **Inconnu (et probablement bloqué)** :
  [public, guide Apple] la **fraîcheur anti-rejeu vit dans un composant matériel séparé (Secure Storage Component)**,
  accessible **seulement par le SEP** via bus I2C dédié ; **rejouer le coffre disque est insuffisant par conception**
  (`public_linux_state.md` §H-K). [trace] nos essais SERVE_GL → **re-scellement** (SAVE@TAG05). → un **état SEP propre**
  (keybag + enrôlement) obtenu nativement (DFU Restore + ré-enrôlement macOS, matériel/Albert) semble la condition.
- **RISQUE** : **le plus élevé** — [[stockholm-se-brick-definitif]] (puce SE séparée) : acquitter un SAVE fait **avancer
  un compteur scellé** ; DIRECT peut bricker. SKS 0x12 en écriture = jamais testé.
- **LIGNES ROUGES** : **0x12/0x13/0x10/0x15/gigalocker en écriture = `pending/` + go d'Albert** (classe jamais testée) ;
  Linux de test interdit ; derrière un module param désactivé par défaut (`driver_plan.md` §2).

### J5 — Relais capteur complet (init + match) — dépend du DMA 22 Ko
- **À FAIRE** : init capteur `0x17`→`0x15/0x16`→`0x42/0x18`→**`0x5f` (patch ~22 Ko)**→`0x5b` (calibration)→`0x6d`
  (catacomb), puis match `0x23`/`0x06`/`0x65`(image 0x7200)/`0x09`. L'AP **transporte** (chiffré bout en bout
  capteur↔SEP, `driver_plan.md` C-C, [trace vérifié macOS]).
- **Public/faisable** : séquence+tailles = [kext/vérifié macOS] chez nous. **Inconnu/À CODER** : **le push DMA 22 Ko**
  (§2) — `apple-sio` boote le SIO mais est **cyclique/TX-only** ; `spi-apple` n'est **pas** client DMA → **écart réel**.
  Repli PIO = refusé par le capteur [trace]. Provenance du blob `0x5b`, acceptation d'un `0x6d` rejoué = inconnu
  (`driver_plan.md` §5, classe 3).
- **RISQUE** : moyen côté capteur (transport SPI, pas écriture SEP) ; mais **1er run neuf** du bring-up SIO/DMA =
  classe neuve. **LIGNES ROUGES** : transport capteur = pas une écriture SEP, **mais** bring-up SIO neuf → `pending/` +
  go d'Albert (`voie_sbio.md` §8.6/§8.7) ; Linux de test interdit pour la partie SEP.

### J6 — Intégration libfprint / PAM — sans tether
- **À FAIRE** : exposer le verdict (`0x09 +0x00` = uid / −1, `driver_plan.md` C-E) via un nœud noyau + démon userland →
  libfprint/PAM. Boot non-tether : m1n1 installé (bootloader, `dt_set_sep`) + DT à jour.
- **Public/faisable** : interface = **décision d'archi ouverte**, rien de documenté (l'image ne sort jamais du SEP).
  **Inconnu** : mapping multi-uid, enrôlement sous Linux.
- **RISQUE** : faible (userland). **LIGNES ROUGES** : aucune nouvelle ; dépend de J2-J5 franchis.

### Chemin critique (déduit)
J0 ✅ → **J4 (mur xART/SE, le vrai verrou, matériel + Albert)** conditionne J3 (sbio muet tant que xART non scellé) ;
J5 ajoute l'écart **DMA 22 Ko à coder** (spi-apple client dmaengine + apple-sio cyclique→one-shot). J1 est hors-ligne et
peut avancer tout de suite. **« Sans tether » est atteignable pour le BOOT** (m1n1 installé fait `dt_set_sep`), mais le
livrable final reste suspendu au **mur J4** (fraîcheur xART ancrée matériellement, hors AP) et à l'**écart DMA J5**.

---

## 4. Synthèse des écarts « à coder » purement publics (sans toucher au mur SEP)
1. [déduit] **Transport SEP générique** dans `sep.rs` (aujourd'hui amorceur only, mailbox privée) — J1/J3.
2. [déduit] **Client dmaengine dans `spi-apple`** + binding `dmas`/`dma-names` (inexistant, PIO-only) — J5.
3. [déduit] **Mode one-shot** utilisable sur `apple-sio` (aujourd'hui cyclique/TX-only) **ou** repli payload AP — J5.
4. [déduit] **Nœud DT spi2 + mesa** à intégrer proprement (overlays `driver/linux/` → DT) — J5.

Tout le reste (J2 IMG4, J4 xART/SKS) n'est pas « à coder » mais **à décider/tester en écriture SEP = Albert**.

## 5. Contradictions / points à transmettre au sceptique
- **Aucune contradiction doc↔traces nouvelle.** Le public est **muet** sur : le mécanisme de fraîcheur xART, l'état du
  SEP au boot Linux, le protocole sbio/SKS, le DMA capteur. Nos `[trace]`/`[kext]` vont plus loin mais ne sont **pas**
  publics.
- **À NE PAS présenter comme public** : « sbio muet = état/xART » (trace, `voie_sbio.md` §7, n=1 à reconfirmer) ;
  « voie C penche fermée » (trace + guide Apple au niveau conception, pas une preuve) ; les noms d'opérations EP 0x08
  (`source: kext`, hypothèse).
- **Rafraîchissement 2026-11-22** : `apple-sio.c` **existe et boote le SIO** (≠ m1n1) — nuance clé ; mais **cyclique/
  TX-only** → ne règle pas tel quel le push 22 Ko. `spi-apple.c` reste **PIO-only**. `sep.rs` reste un **amorceur**
  (pas de transport générique). SEP = WIP, Touch ID = TBA côté Asahi.
