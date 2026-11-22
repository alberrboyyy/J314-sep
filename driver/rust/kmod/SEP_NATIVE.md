# sep_native — pilote Rust de boot du SEP (option (b) du design)

Fichiers : `sep_native.rs` (ce dossier), `driver/linux/sep_native_ovl.c` + `driver/linux/sep-native-overlay.dts`.
Conception : `docs/driver_rust_design.md` (§2 option (b), §3.1-3.6). Boot (`allow_boot=1`) **éprouvé sur matériel
le 2026-11-22** (`docs/journal.md`). Service xART (`allow_xart`) : **éprouvé sur matériel le 2026-11-22** (J4,
`logs/20261122-183847_j4-xart-native/`). Ouverture de sbio + poignée 0x73 (`allow_sbio`, J3, ouverture tardive) : **éprouvée sur matériel le 2026-11-22 après un
scellement frais** (`logs/20261122-192013_j3c-sbio-fresh/`, VIVANT). Relais J5 (`allow_sbio_relay`, `/dev/sep_sbio`, `sbiod`) :
**exécuté le 2026-11-22** (v2, patch chargé, `logs/20261122-204249_j5b-patch-loaded/`). Ouverture précoce (`sbio_open=1`)
et J5c (`allow_sbio_params`, point 11) : **compilés et testés hors ligne, jamais chargés.**

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
7. Porte d'envoi (`send_running`) : l'EP 0x00 (TYPE 0x14, 0x02-0x05, 0x12 ; un CNTL de PARAM 0x08 seulement en
   phase d'ouverture de sbio et seulement TYPE 0x02-0x05), l'EP de `xarm` une fois ouvert, et, avec `allow_sbio=1`,
   **un seul** mot vers 0x08 : `TAG 0xfc TYPE 0x73 PARAM 0 DATA 0`, admis une fois (phase `Open` → `HelloSent`).
   0x12 (sks) toujours refusé. Sans `allow_sbio`, aucun chemin vers 0x08.
8. `allow_sbio=1` (exige `allow_xart=1`), J3 selon `docs/j3_sbio_open.md` : au probe, deux tampons DMA cohérents de
   0x4000 o (A8, B8), distincts de ceux de 0x13. Après la création de `/dev/sep_native`, **le probe (donc `insmod`)
   attend** (sepd sert le xART en parallèle) :
   - que `sbio` soit annoncé **en 0x08** (annoncé ailleurs → rien envoyé, abandon) ;
   - que le xART soit **calme** : aucune requête 0x13 en attente, aucun ack CNTL attendu, aucun mot 0x13 reçu ou
     envoyé depuis **2 s**. Choix : sbio est annoncé au milieu de la rafale de SAVE (J4 : annonce à 18:38:50, SAVE
     jusqu'à 18:38:52) ; ouvrir à ce moment mélangerait nos CNTL aux échanges xART. Le harnais m1n1 attendait 25 s
     de silence (`IDLE`) ; 2 s suffit à séparer les deux phases (J4 : SAVE espacés de moins de 0,5 s), hypothèse ;
   - délai maximal 120 s depuis l'ouverture de 0x13 ; au-delà, ou sur signal, **rien n'est envoyé à 0x08 et pas de
     `Halted`** (le service xART continue).
   Puis 4 CNTL PARAM 0x08, **sans 2e SECMODE** : 0x04 (taille A8 = 0x4000), 0x02 (IOVA A8 >> 12), 0x05 (taille B8),
   0x03 (IOVA B8 >> 12), chacun attendant son ack TYPE 0x01 de même TAG (5 s ; sinon `Halted`). Puis A8 = gt_packet
   0x73 capturé sous macOS (`sbio_hello_0x73.bin`, copie de `traces/20261108-032454_c12-boot-ho/sep.log.ool/000300_08_A.bin`,
   1024 o, sha256 `0982f722…92f3`), **embarqué à la compilation** (`include_bytes!`, le noyau ne lit aucun fichier) ;
   `+0x00 == 1` et `+0x14 == 0x73` contrôlés à la compilation (assertion) et relus dans A8 avant l'envoi (sinon
   `Halted`). Envoi de `> EP 0x08 TAG 0xfc TYPE 0x73 PARAM 0 DATA 0`, écoute 6 s, dump de B8 avant le 0x73, après
   chaque nouveau mot 0x08 (4 au plus) et en fin d'écoute : nombre d'octets non nuls sur 0x4000, en-tête gt_packet
   (version, total, offset, opcode, fragment) et 0x80 premiers octets. Ligne finale :
   `VERDICT sbio : VIVANT` si `B8[0x00] == 1 && B8[0x14] == 0x73`, ou si un mot 0x08 `TAG 0xfc TYPE 0x73` ou
   `TAG 0x04` arrive après le 0x73 ; sinon `VERDICT sbio : MUET`. Ensuite **rien d'autre** vers 0x08 (ni 0x17, ni
   0x15, ni 0x16 : J5). Tout mot reçu sur 0x08 (notifications TAG 0x01 lockState, 0x02-0x04, réponses GT) est
   journalisé `sbio < …` (128 lignes au plus, compte gardé), **sans réponse ni `Halted`**. Le dump de B8 n'est pas
   exposé à l'espace utilisateur (dmesg seulement).

