# Table des messages SEP

Format d'un message (doc Asahi) : bits 0-7 endpoint, 8-15 tag, 16-23 type, 24-31 param, 32-63 data.
Direction : `>` AP → SEP, `<` SEP → AP.

Statuts : `connu-doc` (doc publique Asahi / code m1n1 publié), `hypothèse`, `vérifié` (confirmé par expérience).
Source : `doc-asahi`, `m1n1` (code public), `trace:<dossier>`, `kext` (phase 2 uniquement).
Dans les colonnes « Vu » : `Lnnn` = numéro de ligne de `sep.log` de la trace citée ; `uart Lnnn` = ligne de `hv_uart.log`
(log noyau macOS de la même capture). C1 = `traces/20261107-033436_c1-boot`. C3 = `traces/20261107-035930_c3-touchid`
(rapport : `analysis/out/c3_report.md`, tentatives : `analysis/out/c3_lock_cycles.txt`).

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
| 0x08 | > / < | 0xfc | 0x09 | 0 | 0 | L1119→L1126 (1×, 241 ms ; notif `0x01/0x08` L1125 avant la réponse, une 2e L1127 après) ; le message SKS « handle -501 » (L1124) tombe pendant | candidat principal « comparaison Touch ID » ; **C3 : 20 occurrences**, 240-245 ms quand suivie d'un UNLOCKED (8×), 296-356 ms sinon (12×) — voir section C3 | hypothèse | trace:C1 ; trace:C3 | 2026-11-07 |
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
| 0x08 | < | 0x01 | 0x09 | 0x02 | 0x1f5 | L1042 (1×, 03:36:58.35, ~2-3 s après le lock, pendant l'écran verrouillé) | événement après lock (armement ?) ; **reproduit 10/10 verrouillages dans C3**, sans doigt (voir section C3) | hypothèse | trace:C1 ; trace:C3 | 2026-11-07 |
| 0x08 | < | 0x01 | 0x08 | 0x02 | 0x1f5 | L1125 (pendant 0x09), L1127 (après) — 2× | résultat « correspondance » ? **C3 : 2× dans chacun des 8 succès, 0 dans les 12 échecs** ; mais aussi 1× au déverrouillage mot de passe après blocage (C3 L5724) | hypothèse | trace:C1 ; trace:C3 | 2026-11-07 |
| 0x08 | < | 0x03 | 0x00 | 0 | 0 | L1143 (1×, fin de 0x70 à l'unlock) | fin d'opération ? | hypothèse | trace:C1 | 2026-11-07 |

### SBIO (0x08) — C3 : lock, tentatives doigt, déverrouillage (C3 = `traces/20261107-035930_c3-touchid`)

Vu : macOS a verrouillé 10 fois après le login (uart L3032 … L4978) et déverrouillé 8 fois au doigt, 2 fois au mot de passe.
Les marques de `marks.txt` sont décalées par rapport aux actions (voir rapport §0) : les lignes ci-dessous sont rattachées aux
états `LOCKED/UNLOCKED now=` de hv_uart, pas aux marques. Notation : `xx` = paire `> 0xfc TYPE=xx` / `< 0xfc TYPE=xx`
(PARAM=0, DATA=0).

| EP | Dir | Tag | Type | Param | Data | Vu (C3) | Rôle supposé | Statut | Source | Date |
|----|-----|-----|------|-------|------|---------|--------------|--------|--------|------|
| 0x08 | < puis > / < | 0x01 puis 0xfc | `<01/09` puis `2b 2b 7d 2b` | 0x02 / 0 | 0x1f5 / 0 | 10/10 verrouillages, `<01/09` à [−0.3 ; +2.3] s du `now=` (L1362, 2024, 2292, 2510, 2760, 3176, 3918, 4362, 4608, 5173), `2b…` ~0.6 s après (1er lock : `2b 36 2b 7d 2b`, L1405-1452) ; 2e `<01/09` à +10.6 s si l'écran reste verrouillé (L1464, L4714, L3462) ; C1 L1042 + L1049-1106 | « écran verrouillé, capteur armé » ; **reproduit 10 fois dans c3**, sans doigt (fenêtre 616-646 sans 0x23) | hypothèse | trace:C3 ; trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc + notifs | `23 06 65(<fe 0, >fd 0x10000) 07 09 [<01/08 P2] <fc09 [<01/08 P2] 1f 22 0b 70 <03 21` | — | — | 25 messages identiques bit à bit (dir/TAG/TYPE/PARAM/DATA) : L2147, 2391, 2602, 2861, 3553, 4109, 4461, 4966 et C1 L1109 ; chacun suivi d'UNLOCKED ≤ 2 s ; notif SKS `TAG=0x00 DATA=0xfffffe0b` pendant 0x09 (L2160, 2404, 2622, 2874, 3567, 4122, 4474, 4980) | déverrouillage Touch ID réussi ; **reproduit 8 fois dans c3** (+1 C1) ; absent des 2 déverrouillages mot de passe (L1675-1729, L5721-5760) et de 30 s de lock sans doigt | hypothèse | trace:C3 ; trace:C1 | 2026-11-07 |
| 0x08 | > / < | 0xfc + notifs | `23 06 65 07 09 <fc09 1f 22 70 <03 21` | — | — | 12× : L3281, 3340, 3495, 3526, 4861, 4888, 4927, 5264, 5338, 5363, 5394, 5418 ; jamais suivi d'UNLOCKED. Diffère du succès par : pas de `<01/08`, pas de `0b`, 0x09 = 296-356 ms, pas de notif SKS -501, `<03` ~0.3-0.4 s après la fin de 0x70 | tentative doigt rejetée ; **reproduit 12 fois dans c3** ; doigt utilisé inconnu (marques peu fiables) | hypothèse | trace:C3 | 2026-11-07 |
| 0x08 | > / < | 0xfc | `23 06 65 07 22` | 0 | 0 | 2× : L4915, L4954 (28-29 ms, pas de 0x09), suivis 80 ms après d'une tentative complète | tentative abandonnée (acquisition inexploitable ?) | hypothèse | trace:C3 | 2026-11-07 |
| 0x08 | < | 0x01 | 0x45 | 0x00 | 0x1f5 | L5432, L5433, L5435 (pendant 0x09 du 5e échec consécutif, à la place des `<01/08`), L5504 (1111.2, +10.6 s après le `<01/09` L5173) ; 4× dans **un seul** cycle de verrouillage | « trop d'échecs, biométrie bloquée » ? (un seul cycle : coïncidence possible) ; déverrouillage ensuite au mot de passe | hypothèse | trace:C3 | 2026-11-07 |
| 0x08 | > / < | 0xfc | `6b 79 6c(2 tours) 37 33 36 6c 37` | 0 | 0 | ~15-16 s après chaque unlock doigt resté déverrouillé (L2734, 2998, 3758, 4334, 4582 : 5/5) ; L5813 6 s après l'unlock mot de passe post-blocage (s'arrête après 0x33) ; absent après pw_unlock ; C1 L1224 | tâche post-déverrouillage (mise à jour de gabarit ?) ; **reproduit 5 fois dans c3** | hypothèse | trace:C3 ; trace:C1 | 2026-11-07 |
| 0x08 | < puis > / < | 0x01 puis 0xfc | `<01/28 P2` → `70`, deux fois | 0x02 | 0x1f5 | login L701-713, pw_unlock L1677-1711, pw_after_bad L5723-5760 ; aussi dans les succès doigt via `70` | réaction au déverrouillage (commun mot de passe / doigt) ; **reproduit 3 fois dans c3** (+ C1 login) | hypothèse | trace:C3 ; trace:C1 | 2026-11-07 |
| 0x08 | — | — | aucun message | — | — | fp_prelogin (457.7-472.1) et idle1 : 0 message EP 0x08 de L585 à L683 ; fp_noprompt (1163.8-1193.8) : 0 message après L5826 | doigt sans demande de macOS → aucun trafic mailbox SBIO | hypothèse | trace:C3 | 2026-11-07 |

### SBIO (0x08) — C8 : contenu OOL des tentatives doigt (C8 = `traces/20261108-004657_c8-doigt-ool`)

Capture : SEP_OOL_EPS=0x08, lectures 0x400 (types complets 0x09,0x21,0x45,0x54,0x5b,0x5f,0x65,0x6d), `>` lit le buffer A,
`<` lit le buffer B (split_dir=1). Résultats rapportés par Albert (notes.txt) : fp_good_1/2/3 déverrouillé, fp_bad_1/2 refusé.
Sorties : `analysis/out/c8_attempts.txt` (séquences vs C3), `c8_ool_attempts.txt` (comparaison octet par octet),
`c8_ool_index.txt` (lecture OOL ↔ message), `c8_latency.txt`, `c8_payloads/` (charges recollées) ; C6 refait avec le même
outil : `c6_ool_attempts.txt`, `c6_payloads/` (C6 = `traces/20261107-043828_c6-doigt-ool`, 5 tentatives 0x09 bon doigt
**refusées**). Offsets ci-dessous = offsets dans la **charge** (après l'en-tête de 0x1c octets), sauf mention.
Rappel : chaque dump est un instantané pris quand le tracer voit le mot mailbox ; l'association A = AP→SEP, B = SEP→AP
reste une hypothèse (cohérente avec tout C8).

**En-tête OOL — VU** sur les 480 lectures EP 0x08 de C8 (et C5/C6/C7) : u32 LE `+0x00`=1 (0 si buffer remis à zéro),
`+0x04` = longueur totale, `+0x08` = offset du morceau (0, 0x3fe4, 0x7fc8, 0xbfac = k·0x3fe4, seulement dans les
`0xfd`), `+0x0c`=`+0x10`=0, `+0x14` = TYPE du mot mailbox (428/435 lectures 0xfc/0xfd/0xfe non nulles ; les 7 autres sont `changed=none`, buffer pas
encore réécrit : 5× `< B 0xfe/0x65` avec l'en-tête 0x06 précédent, L1684…, et 2× `> A 0x70` avec l'en-tête 0x21, L3836, L3866),
`+0x18` = longueur du morceau (≤ 0x3fe4 = 0x4000−0x1c), charge à `+0x1c`. Fin du contenu non nul = 0x1c + longueur, sans
exception. Les 35 notifications EP 0x08 (`<01/xx`, `<02/01`, `<03/00`, `<04/00`) n'ont **pas** de contenu propre visible : B y est nul,
identique au B précédent, égal au début de la réponse 0xfc qui suit (`<01/08` L2426→L2428, L2997→L2999) ou réduit
à l'en-tête vide de la commande en cours (L325, L536, L584).
Interprété : enveloppe commune de la couche de transport sbio ; les 0xfe/0xfd sont des morceaux d'une même charge.

| EP | Dir | Tag | Type | Param | Data | Vu (C8, OOL) | Rôle supposé | Statut | Source | Date |
|----|-----|-----|------|-------|------|--------------|--------------|--------|--------|------|
| 0x08 | > / < | 0xfc+notifs | séquence 25 messages | — | — | identique bit à bit à C3 L2147 (dir/TAG/TYPE/PARAM/DATA) pour fp_good_2 (L2399-2485) et fp_good_3 (L2968-3054) ; fp_good_1 (L1698-1784) : mêmes 25 mots, `<03/00` (L1750) arrivé **avant** `<fc 70` (L1780) au lieu d'après | succès Touch ID (C3 : 8× ; C8 : 3/3) | hypothèse | trace:C8 ; trace:C3 | 2026-11-08 |
| 0x08 | > / < | 0xfc | `23 06 65 07 22` | 0 | 0 | 3× avant un succès : L1674 (fp_good_1), L2351 et L2375 (fp_good_2), 38-44 ms, pas de 0x09 ; C6 L1791 | tentative abandonnée par l'AP après 0x07 | hypothèse | trace:C8 ; trace:C6 ; trace:C3 | 2026-11-08 |
| 0x08 | > / < | 0xfc | `23 06 65 07 09 1f 22 70 [2b] <03 21` | 0 | 0 | 3 essais mauvais doigt : L3621, L3687 (fp_bad_1), L4217 (fp_bad_2) ; = séquence échec de C3, avec en plus `2b` entre `<fc 70` et `<03` dans 2/3 (L3675, L4271) ; pas de `<01/08`, pas de `0b`, pas de notif SKS `TAG=0 DATA=0xfffffe0b` (présente pendant 0x09 dans les 3 succès : L1728, L2424, L2995) | refus | hypothèse | trace:C8 | 2026-11-08 |
| 0x08 | > | 0xfc | 0x06 | 0 | 0 | A : charge 0xa7 octets (9/9). `+0x40..+0x4b` différent à chaque tentative et **recopié** dans la réponse 0x07 à `+0x44` (9/9) ; `+0x97..+0xa6` (16 octets, entropie haute) identiques dans toutes les tentatives d'un même verrouillage, différents d'un verrouillage à l'autre (5 verrouillages) ; `+0x40` u32 différent à chaque tentative (croissant dans C6, pas dans C8) ; `+0x44` u32 = 4 (6 tentatives lock_g*) / 5 (3 tentatives lock_b*) ; C6 : 1 (6/6) ; `+0x48` u32 = nombre d'abandons depuis la dernière tentative complète du même verrouillage (C8 : 0,1 / 0,1,2 / 0 / 0,0 / 0 ; C6 : 0,1,0,0,0,0 — 15/15) et `+0x07` = 1 si `+0x48`=0, 0 sinon (15/15) | paramètres de session de capture (nonce par verrouillage ?) ; fixés par l'AP **avant** la comparaison | hypothèse | trace:C8 | 2026-11-08 |
| 0x08 | > | 0xfc/0xfd | 0x65 | 0 | 0 / 0x10000 | A : 0x7200 octets en 2 morceaux (0x3fe4 + 0x321c), 9/9 ; 12 blocs de 0x980 octets, chacun = 0x17 octets d'en-tête `80 52 NN 80 09 00 00 3a 80 00…00 22 33 15 06 SS SS 00 09 57` + 0x969 octets à entropie ~8 bits/octet (sur 0x7200 : 7.99). NN = index de bloc qui continue après un abandon (0x00-0x0b puis 0x0c-0x17, 0x18-0x23) et repart à 0 après une tentative complète (C8 6/6, C6 4/4) ; SSSS (big-endian) +1 par bloc sur toute la capture, aucun saut après un abandon (C8 3/3, C6 1/1), saut après chaque tentative complète : +0xd dans C8 (6/6), +0x18 dans C6 (4/4) ; corps incompressible (zlib 9 : ratio 1.001) | données capteur AP→SEP ; corps **chiffré ou compressé** (non interprété) | hypothèse | trace:C8 | 2026-11-08 |
| 0x08 | < | 0xfc | 0x07 | 0 | 0 | B : 0xc0 octets (9/9 + C6 6/6). `+0x06..+0x07` = `01 01` dans les 11 tentatives suivies de 0x09 (C8 6, C6 5), `00 00` dans les 4 abandons (C8 L1692, L2369, L2393 ; C6 L1791) ; `+0x02` = 2 dans 4/4 abandons, 0 dans 10/11 autres (3 pour L2417) ; `+0x18..` : groupes de 4 octets qui, lus en float32 LE, donnent 0.014-0.16 (et +inf `0000807f` 2× dans C6) ; `+0x28` = 1 dans les 3 mauvais doigts, 0 ailleurs (C8+C6) ; recopie de `+0x18..+0x5f` dans la réponse 0x09 à `+0xc37` (8/8 échecs C8+C6 ; quelques octets diffèrent dans les 3 succès) | résultat de l'acquisition (qualité ?) qui décide abandon/comparaison ; `+0x28` = indice lié au doigt (3 essais seulement : coïncidence possible) | hypothèse | trace:C8 ; trace:C6 | 2026-11-08 |
| 0x08 | < | 0xfc | 0x09 | 0 | 0 | B : 0xca2 octets dans les 6 tentatives (et C6 5/5). **Succès (3/3)** : `+0x00` u32 = 0x1f5 ; `+0x04..+0x13` = 16 octets `fe6003d8 cea5414f b48a0338 dc7c371b` (identiques 3/3) ; `+0x1c`=1 ; `+0x2c..+0xc1f` (0xbf4 octets) = **la réponse 0x54 de l'init** (L556), 0 octet différent pour fp_good_1, 20 octets différents (mêmes offsets) pour fp_good_2/3. **Échec (3/3 C8 + 5/5 C6)** : `+0x00` = 0xffffffff, `+0x04..+0x1f` = 0, `+0x24` u16 = 0xffff, `+0x40..+0xbff` entièrement nul. Commun : `+0x20` u32 = 0x00040c08, `+0xc20` = 0xffffffff, `+0xc8e` = 0x1f5. `+0xc24` u32 : succès 2, 2, 1 ; mauvais doigt 0x2e ×3 ; C6 bon doigt refusé 5, 5, 0x1b, 6, 0x1b. Entropie faible partout (≤ 3.3 bits/64 o) | résultat de la comparaison : uid + identifiant (16 o) + enregistrement 0x54 si correspondance, -1 et zéros sinon ; `+0xc24` = code/raison ou score (pas un simple booléen : 1 et 2 pour des succès) | hypothèse | trace:C8 ; trace:C6 | 2026-11-08 |
| 0x08 | < | 0xfc | 0x21 | 0 | 0 | B : 0xc8e octets (6/6). = préfixe 12 o (`01 00 | 01 00 | f5010000 | 0` succès ; `01 00 | 00 00 | ffffffff | 0` échec) + `0x09[0x00:0x14]` + `0x09[0x1c:0xc8a]` décalé de +4, à 48-62 octets près (succès) ou 10 (échec, autour de `+0x20` et `+0xc20`) ; `+0x3a` deux u16 égaux qui varient entre succès (1, 0x12, 0x10) | récapitulatif de fin de tentative (même résultat que 0x09) | hypothèse | trace:C8 | 2026-11-08 |
| 0x08 | < | 0xfc | 0x70 | 0 | 0 | B : 0x69 octets, 12/12 (6 tentatives + login L860/L872 + pw_unlock L3838/L3868/L4388/L4424) ; `HRLB` (`48524c42`) + u32 2 + zéros jusqu'à `+0x20`, `+0x20`=0x3a, `+0x2d..+0x2f`=`00 00 29` ; `+0x21..+0x2c` et `+0x30..+0x68` différents à chaque fois, entropie ~5.2 bits/64 o (proche du max pour cette taille) ; aucun octet ne sépare succès et échec | blob opaque à magic `HRLB` (signé/chiffré ? non interprété) | hypothèse | trace:C8 | 2026-11-08 |
| 0x08 | < | 0xfc | 0x1f | 0 | 0 | B : 2 octets `05 05` dans 6/6 tentatives (succès et échecs) | ? (constant) | hypothèse | trace:C8 | 2026-11-08 |
| 0x08 | > / < | 0xfc | 0x54 (init) | 0 | 0 | `>` A L554 : charge 0x14 = `f5010000` + les 16 octets `fe6003d8…371b` ; `<` B L556 : 0xbf4 octets, **identiques** dans C5, C6, C7, C8 (4 boots) ; les mêmes 16 octets dans `<` B 0x6e (L572) et 0x7a (L576) | l'AP demande au SEP l'enregistrement associé à (uid 501, identifiant 16 o) ; l'identifiant est stable entre boots (gabarit/utilisateur enrôlé ?) | hypothèse | trace:C8 ; trace:C5 ; trace:C6 ; trace:C7 | 2026-11-08 |
| 0x08 | < | 0x01 | 0x09 | 0x02 | 0x1f5 | 2e occurrence par verrouillage : L2209, L2840, L3493, L4089, 1-4 ms après les 3 `< EP=0x12 TAG=0x01` (verrouillage volume/-501/-6) déclenchés par `> EP=0x12 TAG=0x2f` ; 4/4 dans C8 ; C3 3/4 à +1 ms (L1464, L4714, `<01/45` L5504) et 1/4 à +243 ms (L3462) | écho sbio du verrouillage du keybag 501 (le « 2e `<01/09` à +10.6 s » de C3) ; le 1er `<01/09` suit `> EP=0x12 TAG=0x18 DATA=0x00740000` de < 10 ms (5/5) | hypothèse | trace:C8 ; trace:C3 ; lecteur-logs C8 | 2026-11-08 |
| 0x08 | > / < | 0xfc | 0x23, 0x22, 0x0b, 0x09 (`>`), 0x07 (`>`), 0x70 (`>`), 0x21 (`>`) | 0 | 0 | charge vide (longueur 0) dans 100 % des lectures C8 | commandes sans argument | hypothèse | trace:C8 | 2026-11-08 |

Latence (VU, `analysis/out/c8_latency.txt`, `> 0xfc X` → `< 0xfc X`) : médiane 1.59 ms sur 200 paires ; moyenne des paires
< 50 ms (définition qui redonne C3 2.35 / C6 7.36 / C7 2.47) = **3.62 ms** ; restreinte aux TYPE présents dans C7 : 2.17 ms
(C7 2.21). Le chiffre 3.62 vient de la composition (0x07 ~20 ms, 0x23 ~6.6 ms absents de C7), pas d'un ralentissement :
TYPE par TYPE C8 ≈ C7 (plancher ~1.4 ms par paire contre ~0.05 ms en ASYNC dans C3). 0x09 : succès 250, 247, 235 ms,
échecs 277, 298, 303 ms (comme C3 : 240-245 / 296-356). `# ool_stats` L4480 : 480 lectures, 0.45 ms en moyenne (max 1.50),
216 ms au total, 1.95 Mo, 9 traductions ; 0 `ool_error`.

### SKS (0x12) — structure (aperçu, C1)

| EP | Dir | Tag | Type | Param | Data | Vu (C1) | Rôle supposé | Statut | Source | Date |
|----|-----|-----|------|-------|------|---------|--------------|--------|--------|------|
| 0x12 | > | t | n | 0 | 0xLLLL0000 | 579 requêtes, L174… | TAG = commande ; TYPE = compteur de transaction (+1 à chaque requête, 3 écarts sur 579) ; bits 48-63 = longueur ? | hypothèse | trace:C1 | 2026-11-07 |
| 0x12 | < | t\|0x80 | n | s | 0xLLLL0000 ou 0 | 579 réponses, toutes appariées (TAG\|0x80, même TYPE) | réponse ; PARAM≠0 (0xfd ×53, 0xfb ×5, 0xff, 0xfe, 0xed) toujours avec DATA=0 → code d'erreur ? Réponses TAG 0x84/0x86 : PARAM=0xfd avant le 1er login, 0x00 après, sans exception (C1 L251→L695 ; C2a L247→L681 ; C3 12/12 0xfd L247-L688 puis 290/290 0x00 dès L697, bascule au UNLOCKED now=1794020513, uart L2748) — **reproduit dans 3 captures** | hypothèse | trace:C1 ; trace:C3 | 2026-11-07 |
| 0x12 | < | 0x00 | v | p | handle (int32) | L550, L639, L641, L697, L1124, L1624 | notification de changement d'état d'un keybag : DATA = « handle » du noyau, 5/5 correspondances (L550 ↔ uart L2332-2333 ; L639 ↔ L2615-2616 ; L641 (-6) ↔ L2619 ; L697/L1124 (-501) ↔ L2679 / L2784 ; L1624 ↔ L2987-2988) ; PARAM=1 pour les volumes (« Unlock notification for volume »), 0 sinon ; TYPE=1 en L697, 0 ailleurs | hypothèse | trace:C1 | 2026-11-07 |
| 0x12 | < | 0x09 | 0 | 0 | 0 | L640, L1619 (2×, chaque fois à côté d'une notification de volume) | ? | hypothèse | trace:C1 | 2026-11-07 |

### SKS (0x12) et xART (0x13) — C8 : alignement avec le log noyau (source : lecteur-logs, C8 ; recoupé par l'analyste)

Rapport source : `analysis/out/c8_uart_align.md` (lecteur-logs, outil `analysis/uart_timeline.py`, chronologie
`analysis/out/c8_uart_timeline.txt`). Recompté par l'analyste (2026-11-08) : la règle « lock change » (29/29, 34/34, 6/6),
les comptes « Saving USER-xART » / `< EP=0x13 TYPE=0x01 PARAM=0x9c` (C8 18/18, C3 52/52, C1 4/4) et « Saving SEP-xART
[Locker] » (4 + 2 dans C1, C3, C8), les lignes `> EP=0x12 TAG=0x2f/0x41/0x18` citées. Correction : le 2e déverrouillage
mot de passe commence à L4287 (`> TAG=0x41`), pas L4288 (qui est la notif volume). uart Lnnn = `traces/<C8>/hv_uart.log`.

| EP | Dir | Tag | Type | Param | Data | Vu (C8) | Rôle supposé | Statut | Source | Date |
|----|-----|-----|------|-------|------|---------|--------------|--------|--------|------|
| 0x12 | < | 0x00 / 0x01 | V (0 ; 1 une fois, au login L851) | 1 = volume, 0 sinon | handle int32 | k-ième uart « Sending lock change X for handle H value V » ↔ k-ième `< EP=0x12 TAG=X TYPE=V DATA=H` : **C8 29/29, C3 34/34, C1 6/6** (même ordre, mêmes valeurs) ; ex. L1728 ↔ uart L3056 (« … 0 for handle -501 value 0 ») ; L2205 ↔ uart L3307 (« … 1 for handle -832618891 value 0 ») | notification de changement d'état de verrou de keybag : TAG = sens (0 = déverrouillage, **1 = verrouillage**), TYPE = « value », DATA = handle (-501 utilisateur, -6, handle volume) ; complète la ligne `< 0x00 v p handle` de C1 ci-dessus | hypothèse | trace:C8 ; trace:C3 ; trace:C1 ; lecteur-logs C8 | 2026-11-08 |
| 0x12 | < | 0x00 | 0 | 0 | 0xfffffe0b (-501) | pendant sbio 0x09 dans les 3 succès doigt (L1728, L2424, L2995), jamais dans les 3 échecs (analyste, section C8 SBIO) ; aussi aux 2 déverrouillages mot de passe (L3831, L4381, ~2 ms avant `<01/28`) ; uart « Sending lock change 0 for handle -501 value 0 » | déverrouillage du keybag utilisateur 501, commun doigt / mot de passe ; côté doigt, non précédé d'une requête AP 0x12 (notif spontanée pendant 0x09) | hypothèse | trace:C8 ; trace:C3 ; lecteur-logs C8 | 2026-11-08 |
| 0x12 | > / < | 0x2f / 0xaf | n | 0 | 0x00600000 / 0x006c0000 ou 0x006c0001 | 6× ; 4× (L2204, L2835, L3488, L4084, 12.4-14.6 s après le verrouillage écran) suivies de 3 `< TAG=0x01` (volume, -501, -6) puis réponse `DATA=0x006c0001` ; 2× (L1828, L4283) sans notification, réponse `DATA=0x006c0000` ; uart « Lock notification for volume … » / « apfs is being LOCKED! » | requête AP « verrouiller keybag/volume si délai écoulé » ? bit 0 de la réponse = verrouillage effectué (6/6) | hypothèse | trace:C8 ; lecteur-logs C8 | 2026-11-08 |
| 0x12 | > | 0x41 | n | 0 | 0x01c80000 | 3× : login L789, pw_unlock_1 L3737, pw_unlock_2 L4287, chacune suivie de `< TAG=0x09 DATA=0` (L791, L3739, L4289) et des notifs volume/-6 ; les 35 autres `> TAG=0x41` ont un autre DATA (surtout `0x01c00000`) | déverrouillage par mot de passe, 1re étape (volume, -6) ; absent des déverrouillages doigt | hypothèse | trace:C8 ; lecteur-logs C8 | 2026-11-08 |
| 0x12 | > | 0x18 | n | 0 | 0x007c0000 / 0x00740000 | `DATA=0x007c0000` : 6× par paires (login L850/L862, pw L3830/L3840, L4380/L4390), la 1re suivie de la notif -501 ; `DATA=0x00740000` : 9× dont une < 0.1 s avant chaque 1er `<01/09` de verrouillage (L1524, L2068, L2673, L3278, L3930) | 0x007c… = déverrouillage -501 par mot de passe (2e étape) ; 0x0074… = autre opération au verrouillage (?) ; bits 16-31 de DATA = longueur ? (cf. ligne SKS C1) | hypothèse | trace:C8 ; lecteur-logs C8 (0x007c) ; analyste (0x0074) | 2026-11-08 |
| 0x13 | < | t | 0x01 | 0x9c | CRC<<16 \| 0x0007 | 18× ; uart « Saving USER-xART with CRC: 0xNNNN » (ex. L1722 ↔ uart L3050) ; 2 par tentative doigt atteignant 0x09 (1 pendant sbio 0x09, 1 pendant sbio 0x70), **succès et échecs**, 6/6 ; 0 dans les 3 abandons ; 2 pendant le 2e 0x37 de chaque rafale post-unlock (3×) ; C3 : 2 dans 19/20 tentatives à 0x09, 1 dans L5363, 0 dans les abandons | sauvegarde d'un état utilisateur à chaque comparaison effectuée (compteur d'essais ?) — marqueur « comparaison faite », pas du résultat | hypothèse | trace:C8 ; trace:C3 ; lecteur-logs C8 | 2026-11-08 |
| 0x13 | < | t | 0x01 / 0x06 | 0x53 / 0x2f, 0x50 | CRC<<16 \| 0x0103 / 0x0101, 0x0100 | 4× / 2× dans chacune de C1, C3, C8 ; uart « Saving SEP-xART with CRC » / « Saving SEP-xART Locker with CRC » | sauvegardes xART côté SEP (boot/login) | hypothèse | trace:C8 ; trace:C3 ; trace:C1 ; lecteur-logs C8 | 2026-11-08 |

Chemins SKS, VU dans C8 (résumé) : **doigt** = aucune requête AP 0x12 avant le succès ; pendant 0x09 le SEP émet seul
`< TAG=0x00 … DATA=-501` (et, si le volume était verrouillé, volume puis -6 : L2423-2425, L2994-2996), puis macOS publie
UNLOCKED. **Mot de passe** = `> TAG=0x41 DATA=0x01c80000` → `< TAG=0x09` + notifs volume/-6, puis `> TAG=0x18
DATA=0x007c0000` → notif -501 → `<01/28` → sbio `70`, deux fois. **Échec doigt** = rien sur 0x12, aucune ligne noyau
(ni erreur biométrique, ni keybag) : côté log, l'échec n'est visible que par l'absence. Interprété : le verdict doigt
déclenche le déverrouillage du keybag dans le SEP lui-même ; l'AP en est informé par la notif SKS -501 et par la réponse
OOL 0x09 (section C8 SBIO, HE).

### xART (0x13) — remarque sur la table doc-asahi

Vu (C1) : sous macOS 13.5, les échanges 0x13 commencent côté SEP : `< TAG=t TYPE=op …` puis `> TAG=t TYPE=0x00 …`
(ex. L125/L129 ; L237/L238). Le noyau les traite comme des requêtes du SEP (« _handle_sep_driven_msg … Replied to xART
app »). Pour `TYPE=0x01 PARAM=0x53|0x9c` et `TYPE=0x06`, DATA>>16 = CRC affiché par le noyau « Saving … with CRC »
(L237 ↔ uart L1992 ; L1122 ↔ L2781 ; L1140 ↔ L2791 ; L1243 ↔ L2841 ; L1245 ↔ L2844…). `TYPE=0x1d` (op 29) porte un nom
d'endpoint en ASCII (PARAM + DATA, ex. L106 `sbio`). Les lignes doc-asahi (`> TYPE 0`, `< TYPE 5/7 PARAM 0x10`) décrivent
donc un sens qui n'est pas celui observé ici : à revoir (hypothèse : la doc décrit l'usage depuis m1n1/Linux).
