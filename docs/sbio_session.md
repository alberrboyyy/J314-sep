# sbio — la session capteur APRÈS le key exchange (0x16) : trames SPI exactes (phase 2)

2026-11-22 — reverseur. But : cartographier, **dans l'ordre**, les trames SPI exactes de **chaque** commande
capteur qui suit le key exchange (0x15/0x16), pour coder la suite du relais natif (**sbio5**). Fait suite à
`docs/sbio_keyexchange.md` §9 (recette de la trame 0x72). **Protocole / transport uniquement. Aucune clé,
aucun secret extrait.**

Source unique : **trace macOS C19** = `traces/20261110-002829_c19-spi-dma-boot` (bus capteur en DMA SIO,
147 buffers, 0 erreur de lecture), relue par `analysis/sio_dialog.py <dir> --sep --full`. Recoupe
`docs/sbio_sequence.md` §1 (ordre des opcodes EP 0x08, trace C12) et `docs/sensor_hw.md` (trames 0x10/0x13/0x55/0x60/0x72/0x73).

Marquage par fait : **VU (C19)** = octets lus tels quels dans la capture C19 ; **hypothèse** = interprété. Aucune
étape n'est `vérifié` au sens matériel (rien n'a été envoyé ; c'est une capture macOS relue hors-ligne).

---

## 0. Réponses courtes aux trois questions décisives

1. **Les gros blobs passent-ils par le FIFO scruté ou par DMA ?** Le **patch** (`0x5f`) part en **UN SEUL
   transfert SPI contigu** de **22158 o** (1re passe) / **28878 o** (2e passe) — pas de fractionnement en petites
   trames. Sous macOS c'est du **DMA SIO**. Le reproduire en FIFO scruté (`mesa_spi_proxy`) demande un **unique
   burst CS-maintenu** de ~22 Ko : **c'est le risque de faisabilité n°1 de sbio5 → DMA SIO très probablement requis**
   (détail §4). (VU C19.)
2. **Le gros blob de calibration (~64 Ko, `0x5b`) est-il un souci SPI ?** **NON.** `setCalibrationData` (`0x5b`)
   ne génère **AUCUNE trame SPI** en C19 : il est entièrement consommé **côté SEP** (fragments OOL mailbox
   `0xfe/0xfd`), jamais poussé au capteur. Le capteur ne reçoit que des **paramètres dérivés** via les petites
   trames `0x55` (≤ 86 o). **Les 64 Ko ne touchent jamais le bus SPI.** (VU C19 — décisif, voir §4.)
3. **D'où viennent les blobs, et sont-ils rejouables ?** Le **patch** vient du **SEP** (relais `0x5f`), il est
   **chiffré et frais à chaque boot** (enveloppe `3a` + compteur ; 1re passe ≠ 2e passe : 22158 o `8c56…` vs
   28878 o `cc70…`) → **PAS rejouable** en octets, à **relayer vivant** à chaque allumage. La **calibration**
   vient de l'**espace utilisateur** (blob signé), passe au **SEP** (mailbox), **jamais sur SPI** → pour sbio5
   c'est un rejeu **mailbox** (D3, cf. `sbio_sequence.md`), pas SPI. (VU C19 + recoupé sbio_sequence.)

---

## 1. La règle de longueur (confirmée, VU C19)

Toutes les petites trames respectent la règle déjà actée au §9 de `sbio_keyexchange.md` :

> En-tête d'émission `80 <cmd> <LL 16 bits gros-boutiste> 00 00 00` + charge, où **`LL` = TAILLE TOTALE de la
> trame** (en-tête 7 o **inclus**), pas la taille de la charge.

Exemples VU C19 : `80 72 00 2f` (0x2f=47=7+40), `80 73 00 47` (0x47=71=7+64), `80 55 00 40` (0x40=64=7+57),
`80 55 00 49` (0x49=73=7+66), `80 10 00 07` (poll), `80 13 00 0b` (demande de lecture). **Le gros patch fait
exception** : il n'a **pas** d'en-tête `80 …` (voir §3-LoadPatch).

Lecture d'une réponse (identique partout) : **poll `80 10 00 07 …`** → l'état `80 20 00 10 …` renvoie la
**longueur en attente** (octet 12, puis 13 pour le poids fort) → **`80 13 00 0b 000000 <len 32 bits petit-boutiste>`**
→ (octet muet `00`) → **réception** de `len` octets. La réponse a la forme `80 d4 <len16 BE> <status32> <type> <charge> <crc16>` :
**9 o d'en-tête** (dont `status32` : `00000000` = OK), charge à **l'offset 9**, puis CRC16. (VU C19, = recette §9.2.)

