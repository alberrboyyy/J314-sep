# DMA SIO pour spi2 (capteur Mesa) — étude et conception (roadmap J5, « mur DMA »)

Statut : **étude en lecture seule + brouillon de patch NON appliqué, NON compilé, NON testé** (2026-11-22, agent).
Rien n'a été chargé, compilé, envoyé au SEP ni au capteur ; `~/kbuild/src` n'a pas été modifié (copies dans le
scratchpad). Le patch : `driver/linux/patches/0001-spi-apple-dmaengine-draft.patch` (applique proprement en
`patch -p1 --dry-run` sur une copie de l'arbre `asahi-7.2.12-3`).

Conventions : **[public]** = code/DT public (arbre `~/kbuild/src/linux-asahi-7.2.12-3`, m1n1 public) ;
**[projet]** = nos traces/docs/DT vivant ; **[déduit]** = raisonnement, non vérifié par une expérience.
Chemins courts : `sio.c` = `drivers/dma/apple-sio.c`, `spi-apple.c` = `drivers/spi/spi-apple.c`,
`C19` = `traces/20261110-002829_c19-spi-dma-boot/` (boot macOS sous hv, observation seule).

---

## 0. Verdict court

- **Faisable, et plus proche qu'on ne le pensait.** Le SIO est déjà booté par Linux [projet : dmesg « SIO protocol v9 »],
  il reçoit **le même jeu de paramètres firmware que sous macOS** (dont le `dmashim` SPI `SSPI` et `device-type` `dSPI`)
  [public + projet, §1.1], et le **format de descripteur Linux est identique** à celui que macOS utilise sur les canaux
  0x18/0x19 [projet + déduit, §1.2]. Il manque deux morceaux de code, petits :
  1. `apple-sio` : un **`device_prep_slave_sg` one-shot** (~60 lignes) — aujourd'hui cyclique seulement ;
  2. `spi-apple` (ou un fork hors arbre) : un **chemin `transfer_one` DMA, TX seul** (~150 lignes), qui rejoue la
     séquence de registres que macOS fait sur spi2 (relevée dans C19, §1.6).
- **La séquence macOS pour le patch 22 Ko est minimale et entièrement VUE** [projet, C19] : `ISSUE` canal 0x18 avec
  **un seul descripteur de 0x568e octets**, ACK, puis **un seul `REPORT` ~23 ms plus tard** (= 22158 o × 8 bits à
  8 MHz). Pas de RX, pas de `TERMINATE`. Le slave_sg proposé reproduit exactement ce trafic.
- **Chemin recommandé : tout hors arbre, rien d'intégré touché** (§3) : un fork `spi_apple_dma.ko` lié à spi2 par un
  `compatible` propre à notre overlay (le `spi-apple` intégré, qui sert le clavier sur spi3, reste intact) + un fork
  `apple_sio_draft.ko` chargé à la place du module `apple_sio` (blacklist + redémarrage par Albert). Pas de noyau custom.
- **Test bon marché à faire AVANT tout DMA (voie 0, §3.4)** : pousser le patch par le **PIO du noyau** (le `spi-apple`
  actuel). Le mur des 2,2 s venait surtout des allers-retours du tunnel m1n1 ; dans le noyau, le même PIO devrait
  durer quelques dizaines de ms [déduit, non mesuré]. Si le capteur l'accepte, le DMA n'est plus sur le chemin critique.

---

## 1. Ce que `apple-sio` supporte aujourd'hui

### 1.1 Boot et protocole RTKit (endpoint 0x20)

- [public] Format de message : `EP` bits 0-7 (= n° de canal), `TAG` bits 8-13, `TYPE` 16-23, `PARAM` 24-31, `DATA` 32-63
  (`sio.c:30-34`) ; endpoint RTKit applicatif `EP_SIO = 0x20` (`sio.c:36`).
- [public] Types : `START 2`, `SETUP 3`, `CONFIGURE 5`, `ISSUE 6`, `TERMINATE 8` (AP→SIO) ; `ACK 0x65`, `NACK 0x66`,
  `STARTED 0x67`, `REPORT 0x68` (SIO→AP) (`sio.c:38-46`). Tags 1..15 alloués globalement (`sio.c:105`, `163-191`) ;
  appels bloquants `sio_call` (timeout 100 ms, `sio.c:605-625`) ou « atomiques » avec callback d'ACK (`sio.c:567-603`).
- [public] Probe (`sio.c:784-898`) : `CPU_CONTROL_RUN` (`:859`), `apple_rtkit_boot` (`:861`), `start_ep(0x20)` (`:865`),
  `MSG_START` (`:869`), puis les paires clé/valeur de `apple,sio-firmware-params` en `SETUP` (`PARAM = clé & 0xff`,
  `EP = clé >> 8`, `sio.c:744-782`), puis la shmem de 4 Ko (`SETUP` param 1 = IOVA>>12, param 2 = taille,
  `sio.c:707-742`).
- [public] Les paramètres sont fabriqués par m1n1 depuis l'ADT (`m1n1/src/sio.c:94-133`, `kboot.c:2370-2424`) :
  tunables, panic buffer, `map-range`, **`dmashim` (clés `SSPI`, `SUAR`, `SAUD`, `ADMA`, `AAUD`)** et **`device-type`
  (`dSPI`, `dUAR`, …)**. Autrement dit le firmware SIO **reçoit la description des périphériques SPI** : c'est lui, pas
  le pilote AP, qui connaît l'adresse du FIFO SPI (le `dst_addr` dmaengine n'est jamais lu, `sio.c:632-705`) [déduit].
