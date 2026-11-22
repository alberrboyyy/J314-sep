# sep_native — pilote Rust de boot du SEP (option (b) du design)

Fichiers : `sep_native.rs` (ce dossier), `driver/linux/sep_native_ovl.c` + `driver/linux/sep-native-overlay.dts`.
Conception : `docs/driver_rust_design.md` (§2 option (b), §3.1-3.6). Boot (`allow_boot=1`) **éprouvé sur matériel
le 2026-11-22** (`docs/journal.md`). Service xART (`allow_xart`) : **compilé, jamais chargé.**

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
4. Après le boot, avec `allow_xart=0`, le pilote **n'envoie plus rien**. Messages connus, journalisés sans réponse :
   annonces 0xFD TYPE 0/1, CNTL spontanés `0x0d`/`0x29`/`0x10` (TAG 0), 1re requête de `xarm` (TAG 2, TYPE 0x0e).
   Tout autre message → `Halted`.
5. `allow_xart=1` (exige `allow_boot=1`) : au probe, deux tampons DMA cohérents de 0x8000 o (A = AP→SEP,
   B = SEP→AP). Après le boot et les 3 s d'écoute, si `xarm` est annoncé **en 0x13** : ouverture par le CNTL comme
   `pending/sep_native_persist.sh` : `SECMODE` (TYPE 0x14, PARAM 0, DATA 0), puis TYPE 0x04 (taille A), 0x02
   (IOVA A >> 12), 0x05 (taille B), 0x03 (IOVA B >> 12), PARAM = 0x13, TAG 1..8, chacun attend son ack
   `< TYPE 0x01` de même TAG (5 s). Puis création de `/dev/sep_native`, servi par le démon `driver/rust/sepd`.
   Le noyau **ne garde ni store ni politique** : il met en file les requêtes 0x13, copie B à leur arrivée, et
   n'envoie une réponse du démon qu'après l'avoir contrôlée (`sep-proto/src/xart_gate.rs`, `check_reply`).
   CNTL `< 0x11` → `> 0x12` (même TAG) est servi (comme `pump_ep0` du harnais).
6. SAVE (0x01 maître, 0x06 locker) : **avec `allow_xart_save_ack=0`, un SAVE reçu → `Halted` sans ACK**
   (fail-closed, comme `pending/sep_native_0x13.sh`). Avec `allow_xart_save_ack=1` : la requête est remise au démon
   avec B ; le démon écrit le blob sur disque (tmp + fsync + rename + fsync du dossier) **avant** de soumettre l'ACK.
   Le noyau passe en `Halted` juste après le 48e ACK (`MAX_SAVES`, comme le harnais).
7. Aucun chemin d'envoi vers 0x08 (sbio) ni 0x12 (sks) : la porte d'envoi (`send_running`) n'admet que l'EP 0x00
   (TYPE 0x14, 0x02-0x05, 0x12) et l'EP de `xarm` une fois ouvert, et refuse explicitement 0x08 et 0x12.

## Paramètres (u32, défaut 0, absents de sysfs : figés au chargement)

| Paramètre | Effet |
|---|---|
| `allow_boot` | 1 = séquence de boot ci-dessus. 0 = probe seul. |
| `allow_xart` | 1 = ouverture de 0x13 et `/dev/sep_native` (réponses 0x0e, 0x13, FETCH servi/ABSENT, 0x07, 0x1d). Exige `allow_boot=1` (sinon EINVAL). |
| `allow_xart_save_ack` | 1 = le démon peut acquitter les SAVE (⚠️ le compteur scellé avance). 0 = un SAVE → `Halted`. Exige `allow_xart=1`. |
| `allow_sbio`, `allow_sks` | **non implémentés** : toute valeur ≠ 0 fait échouer le probe (EINVAL). |

## États

