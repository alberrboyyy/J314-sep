# AppleSEPManager / IOBiometricFamily : ce qu'un driver doit faire pour parler à SBIO (phase 2, source: kext)

2026-11-08 — analyste. Kernelcache macOS 13.5 (`macos/kernel.macho`). Kexts lus : `com.apple.driver.AppleSEPManager`
(fileoff 0x49e030 : classes AppleSEPBooter, AppleSEPControl, AppleSEPDiscovery, AppleSEPEndpoint, AppleSEPManager),
`com.apple.iokit.AppleSEPGenericTransfer`, `com.apple.driver.AppleMesaSEPDriver`, `com.apple.iokit.IOBiometricFamily`
(fileoff 0x6de8b0). Outils : `analysis/kext/kdump_syms.py` (nouveau : un listing par fonction nommée, annoté par les
symboles LC_SYMTAB) + `ksyms.py`, `kdis.py`, `macho_fileset.py`. Listings dans `analysis/out/kext/` (non versionné).
Aucun code Apple recopié : description en prose du protocole uniquement.

**Statut de tout ce fichier : `hypothèse` (source: kext).** Rien n'est `vérifié`. « Recoupe » = la lecture du kext
explique une valeur observée dans une trace citée ; ce n'est pas une expérience. Les traces : C1 =
`traces/20261107-033436_c1-boot`, C11 = `traces/20261108-025802_c11-doigt-tranchant`, C12 =
`traces/20261108-032454_c12-boot-ho` ; `Lnnn` = ligne de `sep.log`, `uart Lnnn` = ligne de `hv_uart.log`.

---

## 1. Mot mailbox et envoi (AppleSEPManager)

- Disposition octet par octet du message construit par les classes du kext : octet 0 = endpoint, octet 1 = tag,
  octet 2 = opcode (TYPE), octet 3 = param, octets 4-7 = data — identique au découpage Asahi.
- `sendMessage(ep, msg)` : le gestionnaire **écrase l'octet 0 par le numéro d'endpoint** et conserve tag/type/param/data.
  `sendRawMessage` (drapeau « raw ») envoie le mot de 64 bits tel quel, sans poser l'endpoint.
- Machine d'état d'envoi : dans les états de boot, seuls les messages vers 0xFE/0xFF sont acceptés (« attempt to send
  message to SEP in non-receptive state »). Un driver ne doit rien envoyer aux autres endpoints avant le signal
  « SEP/OS alive » (section 3).

## 2. Boot ROM (EP 0xFF) et mémoire partagée (EP 0xFE) — AppleSEPBooter

Rappel lignes rouges : l'envoi d'IMG4 / le boot du SEP est une **écriture vers le SEP** (Albert uniquement). Décrit ici
parce que c'est un prérequis de SBIO sous Linux.

| Ordre | Message AP→SEP (EP 0xFF sauf mention) | Construction (source: kext) | Réponse attendue | Trace |
|---|---|---|---|---|
| 0 | (debug seulement) TAG 1 TYPE 0x1e, puis TYPE 0x1f ×8 (param = 0, 4, … 0x1c) | lecture d'un KCV « iBIC » de 32 o si `PE_i_can_has_debugger` | 0x82 puis 0x83 (4 o chacun) | non vu |
| 1 | (si firmware « TbmV2 ») TYPE 0x24 data=adresse ustuff, puis TYPE 0x25 param=type fw data=adresse patch | « BootTmmManifest », « BootPatch » | « accepted TMM manifest / patches » | non vu (M1 Max 13.5) |
| 2 | TAG 1 TYPE 0x02 | GET_STATUS | 0x66, le kext exige statut = 1 | C11 L5-6 (DATA=1) — recoupe |
| 3 | TAG 1 TYPE 0x05 param=type fw | BOOT_TZ0 | 0x69 « accepted Tz0 » | C11 L7-8 ; uart L643 |
| 4 | TAG 1 TYPE 0x02 | GET_STATUS ; le kext exige statut = 2 | 0x66 (et 0xd2 porte aussi un statut) | C11 L9-11 ; uart L657-658 « SEP status: 2 » ×2 |
| 5 | TAG 1 TYPE 0x06 param=type fw data=adresse firmware >> 12 (variante « resume » : TYPE 0x08) | BOOT_IMG4 | — | C11 L12 (DATA=4) |
| 6 | **EP 0xFE** TAG 1, **octets 2-3 = taille de la mémoire partagée en pages de 4 Kio**, data = adresse esclave >> 12 | « Shmbuf for SEP » | 0x6a « accepted IMG4 » | C11 L13 + uart L660 « slave addr = 0x580000, size = 0x1c000 » — **recoupe** |

- Correction d'interprétation : le « TYPE 0x1c » de `> EP=0xFE` n'est pas un opcode mais l'octet bas d'une taille
  16 bits (0x1c pages = 0x1c000 o, confirmé par la ligne uart). Le `SET_SHMEM = 0x18` de m1n1 `hw/sep.py` serait donc
  lui aussi une taille (0x18000) — lecture, non vérifiée.
- Sur réveil (pas de firmware), le kext envoie un mot brut à l'EP 0xFE contenant l'offset de base de temps
  (`ml_get_abstime_offset`). Le réveil d'une sieste (« nap ») poste le mot 0x0e0000 (EP 0, TYPE 0x0e) deux fois.
- Réponses ROM traitées (`_bootAction`) : 0x65-0x6c, 0x82-0x89, 0xc7, 0xc9, 0xca (octets de log panique), 0xd2
  (statut), 0xff. **Non attribué : `> EP=0xFF TAG 0 TYPE 0x1b` / `< TYPE 0x7f` (C11 L3-4, ~1,7 s avant GET_STATUS).**
  Aucun site d'envoi trouvé dans AppleSEPManager ni AppleA7IOP ; 0x7f n'est pas dans la table de `_bootAction` et
  aucune ligne uart « unexpected message, op 127 » n'apparaît. Origine inconnue.

## 3. CNTL (EP 0x00) — AppleSEPControl

Opcodes envoyés par l'AP (noms = noms des fonctions `cmsg*`) :

| TYPE | Nom (source: kext) | Param / data | Trace |
|---|---|---|---|
| 0x00 | NOP | data = argument | — |
| 0x02 | SET_OOL_IN, adresse | param = ep, data = adresse esclave du buffer **d'envoi AP→SEP** >> 12 | C11 L140 (0x64) |
| 0x03 | SET_OOL_OUT, adresse | param = ep, data = adresse esclave du buffer **de réception SEP→AP** >> 12 | C11 L146 (0x6c) |
| 0x04 | SET_OOL_IN, taille | param = ep, data = longueur en octets | C11 L137 (0x4000) |
| 0x05 | SET_OOL_OUT, taille | param = ep, data = longueur en octets | C11 L143 (0x4000) |
| 0x0a | TTYIN | param = caractère | non vu |
| 0x0c | SLEEP | param = type de sommeil | non vu |
| 0x12 | NAP_OK | réponse de l'AP à un 0x11 du SEP | non vu |
| 0x13 | NAP | — | non vu |
| 0x14 | SECMODE_REQUEST | réponse : data = mode | C11 L41-42, réponse DATA=3 |
| 0x18 | SELF_TEST | — | non vu |
| 0x19, 0x1a | SET_DMA_CMD | — | non vu |
| 0x1b/0x1d/0x1f, 0x1c/0x1e/0x20 | SET_DMA_IN / SET_DMA_OUT | param = ep | non vu |
| 0x25 | ERASE_INSTALL | — | non vu |
| 0x26, 0x27 | L4_PANIC, SEPOS_PANIC | — | non vu |

- « IN »/« OUT » sont nommés du point de vue du SEP : `AppleSEPEndpoint::setSendOOLBuffer` → SET_OOL_IN (4 puis 2),
  `setReceiveOOLBuffer` → SET_OOL_OUT (5 puis 3). Donc **buffer A (T4/T2) = envoi AP→SEP, buffer B (T5/T3) =
  réception** — confirme côté kext la correspondance A/B jusqu'ici seulement cohérente avec les traces.
