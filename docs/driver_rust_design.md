# Conception du pilote SEP natif en Rust (Linux, j314c / t6001)

2026-11-22 — Claude (Opus 5.5), étude en lecture seule. Aucun code modifié, aucun matériel, aucune écriture SEP.
But : fixer l'architecture du pilote Linux natif (sans tether) qui remplace le harnais m1n1 `pending/sep_native_*.sh`.

Sources lues :
- Arbre noyau = noyau qui tourne : `~/kbuild/src/linux-asahi-7.2.12-3` (tag AsahiLinux `asahi-7.2.12-3`,
  `uname -r` = `7.2.12-3-1-ARCH`). Les chemins `drivers/…`, `rust/…`, `arch/…` ci-dessous sont relatifs à cet arbre.
- m1n1 local `/home/albert/m1n1` (commit `70757dc7`) : `src/kboot.c`, `proxyclient/m1n1/hw/sep.py`.
- DT vivant d'ALARM (`/proc/device-tree`, `/sys/bus/platform`), lu le 2026-11-22.
- Nos docs : `linux_roadmap.md`, `driver_plan.md`, `messages.md`, `kext_sepmanager.md`, `verification_status.md`,
  `voie_sbio.md`, `route_native.md`, `handler_0x13.md`, `driver/rust/README.md`, `driver/rust/sep-proto/src/`.