---

## 2. Table ordonnée de la session capteur post-KX (VU C19, 1re passe, t≈28.7 s)

Chaque bloc = une commande sbio EP 0x08 (`SEP >`) et la (les) trame(s) SPI qu'elle pilote, **dans l'ordre fil**.
`len` d'en-tête = **taille totale**. « réponse » = trame RX relue via poll→0x13.

| # | op sbio (SEP) | opération (kext) | trame SPI TX | taille totale | charge | réponse SPI (type / taille) | statut |
|---|---|---|---|---|---|---|---|
| 1 | 0x15 → 0x16 | performKeyExchange | `80 72 00 2f 000000`+40o | 0x2f = 47 | 40 o | `80 d4 0033` type **0x72**, 51 o (charge 40 @off9) | VU |
| 2 | **0x42 → 0x18** | **initializeSequenceCounter** | **`80 73 00 47 000000`+64o** | **0x47 = 71** | **64 o** | **`80 d4 004b` type 0x73, 75 o** (charge 66 @off9) | **VU** |
| 3 | **0x5f** (+OOL 16 Ko) | **LoadPatch** | **`80 60 00 07 000000`** (prélude 7 o) **puis** gros bloc brut | voir §3 | — | état seul (`…2901007c…` = patch chargé) | **VU** |
| 3b | — | (le gros bloc du patch) | **bloc contigu `8c 56 3a 00…`** | **0x568e = 22158 o** | ~22151 o | pas de read-back ; ACK via état | **VU** |
| 4 | **0x5d** | applySensorParams | **`80 55 00 40 000000`+57o** | **0x40 = 64** | 57 o | état seul (pas de read-back) | **VU** |
| 5 | **0x5c** | applySensorParams | **`80 55 00 40 000000`+57o** | **0x40 = 64** | 57 o | état seul | **VU** |
| 6 | **0x6a / 0x31** | applySensorParams / n° série | **`80 55 00 49 000000`+66o** | **0x49 = 73** | 66 o | **`80 d4 004b` type 0x75, 75 o** → sbio **0x32** | **VU** |
| 7 | **0x01** | fin loadPatch (état capteur=3) | — (SEP seul) | — | — | — | VU |
| 8 | 0x1f | cacheMatchPolicy | — (SEP seul) | — | — | — | VU |
| 9 | **0x31** (répété) | n° série module | **`80 55 00 49 000000`+66o** | **0x49 = 73** | 66 o | **type 0x75, 75 o** → sbio **0x32** | **VU** |
| 10 | **0x5b** (+OOL ~64 Ko, 4 frags) | **setCalibrationData** | **AUCUNE trame SPI** | — | — | — (consommé côté SEP) | **VU (décisif)** |
| 11 | 0x63 | getCalibrationDataInfo | — (SEP seul) | — | — | — | VU |
| 12 | **0x19** | HandleReset (reset capteur) | — ; suivi de réveil `80 70` (identité) | 7 | — | `80 d4 001b` type 0x70, 27 o | VU |

Après le `0x19`, **toute la séquence #1→#6 recommence** (2e passe), avec une variante aux paramètres (§2b).
Pas de 2e `0x5b` en C19 (calibration envoyée une seule fois).

### 2b. 2e passe — ce qui change aux `applySensorParams` (VU C19)

Les tailles des trames `0x55` dépendent de l'opcode : au 2e tour, `0x6a` et `0x6f` émettent leurs **propres**
trames (au 1er tour `0x6a` était replié avec `0x31`) :

| op sbio | trame SPI | taille totale | charge |
|---|---|---|---|
| 0x5d | `80 55 00 40` | 0x40 = 64 | 57 o |
| 0x5c | `80 55 00 40` | 0x40 = 64 | 57 o |
| **0x6a** | `80 55 00 **4d**` | 0x4d = 77 | 70 o |
| **0x6f** (2e passe seulement) | `80 55 00 **56**` | 0x56 = 86 | 79 o |
| 0x31 | `80 55 00 49` | 0x49 = 73 | 66 o (réponse type 0x75) |

**Règle sbio5 (VU) :** ne pas coder une taille de charge `0x55` en dur — elle vient du `gt_packet_t` de l'opcode
sbio. L'AP **habille** la charge fournie par le SEP (`80 55 <7+len BE> 000000` + charge) ; le patch de longueur
suit la même règle « taille totale ».

---

## 3. Le patch (`0x5f`) : comment le gros bloc est poussé (VU C19, le point qui tranche)

Déroulé fil **exact** entre `SEP > 0x5f` et `SEP > 0x5d` :