- Unités : tailles en octets, adresses en pages de 4 Kio (adresse « esclave » = IOVA vue par le SEP, `>> 12` en dur).
- TAG : `_cmsgSend` prend un emplacement dans un pool de 8 commandes et pose **tag = index + 1** ; la réponse
  (TYPE 0x01, même tag, data = écho) est rangée par tag. Le tag n'a pas de sens propre : C1 L39-41 (SECMODE en 0x08,
  OOL en 0x07) et C11 L39-41 / C12 L39-49 (inverse) — **recoupe**.
- Messages SEP→AP sur l'EP 0 (tag 0) : 0x0d → notification asynchrone « OS actif » ; 0x15 → idem directe ; 0x10 →
  `notifyWrappingActive` ; 0x11 → l'AP répond NAP_OK (0x12) ; tout autre opcode (0x0e, 0x0f, 0x12-0x14, 0x29…) →
  « EP0 received unsolicited message ». Trace : C11 L34 `<0d`, L38 `<29`, L98 `<10` ; uart L765 « unsolicited
  0x290000 » puis L766 « SEP/OS is alive » — **recoupe**.

## 4. Découverte (EP 0xFD) et table nom → numéro — AppleSEPDiscovery

- TYPE 0x00 : param = numéro d'endpoint, data = nom sur 4 caractères ASCII. TYPE 0x01 : param = numéro, data = 4 octets
  de tailles OOL : **octet 4 = min pages envoi, octet 5 = max pages envoi, octet 6 = min pages réception, octet 7 =
  max pages réception** (format du log « OOL in [%u,%u] OOL out [%u,%u] »). Page SEP = 0x4000 (0x1000 si un drapeau
  du gestionnaire est nul).
  Trace : `pnon` 0x02020404 → envoi [4,4], réception [2,2] = T4 0x10000 / T5 0x8000 ; `sks ` 0x02010201 → [1,2]/[1,2]
  = 0x8000/0x8000 ; `sbio` 0x01010101 → [1,1]/[1,1] = 0x4000 — **recoupe** l'hypothèse de messages.md et précise le
  sens des octets 0 et 2 (= minimums).
- **Pas de table statique nom → numéro** : le numéro vient de l'annonce TYPE 0x00 à chaque boot ; chaque endpoint annoncé
  devient un nub IOKit nommé `sep-endpoint,<nom>` ; les clients le cherchent par nom (GT : `sep-endpoint,sbio`).
  Un driver Linux doit donc lire les annonces 0xFD et chercher `sbio` (0x7362696f), sans coder 0x08 en dur.

## 5. Ouverture d'un endpoint (ex. sbio) — GT + AppleSEPEndpoint

1. Mesa crée son transport GT avec : nom d'endpoint `sbio`, **taille de buffer OOL 0x4000**, taille max de transaction
   0x4b000.
2. GT `enableEndpoint` : trouve `sep-endpoint,sbio`, obtient l'objet endpoint, puis **l'AP alloue** (allocateVisibleMemory
   du gestionnaire, alignement page) deux buffers de 0x4000 : d'abord l'envoi (`setSendOOLBuffer` → CNTL 4 puis 2),
   puis la réception (`setReceiveOOLBuffer` → CNTL 5 puis 3). Chaque message CNTL attend son acquittement.
3. Trace : C11 L137-148 (4/2/5/3, PARAM=8, 0x4000, pages 0x64 et 0x6c), uart L1555 « SEP EP 8 enabled » — **recoupe**.
   L'écart de 4 pages entre buffers (messages.md) n'est pas expliqué par le kext (allocateur).
4. Aucun message vers l'endpoint 0x08 lui-même n'est nécessaire pour « l'ouvrir » ; la 1re commande est 0x73.

## 6. IOBiometricFamily : lockState (notification TAG 0x01) et TAG 0x02/0x03/0x04 sur l'EP 0x08

Rappel : notification `< EP=0x08 TAG=0x01`, DATA = userID, u16 lockState = TYPE + PARAM·0x100 (Mesa
`handleSEPMessage`, déjà dans messages.md). `sksQueueProcess` range le u16 dans le contexte utilisateur et le teste bit
par bit. Sens des bits **déduit des noms des fonctions qui les testent** (source: kext) :

| Bit | Masque | Fonction qui le lit (source: kext) | Lecture |
|---|---|---|---|
| 0 | 0x0001 | `isAtLeastOneLocked` (et utilisateur avec u16 TAG 0x02 ≠ 0) | keybag verrouillé |
| 1 | 0x0002 | `isAtLeastOneWithoutPasscodeLockout` | blocage code (passcode lockout) |
| 2 | 0x0004 | `isAtLeastOneWithoutBioLockout` | **blocage biométrique** |
| 3 | 0x0008 | timers `checkBioTokenTimer` / `checkPasscodeInputTimer` / `checkBioMatchTimer` ; `isAtLeastOneEligibleForPrewarm` exige bits 0 et 3 | condition d'armement des jetons bio — sens exact non lu |
| 5 | 0x0020 | appelle `passcodeValidated` | « code validé » (événement) |
| 9 | 0x0200 | mêmes timers que le bit 3 (avec un autre drapeau du contexte) | sens non lu |
| 4, 6 | 0x0010, 0x0040 | aucun test trouvé dans IOBiometricFamily | inconnu |

- Transition spéciale : si (ancien & 0xc) = 0x8 et (nouveau & 0xc) = 0x4 (bit 3 → bit 2), message IOKit 0xe3ff8200 aux
  clients avec {uid, 2 ou 3}. Après chaque traitement : `finalizeSKSStateHandling`.
- Valeurs observées (C11, uid 0x1f5) : 0x0015 L558 et 0x0055 L560 (boot, juste après le 2e `0x6d`) ; 0x0011 L606, L666,
  L842 (avant login) ; **0x0228 L851, L860 (login, 207.38 s) et L5980 (`pw_unlock_4`, 792.13 s) : 3/3 juste après une
  saisie de mot de passe** ; 0x0209 au verrouillage ; 0x0208 au succès ; 0x0045 (C3, 5 échecs).
- Lecture (interprétation) : 0x0015 au boot = verrouillé + **blocage bio** (+ bit 4) → Touch ID refusé après boot
  jusqu'au code ; 0x0228 = code validé + bits 3/9 ; 0x0209/0x0208 = verrouillé/déverrouillé avec bio autorisée ;
  0x0045 = verrouillé + blocage bio après trop d'échecs. Cohérent avec le comportement macOS connu, mais `hypothèse`.
- Le 0x0228 de C11 L851 arrive 1 ms après la réponse SKS `< EP=0x12 TAG=0x98 TYPE=0x67` (L850) : l'état SBIO suit le
  keybag géré par l'EP 0x12 (AppleSEPKeyStore), pas l'EP 0x08.
- **TAG 0x02** : Mesa range le u16 dans le champ +0x10 du contexte utilisateur ; ce champ ≠ 0 est exigé par
  `isAtLeastOneLocked`, les tests de blocage et les timers bio → « l'utilisateur a la biométrie (gabarits) » ; valeur
  = nombre de gabarits ou simple drapeau : non lu. Trace : 1× C11 L562 (`TYPE=0x01`, uid 0x1f5), juste après le
  `> 0x6d` LoadCatacomb (L548) — cohérent ; une seule occurrence (coïncidence possible).
- **TAG 0x03** : pose un drapeau et déclenche `checkBgOpsResult` → `> 0x21` (recoupe, voir messages.md).
- **TAG 0x04** : `messageClients(0xe3ff800c)` sans charge ; vu 1× (C11 L350) entre `> 0x73` et `< 0x73`. Sens non lu
  (« SEP sbio prêt » : interprétation).
- `IOSEPBiometricService::handleSEPMessage` traite à part un TAG 0xfb (non vu dans nos traces).

## 7. Séquence minimale ordonnée pour un driver SBIO (lecture + C11) et dépendances macOS

