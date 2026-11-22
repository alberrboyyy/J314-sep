# sbio (EP 0x08) — la micro-séquence de MATCH : ordre, formats OOL, gating keybag, chemin de l'image

2026-11-22 — reverseur (Opus 4.8). But : compléter le **protocole** de la passe de match Touch ID
(doigt posé → verdict oui/non), pour préparer le script final de match natif (après enrôlement).
**Protocole / séquence / format uniquement. Aucune image, aucun gabarit, aucune clé, aucune donnée biométrique.**

Binaire : `macos/kernel.macho` (fileset macOS 13.5), bundle `com.apple.driver.AppleMesaSEPDriver`.
Outils : `analysis/kext/ksyms.py`, `analysis/kext/kdis.py func` (venv capstone du scratchpad). Aucun code Apple recopié.

**Convention de statut.** `VU` = lu directement dans le désassemblage de cette session (adresse donnée).
`hypothèse` = interprété. Tout est `source: kext`. **Rien ici n'est `vérifié`** au sens matériel (pas d'écriture SEP).
Complète (sans les modifier) `kext_sepmanager.md` §12c/§12d/§13c, `messages.md` §SBIO, `sbio_sequence.md` §3.

Ne remplace pas le verdict 0x09 déjà `vérifié` (c6/c8/c11) : ce doc ajoute le **cadre** autour de ce verdict.

---

## 0. Fonctions désassemblées (adresses VA, VU)