- [projet] Comparaison **macOS (C19 `sio.log:54-85`) vs Linux (DT vivant `apple,sio-firmware-params`, lu 2026-11-22)** :

  | clé | macOS (valeur) | Linux (valeur) | rôle (m1n1) |
  |---|---|---|---|
  | 0x0f / 0x10 | 0x358 / 0x1e000 | 0x34 / 0x1e000 | panic buffer |
  | 0x1a / 0x1b | 0x37c / 0x40 | 0x58 / 0x40 | map-range |
  | 0x1e / 0x1f | 0x384 / 0x30 | 0x30 / 0x30 | tunables |
  | 0x22 / 0x23 | 0x38c / 0xa0 | 0x59 / 0xa0 | **dmashim (dont SSPI)** |
  | 0x1c / 0x1d | 0x394 / 0x40 | 0x5a / 0x40 | **device-type (dont dSPI)** |
  | 0x30d / 0x30e (EP=3) | 0x39c / 0x4000 | 0x54 / 0x4000 | « unk 030d » |
  | 0x0b / 0x0c | 0x3b0 / 0x1b80 | 0x31 / 0x1b80 | « unk 000b » |
  | shmem 1 / 2 | 0x3a4 / **0xaaa** | IOVA / **0x1000** | bloc de contrôle |

  Mêmes clés, mêmes tailles ; seules les IOVA (pages) diffèrent, plus la taille déclarée de la shmem (0xaaa vs 0x1000).
  Les « PARAM 0xd/0xe = région capteur » de `voie_sbio.md` §8.4 sont en fait la clé **0x30d/0x30e** de m1n1 (EP=3),
  que Linux envoie aussi [déduit, recoupement].

### 1.2 Ce qui est exposé à dmaengine

- [public] `dma-channels = <128>`, `#dma-cells = <1>` (`t600x-dieX.dtsi:366-376`, activé par
  `t600x-j314-j316.dtsi:140-143`) ; un client demande un canal par **`dmas = <&sio N>`** (xlate `sio.c:473-483`,
  `dma_get_slave_channel` = exclusif). Sous ALARM le phandle numérique du nœud `sio` vaut **0x38** [projet, lu
  `/proc/device-tree/soc/sio@39bc00000/phandle`]. Seuls consommateurs dans le DT public : dpaudio (`0x64..0x6c`) ; aucun
  driver dpaudio n'est lié ici, **aucun canal en usage** (`/sys/class/dma/dma2chan*/in_use` = 0) [projet].
