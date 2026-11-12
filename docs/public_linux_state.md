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