Légende : **[public]** = lu dans linux-asahi ou m1n1 ; **[projet]** = nos docs ou traces, avec le statut
`vérifié` ou `hypothèse` de `verification_status.md` (`source: kext` si ça vient d'un désassemblage) ;
**[déduit]** = notre raisonnement, à traiter comme une hypothèse.
Note : `sep-proto/` évolue vite (autre session). On cite donc ses fonctions par leur nom ; les numéros de ligne
indiqués sont ceux du 2026-11-22.

---

## 1. Ce que fait `drivers/soc/apple/sep.rs` (375 lignes)

### 1.1 Déroulé du boot [public]
| Étape | Code | Message |
|---|---|---|
| probe | `sep.rs:341-361` | lit la région réservée `sepfw` (`of.reserved_mem_region_to_resource_byname`, l.346), construit `SepData` (l.347), prend la mailbox `mbox` (l.354-358), puis **envoie tout de suite `BOOT_TZ0`** (`start()`, l.359) |
| `start()` | l.198-206 | `> EP 0xFF TYPE 0x05` (TZ0) |
| ACK1 | l.245 | `< 0xFF 0x69` : ignoré |
| ACK2 | l.246-251 | `< 0xFF 0xD2` → `load_fw_and_shmem()` |
| `load_fw_and_shmem()` | l.207-241 | `dma_map_resource(sepfw)` en DMA_TO_DEVICE (l.208-222), puis `> 0xFF TYPE 0x06 DATA=iova_fw>>12` (IMG4, l.225-231), puis `> 0xFE TYPE 0x18 DATA=iova_shmem>>12` (SET_SHMEM, l.232-239) |
| ACK IMG4 | l.252 | `< 0xFF 0x6A` : ignoré, fin |

- Endpoints traités : seulement `0xFF` (boot) et `0xFD` (découverte) (`process_message`, l.276-283). L'EP `0xFE`
  ne sert qu'à émettre. **Tout le reste est jeté sans log** (`_ => {}`, l.281), CNTL 0x00 compris. Le handler
  0xFD est vide (l.258-275, log commenté) [public].
- Constantes : `SHMEM_SIZE = 0x30000` (l.41), `IOVA_SHIFT = 0xC` (l.61) [public].

### 1.2 Données et verrous [public]
- `SepData` (l.172-180) : `dev`, `mbox: Mutex<Option<Mailbox<SepData>>>` (Mutex qui dort), `shmem: dma::Coherent<[u8]>`,
  `region_params` (adresse et taille de sepfw), `fw_mapped: Atomic<bool>`. Partagé par `Arc` ; `Send`/`Sync` posés
  à la main avec `unsafe impl` (l.323-324).
- Réception : `MailCallback::recv_message` (l.300-321) est appelé **en contexte d'IRQ dure**
  (`rust/kernel/soc/apple/mailbox.rs:32` ; `drivers/soc/apple/mailbox.c:219-227` et `:371-373`, `devm_request_irq`
  non threadé). Pour chaque message, le pilote alloue un `SepReceiveWork` en `GFP_ATOMIC` (l.147-156) et le met sur
  `workqueue::system()` (l.305). Le traitement (`process_message`) tourne ensuite dans la workqueue.
- Envoi : `Mailbox::send(msg, atomic=false)` (`mailbox.rs:84-87`) peut dormir jusqu'à 500 ms si la file TX est
  pleine (`mailbox.c:81`, `:144-150`). Il est appelé sous le Mutex.
- Cycle de références : la mailbox garde un `Arc<SepData>` comme cookie (l.354-358, `mailbox.rs:59-74`).
  `remove()` le casse en remettant `None` (l.285).

### 1.3 Firmware, shmem et IOVA [public]
- **Firmware** : région `memory-region-names = "sepfw"` du nœud, que **m1n1 ajoute seulement si le FDT a l'alias
  `sep`** (`m1n1 src/kboot.c:2321-2347`, région ADT `/chosen/memory-map` `SEPFW`, réservée sous le nom
  `sep-firmware`, compatible `apple,asc-mem`). L'IOVA vient de `dma_map_resource` sur le device `sep`, donc du DART
  `sep_dart` (`iommus = <&sep_dart 0>`, `arch/arm64/boot/dts/apple/t600x-die0.dtsi:458`). Le pilote passe par
  `bindings::` brut, en `unsafe` : il n'existe pas d'abstraction Rust pour ce mapping.
- **Manifestes** : propriétés `local-policy-manifest` et `iboot-manifest`, copiées par m1n1 depuis
  `/chosen/boot-object-manifests` `lpol`/`ibot` (`kboot.c:2353-2365`). `build_shmem` (l.82-132) les recopie dans
  une `dma::Coherent::zeroed_slice` de 0x30000 octets (l.84). Table en tête : 3 entrées de 16 octets (nom, taille,
  offset), puis `llun`.

### 1.4 Écarts relevés entre `sep.rs` et la séquence éprouvée de m1n1 `hw/sep.py`
Notre route native a été validée avec `sep.py` (`pending/sep_native_persist.sh:198`, `sep.boot()`). [projet, vérifié]
1. **Pas de `GET_STATUS`.** `sep.py:107-115` envoie `GET_STATUS` (attend 0x66) avant TZ0 et avant IMG4.
   `sep.rs` n'en envoie aucun. Le kext exige statut 1 puis 2 (`kext_sepmanager.md` §2, `source: kext`). [public + projet]
2. **Magic du tampon panique : `CNIP` (`sep.rs:118`) contre `CINP` (`sep.py:90`).** Le commentaire de m1n1 dit
   « PNIC », soit `CINP` lu à l'envers. `sep.rs` contient donc probablement une coquille. On ne sait pas si SEPOS
   vérifie ce champ. [public ; « coquille » = déduit]
3. **Le firmware n'est jamais démappé.** `sep.py:125` fait `unmap_sepfw()` après 0x6A ; `sep.rs` garde le mapping
   jusqu'à `remove()` (l.286-296). [public]
4. **Aucun timeout ni état.** Si le SEP ne répond pas, rien ne se passe. Une erreur d'IMG4 n'est que loguée
   (l.248-250). probe renvoie OK dès que TZ0 est parti. [public]
5. **Ordre de traitement non garanti.** Chaque message devient un work item séparé sur la workqueue système, qui
   n'est pas ordonnée, et un échec d'allocation `GFP_ATOMIC` perd le message (l.313-318). Pour 0x13 (FETCH/SAVE)
   et le compteur GT de 0x08, il faut un ordre FIFO strict. [public ; conséquence = déduit]
6. **`remove()` est dangereux une fois SEPOS lancé.** Il arrête la mailbox, démappe le firmware, puis libère la shmem
   (drop de `Coherent`). Or le SEP continue de tourner et peut encore faire du DMA. Seul un power-cycle (Albert)
   remet le SEP à zéro. [public + déduit]
7. **Boot automatique au probe, sans garde.** Il suffit d'activer le nœud pour que le SEP soit amorcé au démarrage :
   pas de paramètre de module, pas de fail-closed. [public]
8. `Kconfig` `APPLE_SEP` fait `select RUST_APPLE_RTKIT` (`drivers/soc/apple/Kconfig:104`), alors que `sep.rs`
   n'utilise pas RTKit : le SEP n'est pas un coprocesseur RTKit, seule la mailbox ASC lui sert. [public]

### 1.5 État réel sur ALARM aujourd'hui [public, lu le 2026-11-22]
- `sep@396400000` : `status = "disabled"` (dtsi `:453-461` et `/proc/device-tree`). Il n'a ni `memory-region` ni
  manifestes, et **aucun platform device n'existe** (`396400000.sep` sans pilote).
- Les aliases du DT vivant n'ont pas d'entrée `sep`. `/proc/device-tree/reserved-memory` n'a pas de `sep-firmware`.
  m1n1 n'a donc rien transmis.
- `sep_dart` `3952c0000.iommu` est lié à `apple-dart`. `sep_mbox` `396408000.mbox` est lié à `apple-mailbox`.
- Le DT qui arrive au noyau est celui que m1n1 a patché (il contient les propriétés `asahi,*` de `/chosen`). Il est
  embarqué dans `/efi/m1n1/boot.bin`. Une entrée GRUB `devicetree` (il en existe une, « test PMP » dans
  `/boot/grub/custom.cfg`) **remplacerait** ce FDT patché et ferait perdre `sepfw` et les manifestes. [déduit]

---

## 2. Coexistence avec `CONFIG_APPLE_SEP=y`

Faits de départ [public] : `apple_sep` est intégré au noyau (`config-7.2.12-3-1-ARCH` : `CONFIG_APPLE_SEP=y`,
`CONFIG_RUST_APPLE_MAILBOX=y`, `CONFIG_OF_OVERLAY=y`, `CONFIG_MODULE_SIG` non défini) et il se lie au compatible
`apple,sep` (`sep.rs:328-333`). La mailbox n'a **qu'un seul** callback et un seul cookie
(`mailbox.rs:73-74`), et `apple_mbox_get` n'interdit pas un second client (`mailbox.c:286-320`). Deux pilotes sur
`sep_mbox` s'écraseraient donc sans aucune erreur. **Règle : il ne doit jamais y avoir deux clients de
`sep_mbox`.** [déduit]

Prérequis commun à toutes les options : **l'alias `sep` dans le DT patché par m1n1**, sinon pas de `sepfw`
(`kboot.c:2323-2327`). m1n1 se contente de suivre l'alias, quel que soit le compatible ou le `status` du nœud
(`kboot.c:2345-2365`). Le DT est dans `boot.bin`, c'est-à-dire dans l'installation de m1n1 : **c'est à Albert de
le faire, à la main** (CLAUDE.md, « toucher à m1n1 » interdit à l'agent). [public + projet]

| Option | Principe | Pour | Contre / risques |
|---|---|---|---|
| (a) Noyau custom : remplacer ou étendre `sep.rs` dans l'arbre | patch de `drivers/soc/apple/sep.rs`, `APPLE_SEP=m`, DT j314c `sep` alias + `okay` | forme finale propre ; abstraction partagée possible (`rust/kernel/soc/apple/sep.rs`, sur le modèle d'`aop.rs`, cf. §3.7) | il faut réinstaller un noyau sur la partition principale (risque « perdre Linux », filet = snapshot) ; cycle de build lent ; avec `=y`, pas de rmmod |
| (b) Module hors arbre + compatible distinct | DT : alias `sep` seulement, le nœud reste `disabled` (inerte) ; au chargement, un overlay à chaud crée un nœud `j314c,sep-native` qui pointe vers `sep_mbox`, `sep_dart` et la région `sepfw` ; le module se lie à ce nœud | aucun rebuild du noyau ; `apple_sep` ne se lie jamais (nœud `apple,sep` toujours `disabled`) ; chargé à la main, rmmod possible tant que SEPOS n'est pas lancé ; précédent qui marche : `driver/linux/mesa_ovl.c` (overlay à chaud, phandle patché) | overlay à chaud en C (pas de binding Rust) ; il faut recopier les phandles (`memory-region`) et les propriétés des manifestes depuis le nœud désactivé ; le `reg` est en double avec le nœud désactivé (sans effet tant qu'il reste `disabled`) |
| (b') Variante : l'overlay passe le nœud existant en `okay` et change son compatible | `of_reconfig_get_state_change` crée le pdev au passage disabled→okay (`drivers/of/dynamic.c:121-193`, `drivers/of/platform.c:735`) | un seul nœud, mémoire et manifestes déjà en place | **si le compatible reste `apple,sep` (erreur dans l'overlay), `apple_sep` se lie et boote le SEP sans contrôle** (§1.4-7). Rejetée. |
| (c) Sans DT : adresse SEPFW codée en dur (dump ADT) | | rien à changer dans m1n1 | région non réservée, Linux peut l'écraser ; manifestes inaccessibles (l'ADT n'est pas passé à Linux) ; fragile. Rejetée. |

**Recommandation** [déduit] :
- **Phase de développement = (b)** : DT avec l'alias `sep` seulement (inerte, fait par Albert) + module Rust hors
  arbre `sep_native.ko` construit par `driver/rust/build.sh`, et petit module C `sep_native_ovl.ko` (calqué sur
  `mesa_ovl.c`) qui crée le nœud distinct. Rien ne parle au SEP sans paramètre de module explicite (§3.6).
- **Forme finale = (a)** : le même code remplace `sep.rs` dans l'arbre (compatible `apple,sep`, `tristate m`), et les
  services (sbio, SKS) passent en sous-pilotes. Cette bascule n'a lieu qu'une fois les étapes J2-J4 franchies avec
  (b).
- Une fois SEPOS lancé, **le module refuse le rmmod** : il garde une référence sur lui-même et retourne `EBUSY`, et
  ne libère jamais la shmem ni les OOL mappés (§1.4-6). Seul un power-cycle permet de recommencer.
- **Variante sans toucher `boot.bin`** : le tethered boot (`tools/tethered_boot.sh`, déjà éprouvé ; cf.
  `pending/j2_sep_boot_linux.sh`) fait passer par m1n1 un DTB qui porte l'alias, et `dt_set_sep` le remplit. En
  dev, **ce DTB ne doit porter que l'alias** (nœud `apple,sep` laissé `disabled`) si l'on veut utiliser (b). Le
  passer en `okay`, c'est confier le boot à `sep.rs` avec ses écarts du §1.4 (pas de GET_STATUS, `CNIP`, aucune
  réponse à 0x13). [projet + déduit]

---

## 3. Architecture

```
 userspace : septouchd (Rust std, sep-proto complet : politique xART, store, init sbio, blobs 0x6c/0x6d, DER SKS)
     │  /dev/sep_native (miscdevice : ioctl + read bloquant)          capteur : mesa (C, spi-apple) — hors de ce doc
 ────┼──────────────────────────────────────────────────────────────
 L5  │ services : xart (0x13)  │ sbio (0x08, GT)  │ sks (0x12, plus tard)
 L4  │ ouverture d'EP : CNTL 0x00 (SECMODE, OOL A/B 4/2/5/3, ack par TAG)   table de découverte 0xFD (nom→EP)
 L3  │ boot ROM : GET_STATUS / TZ0 / IMG4 / SET_SHMEM (0xFF/0xFE) — machine à états avec timeouts
 L2  │ cœur : file RX FIFO (SpinLock + 1 work), état global (Halted), file d'envoi sérialisée, sep-proto `word`
 L1  │ kernel::soc::apple::mailbox::Mailbox + dma::Coherent sur le device (DART sep, stream 0)
```

### 3.1 L1-L2 Transport [public pour les briques, déduit pour le design]
- **RX** : le callback IRQ ne fait que copier le mot dans un anneau de taille fixe (`SpinLock<[Message; N]>`, rien
  n'est alloué en IRQ) et met en file **un seul** `Work` s'il n'est pas déjà en attente. Le work vide l'anneau
  dans l'ordre. Ainsi l'ordre FIFO est garanti et aucun message n'est perdu sur un échec d'allocation, ce qui
  corrige §1.4-5. Si l'anneau déborde, on passe en `Halted`.
- **TX** : une seule fonction `send(word)` qui vérifie la porte de l'EP (§3.6), puis appelle `Mailbox::send(…, false)`
  depuis le work ou depuis un ioctl, jamais depuis l'IRQ.
- **Attentes** : `CondVar::wait_interruptible_timeout` (`rust/kernel/sync/condvar.rs:186`) ou le motif
  `FutureValue` d'`aop.rs:153-184`. `Completion` (`rust/kernel/sync/completion.rs:98-110`) n'a pas de variante avec
  timeout dans cet arbre.
- **Mot** : sep-proto `word::Word::checked` (encodage EP/TAG/TYPE/PARAM/DATA, `Result`, sans panique). Le découpage
  des bits est une `hypothèse (cohérent)` dans `verification_status.md`, mais il a été éprouvé de fait par tous les
  runs natifs. [projet]
- **DMA** : `dma::Coherent::<u8>::zeroed_slice(dev, len, GFP_KERNEL)` (`rust/kernel/dma.rs:857`) pour la shmem et
  les OOL ; IOVA = `dma_handle()` (`dma.rs:633`). L'accès CPU passe par `as_mut()`, qui est `unsafe` (`dma.rs:661`) :
  à encapsuler une seule fois. Il faut une barrière d'écriture (`dma_wmb`, par `bindings`) avant l'envoi du mot qui
  annonce un tampon. [déduit]

### 3.2 L3 Boot ROM [public + projet]
On reproduit `sep.py:104-125`, qui est la séquence éprouvée, et non `sep.rs` :
`GET_STATUS`→0x66, `TZ0`→0x69 puis 0xD2, `GET_STATUS`→0x66, `IMG4` (IOVA fw>>12), `SET_SHMEM` (0xFE, TYPE 0x18,
IOVA shmem>>12)→0x6A, puis démapping du firmware. La shmem utilise `CINP` (§1.4-2). Chaque attente a un timeout ;
un code inattendu fait passer en `Halted` sans rien envoyer d'autre. Les IOVA choisies par Linux ne sont pas celles
de m1n1 (`0xDEAD0000`/`0xBEEF0000`, `sep.py:59-60`) : voir Q3.

### 3.3 L4 CNTL et découverte [projet, `source: kext` + traces]
- **Découverte 0xFD** : TYPE 0 = (PARAM = numéro d'EP, DATA = nom ASCII), TYPE 1 = pages OOL min/max
  (`kext_sepmanager.md` §4). L'ordre change d'un boot à l'autre : **on cherche toujours un EP par son nom** (`sbio`,
  `xarm`, `sks `). sep-proto `discovery::DiscoveryTable::find` fait ce travail, mais utilise `BTreeMap`/`alloc` (cf.
  §4) : côté noyau, on prendra un tableau fixe de 256 entrées. Statut : `hypothèse` (noms et tailles), mais 12/12
  conformes à la doc Asahi.
- **CNTL EP 0x00** : TAG = indice du pool + 1 (1..8), ack `<TYPE 0x01` avec le même TAG et la DATA en écho.
  Avant toute ouverture : attendre l'annonce de l'EP visé, puis `SECMODE 0x14`
  (`pending/sep_native_persist.sh:199-208`). Ouverture : `0x04` taille A, `0x02` IOVA A>>12, `0x05` taille B,
  `0x03` IOVA B>>12, avec PARAM = EP, chaque message attendant son ack (timeout de 5 s dans le harnais, l.138-144).
  A = AP→SEP, B = SEP→AP (`kext_sepmanager.md` §3 ; reste `hypothèse` pour la ligne A/B, mais la route native
  fonctionne avec ce sens). Tailles : 0x13 = 0x8000/0x8000, 0x08 = 0x4000/0x4000 (`messages.md` §Endpoints). Les
  `<0x0d`, `<0x29`, `<0x10` sur l'EP 0 sont spontanés et bénins (`kext_sepmanager.md` §3) : ils figurent dans la
  liste des messages connus.
- **Pas d'envoi à un EP de service avant « SEP/OS alive »** (`kext_sepmanager.md` §1). [projet, source: kext]

### 3.4 L5 Services
- **xART 0x13** (`handler_0x13.md` §1, `route_native.md` §6) [projet] : la politique native « FETCH → ABSENT si
  absent du store / servir si présent ; SAVE → stocker puis ACK » est **`vérifiée` sur matériel sous m1n1**
  (n=4 : stabilisation, `sbio`+`sks` annoncés ; `verification_status.md:155`). Côté code : sep-proto
  `xart::encode_fetch_len`, `xart_responder::observed_response` (l.55), `native_fetch_decision` (l.87),
  `native_on_save` (l.98). Répartition [déduit] :
  le **store persistant reste dans le démon** (fichier), qui le **précharge** par ioctl avant le boot. Le noyau
  répond aux FETCH depuis cette copie en RAM et **n'acquitte un SAVE qu'après que le démon a confirmé l'écriture
  durable** (fsync) du blob. Un SAVE acquitté puis perdu ferait diverger le compteur scellé. Le harnais tolérait la
  latence USB (`pending/sep_native_persist.sh`), donc un aller-retour vers userspace est acceptable (`hypothèse`).
  Il faut aussi un **budget de SAVE borné** (le harnais utilise `MAX_SAVES`) et l'arrêt sur toute op 0x13 absente
  de la liste connue (0x0e, 0x13, 0x00, 0x05, 0x07, 0x1d, 0x01, 0x06).
- **sbio 0x08 (GT)** [projet] : mot `request ∈ {0xfc,0xfd,0xfe}`, TYPE = opcode, DATA = compteur<<16 par sens
  (**`vérifié` côté macOS**, 4006/4006). OOL = `gt_packet_t` : en-tête de 0x1c octets, `+0x14` = opcode,
  fragmentation à 0x3fe4 octets par tranche (**`vérifié`**, `verification_status.md:128`). Transaction maximale
  0x4b000 (`kext_sepmanager.md:102`, source: kext). Code : sep-proto `gt::CounterChecker` (sans alloc, réutilisable
  dans le noyau) et `gt::fragment` (`gt.rs:278`, renvoie `Vec<Vec<u8>>` : à réécrire en itérateur sur une tranche
  pour le noyau). Le noyau fournit **un appel par transaction** : (opcode, charge) → fragments vers A, puis
  réassemblage de B → réponse. La séquence d'init (57 commandes, `vérifié` macOS) et le relais capteur restent dans
  le démon (sep-proto `daemon`, `sensor`). Les notifications hors 0xfc (TAG 0x01 lockState, 0x02 à 0x04) remontent
  telles quelles en événements.
- **SKS 0x12** (plus tard) [projet, source: kext, `hypothèse`] : RPC à paramètres DER, le mot ne porte qu'un compteur
  et une longueur (`kext_sepmanager.md` §14b-§15). Le noyau ne fait que transporter des octets opaques ; tout le DER
  est dans le démon. **Écriture d'une classe jamais testée** (porte d'Albert).

### 3.5 Interface userspace [déduit]
- **miscdevice `/dev/sep_native`** (`rust/kernel/miscdevice.rs:125-180` : `open`, `read_iter`, `write_iter`,
  `ioctl`). C'est le choix le plus simple. Netlink n'a pas d'abstraction Rust dans cet arbre (`rust/kernel/net/` ne
  contient que `phy`), et sysfs ne convient pas à un flux de messages. **Pas de `poll`** dans le trait
  `MiscDevice` de cet arbre : le démon utilise un `read` bloquant dans un thread dédié.