`Idle` (probe fait, rien envoyé) → `Booting` (seuls des mots EP 0xFF sont admis, dans l'ordre attendu) →
`Running` (passage à la réception de 0x6A ; écoute seule) ; à tout moment → `Halted`, définitif jusqu'au
power-cycle : plus aucun envoi (le seul chemin d'envoi, `send()`, n'accepte que `Booting`).
Causes de `Halted` : message reçu en `Idle`, message hors EP 0xFF pendant le boot, réponse ROM d'un autre TYPE
ou d'une autre DATA (0x66), timeout, signal, erreur mailbox, IOVA inutilisable, anneau RX plein, message
inconnu après le boot, EP annoncé deux fois ; et avec `allow_xart` : TYPE 0x13 hors liste (0x0e, 0x13, 0x00, 0x05,
0x07, 0x1d, 0x01, 0x06), SAVE sans `allow_xart_save_ack`, requête autre que 0x0e avant l'ouverture, longueur B hors
tampon (FETCH locker : B ≠ 16 o), deux requêtes à tampon B en attente, plus de 16 requêtes en attente, ack CNTL
absent ou de TAG inattendu, réponse du démon refusée par `check_reply` (ou à un `seq` inconnu), 48e SAVE acquitté.

**Après l'ouverture de 0x13, journalisé et ignoré (ni réponse, ni `Halted`)**, comme le harnais m1n1 qui ne lisait
que l'EP 0 et 0x13 : tout message sur un **autre EP annoncé** (0x08 sbio, 0x12 sks, 0x10, 0x14, 0x15, 0x18, 0x0e…),
et côté 0xFD une annonce répétée, une table pleine, un TYPE 1 sans TYPE 0 ou un TYPE inconnu. Raison : un `Halted` au
milieu des SAVE laisserait le xART à moitié scellé. Une nouvelle annonce 0xFD est ajoutée à la table ; celle de
`sbio` donne la ligne « sbio annoncé (EP 0x08) ». Journal limité à 256 lignes « ignoré (…) », total dans la table
finale. **Restent `Halted`** : TYPE 0x13 hors liste, TYPE CNTL inconnu sur l'EP 0x00, message sur un EP jamais
annoncé. Avant l'ouverture, les règles strictes ci-dessus s'appliquent toujours.

## Interface `/dev/sep_native` (version minimale typée, sans ioctl)

N'existe qu'après l'ouverture réussie de 0x13 ; root 0600 ; un seul ouvreur (EBUSY). Un enregistrement = en-tête de
16 o (petit-boutiste) + `len` octets : `+0 u32 seq | +4 ep | +5 tag | +6 type | +7 param | +8 u32 data | +12 u32 len`
(`sep-proto::xart_gate::RecHdr`, partagé par le noyau et le démon).
- `read` (bloquant, tampon ≥ 16 + 0x8000 o, sinon EINVAL) : une requête du SEP pas encore lue ; charge = copie de B
  (FETCH locker : 16 o d'UUID ; SAVE : `PARAM | DATA[0] << 8` o ; sinon rien). `EIO` dès que `Halted`. À chaque
  ouverture, les requêtes lues mais non acquittées sont remises (démon relancé).
- `write` : **un** enregistrement de réponse par appel ; `seq` = celui de la requête ; charge = octets à mettre en A.
  Jamais de mot brut : EP et TAG doivent être ceux de la requête, et `check_reply` n'admet, par TYPE de requête,
  que le mot de la politique (`docs/xart_native_policy.md`) : 0x0e → `0x00/0/0x100`, A vide ; 0x13 → `0x00/0/0`,
  A = 16 o ; 0x00 → A ≥ 0x11 o commençant par 0x11 zéros, PARAM/DATA = longueur de A + sélecteur ; 0x05 → PARAM/DATA =
  longueur de A (0 = ABSENT) + sélecteur ; 0x07 → `0x00/0/0` ; 0x1d → `0x16/0/DATA&0xFFFFFF00` ; SAVE →
  `0x00/0/DATA&0xFFFFFF00`, seulement si `allow_xart_save_ack=1`. A est mis à zéro puis rempli pour 0x0e, 0x13 et
  les FETCH ; il n'est pas touché pour 0x07, 0x1d et les SAVE (comme le harnais). Refus → `Halted`, rien d'envoyé.
- Écart au design §3.5 : pas d'ioctl (`GET_STATE`, `XART_LOAD_STORE`…) ; l'état se lit dans `dmesg`. Le noyau ne
  précharge pas le store : chaque FETCH fait l'aller-retour vers le démon (le harnais tolérait la latence USB).

## Démon `driver/rust/sepd`

`sepd [--store DIR] [--os-uuid-file FICHIER] [--dev /dev/sep_native]` (défauts `/var/lib/sepd`,
`/etc/sepd/os_uuid`). Journal de chaque échange sur stderr et dans `DIR/sepd.log`. Toute erreur → arrêt **sans
répondre** (le SEP attend ; power-cycle).
- **UUID d'OS (op 0x13)** : lu dans `--os-uuid-file` (32 chiffres hexa, tirets admis). **Fichier absent ou invalide →
  le démon refuse de démarrer.** Valeur du run éprouvé sous m1n1 : `4c494e55580000000000000000000000` (« LINUX »,
  `LINUX_OS_UUID` de `pending/sep_native_persist.sh`). Le bon UUID reste un point ouvert (politique, ouvert n°1).
- Store : `master_1.bin` (USER, sélecteur pair) / `master_2.bin` (SEP, sélecteur impair) = charge servie après le
  préfixe de 0x11 zéros ; `locker_<uuid32hex>.bin` = octets servis tels quels pour un FETCH locker.
- SAVE maître → `master_<t>.bin` (B brut). SAVE locker → `locker_save_<uuid>.bin` (B brut, UUID = B[0..16]) ; **pas
  re-servi** : la forme « B du SAVE → A du FETCH » d'un locker n'est pas établie (`docs/gigalocker.md`), et le harnais
  éprouvé faisait pareil (dump brut, lockers toujours ABSENT).
- Tests (`cargo test --offline`) : les 30 paires 0x13 de `snew-reel` (macOS) sont reproduites mot et tampon A quand
  le store contient ce que macOS a servi (8 TYPE couverts) ; branches natives (store vide : ABSENT maître 0x11 et
  locker 0, SAVE persisté puis servi avec la longueur recalculée, SAVE locker non re-servi, TYPE inconnu, budget).

Réception : callback mailbox (IRQ dure) → anneau fixe de 64 mots → un seul work qui vide dans l'ordre.
**Écart au design** : anneau atomique à un producteur / un consommateur au lieu d'un `SpinLock` : le Rust de
cet arbre n'a pas de spinlock qui coupe les IRQ, et un `SpinLock` simple partagé entre IRQ et work peut bloquer
un CPU. Producteur unique garanti par `mbox->rx_lock` (`mailbox.c`), consommateur unique = un seul `work_struct`.

Après le 1er mot envoyé : le module prend une référence sur lui-même (rmmod → EBUSY jusqu'au reboot), un unbind
fuit volontairement mailbox, shmem et mapping firmware, et tout nouveau probe est refusé (EBUSY).

## Vérifié / hypothèse

| Élément | Statut |
|---|---|
| Séquence GET_STATUS / TZ0 / GET_STATUS / IMG4 + SET_SHMEM / 0x6A | éprouvée sous m1n1, puis **exécutée par ce pilote le 2026-11-22** (J2, `docs/journal.md`) |
| Ouverture CNTL de 0x13 (SECMODE, A/B 0x8000) et politique xART | éprouvées sous m1n1 (`native_persist`, n=4) ; **jamais exécutées par ce pilote** |
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

## Test de l'étape 7 (xART), plus tard

**Nouvelle classe d'écriture pour ce pilote = go d'Albert.** C'est l'étape où l'enrôlement Touch ID de macOS est
invalidé (re-scellement du master ; macOS déclaré sacrifiable le 2026-11-22). Filet avant : `alarm_p5.img`, backup,
DFU. Power-cycle avant le run (Albert).
1. Préparer (root) : `mkdir -p /etc/sepd /var/lib/sepd`, écrire l'UUID dans `/etc/sepd/os_uuid`, store **neuf et
   séparé** (vide : tout FETCH → ABSENT, comme le 1er run éprouvé). Compiler `sepd` (`cargo build --release --offline`).
2. `insmod sep_native.ko allow_boot=1 allow_xart=1 allow_xart_save_ack=1`, puis lancer `sepd` dès que le log dit
   « /dev/sep_native prêt » (le SEP attend la réponse au 0x0e ; aucun délai mesuré côté SEP, hypothèse).
3. Attendu (run m1n1 du 2026-11-22 `native_persist`) : 0x0e, 0x13, 2 FETCH maître ABSENT, 5 annonces 0x1d (sbio, skdl,
   sse, sks, scrd), une douzaine de SAVE alternant maître/locker, un 0x07, puis le calme ; nouvelles annonces 0xFD
   dont **`sbio` (EP 0x08)** et `sks ` (0x12). Store après : `master_2.bin` + des `locker_save_*`.
4. Échec : `HALTED : <raison>` dans dmesg, `sepd` sort en `read: EIO`. Power-cycle.

Une variante sans écriture existe : `allow_xart=1 allow_xart_save_ack=0` s'arrête (Halted) au 1er SAVE sans
l'acquitter (même chose que `pending/sep_native_0x13.sh`, compteur non avancé) ; c'est aussi un 1er run de ce
pilote (go).

Points à observer (ne rien supposer) : l'UUID d'OS (ouvert n°1), le master Linux vs macOS (ouvert n°3), et les
lignes « ignoré (…) » : messages spontanés des EP nouvellement annoncés, à lire pour la suite (J3).

## Test du boot, plus tard

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
