# sbio — performKeyExchange (0x15/0x16) : le mécanisme de relais AP ↔ capteur (phase 2)

2026-11-22 — reverseur. But : comprendre **comment l'AP relaie** le dialogue chiffré SEP ↔ capteur qui a lieu
pendant `performKeyExchange` (commande sbio 0x15, réponse 0x16), pour pouvoir coder le relais côté Linux (sbio4).
**Protocole / transport uniquement. Aucune clé, aucun secret extrait.**

Sources :
- **kext** = désassemblage de `macos/kernel.macho` (fileset macOS 13.5). Deux bundles concernés :
  - `com.apple.driver.AppleMesaSEPDriver` = le **côté SEP** (EP 0x08, `sepTransact`).
  - `com.apple.driver.AppleBiometricSensor` = le **côté capteur** (classes `AppleMesa`, `AppleSPIBiometricSensor` ;
    pilote SPI du capteur Touch ID sur le bus de l'AP).
- **trace** = `traces/20261108-032454_c12-boot-ho` (`sep.log` + `sep.log.ool/*_08_A.bin`) et `docs/sensor_hw.md`
  (dialogue SPI AP↔capteur, C17-C20).

**Statut : `source: kext` (VU dans le binaire) + recoupements `trace`. Rien n'est `vérifié` (statut matériel).**
Marquage par fait : **VU** = lu dans le désassemblage/la trace ; **hypothèse** = interprété.

---

## 0. Réponse courte à la question clé

**L'AP est un PUR RELAIS D'OCTETS. Il ne détient ni ne génère aucune clé, et ne fait aucune crypto** pour la session
SEP↔capteur. (VU, confiance élevée.)

- Le pilote AP (côté capteur) ne contient **aucune primitive crypto** dans son propre code : pas d'AES, pas de HMAC,
  pas d'ECDH/Diffie-Hellman, pas de RNG. Les symboles crypto du noyau (`ccsha*`, `AESSubBytesWordTable`,
  `AppleS8000AESAccelerator`, `ccrng*`) sont **dans d'autres bundles**, jamais appelés par `AppleBiometricSensor`
  (son `__text` est en `0x91b…`–`0x91d…` ; aucune de ses fonctions de relais ne branche vers le crypto). (VU.)
- Pour `performKeyExchange`, l'AP se contente de : recevoir du SEP un blob opaque (réponse sbio 0x15, 40 octets) →
  l'habiller d'un en-tête SPI + CRC → l'envoyer au capteur en DMA → lire la réponse SPI → la renvoyer au SEP
  (sbio 0x16, 40 octets). (VU.)
- Les seules « transformations » faites par l'AP sont du **transport** : trame SPI `80 <cmd> <len>…`, CRC16
  (`AppleMesa::crc16ansi`, intégrité — pas un secret), et réservation d'emplacements de tampon. **Aucune donnée
  n'est déchiffrée ni signée côté AP.** (VU.)

**Conséquence pour le driver Linux** : ce relais est **faisable** sans jamais connaître de secret. Le mur
« performKeyExchange » n'est **pas** un mur crypto ; c'est un mur de **transport en lockstep** (capteur vivant +
SPI + relais exact des octets). Le secret de session est négocié **de bout en bout entre le SEP et le capteur** ;
l'AP ne le voit jamais.

---

## 1. Les deux côtés et leur point de jonction (VU)

| rôle | classe / bundle | fonction clé | adresse VA |
|---|---|---|---|
| côté SEP (EP 0x08) | `AppleMesaSEPDriver` | `performKeyExchange(uint sessionType)` | `0xfffffe000978a6b0` |
| côté capteur (SPI) | `AppleMesa` | `SessionKeyExchange(IOService*, uchar* in, ulong inLen, uchar* out, ulong outLen)` | `0xfffffe00091d269c` |
| côté capteur (gate) | `AppleMesa` | `SessionKeyExchangeGated(uchar* in, ulong inLen, uchar* out, ulong outLen)` | `0xfffffe00091d27a0` |
| dispatch commande | `AppleMesa` | `handleCMDSync(this, uint cmd, in, inLen, out)` | `0xfffffe00091c7a40` |
| transport SPI | `AppleSPIBiometricSensor` | `transferData(txMD, …, rxMD, …)` | `0xfffffe00091bb4e8` |