Ordre observé dans C11 (L348 à ~L2100), rôle d'après le kext. « AP relaie » = la charge vient du SEP ou du capteur
(SPI), l'AP ne fabrique rien.

**A. Prérequis (hors SBIO, écritures SEP = Albert)** : boot ROM + IMG4 + mémoire partagée (section 2), attente
« OS actif » (CNTL 0x0d/0x15), SECMODE_REQUEST, découverte 0xFD, ouverture `sbio` (section 5). Le firmware SEP est
préchargé par iBoot (« SEP firmware preloaded in memory », uart L1515).

**B. Init SBIO**
1. `0x73` initSbioCommunication, entrée u32 = 1 (constante). SEP envoie `<TAG 0x04`.
2. `0x17` prepareSession, entrée 16 o = **numéro de série lu sur le capteur** (`GetSerialNumber`, SPI). Puis
   `prepareNotPairedSession` (0x1b) seulement si non appairé (non vu).
3. `0x15` (entrée u32 sessionType = 1, « Establishing UID session ») → sortie 40 o = `hostKeyWrapped` → capteur
   `SessionKeyExchange` (40 o → 40 o) → `0x16` (entrée = réponse du capteur, 40 o). **La clé de session est produite par
   le SEP et emballée pour le capteur ; l'AP ne fournit aucune clé.** (Clé capteur posée en usine : `ProvisionSensor`,
   `LockSensor`… non vus.)
4. `0x42` → sortie → capteur `InitializeSequenceCounter` → `0x18` (entrée 0x40 o). AP relaie.
5. `0x5f` (entrée 2 o) → sortie = patch → capteur `Patch` → `0x01`. Patch fourni par le SEP.
6. `0x5d`, `0x5c`, `0x6a` (`0x6f` au 2e tour) applySensorParams ; `0x31`/`0x32` numéro de série module ; `0x1f`.
7. `0x5b` setCalibrationData : **blob fourni par l'espace utilisateur** (biometrickitd, via user-client) ; le kext
   vérifie une signature et que le numéro de série du blob = celui du capteur. Identique d'un boot à l'autre (C5-C9).
   Puis `0x63`. `0x19` (reset capteur) et **le 2e tour 0x17…0x1f** (C11 refait 17-15-16-42-18-5f-5d-5c-6a-6f-31-32-01-1f).
8. `0x63` ×2, `0x7c`, `0x6b`/`0x79`, **`0x6d` LoadCatacomb : blob fourni par l'espace utilisateur** (fichier de gabarits
   scellé par le SEP, = dernier export `0x6c`, C12). Envoyé 2× (L522, L548) ; après le 2e : `<01` 0x0015, 0x0055,
   `<02`. Le chargement a lieu avant le login (137 s vs `pw_login` 203 s) : il ne semble pas exiger le keybag ouvert.
9. Requêtes de clients (`0x2b`, `0x54`, `0x33`, `0x36`, `0x6e`, `0x7a`, `0x39`, `0x28`, `0x7c`, `0x7d`, `0x0b`, `0x40`) :
   pilotées par biometrickitd ; nécessité pour un match : **inconnue**.
10. `0x71` LoadBioLockoutRecord : **blob utilisateur** (`HRLB`, sauvé par `0x70` après login/unlock). Nécessité inconnue.
11. `> TAG 0x26 DATA=uid` (dropUnlockToken), C11 L664.

**C. Tentative de match** (C11, à partir de ~L1841) : `0x23` → `0x06` (entrée 0xa7 o = `_lastImageProcessingParams`,
origine non lue) → `0x65` (image 0x7200 o lue sur SPI, AP recopie) → `0x07` (résultat image) → si image exploitable
`0x09` (sortie 0xca2 o `match_info_t`, uid ou −1) → `0x1f` → `0x22` ; `<TAG 0x03` → `0x21`. `0x27`/`0x25`
(`commandStartMatch`) n'apparaissent pas dans C11.

**Dépendances à des données fournies par macOS (bloquants potentiels pour Linux)**

| # | Donnée | Origine (source: kext) | Contournement envisageable | Gravité |
|---|---|---|---|---|
| D1 | Boot SEPOS (IMG4, TZ0, shmem) | iBoot précharge le firmware ; AppleSEPManager le boote | m1n1/Asahi ; écriture SEP → Albert | prérequis |
| D2 | **Keybag utilisateur (SKS, EP 0x12)** | AppleSEPKeyStore + mot de passe ; lockState 0x0015 au boot = blocage bio jusqu'à « code validé » (0x0228, 1 ms après la réponse SKS) | aucun simple : piloter l'EP 0x12 avec le mot de passe (écriture SEP, protocole SKS inconnu). **Inconnu : le SEP refuse-t-il `0x09` sous blocage bio, ou macOS s'abstient-il seulement ?** | **bloquant probable** |
| D3 | Calibration `0x5b` | blob espace utilisateur, signé, lié au n° de série capteur | rejouer le blob capturé (C5-C9 identique) | faible si rejouable |
| D4 | Catacomb `0x6d` | fichier espace utilisateur, scellé par le SEP | rejouer le dernier export `0x6c` (C12) ; enrôlement Linux = autre chantier | moyen |
| D5 | BioLockoutRecord `0x71` | blob espace utilisateur | rejouer ou omettre (à tester) | inconnu |
| D6 | Paramètres `0x06` (0xa7 o) | `_lastImageProcessingParams` du kext (origine non lue) | à lire (Mesa) ou rejouer | inconnu |
| — | Clé de session capteur (0x15/0x16), patch (0x5f), compteur (0x42/0x18), n° de série (0x17) | SEP ↔ capteur, AP relaie | rien à fournir | aucun secret AP |

## Incertitudes signalées

- Sens des bits 3, 4, 6, 9 du lockState ; valeur exacte du u16 TAG 0x02.
- Origine du couple `0x1b`/`0x7f` sur l'EP 0xFF.
- `SET_SHMEM 0x18` de m1n1 lu comme une taille : déduction, pas vérifiée.
- Les noms SET_OOL_IN/OUT et les sens des bits sont des noms de fonctions Apple ; leur sémantique côté SEP n'est pas
  observable depuis le kext.

## Écarts d'ordre d'init K6-1..3, `+0x14` de 0x09, 0x63/0x61 (2026-11-08, analyste — source: kext, macOS 13.5)

Méthode : AppleMesaSEPDriver (fileset de `macos/kernel.macho`), noms par `analysis/kext/ksyms.py`, listings
`kdis.py func` (non commités), arbre d'appels et immédiats `w1` par script jetable. Aucun code copié. Les offsets `this+0x…`
sont ceux du kext (noms de champs = déduits des chaînes de log, sauf mention).

**K6-1 (5f et 01 jamais adjacents) : expliqué.** `loadPatch(uint, uint8*, uint, bool)` (0x978bd88) contient, dans cet
ordre : envoi `0x5f` (patch) → `applySensorParams(false)` → lecture du n° de série module (`getSensorModuleSerialNumberRaw`,
`memcmp` de 0x14 o, puis `checkDisableConditions`) → **`0x01` sans paramètre** (sepTransact w1=1, aucun tampon) →
`cacheMatchPolicy(true)` → `_sensorState = 3` (this+0x200). Donc 5d 5c 6a [6f] et 31 32 sont **à l'intérieur** de
`loadPatch`, et 0x01 en est la dernière commande SEP : l'ordre observé `5f 5d 5c 6a 31 32 01` est l'ordre du code.
L'hypothèse « loadPatch appelle applySensorParams et le n° de série entre le patch et 0x01 » est la bonne ; la lecture
« 5f → GetStatus → 01 » était fausse. Rôle de 0x01 : il précède le passage à l'état 3 → plutôt « activer/valider le capteur
après patch » (interprétation ; aucun tampon, donc rien à décoder).

