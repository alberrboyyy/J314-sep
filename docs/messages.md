# Table des messages SEP

Format d'un message (doc Asahi) : bits 0-7 endpoint, 8-15 tag, 16-23 type, 24-31 param, 32-63 data.
Direction : `>` AP → SEP, `<` SEP → AP.

Statuts : `connu-doc` (doc publique Asahi / code m1n1 publié), `hypothèse`, `vérifié` (confirmé par expérience).
Source : `doc-asahi`, `m1n1` (code public), `trace:<dossier>`, `kext` (phase 2 uniquement).
Dans les colonnes « Vu » : `Lnnn` = numéro de ligne de `sep.log` de la trace citée ; `uart Lnnn` = ligne de `hv_uart.log`
(log noyau macOS de la même capture). C1 = `traces/20261107-033436_c1-boot`.

**Rien n'est `vérifié` dans ce fichier.** Les rôles supposés sont des interprétations de logs.

## Contrôles de cohérence du découpage de bits (C1, 2026-11-07)

Vu (faits) :
- `uart L776` « EP0 received unsolicited message 0x0000000000290000 » ↔ C1 L35 `< EP=0x00 TYPE=0x29` : la valeur
  64 bits du noyau redonne bien TYPE dans les bits 16-23.
- `uart L1502..L2846` : les 36 lignes « Replied to xART app: 0x… » se rapprochent une à une, par TAG (bits 8-15), d'un
  `> EP=0x13` de C1 (TAG 0x01 → 0x20, croissants). 22/36 sont identiques bit à bit à la valeur reconstruite depuis
  le tracer ; les 14 autres ne diffèrent que sur les bits ≥ 40 (cause inconnue). Script : `analysis/align_uart.py`.
- `uart L1521..L1530` « AppleSEPXART (EP: 19) received unknown SEP request op 29 » ×5 ↔ C1 L106, L111, L115, L119, L120
  `< EP=0x13 TYPE=0x1d` ×5 (0x1d = 29 ; EP 19 = 0x13).