- ioctls (un seul ouvreur, `EBUSY` sinon) : `GET_STATE` (état L3, `Halted` + raison), `GET_EPTABLE`,
  `XART_LOAD_STORE`, `XART_SAVE_DONE(seq)`, `SBIO_TRANSACT(opcode, buf)`, `SKS_TRANSACT(buf)` (refusé tant que la
  porte est fermée), `BOOT` (refusé si `allow_boot=0`).
- `read` renvoie des événements : messages non sollicités, SAVE xART à persister (blob B), notifications sbio et
  `Halted`.
- **Aucun ioctl « mot brut vers un EP quelconque »**. On ne peut écrire au SEP que par des chemins typés, chacun avec
  sa porte.

### 3.6 Fail-closed et paramètres de module [projet (règles CLAUDE.md) + déduit]
Paramètres `u32` (0 ou 1), **tous à 0 par défaut**. `module_param.rs` n'implémente que des entiers (l.97-104), pas
de `bool`. `module_platform_driver!` transmet `params:` à `module!` (`rust/kernel/platform.rs:155-158`,
`rust/kernel/driver.rs:264-290`).

| Paramètre | Ouvre | Classe d'écriture (CLAUDE.md) |
|---|---|---|
| `allow_boot` | GET_STATUS/TZ0/IMG4/SET_SHMEM, CNTL SECMODE | éprouvée sous m1n1 ; **1er run du module = go d'Albert** |
| `allow_xart` | ouverture de 0x13, réponses FETCH (absent/servi) | éprouvée (route native) ; 1er run du module = go |
| `allow_xart_save_ack` | ACK des SAVE (fait avancer le compteur scellé) | éprouvée ; 1er run = go |
| `allow_sbio` | ouverture de 0x08, transactions GT | 0x73 et escalade éprouvés ; toute nouvelle phase = go |
| `allow_sks` | 0x12 | **jamais testée** : go obligatoire |
| `max_saves` | budget de SAVE (défaut 48, comme le harnais) | — |