**K6-2 (0x6f absent au 1er tour, présent au 2e) : expliqué par un drapeau posé par `setCalibrationData`.**
`applySensorParams(coverageParamsOnly)` envoie 0x5d, 0x5c, 0x6a (si `!coverageParamsOnly`), puis 0x6f **seulement si**
`this+0x204 ∈ {3,4}` (valeur lue comme type de capteur, cf. assert `_sensorType == kSensorType…`) **et** l'octet `this+0x2cc3`
≠ 0. Cet octet n'est écrit qu'à un endroit du kext : `setCalibrationData` (0x9785b24, `=1`), après l'envoi de 0x5b.
1er tour (avant 0x5b) : octet = 0 → pas de 0x6f ; 2e tour (après 5b/63) : octet = 1 → 0x6f. Concorde avec 8/8 boots.
Autre effet : chacun de 5d/5c/6a/6f, si la réponse est `0x12d`, relance `resetSensorAndLoadPatch(4,false)` — jamais vu en trace.
Limite : ne dit pas de quel type est notre capteur ; seule la présence de 0x6f au 2e tour prouve que `+0x204 ∈ {3,4}`.

**K6-3 (0x61 jamais envoyé) : expliqué, condition dépendant de l'arbre de périphériques.**
`setCalibrationData` envoie 0x61 avec **4 octets en entrée** (float, `w3=4`, sortie nulle) ; le log est « Modulation ratio set
to SEP. (MR*1000)=%d ». Conditions : `this+0x1cc4` (float) ≠ 0 **et** l'indicateur « déjà envoyé » (`this+0x1cc8`) = 0. Le float est
écrit uniquement par `mesaInit` (0x977ea54) : u16 d'une propriété de nom `modulation-ratio` × 1/1024 ; si la propriété est
absente ou nulle, il reste 0 (init à 0 dans `start`). Donc 0x61 = « envoyer le ratio de modulation au SEP », et il n'est pas
envoyé ici parce que `modulation-ratio` est absent/0 dans le DT de ce MBP (**hypothèse non vérifiée** : aucun DT dans les
traces ; `grep modulation` traces/docs = 0). Conséquence Linux : rien à faire tant que cette propriété est absente.

**Ordre de la 2e passe (K6-4, complément).** `setCalibrationData` finit (si `this+0x204 ∈ [2,4]` et l'octet `this+0x1c38` = 0)
par `resetSensorAndLoadPatch(4,false)` (0x9785e70) = `resetSensor` (→ 0x19) puis `loadPatch(…)` : c'est la 2e passe complète
(17 15 16 42 18 5f … 01 1f vue en C11). Autrement (octet ≠ 0) le kext fait `applySensorParams(false)` + `sendDeviceSerialNumberToSbio`
sans reset. Le 1er tour passe par `prepareSession` (0x17, `performKeyExchange(1)` = 15/16) puis `loadPatch`.
Non élucidé : quel chemin fait appeler `prepareSession`/`initializeSequenceCounter` dans la 2e passe (appel virtuel, non résolu).

**K3 (+0x14 de la réponse 0x09).** Les 29 réponses 0x09 OOL non vides (C6 5, C8 6, C11 18 ; charge 0xca2 = 3234 o,
`analysis/out/c{6,8,11}_payloads/*outB_09.bin`, C11 extrait par `ool_attempts.py --dump-dir`) ont **toutes** `+0x14..+0x1b = 0`
(u32 +0x14 = 0, 29/29, y compris les non-correspondances `ffffffff` de C11). C6 a 5 autres fichiers 0x09 vides (0 o, pas des
réponses). Les 18 de C11 couvrent bon et mauvais doigt, session verrouillée et ouverte. Cohérent avec « ≠ 0 ⇒ relance » :
aucune relance n'a lieu. (C1/C3 : captures antérieures sans dump OOL, non lues → les 50 transactions annoncées par le
sceptique ne sont couvertes qu'à 29.) Statut : lecture kext **non contredite**, branche ≠ 0 jamais exercée.

**0x63 / 0x61.** 0x63 = `getCalibrationDataInfo` (0x97854d4 : sepTransact w1=0x63 ; attente d'événement 30 s `waitForEvent(0x7530)`
si le drapeau n'est pas prêt). Utilisé sur ce capteur : oui (présent à chaque boot : `5b 63`, `63 63`, + 2 dans la queue
user-client). `setCalibrationData` exige que la taille retournée soit `sizeof(calDataInfo)` (assert) avant
`sendDeviceSerialNumberToSbio`. 0x61 n'est **pas** GetCalibrationDataInfo : c'est le ratio de modulation (voir K6-3), non envoyé.

## 8. xART (EP 0x13) — `AppleSEPXART::_handle_sep_driven_msg` : table des opérations (2026-11-11, Claude — source: kext, macOS 13.5)

Méthode : `com.apple.driver.AppleSEPManager` du fileset `macos/kernel.macho` ; symbole
`__ZN12AppleSEPXART22_handle_sep_driven_msgEPNS_11XARTMessageE` (vm `0xfffffe0009986588`), désassemblé avec
`analysis/kext/kdis.py func` (listing non commité). Aucun code copié ; on décrit le dispatch et le format. **Statut : `hypothèse`
(source: kext).** But : interpréter la bifurcation de l'essai voie C n°1 (le SEP a demandé `TYPE=0x01` à `TAG=0x05` au lieu du
`TYPE=0x05` de macOS — cf. journal 2026-11-11).

**Structure `XARTMessage` (offsets lus dans le handler).** Le message SEP→AP (`<` sur EP 0x13) est vu octet par octet :
octet 1 = TAG, **octet 2 = opération (ce que la trace appelle TYPE)**, octets 3-4 = longueur (halfword, `[x19,#3]`),
**octet 5 bit 0 = sélecteur SEP(0) / USER(1)** (`tst w22,#1` → chaîne `"SEP"` ou `"USER"`). Deux tampons OOL portés par l'objet :
`this+0xc8` = tampon **A** (AP→SEP, ce que l'AP *écrit* pour le SEP) et `this+0xd0` = tampon **B** (SEP→AP, ce que le SEP a
*déposé* : UUID réclamé ou blob à sauver). Concorde avec notre convention de trace (A = AP→SEP, B = SEP→AP).

