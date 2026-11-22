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

---

## 9. Enveloppe SPI 0x72 — séquence de lecture (VU trace macOS C19)

2026-11-22, reverseur. **L'ouvert §8.3 est tranché par une capture macOS réelle.** Source : `traces/20261110-002829_c19-spi-dma-boot`
(bus capteur en DMA SIO, `analysis/sio_dialog.py <dir> --sep --full`). Le key exchange 0x72 y est **complet et exploitable**.
Marquage : **VU (trace macOS)** — octets lus tels quels dans la capture. Recoupe le run `sbio4` (2026-11-22) qui, lui, a échoué.

### 9.1 La séquence macOS exacte (VU, C19, t≈28.67 s)

Entre `SEP 0x15` (acquitté) et `SEP 0x16`, l'AP exécute **6 transferts SPI** dans cet ordre :

| # | sens | octets (hex) | taille | rôle |
|---|---|---|---|---|
| 1 | TX | `8072002f000000` + **40 o** (blob du SEP) | 0x2f = 47 | **émettre la commande 0x72** + la charge |
| 2 | TX | `80100007000000` | 7 | poll d'état (0x10) |
| 3 | RX | `00000000000000` + `8020001000000007 6000008833000000` | 0x17 = 23 | état : **longueur en attente = 0x33** |
| 4 | TX | `8013000b00000033000000` | 0x0b = 11 | demande 0x13 : « donne-moi **0x33 = 51** octets » |
| 5 | TX | `00` | 1 | octet muet (voir 9.3) |
| 6 | RX | `80d4003300000000 72 <40 o charge> <crc16>` | 0x33 = 51 | **la réponse-clé** |

Après le #6, l'AP refait un poll 0x10 (état revenu à `…006000000052330000`, au repos) puis acquitte `SEP 0x16`.

### 9.2 Les deux clés de la recette

1. **La longueur dans l'en-tête 0x72 = TAILLE TOTALE de la trame, pas la charge.** macOS envoie
   `80 72 00 2f 00 00 00` : `0x2f = 47 = 7 (en-tête) + 40 (charge)`. **PAS `0x28`.** C'est la même règle que toutes les
   autres trames (`80 10 00 07…` = 7 o total ; `80 13 00 0b…` = 11 o total ; identité `80 70 00 07…`). (VU, recoupé sensor_hw.md
   « longueur totale, 16 bits gros-boutiste ».)
2. **La charge de 40 o est à l'offset 9 de la réponse RX.** Enveloppe réponse = `80 d4 <len16 BE> <status32> <cmd> <charge> <crc16>` :
   - `80 d4 00 33` (4 o) · `00 00 00 00` (status = 0 = OK) · `72` (écho de la commande) → **9 o d'en-tête**, puis **40 o de charge**
     (offset 9..49), puis **2 o de CRC16**. `SPI_RESP_OFF = 9` est donc **correct** (même offset que le n° de série dans l'identité).
   - Le `status32` discrimine succès/erreur : **0 = OK** (réponse pleine), **≠0 = erreur** (réponse courte, voir 9.4).

### 9.3 L'octet muet #5 est optionnel

macOS sépare la demande 0x13 (#4), l'octet `00` (#5) et la lecture (#6) en **trois** cycles CS. `tools/mesa_hello.sh`
(et `analysis/mesa_spi_proxy.hello`) lit l'identité en **deux** cycles seulement — `xfer(req,0)` puis `xfer(zeros(N),N)` —
**sans** octet muet séparé, et cela marche (lecture d'identité **vérifiée matériel**, 2026-11-10). En mode FIFO scruté, le
premier octet `00` de la lecture full-duplex joue le rôle du muet. Donc #5 **n'est pas requis** : la lecture 2-cycles de
mesa_hello suffit. (VU mesa_hello vérifié + VU trace macOS.)

### 9.4 Décodage de l'échec du run sbio4 (2026-11-22) — confirme le diagnostic

Le run `traces/20261122-023626_native_sbio4` a envoyé `80 72 00 28 …` (longueur = **0x28**, erronée). Résultats bruts :
- état (`spi_0x72_status.bin`) : `8020001000000007 6000 46 88 0b 000000` → longueur en attente = st[12] = **0x0b = 11** (et non 0x33) ;
- réponse (`spi_0x72_resp_raw.bin`, 11 o) : `80 d4 00 0b 00 00 00 02 72 ed57` = `80 d4 00 0b` · status32 = **`00 00 00 02` (= 2, ERREUR)**
  · `72` (écho) · `ed57` (CRC). **Pas un ACK à re-poller : une réponse d'erreur (status = 2).**

Le capteur a reçu une trame qui s'annonçait longue de 0x28 = 40 o mais dont on a poussé 47 o : trame malformée → il répond
« commande 0x72 refusée, code 2 » en 11 o. La séquence de **lecture** du script était **correcte** (poll 0x10 → 0x13 → read →
offset 9) ; seule la **longueur d'en-tête à l'émission** était fausse. (VU, recoupe 9.1.)

### 9.5 Ce qu'il faut changer dans `pending/sep_native_sbio4.sh` → `spi_relay_0x72`

**Un seul changement, sur la construction de la trame (ligne ~711) :**
```
- frame = bytes.fromhex("80720028000000") + bytes(blob40)   # 0x28 = charge → FAUX
+ frame = bytes.fromhex("8072002f000000") + bytes(blob40)   # 0x2f = TOTALE (7+40) → macOS C19
```
Rien d'autre à toucher dans la fonction : le poll d'état (`st[12]|st[13]<<8`), la demande `80 13 00 0b … <len LE>` et la lecture
de `pending` octets reproduisent déjà la séquence macOS ; `SPI_RESP_OFF = 9` (offset de la charge) est confirmé juste.
(Corrigé dans le script le 2026-11-22 ; même correction appliquée au bloc SELFTEST et aux en-têtes de commentaire.)

**Garde-fou recommandé (facultatif) :** après la lecture, vérifier `resp[4:8] == b"\x00\x00\x00\x00"` (status32 = OK) et
`pending == 0x33` ; sinon c'est une réponse d'erreur → STOP+dump plutôt que d'injecter 40 o d'erreur dans le `SEP 0x16`.

### 9.6 Statut et limites

- La **forme** et la **séquence** 0x72 sont désormais **VU (trace macOS)**, plus seulement hypothèse §8.3.
- Reste **`hypothèse`** au sens matériel : que le SEP *accepte en natif* le blob relayé (ACK 0x16) — à prouver au prochain run
  réel (Albert), la correction de longueur levée. Les 40 o de charge restent **opaques** (chiffrés bout-à-bout, frais à chaque
  allumage : la charge C19 `c01f…abb` ≠ la charge sbio4, normal). Aucune clé ni secret extrait.