```
SEP > 0xfc 0x5f                    (commande LoadPatch)
SEP > 0xfe 0x5f / < 0xfd 0x5f      (le SEP livre le patch à l'AP en OOL mailbox, 1 frag ≈ 16 Ko)
TX  80 60 00 07 00 00 00           (prélude SPI : « reçois le patch », 7 o)
TX  8c 56 3a 00 00 00 00 …         (UN SEUL bloc de 0x568e = 22158 o — le patch chiffré)
poll 0x10 → état 00 29 01 00 7c…   (= « repos, correctif chargé » ; PAS de read-back)
SEP > 0x5d …                       (on enchaîne les paramètres)
```

Points VU :

- **Un seul transfert.** Entre le prélude `0x60` et le poll suivant, il y a **exactement une** opération TX SPI :
  le bloc de **22158 o** (2e passe : **28878 o**). **Aucun fractionnement** en trames FIFO-taille. (VU C19 :
  `sio_dialog` ne montre qu'un `TX 0x568e` puis qu'un `TX 0x70ce` sur toute la capture.)
- **Le bloc n'a pas l'en-tête `80 <cmd> <len>`** des petites trames. Il commence par **`8c 56 3a 00…`**
  (2e passe `cc 70 3a 00…`). Lecture probable (**hypothèse**) : 2 o de longueur petit-boutiste (`8c 56` = 0x568c
  = total−2 ; `cc 70` = 0x70cc = total−2) puis l'**enveloppe `3a` + compteur 8 o** de `sensor_hw.md`. Le
  **transport**, lui, est VU : prélude `0x60` 7 o, puis le bloc brut tel quel.