**Dispatch (switch sur l'opération, table à `0xfffffe0009986db8`, opérations 0x00–0x0e ; 0x13 traité à part ; autre = inconnu).**

| op (TYPE) | handler | rôle (chaîne de log du kext) | tampon lu / écrit |
|---|---|---|---|
| 0x00 | 0x6e8 | **FETCH xART maître** — `"Fetched %s-xART with CRC: 0x%x"` (`%s` = SEP ou USER) | écrit le blob dans **A** |
| 0x01 | 0x838 | **SAVE xART maître** — `"Saving %s-xART with CRC: 0x%x"` | lit le blob depuis **B** (CRC16) |
| 0x05 | 0x874 | **FETCH gigalocker par UUID** — attend longueur = 0x10 (16 o d'UUID dans **B**), rend le locker | lit UUID en **B**, écrit locker en **A** |
| 0x06 | 0x99c | **SAVE gigalocker** — `"Saving %s-xART Locker with CRC"` / `"Fetched %s-xART Locker with CRC"` | B/A |
| 0x07 | 0x9d8 | locker **supprimé / introuvable** — `"%s_XART_LOCKER with uuid %s %s"` (`being deleted` / `not found`) | — |
| 0x0e | 0xac8 | état de chargement fw — chaînes `protected-data-access`, `sepfw-load-at-boot`, `sepfw-loaded` | — |
| 0x13 | (hors table) | `AppleSEPXART::_determineOsUuidGated` (vm `0x9986290`) : rend **16 o d'UUID de l'OS** | écrit l'UUID en **A** |
| autre | 0x814 | `"AppleSEP:WARNING: AppleSEPXART (EP: %u) received unknown SEP request op %u"` → acquitte (op 0x16) | — |

Toutes les branches réécrivent l'octet 2 (op) par le code de réponse et renvoient le message au SEP (`"Replied to xART app: 0x%016llx"`).

**Fraîcheur / anti-rejeu (symboles, non désassemblés en détail).** La classe `AppleSEPXART` expose un sous-système de nonce et de
graines de session : `nonce_generate`, `nonce_read`, `nonce_invalidate`, `_nonce_action`, `commit_hash`, `setup_OS_UUID`,
`_determineOsUuidGated`, `fetch_xart_known_sessions`, `erase_session_seeds_for_UUID`, `erase_all_xART_seeds`. Lecture (hypothèse) :
l'état xART est **lié à un UUID d'OS + un nonce/graine de session** (op 0x13 fournit l'UUID ; le nonce vient a priori de l'EP
`pnon` 0x15). Ce n'est donc **pas** un simple « rends-moi le dernier blob » : le SEP valide le blob rendu contre ce contexte.

**Application à l'essai voie C n°1 (interprétation, `hypothèse`).** Les « 4 lockers » rejoués = TAG 0x02 **op 0x0e** (état fw-boot),
TAG 0x01 **op 0x13** (UUID d'OS), TAG 0x03 **op 0x00** (FETCH SEP-xART) et TAG 0x04 **op 0x00** (FETCH USER-xART) — soit **2 blobs
xART maîtres + l'UUID + le drapeau fw**, pas 4 gigalockers. Puis, là où macOS enchaîne des **op 0x05 (FETCH gigalocker)**, le SEP
sous m1n1 a émis **op 0x01 (SAVE xART maître)**. Donc le SEP ne réclame pas le gigalocker suivant : il veut **ré-écrire** son xART
maître. Cohérent avec « l'état restauré n'a pas été jugé valide/courant → le SEP re-scelle » (hypothèse B de `hypotheses.md` HV1) —
et un SAVE acquitté ferait vraisemblablement **avancer le compteur scellé** du SEP (ce qui collerait avec la casse du boot Apple
constatée après l'essai). À **ne pas** acquitter sans décision d'Albert **et** sans image disque préalable.

## 9. xART — fraîcheur / nonce : d'où vient l'anti-rejeu ? (2026-11-12, Claude — source: kext, macOS 13.5)

Suite du §8. But : dire si le **re-scellement** observé à l'essai voie C (le SEP émet op 0x01 SAVE au lieu de continuer les FETCH)
est **inévitable par conception**. Fonctions désassemblées (kext AppleSEPManager, `kdis.py func`, listings non commités) ;
**statut : `hypothèse` (source: kext)**. Le *pourquoi* final est interne à SEPOS/ROM, non observable depuis le kext — on décrit
ce que l'AP fait et ce à quoi l'état est lié.

**À quoi l'état xART est lié (2 ancrages).**
1. **UUID d'OS** — `_determineOsUuidGated` (op 0x13) lit `/chosen` → propriété **`apfs-preboot-uuid`** (`0x74a71a8`) et la rend au
   SEP en tampon A. C'est l'UUID du volume macOS amorcé : **constant** pour une même install → **rejouable**, donc ce n'est **pas**
   lui le verrou de fraîcheur.
2. **Nonce SEP** — un sous-système de nonce, porté **par l'EP xART 0x13 lui-même** : `nonce_generate` / `nonce_read` /
   `nonce_invalidate` → `_nonce_action` → `_runOperation(block)` → **`AppleSEPXART::_xmsgSend(XARTMessage*, xart_buffer_config*)`**
   (`0x99939e8`). L'AP **demande** au SEP de générer/lire/invalider un nonce ; il n'en **choisit pas** la valeur.
   - `AppleSEPUserClient::getOrGenerateNonce` (`0x9999aac`) appelle generate puis read et journalise
     `"AppleSEP: %s SEP Nonce (%u bytes): 0x…"` avec `%s` ∈ {`Current`, `New`} — déclenché **à la demande** (user-client), pas
     prouvé « à chaque boot ».
   - `nonce_invalidate` journalise `"SEP Nonce invalidated"` (via `DispatchUserClientInvalidate…`).

**Nonce ROM du SEP (booter).** `AppleSEPBooter::generateROMNonce(uint8_t*, uint32_t*)` (`0x9989684`) dialogue avec la **ROM du SEP**
et attend l'opcode de boot **`BootOpcode::ReportNonceWord`** (« le SEP rapporte un mot de nonce »). **Appelé uniquement** depuis
`AppleSEPUserClient::DispatchUserClientGenerateROMNonce` (user-client, à la demande) — **pas** dans la séquence de boot automatique
que reproduit `pending/sep_boot.sh` (qui ne fait que GET_STATUS / BOOT_TZ0 / BOOT_IMG4 / SET_SHMEM). La valeur est **produite par
la ROM**, l'AP ne la fixe pas.

**Lecture (HYPOTHÈSE, source: kext) — pourquoi le SAVE à TAG=0x05 est le comportement attendu.** Les blobs xART que le SEP fait
sauvegarder sont liés à un **nonce que le SEP produit lui-même** (xART et/ou ROM), pas à une valeur fournie par l'AP. Au boot m1n1
(sep_boot), le SEP a un **contexte de nonce courant** qui n'est pas celui sous lequel les lockers rejoués ont été scellés (capture
macOS = un autre boot SEP). Après avoir chargé les 2 blobs maîtres (op 0x00) + l'UUID (op 0x13), le SEP **ne reconnaît pas l'état
comme courant** et **re-scelle** (op 0x01) au lieu d'aller chercher les gigalockers (op 0x05). C'est exactement la bifurcation
observée, et un SAVE acquitté ferait avancer l'état scellé (cohérent avec la casse du boot Apple).

**Détail du protocole nonce (2026-11-12, Claude — désassemblé, source: kext).**
- **Sélecteurs** passés à `_nonce_action(void*, uint*, uchar)` via les closures : `nonce_generate` = **0x0f**, `nonce_read` = **0x10**
  (`nonce_invalidate` sans buffer). Le block_invoke (`0x99879a0`) exige **`*len ≥ 0x14` (20 o)** sinon `0xe00002c2`, puis délègue à
  `_xmsgSend` (`0x99939e8`) avec le sélecteur. La **taille du nonce = 20 o = 160 bits**, la même des deux côtés (xART et ROM).
- **`generateROMNonce` (protocole bootstrap ROM).** L'AP construit un message **constant** `0x00030100` (aucune graine chargée),
  l'envoie (vtable +0x1e8), attend (timeout `0xc350` = 50 s), le SEP répond **opcode `0x67`** avec **data `0xa0` (= `NONCE_BIT_LEN` 160)**,
  puis l'AP **lit** le nonce mot par mot (opcode suivant `0x00040100`). Les seules entrées de `generateROMNonce` sont le **buffer de
  sortie** et sa **longueur** : l'AP **ne fournit aucune graine**, il reçoit un nonce **produit par la ROM**.
- **Aucune API « poser / semer » un nonce côté SEP.** Recherche de symboles `set_nonce`/`writeNonce`/`SeedNonce`/`nonce_seed`/
  `bootNonce` dans les classes SEP/XART/Booter : **vide**. L'AP n'expose que generate (0x0f) / read (0x10) / invalidate — **jamais set**.
- **NVRAM vue par AppleSEPManager** (`_loadFlagData`, `getReadableNvram`) : uniquement `oblit-inprogress`, `auto-boot`,
  `sep-debug-args`. **Aucune** variable `boot-nonce`/graine qui alimenterait l'xART. Donc le nonce de fraîcheur n'est **pas** dérivé
  d'une graine NVRAM réglable par l'AP (≠ modèle « boot-nonce » iOS, qui, lui, est du côté img4 `__img4_nonce_manager_persistence_nvram`,
  pour la **personnalisation de l'image de boot**, pas pour la fraîcheur des lockers xART).

**Conséquence pour la voie C (HYPOTHÈSE renforcée, source: kext).** Du **côté AP**, il n'existe **aucun levier** pour fixer, semer ou
reproduire le nonce xART : il est généré par le SEP (ROM, 20 o), l'AP ne peut que le déclencher/lire/invalider. Un rejeu (statique ou
relais) d'un état scellé sous un **ancien** nonce ne peut donc **pas** être rendu « frais » par l'AP sous Linux → le re-scellement
observé (op 0x01 à TAG=0x05) est bien le comportement **attendu**, et la voie C « faire accepter un rejeu » penche **fortement vers
impossible côté AP**. **Réserve honnête** : ceci prouve l'**absence d'API côté AP** ; ça n'exclut pas formellement que la ROM du SEP
lise une graine dans son **propre** stockage effaçable interne (non observable d'ici). Mais tout ce que l'AP contrôle est désormais
cartographié : pas de levier nonce. L'essai qui écrirait reste **Albert + image disque**, mais sa probabilité de succès baisse.

## 10. SKS (EP 0x12) — inventaire pour une sonde « annoncé vs vivant » (2026-11-12, Claude — source: kext + traces)

But : savoir quels messages SKS seraient **de pure lecture** (ne changent pas l'état du keybag), en vue d'une sonde
`pending/` testant « sks annoncé ≠ sks fonctionnel ». **Statut : hypothèse.**

**Transport confirmé (source: kext).** Le driver du keybag côté AP est `com.apple.driver.AppleSEPKeyStore` (bundle présent
dans `macos/kernel.macho`) ; il parle à l'EP 0x12. Classes/méthodes liées vues dans les symboles : `AppleKeyStore`
(`unload_keybag`, `unload_session_keybags`, `set_volume_keybag`, `tdm_new_entry`/`tdm_remove_entry`), `AppleFDEKeyStore`
(`setPassphraseWithUserID`, `deletePassphrase`, `setKeyWithUserID`, `deleteKey`), et côté biométrie
`IOSEPBiometricService::sksQueueInit/Enqueue/Dequeue/Process/ProcessAsync` + `sksLockStateChangeHandler` (chemin des
notifications TAG 0x01, déjà documenté §6). Ces noms sont majoritairement des **mutations** (load/unload/set/delete).

**Commandes SKS on-wire observées en trace (`> EP=0x12`), nature :**

| TAG | rôle observé (messages.md C8/C3/C1) | nature |
|---|---|---|
| 0x2f | verrouiller keybag/volume si délai écoulé (bit 0 réponse = verrouillé) | **MUTE** (verrouille) |
| 0x41 | déverrouillage par mot de passe, 1re étape (volume, -6) | **MUTE** (déverrouille) |
| 0x18 | déverrouillage -501 par mot de passe (2e étape) / op au verrouillage | **MUTE** |
| 0x04/0x06 (→ réponse 0x84/0x86) | réponse PARAM=0xfd **avant** 1er login, 0x00 **après** (3 captures) ; reflète l'état login | **candidat LECTURE** (reflète un état, pas vu muter) |
| 0x98 (→ réponse d'une requête) | réponse SKS `TYPE=0x67` 1 ms avant 0x0228 (code validé) | à classer |
| TYPE = compteur de transaction | +1 à chaque requête (3 écarts sur 579) | le SEP suit une **séquence** → une requête hors-séquence peut désync |

**Conclusion pour une sonde (honnête).**
1. **EP 0x12 est une ligne rouge « écriture interdite à l'agent »** (CLAUDE.md). *Envoyer* un message SKS — même le poll
   0x04/0x06 — reste un envoi vers le SEP : la sonde va **dans `pending/`**, lancée par Albert, jamais par l'agent.
2. On n'a **aucune** commande SKS **vérifiée** comme pure lecture : 0x04/0x06 est seulement un *candidat* (reflète l'état login
   sans mutation observée) ; le compteur de transaction fait qu'une requête injectée hors-séquence pourrait être rejetée/désync.
3. **`sbio` (EP 0x08) n'est PAS sur la liste rouge d'écriture** : une sonde de lecture est bien moins contrainte côté sbio que
   côté sks. Si l'on veut tester « vivant », sbio est la porte la plus sûre (reste à bâtir la liste exhaustive de ses messages de
   lecture — règle « protocole complet avant de coder la réponse »).

## 11. sbio (EP 0x08) — reconnaissance pour une sonde « vivant » et pour le driver (2026-11-12, Claude — source: kext)

But : trouver un message sbio de **lecture pure** (prouver « sbio annoncé = vivant » sans déclencher match/enroll/capture) et,
plus largement, préparer le driver. Désassemblage `com.apple.driver.AppleMesaSEPDriver`. **Statut : hypothèse / reconnaissance.**

**Vu (FAITS, source: kext).**
- Le statut de provision côté AP est **caché** : `getProvisioningStateInt` (`0x978e16c`) lit seulement des champs de l'objet
  (`_provisionStatus` à `+0x1f0`, `_provisionStatusExt` `+0x1f4`, drapeaux `+0x1f8`/`+0x1fa`) et les mappe vers un enum public
  (ex. statut interne 0x1d/0x20/0x35/0x36/0x6e → 0..10). **Aucun aller-retour SEP** : lire « provision status » ne prouve pas que
  le lien SEP est vivant *maintenant*.
- Les opérations sbio sont dispatchées par **méthodes virtuelles** du driver Mesa : `provisionSensor` (`0x978e3ec`) appelle
  `this+0xa48` (provType 1) ou `this+0xa58` (provType 2-4) — les opcodes fil sont **dans ces méthodes virtuelles**, pas en
  immédiat. Le stack est **stateful** (handlers `checkAutoMatchConditions`, `accessoryStateHandler`, `_commandMode`, `_fingerOn`,
  `autoMatchConditionsHandler`, `bgOpsResultReadyHandler`…).

**Interprété / conséquence.**
- Pas de « lecture de statut » fil **triviale et sans effet de bord** repérée côté sbio : une sonde « vivant » n'est **pas** un
  one-shot simple, c'est un sous-système à cartographier opcode par opcode. Cohérent avec la prudence déjà retenue (« annoncé ≠
  vivant » ne se tranche pas d'un seul message injecté).
- **Prochain pas (décompilation, pour le driver surtout)** : marcher la **vtable du driver Mesa** (slots `+0xa48`, `+0xa58`, et
  ceux de match/enroll/cancel) pour nommer les opcodes EP 0x08, en les croisant avec les **TAGs fil déjà dans `messages.md`**
  (séquences `0xfc`/`0x09`/`0x70`, notifs TAG 0x01, TAG 0x02/0x03/0x04 — cf. §6). Objectif : table opcode↔nom↔effet (lecture/mutation).

## 12. sbio (EP 0x08) — carte des opérations du driver (vtable AppleMesaSEPDriver, 2026-11-12, Claude — source: kext)

Suite du §11. Vtable `__ZTV18AppleMesaSEPDriver` résolue (chained-fixup arm64e auth-rebase, base `0xfffffe0007004000`,
VA = base + 32 bits bas ; outil `scratchpad/vtable_dump.py`, non commité). Les méthodes **propres** au driver (au-delà de
l'IOService hérité) donnent la surface d'opérations sbio. **Statut : hypothèse (noms de méthodes, source: kext).**

**Primitive d'envoi au SEP.** `sepTransact(uint opcode, const void* in, ulong inLen, void** out, ulong* outLen, bool, uint)`
(slot 316) et `sepTransactToIOMD(uint, const void*, ulong, IOMemoryDescriptor*, uint*, uint)` (slot 315). C'est le point de
passage AP→SEP sbio. Appelées **en virtuel** (pas de `bl` direct → la recherche d'appelants ne les voit pas) ; l'`opcode` (w1)
provient de structures de commande `bm_cmd_t` (cf. `performSpecificCommandGated(const bm_cmd_t*, …)` slot 277,
`checkBiometricCommand(const bm_cmd_t*)` slot 294, `getBiometricCommandMagic()` slot 293).

**Opérations nommées (sélection), nature présumée d'après le nom :**

| slot | méthode | nature |
|---|---|---|
| 324 | `getProvisioningState(IOMemoryDescriptor*, uint*)` | **lecture — mais CACHÉE côté AP** : empaquette `getProvisioningStateInt` (champs `_provisionStatus` +0x1f0), **aucun aller-retour SEP** (désassemblé) |
| 341 | `diagnostics(const void* in, ulong, IOMemoryDescriptor* out, uint*)` | **lecture structurée** : `in[0]` = sous-sélecteur 1..5 (table de saut) ; candidat sonde mais pas un opcode unique |
| 313 | `getSepTimeMeasurements(time_struct_t*)` | lecture (mesures de temps SEP) — à vérifier si transact réel |
| 322/323 | `prepareSession` / `prepareNotPairedSession(bool*)` | session (établit l'état) |
| 325/326/327 | `provisionSensor(uint)` / `unpairSensor()` / `unprovisionSensor(bool)` | **mutation** (provisioning) |
| 329/331 | `provisionNavajo(uint)` / `provisionSandDollar(uint, bool)` | **mutation** par génération de capteur (Navajo, SandDollar = noms Apple du capteur Touch ID) |
| 333/335 | `lockRootKeyInSensor(bool*)` / `provisionSensorWithRootKey(…)` | **mutation sensible** (clés) |
| 334 | `establishDiffieHellmanSession()` | **mutation** (négociation de clé SEP↔capteur) |
| 305/306/319/320 | `LoadPatch` / `ClearPatchOverride` / `loadCustomPatch` / `cachePatch` | **mutation** (firmware capteur) |
| 290/291/292 | `forceBioLockout(int)` / `dropUnlockToken(uint)` / `dropBiometricTokens(uint)` | **mutation** (verrouillage/tokens) |
| 338/339/340 | `getPreImage` / `prepareSerialisedTemplates` / `getSerialisedTemplates` | **lecture de données biométriques — NE PAS sonder** (empreintes/templates) |
| 300 | `sendLockStateToClients(lock_state_data_v1_t)` | propage l'état de verrou (côté AP) |
| 297/310 | `handleSEPMessage(ulong)` / `ProcessMessage(asd_message_t)` | réception SEP→AP |

**Conclusion pour une sonde « vivant » (honnête).** À cette couche, pas de « ping statut » fil **trivial et sans effet de bord** :
`getProvisioningState` est caché AP (ne prouve rien) ; `diagnostics` est multi-sous-commandes ; les opérations qui parlent
vraiment au SEP sont soit des mutations, soit des lectures de données biométriques (interdites). **Prochain pas pour une sonde** :
suivre une sous-commande de `diagnostics` (sélecteur 1 → `0x978df34`) ou `getSepTimeMeasurements` pour trouver **une** lecture qui
fait un `sepTransact` propre (opcode fixe, sortie bornée, aucune écriture) — ce serait le message à mettre dans `pending/`.

### 12b. Format de commande `bm_cmd_t` (performSpecificCommandGated, source: kext)

`performSpecificCommandGated(bm_cmd_t* cmd, payload, payloadSize, outData, outSize)` (slot 277) lit l'en-tête de `cmd` :
- **Magic « BM »** (`0x4d42` = 'B','M', `getBiometricCommandMagic`) en u16 à l'offset **+0**. Format « BM » : champ u16 à **+2**
  (sélecteur/opcode présumé, → `w25`) et u16 à **+6** (→ `w27`).
- **Magic v2 « CMCM »** (`0x4d434d43`) en u32 à +0 : octet de **type** à **+4** mappé vers une taille (type `0x01`→`0x02`,
  `0x1b`→`0x10`, `0x36`→`0x22`), octet à **+5** (→ `w27`) ; le driver reconstruit un en-tête « BM » (`0x4d42` + taille) en interne.
Ensuite la commande est exécutée et, pour les opérations qui parlent au SEP, relayée par `sepTransact(opcode, …)`. L'`opcode`
**fil** (EP 0x08) n'est donc pas le champ `bm_cmd_t` directement : il est posé au moment du `sepTransact` (appel virtuel).
**Prochain pas table opcode↔fil** : tracer, pour quelques opérations nommées (§12), la valeur d'`opcode` passée à `sepTransact`,
puis la croiser avec les TAGs EP 0x08 de `docs/messages.md` (0xfc/0x09/0x70…). **Statut : hypothèse (source: kext).**

### 12c. Table opcode `sepTransact` ↔ opération ↔ TAG fil (2026-11-12, Claude — source: kext + traces)

Opcodes **fil EP 0x08** extraits du `mov w1,#imm` **juste avant** l'appel virtuel `sepTransact` (slot +0x9e0), par fonction
appelante (scan `scratchpad/scan_opcodes.py` + lecture du contexte exact ; quelques hits du scan étaient du bruit, écartés).
`sepTransact(w1=opcode, …)` relaie vers le transfert SEP interne (`AppleSEPManager`, `[this+0x170]`). **Statut : hypothèse
(source: kext), partiellement recoupée par les TAGs de `docs/messages.md`.**

Table **complète** (tous les sites `sepTransact` du Mesa, opcode = `mov w1,#imm` remonté jusqu'à 22 instr avant l'appel ;
`scratchpad/scan_opcodes2.py`). ✓ = octet vu dans la sous-séquence de match fil `23 06 65 07 09 1f 22 70 03 21` (messages.md).

| opcode | opération (nom kext) | note / recoupement |
|---|---|---|
| 0x03 | `commandStartEnroll` | ✓ (`…70 03 21`) |
| 0x06 | `forceNoMatch` | ✓ (`23 06 65…`) ; aussi dans `retryMatchAfterHomeButtonPress` |
| 0x07 | `asyncCaptureHandler` / retryMatch (capture) | ✓ (`…07 09…`) |
| 0x08 | `handleEnrollment` | capture d'enrôlement (sortie lue) |
| **0x09** | **`handleMatch` — le match** | ✓ **`<09` = match, 240-356 ms (C3/C8)** |
| 0x0a | `applyPostponedMatch` | match différé |
| 0x0c | `handleMatch` (×2, 1er transact = armement) | — |
| 0x15 | `performKeyExchange` | **clé de session 0x15/0x16 (§4)** |
| 0x19 | `HandleReset` | reset capteur |
| 0x1b | `prepareNotPairedSession` | session (non appairée) |
| 0x1f | `cacheMatchPolicy` | ✓ (`…09 1f 22…`) |
| 0x22 | `asyncCaptureHandler` | ✓ (`…1f 22 70…`) |
| 0x23 | `asyncCaptureHandler` | ✓ (`23 06…` = début de la séquence) |
| 0x24 / 0x30 | `lockRootKeyInSensor` | verrouillage clé racine (2 étapes) |
| 0x28 | `performSpecificCommandGated` / `cacheCaptureData` | — |
| 0x2b | `cacheProtectedConfigurationSpecific` | config protégée |
| 0x36 | `performSpecificCommandGated` | — |
| 0x39 | `cacheSysProtectedConfigurationSpecific` | config système protégée |
| 0x3d | `forceBioLockoutSpecific` | verrouillage biométrique |
| 0x42 | `initializeSequenceCounter` | **compteur 0x42 (§4)** |
| 0x43 | `establishDiffieHellmanSession` | négociation de clé SEP↔capteur |
| 0x49-0x4f, 0x53, 0x76, 0x77 | `seaCookieHandleMessage` | provisioning **usine** (nombreux sous-opcodes) |
| 0x58 / 0x5a | `cacheCaptureData` | — |
| 0x5d | `applySensorParams` | proche patch 0x5f (§4) |
| 0x63 | `setCalibrationData` | — |
| 0x65 / 0x74 | `asyncCaptureHandler` / retryMatch | ✓ (`…65 07…`, et `0x74`) |
| 0x7e | `provisionNavajo` | provisioning capteur Navajo |

**Lecture.** La sous-séquence de match `23 06 65 07 09 1f 22 70 03 21` (relayée dans la transaction `0xfc`) est **nommée à 8/10** :
`0x23`/`0x06`/`0x65`/`0x07`/`0x09`/`0x1f`/`0x22`/`0x03` = opérations `asyncCaptureHandler`/`forceNoMatch`/capture/`handleMatch`/
`cacheMatchPolicy`/`commandStartEnroll`. `0x09` = l'ordre de match. **Restent `0x70` et `0x21`** (non émis par un `sepTransact` Mesa →
sans doute une autre couche : trame mailbox `0x70` = transfert d'image de capture ?, à confirmer). Le driver Linux (phase 2+) devra
émettre cette séquence. **Statut : hypothèse (source: kext), cross-validé par les TAGs fil.**

### 12d. Flot `handleMatch` / `handleEnrollment` — répertoire d'opcodes (2026-11-12, Claude — source: kext)

Désassemblage de `handleMatch` (`0x9794da4`) et `handleEnrollment` (`0x9794468`). **Opcodes `sepTransact` émis** (répertoire sûr ;
**ordre approximatif**, toutes les branches ne sont pas reversées) :
- **`handleMatch`** : `0x0c` (armement) → `0x8001` (récurrent, bit haut = passthrough capteur / capture d'image ?) → `0x1e` →
  `0x14` → une rafale **`0x11 0x12 0x0f 0x10 0x0b 0x0c 0x0d 0x0e`** chacune chronométrée (`mach_absolute_time`) = **lectures de
  sous-résultats / télémétrie** → **`0x09` = le verdict de match** → `0x1b 0x1c 0x22` (finalisation). Résultat dans une structure
  **`match_info_t`** ; logs `"%s: Image matched: %d"`, `"Dirt on sensor detected …"` ; assert `getCommandMode() == kCommandModeMatch`.
- **`handleEnrollment`** : `0x8001` (×3, capture) → `0x1e` → **`0x08` = capture d'enrôlement** → `0x1f` (`cacheMatchPolicy`) → `0x8001`.

Ces opcodes **complètent** la table §12c (ajouts : `0x0b 0x0d 0x0e 0x0f 0x10 0x11 0x12 0x14 0x1c 0x1e`, tous dans le flot de match,
= lectures de sous-résultats ; `0x8001` = opcode à bit haut, probablement « relais capteur »). **Statut : hypothèse (source: kext).**
Pour le driver (phase 2+), le **cœur du match** = armer (`0x0c`) → capturer (`0x8001`) → lire les sous-résultats (`0x0b`–`0x12`) →
demander le verdict (`0x09`) → finaliser (`0x1b/0x1c/0x22`). Payloads exacts et ordre strict = à finir (suivi du flot de données).

## 13. sbio (EP 0x08) — cadre fil : le message `0xfc` et le buffer OOL (2026-11-12, Claude — source: kext)

Comment un opcode `sepTransact` devient un message EP 0x08. Chaîne : `AppleMesaSEPDriver::sepTransact(opcode,…)` →
`AppleSEPGenericTransfer::transact(opcode,…)` (`0x9939900`) → construction du message (`0x9937348`) → doorbell (`0x993a480`).
**Statut : hypothèse (source: kext), recoupé par les traces.**

**`transact` (`0x9939900`)** range, dans l'objet endpoint : l'**opcode** à `+0xa4`, le **pointeur inData** à `+0x80`, l'**inLen**
(32 bits) à `+0x88`, un flag à `+0xac` ; mappe le buffer OOL (`+0x50`) ; puis envoie un message de **type `0xfc`** (`mov w1,#0xfc ;
bl 0x9937348`) et attend la réponse (vérifie que l'opcode renvoyé `+0xa4` == opcode envoyé).

**Construction du mot de message (`0x9937348`, le « 0xfc »)** :
```
tag16   = *(u16*)(obj+0x20); (*(u16*)(obj+0x20))++   // compteur de séquence, +1 par message
data32  = *(u32*)(obj+0x24)
message = (tag16 << 48) | (data32 << 16) | (0xfc << 8) | endpoint
```
→ **bits 8-15 = `0xfc` (type du message GenericTransfer)**, bits 16-47 = DATA (config/longueur OOL), **bits 48-63 = tag (compteur
incrémenté)**, bits 0-7 = endpoint (0x08, posé par la couche doorbell). **L'opcode sbio (0x09, 0x42…) et le payload ne sont PAS dans
ce mot** : ils sont dans le **buffer OOL** pointé par l'objet.

**Recoupement trace (décisif).** C'est exactement le `<fc`/`>fc` des captures (EP 0x08), avec son buffer B hors-ligne. Chaque
`sepTransact(opcode)` = **une transaction `0xfc`** portant un opcode dans l'OOL. La sous-séquence `23 06 65 07 09 1f 22 70 03 21`
observée = **une suite de transactions `0xfc`, une par opcode** (0x23, 0x06, 0x65, 0x07, 0x09=match, 0x1f, 0x22, …). Le tag qui
s'incrémente explique le compteur de TAG vu sur EP 0x08.

**Format OOL = `gt_packet_t`.** `0x993741c` (prépare le transfert) exige `oolBufferSize > sizeof(gt_packet_t)` (`cmp x2,#0x1c` →
buffer > **0x1c = 28 o**), vérifie `context->transfer.state == kGTIdle` et met l'état à 2 (kGTBusy ?). Donc l'OOL commence par un
en-tête **`gt_packet_t`** (**0x1c = 28 o**) écrit par `0x9937570`, puis le payload. Champs décodés (le writer construit l'en-tête
puis `memcpy` le payload à `+0x1c`) :

| offset | champ |
|---|---|
| +0x00 | `kind` = 1 |
| +0x04 | longueur **totale** du transfert |
| +0x08 | `offset` du fragment courant |
| +0x0c | flags (endpoint `+0xac`) |
| +0x10 | 0 (réservé) |
| +0x14 | **opcode** (endpoint `+0xa4` → 0x09 match, 0x42 compteur…) |
| +0x18 | longueur du fragment |
| +0x1c | payload (données de la commande) |

→ **l'opcode sbio est à l'offset `+0x14` du `gt_packet_t`**, dans le buffer OOL (pas dans le mot mailbox). Transfert fragmenté
possible (champs `offset`/`total`/`fragment`), état `kGTIdle`→occupé.

**Pour le driver Linux (phase 2+)** : pour piloter sbio, (1) écrire un `gt_packet_t` (opcode + payload) dans un buffer OOL mappé au
SEP, (2) envoyer un message EP 0x08 `type=0xfc`, `data`=descripteur OOL, `tag`=compteur++, (3) attendre le `0xfc` de réponse (même
tag), (4) lire l'OOL de sortie. **Reste** : champs exacts de `gt_packet_t` (`0x9937570`), et le type `0x70` (vu en trace, probable
transfert d'image en vrac, distinct du `0xfc`) — à finir.

### 13b. VÉRIFICATION du format `gt_packet_t` contre capture (trace c12) — VÉRIFIÉ

Les buffers OOL **EP 0x08** capturés (`traces/20261108-032454_c12-boot-ho/sep.log.ool/*_08_A.bin`) collent **exactement** au
`gt_packet_t` décodé du kext — confirmation par trace (14 buffers A examinés) :
- `+0x00 = 0x01` (kind) sur **14/14** ; `+0x04` (total) == `+0x18` (longueur fragment) ; payload à `+0x1c` de la bonne longueur.
- `+0x14` = opcode, valeurs lues et recoupées avec §4 et la table §12c :
  `0x73` (len 4), **`0x17`** (len 0x10 = **n° de série**, §4), **`0x15`/`0x16`** (len 4 / 0x28 = **clé de session**, `performKeyExchange`),
  **`0x42`/`0x18`** (**compteur**, §4), **`0x5f`** (buffer **16 Ko** = **patch**, §4), `0x5d` (`applySensorParams`), `0x5c`, `0x6a`, `0x31`,
  `0x32`, `0x01`, **`0x1f`** (`cacheMatchPolicy`).
- **Conséquence** : le **format fil sbio est VÉRIFIÉ** (le reste — noms d'opérations — reste `source: kext`). On peut désormais
  **parser l'opcode de n'importe quelle transaction EP 0x08** (= `gt_packet_t.+0x14` du buffer A), et donc nommer toutes les
  transactions `0xfc` d'une capture. Outil d'analyse à ajouter : lecture `gt_packet_t` dans `analysis/`.
