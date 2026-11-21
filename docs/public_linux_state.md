# État public côté Linux : SEP, SPI, AOP, capteur Touch ID (mesa)

Documentaliste, lu le **2026-11-08**. Sources :
- m1n1 : clone local `m1n1/`, commit `70757dc7` (2026-11-04).
- linux-asahi : branche `asahi` de github.com/AsahiLinux/linux, fichiers bruts lus via raw.githubusercontent.com
  le 2026-11-08 (hash non relevé ; branche rebasée, les dates de commit GitHub sont des dates de rebase).
- Mainline : github.com/torvalds/linux `master` (7.4-rc1) pour savoir ce qui est upstream.
- Doc Asahi : asahilinux.org/docs (pages citées plus bas).

Légende : **[public]** = écrit tel quel dans la source citée ; **[déduit]** = notre lecture, à traiter comme
hypothèse ; **[trace]** = vu dans nos captures (pas une source publique).

---

## 1. SEP sous Linux

### 1.1 Qui démarre SEPOS
- [public] Asahi, https://asahilinux.org/docs/hw/soc/sep/ section « SEP boot flow » : iBoot précharge le firmware SEP
  dans une région mémoire décrite par l'ADT ; **XNU** envoie boottz0 puis un IMG4 ; le SEP le vérifie et démarre
  SEPOS. Avertissement : « sending a malformed or invalid IMG4 is a panic on SEP side ». Puis configuration des
  endpoints (xART/gigalocker, SKS).
- [public] Même page : la partie utile à Linux est « really just the communication protocol between AP and SEP ».
  La page ne parle ni de m1n1 ni de l'état du SEP au démarrage de Linux.
- [public] m1n1 `src/sep.c:14-17,32-67` : m1n1 parle au **SEPROM** (EP `0xff`, type 16 GETRAND → réponse 116) pour
  obtenir de l'aléa ; `src/main.c:187` appelle `sep_init()` ; `src/kboot.c:108-126` (`dt_set_rng_seed_sep`) remplit
  `kaslr-seed`/`rng-seed` du FDT par ce biais (commit `0a1a9348`, 2022-03-18 : « kboot: try SEPROM for the random
  seeds first »).
- [public] Commit m1n1 `6afe9eba` (Sven Peter, 2021-07-01) : « Bootstrapping SEPOS requires to setup a scratch buffer
  and will have to be handled by the final OS. » Revert `68c1f1c1` (marcan) : le firmware doit passer par des
  reserved-ranges et non par l'initramfs.
- [public] m1n1 `src/kboot.c:2321-2368` (`dt_set_sep`, commit `62ff43f0`, Sasha Finkelstein, 2024-11-10) : si le FDT
  a un alias `sep`, m1n1 réserve la région ADT `/chosen/memory-map` `SEPFW` (nœud `sep-firmware`, `apple,asc-mem`,
  memory-region nommée `sepfw`) et copie `/chosen/boot-object-manifests` `lpol` et `ibot` dans les propriétés
  `local-policy-manifest` et `iboot-manifest` du nœud SEP. Sans alias : « FDT: sep alias not found in devtree », et
  la fonction ne fait rien (`kboot.c:2323-2327`).
- [déduit] Quand Linux démarre via m1n1, le SEP est encore sous SEPROM (m1n1 lui parle sur l'EP 0xff), et SEPOS ne
  tourne que si Linux l'amorce lui-même. Aucune source ne l'écrit noir sur blanc, mais le message de commit
  `6afe9eba` et le pilote ci-dessous vont dans ce sens.

### 1.2 Pilote Linux existant : `drivers/soc/apple/sep.rs` (downstream uniquement)
- [public] linux-asahi `drivers/soc/apple/sep.rs` (Rust, 375 lignes), compatible `apple,sep` (l.332), description
  « Secure enclave processor stub driver » (l.373). Commit d'origine « soc: apple: Add SEP driver » (auteur GitHub
  WhatAmISupposedToPutHere, commité par jannau). **Absent du mainline** (`drivers/soc/apple/sep.rs` en 404 sur
  torvalds/linux master).
- [public] Ce que fait le pilote :
  - probe : récupère la région `sepfw` (l.346), construit une shmem de 0x30000 octets (l.41, 82-132 : entrées `CNIP`
    panique 0x8000 à +0x4000, `OPLA` = local policy, `IPIS` = manifeste iBoot, terminateur `llun`), puis envoie
    `BOOT_TZ0` sur l'EP 0xff (l.198-206) ;
  - quand arrive l'ACK 0xD2 : `BOOT_IMG4` (EP 0xff, DATA = IOVA du firmware >> 12) et `SET_SHMEM` (EP 0xfe, type
    0x18) (l.207-241, 246-251) ;
  - EP 0xfd (découverte) : messages reçus puis **ignorés** (log commenté, l.258-275) ; tout autre endpoint est
    ignoré (l.281).
  - Constantes l.42-51 : BOOT_TZ0 5, BOOT_IMG4 6, SET_SHMEM 0x18, ACK 0x69/0xD2/0x6A, EP 0xfd/0xfe/0xff.
- [public] Même séquence dans m1n1 `proxyclient/m1n1/hw/sep.py:10-21,104-127` (Sven Peter, commit `5b86c1ee`,
  2021-07-06 « add initial code to boot SEPOS »), avec en plus un GET_STATUS (2 → 0x66) et la découverte des
  endpoints par l'EP 0xfd (`sep.py:151-160`, nom 4 caractères dans DATA, numéro dans PARAM).
- [public] Kconfig linux-asahi `drivers/soc/apple/Kconfig:99-110` `APPLE_SEP` : « controlling transparent disk
  encryption, secure boot, HDCP, biometric auth and probably more ». Il n'y a aucun code SBIO, SKS ou xART.
- **Endpoints utilisés par du code public** : 0xff (SEPROM/boot), 0xfe (shmem), 0xfd (découverte, lecture seule).
  **Aucun pilote ni outil public pour 0x08 (SBIO)** : non trouvé dans m1n1 ni dans linux-asahi.
