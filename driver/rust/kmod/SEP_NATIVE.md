# sep_native — pilote Rust de boot du SEP (option (b) du design)

Fichiers : `sep_native.rs` (ce dossier), `driver/linux/sep_native_ovl.c` + `driver/linux/sep-native-overlay.dts`.
Conception : `docs/driver_rust_design.md` (§2 option (b), §3.1-3.3, §3.6). **Compilé, jamais chargé.**

## Ce que ça fait

1. `sep_native_ovl.ko` (C) ajoute à chaud un nœud `/soc/sep-native` (compatible `j314c,sep-native`) qui reprend
   les références du nœud `apple,sep` d'origine : `mboxes` (sep_mbox), `iommus` (sep_dart + stream id),
   `power-domains` (ps_sep), `memory-region` = `sepfw`, et `j314c,sep-node` = le nœud d'origine (où m1n1 a mis
   les manifestes). Valeurs lues sur le DT vivant, à la place des marqueurs `0xdeadbe01..06` du dtbo.
   Le nœud `apple,sep` reste `disabled` : `apple_sep` (intégré, `CONFIG_APPLE_SEP=y`) ne se lie jamais.
   Refus si : `sepfw` absent (cas du boot normal actuel), nœud `apple,sep` non `disabled`, cible d'un phandle
   au compatible inattendu, marqueur absent ou en double, nœud déjà présent.
   Seule retouche du DT vivant : si le nœud `apple,sep` n'a pas de phandle, il en reçoit un, en mémoire
   (comme `mesa_ovl.c` pour ps_spi2).
   Au déchargement, l'overlay n'est retiré que si `sep_native` n'est pas lié au nœud.
2. `sep_native.ko` (Rust) se lie à ce nœud. Probe : contrôle du nœud d'origine (`apple,sep` + `disabled`),
   région `sepfw`, manifestes, shmem de 0x30000 octets (DMA cohérent sur le DART du SEP), mailbox `mbox`
   prise (réception active). Tout est journalisé. **Avec `allow_boot=0`, rien n'est envoyé au SEP.**
3. `allow_boot=1` : séquence de m1n1 `proxyclient/m1n1/hw/sep.py` `SEP.boot()` :
   `GET_STATUS` → `0x66` (DATA 1) ; `BOOT_TZ0` → `0x69` puis `0xD2` ; `GET_STATUS` → `0x66` (DATA 2) ;
   mapping du firmware ; `BOOT_IMG4` (EP 0xFF, IOVA fw >> 12) + `SET_SHMEM` (EP 0xFE, TYPE 0x18, IOVA shmem >> 12)
   → `0x6A` ; démapping du firmware. Timeout de 5 s par réponse. Puis écoute 3 s et affiche la table 0xFD.
4. Après le boot, le pilote **n'envoie plus rien**. Messages connus, journalisés sans réponse : annonces 0xFD
   TYPE 0/1, CNTL spontanés `0x0d`/`0x29`/`0x10` (TAG 0), 1re requête de `xarm` (TAG 2, TYPE 0x0e). Tout autre
   message → `Halted`.

## Paramètres (u32, défaut 0, absents de sysfs : figés au chargement)

| Paramètre | Effet |
|---|---|
| `allow_boot` | 1 = séquence de boot ci-dessus. 0 = probe seul. |
| `allow_xart`, `allow_xart_save_ack`, `allow_sbio`, `allow_sks` | **non implémentés** : toute valeur ≠ 0 fait échouer le probe (EINVAL). Aucun chemin d'envoi vers 0x13, 0x12, 0x08 n'existe dans le code ; aucun ACK de SAVE. |

## États