- [public] Direction **fixée par la parité** du canal : pair = MEM_TO_DEV, impair = DEV_TO_MEM (`sio.c:238-242`), donc
  0x18 = TX, 0x19 = RX, cohérent avec C19. Mais le device n'annonce que `BIT(DMA_MEM_TO_DEV)` (`sio.c:842`) et pas de
  `src_addr_widths` → un client RX qui vérifie `dma_get_slave_caps` serait refusé.
- [public] **Cyclique seulement** : `DMA_CYCLIC` + `device_prep_dma_cyclic` (`sio.c:830-839`, commentaire `:52-68`). Pas
  de `device_prep_slave_sg`, pas de `DMA_SLAVE`.
- [public] Descripteur coprocesseur 48 o : `{u32 pad1; u32 flag(=1); u64 unk; u64 iova; u64 size; u64 pad2, pad3}`
  (`sio.c:71-80`, `flag=1` « not sure », `:286`) ; 64 slots dans la shmem à partir de l'offset 56 (`:50`, `:717`) ;
  `ISSUE.DATA = index × 4` (`:233-236`). En vol : **au plus 4 descripteurs par canal** (`SIO_MAX_NINFLIGHT`, `:69`,
  `:368`). Fin d'un descripteur = `REPORT` (`:550-555`, `:492-507`).
- [projet + déduit] **Même format que macOS** : notre traceur lit le descripteur à `shmem + 0x40 + DATA×0xc`, pointeur à
  +8, taille à +0x10 (`sensor_hw.md` §transport). Avec le layout Linux, le champ `iova` du slot *i* est à
  `56 + 48i + 16 = 0x48 + 12×(4i)` = `0x40 + DATA×0xc + 8` pour `DATA = 4i` : **identique**. macOS utilise DATA 0 et 8
  (slots 0 et 2) [projet C19 `sio.log:90,93`].

### 1.3 Configuration de canal

- [public] `device_config` écrit `{datashape, timeout=0, fifo=0x800, threshold=0x800, limit=0x800}` à l'offset 0 de la
  shmem puis `CONFIGURE` (DATA=0) sur le canal (`sio.c:632-705`, valeurs en dur `:656-659`) ; configuration **une seule
  fois par canal** (`:685-686`). `datashape` dérive de `dst_addr_width` (1 o → 0).
- [projet] macOS envoie aussi `CONFIGURE` DATA=0 sur 0x18 puis 0x19, une seule fois au boot (C19 `sio.log:86-89`, ACK
  DATA=5). **On ne connaît pas le contenu de la shmem qu'il a écrit** (le traceur ne l'a pas lu) : les valeurs 0x800 sont
  celles de l'audio. **C'est le principal inconnu du chemin SIO** (§6 Q1).

### 1.4 Un transfert one-shot (22 Ko) est-il faisable ?

- **Avec le cyclique actuel : non, pas proprement** [public + déduit]. Sur ACK d'un `ISSUE`, le pilote avance `next`
  **modulo `nperiods`** et réémet aussitôt (`sio.c:353-355`) jusqu'à 4 en vol ; avec 1 période il réémettrait **le même
  slot** jusqu'à 4 fois, avec N périodes il reboucle sur la période 0 dès le 1er `REPORT`. Le fil resterait borné par
  `TXCNT` côté SPI, mais il faudrait finir par `TERMINATE` — message que **macOS n'envoie jamais** sur 0x18/0x19 (0
  occurrence de TYPE 0x08 ou 0x66 dans C19) : séquence jamais observée → rejeté comme voie principale (gardé en repli,
  §3.3).
- **Avec un `device_prep_slave_sg` : oui** [déduit]. Ce qu'il faut (fait dans le patch, §4) :
  1. `prep_slave_sg` : un descripteur par entrée de scatterlist (`flag=1`, `iova=sg_dma_address`, `size=sg_dma_len`),
     borne `SIO_MAX_SG = 16` (les 64 slots sont partagés entre canaux) ;
  2. un drapeau `cyclic` dans `struct sio_tx` : pas de modulo à l'ACK, `fill_in` s'arrête à la dernière entrée ;
  3. dans `sio_process_report` : compter les `REPORT` ; au dernier, `vchan_cookie_complete` (callback client),
     `current_tx = NULL`, démarrer la transaction suivante ;
  4. annoncer `DMA_SLAVE` et `DMA_DEV_TO_MEM` (+ `src_addr_widths`) ;
  5. `sio_synchronize` doit aussi faire `vchan_synchronize` (les callbacks one-shot passent par la tasklet vchan).
  Aucun nouveau message RTKit : `ISSUE`/`ACK`/`REPORT` seulement, exactement le trafic VU sous macOS.

