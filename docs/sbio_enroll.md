# sbio (EP 0x08) — séquence d'ENRÔLEMENT : protocole de messages (source: kext)

2026-11-22 — reverseur. But : extraire, pour préparer une future session humaine (doigt à enrôler nativement
sous Linux), la **séquence d'enrôlement** côté AP et ses **formats de message** — sans aucune donnée biométrique.
Les gabarits macOS ne se transfèrent pas : un enrôlement natif devra rejouer CE protocole.

Binaire : `macos/kernel.macho` (fileset, macOS 13.5). Kext : `com.apple.driver.AppleMesaSEPDriver`.
Outils : `analysis/kext/ksyms.py`, `analysis/kext/kdis.py` (func / callers / strrefs), venv capstone.

**Portée : PROTOCOLE / SÉQUENCE / FORMAT uniquement.** Aucun gabarit, aucune image, aucune clé extraite.
Les champs « blob » (données qui construisent le gabarit) sont nommés + taillés mais **jamais caractérisés en contenu**.

**Convention de statut :**
- **VU** = lu directement dans le désassemblage (instruction, immédiat, chaîne, offset).
- **hypothèse** = interprétation du rôle à partir des noms de symboles / du contexte.
- Tout est **`source: kext`** (lecture de binaire hors-ligne). Rien n'est `vérifié` (aucune expérience matérielle).

Rappel cadre fil (kext §13, VU/vérifié ailleurs) : chaque `sepTransact(opcode, in, inLen, out, outLen, …)` =
**une transaction mailbox EP 0x08 `type=0xfc`** ; l'**opcode** va à l'offset **+0x14** du `gt_packet_t` dans le
buffer OOL, le payload à **+0x1c**. Les opcodes ci-dessous sont donc des opcodes `gt_packet_t`.

---

## 1. Symboles de l'enrôlement (VU — `ksyms`)

