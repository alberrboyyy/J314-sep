# J5c — après le patch chargé : paramètres, n° de série module, calibration (1re passe macOS)

2026-11-22 — agent driver (session ALARM). But : la séquence EXACTE que macOS joue entre « patch chargé » (état
`29 01 00 7c`) et la fin de la 1re passe d'init (`0x63`), pour l'étendre dans `sep_native` / `sbiod`. Arrêt après `0x63` :
pas de `0x19` ni de 2e passe, pas de `0x6c`/`0x6d`, rien qui touche enrôlement ou match.

Marquage : **VU** = octets lus dans une capture macOS (fichier:ligne ou seq) ; **hypothèse** = interprétation.
Rien ici n'est `vérifié` au sens matériel natif : c'est l'expérience J5c. Sources : `source: trace` sauf mention
`source: kext` (noms d'opérations, `docs/messages.md` §SBIO).

Captures : c12 = `traces/20261108-032454_c12-boot-ho` (`sep.log` + `sep.log.ool/*_08_{A,B}.bin`) ;
C17-C20 = `traces/20261110-00{1859_c17,2417_c18,2829_c19,3201_c20}*` (`spi2.log` registres + broches ; C18-C20 aussi
`sio.log`/`sio.bufs` = octets SPI). Outils : `analysis/sio_dialog.py <C> --sep --full`,
`analysis/spi2_gpio_timeline.py <C> --params` (mode ajouté ce jour : mots EP 0x08 intercalés, temps relatifs au `> 0x5d`).

---

## 1. Séquence et tailles (VU, identique sur 9 boots à OOL : c5, c6, c7, c8, c9, c10b, c11, c12, c20)

`A` = charge envoyée par l'AP (gt_packet `+0x1c`, longueur `+0x18`), `B` = réponse totale du SEP (`+0x04`). Lignes c12 :
`sep.log` (mot `> fc`), fichiers OOL.

| # | op | nom (source: kext) | A (o) | B (o) | SPI capteur | c12 `sep.log` | c12 OOL A / B |
|---|---|---|---|---|---|---|---|
| 1 | 0x5d | applySensorParams | 4 = `00 00 00 00` | 0x37 = 55 | trame 0x55 de 0x40, état seul | L352/354 | 000317 / 000318 |
| 2 | 0x5c | applySensorParams | 4 = `00 00 00 00` | 0x37 = 55 | trame 0x55 de 0x40, état seul | L356/358 | 000319 / 000320 |
| 3 | 0x6a | applySensorParams | 0 | **0** | **aucune** | L360/362 | 000321 / 000322 |
| 4 | 0x31 | n° de série module | 0 | 0x40 = 64 | trame 0x55 de 0x49 → réponse 0x75 (0x4b o) | L364/366 | 000323 / 000324 |
| 5 | 0x32 | n° de série module (2) | 0x40 = charge @9 de la réponse 0x75 | 0x12 = 18 (ASCII) | aucune | L368/370 | 000325 / 000326 |
| 6 | 0x01 | fin loadPatch | 0 | 0 | aucune | L372/374 | 000327 / 000328 |
| 7 | 0x1f | cacheMatchPolicy | 0 | 2 = `05 05` | aucune | L376/378 | 000329 / 000330 |
| 8 | 0x31 | n° de série module | 0 | 0x40 | trame 0x55 de 0x49 → réponse 0x75 | L380/382 | 000331 / 000332 |
| 9 | 0x32 | n° de série module (2) | 0x40 | 0x12 (mêmes 18 o qu'au #5) | aucune | L384/386 | 000333 / 000334 |
| 10 | 0x5b | setCalibrationData | **0xfc99 = 64665, 4 fragments AP→SEP** | 0 | **aucune** | L388-402 | 000335/337/339/341 / 000342 |
| 11 | 0x63 | getCalibrationDataInfo | 0 | 0x1c = 28 | aucune | L404/406 | 000343 / 000344 |

Puis macOS envoie `0x19` (c12 L408) et rejoue toute l'init (2e passe) : voir §8 (niveau 3 / `--upto pass2`).

VU en plus (9/9 boots, contenu) : A de 0x5d/0x5c = `00 00 00 00` ; B de 0x6a et 0x01 vides ; B de 0x1f = `05 05` ; B de
0x32 = la même chaîne de 18 o ASCII (n° de série du module) aux deux paires ; B de 0x63 =
`03000000 00ac6041 00000000 00000000 09000000 03000000 03000000`. Les blobs de 0x5d/0x5c/0x31 sont chiffrés (enveloppe
`3a` + compteur), différents à chaque boot.

## 2. Trame SPI 0x55 (VU C19, recoupé sbio9)

```
80 55 <TOTAL u16 gros-boutiste> 00 00 00 | blob du SEP (len o, tel quel) | CRC16 2 o petit-boutiste
TOTAL = 7 + len + 2 ; CRC = CRC-16/ARC (poly 0xA001 réfléchi, init 0) sur les 7 + len premiers octets.
```

- **Le CRC est ajouté par l'AP et compté dans TOTAL.** 0x5d : blob 0x37 = 55 → 7 + 55 + 2 = 0x40 ; 0x31 : 64 → 0x49.
  Le « 57 o » de `sbio_session.md` §2 = 55 o de blob + 2 o de CRC. VU : recalcul sur les trames C19 (`sio.log` seq 774
  L870, seq 783 L885, seq 792 L900, seq 810 L930) : CRC(en-tête + blob) = les 2 derniers octets, petit-boutiste
  (ex. 0x5d : `0x1700` → `00 17`). Le CRC ne porte PAS sur le blob seul (vérifié : faux).
- Pas de CRC sur 0x72/0x73 (0x2f = 7 + 40, 0x47 = 7 + 64 ; inchangé).
- Réponse capteur à 0x31 (VU C18/C19/C20, 2 par boot) : 0x4b = 75 o =
  `80 d4 00 4b | 00 00 00 00 | 75 | 64 o | CRC16` ; CRC-16/ARC des 73 premiers octets, petit-boutiste (recalculé sur
  C19 seq 808 L926 et seq 826 L956 : juste). Charge @9 = 64 o = A de 0x32 (c12 000325 : `3a 80 …`, même forme que la
  réponse 0x73 → 0x18 déjà relayée).

## 3. Motif de lecture et broche 195 (VU C17 `spi2.log`, C18-C20 `sio.log`)

`analysis/spi2_gpio_timeline.py traces/20261110-001859_c17-spi-boot --params` (C17 = registres seuls, traceur le
moins intrusif) :

- Avant le 1er `> 0x5d` : la lecture d'état « chargé » (`29 01 00 7c`) vient de se faire, 195 réarmée en « IRQ niveau
  haut » (-0,4 ms). Pas d'autre SPI.
- **Trame 0x55 « état seul » (0x5d, 0x5c)** : trame (`len=0x40`) → 195 masquée 0,3 ms après DONE (= l'IRQ a monté ;
  2e passe C17 : 9,6 ms après pour 0x5c) → **une** lecture d'état (0x17 o) → 195 réarmée → mot SEP suivant. Aucune
  lecture d'état avant la montée de l'IRQ, aucune deuxième lecture.
- **Trame 0x55 avec réponse (0x31)** : trame (`len=0x49`) → IRQ (0,5 ms) → **une** lecture d'état (annonce 0x4b) →
  `0x13` (`80 13 00 0b 00 00 00 4b 00 00 00`) → lecture de 0x4b o → 195 réarmée → `> 0x32`. **Pas de lecture d'état
  après la réponse** ; la 2e trame 0x31 part sans lecture d'état intermédiaire (après 0x32, 0x01, 0x1f).
- 0x6a, 0x32, 0x01, 0x1f, 0x5b, 0x63 : aucun SPI.
- Après `< 0x63` : macOS écrit tout de suite gpio0 196 (coupure d'alimentation, C17 +66,1 ms) puis rejoue l'init.
  Il ne lit pas l'état entre 0x32 n°2 et la coupure.

États lus (VU C18, C19, C20, 3/3 identiques ; C17 sans contenu) — corps de 9 o après `80 20 00 10 00 00 00` :

| après | état |
|---|---|
| 0x5d | `00 00 21 00 0c 52 33 00 16` |
| 0x5c | `00 00 21 00 0c 52 33 00 16` |
| 0x31 (n°1 et n°2) | `07 00 21 00 8c 4b 00 00 00` (réponse prête, 0x4b o) |

Hypothèse (forme, pas sens) : octet 0 = état (`00` repos, `07` réponse prête), octets 5-6 = longueur en attente
**seulement quand l'octet 0 vaut 07** (au repos, ces octets valent `52 33`). Conséquence trouvée au passage : la boucle
de `Mesa::relay` (0x72/0x73) prenait `52 33` pour une longueur si le 1er état lu était « repos » ; corrigé (longueur lue
seulement si l'octet 0 = 07). Sans effet sur J5 v2 (le 1er état lu était déjà `07`).

## 4. 0x5b : fragmentation AP→SEP (VU, 23/23 boots pour les mots, 9/9 pour les octets)

Mots (c12 L388-402 ; identiques dans les 23 captures à trafic 0x08 : c1 … c25) :

```
> fc 5b DATA 0x00000000   A8 = fragment 0
< fe 5b DATA 0x00000000   (« suivant »)
> fd 5b DATA 0x00010000   A8 = fragment 1
< fe 5b DATA 0x00010000
> fd 5b DATA 0x00020000   A8 = fragment 2
< fe 5b DATA 0x00020000
> fd 5b DATA 0x00030000   A8 = fragment 3 (dernier)
< fc 5b DATA 0x00000000   B8 = gt_packet {1, total 0, offset 0, op 0x5b, len 0} (000342_08_B.bin)
```

- C'est la règle du compteur GT déjà vérifiée (`gt.rs` : `fe` = nombre de `fd` déjà vus, `fd` = ce nombre + 1), avec
  les rôles inversés par rapport au 0x5f : l'AP envoie `fc` puis `fd`, le SEP répond `fe` puis `fc`.
- Chaque fragment = A8 de 0x4000 : en-tête `{+0x00 1, +0x04 total 0xfc99, +0x08 offset, +0x0c 0, +0x10 0,
  +0x14 0x5b, +0x18 len}` + charge à `+0x1c`. Offsets 0, 0x3fe4, 0x7fc8, 0xbfac ; len 0x3fe4 ×3 puis 0x3ced
  (somme = 0xfc99). Reste de A8 : zéros dans 000335/337/339 ; **000341 porte des octets non nuls après la charge**
  (reste d'un usage antérieur du tampon, hypothèse) : on envoie des zéros.
- B8 au moment des `< fe` : tout à zéro (`nz=0`, c12 seq 336). Qui l'efface (SEP ou macOS) : **inconnu**. Non contrôlé
  par la porte (journalisé seulement).
- Délai `> fd` n°3 → `< fc` : 36-40 ms (c12 39 ms, C17 36 ms, C20 39 ms). Le noyau attend 6 s.
- Blob (= concaténation des 4 charges) : 64665 o, **sha256 `d5a6117dc8b5482320ab4d86c94148f190a7b08530c6235735636b9abd23ddda`**,
  CRC-32 `0x6f98a221`, identique dans les 9 boots à OOL (c5…c20). Contenu : u32 3 puis structure DER (`comb`, `fdrd`,
  `IMG4`, `IM4P`, `FSCl`, `CALB`…). **Il contient le n° de série capteur** (les 16 o d'identité [9..25], envoyés en 0x17)
  à l'offset 91 (0x5b), et la chaîne de 18 o rendue par 0x32 à l'offset 889 (0x379). VU par recherche d'octets ;
  la structure de ces champs n'est pas décodée (hypothèse : le blob est lié à ce capteur / ce module).

## 5. Écarts avec la liste de l'orchestrateur

1. **Il manque une 2e paire 0x31 → 0x32 entre 0x1f et 0x5b** (VU 9/9, et `daemon.rs` INIT_SEQUENCE :
   `… 0x31, 0x32, 0x01, 0x1f, 0x31, 0x32, 0x5b, 0x63`). La séquence codée en a deux.
2. 0x5d / 0x5c : l'AP envoie 4 o (`00 00 00 00`), pas une charge vide.
3. 0x6a en 1re passe : **0 → 0 et aucune trame SPI** (VU 9/9 + C17-C20 4/4). Ce n'est pas « replié avec 0x31 » au sens
   d'une trame commune : la trame 0x49 qui suit vient de 0x31 seul. Porte : réponse de 0x6a bornée à 0 o.
4. 0x32 rend 18 o (pas « livraison sans réponse ») ; `docs/messages.md` (kext) dit « 18 ou 20 o » : ici 18 exact.
5. « Prêt pour un doigt » : macOS **n'utilise jamais** le capteur après la 1re passe. Juste après `0x63` il coupe
   l'alimentation et refait toute l'init (2e passe, avec `0x6f`, sans `0x5b`) : §8. Que le capteur soit utilisable
   après la seule 1re passe est une **hypothèse** ; J5c ne la teste pas (pas de 0x23/0x65/0x09).

## 6. Critères de succès par étape (porte fail-closed de J5c)

| étape | critère (sinon STOP) |
|---|---|
| départ | verdict du patch = chargé (`29`) ; fichier calibration : 64665 o, sha256 ci-dessus ; identité[9..25] == blob[91..107] |
| 0x5d, 0x5c | réponse SEP = 55 o ; 195 basse avant la trame (≤ 20 ms) ; trame `80 55 00 40 000000` + blob + CRC ; 195 monte (≤ 200 ms) ; UNE lecture d'état = `00 00 21 00 0c 52 33 00 16` exactement |
| 0x6a | réponse SEP vide (le noyau refuse autre chose) ; aucun SPI |
| 0x31 | réponse SEP = 64 o ; trame `80 55 00 49 000000` + blob + CRC ; 195 monte ; état = `07 00 21 00 8c 4b 00 00 00` ; 0x13 puis lecture 0x4b ; réponse `80 d4 00 4b 00000000 75`, CRC16 juste |
| 0x32 | charge = réponse[9..73] ; réponse SEP = 18 o == blob[889..907] (les deux fois) |
| 0x01 | réponse vide |
| 0x1f | réponse = `05 05` |
| 0x5b | noyau : charge = 64665 o, CRC-32 `0x6f98a221` ; mots du §4 dans cet ordre ; `< fc` final avec en-tête B8 total 0 |
| 0x63 | réponse 28 o ; égale à la référence macOS → VERDICT « calibré » ; différente → VERDICT « 0x63 ≠ macOS » (pas d'erreur, rien après) |
| fin | aucun SPI après 0x32 n°2 ; capteur éteint |

Tout mot SEP hors de cette liste, toute longueur différente → `Halted` côté noyau (power-cycle). Toute incohérence
côté capteur → STOP de sbiod avant la commande SEP suivante.

## 7. Points incertains (dits, pas inventés)

- La reproduction « IRQ puis une lecture » est calquée sur C17 ; on ne sait pas si une lecture plus précoce ferait
  échouer les paramètres (la leçon du patch dit de ne pas essayer).
- Le rejeu du 0x5b dans une session neuve n'a **jamais** été fait (sbio10 jamais lancé). Le SEP peut le refuser
  (`< fc` avec un en-tête non vide, ou autre mot) → Halted, rien de cassé côté capteur (0x5b ne touche pas le SPI).
- Effacement de B8 aux `< fe` : inconnu (journalisé).
- Sens des octets d'état et du contenu de 0x63 : inconnu ; on compare seulement à macOS.

---

## 8. 2e passe (niveau 3, `sbiod --upto pass2`) — de `0x19` au repos final

2026-11-22, agent driver. Même marquage (VU / hypothèse). Rien de §8 n'a tourné en natif.

### 8.1 Mots et tailles côté SEP (VU)

Ordre des `> fc` de `0x19` jusqu'au premier `0x7c` : **identique dans les 23 captures à trafic 0x08** (c1 … c25) :
`19 17 15 16 42 18 5f 5d 5c 6a 6f 31 32 01 1f 63 63` (= `daemon.rs` `INIT_SEQUENCE[18..35]`). `0x19` et `0x5b`
apparaissent **une seule fois par boot** (23/23) : **pas de 2e 0x5b** (confirmé, pas seulement C19). Aucune
notification (TAG 0x01-0x04) sur 0x08 dans cet intervalle (23/23). Tailles : 9/9 boots à OOL identiques (c5 … c20 ;
c5/c6 ont un traceur plus ancien qui ne sauve pas les A au bon moment, les B sont identiques).

| # porte | op | nom (source: kext) | A (o) | B (o) | SPI capteur | c12 `sep.log` | c12 OOL A / B |
|---|---|---|---|---|---|---|---|
| 17 | 0x19 | HandleReset | 0 | 0 | aucune (après la coupure/rallumage, §8.2) | L408/410 | 000345 / 000346 |
| 18 | 0x17 | prepareSession | 0x10 = n° de série (mêmes 16 o) | 0 | identité lue avant | L412/414 | 000347 / 000348 |
| 19 | 0x15 | keyExchange | 4 = `01 00 00 00` | 0x28 | trame 0x72 (0x2f) | L416/418 | 000349 / 000350 |
| 20 | 0x16 | keyExchange2 | 0x28 | 0 | — | L420/422 | 000351 / 000352 |
| 21 | 0x42 | initSeqCounter | 0 | 0x40 | trame 0x73 (0x47) | L424/426 | 000353 / 000354 |
| 22 | 0x18 | seqCounter2 | 0x40 | 0 | — | L428/430 | 000355 / 000356 |
| 23 | 0x5f | LoadPatch | 2 = `02 00` | **0x70ce = 28878** (0x3fe4 + 0x30ea, `fe`/`fd`) | prélude 0x60 + bloc | L432-438 | 000357 / 000358, 000360 |
| 24 | 0x5d | applySensorParams | 4 = `00 00 00 00` | 0x37 | trame 0x55 de 0x40 | L441/444 | 000362 / 000364 |
| 25 | 0x5c | applySensorParams | 4 = `00 00 00 00` | 0x37 | trame 0x55 de 0x40 | L446/448 | 000365 / 000366 |
| 26 | 0x6a | applySensorParams | 0 | **0x44 = 68** (1re passe : 0) | **trame 0x55 de 0x4d** | L450/452 | 000367 / 000368 |
| 27 | 0x6f | (2e passe seulement) | 0 | **0x4d = 77** | **trame 0x55 de 0x56** | L454/456 | 000369 / 000370 |
| 28 | 0x31 | n° de série module | 0 | 0x40 | trame 0x55 de 0x49 → 0x75 | L458/460 | 000371 / 000372 |
| 29 | 0x32 | n° de série module (2) | 0x40 | 0x12 (= la chaîne de la 1re passe) | — | L462/464 | 000373 / 000374 |
| 30 | 0x01 | fin loadPatch | 0 | 0 | — | L466/468 | 000375 / 000376 |
| 31 | 0x1f | cacheMatchPolicy | 0 | 2 = `05 05` | — | L470/472 | 000377 / 000378 |
| 32 | 0x63 | getCalibrationDataInfo | 0 | 0x1c = la réf. de §1 | — | L474/476 | 000379 / 000380 |
| 33 | 0x63 | idem (1,2 ms après) | 0 | 0x1c, mêmes octets (B8 inchangé, `changed=none`) | — | L478/480 | (pas de fichier : sha 6704282b / aa957732 inchangées) |

- **Une seule paire 0x31/0x32** en 2e passe (la 1re passe en a deux).
- Le patch n°2 (`cc 70 3a 00…`) a **la même taille 0x70ce dans les 9 boots** et les 4 captures SPI : la porte borne
  sa réponse à 0x70ce exactement (la 1re passe garde `2 .. 0x10000`, éprouvée). Préfixe u16 LE = longueur − 2 (VU).
- Après le 2e 0x63, macOS envoie `0x7c` (c12 L482), puis `0x6b`/`0x79`/`0x6d`/`0x39`… (catacomb, gabarits) : c'est
  le premier « usage » ; **le repos final = après le 2e `< 0x63`**. Rien de tout cela n'est admis.
- c12 montre un mot EP 0x12 (SKS) TYPE 0x1a entre le `< fd 5f` et le `> 0x5d` (L440/443) ; absent de C17, placé
  ailleurs en C19 : trafic SKS de macOS indépendant de l'init (hypothèse). Non reproduit (le pilote ne parle pas à
  0x12) ; la 1re passe native a réussi sans.

### 8.2 Entre le 0x63 de la 1re passe et le 0x17 de la 2e (VU C17 registres, C18/C19/C20 octets)

C17 `spi2.log` (traceur le moins intrusif), temps relatifs au `< 0x63` (`sep.log` L360, 1794266379.282426) :

```
+0,07 ms  gpio0 196 = 0x76a02 (sortie basse : coupure)              spi2.log L1239
+11,0 ms  gpio0 196 = 0x76a03 (sortie haute : rallumage)             spi2.log L1241
+14,7 ms  195 masquée ; +18,4 ms 195 « IRQ niveau haut » ; +19,1 ms masquée (l'IRQ est montée ~8 ms après le rallumage)
+19,4 ms  lecture d'état n°1 (0x17 o)                                spi2.log L1266
+20,5 ms  195 réarmée ; +21,1 ms lecture d'état n°2, SANS attendre d'IRQ   L1296
+21,3 ms  > 0x19 (sep.log L361) ; < 0x19 +0,06 ms
+21,6 ms  80 70 (identité, 7 o)                                      L1325 ; IRQ 0,04 ms après
          état → 0x13 (0x1b) → lecture 0x1b → état → 195 réarmée
+25,0 ms  > 0x17 (sep.log L363)
```

- Coupure : 4/4 captures (C17-C20), juste après `< 0x63` (≤ 0,8 ms), durée **11,0-11,6 ms** ; même coupure de
  11,1 ms avant la 1re passe (C17 1794266379.105711 → .116808). `< 0x63` → `> 0x19` : 21,3 ms (C17), 41-43 ms (C18-C20,
  traceurs DMA plus lents).
- **Pas de `80 78`** : ni avant la 1re passe (C19 t=28,611) ni avant la 2e ; macOS ne l'envoie qu'une fois, au tout
  premier sondage du boot (C19 t=0,067). Notre 1re passe native l'envoie (éprouvé) ; **la 2e passe le supprime**,
  comme macOS (choix, cf. §8.5).
- États (corps de 9 o), C18/C19/C20 **3/3 identiques** (`sio_dialog.py <C> --sep --full`, C19 t=29,048-29,109) :

| lecture | état |
|---|---|
| n°1 après rallumage | `00 60 00 00 18 52 33 00 00` (= aussi le 1er état de la 1re passe, C19 t=28,614) |
| n°2 (aussitôt) | `00 60 00 00 00 52 33 00 00` |
| après `80 70` | `07 60 00 00 88 1b 00 00 00` (0x1b en attente) |
| après lecture de l'identité (27 o = `IDENTITY_J314C`) | `00 60 00 00 00 52 33 00 00` |

### 8.3 Push du patch n°2 (VU C17-C20, `spi2_gpio_timeline.py <C> --patch`)

Même motif que le 1er : prélude `80 60` → IRQ (C17 +0,3 ms) → **une** lecture d'état (`00 60 00 00 08 52 33 00 00`,
C18/C19 ; identique au 1er push) → bloc 0x70ce en un transfert → aucune SPI → IRQ → **une** lecture =
`00 29 01 00 7c 52 33 00 16` (C18/C19/C20 3/3, même marqueur 0x29 qu'au 1er). IRQ après la fin du bloc :
**54,8 / 52,6 / 49,5 / 49,6 ms** (C17/C18/C19/C20 ; 1er push : 42,6 / 40,3 / 37,9 / 37,8 ms). Le noyau/sbiod
attendent 300 ms (`WAIT_LOAD_IRQ_MS`). État avant le prélude = celui lu après la réponse 0x73 (comme la 1re passe).

### 8.4 Paramètres de la 2e passe (VU C17 registres, C18/C19/C20 octets)

C17 `--params`, 2e phase (1794266379.407303) : chaque trame (0x40, 0x40, **0x4d**, **0x56**, 0x49) → IRQ (0,1-9,6 ms)
→ **une** lecture d'état → 195 réarmée → mot SEP suivant. États 3/3 : `00 00 21 00 0c 52 33 00 16` après 0x5d, 0x5c,
0x6a **et** 0x6f ; `07 00 21 00 8c 4b 00 00 00` après 0x31, puis 0x13 + lecture de 0x4b (`80 d4 00 4b 00000000 75` …).
Après la réponse 0x75 : **plus aucune SPI** (C19 : la suivante est le `80 40` de t=31,189, après `0x7d`, hors init).
Trames : `80 55 <7+len+2> 00 00 00` + blob + CRC16 (§2), 0x4d = 7 + 68 + 2, 0x56 = 7 + 77 + 2 (VU C19 t=29,373/29,391).

### 8.5 Ce que fait le niveau 3 / `--upto pass2` (porte fail-closed)

Seulement si la 1re passe a fini par le 0x63 de macOS (verdict « calibré »). Tout écart → STOP de sbiod avant la
commande SEP suivante, ou Halted côté noyau (taille hors borne, ordre).

| étape | critère (sinon STOP) |
|---|---|
| coupure | 196 = 0 pendant **40 ms** (macOS 11 ms : écart choisi, une coupure plus longue ne peut que mieux remettre à zéro — **hypothèse**) puis 196 = 1 |
| réveil | 195 haute en ≤ 100 ms (macOS ~8 ms) — sinon aucune lecture ; état n°1 = `00 60 00 00 18 52 33 00 00`, état n°2 = `00 60 00 00 00 52 33 00 00` |
| 0x19 | réponse vide |
| identité | `80 70` (pas de `80 78`) ; 195 haute ≤ 50 ms ; état `07 60 00 00 88 1b 00 00 00` ; 0x13 + 27 o = identité ; état `00 60 00 00 00 52 33 00 00` |
| 0x17 … 0x18 | comme la 1re passe (n° de série = gabarit = blob[91..107], 40/64 o, réponses 0x72/0x73 @ 9) |
| 0x5f | réponse = **0x70ce** (noyau et sbiod), préfixe = longueur − 2 ; push §8.3 ; état chargé 0x29, sinon STOP |
| 0x5d, 0x5c | 55 o ; trame 0x40 ; état `00 00 21 00 0c 52 33 00 16` |
| 0x6a | **68 o** ; trame 0x4d ; même état |
| 0x6f | **77 o** ; trame 0x56 ; même état |
| 0x31 / 0x32 | 64 o → trame 0x49 → `07 00 21 00 8c 4b…` → 0x75 (CRC) → 0x32 = 18 o **= n° de série module de la 1re passe** |
| 0x01, 0x1f | vide ; `05 05` |
| 0x63 ×2 | 28 o = réf. §1 ; le 1er différent → verdict « 0x63 ≠ macOS », **2e non envoyé** |
| fin | aucune SPI après la réponse 0x75 ; capteur éteint par sbiod (macOS le laisse allumé : il enchaîne 0x7c) |

Porte noyau : `RELAY_SEQUENCE` passe de 17 à 34 étapes, toujours **linéaire** (index `next`) : chaque opcode de la
2e passe n'est admis qu'à son rang (un 0x17 juste après 0x63, un 0x31 à la place de 0x6f, un 0x5b → Halted) ;
`allow_sbio_params=3` → `LIMIT_PASS2 = 34`.

### 8.6 Incertain (dit, pas inventé)

- **Durée de coupure** : 40 ms au lieu de 11 ms. Si le capteur garde son patch (état ≠ `00 60 … 18`), STOP avant 0x19.
- **Sans `80 78`** : calqué sur macOS, jamais fait sous Linux (la 1re passe native l'envoie). Si l'état après `80 70`
  n'est pas celui de macOS → STOP (le SEP a seulement reçu 0x19).
- **0x19 hors macOS** : jamais envoyé ; effet côté SEP inconnu (nom kext HandleReset). Le SEP pourrait refuser un 2e
  0x17/0x15 (clé de session neuve ?) → Halted, power-cycle.
- **Délai 0x63 → 0x19** : macOS 21-43 ms ; ici ~40 ms de coupure + ≤ 100 ms + 2 lectures (≈ 70 ms). Sensibilité au
  délai inconnue.
- **Sens** des états et de 0x6a/0x6f (2e passe) : inconnu ; seulement comparés à macOS.
- Le capteur est-il « prêt pour un doigt » au repos final ? Hypothèse (c'est l'état d'où macOS part pour 0x7c/0x6d) ;
  non testé (rien de match/enrôlement).
