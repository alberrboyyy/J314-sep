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