### 1.5 Défauts latents relevés dans `apple-sio` [public, déduit]

- `desc_allocated = devm_kzalloc(dev, SIO_NO_DESC_SLOTS / 32)` = **2 octets** pour un bitmap de 64 bits manipulé en
  `unsigned long` (`sio.c:718-719`) : débordement silencieux (masqué par l'arrondi de l'allocateur). Corrigé dans le patch.
- `sio_remove` (`sio.c:900-906`) n'arrête pas le coprocesseur et ne libère pas la shmem (`dma_alloc_coherent` sans
  libération) ; `sio_probe` attend le HELLO RTKit (`apple_rtkit_boot`, `drivers/soc/apple/rtkit.c:815-837`) qu'un SIO
  déjà démarré ne renverra pas → **décharger puis recharger `apple_sio` laisserait très probablement le SIO
  inutilisable jusqu'au redémarrage**. Conséquence directe sur le plan de test (§3.2).

### 1.6 Ce que macOS fait réellement sur spi2 (C19) [projet, VU]

Patch 1re passe (`sio.log:854-858`, `spi2.log:820-850`) :

```
SIO  > EP=0x18 TYPE=6 (ISSUE) DATA=0          ; descripteur ptr=0x3d2000 size=0x568e
SIO  < EP=0x18 TYPE=0x65 (ACK) DATA=6
spi2 W RXCNT(0x34)=0  W TXCNT(0x4c)=0x568e  W CLKDIV(0x30)=3  W WORD_DELAY(0x38)=0
     W STATUS(0x08)=0x400023  W CFG(0x04)=0x40042  SHIFTCFG(0x150) relu/réécrit 0x80c07
     W DELAY_PRE/POST=0  W CTRL(0x00)=0xd   (RUN|TX_RESET|RX_RESET)
SIO  < EP=0x18 TYPE=0x68 (REPORT) PARAM=0x80 DATA=0x568e     ; ~23 ms après l'ACK
spi2 R FIFOSTAT=0x100000 (RX vide, TX niveau 0)  R STATUS=0x400000  W CFG=0x40002  W CTRL=0
```

- Avant chaque transfert : `CTRL=0`, `PIN=0` (CS interne bas tout le long), `STATUS=0x400023`.
- **TX seul ⇒ seul le canal 0x18 sert** (idem pour 0x78/0x70/0x13, 7-11 o) ; TX+RX (état 0x10) : `ISSUE` 0x19 **avant**
  0x18, puis deux `REPORT` (`sio.log:90-97`).
- `CFG 0x40042` = CPHA + MODE=2 (DMA) + champ FIFO_THRESH (bits 17-18) = 2 ; au repos `0x40002` (MODE=0). Aucune écriture
  de `IE_XFER`/`IE_FIFO` (0x130/0x138) : la fin est signalée par le `REPORT` SIO, pas par une IRQ SPI.
- La 2e passe (28878 o, `sio.log:1115-1118`) suit le même motif. macOS se sert aussi des canaux 0x1a/0x1b (transferts de
  0x100 o, autre périphérique, non identifié).

---

## 2. Ce qu'il faut à `spi-apple` pour devenir client dmaengine

État [public] : PIO pur (`spi-apple.c:357-455`), FIFO 16 (`:109`), `CFG_MODE_DMA = 2` défini mais inutilisé (`:28-31`),
init en `MODE_IRQ` + `FIFO_THRESH_8B` (`:159-162`), CS par le bit `PIN_CS` (`:189-194`), aucun `dmas`.