Règles noyau : (1) au premier message inattendu (EP, TYPE ou op absents de la liste connue, ack manquant, timeout,
compteur GT faux, débordement d'anneau), on passe en **`Halted`** de façon définitive jusqu'au power-cycle : plus
aucun envoi, et l'événement remonte au démon ; (2) aucun envoi vers un EP qui n'a pas été annoncé ou ouvert ;
(3) la liste des messages connus est construite **à partir de toutes les captures**, pas d'un sous-ensemble (règle
CLAUDE.md du 2026-11-12) ; (4) jamais d'écriture vers le Secure Element Stockholm (aucun chemin n'existe dans le
pilote) ; (5) les paramètres sont en lecture seule après le chargement (perm 0444), pour que « armer » demande un
rechargement explicite.

### 3.7 Organisation du code [déduit]
- `sep_native.ko` (Rust) : `core` (L1-L2), `boot` (L3), `ep` (L4), `xart`, `sbio`, `sks`, `uapi` (miscdevice).
  Modèle à suivre : `aop.rs`, avec `AopData` et ses Mutex par EP (`drivers/soc/apple/aop.rs:631-642`), le motif
  `FutureValue` (l.153-184) et des sous-devices `platform_device_register_full` (l.700). La forme finale (a) pourra
  exposer un trait `Sep` dans `rust/kernel/soc/apple/`, comme `aop.rs` le fait avec son trait `AOP`
  (`rust/kernel/soc/apple/aop.rs:24-46`).
