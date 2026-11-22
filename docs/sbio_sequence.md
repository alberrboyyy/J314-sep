# sbio (EP 0x08) — carte ordonnée du 0x73 jusqu'au match, et plan « au-delà du 0x73 »

2026-11-22 — analyste. But : donner un plan clair pour le prochain script natif « sbio au-delà du 0x73 »
(cf. route native, breakthrough 2026-11-22 : après scellement d'un xART frais, le `0x73` natif reçoit la réponse
de référence macOS). On dit **jusqu'où** on peut aller sans doigt / sans secret capteur, et **où est le mur suivant**.

Sources :
- **trace** = `traces/20261108-032454_c12-boot-ho` (`sep.log` + `sep.log.ool/*_08_*.bin`), C12 ci-dessous.
  Outils : `analysis/sbio_gt_packet.py` (parse l'opcode `gt_packet_t +0x14` et la taille de charge), lecture
  directe de `sep.log`. **Format fil `gt_packet_t` = `vérifié`** (docs/messages.md §SBIO, kext §13b).
- **kext** = `docs/kext_sepmanager.md` §4-§7, §12c/§12d, §13 ; `docs/messages.md` §SBIO (noms d'opérations
  `source: kext`, statut `hypothèse` sauf mentions `vérifié`).
- **capteur** = `docs/sensor_hw.md` (dialogue SPI AP↔capteur, `vu` macOS) et `docs/route_native.md`.

**Statut global : les NOMS d'opérations et les rôles sont `hypothèse` (source: kext).** Ce qui est `vérifié` :
le format fil (`gt_packet_t`), le verdict de match 0x09 (`match_info_t`), et l'**ordre/les tailles** observés dans C12
(= VU en trace). La **classe de rejouabilité** de chaque étape est une **interprétation** (séparée ci-dessous).

---

## 0. Avertissement décisif : C12 est un boot SANS doigt (VU)

La séquence EP 0x08 de C12 va du `0x73` (L318) jusqu'à des requêtes clients (L672, op 0x0b) **puis s'arrête**
(fin de capture = timeout). **Il n'y a AUCUN match (0x09), AUCUNE capture d'image (0x23/0x65/0x07) dans C12** :
aucun doigt n'a été posé. La **micro-séquence de match** (`23 06 65 07 … 09 …`) n'est donc **PAS** dans cette trace ;
elle est documentée à partir de **C11** (`…025802_c11-doigt-tranchant`) + kext (§3 ci-dessous, source: trace C11 / kext).
C12 donne donc **toute la préparation sbio** (init + session capteur + calibration + catacomb + requêtes clients),
pas le match lui-même.

---

## 1. VU (trace C12) — carte ordonnée des transactions EP 0x08, du 0x73 à la fin de capture

Chaque ligne = une transaction mailbox `type=0xfc` (une commande sbio). `len` = longueur de charge du
`gt_packet_t` (buffer A = AP→SEP) lue par `sbio_gt_packet.py`. `op` = opcode `gt_packet_t +0x14`. Les fragments
`0xfe/0xfd` (gros transferts) sont repliés sur leur transaction. Noms = `source: kext`.

### 1.1 Init + 1re passe capteur (L318→L402)

| L (sep.log) | op | len A | opération (kext) | classe (interprété) |
|---|---|---|---|---|
| 318 | 0x73 | 4 | `initSbioCommunication` (entrée **u32 = 1**, constante) | **[AP]** rejouable côté AP (comme le breakthrough) |
| — (320) | — | — | SEP→AP `< TAG=0x04` (signal « sbio prêt », §6/§12d) | — (réponse SEP) |
| 324 | 0x17 | 0x10 | `prepareSession` — **n° de série lu sur le capteur** | **[SPI]** capteur vivant (pas de doigt) |
| 328 | 0x15 | 4 | `performKeyExchange` (sessionType=1) | **[SPI]** capteur (clé de session SEP↔capteur) |
| 332 | 0x16 | 0x28 | `performKeyExchange` (2) — réponse du capteur (40 o) | **[SPI]** capteur |
| 336 | 0x42 | 0 | `initializeSequenceCounter` | **[SPI]** capteur |
| 340 | 0x18 | 0x40 | compteur (réponse capteur, 0x40 o) | **[SPI]** capteur |
| 344 | 0x5f | 2 (+ OOL 16 Ko) | `LoadPatch` — patch capteur **fourni par le SEP** (B = 16 Ko) | **[SPI]** capteur (patch vient du SEP) |
| 352 | 0x5d | 4 | `applySensorParams` | **[SPI]** capteur |
| 356 | 0x5c | 4 | `applySensorParams` (suite) | **[SPI]** capteur |
| 360 | 0x6a | 0 | `applySensorParams` (suite) | **[SPI]** capteur |
| 364 | 0x31 | 0 | n° de série module (kext) | **[SPI]** capteur |
| 368 | 0x32 | 0x40 | n° de série module (2) | **[SPI]** capteur |
| 372 | 0x01 | 0 | fin de `loadPatch` (passe état capteur = 3, §K6-1) | **[SPI]** capteur |
| 376 | 0x1f | 0 | `cacheMatchPolicy` | **[SEP]** cache/politique, sans capteur ni doigt |
| 380 | 0x31 | 0 | n° de série module (répété) | **[SPI]** capteur |
| 384 | 0x32 | 0x40 | n° de série module (2, répété) | **[SPI]** capteur |
| 388 | 0x5b | 0xfc99 (4 frags) | `setCalibrationData` — **blob espace-utilisateur signé** (≈ 64 Ko) | **[BLOB]** D3 (rejouable si n° série capteur concorde) |

### 1.2 Calibration + reset + 2e passe capteur (L404→L472)

| L | op | len A | opération (kext) | classe |
|---|---|---|---|---|
| 404 | 0x63 | 0 | `getCalibrationDataInfo` | **[SEP]** |
| 408 | 0x19 | 0 | `HandleReset` (reset capteur) | **[SPI]** capteur |
| 412 | 0x17 | 0x10 | `prepareSession` (2e passe) | **[SPI]** capteur |
| 416 | 0x15 | 4 | `performKeyExchange` | **[SPI]** capteur |
| 420 | 0x16 | 0x28 | `performKeyExchange` (2) | **[SPI]** capteur |
| 424 | 0x42 | 0 | `initializeSequenceCounter` | **[SPI]** capteur |
| 428 | 0x18 | 0x40 | compteur | **[SPI]** capteur |
| 432 | 0x5f | 2 (+ OOL 16 Ko) | `LoadPatch` | **[SPI]** capteur |
| 441 | 0x5d | 4 | `applySensorParams` | **[SPI]** capteur |
| 446 | 0x5c | 4 | `applySensorParams` | **[SPI]** capteur |
| 450 | 0x6a | 0 | `applySensorParams` | **[SPI]** capteur |
| 454 | 0x6f | 0 | `applySensorParams` — **présent seulement au 2e tour** (drapeau 0x5b, §K6-2) | **[SPI]** capteur |
| 458 | 0x31 | 0 | n° de série module | **[SPI]** capteur |
| 462 | 0x32 | 0x40 | n° de série module (2) | **[SPI]** capteur |
| 466 | 0x01 | 0 | fin de `loadPatch` | **[SPI]** capteur |
| 470 | 0x1f | 0 | `cacheMatchPolicy` | **[SEP]** |

### 1.3 Catacomb (gabarits) + requêtes clients (L474→L672, fin de capture)

| L | op | len A | opération (kext) | classe |
|---|---|---|---|---|
| 474, 478 | 0x63 ×2 | 0 | `getCalibrationDataInfo` | **[SEP]** |
| 482 | 0x7c | 0 | `GetBioDeviceList` | **[SEP]** requête client (IOMD) |
| 486, 490 | 0x6b, 0x79 | 0 | `GetCatacombState`, `GetCatacombGroupState` | **[SEP]** |
| 494 | 0x6d | 0xf4 | `LoadCatacomb` (1er envoi, petit) | **[BLOB]** D4 (catacomb) |
| 498 | 0x39 | 0 | `cacheSysProtectedConfig` | **[SEP]** |
| 502-516 | 0x6b, 0x79 ×2 | 0 | état catacomb | **[SEP]** |
| 520 | 0x6d | 0x9245 (3 frags) | `LoadCatacomb` (2e envoi, ≈ 37 Ko) — **blob espace-utilisateur** = dernier export `0x6c` | **[BLOB]** D4 (rejouable depuis capture) |
| — (530/532) | — | — | SEP→AP `< TAG=0x01` lockState **0x0015** puis **0x0055** (keybag verrouillé + blocage bio, §6) | — (notif SKS) |
| 538 | 0x2b | 4 | `cacheProtectedConfigurationSpecific` | **[SEP]** |
| 542, 546 | 0x6b, 0x79 | 0 | état catacomb | **[SEP]** |
| 550 | 0x54 | 0x14 | `RequestTopologyOfTemplate` | **[SEP]** requête client |
| 554 | 0x2b | 4 | `cacheProtectedConfig` | **[SEP]** |
| 558 | 0x33 | 4 | (requête client, IOMD) | **[SEP]** |
| 562 | 0x36 | 4 | `performSpecificCommandGated` | **[SEP]** |
| 566 | 0x6e | 4 | `GetIdentitiesList` | **[SEP]** |
| 570 | 0x7a | 0 | `GetIdentityRecords` | **[SEP]** |
| 574 | 0x71 | 0x69 | `LoadBioLockoutRecord` — **blob `HRLB` espace-utilisateur** | **[BLOB]** D5 (lockout) |
| — (576) | — | — | SEP→AP `< TAG=0x01` lockState **0x0011** (avant login, §6) | — (notif SKS) |
| 580 | 0x28 | 0 | `cacheCaptureData` / specificCmd | **[SEP]** |
| 584, 598 | 0x7c ×2 | 0 | `GetBioDeviceList` | **[SEP]** |
| 594, 610, 632 | 0x2b ×3 | 4 | `cacheProtectedConfig` | **[SEP]** |
| 614, 618 | 0x63 ×2 | 0 | `getCalibrationDataInfo` | **[SEP]** |
| 652 | 0x7d | 0 | `updateOperationDeviceList` | **[SEP]** |
| 670 | 0x0b | 0 | `commandCancel` (fin de requête client) | **[SEP]** |

**Fin de la capture C12** après L672 (op 0x0b). Pas de match.

---

## 2. INTERPRÉTÉ — les quatre classes de rejouabilité

Ce que l'AP doit produire pour chaque classe (interprétation à partir de kext §4/§7 + sensor_hw.md + route_native.md) :

- **[AP] — rejouable côté AP, sans capteur.** Entrée connue et constante, commande SEP-seule (pas de dialogue
  capteur). **Seul `0x73`** (entrée u32 = 1). C'est exactement l'étape prouvée au breakthrough 2026-11-22.
- **[SPI] — nécessite le capteur vivant (pas de doigt).** L'AP est un **pur relais** entre le SEP et le capteur
  Touch ID sur SPI (`sensor_hw.md` §« L'AP est un simple relais ») : le contenu est **chiffré SEP↔capteur**,
  **frais à chaque boot** (compteur/clé de session dans le capteur). Donc **PAS un rejeu d'octets** d'une capture :
  il faut **rejouer le dialogue SPI vivant** en lockstep avec chaque opcode sbio. L'AP **n'a jamais besoin du secret
  capteur** (posé en usine, négocié par le SEP). Nécessite : capteur présent + alimenté (acquis C-A, `route_native.md`
  §1). Opcodes : `0x17 0x15 0x16 0x42 0x18 0x5f 0x5d 0x5c 0x6a 0x6f 0x31 0x32 0x01 0x19`.
- **[BLOB] — nécessite un blob espace-utilisateur.** Rejouable **depuis une capture** si le n° de série du capteur
  concorde (le kext vérifie signature + n° série) :
  - `0x5b` calibration (D3, identique C5-C9, `faible si rejouable`) ;
  - `0x6d` catacomb/gabarits (D4, = dernier export `0x6c` ; **mais** : gabarits = l'enrôlement, scellés à l'état SEP —
    un enrôlement Linux est un **autre chantier**, cf. `route_native.md` §6) ;
  - `0x71` BioLockoutRecord (D5, `HRLB` ; rejouer ou omettre = à tester).
- **[SEP] — cache/politique/requête client, sans capteur ni doigt.** Entrée vide ou petite ; réponses IOMD écrites
  pour biometrickitd (le kext ne les lit pas pour la plupart). Opcodes : `0x1f 0x63 0x6b 0x79 0x7c 0x2b 0x54 0x33
  0x36 0x6e 0x7a 0x28 0x7d 0x0b 0x39`. Rejouables côté AP **si** le SEP accepte la requête hors-séquence (à tester) ;
  nécessité réelle pour un match : **inconnue** (kext §7 item 9).

---

## 3. VU (C11) + kext — la micro-séquence de MATCH (ABSENTE de C12)

Documentée à partir de **C11** (`…025802_c11-doigt-tranchant`, `> EP=0x08` ~L1841+) et du kext (§12c/§12d, §13c ;
`messages.md` §SBIO). **Ordre fil observé en C11** (une transaction `0xfc` par opcode) :

```
0x23  0x06  0x65  0x07  [0x1e]  0x09  0x1f  0x22  …  0x70  0x03  0x21
```

| op | len (kext/trace) | opération (kext) | classe (interprété) |
|---|---|---|---|
| 0x23 | 0 | `asyncCaptureHandler` (début de tentative, après « kImageProcessingInit ») | **[SEP]** (pas de doigt pour l'armement) |
| 0x06 | 0xa7 | `asyncCaptureHandler` — entrée = `_lastImageProcessingParams` (**D6**, origine non lue) | **[SEP]** mais D6 = param à retrouver |
| **0x65** | **0x7200** | capture : **image du doigt** lue sur SPI (12 × 0x980) et recopiée vers le SEP | **[FINGER]** doigt posé + capteur |
| 0x07 | 0xc0 (réponse) | résultat de traitement d'image (`+0x06/07`=`01 01` → image exploitable) | **[FINGER]** suit l'image |
| 0x1e | 0 | `handleMatch` étape | **[SEP]** |
| **0x09** | **réponse 0xca2** | `handleMatch` — **le verdict** (`match_info_t`) | **[FINGER]** — **verdict `vérifié`** |
| 0x1f | 0 | `cacheMatchPolicy` | **[SEP]** |
| 0x22 | 0 | `kEnableBgOpsUpdate` (fin de tentative) | **[SEP]** |
| 0x70 | 0 | `SaveBioLockoutRecord` (sortie `HRLB`) | **[SEP]** (écrit un blob utilisateur après) |
| 0x03 | — | `commandStartEnroll` (présent dans la queue fin-de-séquence) | **[SEP]** |
| 0x21 | 0 | `checkBgOpsResult` (après `< TAG=0x03`) | **[SEP]** |

**Verdict 0x09 = `vérifié` (c6/c8/c11)** : réponse `gt_packet_t` opcode 0x09, charge `match_info_t` 0xca2 o ;
`+0x00` u32 = **0x1f5** (succès, user 501) ou **0xffffffff** (échec) ; `+0x04` = identifiant du gabarit du doigt
enrôlé (succès) ou zéros (échec). C'est le signal « doigt reconnu » que le driver Linux lira (`messages.md` §SBIO).

**D2 (gating keybag) — non tranché.** Au boot (C11/C12), lockState = 0x0015 = keybag verrouillé + **blocage bio**
jusqu'à « code validé » (0x0228). **Inconnu** : le SEP **refuse-t-il** `0x09` sous blocage bio, ou macOS s'abstient-il
seulement ? Non tranchable sans écriture EP 0x12 (ligne rouge Albert). Cf. kext §6/§15.6, `messages.md` D2.

---

## 4. Jusqu'où sans doigt / sans secret capteur — et le prochain mur

**Sans doigt ET sans jamais connaître le secret capteur, on peut aller de `0x73` jusqu'à la FIN de toute la
préparation** (tout C12 : init → session capteur ×2 → calibration → catacomb → requêtes clients). Raisons :
- aucune de ces étapes ne pose un doigt ;
- pour les étapes **[SPI]**, l'AP **relaie** un dialogue chiffré SEP↔capteur dont il n'a **pas besoin de connaître le
  secret** (posé en usine, négocié par le SEP) ; il lui suffit du **capteur vivant** (acquis) et de **rejouer le
  transport SPI** (`sensor_hw.md`) en lockstep ;
- les étapes **[BLOB]** se rejouent depuis une capture (sous réserve concordance n° série pour 0x5b ; le catacomb
  0x6d = gabarits macOS, voir réserve enrôlement).

**Prérequis amont (hors sbio) — non négociable :** `0x73` lui-même n'a répondu « référence » **qu'après** que le SEP
a **scellé un xART frais** (route native EP 0x13). Donc la carte §1 n'est atteignable **qu'une fois sbio armé**
(xART scellé). Ce prérequis = écriture SEP = **Albert** (`pending/`).

**Le prochain mur (au-delà de C12) = le MATCH, qui exige un doigt :**
1. **[FINGER] `0x65` (image 0x7200) + `0x09` (verdict)** : un vrai match demande une **image de doigt** lue sur le
   capteur → **session humaine**. (Les gabarits à matcher = catacomb 0x6d ; sous Linux, l'enrôlement propre est un
   **autre chantier** — les gabarits macOS sont scellés à l'état macOS.)
2. **D6 `0x06`** : entrée `_lastImageProcessingParams` (0xa7 o) d'origine non lue — à extraire (Mesa) ou rejouer.
3. **D2 (keybag)** : possible refus de `0x09` tant que le keybag est verrouillé — tranchable seulement par écriture
   EP 0x12 (Albert).

---

## 5. Plan pour le prochain script natif « sbio au-delà du 0x73 »

Objectif réaliste et **sans doigt** : étendre le run natif du `0x73` jusqu'à la fin de la préparation (bas de C12),
pour prouver que sbio accepte toute la séquence d'init native (et nommer tout refus). Étapes :

1. **Prérequis (Albert, déjà en place sur la route native)** : SEPOS booté + **xART frais scellé** (EP 0x13) → sbio
   armé. Sans ça, inutile d'aller au-delà de `0x73`.
2. **[AP] `0x73`** : déjà prouvé (entrée u32=1, réponse de référence + `< TAG=0x04`).
3. **[SPI] boucle de dialogue capteur en lockstep** : pour `0x17 0x15 0x16 0x42 0x18 0x5f …`, le driver doit
   **piloter le capteur sur SPI** (transport `sensor_hw.md` : trames 0x10/0x13/0x72/0x73/0x60/0x55…) et **relayer** :
   lire la réponse capteur → la mettre en entrée du `gt_packet_t` de l'opcode sbio ; renvoyer la sortie SEP au capteur.
   Fondations déjà faites : `tools/mesa_hello.sh` (capteur répond), modules `driver/linux/`. **Rien à fabriquer comme
   secret.**
4. **[BLOB] `0x5b` (calibration), `0x6d` (catacomb), `0x71` (lockout)** : rejouer les blobs capturés (C5-C9 pour 0x5b ;
   dernier `0x6c` pour 0x6d). Réserve enrôlement pour 0x6d.
5. **[SEP] requêtes de cache/clients** (`0x1f 0x63 0x6b 0x79 0x2b …`) : émettre comme en C12 ; **fail-closed** sur tout
   opcode ou toute réponse non prévue (règle « protocole complet avant de répondre » : la liste des « connus » = la
   carte §1).
6. **Arrêt AVANT le match** : ne pas tenter `0x23/0x06/0x65/0x07/0x09` sans doigt (= session humaine) ni sans avoir
   tranché D2. Préparer la session doigt (`docs/hypotheses.md`, « EXPÉRIENCE HUMAINE ») une fois §1 natif validé.

**Ce qui reste `hypothèse` à lever par l'expérience :** que le SEP, une fois le xART frais scellé, accepte bien la
séquence §1 complète en natif (jusqu'ici seul `0x73` est prouvé natif) ; l'origine de D6 (0x06) ; et D2 (gating).
</content>
</invoke>