| symbole (démanglé) | VA | rôle (hypothèse d'après nom) |
|---|---|---|
| `commandStartEnroll(enroll_indata_v2_t*)` | 0x97838b0 | démarre l'enrôlement (commande userspace) |
| `commandStopEnroll()` | 0x9784db4 | arrête/annule l'enrôlement |
| `handleEnrollment(bool, IOMesaCaptureData*, bool*)` | 0x9794468 | traite une capture dans l'enrôlement en cours |
| `sendEnrollProgresWithEnrollInfo(uint8, enrollment_info_v2_t*)` | 0x9792b24 | notifie la progression à l'userspace |
| `sendEnrollResult(enroll_result_v2*)` | 0x9792c9c | notifie le résultat final à l'userspace |
| `checkEnrollmentFail()` / `enrollmentTimeoutHandler` / `enrollmentForceFailHandler` | — | garde-fous (timeout / échec forcé) |

Structures nommées par les symboles (VU, noms de types Apple) : **`enroll_indata_v2_t`** (entrée du start),
**`enrollment_info_t` / `enrollment_info_v2_t`** (retour SEP de progression), **`enroll_result_v2`** (résultat final),
**`IOMesaCaptureData`** (une capture d'image côté AP).

---

## 2. Qui déclenche quoi (VU — `callers`)

- `commandStartEnroll` est appelé **uniquement** par `performSpecificCommandGated` (0x977eecc) :
  l'userspace (biometrickitd) envoie une **commande `bm_cmd_t`** (cf. kext §12b) qui déclenche le start. **VU.**
- `handleEnrollment` est appelé par **deux** sites **VU** :
  - `asyncCaptureHandler` (0x9778d90) avec `x2 = captureData` → **une image vient d'être capturée** ;
  - `postFingerOffHandler` (0x977ae8c) avec `w1=0, x2=0, x3=0` → **doigt retiré**, pas d'image (fin de pose).

Donc l'acquisition de l'image (le `0x23 0x06 0x65 0x07` déjà documenté pour le match, sbio_sequence §3) se fait
**en amont** dans `asyncCaptureHandler` ; `handleEnrollment` est le **post-traitement** qui replie l'image dans le
gabarit en cours de construction dans le SEP. **VU (sites d'appel) + hypothèse (rôle).**

---

## 3. Séquence d'enrôlement — vue d'ensemble (VU pour les opcodes, hypothèse pour l'orchestration)

```
  userspace (bm_cmd_t)                         SEP (EP 0x08, gt_packet_t)
  ───────────────────                          ─────────────────────────
  START ───► commandStartEnroll ───────────────► sepTransact(0x03, enroll_indata_v2_t, inLen=0x44)   [VU]
                                                   (met _commandMode = kCommandModeEnroll = 3)        [VU]

  ┌── BOUCLE de poses (répétée, N piloté par le SEP) ──────────────────────────────┐
  │  doigt posé → capture (asyncCaptureHandler : 0x23 0x06 0x65 0x07, cf. §sbio_seq) │  [capture = doigt]
  │       │                                                                          │
  │       ▼ handleEnrollment(imagePassedImgQuality, captureData, &imageConsumed)     │
  │          sepTransact(0x1e, in=0)                      étape de pré-traitement    │  [VU opcode 0x1e]
  │          sepTransact(0x08, in=0, out=enrollment_info_t[0xc98])   « plie l'image »│  [VU opcode 0x08]
  │          parse enrollment_info_t → progress / error / complete                   │  [VU parse]
  │          sendEnrollProgresWithEnrollInfo(...) ──────────► userspace (barre)       │  [VU]
  │  doigt retiré → postFingerOffHandler → handleEnrollment(0,0,0) (pas d'image)     │
  └── jusqu'à enrollment_info_t.complete (offset +0xbfe) ≠ 0 ────────────────────────┘

  COMPLETE ─► sendEnrollResult(enroll_result_v2[20 o]) ────► userspace (identité créée) [VU]
  STOP/annulation ─► commandStopEnroll (_commandMode → 1, statistiques)                 [VU]
```

**Opcodes SEP réellement émis par l'enrôlement (VU, via le slot vtable `sepTransact` `+0x9e0`, discriminant PAC
`#0x3d75`) : `0x03`, `0x1e`, `0x08`.** C'est tout pour le cœur sbio. L'acquisition d'image (`0x23/0x06/0x65/0x07`)
est partagée avec le match et déjà documentée (sbio_sequence §3).

> **Correction d'une lecture antérieure (kext §12d).** Les appels `mov w1,#0xe3ff8001 … bl 0x97928d8` ne sont **pas**
> des opcodes SEP : `0x97928d8` est un point de **trace kdebug** (`0xe3ff8001` = code de classe kdebug, `0x2b97` =
> sous-classe ; VU). De même `mov w1,#0x1f … bl 0x9792388` = `sendStatisticsInt` (message de **statistiques** à
> l'userspace, type client `0xe3ff8004`), **pas** un opcode SEP `0x1f`. L'ancienne table « 0x8001 ×3 / 0x1f » du
> flot enroll était donc du bruit d'instrumentation. **Les seuls opcodes fil de l'enroll sont 0x03, 0x1e, 0x08.**

---

## 4. `commandStartEnroll` — opcode 0x03 (VU, décompilé 0x97838b0)

- **Gating local (VU)** : asserts `enrollInit != NULL`, `!_mesaDisabled`, `isMesaDeviceAvailable()`.
  → l'enrôlement exige le device Mesa **présent et non désactivé** avant tout envoi.
- Lit le **1er u32 de `enroll_indata_v2_t`** (`ldr w8,[x20]`), stocke `w8 & 1` dans un drapeau d'état (objet `+0x1dd4`,
  et `w8` entier en `+0x1d6c`). **VU.** Interprétation : bit 0 = un mode/flag d'enrôlement (hypothèse).
- **Envoi SEP (VU)** :
  `sepTransact(opcode=0x03, in = enroll_indata_v2_t, inLen = 0x44, out=0, outLen=0, flag=1, 0)`.
  → **`enroll_indata_v2_t` fait 0x44 = 68 octets** et est transmis **tel quel** au SEP comme payload du `gt_packet_t`
  opcode 0x03. **VU (taille + opcode).** Contenu des 68 octets : **non caractérisé** (paramètres d'init d'enrôlement ;
  l'AP doit les fournir — origine à retrouver côté userspace/biometrickitd, point ouvert §8).
- Après succès : `_commandMode = kCommandModeEnroll (=3)` (VU : `setCommandMode(3)` = 0xa43aeac w1=3), puis armement
  interne (0x9784ba0). **VU.**
- Les asserts échoués renvoient des codes d'erreur `0xe0000...` (VU, non détaillés).

**Ce que l'AP doit fournir : le blob `enroll_indata_v2_t` de 68 o.** **Ce qui reste au SEP :** tout l'état d'enrôlement.

---

## 5. `handleEnrollment` — opcodes 0x1e puis 0x08, et le format `enrollment_info_t` (VU, 0x9794468)

Signature (VU, d'après chaîne de log `imagePassedImgQuality:%d, imageNumber:%u, imageConsumed:%p`) :
`handleEnrollment(bool imagePassedImgQuality, IOMesaCaptureData* capture, bool* imageConsumed)`.

Flot principal (VU) :
1. assert `getCommandMode() == kCommandModeEnroll` (VU) — l'enroll doit être actif.
2. `sepTransact(opcode=0x1e, in=0, inLen=0)` — étape de pré-traitement (hypothèse : init du traitement d'image,
   analogue au `0x1e` du flot de match). **VU opcode.**
3. `sepTransact(opcode=0x08, in=0, inLen=0, out=&buf, …)` — demande au SEP de **traiter la dernière image capturée**
   et renvoie une structure **`enrollment_info_t`**. **VU opcode + sortie lue.**
4. Vérifie la taille de sortie : **`size == 0xc98` (= 3224 o = `sizeof(enrollment_info_t)`)** (VU, assert
   `enrollmentInfoData.size == sizeof(enrollment_info_t)`). Sinon → erreur.
5. Parse `enrollment_info_t` (offsets VU ; rôles hypothèse) :

| offset | taille | lecture (VU) | rôle (hypothèse) |
|---|---|---|---|
| +0x00 | u16 | `ldrh [p]` ; si 0 on teste +0x02 | état / type de nœud |
| +0x02 | u16 | si ≠ 0 → log `Enrollment error %d` | **code d'erreur** (0 = OK) |
| +0x04 | u16 | log `progress` (= valeur +0x64) ; octet bas → `sendEnrollProgresWithEnrollInfo` | **progression de la pose** |
| +0x06 | u32 | si ≠ 0 → recopie du blob | drapeau « image consommée / données présentes » |
| +0x0a | 0xbf4 o | `memcpy(objet+0x3b8, p+0x0a, 0xbf4)` | **blob de construction du gabarit** (nœuds) — contenu NON caractérisé |
| +0xbfe | u32 | si ≠ 0 → log `Enrollment complete` | **drapeau FIN d'enrôlement** |
| +0xc02 | 16 o | copié dans `enroll_result_v2` | **identifiant d'identité** (référence, pas le gabarit) |
| +0xc12 | u32 | copié dans `enroll_result_v2` | champ de résultat |
| +0xc60 | 16 o + | copiés dans `enroll_result_v2` | métadonnées de résultat (non caractérisées) |

6. **Progression** (erreur=0, pas encore complet) : `sendEnrollProgresWithEnrollInfo(progress=[+0x04], info=p)` →
   notification userspace. On **reste dans la boucle** (attendre la pose suivante). **VU.**
7. **Fin** (`+0xbfe ≠ 0`) : log `Enrollment complete`, enregistre l'identité (`0xa43b438` w1=`[+0xc02...]`),
   `sendEnrollProgresWithEnrollInfo` final, construit `enroll_result_v2` (20 o : identité 16 o + u32) et
   `sendEnrollResult(result)`. **VU.**
8. Les appels vtable `+0xa88` (slot 337) et `+0xab0` (slot 342), pris **seulement** sur une branche « validNodePlacement »
   (première pose, condition `imageNumber`), sont des **méthodes de sérialisation de gabarit** (voisines de
   `getPreImage`/`prepareSerialisedTemplates`/`getSerialisedTemplates`, kext §12 slots 338-340 — groupe « données
   biométriques, NE PAS sonder »). **Non détaillées** (hors protocole fil ; data biométrique). VU (présence), non caractérisé.

**Ce que l'AP fournit à l'étape 2-3 : rien de nouveau** (in=0) — l'image est déjà chez le SEP (capture amont).
**Ce qui reste au SEP :** la construction et le stockage du gabarit ; l'AP ne reçoit que **progression + code d'erreur
+ un identifiant d'identité** (métadonnées), jamais le gabarit.

---

## 6. `commandStopEnroll` (VU, 0x9784db4) et garde-fous

- assert `getCommandMode() == kCommandModeEnroll`, puis `_commandMode = 1` (VU : `setCommandMode(1)`).
- appelle une méthode vtable `+0x238` sur l'objet d'état capteur (`[this+0x2bb8]`) — arrêt côté état (hypothèse),
  `0x977de0c(0)`, et `sendStatisticsInt(0x1f, durée)`. **Aucun opcode SEP dédié émis** (VU) — l'arrêt est local + stats.
- `enrollmentTimeoutHandler` / `enrollmentForceFailHandler` / `checkEnrollmentFail` : minuteries d'abandon
  (une pose trop longue / enrôlement qui échoue). Garde-fous, pas d'opcode fil nouveau. **VU (existence).**

---

## 7. Nombre de poses, feedback, gating (synthèse)

- **Nombre de poses : NON fixé dans le kext (VU).** Le kext **boucle** (capture → 0x1e → 0x08 → progress) et ne
  s'arrête **que** quand `enrollment_info_t.+0xbfe` (drapeau « complete ») passe à ≠ 0. C'est donc **le SEP/firmware
  capteur qui décide** du nombre de poses et de la fin (le classique « poser/relever ~10-15× » n'est pas un compteur AP).
  → Côté Linux : enrôler = **boucler les captures jusqu'à ce que le SEP annonce `complete`**, pas un compte fixe. **VU.**
- **Feedback de progression** = champ `+0x04` de `enrollment_info_t`, relayé à l'userspace par
  `sendEnrollProgresWithEnrollInfo` (type client `0xe3ff8003`). `+0x02` = code d'erreur par pose (p.ex. « image
  rejetée / salissure capteur » — logs `Dirt on sensor detected`). **VU.**
- **Gating local (VU)** : device Mesa présent + non désactivé + `_commandMode == kCommandModeEnroll`.
- **Gating keybag / mot de passe (hypothèse, NON tranché)** : l'enrôlement crée et scelle un gabarit dans le
  catacomb du SEP (sbio_sequence §1.3 : `0x6d LoadCatacomb`), ce qui exige l'état utilisateur déverrouillé. Au boot
  `lockState=0x0015` (keybag verrouillé + blocage bio). **Inconnu depuis le binaire seul** : le SEP refuse-t-il
  `0x08`/la finalisation tant que le keybag est verrouillé, ou est-ce seulement macOS qui s'abstient ? Même question
  ouverte que D2 (sbio_sequence §3, kext §15.6). **Non tranchable sans écriture EP 0x12 (ligne rouge Albert).**

---

## 8. Points ouverts (honnête)

1. **Contenu des 68 octets de `enroll_indata_v2_t`** (opcode 0x03) : l'AP doit les fournir, origine non lue (venir de
   biometrickitd / IOBiometricFamily côté userspace). À extraire si on veut émettre un start natif correct.
2. **`imageNumber` / branche validNodePlacement** : la condition exacte qui déclenche les méthodes de sérialisation
   de gabarit (slots 337/342) sur la 1re pose n'est pas entièrement reversée (et touche aux données biométriques —
   non prioritaire, hors protocole fil).
3. **Gating keybag (§7)** : le SEP accepte-t-il l'enroll sous keybag verrouillé ? Tranchable seulement par expérience
   (écriture EP 0x12 → Albert).
4. **Acquisition d'image pour l'enroll** : supposée identique au match (`0x23 0x06 0x65 0x07`) car `handleEnrollment`
   est appelé depuis `asyncCaptureHandler` (VU), mais la sous-séquence de capture **en mode enroll** n'a pas été
   observée en trace (les captures disponibles sont des matchs). À confirmer par une trace d'enrôlement.
5. **Ordre strict / payloads de 0x1e et 0x08** : opcodes VU, mais toutes les branches de `handleEnrollment` ne sont
   pas reversées ; l'ordre donné est le chemin principal.

---

## 9. Ce qu'il faut un doigt / une session humaine

- **Enrôler = pur événement matériel répété** : chaque pose produit une image réelle sur le capteur SPI
  (impossible à simuler côté AP — c'est une empreinte vivante). Le SEP ne déclare `complete` qu'après assez de poses
  de qualité suffisante. → **session humaine obligatoire** (doigt réel, plusieurs poses, retraits entre poses).
- **Prérequis amont (hors sbio)** : sbio doit être armé = SEPOS booté + **xART frais scellé** (route native EP 0x13,
  = écriture SEP, Albert). Sans ça, la boucle capture/enroll n'est pas atteignable.
- **Préparation à inscrire dans `docs/hypotheses.md` (« EXPÉRIENCE HUMAINE »), le jour venu :** start natif
  (opcode 0x03 + les 68 o `enroll_indata_v2_t` — point ouvert §8.1), puis boucle {capture 0x23/0x06/0x65/0x07 →
  0x1e → 0x08 → lire `enrollment_info_t` → feedback} jusqu'à `+0xbfe=complete`, en **fail-closed** sur tout opcode ou
  retour non prévu. Trancher le gating keybag (§7) **avant** d'espérer une finalisation.

---

*Rédigé par le reverseur, 2026-11-22. Aucune donnée biométrique/clé/gabarit extraite. Tout `source: kext`
(lecture hors-ligne de `macos/kernel.macho`). VU = lu dans le binaire ; hypothèse = interprétation de rôle.
Aucune expérience matérielle → rien n'est `vérifié`.*