- **sep-proto dans le noyau** : les modules hors arbre n'ont que `--extern pin_init, kernel, zerocopy`
  (`scripts/Makefile.build:334-335`), donc **ni `alloc` ni crate externe**. On n'y embarque que le cœur
  `no_std` sans alloc : `word`, `crc`, `gt::CounterChecker` et l'en-tête, le codec `xart`. Inclusion possible par
  `#[path]` à la racine du crate : c'est déjà fait et chargé par `driver/rust/kmod/sep_proto_selftest.rs:15-34`
  (commit `83bbbe0`), voir Q8. Le reste de sep-proto (`discovery` table, `daemon`,
  `xart` store, `trace`) est pour le démon. Le noyau reste mince ; la politique et le stockage vivent en userspace.

---

## 4. Abstractions Rust : présentes ou manquantes dans cet arbre [public]

| Couche | Présent | Manque, et comment contourner |
|---|---|---|
| Mailbox ASC | `kernel::soc::apple::mailbox::{Mailbox, MailCallback, Message}` (`mailbox.rs:28-88`), compilé car `RUST_APPLE_MAILBOX=y` (`soc/apple/mod.rs:122-123`) ; symboles C exportés (`mailbox.c:164,272,284,320,332`) ; `apple_mbox_poll` exporté (l.241) mais sans wrapper Rust | callback en IRQ dure (§3.1) ; pas de `poll` Rust (utile pour un mode synchrone) → `bindings::apple_mbox_poll` |
| RTKit | `rtkit.rs` (non utile au SEP) | — |
| DMA cohérent | `dma::Coherent<[u8]>`, `CoherentBox`, `CoherentHandle` (`dma.rs:418-1100`), `dma::Device::dma_set_mask` (l.58-104) | `dma_map_resource` (firmware) : `bindings` en `unsafe`, comme `sep.rs` ; pas de barrière `dma_wmb` Rust exposée ici (à vérifier) |
| OF / DT | `of::Node::reserved_mem_region_to_resource_byname` (`of.rs:225`), propriétés via `fwnode` | **overlay DT : aucun binding Rust** → module C (`of_overlay_fdt_apply`, précédent `driver/linux/mesa_ovl.c:65`) |
| Platform driver | `platform::Driver` (`platform.rs:209-246`, `probe`, `unbind`), `module_platform_driver!` | — |
| Workqueue | `Work`, `WorkItem`, `system()…system_bh()` (`workqueue.rs:465-1111`) | **pas de création de workqueue ordonnée** (`alloc_ordered_workqueue`) en Rust → anneau + un seul work (§3.1), ou `bindings` + `Queue::from_raw` (l.262) |
| Sync | `Mutex`, `SpinLock`, `CondVar` avec timeout, `Completion` sans timeout, `PollCondVar` | — |
| Userspace | `miscdevice` (sans `poll`), `uaccess::UserSlice`, `ioctl` | netlink absent |
| Paramètres | `module!{ params: }`, types entiers | pas de `bool` → `u32` |
| SPI (capteur) | **aucun** `rust/kernel/spi.rs` | capteur en C (`driver/linux/mesa_*`), ou démon via spidev ; le DMA SIO 22 Ko reste un écart à coder en C (`linux_roadmap.md` §2, J5) |
| Chaîne de build | `driver/rust/build.sh` + `kmod/` ; `sep_hello.ko` chargé et déchargé sur ALARM (`driver/rust/README.md`) | — |