- **Pas de réponse à lire** : le capteur acquitte le patch par son **état** (`…2901007c…` = « correctif chargé »,
  dernier octet `16`), pas par une trame `0x13`. (VU, recoupé table d'état `sensor_hw.md`.)
- **Origine et fraîcheur :** le bloc vient du **SEP** (OOL du `0x5f`). Il est **chiffré et frais** : 1re passe
  22158 o `8c56…`, 2e passe 28878 o `cc70…` (tailles **et** contenus différents) → **non rejouable** en octets ;
  il faut **relayer** ce que le SEP donne, à chaque boot. (VU C19.)

> Note : C19 ne sauvegarde pas les octets OOL **côté SEP** (le tracer `trace_sep_spi_dma.py` ne capture que les
> buffers SPI). Les octets patch **côté SPI** sont dans `sio.bufs` de C19 ; les octets patch **côté SEP** (OOL
> 0x5f) sont dans `traces/20261108-032454_c12-boot-ho/sep.log.ool/` (C12). (VU.)

---

## 4. VERDICT FIFO vs DMA pour les gros blobs (déterminant sbio5)

**Deux blobs « gros » dans la préparation, deux conclusions opposées :**

| blob | taille | va sur SPI ? | transport macOS | contrainte sbio5 |
|---|---|---|---|---|
| **patch** (`0x5f`→bloc) | **~22–29 Ko** | **OUI**, 1 seul burst contigu | **DMA SIO** | **DMA SIO quasi-obligatoire** (voir ci-dessous) |
| **calibration** (`0x5b`) | **~64 Ko** | **NON** (0 trame SPI) | mailbox SEP OOL | **aucune** (pas un pb SPI) |

**Pourquoi le patch est le risque :** le FIFO matériel du contrôleur SPI est minuscule (quelques octets). Pousser
**22 Ko en un seul transfert CS-maintenu** via `mesa_spi_proxy` (FIFO scruté) demanderait des milliers de cycles
remplir-FIFO/attendre-vide **sans relâcher CS**, pilotés depuis le proxyclient m1n1 **par-dessus le tunnel UART**.
C'est lent et fragile, et **rien ne prouve** que le contrôleur maintient CS asserté sur un transfert FIFO aussi
long (macOS, lui, délègue au **DMA SIO** justement pour ça, canal 0x18). **Verdict : pour sbio5, le patch exige
très probablement le chemin DMA SIO** (comme `hv/trace_sep_spi_dma.py` l'observe), pas le FIFO scruté de
`mesa_spi_proxy`. **Bémol honnête :** on n'a pas *testé* un burst FIFO de 22 Ko, donc « FIFO impossible » reste
une **hypothèse forte**, pas un fait prouvé. (VU C19 pour « macOS = 1 burst DMA » ; hypothèse pour « FIFO ne peut pas ».)

**La bonne nouvelle :** le blob **le plus gros** (calibration 64 Ko) **ne touche jamais le SPI** → aucun besoin de
DMA pour lui. Le seul transfert SPI lourd est le patch (~22 Ko). Les paramètres (`0x55`) et tout le reste sont des
**petites trames ≤ 86 o**, parfaitement dans les cordes du FIFO scruté (déjà prouvé pour l'identité par
`mesa_hello`). Donc : **sbio5 = FIFO scruté pour tout SAUF le patch `0x5f`, qui veut DMA SIO.**

---

## 5. D'où viennent les blobs patch / calibration — rejouabilité (VU + recoupé)

- **Patch (`0x5f`)** : **source = SEP** (relais chiffré), **frais chaque boot** → **à relayer vivant**, pas
  rejouable. Les octets SPI sont dans `C19/sio.bufs` ; les octets SEP (OOL) dans `C12/sep.log.ool`. (VU.)
- **Calibration (`0x5b`)** : **source = espace utilisateur** (blob signé), passe **au SEP** (mailbox OOL 4 frags
  ≈ 64 Ko), **jamais sur SPI**. Pour sbio5 : rejeu **mailbox** du blob capturé (classe **D3**, identique C5–C9
  si le n° de série capteur concorde, cf. `sbio_sequence.md` §2). **Pas un problème de transport SPI.** (VU C19 +
  recoupé.)
- **Compteur / clé de session** : jamais côté AP (relais pur, cf. `sbio_keyexchange.md` §0). Les charges `0x73`/
  `0x55`/patch sont **opaques** et **fraîches** à chaque allumage. (VU.)

---

## 6. Plan de trames pour sbio5 (résumé actionnable, à partir du VU ci-dessus)

Après le `0x16` acquitté (fin du key exchange), relayer **dans cet ordre**, chaque fois en lockstep avec l'opcode
sbio fourni par le SEP :

1. `0x42` → **`80 73 00 47`** + 64 o (charge du SEP) ; lire réponse type 0x73 (75 o, charge @off9) → `0x18`.
2. `0x5f` → **`80 60 00 07`** (prélude) **puis DMA** le gros bloc du SEP (~22 Ko) **en un seul transfert** ;
   acquitter via **état** (pas de read-back). **← étape DMA.**
3. `0x5d`,`0x5c` → **`80 55 00 40`** + 57 o ; état seul.
4. `0x6a`/`0x6f` → **`80 55 00 4d`/`0x56`** + charge (taille = `gt_packet_t`, pas en dur) ; état seul.
5. `0x31` → **`80 55 00 49`** + 66 o ; lire réponse type 0x75 (75 o) → `0x32`.
6. `0x01` (fin loadPatch), `0x1f` (cacheMatchPolicy) : **SEP seul**, aucune trame SPI.
7. `0x5b` (calibration) : **SEP seul via mailbox**, **aucune trame SPI** — rejouer le blob D3 côté mailbox.
8. `0x63` : SEP seul. Puis `0x19` (reset) → réveil `80 70` (identité 27 o) → **recommencer 1→5** (2e passe,
   avec `0x6f` en plus).
9. **Règle fail-closed** (« protocole complet avant de répondre ») : la liste des « connus » = cette table.
   Tout opcode ou toute réponse hors table → STOP + dump.

---

## 7. Limites / points ouverts (honnête)

1. **Rien n'est `vérifié` matériel.** C'est une **relecture hors-ligne** d'un boot macOS (C19) : les formes et
   l'ordre sont **VU**, mais la preuve « le SEP + le capteur acceptent ce relais en natif » reste à faire au run
   réel (Albert), xART frais scellé.
2. **Structure interne de l'en-tête du gros bloc** (`8c 56 3a…`) : le **transport** (prélude 0x60 + bloc contigu)
   est VU ; la lecture « 2 o longueur LE + enveloppe `3a` + compteur » est **hypothèse** (sensor_hw §enveloppe).
   Sans incidence sur le relais : l'AP recopie le bloc du SEP tel quel.
3. **« FIFO ne peut pas faire 22 Ko »** = **hypothèse forte** (jamais testée), pas un fait. Ce qui est VU : macOS
   le fait en **1 burst DMA SIO**. Le test « burst FIFO long, CS maintenu » décide — à préparer côté outillage.
4. **Offset exact de la charge dans les réponses `0x75`/`0x73`** (off 9) : VU pour 0x72 (§9.2) et cohérent ici ;
   recoupé mais pas re-disséqué octet par octet pour 0x73/0x75.
5. **Catacomb/gabarits (`0x6d`), lockout (`0x71`)** : hors de cette session capteur (requêtes clients après la
   calibration, cf. `sbio_sequence.md` §1.3) ; non traités ici.

Aucune clé ni secret n'a été extrait ; les charges chiffrées restent opaques et ne sont pas reproduites.