- `uart` « SEP EP n enabled » (L809, 813, 1534, 1539, 1551, 1974, 2168, 2969 : n = 14, 24, 23, 8, 18, 10, 21, 12) ↔ séquences
  CNTL `EP=0x00 TYPE 4/2/5/3 PARAM=n` de C1 (L41, 80, 130, 142, 163, 216, 252, 1554), même ordre (0x13 n'a pas de ligne uart).
Interprété (hypothèse) : le tracer décode correctement les bits 0-39 et le découpage Asahi s'applique à macOS 13.5 ;
le noyau numérote les endpoints en décimal.

## Endpoints

Nom annoncé = DATA ASCII de `< EP=0xFD TYPE=0x00 PARAM=<ep>` (C1 L16-38, L108-124, L161), lu par le tracer (`# epname`).
Tailles CNTL = DATA de `> EP=0x00 TYPE=0x04` / `TYPE=0x05` pour cet endpoint (voir section CNTL).

| EP | Nom annoncé (C1) | FD TYPE 1 DATA (C1) | Tailles CNTL T4 / T5 (C1) | Rôle | Statut | Source |
|----|------------------|---------------------|---------------------------|------|--------|--------|
| 0x00 | `cntl` (L22) | 0x00000000 (L23) | — | propriétés / activation des endpoints | connu-doc (rôle) ; nom : hypothèse | doc-asahi ; trace:C1 |
| 0x08 | `sbio` (L108) | 0x01010101 (L109) | 0x4000 / 0x4000 (L142-149) | authentification biométrique (Touch ID) | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0x0a | `scrd` (L123) | 0x01010101 (L124) | 0x4000 / 0x4000 (L216-223) | credentials utilisateur (probable) | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0x0c | `sse ` (L117) | 0x01010101 (L118) | 0x4000 / 0x4000 (L1554-1561, activé seulement à 03:38:07) | NFC / Apple Pay | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0x0e | `hdcp` (L37) | 0x01010101 (L38) | 0x4000 / 0x4000 (L41-48) | HDCP | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0x10 | `xars` (L25) | 0x02020202 (L26) | aucune séquence CNTL vue | xART setup | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0x12 | `sks ` (L161) | 0x02010201 (L162) | 0x8000 / 0x8000 (L163-172) | Secure Key Store | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0x13 | `xarm` (L28) | 0x02020202 (L29) | 0x8000 / 0x8000 (L91-98) | xART manager (noyau : « AppleSEPXART (EP: 19) ») | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0x14 | `hibe` (L16) | 0x01010101 (L17) | aucune séquence CNTL vue | hibernation | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0x15 | `pnon` (L32) | 0x02020404 (L33) | 0x10000 / 0x8000 (L252-259) | boot policy | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0x17 | `skdl` (L113) | 0x01010101 (L114) | 0x4000 / 0x4000 (L130-137) | kext deny list | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0x18 | `stac` (L19) | 0x02020202 (L20) | 0x8000 / 0x8000 (L80-87) | trusted accessory | connu-doc (rôle) | doc-asahi ; trace:C1 |
| 0xFD | (découverte) | — | — | liste des endpoints + tailles OOL | connu-doc | doc-asahi ; m1n1 hw/sep.py |
| 0xFE | Boot254 | — | — | boot SEPOS / mémoire partagée | connu-doc | doc-asahi ; m1n1 |
| 0xFF | Boot255 | — | — | ROM de boot SEP | connu-doc | doc-asahi ; m1n1 |

Vu : les 12 noms annoncés dans C1 correspondent exactement aux 12 endpoints listés par la doc Asahi (aucun en plus,
aucun en moins). Les annonces 0xFD sont toutes `<` (SEP→AP) ; aucune requête `> EP=0xFD` n'est tracée.
Interprété (hypothèse, 2 cas discriminants seulement : 0x15 et 0x12) : FD TYPE 1 DATA = 4 octets de tailles en unités
de 0x4000 ; l'octet 1 = taille T4, l'octet 3 = taille T5 (0x15 : octets 04/04/02/02 ↔ 0x10000/0x8000 ; 0x12 :
01/02/01/02 ↔ 0x8000/0x8000). Sens des octets 0 et 2 inconnu.

## Messages

| EP | Dir | Tag | Type | Param | Data | Vu (C1) | Rôle supposé | Statut | Source | Date |
|----|-----|-----|------|-------|------|---------|--------------|--------|--------|------|
| 0x13 | > | — | 0x0 | 0x0 | 0x100 | voir note 0x13 | fetch d'un locker (gigalocker init) | connu-doc | doc-asahi | — |
| 0x13 | < | — | 0x5 | 0x10 | — | L125, L190, L192… | succès fetch/unwrap locker | connu-doc | doc-asahi | — |
| 0x13 | < | — | 0x7 | 0x10 | — | non vu dans C1 | erreur (ex. locker utilisateur introuvable) | connu-doc | doc-asahi | — |
| 0x18 | > / < | 0xfc | 0xf | 0x0 | 0x0 | L88 / L89 | ping / pong (C1 : TAG=0xfc des deux côtés) | connu-doc | doc-asahi ; trace:C1 | 2026-11-07 |

### Boot ROM (0xFF / 0xFE) — C1 L3-L14, 03:34:47–03:34:48

| EP | Dir | Tag | Type | Param | Data | Vu (C1) | Rôle supposé | Statut | Source | Date |
|----|-----|-----|------|-------|------|---------|--------------|--------|--------|------|
| 0xFF | > | 0x00 | 0x1b | 0 | 0 | L3 | inconnu (absent de m1n1 hw/sep.py) | hypothèse | trace:C1 | 2026-11-07 |
| 0xFF | < | 0x00 | 0x7f | 0 | 0 | L4 | réponse à 0x1b (inconnue) | hypothèse | trace:C1 | 2026-11-07 |
| 0xFF | > | 0x01 | 0x02 | 0 | 0 | L5, L9 | GET_STATUS | connu-doc | m1n1 BootRomMsg | 2026-11-07 |
| 0xFF | < | 0x01 | 0x66 | 0 | 1 puis 2 | L6, L11 | STATUS_OK ; DATA = 1 puis 2 (état ?) | connu-doc (type) ; DATA : hypothèse | m1n1 ; trace:C1 | 2026-11-07 |
| 0xFF | > | 0x01 | 0x05 | 0 | 0 | L7 | BOOT_TZ0 | connu-doc | m1n1 | 2026-11-07 |
| 0xFF | < | 0x01 | 0x69 | 0 | 0 | L8 | BOOT_TZ0_DONE (noyau : « SEP accepted Tz0 », uart L587) | connu-doc | m1n1 | 2026-11-07 |
| 0xFF | < | 0x00 | 0xd2 | 0 | 2 | L10 | BOOT_UNK_DONE (m1n1) ; DATA=2 ↔ « SEP status: 2 » (uart L611) ? | connu-doc (type) ; lien uart : hypothèse | m1n1 ; trace:C1 | 2026-11-07 |
| 0xFF | > | 0x01 | 0x06 | 0 | 4 | L12 | BOOT_IMG4 ; DATA=4 (m1n1 met l'IOVA du firmware >> 12) | connu-doc (type) | m1n1 | 2026-11-07 |
| 0xFE | > | 0x01 | 0x1c | 0 | 0x580 | L13 | mémoire partagée : 0x580 << 12 = 0x580000 = « Shmbuf for SEP: slave addr = 0x580000 » (uart L614). m1n1 utilise TYPE 0x18 (SET_SHMEM), macOS 0x1c | hypothèse | trace:C1 ; m1n1 | 2026-11-07 |
| 0xFF | < | 0x01 | 0x6a | 0 | 0 | L14 | BOOT_IMG4_DONE (« SEP accepted IMG4 », uart L669) | connu-doc | m1n1 | 2026-11-07 |

### CNTL (0x00) — C1 L34-L259, L1554-L1561

| EP | Dir | Tag | Type | Param | Data | Vu (C1) | Rôle supposé | Statut | Source | Date |
|----|-----|-----|------|-------|------|---------|--------------|--------|--------|------|
| 0x00 | < | 0x00 | 0x0d | 0 | 0 | L34 (1 fois) | spontané, inconnu | hypothèse | trace:C1 | 2026-11-07 |
| 0x00 | < | 0x00 | 0x29 | 0 | 0 | L35 (1 fois) | spontané ; le noyau le déclare « unsolicited » (uart L776) | hypothèse | trace:C1 | 2026-11-07 |
| 0x00 | < | 0x00 | 0x10 | 0 | 0 | L76 (1 fois) | spontané, inconnu | hypothèse | trace:C1 | 2026-11-07 |
| 0x00 | > / < | 0x08 | 0x14 → 0x01 | 0 | 0 → 3 | L39 / L40 (1 fois) | requête d'info ; réponse DATA=3 (version ?) | hypothèse | trace:C1 | 2026-11-07 |
| 0x00 | > | 0x07 | 0x04 | ep | taille | 9 endpoints (ex. L41, L142) | taille buffer n°1 de l'endpoint `ep` (0x4000/0x8000/0x10000) | hypothèse | trace:C1 | 2026-11-07 |
| 0x00 | > | 0x07 | 0x02 | ep | n | ex. L43 (0x14), L144 (0x64) | adresse buffer n°1 en pages de 4 Kio (voir note CNTL) | hypothèse | trace:C1 | 2026-11-07 |
| 0x00 | > | 0x07 | 0x05 | ep | taille | ex. L45, L146 | taille buffer n°2 | hypothèse | trace:C1 | 2026-11-07 |
| 0x00 | > | 0x07 | 0x03 | ep | n | ex. L47 (0x1c), L148 (0x6c) | adresse buffer n°2 en pages de 4 Kio | hypothèse | trace:C1 | 2026-11-07 |
| 0x00 | < | 0x07 | 0x01 | 0 | = DATA reçu | après chaque 4/2/5/3 (36 fois) | acquittement : renvoie la DATA reçue | hypothèse | trace:C1 | 2026-11-07 |

Note CNTL — vu sur les 9 endpoints : DATA(T3) = DATA(T2) + T4/0x1000 + 4, et DATA(T2 suivant) = DATA(T3) + T5/0x1000 + 4
(0x14→0x1c→0x24→0x30→0x3c→0x48→0x54→0x5c→0x64→0x6c→0x74→0x80→0x8c→0x94→0x9c→0xb0→0xbc→0xc4, sans exception).
Interprété : deux buffers OOL par endpoint, alloués à la suite en pages de 4 Kio avec 4 pages d'écart ; lequel est
« entrée » ou « sortie » : inconnu. La base (page 0x14) n'est reliée à aucune adresse connue.

### SBIO (0x08) — structures récurrentes

Vu sur les 224 messages EP 0x08 de C1 (regroupement : `analysis/sbio_transactions.py`) :
- **Paires 0xfc** : chaque `> TAG=0xfc TYPE=X` est suivi de `< TAG=0xfc TYPE=X` (aucune exception, aucune
  commande en suspens). Dans **tous** les messages 0xfc, PARAM=0 et DATA=0 : l'argument et le résultat, s'il y en a,
  ne passent pas par le mot mailbox.
- **Fragments 0xfe/0xfd**, même TYPE que la commande, deux variantes :
  - « pendant » (SEP commence) : `< 0xfe DATA=0`, `> 0xfd DATA=0x10000`, `< 0xfe DATA=0x10000`, `> 0xfd DATA=0x20000`…,
    puis le `< 0xfc` final : TYPE 0x5b (L355-362, 3 tours), 0x6d (L423-431, 2 tours), 0x65 (L1113-1116, 1 tour).
  - « après » (AP commence, après le `< 0xfc` final) : `> 0xfe DATA=0`, `< 0xfd DATA=0x10000`… : TYPE 0x5f (L335-336,
    L379-380, 1 tour), 0x6c (L1230-1233, 2 tours ; finit sur un `< 0xfd` sans 0xfc derrière).
  - Celui qui envoie 0xfe porte k·0x10000, l'autre répond 0xfd avec (k+1)·0x10000.
  Interprété (hypothèse, concurrente de la revue sceptique HA) : transfert en plusieurs morceaux d'un contenu plus grand
  que le buffer OOL, ou simple poignée de main sur un buffer partagé ; rien ne permet de trancher (OOL invisible).
- **Messages hors 0xfc** (TAG 0x01..0x04, 0x26) : listés ligne par ligne ci-dessous. 0x01/0x02 portent DATA=0x1f5.

Interprété : TYPE = numéro de commande sbio (hypothèse ; voir HA dans `docs/hypotheses.md`). DATA=0x1f5 = 501 ; le noyau
écrit `session_uid = 1f5` (uart L2707, L2982) et parle de « special bag -501 » (uart L2677) : 501 est l'uid de l'utilisateur
macOS (hypothèse HB). 0x1f5 apparaît dès L428 (03:35:22), **avant** le login mot de passe (03:36:12, voir c1_report).

### SBIO (0x08) — commandes TAG 0xfc (requête `>` et réponse `<` de même forme : PARAM=0, DATA=0)

Phases (voir `analysis/out/c1_report.md`) : init1 = L320-449 (03:35:22) ; init2 = L466-524 (03:35:25-26) ;
login = L681-710 (03:36:13-14) ; lock→unlock = L1042-1145 (03:36:58–03:37:00) ; post-unlock = L1224-1247 (03:37:15-16).

| EP | Dir | Tag | Type | Param | Data | Vu (C1) | Rôle supposé | Statut | Source | Date |
|----|-----|-----|------|-------|------|---------|--------------|--------|--------|------|
| 0x08 | > / < | 0xfc | 0x73 | 0 | 0 | L320/L322 (1×, 1re commande sbio ; `< TAG=0x04` L321 au milieu) | ouverture / hello | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x17, 0x15, 0x16, 0x42, 0x18 | 0 | 0 | L323-332 et L367-376 (2× chacune, même ordre) | init, répétée deux fois (deux capteurs/clients ? noyau : « Found SandDollarFamily » ×2, « loaded patch vers=22 » ×2, uart L910-912, L2275-2276) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x5f | 0 | 0 | L333-334, L377-378 (2×) + fragments « après » | init, lecture d'un bloc ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x5d, 0x5c, 0x6a | 0 | 0 | L337-342, L382-388 (2× chacune) | init | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x31, 0x32 | 0 | 0 | L343-346, L351-354, L391-394 (3× chacune, toujours en paire 0x31 puis 0x32) | init | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x01 | 0 | 0 | L347, L395 (2×) | init | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x1f | 0 | 0 | L349, L397 (init1) ; L1128 (après 0x09, unlock) | ? (vu à l'init et à l'unlock) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x5b | 0 | 0 | L355-362 (1×, 37 ms, 3 tours de fragments « pendant ») | gros transfert à l'init (patch capteur ? cf. uart L2275 « loaded patch vers=22 », entre ancrages L242 et L452) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x63 | 0 | 0 | L363, L399, L401 (init1) ; L477, L481 (init2) — ~3 ms chacune | ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x19, 0x6f, 0x39, 0x54, 0x6e, 0x7a | 0 | 0 | L365, L389, L411, L438, L446, L448 (1× chacune, init1) | init (une seule occurrence : coïncidence possible) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x6b, 0x79 | 0 | 0 | 0x6b : L405, 413, 417, 434, 1224 ; 0x79 : L407, 415, 419, 436, 1226 (toujours 0x6b puis 0x79) | lecture d'état / liste ? (init1 et post-unlock) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x6d | 0 | 0 | L409-410 ; L423-431 (fragments « pendant » + notifications L428-430) | init ; la 2e occurrence déclenche les 1res notifications 0x1f5 | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x7c | 0 | 0 | L403, L471, L475 (init), L1049 (après lock), L1858 (03:38:43) | ? (réparti dans toute la capture) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x2b | 0 | 0 | 9× : L432, 440, 485, 495, 507 (init) ; L681 (login) ; L1059, 1073, 1105 (après lock) | ? (le plus fréquent) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x33, 0x36 | 0 | 0 | 0x33 : L442, L1236 ; 0x36 : L444, L1057, L1071, L1238 | ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x71 | 0 | 0 | L466-468 (1× ; notification `< 0x01 TYPE=0x11` L467 au milieu) | ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x28 | 0 | 0 | L469 (1×) | ? (même valeur que la notification 0x01/0x28, lien non établi) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x7d | 0 | 0 | L523 (init2), L1087 (après lock) | ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x0b | 0 | 0 | L566 (03:35:32), L1133 (unlock) | ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x70 | 0 | 0 | L701, L708 (login, chacune juste après une notif 0x01/0x28) ; L1137-1142 (unlock, 194 ms, suivie de `< TAG=0x03` L1143) | réaction à un passage « déverrouillé » ? (vu aux 2 déverrouillages, 3 occurrences) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x23, 0x06, 0x65, 0x07 | 0 | 0 | L1109, L1111, L1113 (+fragments), L1117 (1× chacune, unlock ; 0x23 = 6 ms, 0x07 = 19 ms) | préparation de la comparaison doigt ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x09 | 0 | 0 | L1119→L1126 (1×, 241 ms ; notif `0x01/0x08` L1125 avant la réponse, une 2e L1127 après) ; le message SKS « handle -501 » (L1124) tombe pendant | candidat principal « match Touch ID » (une seule occurrence) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x22, 0x21 | 0 | 0 | L1131, L1144 (1× chacune, unlock) | fin de séquence d'authentification ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x6c | 0 | 0 | L1228 (+fragments « après » L1230-1233), L1240 (post-unlock, 03:37:15) | transfert après unlock (mise à jour de gabarit ?) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x37 | 0 | 0 | L1234 (6 ms), L1242→L1247 (382 ms) (post-unlock) | ? (la plus longue commande sbio vue) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc | 0x40 | 0 | 0 | L1856 (1×, 03:38:43, suivie de 0x7c) | ? | hypothèse | trace:C1 | 2026-11-07 |

### SBIO (0x08) — messages hors 0xfc

| EP | Dir | Tag | Type | Param | Data | Vu (C1) | Rôle supposé | Statut | Source | Date |
|----|-----|-----|------|-------|------|---------|--------------|--------|--------|------|
| 0x08 | < | 0x04 | 0x00 | 0 | 0 | L321 (1×, pendant la 1re commande 0x73) | événement « prêt » ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | < | 0x01 | 0x15 | 0 | 0x1f5 | L428 (1×, pendant 0x6d) | notification liée à l'uid 501 | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | < | 0x01 | 0x55 | 0 | 0x1f5 | L429 (1×, pendant 0x6d) | idem | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | < | 0x02 | 0x01 | 0 | 0x1f5 | L430 (1×, pendant 0x6d) | idem (TAG 0x02 : autre classe ?) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | < | 0x01 | 0x11 | 0 | 0x1f5 | L467 (pendant 0x71), L510 (juste après `> TAG=0x26`), L693 (login) — 3× | notification d'état pour 501 | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | > | 0x26 | 0x00 | 0 | 0x1f5 | L509 (1×, seul message AP→SEP hors 0xfc/0xfe/0xfd) | l'AP signale l'uid 501 au SEP ? (entre ancrages L454 et L550 ; même fenêtre que « BIO DROPPED … forcedBioRestrictionReason=2 », uart L2296) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | < | 0x01 | 0x28 | 0x02 | 0x1f5 | L699, L705 (login, chacune suivie de `> 0xfc 0x70`) | « session/keybag 501 déverrouillé » ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | < | 0x01 | 0x09 | 0x02 | 0x1f5 | L1042 (1×, 03:36:58.35, ~2-3 s après le lock, pendant l'écran verrouillé) | événement après lock (armement ? doigt détecté ?) | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | < | 0x01 | 0x08 | 0x02 | 0x1f5 | L1125 (pendant 0x09), L1127 (après) — 2× | résultat de la comparaison ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x08 | < | 0x03 | 0x00 | 0 | 0 | L1143 (1×, fin de 0x70 à l'unlock) | fin d'opération ? | hypothèse | trace:C1 | 2026-11-07 |

### SKS (0x12) — structure (aperçu, C1)

| EP | Dir | Tag | Type | Param | Data | Vu (C1) | Rôle supposé | Statut | Source | Date |
|----|-----|-----|------|-------|------|---------|--------------|--------|--------|------|
| 0x12 | > | t | n | 0 | 0xLLLL0000 | 579 requêtes, L174… | TAG = commande ; TYPE = compteur de transaction (+1 à chaque requête, 3 écarts sur 579) ; bits 48-63 = longueur ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x12 | < | t\|0x80 | n | s | 0xLLLL0000 ou 0 | 579 réponses, toutes appariées (TAG\|0x80, même TYPE) | réponse ; PARAM≠0 (0xfd ×53, 0xfb ×5, 0xff, 0xfe, 0xed) toujours avec DATA=0 → code d'erreur ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x12 | < | 0x00 | v | p | handle (int32) | L550, L639, L641, L697, L1124, L1624 | notification de changement d'état d'un keybag : DATA = « handle » du noyau, 5/5 correspondances (L550 ↔ uart L2332-2333 ; L639 ↔ L2615-2616 ; L641 (-6) ↔ L2619 ; L697/L1124 (-501) ↔ L2679 / L2784 ; L1624 ↔ L2987-2988) ; PARAM=1 pour les volumes (« Unlock notification for volume »), 0 sinon ; TYPE=1 en L697, 0 ailleurs | hypothèse | trace:C1 | 2026-11-07 |
| 0x12 | < | 0x09 | 0 | 0 | 0 | L640, L1619 (2×, chaque fois à côté d'une notification de volume) | ? | hypothèse | trace:C1 | 2026-11-07 |

### xART (0x13) — remarque sur la table doc-asahi

Vu (C1) : sous macOS 13.5, les échanges 0x13 commencent côté SEP : `< TAG=t TYPE=op …` puis `> TAG=t TYPE=0x00 …`
(ex. L125/L129 ; L237/L238). Le noyau les traite comme des requêtes du SEP (« _handle_sep_driven_msg … Replied to xART
app »). Pour `TYPE=0x01 PARAM=0x53|0x9c` et `TYPE=0x06`, DATA>>16 = CRC affiché par le noyau « Saving … with CRC »
(L237 ↔ uart L1992 ; L1122 ↔ L2781 ; L1140 ↔ L2791 ; L1243 ↔ L2841 ; L1245 ↔ L2844…). `TYPE=0x1d` (op 29) porte un nom
d'endpoint en ASCII (PARAM + DATA, ex. L106 `sbio`). Les lignes doc-asahi (`> TYPE 0`, `< TYPE 5/7 PARAM 0x10`) décrivent
donc un sens qui n'est pas celui observé ici : à revoir (hypothèse : la doc décrit l'usage depuis m1n1/Linux).