| Point | Ce qu'on fait (patch) | Base |
|---|---|---|
| Binding DT | `dmas = <&sio 0x18>, <&sio 0x19>; dma-names = "tx", "rx";` sur le nœud spi2 (overlay : `<0x38 0x18>, <0x38 0x19>`). Le patch ne prend que `"tx"` ; `"rx"` est décrit pour plus tard. | [projet] canaux C19 |
| Demande de canal | `dma_request_chan(dev, "tx")` au probe ; `-EPROBE_DEFER` propagé (apple_sio est un module), toute autre erreur = PIO seul ⇒ spi1/spi3 inchangés. `dmaengine_slave_config` 1 o. | [public] motif pl022 `spi-pl022.c:1040-1054` |
| `can_dma` | vrai seulement si `dma_tx` && TX seul && 8 bits && `len >= dma_min` (param, 256 par défaut). | [déduit] |
| Mapping | fait par le cœur SPI avec `ctlr->dma_tx->device->dev` = le device SIO, donc dans le DART SIO (`spi.c:1236-1300`). Un tampon `kmalloc` de 22 Ko donne **1 seule entrée sg** (segment max 64 Ko par défaut, `spi.c:1157-1159`) ; un tampon `vmalloc` serait coupé par page (16 Ko). Le patch **refuse** un transfert à plusieurs entrées (fail-closed : un seul burst comme macOS). | [public] + [déduit] |
| `transfer_one` | `spi_xfer_is_dma_mapped()` (`drivers/spi/internals.h:43-49`) ⇒ chemin DMA : préparer + soumettre le descripteur SIO **d'abord** (comme macOS), puis `RXCNT=0`, `TXCNT=len`, `STATUS=0x400023`, `CFG` MODE=DMA + FIFO_THRESH=2, `CTRL=0xd` ; attendre le callback (timeout = 2× temps fil + 200 ms) ; puis attendre `FIFOSTAT.LEVEL_TX == 0` (≤ 1 ms) + 2 temps-octet ; remettre `CFG` en MODE_IRQ/THRESH_8B, `CTRL=0`. Timeout ⇒ `dmaengine_terminate_sync`. | [projet] C19 + [déduit] |
| Repli PIO | si `prep_slave_sg` échoue (rien n'a touché le fil) : `SPI_TRANS_FAIL_NO_START` ⇒ le cœur refait en PIO (`spi.c:1636-1647`). **Attention pour Mesa** : un repli silencieux renverrait au PIO ; le client doit vérifier le log (§5). | [public] |
| CS | inchangé : le cœur appelle `set_cs` une fois par message ; `PIN=0` pendant tout le transfert, comme macOS (pas de broche CS câblée sur spi2, `driver/linux/README.md` §Chip-select). | [projet] |
| SHIFTCFG | le patch ne touche que le champ BITS (`apple_spi_prep_transfer`, `:196-216`) ; macOS a `0x80c07` (bit 2 non documenté). Valeur sous Linux **non relue** (§6 Q4). | [projet] |

Comparaison rapide [public, de mémoire des pilotes amont — à relire si on s'en inspire] : **spi-pl022** et **spi-imx**
demandent `"tx"/"rx"` par `dma_request_chan`, retombent en PIO si absents, `can_dma` = « plus long que le FIFO »,
`prep_slave_sg` sur `tx_sg/rx_sg` du cœur, callback → `complete()`, `issue_pending` puis attente bornée ; **spi-s3c64xx**
bascule des bits DMA dans son registre de mode (équivalent de notre `CFG.MODE`). Spécificité Apple : **pas d'adresse
FIFO à donner au DMA** (le firmware SIO la connaît via `dmashim`) et **RX/TX sur deux canaux distincts** qu'il faut
amorcer RX d'abord.

---

## 3. Hors arbre d'abord, ou patcher l'intégré ?

### 3.1 Faits de configuration [public/projet]

- `CONFIG_SPI_APPLE=y` (intégré, `.config:3566`) — **il sert le clavier et le trackpad internes** (spi3,
  `39b10c000.spi`, dmesg) : le casser = plus de clavier.
- `CONFIG_APPLE_SIO=m` (`.config:6979`, `/lib/modules/7.2.12-3-1-ARCH/kernel/drivers/dma/apple-sio.ko`), chargé,
  refcount 0. `CONFIG_DMA_VIRTUAL_CHANNELS=y` (helpers `vchan_*` exportés), `CONFIG_MODULE_SIG` absent (un module hors
  arbre se charge, noyau marqué « tainted »).
- Initramfs : `MODULES=(appledrm)` (mkinitcpio) ; présence d'`apple-sio` dans l'initramfs **non vérifiée** (§6 Q6).

### 3.2 Options

| Option | Ce qu'on touche | Pour | Contre |
|---|---|---|---|
| **A. Noyau custom** (patch appliqué, `driver/kernel/`) | noyau entier, chaîne de boot | propre, c'est la cible finale | installer un noyau = action d'Albert sur la partition principale ; bug dans `spi-apple` ⇒ clavier perdu |
| **B. Tout hors arbre (RECOMMANDÉ)** : `spi_apple_dma.ko` (fork de `spi-apple.c` + patch, `compatible = "sep-touchid,spi-apple-dma"`) + `apple_sio_draft.ko` (fork de `apple-sio.c` + patch) | un fichier `/etc/modprobe.d/` (blacklist `apple_sio`) + un redémarrage ; overlay avec le nouveau `compatible` + `dmas` | `spi-apple` intégré intact (clavier sûr) ; aucun noyau installé ; réversible (supprimer le fichier, redémarrer) ; le fork SIO est le **premier** à booter le coprocesseur, comme aujourd'hui | perd l'audio DisplayPort tant que le blacklist est en place (sans usage ici) ; le fork SIO doit compiler hors arbre avec `-I drivers/dma` (en-têtes privés `dmaengine.h`, `virt-dma.h`, disponibles dans `~/kbuild`) |
| **C. SPI hors arbre + SIO d'origine, en détournant le cyclique** | overlay + 1 module | pas de blacklist, pas de reboot | séquence `ISSUE` en boucle + `TERMINATE` **jamais vue** côté firmware sur un canal SPI (§1.4) ; résidu dans le FIFO ; fragile |
| D. Remplacer `apple_sio` à chaud (rmmod/insmod) | — | — | **à exclure** : re-probe d'un SIO déjà démarré ⇒ pas de HELLO ⇒ SIO mort jusqu'au reboot (§1.5) |

Pourquoi un `compatible` propre : le nœud spi2 est **créé par notre overlay** ; s'il ne contient pas `apple,spi`, le
`spi-apple` intégré ne s'y lie jamais et notre fork le prend, enfant `biosensor,mesa` compris (aucun changement dans
`mesa_transport.h`). Copier le code **Linux** (GPL) dans un fork n'enfreint aucune ligne rouge (ce n'est pas du code
Apple) ; les valeurs de registres viennent de nos traces.