9. **Ouverture précoce (`sbio_open=1`, défaut), à la demande de l'orchestrateur PC (comparaison avec c12 chaîné)** :
   en boot chaîné (master servi depuis le store), l'ouverture tardive n'est jamais acquittée (n=2, orchestrateur PC).
   macOS (c12 L119-L136) ouvre ~35 ms après son ack `> 0x13 TYPE 0x16 DATA 0x00736200` de l'annonce
   `< 0x13 TYPE 0x1d PARAM 0x6f DATA 0x00736269` ('sbio'), pendant que les FETCH locker continuent. Ici : dès que sepd a
   fait envoyer cet ack (`submit_reply` reconnaît TYPE 0x1d, PARAM 0x6f, DATA & 0xFFFFFF = 0x736269, et réveille le fil
   du probe) ET que `sbio` est dans la table en 0x08, les 4 CNTL PARAM 0x08 partent sans attendre le calme. Pendant
   l'attente des acks (condvar, verrou rendu), le work continue de mettre en file les requêtes 0x13 et sepd d'y répondre ;
   les acks CNTL sont appariés par TAG (`cntl_wait`), un ack d'un autre TAG → Halted. Ack absent en 5 s → Halted
   (comme l'ouverture tardive). Le 0x73 part ensuite seulement quand le xART est calme (règle des 2 s du point 8),
   délai total 120 s depuis l'ouverture de 0x13 (au-delà : pas de 0x73, pas de Halted). macOS met TAG 8 aux 4 CNTL,
   on garde le TAG tournant 1..8 (celui de l'ouverture tardive éprouvée). Différence non testée sur matériel.
10. **Relais J5 (`allow_sbio_relay=1`)** : si le verdict du 0x73 est VIVANT, phase `Relay` et création de
   `/dev/sep_sbio` (root 0600, un seul ouvreur). Liste blanche **dans l'ordre, une fois chacune** (`sep-proto
   sbio_gate::RELAY_SEQUENCE`), avec longueur de charge EXACTE et bornes de la réponse :
   `0x17` (16 o → 0), `0x15` (4 o → 40), `0x16` (40 o → 0), `0x42` (0 → 64), `0x18` (64 o → 0), `0x5f` (2 o → 2..0x10000).
   Rien après 0x5f. Le noyau construit le gt_packet (en-tête 0x1c `1, total, 0, 0, 0, op, len` + charge, reste de A8 à
   zéro : octet pour octet les A8 de c12, test `sbiod/tests/replay.rs`), relit `+0x00` et `+0x14`, envoie
   `> EP 0x08 TAG 0xfc TYPE op PARAM 0 DATA 0`. Réponse : `< TAG 0xfc TYPE op` (1er fragment) puis, tant que
   `offset + long < total`, `> TAG 0xfe TYPE op DATA nfd << 16` (A8 inchangé) et `< TAG 0xfd` ; chaque mot passe la règle
   du compteur GT (`gt::CounterChecker`) et chaque en-tête de B8 `sbio_gate::check_fragment` (version 1, opcode, total
   stable et borné, fragments dans l'ordre, ≤ 0x3fe4 o, ≤ 8 fragments) ; le fragment est copié de B8 dans un tampon
   préalloué de 0x10000 o. Pas de fragmentation AP→SEP (toutes les charges ≤ 64 o, plus long → refus). 6 s par réponse.
   **Halted** : commande hors liste / hors ordre / mauvaise longueur, mot GT hors transaction ou de mauvais TAG/TYPE,
   compteur faux, en-tête refusé, délai, signal pendant une transaction. Notifications TAG 0x01-0x04 : file de 16
   événements pour le démon (pleine → perdue et comptée, pas de Halted). Autre TAG sur 0x08 pendant le relais → Halted.
   Charges fixes contrôlées en plus de la longueur (J5c) : 0x15 = `01 00 00 00`, 0x5f = `02 00`.
11. **J5c, après le patch (`allow_sbio_params`, défaut 0 = rien après 0x5f)** — `docs/j5_params_protocol.md`,
   séquence de la 1re passe macOS (c12 seq 317-344, tailles identiques sur 9 boots) :
   - niveau 1 : `0x5d` (`00 00 00 00` → 55 o), `0x5c` (idem), `0x6a` (vide → vide), `0x31` (vide → 64 o), `0x32` (64 o →
     18 o), `0x01` (vide → vide), `0x1f` (vide → 2 o), `0x31`, `0x32` (2e paire) ;
   - niveau 2 : en plus `0x5b` (setCalibrationData) puis `0x63` (vide → 28 o). Rien après 0x63.
   **0x5b est la seule commande fragmentée AP→SEP** (`Step::frag_in`) : charge = exactement 0xfc99 o, en-tête
   `03 00 00 00 30 82 fc 91`, CRC-32 `0x6f98a221` (le blob capturé, sinon Halted avant tout envoi) ; 4 fragments
   (0x3fe4 ×3 + 0x3ced), chacun écrit dans A8 (en-tête `1, 0xfc99, offset, 0, 0, 0x5b, len` + morceau, reste à zéro,
   +0x00/+0x08/+0x14 relus) : `> fc DATA 0` (fragment 0), puis pour k = 1..3 : `< fe DATA (k-1) << 16` → `> fd DATA k << 16`
   (fragment k) ; enfin `< fc DATA 0` avec un en-tête B8 de réponse vide (total 0). Mots = c12 L388-402 (23/23
   captures). Un `< fc` avant le dernier fragment, un `< fe` après, un compteur faux → Halted. B8 au moment des `< fe`
   n'est pas contrôlé (c12 : tout à zéro, origine inconnue), seulement journalisé. La porte d'envoi n'admet `> fd` que
   pour l'étape `frag_in`, après un `< fe`, avec DATA = nombre de fragments déjà envoyés << 16.
   `allow_sbio_params` ≠ 0 exige `allow_sbio_relay=1` ; valeur > 2 → EINVAL.

## Paramètres (u32, défaut 0 sauf `sbio_open`, absents de sysfs : figés au chargement)

| Paramètre | Effet |
|---|---|
| `allow_boot` | 1 = séquence de boot ci-dessus. 0 = probe seul. |
| `allow_xart` | 1 = ouverture de 0x13 et `/dev/sep_native` (réponses 0x0e, 0x13, FETCH servi/ABSENT, 0x07, 0x1d). Exige `allow_boot=1` (sinon EINVAL). |
| `allow_xart_save_ack` | 1 = le démon peut acquitter les SAVE (⚠️ le compteur scellé avance). 0 = un SAVE → `Halted`. Exige `allow_xart=1`. |
| `allow_sbio` | 1 = J3 (point 8) : ouverture de 0x08 et UNE poignée 0x73 quand le xART est calme. Exige `allow_xart=1` (sinon EINVAL). En pratique il faut aussi `allow_xart_save_ack=1` : sbio n'est annoncé qu'après le scellement. |
| `sbio_open` | **défaut 1** = ouverture PRÉCOCE de sbio (point 9) ; 0 = TARDIVE (point 8, éprouvée après scellement frais). Autre valeur → EINVAL. Sans effet si `allow_sbio=0`. |
| `allow_sbio_relay` | 1 = relais J5 (point 10) : `/dev/sep_sbio` après un 0x73 VIVANT. Exige `allow_sbio=1` (sinon EINVAL). |
| `allow_sbio_params` | J5c (point 11) : 0 = rien après 0x5f ; 1 = 0x5d … 2e 0x32 ; 2 = en plus 0x5b (⚠️ écriture SEP de classe neuve : calibration) et 0x63. Exige `allow_sbio_relay=1`. |
| `allow_sks` | **non implémenté** : toute valeur ≠ 0 fait échouer le probe (EINVAL). |

## États

`Idle` (probe fait, rien envoyé) → `Booting` (seuls des mots EP 0xFF sont admis, dans l'ordre attendu) →
`Running` (passage à la réception de 0x6A ; écoute seule) ; à tout moment → `Halted`, définitif jusqu'au
power-cycle : plus aucun envoi (le seul chemin d'envoi, `send()`, n'accepte que `Booting`).
Causes de `Halted` : message reçu en `Idle`, message hors EP 0xFF pendant le boot, réponse ROM d'un autre TYPE
ou d'une autre DATA (0x66), timeout, signal, erreur mailbox, IOVA inutilisable, anneau RX plein, message
inconnu après le boot, EP annoncé deux fois ; et avec `allow_xart` : TYPE 0x13 hors liste (0x0e, 0x13, 0x00, 0x05,
0x07, 0x1d, 0x01, 0x06), SAVE sans `allow_xart_save_ack`, requête autre que 0x0e avant l'ouverture, longueur B hors
tampon (FETCH locker : B ≠ 16 o), deux requêtes à tampon B en attente, plus de 16 requêtes en attente, ack CNTL
absent ou de TAG inattendu, réponse du démon refusée par `check_reply` (ou à un `seq` inconnu), 48e SAVE acquitté ;
avec `allow_sbio` : ack CNTL absent à l'ouverture de 0x08, A8 relu qui n'est pas un 0x73.

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

## Interface `/dev/sep_sbio` (allow_sbio_relay=1)

Enregistrements petit-boutistes de `sep-proto::sbio_gate` (noyau et démon partagent le code), magic `SBR1` :
- `write` : `+0 u32 magic | +4 op | +5..8 0 | +8 u32 len` + charge (≤ 64 o, ou les 0xfc99 o de 0x5b). **Bloque** jusqu'à la réponse complète
  (réassemblée) ; EBUSY si la réponse précédente n'a pas été lue (lockstep strict) ; refus → Halted.
- `read` (tampon ≥ 16 + 0x10000 o) : bloque jusqu'à un événement : d'abord les notifications (`kind 2`, mot seul), puis
  la réponse (`kind 1`, mot final + charge réassemblée). `+0 magic | +4 kind | +5 tag | +6 type | +7 param |
  +8 u32 data | +12 u32 len`. EIO une fois Halted.

## Démon `driver/rust/sbiod` (J5)

`sbiod preflight` (côté capteur, sysfs seulement) / `sbiod run [--dev /dev/sep_sbio] [--log F]` / `sbiod power-off`.
`run` : alimentation gpio0 196 (bas 40 ms, haut, 60 ms, comme `mesa_power_on`), identité (0x78, 0x10, 0x70, 0x10, 0x13,
lecture 0x1b ; doit être l'identité connue, série [9..25] = celle du gabarit c12), 0x17, 0x15 → trame `80 72 00 2f 00 00 00`
+ 40 o → réponse (attendue 0x33 o) → 40 o @ 9 → 0x16, 0x42 → `80 73 00 47 00 00 00` + 64 o → 64 o @ 9 → 0x18, 0x5f →
contrôle préfixe u16 = longueur − 2 → état, prélude `80 60 00 07 00 00 00` seul, **bloc en un seul SPI_IOC_MESSAGE**, puis
1,5 s de scrutation (broche 195 + état toutes les 50 ms ; octet 1 lu seulement si l'en-tête est `80 20 00 10`).
Ligne finale : `VERDICT : patch chargé (0x29 …)` / `patch refusé` (broche montée, jamais 0x29) / `IRQ absente` /
`arrêt (fail-closed) : …`. Capteur éteint dans tous les chemins (garde `Drop` + `trap` du script). Chaque échange est
journalisé (longueur + 16 premiers octets), rien n'est interprété. Tous les délais = ceux de `mesa_transport.h` et des
scripts sbio4..11 (10 ms entre échanges, 50 sondages d'état pour la longueur en attente).

Capteur depuis l'espace utilisateur (le noyau ne parle pas au capteur) — commandes du script :
```
cp mesa-spi2.dtbo /lib/firmware/ && insmod mesa_ovl.ko          # nœud spi2 + enfant biosensor@0 (aucun pilote lié)
D=/sys/bus/spi/devices/spiN.0     # celui dont of_node finit par spi@39b108000/biosensor@0
echo spidev > $D/driver_override  # pas de variante d'overlay : driver_override sur l'enfant existant
modprobe spidev bufsiz=65536      # défaut 4096 < 22158 (bloc du patch) ; bufsiz se fixe au chargement
[ -e $D/driver ] || echo spiN.0 > /sys/bus/spi/drivers/spidev/bind
echo on > $D/../power/control     # contrôleur spi2 gardé actif (comme pm_runtime_resume_and_get de mesa_acquire)
```
GPIO : `/dev/gpiochipN` dont le device sysfs est directement sous `39b028000.pinctrl` (pas les `gpiolib_shared.proxy.*`),
label contrôlé par `GPIO_GET_CHIPINFO_IOCTL` ; ligne 196 en sortie (valeur initiale 0), ligne 195 en entrée (si refusée :
pauses fixes seulement). SPI : mode 1 (CPHA), 8 bits, 8 MHz, relus après réglage ; un échange = un message d'un transfert
(CS par message, comme `mesa_xfer`). Le push passe par le PIO de `spi-apple` (FIFO 16, IRQ toutes les 8 octets à 8 MHz :
pas de scrutation) : c'est la « voie 0 » de `docs/dma_spi2_design.md` §3.4, jamais essayée.

J5c (`--upto params|calib`, seulement si le patch est chargé ; `docs/j5_params_protocol.md` §6) : avant chaque trame
0x55 la broche 195 doit être basse (≤ 20 ms), trame seule, attente de la broche haute (≤ 200 ms), UNE lecture d'état qui
doit valoir celle de macOS (`00 00 21 00 0c 52 33 00 16` après 0x5d/0x5c, `07 00 21 00 8c 4b 00 00 00` après 0x31) ;
réponse 0x75 : en-tête `80 d4 00 4b 00000000 75` et CRC16 ; 0x32 = 18 o = n° de série module du blob ; 0x1f = `05 05` ;
0x63 comparé à macOS. Fichier `--calib` contrôlé avant toute ouverture (64665 o, sha256, n° de série capteur à
l'offset 91). La longueur en attente n'est plus lue qu'avec l'octet d'état 0x07 (au repos les mêmes octets valent `52 33`).
`sbiod calib-prepare --from DIR --out F` refait le blob depuis les 4 A8 de c12 (en-têtes contrôlés).

Tests (`cargo test --offline`, `sbiod/tests/replay.rs` sur c12) : gt_packets construits = A8 de macOS (7 commandes,
0x73 compris) ; réponses B8 de c12 acceptées par la porte, patch 0x5f réassemblé en 0x568e o (2 fragments, préfixe
`8c 56`), fragment hors ordre refusé ; run complet contre un faux SEP (réponses c12 + porte d'ordre/longueur du noyau) et
un faux capteur : trames 0x72/0x73 = en-tête C19 + blob du SEP tel quel, réponses capteur @ 9 rendues au SEP telles
quelles, prélude seul puis bloc entier en un transfert ; verdicts « chargé » et « refusé ».

## Démon `driver/rust/sepd`

`sepd [--store DIR] [--os-uuid-file FICHIER] [--dev /dev/sep_native]` (défauts `/var/lib/sepd`,
`/etc/sepd/os_uuid`). Journal de chaque échange sur stderr et dans `DIR/sepd.log`. Toute erreur → arrêt **sans
répondre** (le SEP attend ; power-cycle).
- **UUID d'OS (op 0x13)** : lu dans `--os-uuid-file` (32 chiffres hexa, tirets admis). **Fichier absent ou invalide →
  le démon refuse de démarrer.** Valeur du run éprouvé sous m1n1 : `4c494e55580000000000000000000000` (« LINUX »,
  `LINUX_OS_UUID` de `pending/sep_native_persist.sh`). Le bon UUID reste un point ouvert (politique, ouvert n°1).
- Store : `master_1.bin` (USER, sélecteur pair) / `master_2.bin` (SEP, sélecteur impair) = charge servie après le
  préfixe de 0x11 zéros ; `locker_<uuid32hex>.bin` = octets servis tels quels pour un FETCH locker.
- SAVE maître → `master_<t>.bin` (B brut). SAVE locker → `locker_save_<uuid>.bin` (B brut, UUID = B[0..16]) ; **re-servi
  tel quel** au FETCH 0x05 de cet UUID (commit 7707e4d ; accepté par le SEP en J3b, 2026-11-22 19:04, n=1).
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
| Ouverture CNTL de 0x13 (SECMODE, A/B 0x8000) et politique xART | éprouvées sous m1n1 (`native_persist`, n=4), puis **exécutées par ce pilote le 2026-11-22** (J4, J3×4) |
| Encodage du mot (EP/TAG/TYPE/PARAM/DATA) | `hypothèse (cohérent)`, éprouvé de fait par tous les runs natifs (sep-proto `word`) |
| DATA de 0x66 = 1 puis 2 | `source: kext` + trace C11 (macOS) ; m1n1 ne la vérifie pas. Contrôle strict ici (fail-closed) |
| Magic `CINP` du tampon panique | m1n1 ; `sep.rs` écrit `CNIP`. **À confirmer** (const `SHMEM_MAGIC_PANIC`) |
| TYPE 0x18 de SET_SHMEM | m1n1 ; macOS envoie 0x1c (design Q11) |
| Timeout 5 s, attente de découverte 3 s | hypothèse (aucune mesure de latence de la ROM) |
| IOVA choisies par Linux (et non 0xDEAD0000/0xBEEF0000) | inconnu (design Q3) |
| Mapping fw BIDIRECTIONAL (comme m1n1 : PTE sans protection), et non TO_DEVICE comme `sep.rs` | choix déduit |
| Barrière `dmb oshst` (dma_wmb) avant IMG4/SET_SHMEM | déduit (comme `rtkit.c`), design Q9 |
| Liste des messages connus après boot | traces C1 (19/19) et SEP-BOOT 2026-11-09 ; hypothèse |
| Relais 0x17/0x15/0x16/0x42/0x18/0x5f (forme gt_packet, fe/fd, offset 9, trames 0x72/0x73, prélude 0x60) | éprouvé sous m1n1 (sbio3..11) jusqu'à la réception du patch ; **jamais exécuté par ce pilote** |
| Push du patch par le PIO noyau → 0x29 | **obtenu une fois** (J5 v2, 2026-11-22 20:43, n=1) |
| J5c : 0x5d … 0x63, trames 0x55 + CRC16, 0x5b fragmenté AP→SEP | vu sous macOS (c12, C17-C20) ; **jamais exécuté** (sbio8/9 sous m1n1 : capteur sans patch, sans valeur) |
| Ouverture précoce de sbio (après l'ack 0x1d 'sbio') | vue sous macOS (c12) ; **jamais exécutée** ; nécessaire en boot chaîné selon l'orchestrateur PC (n=2) |
| En-tête de trame capteur au-delà de 0xff o (u16 BE en 2 ou u32 LE en 3) | non tranché, non utilisé (trames relais < 0x100 o) |

Différences avec m1n1, côté AP seulement : TAG 0 comme m1n1 (macOS met 1) ; le firmware est mappé juste avant
IMG4 et non avant le 1er GET_STATUS (le SEP ne voit l'IOVA qu'avec IMG4).

## Tests J5 et J3 chaîné, plus tard (1er run de chacun = go d'Albert)

- `UPTO=params|calib pending/j5c_params_run.sh [STORE]` (J5c, jamais lancé) : prépare `$J5/calib_0x5b.bin` (`sbiod
  calib-prepare` depuis c12, sha256 revérifiée), puis `j5_sensor_run.sh` avec `allow_sbio_params=1|2` et
  `sbiod run --upto params|calib [--calib …]`. Conseil : `params` d'abord.

- `pending/j5_sensor_run.sh [STORE]` : depuis un reboot ; capteur préparé AVANT le SEP (overlay, spidev bufsiz, preflight :
  un échec n'envoie rien au SEP) ; puis sep_native `allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1
  allow_sbio_relay=1 sbio_open=$SBIO_OPEN` (défaut 0 ici : seule ouverture éprouvée en scellement frais), sepd en fond,
  sbiod dès `/dev/sep_sbio`. Fichiers dans `$J5` (défaut `~/kbuild/j5`, à préparer : voir l'en-tête du script).
- `pending/j3_chained_run.sh STORE` (store non vide obligatoire) : `sbio_open=1 allow_sbio_relay=0` ; ouverture précoce +
  0x73 sur boot chaîné. Décide la persistance de l'enrôlement.
- `pending/j3_sbio_run.sh` passe `sbio_open=0` au module J5 (garde l'ouverture tardive éprouvée).

## Test de J3 (sbio), plus tard

**1er run de ce chemin dans sep_native = go d'Albert.** Filet : `alarm_p5.img`, backup, DFU ; reboot avant le run.
1. Compiler (`driver/rust/build.sh`), copier `sep_native.ko` dans `~/kbuild/j2/` (le script vérifie que le module a
   `allow_sbio`).
2. Root : `pending/j3_sbio_run.sh [STORE]` (comme `j4_xart_run.sh`, plus `allow_sbio=1`). Le script affiche le store
   utilisé et s'il est vide.
3. Lire `journalctl -k -b | grep -E 'sbio|VERDICT|HALTED'`. Attendu : même déroulé que J4, puis « xART calme »,
   4 acks CNTL, « 0x08 ouvert », `> sbio 0x73`, les mots `sbio <` éventuels, les dumps de B8 et le `VERDICT`.

**Question ouverte (à trancher avec l'orchestrateur PC, avant le run)** : le store `/var/lib/sepd` du run J4 n'est plus
vide (`master_2.bin` + 4 `locker_save_*`). Le servir (voie « persist » : le SEP retrouve son master) ou repartir d'un
store neuf (scellement frais, compteur encore avancé) ? Le script ne tranche pas : défaut = dossier neuf
`/var/lib/sepd-run-<horodatage>` (même situation que le J4 réussi) ; passer `/var/lib/sepd` en argument pour l'autre
voie. Note : `sepd` ne re-sert pas les `locker_save_*` (forme non établie), seul `master_<t>.bin` est servi.

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