**Jonction (VU).** `AppleMesaSEPDriver` garde un pointeur vers le pilote capteur `AppleMesa` à l'offset **`+0x1e8`**
de son objet. Dans `performKeyExchange`, l'appel au capteur se fait par **méthode virtuelle `+0x8d0`** de cet objet
(`ldr x0,[x19,#0x1e8]` puis appel virtuel). La signature appelée
(`this, IOService*, uchar* in, ulong inLen=0x28, uchar* out, ulong outLen=0x28`) correspond exactement à
`AppleMesa::SessionKeyExchange`. (VU pour les registres/offsets ; **hypothèse (très probable)** pour l'égalité
« slot +0x8d0 == SessionKeyExchange », appuyée par la signature identique.)

---

## 2. performKeyExchange côté SEP — le relais pas à pas (VU, `0x978a6b0`)

Déroulé lu dans le désassemblage (registres et immédiats cités tels quels) :

1. **Log** `"%s <- sessionType:%d"` : l'entrée est un `sessionType` (u32), rangé à `sp+0x4c`. (VU.)
   En trace, 1re passe = `sessionType = 1` (cf. `sbio_sequence.md` L328). (trace)
2. **Garde d'état** : exige `[this+0x200] == 1` sinon sort en erreur. (VU) (= un état de session prêt ; hypothèse.)
3. **sbio 0x15 (AP→SEP)** : appel virtuel `sepTransact` (slot `+0x9e0`) avec
   `opcode w1 = 0x15`, `inLen w3 = 4` (le `sessionType`), sortie = `{ptr→sp+0x38, len→sp+0x40}`. (VU)
   → **Le SEP renvoie un blob** dont la longueur est **vérifiée == 0x28 (40 octets)** (`cmp x8,#0x28 ; b.ne …`).
   Si la taille n'est pas 40, branche d'erreur. (VU)
4. **Relais vers le capteur** : appel virtuel `[this+0x1e8]->+0x8d0` (= `AppleMesa::SessionKeyExchange`) avec
   `in = ptr du blob SEP` (40 o), `inLen = 0x28`, `out = sp+0x50`, `outLen = 0x28`. (VU)
   → L'AP envoie les 40 octets **opaques** du SEP au capteur, et récupère 40 octets de réponse.
5. **sbio 0x16 (AP→SEP)** : appel virtuel `sepTransact` (slot `+0x9e0`) avec
   `opcode w1 = 0x16`, `in = sp+0x50`, `inLen w3 = 0x28`. (VU)
   → **L'AP renvoie au SEP les 40 octets** de la réponse capteur.

**En une phrase (VU)** : `performKeyExchange` = `{ 0x15 : SEP→blob(40) } → { SPI : blob→capteur→réponse(40) } →
{ 0x16 : réponse(40)→SEP }`. L'AP ne lit, ne modifie, ne déchiffre jamais les 40 octets ; il les transporte.

**Recoupement trace (décisif).** `sbio_sequence.md`/§13b : 0x15 `len A = 4`, 0x16 `len A = 0x28`.
`sensor_hw.md` : « trame 0x72 après SEP 0x15 … puis SEP 0x16 ». La trame SPI `0x72` fait **0x2f = 47 octets** =
en-tête SPI 7 octets (`80 72 00 28 00 00 00`) **+ 40 octets de charge** = exactement le blob de 40 octets.
Le compte colle (trace + kext). (VU trace + VU kext.)

---

## 3. Côté capteur — SessionKeyExchange → SPI (VU)

- `AppleMesa::SessionKeyExchange` (`0x91d269c`) : simple enveloppe « command gate ». Elle exécute
  `SessionKeyExchangeGated` sur la work-loop (via `runAction`, objet gate à `[this+0xa8]`). Logs `entry`/`exit`.
  **Aucun traitement de données.** (VU)
- `AppleMesa::SessionKeyExchangeGated` (`0x91d27a0`) : (VU)
  1. `handleCMDSync(this, cmd = 0xe, in = blob, inLen, 0)` — **0xe = la commande interne « SessionKeyExchange »**
     (recoupé par la table de `_handleCMD`, string `"%s: SessionKeyExchange CMD"`). (VU)
  2. Si succès : **`memcpy(out, this+0x169, min(outLen, 0x28))`** — la réponse du capteur (40 octets) est lue
     depuis un tampon de l'objet `AppleMesa` à **`+0x169`** et recopiée vers le SEP. (VU)
  3. Si erreur : trois appels à une méthode virtuelle `+0x7b0` (reprise/reset capteur). (VU ; rôle = hypothèse.)
  - Le seul appel non trivial est `handleCMDSync` ; **aucun appel crypto**. (VU)