---

## 5. Étapes ordonnées

Marques : **offline** (PC ou Mac, sans device), **lecture** (touche au Mac, mais rien n'est envoyé au SEP),
**écriture SEP** (go d'Albert pour le 1er run de chaque script ou module neuf, CLAUDE.md), **Albert-manuel** (hors
périmètre de l'agent).

| # | Étape | Marque | Roadmap |
|---|---|---|---|
| 1 | Séparer sep-proto en cœur noyau (sans alloc, sans `crate::` externe) et partie démon ; tests de rejeu conservés | offline | J1 |
| 2 | Écrire L2-L4 (anneau RX, machine boot, CNTL, découverte) en Rust **testable hors noyau** derrière un trait `Transport`, rejoué contre `traces/` (C1, C11, C12, runs natifs du 2026-11-22) : le noyau ne fait que l'emballer | offline | J1 |
| 3 | Squelette `sep_native.ko` + `sep_native_ovl.ko` (C), params à 0, miscdevice, refus du rmmod après boot ; build par `build.sh` | offline | J1 |
| 4 | Ajouter l'alias `sep` au DT de `boot.bin` (le nœud reste `disabled`), puis vérifier `/proc/device-tree` : `sep-firmware` réservé, `local-policy-manifest` et `iboot-manifest` présents | **Albert-manuel**, puis lecture | J2 |
| 5 | Charger l'overlay et le module avec tous les params à 0 : probe, mailbox prise, buffers alloués, **aucun envoi**. On vérifie l'absence de trafic, l'IOVA attribuée et le groupe IOMMU | lecture | J2 |
| 6 | `allow_boot=1` : GET_STATUS/TZ0/IMG4/SHMEM, puis découverte et SECMODE. On attend 12 EP annoncés. Si ça échoue : `Halted`, power-cycle | **écriture SEP** (classe éprouvée, module neuf → go) | J2 |
| 7 | `allow_xart=1, allow_xart_save_ack=1` : ouverture 0x13 + politique native avec démon et store **neuf et séparé** ; on attend la stabilisation et `sbio`/`sks` annoncés (comme `verification_status.md:155`) | **écriture SEP** (go) | J4 (partie xART) |
| 8 | `allow_sbio=1` : ouverture 0x08 + 0x73 sans doigt ; on attend la réponse identique à c12 | **écriture SEP** (go) | J3 |
| 9 | Démon : init sbio (0x17, échange de clés 0x15/0x16, compteur 0x42/0x18, patch 0x5f…), capteur par mesa, ordre calqué sur `pending/sep_native_sbio9-11.sh` | **écriture SEP** à chaque nouvelle phase (go) ; DMA SIO 22 Ko = écart en C | J5 |
| 10 | SKS 0x12 (DER, gating D2) | **écriture SEP, classe jamais testée** (go obligatoire) | J4 (partie SKS) |
| 11 | Match, enrôlement Linux, libfprint/PAM | session humaine + go | J6 |
| 12 | Bascule (a) : intégrer dans l'arbre à la place de `sep.rs`, DT j314c propre | offline, puis install noyau (Albert) | final |

L'ordre 7 avant 8 suit le résultat vérifié de la route native : sbio ne s'arme qu'une fois xART scellé
(`route_native.md` §2, `verification_status.md:155`). [projet, vérifié]

---

## 6. Questions ouvertes

- **Q1 — État du SEP à la remise à Linux.** Sous le harnais, m1n1 trouvait la ROM prête (GET_STATUS = 1). Au boot
  normal, m1n1 stage 2 a déjà parlé au SEPROM (`sep_init`, GETRAND pour `kaslr-seed` ; `public_linux_state.md`
  §1.1). On ne sait pas si l'état est le même au moment du probe Linux. À lire à l'étape 6 (GET_STATUS en premier,
  arrêt si le statut n'est pas 1). [inconnu]
- **Q2 — Le reboot logiciel.** CLAUDE.md : un reboot logiciel fige le PMU/SPMI. Après un SEPOS amorcé par Linux,
  un `reboot` mène-t-il à un état sain ? Il faut prévoir un power-cycle (Albert) entre deux essais. [projet]
- **Q3 — IOVA et DART.** Linux choisit les IOVA (allocateur iommu-dma, masque 32 bits par défaut), alors que m1n1
  utilisait des IOVA fixes sur le stream 0. Le SEP accepte-t-il n'importe quelle IOVA ? Le fait que des IOVA
  arbitraires comme `0xDEAD0000`/`0xBEEF0000` marchent le laisse penser (déduit). Le DART SEP est-il « locked » par
  iBoot (`apple-dart.c:788-802` gère ce cas) ? Le stream 15 (sids `0x8001`) n'est pas déclaré dans le DT et n'a pas
  été nécessaire (`voie_sbio.md` §3 et §7). [inconnu / projet]
- **Q4 — Région `sepfw`.** Elle est réservée sans `no-map` (`kboot.c:2340`, `false`). `dma_map_resource` sur de la
  RAM, et non du MMIO, comme le fait `sep.rs` : acceptable avec un IOMMU, mais à surveiller. [déduit]
- **Q5 — Latence des réponses.** Délai maximal toléré par le SEP pour FETCH/SAVE et les acks CNTL : inconnu. Le
  harnais par USB est passé, ce qui donne une borne haute large. [projet, hypothèse]
- **Q6 — UUID d'OS (op 0x13) et cohabitation avec macOS** (`handler_0x13.md` §3) : quel UUID renvoyer, et le master
  xART est-il partagé (risque de thrash en dual-boot) ? macOS est déclaré sacrifiable, mais la question reste
  ouverte. [projet]
- **Q7 — rmmod / unbind.** On peut bloquer le rmmod, mais pas un `unbind` sysfs : le pilote doit alors fuir
  volontairement la shmem et les OOL (ne pas les démapper). Reste à voir comment l'écrire proprement avec
  `dma::Coherent` (par exemple `mem::forget` dans `unbind`). [déduit]
- **Q8 — Inclure sep-proto dans kbuild.** C'est en grande partie résolu : `sep_proto_selftest.rs` inclut les
  modules par `#[path]` à la racine du crate, et le cœur compile sans `alloc` (`sep-proto/Cargo.toml`, feature
  `alloc`). Il reste à décider ce qui, de `discovery` et `gt::fragment`, passe en version sans allocation côté
  noyau. [projet]
- **Q9 — Barrières et cohérence.** `dma::Coherent` est non caché/cohérent. Faut-il un `dma_wmb` explicite avant le
  mot mailbox (`writeq_relaxed`, `mailbox.c:156-158`, sans barrière) ? Probablement oui. [déduit]
- **Q10 — Capteur.** L'absence de binding Rust SPI et le DMA SIO 22 Ko (`linux_roadmap.md` §2) restent des écarts en
  C, hors de ce pilote. Le démon fait le pont entre les deux. [public + déduit]
- **Q11 — TYPE 0x18 de SET_SHMEM (EP 0xFE).** D'après le kext, ce serait une taille (0x18 pages = 0x18000 octets) alors que
  la shmem fait 0x30000 octets (`kext_sepmanager.md` §2, `hypothèse`). Ça fonctionne tel quel sous m1n1 ; on ne
  change rien sans expérience. [projet]