### 3.3 Recommandation

**B**, avec **C** en repli seulement si Albert refuse le blacklist/reboot. A plus tard, quand le chemin est vérifié
(le patch est écrit pour l'arbre, donc A = appliquer le même diff).

### 3.4 Voie 0 (avant tout DMA) : le PIO du noyau

[déduit, non mesuré] À 8 MHz, 22158 o = ~22 ms de fil. `spi-apple` actuel passe en mode IRQ (seuil `200000×8×8 >
8 MHz`, `spi-apple.c:208-215`) avec réveil tous les 8 octets : des trous de quelques µs à quelques dizaines de µs, total
estimé dizaines à ~200 ms, **CS tenu** (un seul message) — contre 2,2 s via le tunnel m1n1. Ça teste l'hypothèse (A)
« le capteur veut un flux rapide » (`sbio_session.md` §3b (A), source: kext) **sans aucun nouveau code SIO**. Si le
capteur passe à `0x29`, le DMA devient une optimisation. Prérequis commun à tout test du patch : la relève sbio
(`0x5f`) doit tourner sous Linux (J3), car le bloc est frais et non rejouable (`sbio_session.md` §3, §5).

---

## 4. Le brouillon de patch

Fichier : `driver/linux/patches/0001-spi-apple-dmaengine-draft.patch` (en-tête « DRAFT — not compiled, not tested,
never upstream »). Contenu :

- `apple-sio.c` : `sio_prep_slave_sg` (descripteur remis à zéro avant usage, les slots sont réutilisés), drapeau
  `cyclic` + compteur `ndone`, fin one-shot dans `sio_process_report`, `residue` one-shot dans `sio_tx_status`,
  `DMA_SLAVE`/`DMA_DEV_TO_MEM`/`src_addr_widths`, `vchan_synchronize`, correctif `desc_allocated`. Chemin cyclique
  inchangé en comportement.
- `spi-apple.c` : `apple_spi_request_dma` (optionnel), `apple_spi_can_dma`, `apple_spi_transfer_one_dma`, paramètre
  `dma_min`, constante `APPLE_SPI_STATUS_CLEAR_DMA = 0x400023` (valeur C19).

Pour la voie B, dériver les forks **à partir du même diff** : `spi-apple.c` → `spi_apple_dma.c` (changer seulement
`of_match` en `"sep-touchid,spi-apple-dma"`, le nom du driver, et copier `drivers/spi/internals.h` ou remplacer
`spi_xfer_is_dma_mapped()` par `t->tx_sg_mapped`) ; `apple-sio.c` → `apple_sio_draft.c` (`ccflags-y += -I<arbre>/drivers/dma`).
Overlay DMA : copie de `mesa-spi2-overlay.dts` avec `compatible = "sep-touchid,spi-apple-dma";` et
`dmas = <0x38 0x18>, <0x38 0x19>; dma-names = "tx", "rx";` — `mesa_ovl.c` charge un nom fixe (`mesa-spi2.dtbo`,
`mesa_ovl.c:47`) : il faudra un paramètre de nom de fichier ou un 2e dtbo.

Côté client Mesa : le bloc patch doit être dans un tampon `kmalloc` (pas pile, pas `vmalloc`), envoyé en **un seul
`spi_transfer` TX seul** après le prélude 7 o (`sbio_session.md` §3b Q1). `mesa_dev` est déjà `devm_kzalloc`
(`mesa_probe.c:85`).

---

## 5. Risques pour la partition principale et plan de test fail-safe

### 5.1 Risques [déduit sauf mention]

- **Oops/panic d'un module brouillon** ⇒ machine figée, redémarrage forcé ; données non synchronisées perdues. Disque LUKS
  + btrfs (`/proc/cmdline`) : `sync` avant chaque essai, rien d'autre en cours ; snapshot d'Albert = filet fichiers.
- **DMA hors cible** : le SIO est derrière son DART (`iommus`, groupe IOMMU 11 dans dmesg) ⇒ un mauvais descripteur
  donne une faute DART, pas une écriture RAM arbitraire. TX = le SIO **lit** la RAM, n'y écrit pas.
- **Crash du firmware SIO** : `sio_rtk_crashed` ne fait que journaliser (`sio.c:485-490`) ; perte = audio DP + nos essais
  jusqu'au reboot. Aucun lien avec le SEP.
- **Clavier/trackpad** : non touchés en voie B (`spi-apple` intégré intact). En voie A, un bug les casserait.
- **Capteur** : le patch est rechargé à chaque mise sous tension dans C19 (2 passes) ⇒ volatile ; les trames des tests
  T3 sont celles que macOS envoie en DMA. Pas d'écriture capteur hors protocole.
- **SEP** : aucun message SEP dans T1-T3. T4 passe par la relève sbio ⇒ règles SEP propres (go d'Albert si classe neuve).
  Jamais le Secure Element « Stockholm ».
- **Blacklist oublié** : seulement l'audio DP perdu ; retrait = supprimer le fichier + reboot.

### 5.2 Plan (chaque 1er run = « go » d'Albert ; arrêt à la 1re incohérence)

| Étape | Quoi | Succès | Échec ⇒ |
|---|---|---|---|
| T0 (autonome) | compiler les deux forks hors arbre sur ALARM, `W=1`, **sans charger** ; relecture par le sceptique | 0 erreur/avertissement | corriger |
| T1 (go) | voie 0 si la relève sbio existe : patch par PIO noyau | état `0x29` | continuer vers DMA |
| T2 (go + reboot Albert) | `/etc/modprobe.d/` blacklist `apple_sio`, reboot, `insmod apple_sio_draft.ko` | dmesg « SIO protocol v9 », 128 canaux, aucun NACK | retirer le blacklist, reboot |
| T3a (go) | overlay DMA + `insmod spi_apple_dma.ko dma_min=100000` (DMA jamais utilisé) puis `mesa_probe enable=1` | identité identique (régression PIO du fork) | `rmmod`, reboot |
| T3b (go) | même chose avec `dma_min=7` : 0x78, 0x70, 0x13 (TX seul, 7-11 o) passent en DMA ; les lectures restent PIO | log « TX DMA via dma2chan24 », identité identique, aucun « no SIO report » | `rmmod`, reboot ; noter l'état |
| T4 (go) | dans la session sbio : prélude PIO + bloc patch en DMA | `REPORT` de `len` octets, état `29…7c` | noter, ne pas réessayer en boucle |

---

## 6. Questions ouvertes

1. **Config de canal SPI** (`datashape/timeout/fifo/threshold/limit`) écrite par macOS avant `CONFIGURE` 0x18/0x19 :
   inconnue (Linux met 0x800 partout, valeurs audio). Expérience lecture seule possible : capture hv qui lit la shmem
   SIO (IOVA `0x3a4000`, offset 0, 20 o) au moment du `CONFIGURE` 0x18 ; ou décompilation AppleSIO/AppleSPIMC
   (`source: kext`).
2. **Bits 5 et 22 de `STATUS`** (0x400023) et **bit de fin côté SPI en mode DMA** : après TX seul, macOS lit
   `STATUS=0x400000` (pas de `TXCOMPLETE` bit 2) ; le patch se fie au `REPORT` + `FIFOSTAT`. À confirmer.
3. **Descripteur `flag=1` / `unk`** : sens inconnu ; macOS les a-t-il identiques ? (relire un descripteur C19 en entier).
4. **SHIFTCFG sous Linux** vs `0x80c07` macOS (bit 2 inconnu), et `FIFO_THRESH=2` exact en DMA : relecture registre
   spi2 sous Linux (lecture seule, à cadrer : accès MMIO).
5. **Taille max d'un descripteur** : 0x70ce vu ; pas de limite connue au-delà.
6. `apple-sio` est-il dans l'initramfs (le blacklist dans `/etc` suffirait-il sans régénérer l'initramfs) ? Vérifier avec
   `lsinitcpio` avant T2.
7. macOS déclare une shmem de **0xaaa** octets, Linux **0x1000** : sans effet visible (le SIO démarre), à garder en tête.
8. Les canaux 0x1a/0x1b (0x100 o, C19) : quel périphérique ? (sans impact sur spi2).
9. Ordre des `REPORT` avec plusieurs descripteurs one-shot en vol : jamais observé (macOS : 1 descripteur par
   transfert) ; le patch suppose l'ordre d'émission.

## Sources

- Code [public] : `drivers/dma/apple-sio.c` (lignes citées), `drivers/spi/spi-apple.c`, `drivers/spi/spi.c`
  (1133-1162, 1236-1300, 1636-1647), `drivers/spi/internals.h:43-49`, `include/linux/dmaengine.h:933-936, 977-989`,
  `drivers/soc/apple/rtkit.c:815-837, 942-954`, `arch/arm64/boot/dts/apple/t600x-dieX.dtsi:309-376`,
  `t600x-j314-j316.dtsi:140-143`, `.config` (3566, 6973-6979, 870) de `~/kbuild/src/linux-asahi-7.2.12-3` ;
  `m1n1/src/sio.c:75-133`, `m1n1/src/kboot.c:2370-2424`.
- [projet] : `traces/20261110-002829_c19-spi-dma-boot/{sio.log,spi2.log}` (lecture seule) ; DT vivant
  `/proc/device-tree/soc/sio@39bc00000` ; `docs/voie_sbio.md` §8, `docs/sensor_hw.md` §transport,
  `docs/sbio_session.md` §3, §3b (source: kext), §4, §5, `docs/linux_roadmap.md` §2, J5 ; `driver/linux/README.md`,
  `mesa_transport.h`, `mesa-spi2-overlay.dts`, `mesa_ovl.c`, `mesa_probe.c`.