- `handleCMDSync` (`0x91c7a40`) : dispatcher synchrone (`"handleCMDSync entry: cmd=0x%x …"`). Valide le `cmd` par
  masque de bits, pose un contexte de commande (cmd à `+0x24`, param0/param1 = in/inLen à `+0x28`, callback
  `0x91c9bf8` à `+0x48`), puis exécute la machine d'état qui émet la trame SPI et attend la réponse via
  interruption. (VU pour la structure ; le détail machine d'état n'est pas entièrement reversé.)
- `AppleSPIBiometricSensor::transferData` (`0x91bb4e8`) : transport SPI pur. Logs
  `"txBufferLength=%u rxBufferLength=%u"`, `"Wrote: %5zuB"`, `" Read: %5zuB"`. Prend un tampon TX et un tampon RX
  (IOMemoryDescriptor), fait un transfert SPI (DMA, via le contrôleur). **Aucune crypto.** (VU)

---

## 4. Correspondance charge OOL (sbio) ↔ octets SPI (VU trace + kext)

Pour `performKeyExchange`, en lockstep (une étape SPI entre deux transactions sbio) :

| étape | sens | contenu | taille | source |
|---|---|---|---|---|
| sbio 0x15 (buffer A) | AP→SEP | `sessionType` (u32=1) | 4 o | VU (kext+trace) |
| réponse 0x15 (buffer B) | SEP→AP | **blob KX opaque** (vers capteur) | **40 o (0x28)** | VU (kext : `cmp #0x28`) |
| SPI émission | AP→capteur | en-tête `80 72 00 28 00 00 00` + blob 40 o | 47 o (0x2f) | VU (sensor_hw 0x72) |
| SPI réception | capteur→AP | enveloppe `80 d4 …` + charge | réponse type 0x72 | VU (sensor_hw 0x33) |
| — (extraction) | AP interne | charge utile lue depuis `AppleMesa+0x169` | **40 o (0x28)** | VU (kext : `memcpy 0x28`) |
| sbio 0x16 (buffer A) | AP→SEP | **réponse capteur opaque** | **40 o (0x28)** | VU (kext+trace) |

**Règle de relais (pour sbio4)** : à réception d'une transaction sbio `0x15` (le SEP veut lancer la session), lire
la charge de **40 octets** renvoyée par le SEP (buffer B), l'habiller de l'en-tête SPI `0x72` et l'émettre au
capteur, lire la réponse SPI, en extraire la charge (40 octets) et la rendre au SEP dans la transaction `0x16`.
**Les 40 octets ne doivent être ni interprétés ni modifiés.** (VU + hypothèse d'enveloppe côté SPI.)

---

## 5. Généralisation : tout le dialogue chiffré se relaie pareil (VU)

Le même schéma « blob opaque du SEP → trame SPy → réponse → SEP » vaut pour les autres opérations chiffrées de la
préparation. **Aucune ne fait de crypto côté AP** (vérifié par scan des cibles d'appel : chacune n'appelle que
`os_log`, `memcpy`, et `handleCMDSync`) :

| op sbio (SEP) | fonction capteur (AppleMesa) | trame SPI (sensor_hw) | crypto AP ? |
|---|---|---|---|
| 0x15 / 0x16 | `SessionKeyExchange` (cmd 0xe) | 0x72 / réponse 0x72 | **non** (VU) |
| 0x42 / 0x18 | `InitializeSequenceCounter` (`0x91d2aa4`) | 0x73 / réponse 0x73 | **non** (VU : `os_log`+`memcpy`+`handleCMDSync`) |
| 0x5d / 0x5c / 0x6a / 0x6f | `applySensorParams`→`SetEncryptedParameters` (`0x91d1c10`) | 0x55 | **non** (VU : idem) |
| (sous-cmd) | `SendEncryptedCommand` (`0x91d9c84`) | 0x55 | **non** (VU : idem) |

Détail important : `FillEncryptedCommandBuffer` (`0x91cef58`) ne fait que `memset`/`memcpy`/CRC et réserve de la
place pour un bloc **CCM B0** et un **CRC** (`kParameterCCM_B0Offset`, `kParameterCRCSize`), **sans jamais chiffrer**.
Autrement dit : le mot « Encrypted » dans les noms de commandes (`SetEncryptedParameters`,
`EncryptedWriteUpperHalfKey`, …) désigne une charge **déjà chiffrée** (par le SEP / le capteur), **pas** un
chiffrement fait par l'AP. L'AP pose la charge et le CRC dans la trame, c'est tout. (VU + hypothèse sur le sens de
« CCM B0 » = nonce/entête CCM rempli ailleurs qu'à l'AP.)