| fonction (symbole) | VA | rôle |
|---|---|---|
| `AppleMesaSEPDriver::asyncCaptureHandler(IOTimerEventSource*)` | `0x9778d90` | boucle de capture/tentative : émet 0x23, 0x06, 0x65, 0x07, 0x22 |
| `AppleMesaSEPDriver::handleMatch(bool, IOMesaCaptureData*, bool, bool*, uchar)` | `0x9794da4` | la passe de match : émet 0x8001 (capture), …, **0x09 (verdict)** |
| `AppleMesaSEPDriver::commandStartMatch(match_init_v1_t*, ulong)` | `0x9783c0c` | **armement du match** : émet **0x27** ou **0x25** (porte l'acmContext) |
| `AppleMesaSEPDriver::checkAutoMatchConditions(bool)` | `0x978509c` | **le GATE amont** : décide si une tentative démarre |
| `AppleMesaSEPDriver::checkAutoMatchLockoutConditions()` | `0x9784818` | gate de verrouillage (lockout) : produit un « noMatchReason » |
| `AppleMesaSEPDriver::handleEnrollment(bool, IOMesaCaptureData*, bool*)` | `0x9794468` | passe d'enrôlement (émet 0x08) — hors scope, cité pour contraste |
| `AppleMesaSEPDriver::retryMatchAfterHomeButtonPress(bool*, sbio_data*)` | `0x9796708` | reprise (émet 0x74/0x75) |

Primitive d'envoi : appel **virtuel** `sepTransact(opcode, in, inLen, out, outLen, bool, uint)` via le slot vtable
**`+0x9e0`** (motif `mov x17,#0x9e0 ; add x16,x16,x17 ; ldr x8,[x16] ; … ; mov w1,#<opcode> ; blraa`). VU sur tous les sites ci-dessous.

---

## 1. Ordre de la passe de match — ce qui est VU dans le binaire

### 1.1 Armement : `commandStartMatch` → 0x27 **ou** 0x25 (VU)

`commandStartMatch(match_init_v1_t* matchInit, ulong len)` choisit, selon `_matchFlags` (`this+0x1d70`), **une** des deux
commandes d'armement vers le SEP (les deux sont des `sepTransact` slot +0x9e0, entrée pointée par `matchInit`, `w6=1 w7=0`) :

| site VA | opcode (w1) | inLen (w3) | tampon in | branche (bit de `_matchFlags`) |
|---|---|---|---|---|
| `0x9783e08` | **0x27** | **0x3c (60 o)** | `matchInit+8` (x22) | pris quand bit 1 posé |
| `0x9783f08` | **0x25** | **0x44 (68 o)** | `matchInit` (x20) | pris quand bit 3/4 posé |

- **VU** : les immédiats `mov w1,#0x27`/`mov w3,#0x3c` et `mov w1,#0x25`/`mov w3,#0x44`. Recoupe `messages.md` §Écarts
  (« 0x27/0x25 commandStartMatch entrée 0x3c/0x44 o »). Ce sont les 0x27/0x25 **absents de C11** (tentative pilotée
  autrement en trace) mais bien présents dans le code.
- **`match_init_v1_t` porte un `acmContext`** (VU — assert `matchInit && matchInit->data.acmContext.length &&
  (matchInit->data.acmContext.le…`). Le code recopie un contexte ACM de longueur **0x10** (copie `q0`, chemin rapide) ou
  **jusqu'à 0x20 o** (`memcpy`, chemin `w2 ∈ [1,0x20]`) depuis `matchInit+0x24` (branche 0x27) ou `matchInit+0x14`
  (branche 0x25), vers `this+0x1d8c`/`this+0x1db0`. `acmContext` = **jeton d'autorisation ACM** (Access Control Manager)
  fourni par la couche cliente — voir §3 (gating).
- **Drapeaux de match** (VU — chaînes d'assert) : `kMatchingFlagMatchForUnlock`, `kMatchingFlagMatchForCredentialSet`,
  et les masques `_matchFlags & {0x01, 0x02, 0x08, 0x10, 0x80}`. Combinaisons invalides rejetées
  (« Invalid match flag combination … »). Interprétation (hypothèse) : le match est typé (déverrouillage vs credential-set),
  ce qui détermine quelle commande d'armement (0x27/0x25) et quel contenu d'acmContext est transmis au SEP.

### 1.2 Capture d'image : `asyncCaptureHandler` → 0x23, 0x06, 0x65, 0x07, 0x22 (VU)

Sites `sepTransact` (slot +0x9e0) relevés **dans l'ordre du code** :

| site VA | opcode (w1) | inLen (w3) | tampon in | note (VU sauf mention) |
|---|---|---|---|---|
| `0x977948c` | **0x23** | **0 (x2=0, x3=0)** | — | 1re commande de la tentative, **sans charge** |
| `0x97794e0` | **0x06** | (variable) | buffer de params | paramètres de traitement d'image (`_lastImageProcessingParams`, 0xa7 o en trace = hypothèse) |
| `0x9779604` | **0x65** | **w3 = w0** (longueur **dynamique** retournée par un appel virtuel slot `+0x160`) | **x2 = pointeur image** (x26, issu de `getCaptureBuffer…`) | **l'image** : ptr + longueur passés **inline** (voir §4) |
| `0x9779688` | **0x07** | 0 | — | demande du résultat de traitement d'image (réponse 0xc0 o en trace) |
| `0x977a650` | **0x22** | 0 | — | `kEnableBgOpsUpdate` (fin de tentative) |
| `0x9779b04` | 0x75 | 0x21 (33 o) | — | chemin **retry** (reprise de capture) |
| `0x9779a4c` | 0x74 | w3=w0 | ptr | chemin **retry** (ré-émission d'image) |

→ **VU confirme** la sous-séquence fil `23 06 65 07 … 22` de `messages.md`/`sbio_sequence.md`. Le `0x65` (image) n'est **pas**
de longueur fixe dans le code : `w3` vient d'un appel virtuel (taille réelle de la capture) ; la valeur 0x7200 (= 12 × 0x980)
est l'observation de trace pour ce capteur, pas une constante codée.

### 1.3 Verdict : `handleMatch` → 0x8001 (capture) … → **0x09** (VU)

- `0x9795230` : `sepTransact(opcode=0x8001, inLen w3=0x46)` — opcode **à bit haut** (`0x8001` ; aussi vu en §12d),
  interprété (hypothèse) comme « relais capteur / capture d'image » interne à la passe.
- `0x9795a4c` : **`sepTransact(opcode=0x09, in=NULL (x2=0, x3=0), out = tampon pile (sp+0x60))`** — **VU**.
  C'est **la demande de verdict** : **charge d'entrée vide** (recoupe §13c « payload vide, total=0 »), la **réponse**
  (le `match_info_t`, 0xca2 o) est écrite dans un tampon de sortie. La valeur de retour de la transaction est comparée à
  **`0x56`** (`cmp w22,#0x56`) et traitée à part — c'est le « code d'erreur 0x56 » déjà noté en §K3. VU.
- Avant/après le 0x09, `handleMatch` lit des sous-résultats (§12d : rafale `0x0b–0x12`, `0x14`, `0x1e`, puis finalisation
  `0x1b/0x1c/0x22`). Ces opcodes-là ne sont pas tous en `mov w1,#imm` (opcode chargé par registre) : répertoire `source: kext`
  de §12d, non ré-extrait ici. **Ordre sûr du cœur** : armer → capturer (`0x8001`) → sous-résultats → **`0x09` verdict** → finaliser.

**Ordre global de la passe de match (consolidé, VU pour les opcodes cités, hypothèse pour l'ordre fin) :**
```
[GATE AP]  → commandStartMatch : 0x27 | 0x25 (acmContext)
asyncCaptureHandler :  0x23 → 0x06 → 0x65(image) → 0x07
handleMatch :          0x8001(capture) → … (0x0b–0x12,0x14,0x1e) → 0x09(VERDICT) → 0x1b/0x1c/0x22
(reprise éventuelle :  0x74 / 0x75)
```
Recoupe la sous-séquence fil `23 06 65 07 [1e] 09 1f 22 70 03 21` observée en C11 (`sbio_sequence.md` §3).

---

## 2. Formats / OOL (tailles et champs d'en-tête — PAS le contenu)

Toutes les commandes passent par le cadre fil **`gt_packet_t`** déjà `vérifié` (§13/§13b) : message mailbox `type=0xfc`,
charge en buffer OOL, en-tête **0x1c o** (`+0x00 kind=1`, `+0x04 total`, `+0x08 offset`, `+0x0c flags`, `+0x14 opcode`,
`+0x18 longueur fragment`, `+0x1c payload`). Le présent doc ne décrit que les **tailles d'entrée** vues côté kext :

| opcode | inLen (VU) | sortie (kext/trace) | rôle |
|---|---|---|---|
| 0x27 | 0x3c (60 o) | — | armement match (variante bit 1) ; payload = début de `match_init_v1_t` à +8 + acmContext |
| 0x25 | 0x44 (68 o) | — | armement match (variante bit 3/4) ; payload = `match_init_v1_t` + acmContext |
| 0x23 | 0 | — | début de tentative |
| 0x06 | variable (0xa7 o en trace) | — | `_lastImageProcessingParams` (origine non lue = D6) |
| 0x65 | **dynamique** (0x7200 o en trace, 12 × 0x980) | — | **image** (voir §4) |
| 0x07 | 0 | 0xc0 o (`image_processing_result_full`) | résultat image ; champs nommés dans `messages.md` §0x07 |
| 0x8001 | 0x46 (70 o) | — | capture/relais interne (bit haut) |
| 0x09 | **0 (vide)** | **0xca2 o (`match_info_t`)** | **verdict** (`+0x00`=0x1f5/0xffffffff — déjà `vérifié` §13c) |
| 0x75 | 0x21 (33 o) | — | reprise |

- **acmContext** (VU) : longueur **≤ 0x20 o** ; chemin rapide pour **0x10 o** (`ldr q0`/`str q0`). C'est un **jeton
  d'autorisation** sérialisé, pas une donnée biométrique — transmis tel quel au SEP dans le payload de 0x27/0x25.
- Rien dans ce doc ne contient ni n'extrait d'octet d'image, de gabarit ou de clé.

---

## 3. D2 — gating keybag : ce que dit le kext (le SEP refuse-t-il 0x09 verrouillé ?)

**Verdict (VU) : le gating de match est fait CÔTÉ AP (kext), AVANT tout envoi au SEP.** Le kext ne tente ni l'armement
(0x27/0x25) ni le verdict (0x09) quand l'utilisateur n'est pas « autorisé au déverrouillage ».

`checkAutoMatchConditions(bool touchIDButtonPressed)` (`0x978509c`) est la **porte**. Elle appelle (VU, symboles résolus
par `ksyms --at`) :

| appel (VA) | symbole (VU) | effet si non satisfait |
|---|---|---|
| `0xa43beec` | `IOBiometricService::isEnabledForUnlock(CachedUserContext*)` | **bail-out** (`cbz w0, fin`) — pas de match |
| `0xa43c160` | `IOBiometricService::isAtLeastOneLocked()` | bail-out |
| `0xa43c280` | `IOBiometricService::isAtLeastOneWithoutPasscodeLockout()` | bail-out |
| `0xa43c4c0` | `IOBiometricService::isAtLeastOneWithTemplates()` | bail-out (pas de gabarit → pas de match) |
| `0xa43ad70` | `IOBiometricService::lockCommandAccess()` | sérialise l'accès commande |

Et `checkAutoMatchLockoutConditions()` (`0x9784818`) lit directement **`CachedUserContext::getLockState()`** (`0xa439d64`)
— le **u16 lockState** des notifications TAG 0x01 (§6) — et teste ses **bits** (`tbz/tbnz` sur bits 0,1,2,3,4) plus
`isAtLeastOneWithoutPasscodeLockout` / `isAtLeastOneWithoutBioLockout` (`0xa43c3a0`). Selon l'état, elle fabrique un
**`noMatchReason`** (codes VU : `0x51`, `0x52`, `0x53`, `0x5c`) et le **renvoie au client** via
`messageMesaClients(0xe3ff8001, …)` (`0x97928d8`) — **sans aucun `sepTransact`**. De même `checkAutoMatchConditions` émet
des raisons client `0x4b/0x4f/0x50` quand une condition manque.

**Conséquence pour D2 (honnête) :**
- **Côté AP, prouvé (VU)** : quand le keybag est verrouillé avec blocage bio (lockState 0x0015 au boot, §6),
  `isEnabledForUnlock` est faux → le kext **n'arme pas** le match et **n'envoie jamais 0x09** ; il répond localement au
  client « noMatch (raison …) ». Donc **macOS s'abstient** : l'absence de 0x09 en session verrouillée est **explicable
  entièrement côté AP**.
- **Non déterminé par le kext** : on **ne peut pas** savoir, depuis le binaire, si le **SEP** refuserait *aussi* un 0x09
  injecté sous blocage bio. Le kext ne contient **aucun** chemin où 0x09 part en état verrouillé → il n'y a rien à lire
  côté SEP-refus. **Indice protocolaire (hypothèse)** : l'armement 0x27/0x25 transporte un **acmContext** (jeton
  d'autorisation issu de la couche keystore/ACM). Si le SEP valide ce jeton, alors l'autorisation keybag serait **couplée
  au protocole lui-même** (le SEP exigerait un acmContext valide), pas seulement à l'abstention AP. Cela reste une
  hypothèse : seule une écriture EP 0x12 (keybag) + EP 0x08 (ligne rouge Albert) trancherait.

**Pour le script de match natif** : reproduire le gate AP (ne lancer la passe que lockState « bio autorisée »), **et**
prévoir que le SEP puisse exiger un acmContext valide dans 0x27/0x25 — à obtenir de l'EP 0x12, non rejouable à l'aveugle.

---

## 4. Par où passe le gros transfert d'image (DMA SIO vs FIFO)

Deux segments distincts, à ne pas confondre :

1. **Capteur → AP (SPI)** : l'image brute est lue sur le bus SPI du capteur Touch ID par `AppleMesa::readSensorData`
   (trames `80 13 …`, `messages.md` §Capteur). **macOS fait ces transferts par DMA via le coprocesseur SIO** (canaux
   DMA 0x18/0x19 d'après m1n1 sur M1 ; **non vérifié sur ce M1 Max/t6001** — cf. bémol `mesa_spi_proxy` / `messages.md`
   point 1). C'est **là** qu'est le « gros transfert » matériel (≈ 0x7200 o lus du capteur).

2. **AP → SEP (mailbox EP 0x08)** : l'image lue est recopiée (OSData/IOBufferMemoryDescriptor, `messages.md` §Chemin
   jusqu'à 0x65) puis soumise au SEP par **`sepTransact(opcode=0x65, x2=ptr, w3=longueur)`** — **VU** (site `0x9779604`) :
   **passage inline par le cadre OOL `gt_packet_t`**, pas par un `IOMemoryDescriptor`/DMA dédié. La primitive
   `sepTransactToIOMD` (slot 315) existe mais **n'est pas** utilisée pour le 0x65 ici (le site 0x65 est le slot +0x9e0 =
   `sepTransact` classique). Comme 0x7200 o dépasse la taille d'un buffer OOL, le transfert est **fragmenté** par la couche
   GenericTransfer (champs `offset`/`total`/`fragment` du `gt_packet_t`) → c'est le `0xfc`/`0xfd` observé en trace
   (180 tranches de 0x980, §13b/§messages.md). **Aucune DMA spécifique SEP** côté AP→SEP : c'est la mémoire partagée
   SEP ordinaire.

**Donc, pour Linux** : le gros transfert à gérer en DMA est **SPI (capteur→AP)** ; l'envoi au SEP réutilise le mécanisme
OOL/`0xfc` déjà cartographié (fragmentation automatique). Ouvert : le mode **PIO/FIFO** du contrôleur `spi-apple`
suffit-il pour ≈0x7200 o/capture (fréquence, taille FIFO non lues) — non tranché (`messages.md` point 1).

---

## 5. Points ouverts (honnête)

- **D2 non tranché matériellement** : le kext prouve l'abstention AP, pas un refus SEP. L'acmContext de 0x27/0x25 suggère
  un couplage protocolaire (SEP valide un jeton d'autorisation) — **hypothèse**, trancheable seulement par écriture (Albert).
- **D6** : l'origine du payload 0x06 (`_lastImageProcessingParams`, 0xa7 o) reste non lue (où/comment il est rempli).
- **Ordre fin de `handleMatch`** (opcodes 0x0b–0x12/0x14/0x1e/0x1b/0x1c) : répertoire `source: kext` (§12d), opcodes
  chargés par registre, non ré-extraits un par un ici ; seul le **0x09 (verdict, vide)** et le **0x8001 (capture, 0x46)**
  sont VU cette session avec leur taille.
- **Détail du `match_info_t`** (~3200 o après `+0x00/+0x04`) : non décodé, et **à ne pas** décoder (métadonnées d'image).
- **Transport SPI sur t6001** : canaux DMA SIO et faisabilité PIO non vérifiés sur ce Mac (hérités de m1n1/M1).
- **acmContext** : format interne non décodé (jeton d'autorisation ; hors scope biométrie, mais aussi hors besoin pour la
  carte d'opcodes). Longueur ≤ 0x20 o (VU).
</content>
</invoke>