`Idle` (probe fait, rien envoyé) → `Booting` (seuls des mots EP 0xFF sont admis, dans l'ordre attendu) →
`Running` (passage à la réception de 0x6A ; écoute seule) ; à tout moment → `Halted`, définitif jusqu'au
power-cycle : plus aucun envoi (le seul chemin d'envoi, `send()`, n'accepte que `Booting`).
Causes de `Halted` : message reçu en `Idle`, message hors EP 0xFF pendant le boot, réponse ROM d'un autre TYPE
ou d'une autre DATA (0x66), timeout, signal, erreur mailbox, IOVA inutilisable, anneau RX plein, message
inconnu après le boot, EP annoncé deux fois.

Réception : callback mailbox (IRQ dure) → anneau fixe de 64 mots → un seul work qui vide dans l'ordre.
**Écart au design** : anneau atomique à un producteur / un consommateur au lieu d'un `SpinLock` : le Rust de
cet arbre n'a pas de spinlock qui coupe les IRQ, et un `SpinLock` simple partagé entre IRQ et work peut bloquer
un CPU. Producteur unique garanti par `mbox->rx_lock` (`mailbox.c`), consommateur unique = un seul `work_struct`.

Après le 1er mot envoyé : le module prend une référence sur lui-même (rmmod → EBUSY jusqu'au reboot), un unbind
fuit volontairement mailbox, shmem et mapping firmware, et tout nouveau probe est refusé (EBUSY).

## Vérifié / hypothèse

| Élément | Statut |
|---|---|
| Séquence GET_STATUS / TZ0 / GET_STATUS / IMG4 + SET_SHMEM / 0x6A sous m1n1 | éprouvée sous m1n1 (route native) ; **jamais exécutée par ce pilote** |
| Encodage du mot (EP/TAG/TYPE/PARAM/DATA) | `hypothèse (cohérent)`, éprouvé de fait par tous les runs natifs (sep-proto `word`) |
| DATA de 0x66 = 1 puis 2 | `source: kext` + trace C11 (macOS) ; m1n1 ne la vérifie pas. Contrôle strict ici (fail-closed) |
| Magic `CINP` du tampon panique | m1n1 ; `sep.rs` écrit `CNIP`. **À confirmer** (const `SHMEM_MAGIC_PANIC`) |
| TYPE 0x18 de SET_SHMEM | m1n1 ; macOS envoie 0x1c (design Q11) |
| Timeout 5 s, attente de découverte 3 s | hypothèse (aucune mesure de latence de la ROM) |
| IOVA choisies par Linux (et non 0xDEAD0000/0xBEEF0000) | inconnu (design Q3) |
| Mapping fw BIDIRECTIONAL (comme m1n1 : PTE sans protection), et non TO_DEVICE comme `sep.rs` | choix déduit |
| Barrière `dmb oshst` (dma_wmb) avant IMG4/SET_SHMEM | déduit (comme `rtkit.c`), design Q9 |
| Liste des messages connus après boot | traces C1 (19/19) et SEP-BOOT 2026-11-09 ; hypothèse |

Différences avec m1n1, côté AP seulement : TAG 0 comme m1n1 (macOS met 1) ; le firmware est mappé juste avant
IMG4 et non avant le 1er GET_STATUS (le SEP ne voit l'IOVA qu'avec IMG4).

## Test, plus tard

Prérequis : un boot où m1n1 a réservé `sepfw`, c.-à-d. un DT de boot qui porte l'alias `sep`. Aujourd'hui :
tethered boot (`pending/j2_sep_boot_linux.sh`). **Chaque 1er run avec `allow_boot=1` = « go » d'Albert**
(écriture SEP, module neuf). Power-cycle entre deux essais (Albert).

1. Compiler : `driver/rust/build.sh` ; `make -C /lib/modules/$(uname -r)/build M=<copie de driver/linux> modules` ;
   `dtc -Wno-mboxes_property -Wno-iommus_property -Wno-power_domains_property -I dts -O dtb -o sep-native.dtbo
   driver/linux/sep-native-overlay.dts`, puis copier `sep-native.dtbo` dans `/lib/firmware/` (root).
2. Lecture seule : `insmod sep_native_ovl.ko` (doit refuser sur un boot sans alias), puis `insmod sep_native.ko`
   (allow_boot=0) : vérifier le log (sepfw, tailles des manifestes, IOVA shmem, mailbox prise, aucun envoi) et
   `/sys/kernel/iommu_groups`. `rmmod sep_native` reste possible à ce stade.
3. Écriture SEP (go d'Albert) : `insmod sep_native.ko allow_boot=1`. Succès attendu : 4 réponses ROM OK,
   « firmware démappé », puis 7 EP annoncés (cntl, hdcp, xars, xarm, hibe, pnon, stac, comme SEP-BOOT
   2026-11-09) et les spontanés connus. Échec : `HALTED : <raison>`, power-cycle.

## Changement proposé pour `pending/j2_sep_boot_linux.sh`

Aujourd'hui le script fait 2 changements au DTB : alias `sep` **et** `status = "okay"` sur `apple,sep`, ce qui
confie le boot à `sep.rs` dès le démarrage (sans GET_STATUS, magic `CNIP`, sans garde). Pour utiliser
`sep_native` :
- ne garder **que** `/aliases/sep = "/soc/sep@396400000"` (m1n1 réserve `sepfw` et copie les manifestes) ;
  le nœud reste `disabled` → rien ne parle au SEP au boot ;
- contrôle P3 : le DTB produit ne diffère du source que par l'alias ; vérifier en plus que `status` vaut
  toujours `disabled` ;
- après le boot, sur ALARM : étapes 1-2 ci-dessus (lecture seule), puis étape 3 sur go d'Albert ;
- résultat attendu côté noyau : aucune ligne `apple-sep` ; lignes `sep_native_ovl:` puis `sep_native`.
Le script reste à réécrire (et relire) avant tout lancement : ce n'est qu'une proposition.
