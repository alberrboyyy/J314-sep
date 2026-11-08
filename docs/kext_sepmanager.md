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