- [public] Feature support M1 (https://asahilinux.org/docs/platform/feature-support/m1/), tableau « SoC Blocks » :
  « SEP | WIP | WIP » (T8103 | T600x).

### 1.3 Activation dans le device tree, et notre machine
- [public] `arch/arm64/boot/dts/apple/t600x-die0.dtsi:453-461` : `sep@396400000`, `compatible = "apple,sep"`,
  mailbox `sep_mbox` (asc-mailbox-v4, IRQ AIC 545-548), `iommus = <&sep_dart 0>`, `status = "disabled"`.
- [public] `t600x-j314-j316.dtsi:17-37` (aliases de notre famille j314/j316) : **pas d'alias `sep`**, et aucun
  `&sep { status = "okay"; }` dans `t600x-j314-j316.dtsi` ni dans `t6001-j314c.dts`.
- [public] Le SEP n'est activé (alias `sep` + `status = "okay"`) que sur certaines machines M1 : `t8103-j293.dts:27,251-253`,
  `t8103-j313.dts:22,150-152` ; `t8103-j456.dts:135-137` a `okay` sans alias. `t8112.dtsi:1658-1665` : disabled.
- [déduit] Sur un j314c avec linux-asahi tel que publié, le pilote SEP ne se lie pas et m1n1 ne transmet pas `sepfw` :
  **le SEP reste sous SEPROM pendant toute la session Linux.** Pour avoir SEPOS sous Linux il faudrait un DT modifié
  (alias + okay). Le pilote enverrait alors un IMG4 au SEP. **C'est une ligne rouge pour les agents** (« envoi
  d'IMG4 », CLAUDE.md) : réservé à Albert, via `pending/`.
- [déduit] SEPOS amorcé par ce stub n'aurait ni xART/gigalocker (EP 0x13), ni SKS (0x12), ni boot policy (0x15). La
  doc Asahi indique que 0x13 « is needed for SKS to start ». On ne sait pas publiquement si SBIO (0x08) marche
  sans ces étapes : **non trouvé dans les sources publiques**. (Ne pas confondre : dans le journal, les « 0x15 / 0x16 »
  de l'init mesa sont des commandes SBIO sur l'EP 0x08, pas l'EP 0x15.) Les notifications SBIO TAG 0x01 passent par
  `sksQueueProcess` (source: kext) : un lien avec l'état du keybag est donc probable.

### 1.4 Une différence de doc à transmettre au sceptique
- Doc Asahi (sep/, « SEP Message format ») : « bits 16-24 » = type et « bits 25-31 » = param. Le code public
  (`m1n1/proxyclient/m1n1/hw/sep.py:24-29`, `src/sep.c:10-12`, `sep.rs:53-56`) utilise 16-23 / 24-31, comme
  CLAUDE.md. Probablement une coquille dans la doc ; nos traces collent au découpage 16-23/24-31.

---

## 2. SPI Apple (`spi-apple`) et nœud du capteur mesa

### 2.1 Le pilote
- [public] `drivers/spi/spi-apple.c` est **dans le mainline** (présent sur torvalds/linux master, avec le binding
  `Documentation/devicetree/bindings/spi/apple,spi.yaml`). Feature support M1 : « SPI | 6.15 | 6.15 »
  (T8103 | T600x).
- [public] Compatibles : `apple,t8103-spi` et `apple,spi` (`spi-apple.c:513-514`). Le DT t600x ajoute
  `apple,t6000-spi` (qui se rabat sur `apple,spi`).
- [public] Mode polled/IRQ, FIFO de 16 mots (`spi-apple.c:109`). `APPLE_SPI_CFG_MODE_DMA` est défini (l.31) mais
  jamais utilisé : **pas de DMA**. CS par GPIO possible (`use_gpio_descriptors`, l.495).
- [public] Kconfig linux-asahi `drivers/spi/Kconfig:121-130` `SPI_APPLE` : « t8103 (M1), t8112 (M2) and t600x (M1
  Pro/Max/Ultra). Multiple SPI controller instances are present on the SoC and each connects usually to a single
  device like spi-nor (nvram), input device controller **or fingerprint sensor**. » C'est la seule mention publique
  côté Linux d'un capteur d'empreintes sur SPI.
- [public] Page des bindings Asahi (https://asahilinux.org/docs/sw/devicetree-bindings/) : SPI « Used by OpenBSD; not
  submitted upstream yet ». C'est **périmé** : la page feature support et l'arbre mainline montrent que spi-apple est
  upstream.

### 2.2 Nœuds SPI du DT t600x
- [public] `t600x-die0.dtsi:653-679` ne définit que `spi1` (`spi@39b104000`, IRQ 1107, clk_200m) et `spi3`
  (`spi@39b10c000`, IRQ 1109, clkref), tous deux `disabled` par défaut. `t600x-j314-j316.dtsi:357-376` active `spi3`
  pour le clavier/trackpad (`apple,spi-hid-transport`), et `spi1` sert à la NVRAM (`#include "spi1-nvram.dtsi"`, l.744).
- [public] **Il n'y a ni `spi2` ni nœud `biosensor`/`mesa`/fingerprint** dans les DT linux-asahi : on a cherché
  `mesa|biosensor|touch.?id|fingerprint` dans t600x-*, t6001-j314c, t8103*, t8112.dtsi, sans résultat.
- [trace] Sur notre j314c sous macOS 13.5, le noyau démarre `spi1`, `spi2`, `spi3` et `spi4`
  (`traces/20261107-033436_c1-boot/hv_uart.log:176,182-184` : « spi2 AppleSPIMCController::start:129: using CCLK
  24000000 »). Il existe donc des contrôleurs que le DT Linux ne décrit pas. Lequel porte mesa sur t6001 : à lire dans
  l'ADT (pas encore fait ici).

### 2.3 m1n1 `proxyclient/hv/trace_mesa.py` (James Calligeros, 2022-06, commits `e2d671d5`…`a95c6d4d`)
- [public] Il cherche dans l'ADT un nœud `compatible = "spi-1,spimc"` qui a un enfant `biosensor,mesa`
  (l.25-39), puis trace les IRQ du contrôleur et du capteur (l.41-51).
- [public] Une broche GPIO `0xc4: "mesa_pwr"` sur `/arm-io/gpio0` (l.53-60). C'est la valeur de la machine de
  l'auteur, une M1 d'après les chemins ; rien n'indique qu'elle vaut pour t6001.
- [public] Les transferts SPI passent par **SIO** (coprocesseur ASC `/arm-io/sio`, EP 0x20) : canaux DMA « SPI2 DMA
  channels 0x18, 0x19 » (l.78-83), messages SIO 2/3/5/6/0x65/0x68. Il trace aussi `/arm-io/spi2` (l.208-212) et le
  DART `dart-sio`.
- [public] Docstring l.2-6 : « The command buffer is encrypted after the poweron sequence, and I can't find the key in
  the SEP using sven's old SEP tracer. »
- [public] l.188-192 : un transfert de taille `>= 0x7200` est enregistré comme « Fingerprint record message ».
- [déduit] Ça recoupe notre lecture du kext : capteur sur un SPI de l'AP, trafic chiffré après l'échange de clé de
  session, image de 0x7200 octets (= taille de la commande 0x65, source: kext). Sous macOS, le DMA SPI du capteur
  passe par SIO. Côté Linux, `apple-sio.c` existe (dmaengine, downstream seulement, absent du mainline) mais
  `spi-apple.c` ne l'utilise pas. 0x7200 octets en PIO à travers une FIFO de 16 mots est possible mais pas éprouvé.

---

## 3. AOP sous Linux
- [public] linux-asahi `drivers/soc/apple/aop.rs` (Rust, downstream ; Kconfig `APPLE_AOP` l.87-97 : « accelerometers,
  gyros, ambient light sensors and microphones »). Les services EPIC reconnus se limitent à `aop-audio`, `las` et
  `als` (`aop.rs:767-773`) ; tout autre nom est ignoré (`_ => return Ok(())`). Le pilote gère des rapports
  « fakehid » (sous-type 0xc4, `aop.rs:96,446-447,781-785`), mais seulement pour ces services.
- [public] DT : `t600x-die0.dtsi:400-425` (`aop@293c00000`, enfants audio/als/las), activé par
  `t600x-j314-j316.dtsi:602-604`. Pas d'enfant mesa ni HID/SPU.
- [public] m1n1 : `proxyclient/hv/trace_aop.py` et `experiments/aop.py` (Martin Povišer, 2022-10) ne contiennent
  pas « mesa » (grep sur tout le clone m1n1, en dehors de trace_mesa.py).
- [déduit] **Rien de public pour le reset mesa via l'AOP** (commandes 0x20/0x21 de AppleSPUMesaDriver, source: kext).
  Il faudrait un nouveau service AOP, ou piloter directement la GPIO/le reset si l'ADT les expose : non vérifié.

---

## 4. Mentions publiques de Touch ID dans Asahi
- [public] Feature support M1 (https://asahilinux.org/docs/platform/feature-support/m1/) : « TouchID | TBA | TBA » pour
  MacBook Pro (14/16-inch, 2021) et Mac Studio, et « TBA » pour toutes les machines M1.
- [public] Doc SEP : EP 0x08 « Secure Biometrics (SBIO) » ; EP 0x18 `stac` : « AppleTrustedAccessory talks to this
  endpoint, likely for the Touch ID sensor on external keyboards ».
- [public] Doc Subsystems (https://asahilinux.org/docs/platform/subsystems/) : « The Secure Enclave, Apple's
  crypto/biometrics/security engine ». Rien de plus.
- [public] Bindings DT (https://asahilinux.org/docs/sw/devicetree-bindings/) : aucune entrée sep, aop, mesa,
  biosensor ou fingerprint.
- Le reste n'est **pas dans les sources publiques consultées** : binding DT du capteur, pilote mesa ou SBIO, format
  des messages 0x08, procédure de reset du capteur.

---

## Ce qui en découle pour nous (déduit, à soumettre au sceptique)
1. Côté SEP, le public ne fournit qu'un amorceur (TZ0, IMG4, shmem, découverte), et il est désactivé sur j314c. Tout
   le protocole SBIO et l'environnement (0x13, 0x12, 0x15) restent à faire. Amorcer SEPOS sous Linux = envoi d'IMG4
   = expérience réservée à Albert.
2. Côté capteur, il faut ajouter au DT le bon contrôleur (spi2 ou spi4 ? à lire dans l'ADT) et un nœud enfant mesa
   (alimentation, IRQ, CS), puis un pilote client SPI. Le transport existe (spi-apple, mainline), sans DMA.
3. Pour le reset via l'AOP, rien n'existe publiquement.

---

## 5. EP 0xFF (SEPROM) : messages connus et état du SEP à l'arrivée de m1n1 — lu le 2026-11-09
Sources relues : https://asahilinux.org/docs/hw/soc/sep/ (sections « Endpoint information », « SEP boot flow »,
« Coprocessor information »), clone m1n1 local. Rien d'autre (pas de macOS, pas de kext).

### 5.1 Messages acceptés par l'EP 0xFF
- [public] `m1n1/proxyclient/m1n1/hw/sep.py:10-15` (`BootRomMsg`) : GET_STATUS = 2, BOOT_TZ0 = 5, BOOT_IMG4 = 6
  (le champ « type » est TYPE, bits 16-23, l.67-71 du même fichier pour la structure `SEPMessage`) ; SET_SHMEM = 0x18
  est envoyé sur l'EP 0xFE (`sep.py:121-123`). Seul GETRAND (16 → réponse 116) est dans `src/sep.c:14-17`.
- [public] Réponses ROM : `sep.py:17-21` (`BootRomStatus`) : 0x66 (statut OK), 0x69 (TZ0 fait), 0x6A (IMG4 fait),
  0xD2 (« unk », reçu juste après 0x69). Séquence complète `sep.py:104-127` : GET_STATUS → 0x66 ; BOOT_TZ0 → 0x69
  puis 0xD2 ; GET_STATUS → 0x66 ; BOOT_IMG4 (DATA = adresse IOVA >> 12) + SET_SHMEM ; attente de 0x6A.
- [public] **Il existe donc un message de statut en lecture seule : GET_STATUS (type 2) sur l'EP 0xFF, réponse
  attendue type 0x66.** Il est écrit dans `sep.py` (Sven Peter, 2021) ; aucun champ DATA de la réponse n'est
  décrit ni lu. La doc Asahi ne documente ni ce message ni ses valeurs : « non trouvé » côté doc.
- [public] Pas de message « version » ni « état détaillé » dans m1n1, ni dans `drivers/soc/apple/sep.rs` de
  linux-asahi (constantes l.42-51, cf. §1.2) : non trouvé.
- [déduit, NON vérifié, à ne pas lancer sans décision] GET_STATUS ressemble à une simple lecture, mais c'est quand
  même un message envoyé au SEP : il ne sort pas de notre périmètre de lecture seule sans l'accord d'Albert (comme
  GETRAND l'a été). Je ne le propose pas ici.

### 5.2 Qui charge SEPOS, état du SEP quand m1n1 démarre
- [public] Doc Asahi « SEP boot flow » : « iBoot preloads SEP firmware into a memory region that's recorded in ADT » ;
  « XNU sends a boottz0 message, bringing SEP into second stage boot (a portion of RAM is reserved for this) » ;
  puis XNU envoie l'IMG4 ; le SEP le vérifie et, s'il est accepté, démarre SEPOS. Donc : iBoot **précharge**,
  l'**OS** (XNU, ou Linux/m1n1 à terme) **amorce**. Le SEP se vérifie lui-même (« Coprocessor information »).
- [public] Aucune page de la doc Asahi ne parle de « SEPROM » (le mot n'y figure pas) ni de l'état du SEP quand m1n1
  prend la main ; l'EP 0xFF y est seulement « Boot255 ».
- [public] m1n1 `src/main.c:187` appelle `sep_init()` à chaque démarrage et `src/kboot.c:108-126` demande de
  l'aléa à l'EP 0xFF avant de lancer Linux, sans avoir amorcé SEPOS : m1n1 compte donc sur une ROM qui répond
  alors que SEPOS n'a pas été amorcé par lui.
- [déduit] Sous m1n1 en mode proxy (avant tout macOS), le SEP est donc vraisemblablement encore sous la ROM : aucune
  source ne l'écrit noir sur blanc. Notre trace `20261109-212150_sep_getrand` (réponse 116 sans macOS) est
  compatible avec cela. Cas hyperviseur (m1n1 lancé sous macOS 13.5) : m1n1 s'exécute **avant** le noyau XNU
  invité (hv lance XNU comme invité), donc avant tout boottz0 de XNU ; mais ce que mBoot/iBoot fait au SEP avant
  de passer la main à m1n1 n'est pas décrit publiquement : non trouvé.

### 5.3 SEPOS tourne-t-il déjà quand m1n1 prend la main ?
- **Non trouvé dans les sources publiques.** Les indices publics (iBoot ne fait que précharger ; XNU envoie
  boottz0 et IMG4 ; m1n1 parle à la ROM) indiquent que non, par défaut. Le statut reste une hypothèse.

### 5.4 Contradiction à transmettre au sceptique
- Doc Asahi (table des endpoints) : 0xFE « Boot254 » = « Signals SEP to boot into SEPOS with an IMG4 » ; 0xFF
  « Boot255 » = « protected region ... is ready for its own use ». Code m1n1 `sep.py:104-125` : BOOT_TZ0 et BOOT_IMG4
  partent sur 0xFF, seul SET_SHMEM part sur 0xFE. Les deux ne concordent pas : le rôle exact de 0xFE et 0xFF
  dans la doc est probablement imprécis ; se fier au code, et à nos traces.
- Nos traces n'en disent rien de plus : l'état de SEPOS reste à trancher (cf. journal du 2026-11-09 21:21).

---

## 2026-11-09 — SPI t6001 (contrôleurs, horloges, pinctrl, absence de mesa)

Documentaliste. Sources : linux-asahi branche `asahi`, fichiers bruts
`https://raw.githubusercontent.com/AsahiLinux/linux/asahi/arch/arm64/boot/dts/apple/<fichier>` lus le 2026-11-09
(numéros de ligne de cette lecture ; branche rebasée, ils peuvent bouger). Mainline `drivers/spi/spi-apple.c` (530 l.).

### A. Ce que le DT public décrit pour t600x (M1 Pro/Max)
- [public] Seuls `spi1` et `spi3` existent : `t600x-die0.dtsi:653-665` et `:667-679`.
  - spi1 : `reg = <0x3 0x9b104000 0x0 0x4000>`, `interrupts = <AIC_IRQ 0 1107 LEVEL_HIGH>`, `clocks = <&clk_200m>`,
    `pinctrl-0 = <&spi1_pins>`, `power-domains = <&ps_spi1>`, `status = "disabled"`, compatible
    `"apple,t6000-spi", "apple,spi"`.
  - spi3 : `reg = <0x3 0x9b10c000 0x0 0x4000>`, IRQ 1109, `clocks = <&clkref>`, `pinctrl-0 = <&spi3_pins>`,
    `power-domains = <&ps_spi3>`, `disabled`.
- [public] **Il n'y a PAS de nœuds `spi0`, `spi2`, `spi4`**, ni désactivés : `grep spi` sur t600x-die0/dieX/common,
  t6000/t6001.dtsi ne donne que spi1 et spi3 (+ `spi1_pins`/`spi3_pins` dans `t600x-gpio-pins.dtsi:39-51`).
- [public] Horloges : fixes, `t600x-common.dtsi:427-433` `clkref` = 24 000 000 Hz ; `:434-440` `clk_200m` = 200 MHz.
  Ce sont des `fixed-clock`, pas de gate PMGR. Le pilote fait `devm_clk_get_enabled` (`spi-apple.c:474`) et calcule
  le diviseur avec `clk_get_rate` (l.201). **Cohérent avec nos traces** [trace] : spi1 200 MHz, spi2/3/4 24 MHz
  (`hv_uart.log:176,182-184`) -> spi2 et spi4 auraient `clocks = <&clkref>` comme spi3.
- [public] Power-domains : `t600x-pmgr.dtsi` définit **ps_spi0** (reg 0x1f0, l.942), **ps_spi1** (0x1f8, l.951),
  **ps_spi2** (0x200, l.960), **ps_spi3** (0x208, l.969), **ps_spi4** (0x210, l.978), tous enfants de `ps_spi_p`
  (0x1e8, l.933, lui-même sous `ps_sio`). Donc le domaine d'alimentation de spi2 et spi4 existe déjà dans le DT public,
  il manque seulement le nœud du contrôleur.
- [public] Pinctrl : `spi1_pins` = broches 10, 11, 32, 33 ; `spi3_pins` = 52, 53, 54, 55, toutes `APPLE_PINMUX(n, 1)`
  (`t600x-gpio-pins.dtsi:39-51`). Pas de `spi2_pins`/`spi4_pins`. (À titre de comparaison t8103 : spi0 67-69,
  spi1 42-45, spi3 46-49, `t8103.dtsi:1114-1133`.) Le numéro de fonction « 1 » est celui des SPI connus ; pour
  spi2/spi4 de t6001 les broches sont **non trouvées dans les sources publiques**.
- [public] t8103 (M1) : spi0 `0x235100000` IRQ 614, spi1 `0x235104000` IRQ 615, spi3 `0x23510c000` IRQ 617
  (`t8103.dtsi:834-875`) ; `spi2` absent aussi, alors que trace_mesa.py l'utilise sur M1 (`/arm-io/spi2`).

### B. Écart d'adresse et IRQ
- [public] spi1 = 0x39b104000, spi3 = 0x39b10c000 : écart 0x8000 pour deux numéros, soit **0x4000 par contrôleur**
  (la taille `reg` est 0x4000). Même pas sur t8103 (0x235100000 / 04000 / 0c000) et IRQ qui suivent le numéro
  (614, 615, 617 ; 1107, 1109).
- [déduit] Donc spi2 = **0x39b108000** (spi0 = 0x39b100000, spi4 = 0x39b110000) et IRQ spi2 = **1108**, spi4 = 1110.
  Hypothèse par régularité, **pas écrite dans une source publique** : à confirmer avec l'ADT (`reg`/`interrupts`
  du nœud `spi2`) avant toute utilisation. Attention : `t600x-die0.dtsi:725` utilise l'IRQ 1111 pour autre chose
  (nœud suivant), donc 1110 n'est pas contredit mais vérifier l'ADT. Pour la numérotation IRQ sur die 1 (t6002),
  `AIC_IRQ` prend le premier argument en die ; non pertinent pour t6001 (1 die).
- [trace] Aucune trace ni doc locale ne contient 0x39b108000 (grep traces/ docs/ vide) : adresse non vérifiée.

### C. Capteur Touch ID / GPIO d'alimentation
- [public] Aucun DT public (t600x-*, t6001-j314c/j316c, t8103*, spi1-nvram.dtsi) ne contient `mesa`, `biosensor`,
  `touchid`, ni nœud fingerprint. Seule mention : Kconfig `SPI_APPLE` « … or fingerprint sensor » (voir §2.1).
- [public] Seul nœud client SPI actif sur t6001-j314/316 : `hid-transport@0` sur spi3
  (`t600x-j314-j316.dtsi:357-376`) avec `spien-gpios = <&pinctrl_ap 194 0>` (GPIO d'activation du SPI HID) et
  IRQ via `pinctrl_nub 6`. C'est le **seul modèle public** de « GPIO d'alimentation/enable » d'un périphérique SPI
  Apple ; rien pour mesa.
- [public] GPIO d'alimentation de mesa : seulement `0xc4: "mesa_pwr"` dans m1n1 `trace_mesa.py:53-56` (machine M1 de
  l'auteur, `/arm-io/gpio0`). **Non trouvé dans les sources publiques pour t6001** ; à lire dans l'ADT
  (`function-mesa-reset-ntfy`, etc., voir `docs/sensor_hw.md`).
- [déduit] Un nœud DT de départ pour mesa : copier le motif spi3 (`clocks=<&clkref>`, `power-domains=<&ps_spi2>`,
  `pinctrl-0` à créer, IRQ à confirmer) — tous les chiffres propres à mesa restent à prendre dans l'ADT.

### D. Contradictions avec nos traces
- Aucune : la doc publique est seulement incomplète (pas de spi2/spi4 dans le DT, pas de mesa). Les 4 contrôleurs vus
  dans la trace macOS ne sont pas tous décrits par Linux.

---

## 2026-11-12 — xART anti-rejeu / nonce (sources publiques)

Documentaliste. Question posée : l'anti-rejeu xART du SEP est-il **inévitable par conception** (compteur/nonce
monotone matériel interne au SEP qui refuse un rejeu), ou un rejeu fidèle des derniers lockers capturés peut-il
être accepté par un SEP redémarré par m1n1 ? Sources lues le 2026-11-12 : doc Asahi `hw/soc/sep/` et
`platform/security/` ; clone m1n1 local (commit de travail habituel) ; rappel des limites de linux-asahi (§1.2).
Aucun firmware ni dump. Légende : **[public]**, **[déduit]**, **[trace]** comme ci-dessus ; **[kext]** = issu du
désassemblage du kext (phase 2), cité ici seulement pour contraste, PAS comme source publique.

### A. Ce que xART garantit, d'après la doc publique
- [public] Asahi, https://asahilinux.org/docs/platform/security/ : « the SEP generates a Volume Encryption Key
  (VEK) and eXtended Anti-Replay Token (xART) for each APFS volume » ; « The xART prevents replay attacks from
  capturing the VEK » ; le VEK « is stored in the SEP's own airgapped memory » et « can never be read by the
  application cores ». Avec FileVault : « the VEK and xART are wrapped with a Key Encryption Key (KEK) ».
  « All encryption keys are destroyed by the SEP when the Machine Owner requests the machine to be wiped. »
- [public] Même page, intégrité de boot (lié mais distinct de la fraîcheur xART) : pour chaque kernelcache,
  « its hash is recorded in the SEP's Boot Policy ».
- [public] Donc la **finalité** anti-rejeu est affirmée noir sur blanc (« prevents replay attacks »), mais la
  page **ne décrit pas le mécanisme** : ni compteur monotone, ni nonce, ni où vit l'ancre de fraîcheur
  (interne SEP vs NVRAM vs disque). « Non trouvé » côté doc pour le *comment*.

### B. Les endpoints xART/pnon selon Asahi (table des endpoints, `hw/soc/sep/`)
- [public] 0x10 = « xars (according to tracer) », « xART setup? involved in startup/shutdown ».
- [public] 0x12 = « Secure/SEP Key Store », « SEP encrypt/decrypt operations and key management ».
- [public] 0x13 = « xART manager », « manages xARTs, gigalockers and keybags (needed for SKS to start) ».
- [public] 0x15 = « pnon (tracer name) », « Boot policy related. We will eventually need it for Machine owner
  credentials handoff, but can be ignored for now ».
- [public] Structure d'un locker décrite sur la même page : identifiant/UUID de clé à 0x01–0x12, longueur de clé
  0x12–0x16, CRC de la clé wrappée 0x16–0x1a, payload/keybag wrappé de 0x22 à la fin. Fetch = message type 0 ;
  réponse de fetch d'un locker = type 0x5 (succès), 0x7 = erreur, param 0x10. Les tags « seem to be increasing in
  the order of the lockers within the gigalocker ». La trace gigalocker init (EP 0x13) est marquée **non vérifiée**
  par Asahi.
- [public] **La doc ne contient aucun nonce, compteur monotone, anti-rollback, ni « boot nonce » dans ces
  endpoints.** Le nom `pnon` est seulement « boot policy related » (handoff Machine owner), pas décrit comme un
  nonce anti-rejeu xART.

### C. Nonce / BootNonce côté boot : ce que les sources publiques consultées contiennent
- [public] Dans tout le clone m1n1, `nonce` n'apparaît que pour l'**aléa de boot Linux** (rng-seed / kaslr-seed
  via GETRAND sur l'EP 0xff, cf. §1.1), **jamais** pour xART, le SEP scellé, un ap-nonce/sep-nonce ou un BootNonce.
  Grep `xart|xarm|xars|pnon|anti-replay|nonce` sur m1n1 : aucune occurrence xART/pnon/nonce-anti-rejeu.
- [public] linux-asahi (§1.2) : le stub `drivers/soc/apple/sep.rs` ne gère que TZ0/IMG4/shmem/découverte et
  **ignore** tous les autres endpoints ; aucun code xART, nonce ou boot-policy. Rien non plus dans la doc bindings.
- [déduit] La notion « ap-nonce / sep-nonce / BootNonce → fraîcheur de l'état scellé » n'est **pas documentée
  dans les sources publiques autorisées ici** (Asahi + m1n1 + linux-asahi + open source Apple publié). Non trouvé.

### D. Peut-on rejouer l'état xART d'un boot précédent ? — ce que le public établit
- [public] **Le stockage opaque (gigalocker sur disque) est publiquement lisible.** m1n1 contient
  `rust_read_gigalocker` (`rust/src/apfs.rs`, commit `07c2c3af` « proxyclient: Add get_gigalocker », Sasha
  Finkelstein, 2026-07-16) : il scanne le GPT, trouve le volume APFS de rôle xART (`VOL_ROLE_XART = 0x100`,
  `apfs.rs:162,330`), remonte au fichier gigalocker et renvoie son contenu brut (`apfs.rs:378-392`,
  `proxyclient/m1n1/proxyutils.py:428-434` `get_gigalocker`, proxy op `P_READ_GIGALOCKER = 0x1400`).
  → Côté AP, le blob xART n'est qu'un fichier chiffré que n'importe quel code peut relire : **rien côté AP
  n'empêche de le rejouer.** C'est cohérent avec Asahi : le SEP « is the only one that seems to have dedicated
  storage » et confie le reste à l'AP.
- [public] **Ce que le public ne dit PAS** : où le SEP ancre la fraîcheur (compteur monotone matériel interne ?),
  ni s'il refuse un gigalocker rejoué, ni s'il lie l'acceptation à un nonce régénéré à chaque boot. Asahi affirme
  seulement l'objectif (« prevents replay attacks ») sans le mécanisme. L'open source Apple publié
  (apple-oss-distributions) ne publie pas le firmware SEP ni les kexts SEP ; ces internes n'y figurent pas
  (non trouvé).
- [déduit] Nuance importante pour notre question précise : « anti-replay » protège classiquement contre un
  **rollback** (rejouer un état *ancien*). Rejouer à l'identique l'état *le plus récent* sauvé n'est pas un
  rollback. La question « un rejeu fidèle du dernier gigalocker passe-t-il ? » dépend donc de savoir si le SEP lie
  l'acceptation à un **nonce régénéré à chaque boot** (alors le dernier état devient périmé au boot suivant) ou à
  une **simple monotonie de version** (alors le dernier état reste toujours acceptable). **Aucune source publique
  ne tranche entre ces deux cas.**
- [kext, pour contraste — PAS une source publique] La classe `AppleSEPXART` expose `nonce_generate`/`nonce_read`/
  `nonce_invalidate` (cf. `docs/kext_sepmanager.md`) : l'existence d'un nonce xART côté protocole est plausible,
  mais son rôle (par-boot vs par-session) et son ancrage matériel ne sont **pas** établis publiquement. À traiter
  comme hypothèse, à confirmer par l'expérience (voie B/C), pas par la doc.

### E. Conclusion (sources publiques uniquement)
**(c) Indéterminé publiquement.** Les sources publiques établissent l'**intention** anti-rejeu de xART
(« The xART prevents replay attacks ») et montrent que le **stockage AP est trivialement rejouable** (m1n1
`get_gigalocker`). Mais elles **ne documentent pas le mécanisme de fraîcheur** (compteur monotone interne au SEP,
nonce par boot, ou simple monotonie de version) : impossible de conclure, à partir du seul public, que le
re-scellement est (a) inévitable par conception, ni (b) contournable par rejeu du dernier état. Trancher exige une
**expérience** (voie B pour chercher un nonce/compteur par boot dans l'échange 0x13, cf. `docs/xart_options.md`,
`docs/verification_status.md` xART-CHAIN) ou l'étude du protocole en phase 2 — pas une source publique.

### F. Contradictions doc publique ↔ nos traces (pour le sceptique)
- Aucune contradiction : le public est seulement **muet** sur le mécanisme de fraîcheur. Nos traces (xART-CHAIN,
  `verification_status.md` L120-123) vont plus loin que tout public : `save(N)=fetch(N+1)`, 2 lockers variables
  sur 10 (SEP-xART TAG 0x03 + un locker Credential Manager), préfixe 16 o = nonce/MAC **hypothèse**, pas de
  compteur en clair. À confronter à la voie B, pas à la doc.

---

## 2026-11-17 — m1n1 proxy sans macOS 13.5 (machine Asahi déjà installée)

Documentaliste, lu le **2026-11-17**. Contexte : après DFU Restore, Asahi réinstallé en « UEFI only »
(m1n1 stage 1 + stage 2 + U-Boot sur une ESP neuve), ALARM restauré (image bloc, boote m1n1→U-Boot→GRUB→ALARM),
macOS **27.2.1** neuf présent, **macOS 13.5 effacé et non resignable**. Question : comment obtenir un m1n1
**mode proxy** (2 ports série USB) pour `chainload.py` / `sep_peek.sh` / `tethered_boot.sh` sans le volume 13.5.

Sources publiques consultées le 2026-11-17 :
- `m1n1-user-guide` : https://asahilinux.org/docs/sw/m1n1-user-guide/
- `m1n1-hypervisor` : https://asahilinux.org/docs/sw/m1n1-hypervisor/
- `tethered-boot` : https://asahilinux.org/docs/sw/tethered-boot/
- `platform/introduction` (boot process) : https://asahilinux.org/docs/platform/introduction/

Légende identique au reste du fichier : **[public]** = écrit dans la source ; **[déduit]** = notre lecture ;
**[projet]** = état/règles internes (pas une source publique).

### A. Fait structurant : l'ancienne méthode (kmutil sur 13.5) n'est plus nécessaire
- [projet] Ancienne voie (README §4, journal 2026-11-07) : poser un m1n1 **sans payload** comme fuOS via
  `kmutil configure-boot` sur le volume **macOS 13.5** → il tombe en proxy. Elle dépendait d'un macOS 13.5 installé.
- [public] `tethered-boot` : sur une machine **Asahi déjà installée**, le **stage 2** de m1n1 est chargé depuis
  l'ESP au chemin **`m1n1/boot.bin`** ; le **stage 1** est posé pendant l'étape 1TR de l'installeur et « ne peut pas
  être modifié sans un passage par la recovery ». Autrement dit **le m1n1 dev est déjà en place** : plus besoin de
  `kmutil` ni de macOS 13.5 pour avoir un m1n1 qui peut basculer en proxy.

### B. Voie RECOMMANDÉE (la plus simple et sûre) : flag en recovery + fenêtre de 5 s, puis chainload
- [public] `tethered-boot` : le mode proxy s'active **depuis la recovery macOS**, en exécutant
  `csrutil disable && nvram boot-args=-v` **sur le volume Asahi Linux** (pas sur macOS). Ce réglage **n'est pas
  temporaire** (il reste jusqu'à ce qu'on le remette).
- [public] `tethered-boot` : une fois le flag posé, « m1n1 attend 5 secondes au boot » ; si l'hôte ouvre le TTY m1n1
  pendant cette fenêtre, la machine **entre en mode proxy**. Côté PC, `proxyclient/tools/picocom-sec.sh` attend le
  périphérique et ouvre son **second** port USB comme terminal série ; `proxyclient/tools/shell.py` confirme le
  proxy ; `proxyclient/tools/linux.py` boote un noyau ; `tools/run_guest_kernel.sh` boote sous l'hyperviseur.
- [public] `m1n1-user-guide` : pour casser dans un m1n1 **déjà installé** (build release), il faut **SIP désactivé +
  verbose** ; « le mode verbose seul **n'active plus** la backdoor sur les builds récents » → les **deux**
  (`csrutil disable` ET `boot-args=-v`) sont nécessaires. Ports : l'hôte voit 2 ACM, le **1er = proxy**
  (`M1N1DEVICE=/dev/ttyACM0`), le **2e = UART virtuel de l'hyperviseur** ; sous Linux on ouvre le **2e** avec
  `picocom --omap crlf --imap lfcrlf -b 500000 /dev/ttyACM1` pour déclencher l'entrée en proxy.
- [public] `m1n1-user-guide` + `m1n1-hypervisor` : une fois en proxy, on **chainloade un m1n1 frais de l'arbre de
  travail** pour coller à l'ABI : `proxyclient/tools/chainload.py -r build/m1n1.bin` (ou `build/m1n1.macho` pour
  l'hyperviseur). C'est ce que fait déjà `tools/tethered_boot.sh`.
- ⚠️ **Albert à la main (ligne rouge)** : l'étape `csrutil disable && nvram boot-args=-v` en **recovery/1TR** touche
  la **boot policy** et utilise des **outils Apple** (`csrutil`, `nvram`). L'agent **ne la script pas**. La recovery
  (1TR) s'atteint en maintenant le bouton d'allumage ; elle est **indépendante de la version de macOS** — donc
  **macOS 13.5 n'est pas requis**, macOS 27.2.1 (ou la 1TR) suffit à poser le flag sur le volume Asahi.
- [public] Retour arrière (`tethered-boot`/`m1n1-user-guide`) : `nvram boot-args=` puis `csrutil enable` — **ne pas**
  choisir « full security » au prompt, sinon m1n1 est **désinstallé**. (Albert, à la main également.)

**Bilan voie B** : un **seul** passage en recovery (Albert), aucun fichier de boot modifié, le boot normal
d'ALARM continue de marcher (juste +5 s et verbose). C'est la voie à privilégier.

### C. Voie alternative « Linux-only » (sans macOS) — plausible mais [déduit] et NON documentée telle quelle
- [public] `tethered-boot` : stage 2 = `m1n1/boot.bin` sur l'ESP. [public] `m1n1-user-guide` : « si m1n1 n'a pas de
  payload, ou si le boot du payload échoue, il **retombe en mode proxy** » (`RELEASE=1` garde une « escape hatch to
  activate an early proxy mode »).
- [déduit] En **remplaçant `m1n1/boot.bin` par un m1n1 sans payload** (build dev), le stage 1 le charge au boot, il
  n'a pas de payload → **proxy automatique**, **sans** le flag recovery et **sans** macOS. L'ESP est montable/
  éditable depuis ALARM, donc l'opération et son **retour arrière** (restaurer l'ancien `boot.bin`) se font
  entièrement sous Linux. C'est le même mécanisme que l'update normal de m1n1 (on copie un fichier sur l'ESP).
- ⚠️ **Non documenté noir sur blanc** : aucune page publique ne dit « pose un m1n1 sans payload à `boot.bin` pour
  avoir le proxy ». C'est une **déduction** en combinant deux pages → à traiter comme hypothèse tant que non testé.
- ⚠️ **Albert à la main quand même** : modifier `m1n1/boot.bin` = **toucher à m1n1** → interdit à l'agent y compris
  sur le Linux de test (CLAUDE.md, exception 2e Linux). De plus, tant que ce `boot.bin` sans payload est en place,
  la machine **ne boote plus ALARM** (elle tombe toujours en proxy) : il faut restaurer `boot.bin` pour re-booter
  Linux. Reversible depuis Linux, mais à faire en connaissance de cause.

### D. Réponses point par point à l'orchestrateur
1. **Façon recommandée Asahi** : le m1n1 dev est **déjà installé** (stage 2 `m1n1/boot.bin`). On l'amène en proxy
   via le flag recovery (`csrutil disable && nvram boot-args=-v` sur le volume Asahi) + fenêtre de 5 s, puis
   **chainload** d'un m1n1 frais. [public, `tethered-boot` + `m1n1-user-guide`]. Pas besoin de remplacer un fichier.
2. **Obligatoire de passer par macOS + kmutil/bputil ?** **Non pour `kmutil`/`bputil`**, et **non par macOS 13.5**.
   Mais la voie recommandée exige **un** passage en **recovery/1TR** pour `csrutil`/`nvram` (outils Apple, boot
   policy) = Albert. Une voie **entièrement Linux** existe (remplacer `boot.bin`, §C) mais elle est **[déduit]**,
   non documentée, et reste « Albert » au titre de « ne pas toucher m1n1 ». **Non trouvé dans la doc publique** :
   un chemin proxy officiel 100 % Linux sans ni recovery ni remplacement de `boot.bin`.
3. **Chainload USB sans rien installer de permanent ?** **Oui** : le m1n1 **déjà installé** sert de bootstrap ; une
   fois en proxy (fenêtre 5 s), `chainload.py -r build/m1n1.bin` charge le m1n1 dev **en RAM**, rien de permanent.
   **Mécanisme de déclenchement exact** [public] : le flag `boot-args=-v` (+ `csrutil disable`) fait **attendre
   m1n1 5 s** au boot ; l'hôte **ouvre le 2e port série** (`picocom-sec.sh` / `picocom ... /dev/ttyACM1`) pendant
   ces 5 s → entrée en proxy. Ce n'est **pas** une touche clavier ni un menu : c'est l'**ouverture du TTY** dans la
   fenêtre. (Sans le flag, un m1n1 **avec** payload ne s'arrête pas ; seul un m1n1 **sans** payload tombe en proxy
   tout seul — cf. §C.)
4. **Pièges j314c / macOS récent pour l'hyperviseur** [public, `m1n1-hypervisor`] : cibles macOS **invitées**
   supportées = **13.5 (M1/M2)** et **14.8.3 (M1→M3)** ; M4+ non figé (SPTM). Donc **macOS 27.2.1 n'est PAS
   supporté comme invité** sous l'hyperviseur. **Conséquence utile** : pour reprendre le tracing SEP sous
   hyperviseur (`run_guest.py`), il faudrait réinstaller un macOS **invité supporté** — et la doc liste désormais
   **14.8.3** en plus de 13.5 pour M1 (le projet ne connaissait que « 13.5 only » — repère technique CLAUDE.md à
   mettre à jour). **Important** : obtenir le **proxy** et lancer **`sep_peek`** (SEPROM EP 0xff) **ne dépend pas**
   d'un macOS invité — ça marche dès la voie B, sans aucun macOS 13.5/14.8.3.

### E. Contradiction / mise à jour à signaler au sceptique et au projet
- **Repère technique périmé** : CLAUDE.md « Hyperviseur : macOS **13.5** uniquement » et README §2. La doc Asahi
  (`m1n1-hypervisor`, lue 2026-11-17) liste **13.5 (M1/M2)** **et 14.8.3 (M1→M3)**. À corriger (décision Albert).
- Aucune contradiction doc↔traces sur ce sujet ; il s'agit d'une évolution de la doc publique.

---

## 2026-11-18 — Rejeu xART à travers les boots : viable ou cul-de-sac ? (ré-instruction, sources publiques)

Documentaliste, lu/relu le **2026-11-18**. Question de l'orchestrateur : est-il **théoriquement possible** de
restaurer/rejouer un état xART sauvegardé vers le SEP à travers des boots (voie C), ou le design anti-rejeu
oblige-t-il le SEP à **re-sceller** au lieu de **restaurer** ? Cette section **met à jour** celle du 2026-11-12
(« xART anti-rejeu / nonce ») avec : (a) une re-vérification des sources, (b) un angle neuf — **grep de l'open
source Apple publié** — et (c) le rappel que nos essais SERVE_GL du jour (traces, PAS une source publique)
tranchent côté pratique plus loin que tout public. Légende inchangée : **[public]** / **[déduit]** / **[trace]** /
**[kext]** (contraste phase 2, pas une source publique).

### A. Re-vérification des sources publiques — rien de neuf depuis le 2026-11-12
- [public] **m1n1 inchangé** : clone local toujours au commit `70757dc7` (2026-11-04). Le seul code xART/gigalocker
  reste `rust/src/apfs.rs` (`VOL_ROLE_XART = 0x100` l.162 ; `rust_read_gigalocker` l.378-392 ; proxy
  `P_READ_GIGALOCKER = 0x1400` `src/proxy.h:184`). Il **lit** le fichier gigalocker du volume APFS de rôle xART et
  rend son contenu brut — **aucune notion de fraîcheur, nonce, compteur ou anti-rejeu côté AP**. Grep
  `xart|gigalocker|anti.?replay|monotonic|rollback|ratchet|nonce` sur `rust/ proxyclient/ src/` : pas une seule
  occurrence liée à la fraîcheur (seuls `nonce` = aléa de boot Linux via GETRAND, et `NO_ROLLBACK` = flag libfdt,
  sans rapport).
- [public] **Doc Asahi inchangée** (relue ce jour) : `platform/security/` affirme toujours l'**intention**
  (« The xART prevents replay attacks from capturing the VEK » ; VEK en « airgapped memory », « can never be read
  by the application cores ») **sans décrire le mécanisme** : la page « does not mention nonces, monotonic counters,
  or freshness checks … does not describe how the SEP detects or rejects replayed data ». `hw/soc/sep/` garde la
  table d'endpoints (0x10 xars « xART setup? startup/shutdown » ; 0x12 SKS ; 0x13 « manages xARTs, gigalockers and
  keybags (needed for SKS to start) » ; 0x15 pnon « boot policy related ») et le format de locker partiel
  (fetch = type 0, succès = 0x5, erreur = 0x7 param 0x10). **Aucun type SAVE/store documenté**, **aucun nonce ni
  compteur**. Le *comment* reste « non trouvé » côté doc.
- [public] **linux-asahi inchangé** : le stub `drivers/soc/apple/sep.rs` ne gère que TZ0/IMG4/shmem/découverte et
  **ignore** tous les autres endpoints ; aucun code xART/nonce/boot-policy.

### B. Angle neuf — l'open source Apple publié ne contient PAS le mécanisme xART
- [public] J'ai cloné (depth 1) et grepé le dépôt **`apple-oss-distributions/Security`** (176 Mo, framework Security
  de macOS, publié) pour `xart`, `anti.?replay`, `monotonic`, `ratchet`, `replay attack`, `boot nonce`.
  **Résultat : aucune référence au xART du SEP ni à son anti-rejeu.** Les seuls « xart » sont des **fragments
  base64 fortuits** dans des certificats de test (`tests/TrustTests/…/*.crt.pem`). Les « anti-replay / monotonic /
  replay attack » trouvés concernent **tout autre chose** : SCEP (`OSX/sec/Security/SecSCEP.c:1152`), synchro de
  pairs de confiance iCloud (`keychain/TrustedPeersHelper/Container.swift:7518` « checks signatures and clocks to
  prevent replay attacks »), compteur de politique de certificat (`SecFrameworkStrings.h`), index de base de données
  trousseau (`libsecurity_filedb/AppleDatabase.cpp`). Rien sur la fraîcheur xART/SEP.
- [public, confirmé] Cohérent avec le fait **structurel** : Apple **ne publie pas** le firmware SEPOS ni les kexts
  SEP-side (AppleSEPManager, AppleSEPKeyStore/AppleKeyStore, la classe `AppleSEPXART`). Le mécanisme de fraîcheur
  vit **entièrement** dans ces binaires fermés. **Non trouvé dans l'open source Apple publié** — et il n'y a aucune
  raison qu'il y figure.
- [déduit, limite de méthode] Le code-search plein-texte de GitHub sur `org:apple-oss-distributions` exige une
  **authentification** (non disponible ici) ; grep.app est derrière un checkpoint. J'ai donc échantillonné le dépôt
  le plus pertinent (Security) plutôt que l'ensemble des dépôts. Conclusion robuste malgré tout vu que les
  composants SEP ne sont pas open source.

### C. Existence d'une description publique Apple HORS périmètre (lead pour Albert, NON utilisée ici)
- Apple publie un document de conception public (« Apple Platform Security », support.apple.com) qui décrit, au
  niveau conception, un **composant de stockage sécurisé à compteur anti-rejeu** et un **boot nonce** pour le SEP.
  **Ce document n'est PAS dans la liste de sources autorisées** pour cette phase (asahilinux.org/docs, m1n1,
  linux-asahi, opensource.apple.com). Je le **signale seulement** comme piste : si Albert l'autorise, il donnerait
  le *modèle mental* officiel du « comment » (compteur monotone matériel → un état scellé **ancien** est rejeté).
  Je ne cite **aucune** de ses affirmations comme établie ici. Ce n'est ni un leak ni un firmware : c'est de la
  doc de conception publiée par Apple, mais elle sort du périmètre convenu.

### D. Réponses point par point (sources publiques autorisées uniquement)
1. **Mécanisme de fraîcheur / anti-rejeu (nonce, compteur monotone, graine de session liée au boot)** :
   **non documenté dans les sources autorisées.** Asahi affirme l'objectif, pas le moyen ; m1n1 et linux-asahi
   n'en ont aucune trace ; l'open source Apple publié n'en parle pas. → **« comment » = non trouvé.**
2. **« restaurer » vs « re-sceller » au démarrage** : **aucune source autorisée ne décrit cette décision.** La doc
   Asahi documente seulement le **FETCH** (le SEP réclame un locker, type 0, réponse 0x5/0x7) ; elle ne documente
   **aucun** message SAVE ni la règle de bascule. → non trouvé côté public.
3. **Rôle des gigalockers / SEP-xART / USER-xART** : [public] Asahi dit que 0x13 « manages xARTs, gigalockers and
   keybags (needed for SKS to start) » et que les gigalockers portent les keybags wrappés (format locker partiel).
   La **distinction** xART **maître** (SEP-xART / USER-xART, les racines de fraîcheur) vs **gigalockers** (lockers
   applicatifs réclamés par FETCH) **n'est PAS dans le public** : elle vient de **nos traces** et du **kext**
   (`source: kext`, cf. §B/D plus bas et `kext_sepmanager.md`), pas d'une source publique.
4. **Un rejeu de xART/gigalocker déjà montré faisable (ou explicitement impossible) publiquement ?** **Non, ni l'un
   ni l'autre.** [public] Le seul fait public voisin : le **stockage AP est trivialement rejouable** (m1n1
   `get_gigalocker` relit le blob chiffré sur disque). **Rien côté AP n'empêche de le resservir** ; mais **aucune
   source publique ne montre un SEP acceptant un xART rejoué**, ni ne le déclare impossible. → non trouvé.

### E. Verdict théorique (sources publiques seules)
**Indéterminé publiquement — confirmé et renforcé par rapport au 2026-11-12.** Les sources autorisées établissent
l'**intention** anti-rejeu et la **rejouabilité du stockage AP**, mais **ne tranchent pas** entre :
- **monotonie de version** (seul un état *ancien* est rejeté → le *dernier* SAVE resterait acceptable → voie C
  viable en « relais du dernier état »), et
- **nonce/graine régénéré à chaque boot** (le dernier état devient périmé au boot suivant → un rejeu, même fidèle,
  est re-scellé → voie C fondamentalement bloquée sans reproduire le contexte de fraîcheur).

Aucune source publique ne départage ces deux modèles. **On ne peut donc PAS, à partir du seul public, dire que la
voie C est viable ni qu'elle est un cul-de-sac connu.** Ce n'est **pas** un verrou « documenté comme impossible » :
c'est un **inconnu public**.

### F. Ce que nos traces ajoutent (NON public — à garder séparé, pour le sceptique)
À ne PAS confondre avec le public ci-dessus. Nos essais SERVE_GL/FOLLOW (hypotheses.md HV1, `verification_status.md`
xART-CHAIN ; traces `20261118-082622`, `…085250`) montrent, côté **pratique** :
- [trace] En servant le **vrai** coffre `.gl` (qui colle à la puce réparée + Touch ID ré-enrôlé), le SEP prend les
  **2 maîtres** puis **re-scelle immédiatement (SAVE op 0x01 à TAG=0x05), gl:0** — il **saute toute la phase FETCH
  des gigalockers** que macOS fait au même point. C'est **la** divergence voie C.
- [trace] L'hypothèse « maîtres croisés (bug d'emballage) = cause » est **réfutée** (n=2 : croisés 08:26 **et**
  corrigés 08:52 → **même** SAVE@TAG05). Le contenu/ordre des maîtres n'est pas le déclencheur. → **recentre vers
  le modèle « nonce/graine par boot » (re-scellement), voie C qui recule.**
- [trace/kext] **MAIS ce n'est pas prouvé fermé** : (i) « un SAVE n'est pas un refus » (macOS émet aussi des SAVE
  acquittés et continue) ; (ii) reste le doute **préfixe 0x11** de l'emballage du maître, seul emballage non
  testé et **non vérifiable hors ligne**. La discrimination définitive « emballage faux » vs « vrai anti-rejeu »
  exige d'**acquitter le SAVE** = **écriture risquée** (fait avancer un compteur scellé potentiel) → **Albert +
  backup disque** (inexistant à ce jour). Voir `docs/voie-c-xart-fraicheur` (mémoire) et hypotheses.md HV1.
- [kext, contraste] La classe `AppleSEPXART` expose `nonce_generate`/`nonce_read`/`nonce_invalidate`,
  `setup_OS_UUID`, `erase_session_seeds_for_UUID` — **compatible** avec une fraîcheur liée à un nonce/graine de
  session par boot, mais **le rôle exact (par-boot vs par-session) et l'ancrage matériel ne sont pas établis**.
  Hypothèse, pas une source publique.

### G. Contradiction doc publique ↔ nos traces (pour le sceptique)
- **Aucune contradiction** : le public est seulement **muet** sur le mécanisme. Nos traces vont plus loin que tout
  public (SAVE@TAG05 reproduit, maîtres corrigés sans effet) et **penchent côté pratique vers le re-scellement**,
  mais **sans preuve crypto** (blobs chiffrés, n petit, test décisif = écriture non encore faite). Le seul risque
  d'incohérence serait de **présenter « voie C penche fermée » comme un fait public** : ce n'en est pas un — c'est
  une lecture de **nos traces**, à trancher par l'expérience d'écriture (Albert + backup), pas par la doc.

## 2026-11-18 (après-midi) — Guide « Apple Platform Security » autorisé : (a) compteur vs (b) nonce par boot ?

Albert a **autorisé ce jour une source publique supplémentaire** : le guide officiel **« Apple Platform
Security »** (support.apple.com, document de conception public, ni leak ni firmware). But : départager le modèle
anti-rejeu (a) compteur monotone de version [rejeu du dernier coffre viable] vs (b) nonce régénéré par boot [rejeu
figé impossible]. Page lue : **« Secure Enclave »**, URL
`https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web`, lue le **2026-11-18**. Légende :
**[public, guide Apple]** = citation verbatim du guide ; **[déduit]** = pont vers notre vocabulaire (xART).

### H. Ce que le guide dit VERBATIM (citations exactes)
- [public, guide Apple] **Composant matériel dédié** : « In devices with A12, S4, or later SoCs, the Secure Enclave
  is paired with a **Secure Storage Component** for entropy storage. » Le M1 (A14/M1-class) est postérieur à A12 →
  concerné.
- [public, guide Apple] **Canal exclusif chiffré+authentifié** : « The Secure Enclave and Secure Storage Component
  communicate using an **encrypted and authenticated protocol** that provides **exclusive access to the entropy**. »
  Et : « The secure nonvolatile storage is connected to the Secure Enclave using a **dedicated I2C bus**, so that it
  can only be accessed by the Secure Enclave. »
- [public, guide Apple] **Racine d'entropie hors disque AP** : « All user data encryption keys are **rooted in
  entropy stored in the Secure Enclave nonvolatile storage**. » ; « The Secure Storage Component **generates the
  salt value using its random number generator** » ; « … returns the generated lockbox entropy value to the Secure
  Enclave ».
- [public, guide Apple] **Services anti-rejeu NV liés à des « frontières », PAS à chaque boot** : « The secure
  nonvolatile storage is used for **all anti-replay services** in the Secure Enclave. » Ces services servent à la
  « revocation of data over events that mark **anti-replay boundaries** », dont la liste est : **changement de code**,
  activation/désactivation/reset de Face/Touch/Optic ID, **ajout/retrait d'un doigt/visage**, ajout/retrait d'une
  carte Apple Pay, « Erase All Content and Settings ». **Le boot n'est pas dans cette liste.**
- [public, guide Apple] **Compteur des lockboxes = limiteur de tentatives, PAS un compteur de version** : « Each
  counter lockbox stores a 128-bit salt, a 128-bit passcode verifier, an **8-bit counter**, and an 8-bit maximum
  attempt value. » À chaque essai : « first **increments the counter** » ; bon code → « resets the counter to 0 » ;
  dépassement → « **completely erases the counter lockbox** ». C'est un anti-brute-force de code, pas un compteur de
  fraîcheur xART.
- [public, guide Apple] **Mémoire vive (RAM) du SEP : clé éphémère régénérée au démarrage** (= par boot) : « When the
  device starts up, the Secure Enclave Boot ROM **generates a random ephemeral memory protection key** for the Memory
  Protection Engine. » ; « the Memory Protection Engine stores a **unique one-off number, called an anti-replay
  value** », « protected using an **integrity tree rooted in dedicated SRAM** ». Mais ceci concerne la **protection
  mémoire volatile**, pas le stockage xART persistant.

### I. Ce que le guide NE dit PAS (honnêteté)
- Le guide **n'emploie jamais** les mots « xART », « boot nonce », « monotonic counter » (au sens version), ni ne dit
  que l'état NV **périme à chaque boot**. Il **ne tranche donc pas explicitement (a) vs (b)** dans ces termes pour le
  stockage xART. Dit franchement : **le guide reste vague sur le choix (a)/(b) exact.**

### J. Ce que le guide tranche quand même — et qui dépasse (a)/(b)
- [déduit, de H] Les deux indices textuels **penchent CONTRE (b) « nonce régénéré à chaque boot »** pour le stockage
  **persistant** : (i) les frontières anti-rejeu NV sont des **événements de révocation** (code, biométrie, Apple
  Pay), **le boot n'en fait pas partie** → l'état scellé **survit** à un boot ordinaire ; (ii) le seul « éphémère
  par boot » explicite est la **clé de protection mémoire (RAM)**, pas le coffre NV. → Le modèle persistant ressemble
  plus à (a) **état invalidé seulement aux frontières de révocation** qu'à (b) **tout périmé au boot**.
- [déduit, décisif] **MAIS cela ne rouvre PAS la voie C au sens « rejouer le coffre disque ».** Le fait structurel
  établi par le guide est que la **racine de fraîcheur/entropie vit dans un composant matériel séparé (Secure Storage
  Component)**, accessible **uniquement par le SEP** via un **bus I2C dédié** et un **protocole chiffré+authentifié à
  accès exclusif**. Le blob xART/gigalocker **sur disque** est **enveloppé avec des clés enracinées dans cette
  entropie matérielle** (« All user data encryption keys are rooted in entropy stored in the Secure Enclave
  nonvolatile storage »). Donc **rejouer le coffre figé du disque est insuffisant par conception, que le modèle soit
  (a) ou (b)** : l'AP (m1n1/Linux) **ne peut ni lire, ni rejouer, ni reproduire** l'entropie détenue dans ce silicium.
  C'est un **troisième axe** que (a)/(b) ne capturaient pas : le verrou n'est pas « ancien vs dernier état », c'est
  **« la fraîcheur n'est pas dans le disque, elle est dans une puce que seul le SEP adresse »**.

### K. Mise à jour du verdict (public, maintenant guide Apple inclus)
- **Avant (section E)** : indéterminé public entre (a) et (b). **Maintenant** : le guide **oriente contre (b) pur**
  pour le NV (l'état survit à un boot simple), **mais** établit un fait plus fort pour notre projet — **l'ancrage
  matériel hors-disque**. Conséquence pour la voie C « servir le coffre disque sauvegardé » : **le guide la rend
  improbable au niveau conception** (le coffre seul ne porte pas la fraîcheur), **sans la déclarer formellement
  impossible** (le guide ne décrit pas le protocole SEP↔Secure Storage Component au boot, ni s'il faut un
  ré-appariement/une resynchro d'entropie à chaque démarrage). Le point restant indéterminé : **est-ce la perte de ce
  contexte matériel (apparié par iBoot/sepOS natif, absent sous m1n1) qui force le re-scellement observé dans nos
  traces ?** — cohérent avec notre **hypothèse B′**, mais non prouvé par le guide.
- **Lien avec nos traces (§F)** : le re-scellement observé (SAVE@TAG05, maîtres corrigés sans effet) est **compatible**
  avec « le SEP ne retrouve pas l'entropie du Secure Storage Component dans notre contexte de boot m1n1 et repart sur
  une base fraîche ». Le guide **appuie** cette lecture au niveau conception, sans la démontrer.
- **Pas de contradiction** doc↔traces : le guide est muet sur le protocole de boot précis ; nos traces montrent le
  comportement, le guide donne le **pourquoi plausible** (fraîcheur hors-disque, matérielle).

### L. Ligne rouge / périmètre
- Source = **document de conception public Apple**, cité verbatim, **aucune clé ni secret extrait**, aucun firmware.
  Conforme (Albert a autorisé cette source ce jour, pour ce point précis). Rien envoyé vers Asahi.