> Note de portée : les commandes `WriteUpperHalfKey` / `LockLowerHalfKey` / `ModifyTheDevGid` / `GoToProduction`
> appartiennent au **provisioning usine** (seaCookie, `provisionSensor`), hors de la séquence de boot qui nous
> intéresse. Elles suivent le **même modèle de relais** (pas de crypto AP) d'après le scan, mais ne sont pas sur le
> chemin de sbio4 et n'ont pas été reversées en détail. (hypothèse.)

---

## 6. Rôle des trames 0x72 / 0x73 / 0x55 dans cette phase (VU trace, recoupé kext)

- **0x72** (émission 0x2f=47 o, réponse type 0x72) : l'**échange de clés** lui-même. Vient **après** sbio 0x15,
  précède sbio 0x16. Charge = le blob de 40 octets négocié de bout en bout SEP↔capteur. (VU : kext 0x15→SPI→0x16 ;
  sensor_hw : « 0x72 après SEP 0x15 … puis SEP 0x16 ».)
- **0x73** (émission 0x47 o, réponse type 0x73) : le **1er message chiffré** après la clé de session, lié à
  `InitializeSequenceCounter` (sbio 0x42 → réponse 0x18, 0x40 o). (VU trace ; recoupé par `InitializeSequenceCounter`.)
- **0x55** (plusieurs tailles) : les **commandes chiffrées** de paramètres capteur, relais de `applySensorParams`
  (sbio 0x5d/0x5c/0x6a/0x6f) via `SetEncryptedParameters`/`SendEncryptedCommand`. (VU trace ; recoupé kext.)

Dans les trois cas, la charge est **opaque pour l'AP** : chiffrée et fraîche à chaque allumage (compteur/clé de
session dans le capteur et le SEP). L'AP ne connaît que le **transport** (en-tête `80 <cmd> <len16 BE> 00 00 00`,
mécanisme « demande d'état 0x10 » → longueur en attente → « lis-moi N octets 0x13 », cf. `sensor_hw.md`). (VU.)

---

## 7. Ce que l'AP fait vs ne fait pas (synthèse VU)

**L'AP (pilote capteur) FAIT :**
- habiller la charge SEP dans une trame SPI (`transferData`, en-tête + payload) ; (VU)
- calculer un **CRC16** d'intégrité (`AppleMesa::crc16ansi`) et réserver la place CRC/CCM-B0 dans le tampon ; (VU)
- piloter le capteur sur SPI (alim, réveil 0x78, état 0x10, lecture 0x13, DMA SIO) ; (VU sensor_hw)
- faire circuler les octets en **lockstep** avec les opcodes sbio du SEP. (VU)

**L'AP ne fait PAS :**
- aucun AES / HMAC / ECDH / RNG ; aucun appel à un moteur crypto ; (VU — absence totale dans le `__text` du bundle)
- aucun stockage de clé de session, aucun secret capteur ; (VU — aucun champ clé manipulé sur ce chemin)
- aucune lecture/altération du contenu des blobs SEP↔capteur. (VU)

---

## 8. Points ouverts (honnête)

1. **Machine d'état SPI interne** (`handleCMDSync` → `handleStateMachine`/`_handleCMD`/`_handleInterrupt`) : la
   correspondance exacte « cmd interne 0xe → trame SPI 0x72 » est **recoupée** (strings + ordre trace) mais pas
   suivie instruction par instruction. Le détail des champs d'en-tête SPI pour 0x72 au-delà de `80 72 00 28 00 00 00`
   (ex. octets d'enveloppe `3a 00…` + compteur 8 o vus en trace) est **hypothèse** (sensor_hw).
2. **Égalité slot `+0x8d0` == `SessionKeyExchange`** : très probable (signature identique) mais non confirmée par un
   dump complet de la vtable `AppleMesa`. (hypothèse.)
3. **Taille/forme exactes de la réponse SPI 0x72** (0x33 en trace) et offset précis de la charge de 40 octets dans
   l'enveloppe `80 d4 …` : l'AP l'extrait vers `AppleMesa+0x169`, mais le parsing d'enveloppe (où commence la charge)
   n'est pas reversé ici ; à confirmer sur les buffers OOL / SPI capturés. (hypothèse.)
4. **Provisioning usine** (0x24/0x30/0x43/0x49-0x4f/0x7e, `WriteUpperHalfKey`…) : supposé même modèle de relais,
   non reversé. Hors chemin sbio4. (hypothèse.)
5. Rien ici n'est **`vérifié`** au sens matériel : tout est lecture de binaire + recoupement de traces existantes.
   La preuve « le SEP accepte ce relais en natif » reste à faire par l'expérience (prérequis : xART frais scellé,
   capteur vivant), hors périmètre de cette analyse hors-ligne.
