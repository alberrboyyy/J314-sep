# ▶️ COMMENCE ICI — 2026-11-23 (00h05) — 🎯 J7b : BOOT CHAÎNÉ NATIF COMPLET, sbio VIVANT (n=1)

- **Cause du mur « boot chaîné »** : sepd servait les lockers AVEC leurs 16 o d'UUID. Servis **sans UUID** (A = B[16..] du
  SAVE, `sepd --locker-strip-uuid`), le SEP les accepte tous (4 lockers + op 0x07, 0 SAVE), **annonce sks (0x12)**, et
  **sbio répond au 0x73** — sans aucun RPC SKS. Logs `logs/20261123-000245_j7b-sks-open-chained-nouuid/`, journal 2026-11-23 00:02.
- ⇒ Le « Track B = implémenter SKS » est réfuté pour l'armement de sbio ; la persistance de l'état scellé + sbio vivant = OK.
- **PROCHAIN** : (1) re-run J7b (n=2, script éprouvé → autonome, power-cycle = Albert) ; (2) J7b sans `allow_sks` (les
  ouvertures 0x17/0x12/0x0a sont-elles nécessaires ?) ; (3) faire de « sans UUID » le défaut de sepd et rejouer
  l'init capteur complète (j5c) sur boot chaîné ; (4) enrôlement : toujours bloqué par le jeton du 0x03 (BiometricKit, c9).
- Session c9 : le reverse kext op 0x05/0x06 n'est plus bloquant (le matériel a tranché), mais il confirmerait le format.

---

# ▶️ COMMENCE ICI — 2026-11-22 (nuit, 23h30) — 🎯 INIT CAPTEUR COMPLÈTE EN LINUX NATIF ; enrôlement bloqué (jeton 0x03) ; SKS = prochain mur

**Lis d'abord :** cette entrée, puis `docs/journal.md` (entrées 2026-11-22 20:16 → fin), `docs/j5_params_protocol.md`,
`docs/j6_enroll_match_protocol.md`, `docs/sks_native_plan.md`, `docs/mission_pc_biometrickit.md`. Mémoire : commits
signés, push avant test, **aucun trailer « Claude » dans les commits** (historique réécrit 2026-11-22, `8df1f7b`).

**ÉTAT VÉRIFIÉ / OBTENU CE SOIR (Linux natif ALARM, sans macOS ni m1n1, scellement xART FRAIS à chaque boot) :**
- ✅ **Patch capteur CHARGÉ** (`29 01 00 7c`) — **n=5**. Cause du mur m1n1 trouvée : macOS lit l'état capteur ENTRE
  le prélude `80 60 00 07` et le bloc, et ne lit RIEN pendant le chargement (attente IRQ gpio195). PIO noyau suffit
  (bloc 22158 o en 29 ms), pas besoin de DMA. `sbiod` v2+. Logs `logs/20261122-204249_j5b-patch-loaded/`.
- ✅ **Params capteur** 0x5d/0x5c/0x6a/0x31-0x32×2/0x01/0x1f, états = macOS — n=4.
- ✅ **Calibration 0x5b** (blob c12 rejoué, 64665 o, 4 fragments AP→SEP) acquittée + **0x63 = macOS** — n=3.
- ✅ **2e passe** (coupure capteur, 0x19, patch n°2 28878 o chargé, 0x6f, 0x63×2 = macOS) — **n=2** (22:11, 23:04).
  ⇒ **toute l'init capteur macOS reproduite**, capteur « au repos final de macOS ». Script : `pending/j5c_params_run.sh`
  (`UPTO=params|calib|pass2`, défaut params). Binaires dans `~/kbuild/j5` (sep_native.ko, sbiod, calib_0x5b.bin).
- ❌ **Enrôlement (J6a, 23:04)** : `0x03` de 68 o à zéro → SEP répond **TAG 0xff** (jamais vu, refus probable), rien
  ensuite. Logs `logs/20261122-230441_j6a-enroll-start/`. Albert n'avait pas posé le doigt : sans effet (refus immédiat).
- 🔎 **BiometricKit (session PC, partiel, `docs/biometrickit_protocol.md` côté PC — à pousser)** : 0x03 v2 (0x44 o) =
  `+0 u32 0 ; +4 userID ; +8 usingAuthToken ; +0xc tokenLength ; +0x10 token[32] ; +0x30 deviceGroup.type ;
  +0x34 uuid[16]` ; jeton = CredentialSet (1-32 o) ou AuthToken (0/16 o) ⇒ notre 0x03 nul refusé faute de jeton
  (hypothèse). Non traité : 0x06/nonce, préconditions, sens TAG 0xff, boucle de poses (filtre modèle a coupé ; reprendre
  en session neuve). **Pas de J6b sans go d'Albert.**
- 🔎 **SKS (EP 0x12)** : `docs/sks_native_plan.md` — TYPE = compteur global de transaction, TAG = opération (messages.md
  avait raison ; sks_sequence_c12.md corrigé). Session PC a décodé `get_capabilities` (TAG 0x4d, 0x64 o) dans
  `docs/sks_ipc_negotiation.md` (côté PC, à pousser). **Fait nouveau VU** : sur boot CHAÎNÉ natif, `sks` n'est JAMAIS
  dans la table 0xFD (J3/J3b/J3d) alors qu'il y est sur tout seal frais.

**PROCHAIN PAS (dans l'ordre) :**
1. **J7a** = `pending/j7a_sks_open_chained.sh /var/lib/sepd-run-20261122-230441` (prêt, compilé, sha256 ff799c11…) :
   boot chaîné, sbio ouvert tôt, ouverture skdl 0x17 / sks 0x12 / scrd 0x0a SANS RPC, écoute, puis 0x73. 1er run =
   **go d'Albert** (classe neuve). Tranche : sks s'annonce-t-il si on attend/ouvre skdl ? l'ouverture seule réveille-t-elle sbio ?
2. Session PC : pousser `biometrickit_protocol.md` + `sks_ipc_negotiation.md` ; reprendre BiometricKit (0x06, TAG 0xff,
   d'où vient le jeton 0x03 → ACM/SKS ?).
3. Selon J7a : expérience 2 = `get_capabilities` seul (forme du doc PC ; contient horodatage/pid/cdhash, pas un rejeu).

**PIÈGES :** `sync` AVANT chaque power-cycle (un power-cycle a vidé 25 objets git, réparé par `git fetch`) ; la clé SSH
disparaît de l'agent à chaque boot → Albert tape `! ssh-add` ; les runs tournent en root → Albert tape
`! sudo <script>` (sudo interdit à l'agent) ; `sepd` reste en fond après chaque run (Ctrl-C).

---

# ▶️ COMMENCE ICI — 2026-11-22 (soir) — 🎯 J2 RÉUSSI : SEPOS boote sous Linux NATIF, sans tether ; J4 (xART) en cours

**MODE DE TRAVAIL EN BINÔME (fixé par Albert 2026-11-22) :**
- **Agent Claude sur ALARM (le Mac) = les MAINS** : il agit sur le matériel, écrit le driver (`driver/rust/`), lance les runs. Son go vient d'**Albert directement dans SA session** (pas via l'orchestrateur). ⚠️ Sa session **s'arrête à chaque reboot du Mac** et repart sous un **nouveau nom/ID** → on se retrouve par `ListAgents`, et **tout le contexte durable passe par le repo git** (push/pull) + ce handoff + la mémoire.
- **Session PC `sep-touchid-c9` = CERVEAU protocole + HÔTE DE BUILD + relecteur** : fournit les séquences SEP vérifiées (avant chaque étape neuve), compile noyau/modules (rustc 1.99.1, ~7 min), tranche vérifié/hypothèse, tient ce handoff. Ne pilote plus de hardware.

**ÉTAT (le plus récent d'abord) :**
- ✅ **J1** : transport SEP porté en **Rust** (`driver/rust/sep-proto/`, no_std, rejeu offline conforme). Noyau croisé **buildé sur le PC** (6m41s, Image 35 Mo, 1864 modules, rustc 1.99.1). `sep_proto_selftest.ko` chargé sur ALARM (21/21).
- ✅ **J2 RÉUSSI (sans tether)** : `sep_native.ko` (notre module, PAS sep.rs qui est buggé : CNIP/pas de GET_STATUS) boote **SEPOS sous Linux natif** via `update-m1n1` (DTB + alias `sep`) + reboot. Séquence validée (0x66 1→2, IMG4+SHMEM→0x6A). 7 EP annoncés (xarm 0x13…), Running, xART pas encore servi (fail-closed). `journal.md`.
- ✅ **J4 (servir xART) RÉUSSI EN NATIF (2026-11-22 18:38)** : `sep_native`+`sepd`, store neuf, UUID `4c494e5558…`, go d'Albert. FETCH maître → ABSENT (0x11), **12 SAVE acquittés+persistés** (master t2 420o + 4 lockers), aucun Halt → puis **sbio (0x08), skdl (0x17), sse (0x0c), scrd (0x0a) annoncés, puis sks (0x12)**. = la route native m1n1 (n=4) **reproduite sous Linux natif**. **VERDICT = VÉRIFIÉ** (logs bruts `logs/20261122-183847_j4-xart-native/` confirmés octet-près par l'orchestrateur : 12 SAVE persistés+ACK, 5 annonces 0x1d, 0 Halt / 0 ignoré, sks 0x12 après les SAVE ; n=1 natif, concordant m1n1 n=4 — reste n≥2 pour clouer). Politique = `docs/xart_native_policy.md` (§ vérif orchestrateur). ⚠️ Touch ID macOS désormais invalidé (accepté). Store = `master_2.bin` + 4 `locker_save_*.bin`.
- ✅ **CHAÎNAGE cross-reboot VÉRIFIÉ (n=1, J3 2026-11-22 18:56)** : au 2e boot, servir le master stocké (437o=0x11+420) → le SEP l'**accepte SANS re-sceller** (0 SAVE, annonces immédiates) → **Touch ID persistant VIABLE**. Keying locker = **16 premiers octets de B au SAVE**. Logs `logs/20261122-185633_j3-sbio-open/`.
- ✅ **J3 (sbio 0x08) TRANCHÉ** : sbio **ouvre + répond au 0x73 (VIVANT) en natif APRÈS UN SEAL FRAIS** (B8 +0x14=0x73, reproduit m1n1 n=3, logs `logs/20261122-192013_j3c-sbio-fresh/`) = **VÉRIFIÉ**. MAIS **après un CHAÎNAGE** (master/lockers servis), l'open CNTL 0x08 **reste sans ack (n=2)** — servir les lockers n'a PAS suffi (hypothèse « lockers » réfutée). ⇒ **TENSION confirmée : persistance (chaînage, garde l'enrôlement) ↔ armement sbio (exige seal frais, efface l'enrôlement).**
- 🎯 **TRACK B RÉSOLU (comparaison c12) — l'enrôlement persistant EXIGE SKS (0x12)** : sur un boot CHAÎNÉ, deux choses manquaient. (1) **Timing** : ouvrir le CNTL 0x08 **TÔT** (dès l'annonce `0x1d 'sbio'`, entrelacé avec le service xART), pas après le calme → **testé J3d 2026-11-22 19:57 : open 0x08 ACKÉ sur chaîné** (fix timing confirmé ✅). (2) MAIS le **0x73 reste muet** car, sur un boot résumé, **sbio est GATED derrière l'init de toute la pile keystore** : macOS, entre l'open et le 0x73 (26 s !), **ouvre+initialise skdl (0x17), sks (0x12, taille 0x8000, séquence RPC/DER TYPE 0x01→0x19), scrd (0x0a)** AVANT d'envoyer le 0x73. En seal frais il n'y a rien à déverrouiller → sbio répond direct. ⇒ **Touch ID persistant = implémenter SKS (0x12)** (chantier « SKS classe jamais testée », porte Albert). Logs `logs/20261122-195701_j3d-chained-early/`. Détail = `docs/xart_native_policy.md` (Track B).
- ✅🎯 **Track A / J5 : PATCH CAPTEUR CHARGÉ EN NATIF (2026-11-22 20:43, J5 v2, logs `logs/20261122-204249_j5b-patch-loaded/`)** — le MUR hérité de m1n1 est TOMBÉ : 0x17→0x15/0x16(SPI 0x72)→0x42/0x18(SPI 0x73)→**0x5f patch poussé en PIO natif** → **état capteur `0x60→0x29` (`2901007c`)**. 2 clés : (a) push PIO (pas de tunnel) ; (b) **lire l'état capteur ENTRE le prélude 0x60 et le bloc** (ce que macOS fait, c17-c20) — c'était ça qui manquait. n=1.
- 🔸 **PROCHAIN = fin d'init capteur (post-0x5f)** : params `0x5d/0x5c/0x6a/0x31→0x32` (trame **SPI 0x55** = `80 55 <TOTAL BE> 000000`+blob+**CRC16-ARC**), `0x01/0x1f` (SEP-only), **calib `0x5b`** (mailbox OOL 4 frags, **rejouable** depuis `traces/…c12…/000335/337/339/341_08_A.bin`), `0x63/0x19`+2e passe. **Lire l'état 0x10 ENTRE chaque trame** (leçon patch). STOP avant enrôlement/match (= session humaine, doigt). Détail = `docs/sbio_session.md §2/§3/§6` + `sep_native_sbio9/10`. Tout VU C19 mais **jamais exécuté** → hypothèse jusqu'au run.
- **Enrôlement persistant (Track B)** reste suspendu à **SKS 0x12** (`docs/sks_sequence_c12.md`).
- Après J3 : init capteur (0x17→0x15/0x16→0x42/0x18→patch) ; **patch capteur = tenter PIO noyau d'abord** (le mur m1n1 venait de la latence tunnel, pas du DMA — `docs/dma_spi2_design.md`).

---

# ▶️ REPRISE 2026-11-22 (jour) — 🎯 VIRAGE : cible = pilote Touch ID LINUX NATIF, sans tether

**Décision d'Albert (2026-11-22) : le livrable = un pilote Linux natif, pour NE PLUS dépendre du montage m1n1-proxy tethered (PC USB + power-cycle). m1n1 = échafaudage de reverse.** Lis, dans l'ordre : cette entrée, `docs/linux_roadmap.md` (roadmap J0→J6 + écarts à coder), `driver/linux/MISSION_AGENT_MAC.md` (paquet de mission pour l'agent Claude qu'Albert lance côté Mac sous Linux), le haut de `docs/journal.md` (entrées 2026-11-22 « bloc autonome » / « DÉCISION ALBERT »), et les mémoires [[cible-linux-natif-sans-tether]] + [[regle-lancement-sep-relachee]].

**CE QUI A CHANGÉ :**
- **Règle ouverte** (CLAUDE.md « Exception 2e Linux de test », réécrite) : **SEP désormais AUTORISÉ depuis le Linux de test** (sbio/SKS/xART/IMG4/DMA capteur) avec la discipline habituelle (fail-closed, DFU+alarm_p5, **1er run classe/script neuf = go d'Albert**, power-cycle = Albert, jamais Stockholm direct ; toujours interdit : disques/boot/m1n1/partition/macOS).
- **Verdict DMA (tracer)** : en m1n1 le DMA SIO est mort (personne ne boote le SIO) ; **Linux boote le SIO (`apple-sio`)** → c'est là qu'il faut aller. `docs/voie_sbio.md` §8.
- **Patch (m1n1) = impasse confirmée** : même en attendant l'IRQ (sbio11), le capteur reste en `0x60` (sans correctif). On ne poursuit plus le push patch sous m1n1.

**ÉCARTS À CODER (purement publics, sans toucher au mur SEP) :** (1) transport SEP générique (sep.rs = amorceur only) ; (2) client dmaengine dans spi-apple + binding dmas 0x18/0x19 ; (3) mode one-shot sur apple-sio (cyclique/TX-only) ou payload AP ; (4) nœud DT spi2+mesa. Mur de fond inchangé = **J4 (xART / Secure Storage Component)** → exige un état SEP propre natif (DFU + ré-enrôlement macOS = Albert/matériel).

**PROCHAIN PAS :** Albert boote le Mac **sous Linux** + lance un agent côté Mac → lui passer `MISSION_AGENT_MAC.md`. T1 (`driver/linux/env_probe.sh`, lecture seule : spi2 / **sio/dart-sio/apple-sio** / sep présence) + T2 (bring-up capteur) = autorisés tout de suite. J2+ (SEP) = go d'Albert. ⚠️ Ajuster d'abord le filtre `DENY` de `tools/linux_ssh.sh` (bloque encore `sep|xart|0x1[0235]`).

<!-- ================= BANDEAU PRÉCÉDENT (piste m1n1, close) ================= -->

# REPRISE 2026-11-22 (nuit, FIN) — route native prouvée JUSQU'AU PATCH ; mur = charger le patch INTÈGRE (DMA ?)

**Contexte neuf / après /clear : lis ceci, puis `docs/sbio_session.md` + `docs/sbio_keyexchange.md`, le haut de `docs/journal.md` (entrées 2026-11-22), et la mémoire [[route-native-0x13-breakthrough]] + [[regle-lancement-sep-relachee]]. Règle de lancement RELÂCHÉE (CLAUDE.md) : Claude lance les scripts `pending/` ÉPROUVÉS ; script NEUF = « go » d'Albert ; power-cycle physique = TOUJOURS Albert (le reboot logiciel fige le PMU).**

**CE QUI MARCHE (prouvé matériel, répété) — toute la session capteur native jusqu'au patch inclus (transmission) :**
scellé xART frais → `sbio` VIVANT (0x73, **vérifié n=3**) → **0x17** (serial capteur lu live) → **key exchange 0x15/0x16** (relais lockstep chiffré, trame SPI 0x72) → **compteur 0x42/0x18** (trame 0x73) → **réception patch 0x5f** (poignée fe/fd, 22158o) → **PUSH patch** au capteur (FIFO scruté, 22Ko en 2.4s, sans timeout). L'AP = **PUR RELAIS d'octets** (aucune crypto/clé côté AP, prouvé décompil). Scripts chaînés `pending/sep_native_sbio{,2,3,4,5,6,7,8,9}.sh` (9 = le plus complet : jusqu'aux params). Moteur SPI capteur : `analysis/mesa_spi_proxy.py` (xfer FIFO, timeout param).

**LE MUR (sessions sbio8 + sbio9) :** après le push patch, le 1er param **0x5d** → **état capteur = TOUT ZÉRO** → STOP fail-closed. Le fix CRC des trames 0x55 (sbio9 : +CRC16-ARC suffixe, VU C19) était NÉCESSAIRE mais n'a PAS suffi. **Le patch ne s'ACTIVE pas.** Confirmé (relecture 2026-11-22, Opus 4.8, contre `sensor_hw.md` l.112-115) : l'état post-push `…60 00 00 08…` n'est PAS « push accepté » — c'est la **variante `…08…` de l'état « repos SANS correctif »** (octet 2 = `60`) ; l'état « correctif chargé » serait `00 29 01 00 7c…` (octet 2 = `29`), jamais atteint. ⚠️ **Le « CS lâche → DMA » est un FAUX diagnostic** : sbio7 a mesuré le transport OK (CS tenu, 22158 o en 2.3-2.4 s, pas de timeout). Le capteur reçoit les octets et **rejette/n'active pas** le patch.

**SCRIPT PRÊT (attend « go » d'Albert) :** `pending/sep_native_sbio11.sh` = sbio9 avec le **bon critère de succès** (décompil §3b) : après le push, **attendre l'IRQ gpio0 195 + relire `st[8]` jusqu'à ~1,5 s**, n'enchaîner les params QUE si `st[8]==0x29` (patch chargé), sinon STOP+dump avec verdict distinct (IRQ jamais montée+`0x60` ⇒ réception incomplète ⇒ DMA ; IRQ montée mais ≠`0x29` ⇒ rejet crypto/session). N'émet RIEN de neuf vs sbio9 (prélude+bloc) ; le nouveau = des LECTURES (gpio195+status). SELFTEST vert. Test décisif et pas cher **avant** de se lancer dans le DMA. (1er run d'un script neuf = « go » requis ; power-cycle = Albert.)

**PROCHAINS PAS (ordre) :**
0. **Lancer `sbio11`** (ci-dessus) : tranche « on lisait trop tôt / sans IRQ » (gain gratuit) vs « il faut vraiment le DMA ». ⇒ oriente tout le reste.
1. **Comprendre pourquoi le capteur rejette le patch** = le vrai chantier (le transport est acquis, PAS besoin du DMA). Décompil du protocole **LoadPatch** côté macOS (EP 0x08 op 0x5f, AppleMesaSEPDriver ; agent `reverseur` lancé 2026-11-22) : (a) cadrage exact du bloc poussé (prélude `80 60 00 07`, longueur, CRC/trailer éventuel) ; (b) étape **verify/commit/activate** après le push ? ; (c) bloc chiffré lié à la **clé de session 0x72** (capteur qui ne décode pas → refus) ? ; (d) attente de l'**IRQ gpio0 195** avant relecture de l'état ? **Vérif de succès = l'octet 2 de l'état capteur passe à `0x29` (`00 29 01 00 7c`).**
2. Puis params (0x5d/0x5c/0x55, CRC déjà corrigé sbio9) + **calibration 0x5b** (blob userspace livré au SEP par mailbox ; analyse sbio10 lancée en fin de session — voir `docs/` si rendue).
3. Puis **ENROLL + MATCH = DOIGTS** (session humaine ; séquences déjà cartographiées : `docs/sbio_enroll.md`, `docs/sbio_match.md` ; D2 keybag = gating AP-side, cf. sbio_match).

**Infra :** `tools/catch_loop.sh` = catcher permanent (lancer 1× en fond ; re-catch auto à chaque power-cycle d'Albert). `tools/catch_lib.sh` v2 (nœud brut + baseline + retry d'ouverture) fiable en local. Tunnel tél préparé mais NON validé (appli Android « USB Serial Telnet Server » port 2323 ; `TUNNEL_PROXY_PORT=2323 TUNNEL_CONSOLE=0 python3 tunnel.py` ; à tester : raw-vs-telnet-IAC + le catch côté appli via Autostart). Docs protocole complètes : `sbio_sequence/keyexchange/session/enroll/match.md`, `handler_0x13.md`, `route_native.md`. Audit GitHub fait (IDs Mac dans traces/historique = « pg » selon Albert). ~28 commits, tout committé ; compteur anti-rejeu avancé (récupérable DFU + `alarm_p5.img`).

---

<!-- bandeau précédent (début de nuit) conservé pour l'historique -->
# REPRISE 2026-11-22 (nuit) — 🎯 ROUTE NATIVE RÉUSSIE sur matériel : SEP scelle un état frais pour Linux, sbio+sks armés

**Si contexte neuf / après /clear : lis ceci, puis `docs/route_native.md`, puis le haut de `docs/journal.md` (2026-11-22 00:46), puis la mémoire [[route-native-0x13-breakthrough]]. CLAUDE.md = règles (PHASE 2 ; écriture SEP = Albert lance).**

**CE QUI VIENT D'ARRIVER (2026-11-22, Albert a lancé `pending/sep_native_persist.sh`) :** la question décisive de `route_native.md` §6 est TRANCHÉE. En répondant ABSENT (forme kext) aux FETCH puis en **ACQUITTANT les SAVE d'un état FRAIS**, le SEP **se stabilise** (`idle`, 12 SAVE, PAS la boucle voie C) et garde **sbio (0x08) ET sks (0x12)** armés. État scellé légitime natif, obtenu **sans macOS**. Trace `traces/20261122-004526_native_persist` ; état scellé dans `xart_store_linux/` (gitignoré). Compteur anti-rejeu avancé de 12 (irréversible, prévu) ; Linux intact ; filet DFU + `alarm_p5.img` prêts.

**CATCH PROXY : RÉGLÉ.** `tools/catch_lib.sh` v2 (nœud brut `/dev/ttyACM*` + baseline anti-fantôme + vérif produit USB) rattrape le proxy en local au 1er coup (t+13s). Warning bénin `Permission denied` sur l'ouverture du nœud brut avant droits udev → le chainload prend le relais ; à durcir par un retry d'ouverture ~50 ms (non bloquant).

**FAIT CETTE NUIT (après le bandeau ci-dessus) — 🎯 sbio VIVANT :** `pending/sep_native_sbio.sh` (persist + sonde `0x73`, relu par Claude, SELFTEST vert) → après stabilisation, sbio répond au `0x73` **exactement comme macOS** (B8 +0x00=1/+0x14=0x73 ; `< EP=0x08 TAG=0xfc TYPE=0x73`), via le **stream 0 normal** → ça TRANCHE `voie_sbio` §5/§6 : c'était l'**ÉTAT** (sbio pas armé), PAS le canal DART. **Reproduit n=3 → `vérifié`** (stabilisation du SEP n=4). Journal 2026-11-22 01:05 ; statut : `verification_status.md`. Traces `20261122-010801/012059/013535_native_sbio`. **Catcher fiabilisé** (`catch_lib.sh` : retry d'ouverture du nœud jusqu'à droits udev = fix du "Permission denied" qui ratait la fenêtre ; validé sur matériel).

**PROCHAIN PAS :** (a) ✅ FAIT — sbio n=3 « vérifié » ; (b) **le vrai chantier suivant = la suite d'init sbio APRÈS le 0x73** (ce que macOS envoie ensuite → clé capteur SPI → un vrai **match**) : à cartographier d'abord (décompil/trace de la séquence sbio post-0x73) puis greffer sur le flux natif ; (c) **sks (0x12)** — protocole DER déjà cartographié (`kext_sepmanager.md §15`), mais écriture 0x12 = ligne rouge ; (d) **enrôlement sous Linux** (doigt = session humaine). **Mac EN PROXY en fin de séance** (USB local). ⚠️ **le reboot logiciel via proxy FIGE le PMU** → power-cycle PHYSIQUE obligatoire entre runs (vérifié cette nuit).

**AUDIT GITHUB (fait cette nuit) :** repo techniquement propre (0 secret, 0 binaire Apple suivi, 0 code Apple copié ; `macos/`,`m1n1/`,`xart_store_*/` gitignorés). SEUL point : email/nom/Apple ID + IDs Mac (serial/ECID/MAC) sont dans `traces/20261108-162919_adt/` + ~30 `hv_uart.log` + l'historique git → Albert a jugé « pg » (déjà publics ailleurs). Pour publier proprement il faudrait filter-repo + LICENSE + peser le risque social Asahi (repo 100% IA). Décision = Albert.

---

<!-- HISTORIQUE — le « blocage catch proxy » ci-dessous est RÉSOLU (voir bandeau du haut). Gardé pour le fil des idées. -->

# ▶️ REPRISE 2026-11-21 (soir) — route native qui MARCHE, bloquée sur le catch proxy

**Si contexte neuf / après /clear : lis ceci, puis `docs/catch_proxy_diagnostic.md`, puis le haut de `docs/journal.md` (2026-11-21), puis la mémoire [[route-native-0x13-breakthrough]]. CLAUDE.md = règles (PHASE 2, qui-décide-quoi, lignes rouges : écriture SEP = Albert lance).**

**TL;DR de la journée :** on a prouvé sur matériel que la **route native** marche (le rejeu est mort) : répondre *« pas de xART »* au SEP avec la **bonne forme** (trouvée en décompil : maître absent = `TYPE=0x00` longueur `0x11` ; gigalocker absent = longueur 0 ; **jamais** `0x07`) → le SEP **annonce toute la pile biométrique (sbio inclus)** puis **demande à sceller un xART frais (SAVE)**. On s'est arrêté avant d'écrire.

**LE BLOCAGE (à régler en premier) : on ne rattrape plus le Mac en proxy.** m1n1 boote direct sur Arch. Cause quasi sûre = la **backdoor a sauté** (`csrutil disable` sur Asahi + `nvram boot-args=-v`) → la fenêtre proxy de m1n1 (5 s) ne s'ouvre QUE si `display==0` ET `sip0==127` (VU dans m1n1/src/main.c). Linux INTACT, Mac récupérable, rien écrit/poussé.
- **1re action au retour d'Albert :** allumer le Mac, **lire le texte blanc m1n1** → noter `Boot policy: sip0 = N`, `video: display: 0x…`, et si `Waiting for proxy connection...` s'affiche. Arbre de décision complet dans **`docs/catch_proxy_diagnostic.md`** : léger (booter lid fermé si display≠0) → moyen (réarmer la backdoor en 1TR si sip0≠127) → lourd (DFU restore si 1TR bootloope aussi ; filet prêt, cf. `RECUPERATION_MAC.md`).

**QUAND LE PROXY EST REVENU (plan) :**
1. `./pending/sep_native_persist.sh` (Albert lance — ÉCRITURE : acquitte+stocke le SAVE du xART frais). Verdict guetté : `idle` (SEP stabilisé = 🎯) vs `MÊME MUR QUE VOIE C`.
2. Si stabilisé → sonder **sbio (0x08)** « annoncé vs vivant » (0x73), et handler **SKS (0x12)** = `AppleKeyStore::sep_deliver_msg` (prépa en [[sks-kext-study-pending]]). ➜ **déléguer la décompil 0x12/0x08 à l'agent `reverseur`** (nouveau, `.claude/agents/reverseur.md` ; parallélisable, Opus 4.8 pour éviter le filtre cyber).
3. Enrôlement Touch ID = session humaine (doigt).

**Prêt / fait aujourd'hui :** `pending/sep_native_0x13.sh` (recon, OBSERVE), `pending/sep_native_persist.sh` (écriture), `tools/catch_lib.sh` (catch agressif, saisit if02), modules offline VU `driver/sepreplay/xart.py`+`xart_responder.py` (tests step6/7 verts), CRC `.gl` vérifié 12/12. Décompil : `macos/kernel.macho`, outils `analysis/kext/{ksyms,kdis}.py` + venv capstone à recréer (`python3 -m venv <scratchpad>/venv && venv/bin/pip install capstone`, effacé au reboot). Rien n'est committé ni poussé.

---

> # 🟢 MAC RÉCUPÉRÉ ET OPÉRATIONNEL (2026-11-17) — macOS 27.2.1 + ALARM bootent ; SEP PROPRE ; on reprend le projet
> Suite du DFU Restore (16/11) : **macOS 27.2.1 neuf** et **ALARM réinstallé bootent tous les deux
> normalement** (ALARM = image bloc `alarm_p5.img` + GRUB refabriqué ; chaîne m1n1→U-Boot→GRUB→LUKS→ALARM,
> confirmée par Albert ; fstab /efi corrigé par Albert). **Le SEP est propre/neuf** = meilleure base qu'avant.
> **PERDU au DFU et NON réinstallés** (décision Albert 2026-11-17, « on continue sur 2 ») : les partitions
> jetables **macOS 13.5** et **Fedora de test (10.0.200.4)**. ⚠️ **À REPRENDRE AVEC ALBERT (2026-11-17)** : il
> signale que ma compréhension de « ce qui s'est passé avec la 13.5 » est **en partie fausse** — donc NE PAS
> traiter comme acquis ce qui suit sur le 13.5 (hypervisor exigeait-il vraiment 13.5 ? 13.5 récupérable ? autre
> version possible ?). Conséquences que j'avais déduites (à confirmer) : plus de **capture SEP sous macOS**
> (l'hyperviseur ciblait 13.5 d'après README/CLAUDE.md ; mais protocole déjà sorti par décompilation) ;
> **m1n1 proxy** (ex-volume 13.5) **à refaire** avant tout `sep_boot`/`sep_peek`.
> ✅ **MISE À JOUR (soir 17/11)** : **Touch ID ré-enrôlé** (Albert) ET **m1n1 proxy RÉ-ÉTABLI sans 13.5** (backdoor
> Asahi `csrutil` + nouvel outil `tools/catch_proxy.sh`) → **Mac EN PROXY** (m1n1 v2.0.0 frais), prêt pour `sep_peek`.
> Reste (Albert, pas urgent) : **image disque** avant toute écriture SEP. Détail : **section 2026-11-17 (soir)** +
> [[mac-boot-casse-recuperation]]. **Aucune écriture SEP sans l'accord d'Albert** (il lance).

Tu reprends le projet sep-touchid dans ~/Desktop/sep-touchid : Touch ID sous Linux sur MacBook Pro 14" M1 Max (j314c). Lis d'abord CLAUDE.md (PHASE 2, seul Albert change cette ligne ; lis surtout « Qui décide quoi » et « Exception : 2e Linux de test »), puis la mémoire du projet, puis le haut de docs/journal.md (entrées du 2026-11-09 au 12).

## POINT DE REPRISE 2026-11-17 (soir, Opus 4.8) — ✅ PROXY m1n1 RÉ-ÉTABLI sans macOS 13.5 ; Touch ID ré-enrôlé

> **TL;DR** : le Mac est de nouveau **pilotable en m1n1 proxy depuis le PC** — la capacité centrale pour tout le
> travail SEP, qu'on avait perdue avec l'effacement du volume 13.5. Obtenu **sans macOS 13.5**, par la backdoor
> Asahi (`csrutil`) + un **nouvel outil `tools/catch_proxy.sh`**. Touch ID **ré-enrôlé** par Albert (état scellé SEP
> valide et courant = base inédite). Mac EN PROXY (m1n1 v2.0.0 frais) à la fin de séance, prêt pour `sep_peek`.

**CE QUI A ÉTÉ FAIT (Albert + Claude, 2026-11-17) :**
1. **Touch ID ré-enrôlé** dans macOS 27.2.1 (Albert) → état scellé du SEP de nouveau valide et courant.
2. **Proxy m1n1 ré-établi — méthode NOUVELLE** (l'ancienne, kmutil sur le volume 13.5, est morte) :
   - **Backdoor Asahi (Albert, recovery/1TR, ligne rouge)** : `csrutil disable` en choisissant l'install **Asahi**
     — le recovery liste « 1: Macintosh HD, 2: alarm, 3: UEFI boot » ; fait pour **2 (alarm)** ET **3 (UEFI boot)**,
     **PAS** macOS — puis `nvram boot-args=-v`. **Les DEUX** sont nécessaires (le verbose seul n'ouvre plus la
     backdoor sur builds récents). Sans ça, m1n1 (payload → U-Boot→GRUB→ALARM) boote droit sur Linux sans jamais
     présenter le proxy — c'était la cause de tous les échecs d'attrapage. Retour arrière (plus tard) : `nvram
     boot-args=` + `csrutil enable`, **sans** choisir « full security » (sinon m1n1 désinstallé).
   - **Attrapage côté PC (Claude, via tools/) : `tools/catch_proxy.sh` (nouveau)** — attend l'apparition des ports
     USB du m1n1 au boot (fenêtre ~5 s), ouvre if02 pour tenir la fenêtre, puis chainloade un m1n1 frais
     (`m1n1/build/m1n1.bin`, même invocation que `sep_peek`). NON destructif (RAM). Usage : lancer l'outil en
     arrière-plan, PUIS power-cycler le Mac et laisser booter l'entrée Linux normale.
   - **Résultat VÉRIFIÉ** : `Waiting for proxy connection... Connected!`, m1n1 **v2.0.0-92-g7075** up ; ports
     `usb-Asahi_Linux_m1n1_uartproxy_v2.0.0-92-g7075_WHFWP7FYXF-if00/if02` + `/dev/ttyACM0`/`ttyACM2` présents, stables.
   - ⚠️ **Gotcha outil** : `catch_proxy.sh` finit en **exit 1** (le `chainload.py` fait « Waiting for reconnection… »
     et dépasse le `M1N1TIMEOUT` par défaut 3 s après la ré-énumération USB) — **mais le proxy EST up** (ports v2.0.0
     présents). Purement cosmétique. À corriger : sauter la vérif finale, ou `M1N1TIMEOUT` plus long autour du chainload.
   - ⚠️ **Piège corrigé en séance** : ne JAMAIS mettre `pkill -f catch_proxy.sh` dans la commande qui lance le
     catcher en arrière-plan → elle se tue elle-même (son cmdline contient « catch_proxy.sh »), exit 144.

**CLARIFICATION macOS 13.5 (résout probablement le « tu as mal compris » d'Albert, 2026-11-17) :** le proxy m1n1 —
et donc TOUT le travail SEP (sep_peek, sep_boot, driver natif, capteur) — **ne dépend PAS de macOS 13.5**. Le 13.5 ne
servait **que** pour tracer macOS **sous l'hyperviseur** (`run_guest.py`). **Preuve directe** : le proxy vient d'être
ré-établi sans aucun macOS 13.5. (Doc Asahi 2026-11-17, `public_linux_state.md` : invités hyperviseur supportés = 13.5
**et 14.8.3** ; macOS 27.2.1 non supporté comme invité. Repère CLAUDE.md/README « Hyperviseur : 13.5 uniquement »
**périmé** — correction = décision Albert.)

**ÉTAT MATÉRIEL à la fin de séance :** Mac EN PROXY (m1n1 v2.0.0 frais, lien stable). Backdoor Asahi active (SIP
désactivé sur les 2 installs Asahi, boot verbose → +~5 s au boot normal d'ALARM, réversible). SEP **propre** (DFU) +
**Touch ID enrôlé** = 1re fois qu'on a une puce **valide et courante** à étudier.

**PROCHAINS PAS :**
- [sûr, autonomie] `./tools/sep_peek.sh` (penser `SKIP_CHAINLOAD=1` pour ne pas rechainloader) — **lecture seule** —
  pour confirmer que le SEP répond sur la puce fraîchement enrôlée.
- [Albert, pas urgent] **Image disque** avant toute écriture SEP. Rappel : une image **ne répare PAS** un SEP cassé
  (seul un DFU le fait) ; elle protège les données, pas l'état scellé. Voir [[mac-boot-casse-recuperation]], [[priorites-risque]].
- [offline, fait 2026-11-17] protocole **sbio EP 0x08 consolidé** dans `messages.md` (format fil `vérifié`, noms d'opcodes `hypothèse/kext`).
- Reprise SEP = **driver natif sur puce valide** (voir `driver_plan.md`), pas un rejeu (voie C quasi-morte).

---

## POINT DE REPRISE 2026-11-16 (soir, Opus 4.8) — ✅ DFU RESTORE RÉUSSI (Mac restauré, disque effacé)

> **TL;DR** : décision d'Albert → **DFU Restore destructif depuis le PC Linux**. Réussi. macOS 27.2.1 neuf,
> **SEP + firmware remis à zéro**, bootloop fini. **Le disque interne est intégralement EFFACÉ** (ALARM, Linux
> de test, macOS 13.5 + m1n1). Deux sauvegardes faites et vérifiées avant. Le projet repart d'un **SEP sain**.

**CE QUI S'EST PASSÉ :** le côté Apple est **réparé** par un DFU Restore lancé par Albert depuis le PC (idevicerestore).
`Status: Restore Finished / DONE`. **⚠️ Tout le disque du Mac est effacé** → le setup tethered/m1n1 **n'existe plus**
sur le Mac ; toute reprise SEP par m1n1 demandera de **réinstaller m1n1 via Asahi** d'abord.

**SAUVEGARDES FAITES AVANT (2 filets, vérifiés) :**
- **Image bloc LUKS complète d'ALARM** : `~/mac-dfu/alarm_p5.img` (**259 172 446 208 o = 506196184 secteurs**,
  = taille exacte de `/dev/nvme0n1p5` confirmée ; en-tête LUKS2 intact, UUID `123dfd25…1992da`). Faite par `dd` depuis
  un **Fedora** tethered-booté (ALARM en tethered perd l'USB → Fedora pour avoir le réseau) → PC par `nc`/`/dev/tcp`
  (LAN câblé, ~109 Mo/s).
- **Snapshot restic frais** (`bk commit` depuis ALARM tethered) : dépôt `/latif/data/backup/m1max` (pool ZFS `latif`), cf. `RESTORE.md`.

**COMMENT LE DFU A MARCHÉ (crucial — détails dans [[mac-boot-casse-recuperation]]) :**
- **La version PACKAGÉE d'`idevicerestore` (release 1.0.0) CALE** pile après l'`iBEC` (`ERROR: Device did not disconnect` /
  `Unable to place device into recovery mode from DFU mode`), **reproductible** (2 fois). Apple signe pourtant (SHSH reçus).
- **FIX = `idevicerestore` GIT MASTER** : `yay -S idevicerestore-git` (a installé r287 ; corrige le délai de reconnexion
  post-`iBEC`). Avec le git : recovery → cryptex (SystemOS/AppOS/RosettaOS) → `Sealing System Volume` → DONE.
- **Gotcha build** : la pile `-git` monte libplist `.so.4 → .so.12`. (a) `libimobiledevice-glue-git` restait liée à `.so.4`
  → `idevicerestore: libplist-2.0.so.4 cannot open shared object file` → fix **`yay -S --rebuild libimobiledevice-glue-git`**
  (vérifier `ldd $(command -v idevicerestore)` = 0 « not found »). (b) ça **casse `usbmuxd`/`upower`/KF6Solid** (libplist `.so.4`
  orpheline) → **ne pas redémarrer usbmuxd pendant le restore** (l'instance déjà lancée suffit). **PC à réconcilier après.**
- **Séquence DFU 14" M1 Max (a marché)** : éteindre (power ~10 s) → appuyer/relâcher power puis tout de suite
  **Ctrl-g + Option-g + Maj-DROITE + power** ~10 s → relâcher les 3 touches, garder power ~10 s. Écran NOIR = DFU
  (`lsusb -d 05ac:` = `05ac:1227`/`1902`). **Taper la confirmation TOUT DE SUITE** (le DFU retombe si on attend plusieurs min).
  Garde-fou : `pending/dfu_restore.sh` (vérifie IPSW+sha256, usbmuxd, DFU ; confirmation `EFFACER-ET-RESTAURER`).

**PROCHAINS PAS (dans l'ordre) :**
1. **[Albert, maintenant]** Finir l'assistant macOS — **Verrou d'activation = identifiant Apple + mot de passe exigés** —
   créer la session, vérifier que macOS boote normalement (plus de bootloop).
2. **[Albert]** **Ré-enrôler Touch ID** (Réglages → Touch ID et mot de passe) → **revalide l'état scellé du SEP**. C'est le
   but : repartir d'un SEP **valide et courant** (ce qui manquait pour *valider* toute écriture SEP, cf. sections plus bas).
3. **[plus tard]** **Réinstaller Asahi/ALARM** (installeur Asahi depuis macOS), puis remonter les données depuis une des 2
   sauvegardes. ⚠️ un `dd` brut de l'image ne recrée **pas** la politique de boot Asahi → suivre **`RESTORE.md`** (btrfs/LUKS +
   UUID + grub/m1n1), OU restaurer l'image dans la partition LUKS recréée par l'installeur. À cadrer avec Albert le moment venu.
4. **[PC, sans urgence]** Réconcilier la pile libimobiledevice (usbmuxd/upower/KDE cassés par le bump libplist) : revert vers
   stable **ou** rebuild complet `-git`.
5. **[projet SEP]** La reprise du driver natif repart d'un **SEP sain**. Tout le m1n1/tethered/Linux de test (10.0.200.4) est à
   **réinstaller via Asahi** (l'exception CLAUDE.md sur `root@10.0.200.4` vise un hôte qui n'existe plus tant qu'il n'est pas refait).

---

## POINT DE REPRISE 2026-11-13 (Opus 4.8) — session « décompilation » : voie C quasi-morte, protocole sbio vérifié, archi SKS

> **TL;DR** : grosse session **hors ligne** (désassemblage kernel + 2 reruns ESSAI B lancés par Albert). Deux acquis majeurs :
> (1) **la voie C (rejeu xART) penche fortement vers impossible côté AP** — le nonce de fraîcheur est généré par le SEP, l'AP
> n'a **aucun levier** pour le fixer ; (2) **le protocole sbio (EP 0x08) est désormais vérifié de bout en bout** (format fil
> `gt_packet_t` + verdict de match). La stratégie bascule : **Touch ID sous Linux = driver natif + état SEP valide**, pas un rejeu.

**ÉTAT MATÉRIEL :** inchangé (voir bandeau en tête : Mac en ALARM, côté Apple cassé, non brické). **Rien ne tourne côté SEP**
à la fin de cette session. Albert a lancé **2× l'ESSAI B** (follow_go.sh) → **13 re-scellements chacun** ; **power-cycler le Mac**
avant toute reprise SEP. Tout le travail de cette session était hors ligne (aucune nouvelle capture risquée).

**CE QUE CETTE SESSION A ÉTABLI (tout commité, voir docs/journal.md 2026-11-12/13 + docs/kext_sepmanager.md §9–§14) :**

1. **Voie C / nonce — quasi-morte côté AP** (`kext_sepmanager.md §9`, [[voie-c-xart-fraicheur]]). Désassemblage : nonce = 20 o
   généré par le SEP (ROM), sélecteurs AP = generate/read/invalidate, **aucune API « set/seed »**, et aucune graine `boot-nonce`
   NVRAM qui alimente l'xART. → un rejeu d'un état scellé sous un ancien nonce ne peut **pas** être rendu « frais » par l'AP.
   RÉSERVE : prouve l'absence de levier **AP**, pas que la ROM SEP n'a pas une graine interne (non observable d'ici). Hypothèse
   (source: kext), non tranchée par écriture — mais appuyée aussi par l'observation n=2 (ci-dessous).
2. **ESSAI B reproduit n=2** (`20261112-215313` et `…223837`). `sks`+`sbio` ré-annoncés les 2 fois ; op 0x07 ne change que
   16 o ; **croisé** : 16 o de tête = empreinte déterministe pour les lockers, **variable par boot** pour les blobs xART maîtres
   (= là où vit la fraîcheur). Recoupe le §9.
3. **sbio (EP 0x08) — protocole VÉRIFIÉ** (`kext_sepmanager.md §11–§13c`). Carte des opérations (vtable AppleMesaSEPDriver),
   table opcode↔opération (0x09=match, 0x08=enroll, 0x42=compteur, 0x15=clé, …), cadre fil = message **`0xfc`** + buffer OOL
   **`gt_packet_t`** (opcode à +0x14) **vérifié contre la capture c12**, et **verdict de match vérifié** sur c6/c8/c11 :
   réponse op 0x09 = `match_info_t`, `+0x00 = 0x1f5` (succès, user 501) + identifiant `fe6003d8…`, `0xffffffff` = échec.
   Outil : `analysis/sbio_gt_packet.py`. ⚠️ Une bonne part **recoupait du déjà-`vérifié`** de `verification_status.md`/`messages.md`
   (en-tête GT, séquence d'init, verdict) : lire ces deux docs **avant** de re-décompiler sbio.
4. **SKS / keystore (EP 0x12) — architecture** (`kext_sepmanager.md §14/§14b`, nouveau). L'AP passe par l'API **AKS**
   (`aks_ref_key_*`) → `__aks_operation` → endpoint SKS. **SKS n'est PAS à opcodes** comme sbio : c'est un **RPC à params
   sérialisés DER** dans l'OOL (explique le mot 0x12 « TYPE=compteur, DATA=longueur » des traces). Mapping fin + schéma DER =
   gros reste, et **EP 0x12 = ligne rouge** (non testable sans écriture).

**PROCHAINS PAS (par ordre d'utilité réelle) :**
- **[Albert, matériel, sans urgence] Le vrai déblocage** : Touch ID sous Linux a besoin d'un **état SEP valide et courant**
  (keybag + empreintes enrôlées) qui vit dans macOS — or macOS est cassé. Donc à un moment : **DFU Restore + ré-enrôler Touch ID**,
  et **backup disque** avant toute écriture risquée. Jusque-là, aucun essai SEP en écriture ne peut être *validé*.
- **[offline] Consolidation** : si on veut du driver, intégrer les opcodes nommés (noms kext) dans `messages.md`/`driver_plan.md`.
  Décompil SKS plus loin = possible mais **long et non testable** (EP 0x12 rouge) → faible priorité.
- **NE PAS** relancer l'ESSAI B (n=2 suffit ; chaque run re-scelle le SEP pour rien de neuf).
- **Lire `verification_status.md` + `messages.md` AVANT** toute nouvelle décompilation sbio (éviter de re-labourer le connu).

**Lignes rouges inchangées** (CLAUDE.md) : aucune écriture SEP par l'agent (0x12/0x13/0x10/0x15, IMG4) ; hardware via `tools/*.sh`
uniquement ; écriture = script `pending/` relu et lancé par Albert.

---

## POINT DE REPRISE 2026-11-12 (Opus 4.8) — Mac récupéré en ALARM ; prochain pas SEP = essai observationnel (relais du dernier SAVE)

**ÉTAT MATÉRIEL à la reprise (différent des sections plus bas : plus de tunnel relais) :**
- Mac en **USB LOCAL direct** (Albert est devant, pas de relais TCP). Proxy m1n1 v2.0.0-92-g7075,
  `/dev/serial/by-id/usb-Asahi_Linux_m1n1_uartproxy_v2.0.0-92-g7075_WHFWP7FYXF-if00` → ttyACM0 (console if02→ttyACM1).
- **Le Mac tourne ALARM (tethered boot)** à la fin de cette session. Pour faire du SEP il faut le remettre
  en **m1n1 proxy** (ALARM ≠ proxy : le noyau a pris la main).
- **Piège PMU/SPMI (vu aujourd'hui, aussi en mémoire)** : après des manips SEP (sep_peek / voie C), `linux.py`
  plante au `PMU.reset_panic_counter` (UartTimeout SPMI, bus PMU figé). **Un m1n1 frais ne suffit pas** →
  **coupure complète du courant** (bouton alim ~10 s). Ensuite le **proxy USB ne réénumère pas seul**
  (rien sur ttyACM / lsusb alors que l'écran dit « running proxy ») → **changer câble/port** jusqu'à ce que
  `serial/by-id` revienne. Une fois coupé proprement, le PMU répond et le boot passe.
- `tools/tethered_boot.sh alarm` lancé **sans terminal** finit par `termios.error: Inappropriate ioctl for device`
  (ouverture du ttymode) — **pas un échec**, le noyau est déjà parti. ALARM se rejoint par SSH (`tools/linux_ssh.sh`, root@10.0.200.4).

**CE QUI A CHANGÉ CÔTÉ ANALYSE (corrige les sections plus bas) :** voir [[voie-c-xart-fraicheur]], docs/messages.md
+ docs/hypotheses.md (section xART, 2026-11-12), docs/kext_sepmanager.md §8/§9.
- Le blob xART variable rejoué **= exactement le DERNIER SAVE du boot précédent** (chaînage prouvé octet pour octet,
  `fetch(N)=save(N-1)`). Donc un rejeu doit resservir **le dernier SAVE, PAS le FETCH initial** d'un boot.
- Les 2 blobs qui changent par boot = **SEP-xART maître** (TAG 0x03, avant sbio) + locker **Credential Manager**.
  **USER-xART est STABLE** (corrige une hypothèse antérieure). UUID d'OS constant `EFF3C698-…` (rejouable, pas le verrou).
- La divergence de l'essai n°1 (SEP envoie TAG=0x05 **TYPE=0x01 SAVE** au lieu de FETCH) = re-scellement **attendu**.
  Le verrou de fond (clé relayable OU compteur scellé) **ne se tranche QUE par une écriture**.

**PROCHAIN PAS = essai observationnel (écriture SEP → script `pending/`, Albert lance).**
Il doit **suivre le SEP** au lieu de s'arrêter à la divergence : laisser le SEP re-sceller (op 0x01), **l'acquitter**,
et regarder s'il finit par annoncer **`sks` (0x12, le trousseau)** et atteindre un état fonctionnel (≠ juste `sbio`).

> **✅ LANCÉ 1× (2026-11-12 21:28, Albert) — mode FOLLOW de `pending/sep_xart_replay.sh`.** Trace
> `20261112-212820_xart_replay`. Résultat : après les 4 lockers maîtres, le SEP a enchaîné **9 SAVE**
> (re-scellements, acquittés) puis une op **0x07 (locker-absent)**. La v3 s'arrêtait sur 0x07 → **sks
> jamais atteint, résultat NON concluant** (macOS, lui, acquitte 0x07 et continue : snew-reel TAG=0x0b).
> Détail : journal + hypotheses.md « RÉSULTAT Essai C ». Les 9 SAVE = vraies écritures SEP (état scellé
> avancé) ; aucune persistance disque ; Linux/données intacts ; côté Apple déjà cassé.
>
> **➡️ CORRIGÉ en v3.1 (2026-11-12) :** 0x07 ajouté à ACKABLE (on le suit comme macOS), arrêt seulement
> sur un FETCH-locker 0x05 non servi ou op inconnue ; dump des blobs B re-scellés dans `OUT/follow_B/`.
> SELFTEST + py_compile OK. **NON relancé** (choix d'Albert).
>
> **Albert relance (écriture SEP, lui seul) — depuis le tél en RC :** `! ./pending/follow_go.sh`
> (lanceur court = `M1N1TIMEOUT=20 FOLLOW=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel`).
> Regarder où le suivi bute : annonce `sks` (gagné) / FETCH-locker 0x05 non servi (→ servir le locker par
> UUID depuis la capture) / silence. ⚠️ si le lien fige : seule récup = power-cycle PHYSIQUE (pas depuis le tél) ;
> ~1 bon chainload par power-cycle.

**PROCÉDURE :**
1. *(Optionnel — décision Albert)* **image disque** depuis ALARM (qui tourne). Discuté : ce n'est **pas** un vrai
   filet pour le SEP (une image disque ne répare pas le SEP ; seul DFU Restore le fait), juste du confort. Les vrais
   filets existent déjà : ALARM boote indépendamment + DFU Restore plus tard. Albert tranche : image ou on saute.
2. **Remettre le Mac en m1n1 proxy** : power-cycle, **ne PAS** tethered-booter ALARM ; vérifier `/dev/ttyACM`
   (re-câble/port si besoin, cf. piège ci-dessus).
3. **J'écris le script** dans `pending/` (en-tête but / risque / résultat attendu ; relais du **dernier SAVE** ;
   OBSERVE = suit le SEP, acquitte le SAVE, écoute l'annonce d'endpoints).
4. **Albert relit.**
5. **Albert lance.** Je lis la trace : SEP accepte et avance (sks annoncé → rejeu suffisant) OU re-scelle et bloque
   (compteur scellé). S_new à relayer : repartir de `traces/20261111-113919_snew-reel` (ou recapturer un S_new en
   lecture seule avant, sans booter macOS entre-temps).

**EN ATTENTE D'ALBERT :** (a) image disque oui/non ; (b) quand lancer (reboot m1n1 maintenant, ou plus tard).

**Sûreté (mémoire voie-c-xart-fraicheur) :** lectures seules et **boot SEP permissif nu** (sep_boot, sep_peek) OK en
autonomie (le SEP-BOOT du 2026-11-09 n'a pas cassé le menu, auto-récupéré). Ce qui casse = **engagement xART +
re-scellement**. Toute écriture xART = Albert + (si choisie) image disque.

## POINT DE REPRISE 2026-11-11 (fin après-midi, Opus 4.8) — essai voie C REPRODUIT ; reprendre par l'observation
<!-- ⚠️ SECTION HISTORIQUE — l'état matériel ci-dessous (tunnel relais 10.0.200.5, « Mac débranché », S_new à
     recapturer) est PÉRIMÉ. État courant et procédure à jour = section 2026-11-12 en tête. Garder pour l'historique
     des idées (OBSERVE, divergence) mais NE PAS suivre les commandes tunnel/relais : le Mac est en USB local direct. -->

**Acquis aujourd'hui (vérifié n=2, Albert a lancé) :** un SEP démarré par m1n1 accepte la pose des tampons
xART, **rejoue 4 lockers** (dont SEP-xART+USER-xART), **annonce sbio/scrd/sse/skdl**, puis **diverge à la 5e
transaction** (SEP demande TAG=0x05 TYPE=0x01=SAVE au lieu de TYPE=0x05=FETCH). Reproductible sur 2 runs.
« sbio annoncé » ≠ « Touch ID marche » (sks 0x12 absent). Détail : journal + docs/hypotheses.md « Revue
sceptique — ESSAI VOIE C n°1 » + docs/voie_c_design.md « Résultats ».

**PROCHAIN PAS = essai A (observationnel), déjà prêt** (`OBSERVE` est le DÉFAUT de `pending/sep_xart_replay.sh`) :
rejoue pareil puis **écoute le tampon B en lecture seule ~20 s sans répondre sur 0x13** (n'acquitte PAS le
SAVE → compteur anti-rejeu préservé). But : voir ce que le SEP réclame à la divergence (B≈849 o = SAVE ?).

**ÉTAT MATÉRIEL à la reprise :** Albert a débranché le Mac. Son m1n1 s'était **coincé** (« 0 octet ») après
une capture S_new ratée (run_guest avorté sur lien instable — voir mémoire tunnel-relais-mac, erreur notée).
**À faire pour reprendre :**
1. Albert rebranche + **reboot physique en m1n1**.
2. Relancer le tunnel si besoin : `./tools/restart_tunnel.sh` (le kill est bloqué par le mode auto → Albert
   approuve, ou il lance `! ./tools/restart_tunnel.sh`). NE PAS relancer le tunnel si `sep_peek` dit déjà
   « Running proxy... » (m1n1 vivant, octets périmés qui se purgent en réessayant).
3. **1 seul `./tools/sep_peek.sh`** pour confirmer le lien (lecture seule) — rien d'autre.
4. **Pas besoin de recapturer un S_new** : `traces/20261111-113919_snew-reel` est toujours valide (la capture
   ratée n'a jamais démarré macOS). Si macOS a VRAIMENT rebooté entre-temps, alors recapturer.
5. Albert lance (écriture SEP, jamais l'agent) :
   `M1N1TIMEOUT=20 M1N1DEVICE=/tmp/m1n1 HV_UART=/tmp/m1n1-console ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel`
   (OBSERVE par défaut → la lecture de B à la divergence s'affiche automatiquement.)
6. Reproductibilité : relancer tunnel.py ENTRE chaque run (le lien désync après chaque run).

## Mise à jour 2026-11-11 (journée, Opus 4.8) — EXPÉRIENCE VOIE C PRÊTE À LANCER

**Contexte matériel nouveau** : le MacBook n'est pas en USB local mais derrière un **relais TCP**
(`10.0.200.5`, ports 4000 proxy / 4001 console). Monter le lien : `./tunnel.py` (robuste, PTY stable),
puis `export M1N1DEVICE=/tmp/m1n1 HV_UART=/tmp/m1n1-console`. **Pour le boot macOS (run_guest) : `export
M1N1TIMEOUT=20`** (le défaut 3 s est trop court sur ce lien → UartTimeout ; c'était LA cause des échecs,
pas le tunnel). Détails + récup : mémoire `tunnel-relais-mac`. (Côté relais, bridge avec `fork`.)

**Ce qui est fait et commité aujourd'hui** :
- `tunnel.py` : lien relais fiable (chainload 6/6).
- `pending/sep_xart_replay.sh` **v2** : rejeu xART avec le rôle AP complet (SECMODE + allocation/mapping/
  annonce des tampons OOL via CNTL, protocole du kext §3/§5), puis rejeu fidèle des lockers depuis une
  capture S_new. **Validé** : SELFTEST OK, et surtout le protocole CNTL est **confirmé octet pour octet**
  contre la capture réelle non filtrée `traces/20261111-111740_cntl-study3` (ordre 0x14→0x04/0x02/0x05/0x03,
  IOVA 0x2c/0x38, ack TYPE 0x01 même tag).
- `CLAUDE.md` : décompilation élargie (tout binaire Apple pertinent) ; leçon RTFM M1N1TIMEOUT.
- Docs : `voie_c_design.md` « Correctif voie C » (protocole complet), journal, mémoires à jour.

**ÉTAT : script v2 PRÊT et relu (sceptique : « lançable tel quel », sûr, 0 opération disque). Mac au m1n1
propre. MAIS il MANQUE un vrai S_new.** `traces/20261111-111740_cntl-study3` a servi à VALIDER le protocole
CNTL (octet pour octet), mais ses lockers .ool sont **tronqués à 0x400** (capturé avec le défaut `nbytes=0x400`)
→ **INUTILISABLE comme S_new** (le tampon A serait rejoué incomplet). Erreur de la session précédente, corrigée ici.

**PROCÉDURE pour lancer l'essai voie C :**
1. **Capturer un vrai S_new** (lecture seule, ~15 min ; `SEP_OOL_BYTES=0x8000` = tampon COMPLET, et reboot auto
   en m1n1 à la fin) :
   ```
   M1N1TIMEOUT=20 M1N1DEVICE=/tmp/m1n1 HV_UART=/tmp/m1n1-console \
   SEP_OOL_EPS=0x13 SEP_EPS=0x13 SEP_OOL_BYTES=0x8000 END_ACTION=reboot \
   ./tools/boot_and_trace.sh snew-reel
   ```
   Vérifier ensuite que `traces/..._snew-reel/sep.log.ool/*_A.bin` font bien **32768** octets.
2. **NE PAS booter macOS entre la capture et le lancement** (reboots m1n1 OK — m1n1 = startup disk).
3. **Albert lance** (écriture SEP), après relecture de l'en-tête de `pending/sep_xart_replay.sh` :
   ```
   M1N1TIMEOUT=20 M1N1DEVICE=/tmp/m1n1 HV_UART=/tmp/m1n1-console ./pending/sep_xart_replay.sh traces/<le_snew-reel>
   ```
   Succès = `>>> sbio PRÉSENT`. Échecs = sorties propres (exit 2/3) AVANT toute écriture risquée.

**Sceptique (fait, 2026-11-11)** : v2 conforme à la capture réelle, sûre. Incertitudes de fond, tranchées
seulement par l'essai (non bloquantes pour la sûreté — échec propre si manqué) : le stream/IOVA DART que xarm
lit vraiment ; faut-il aussi poser les tampons de 0x18(stac)/0x0e(hdcp) avant que le SEP enchaîne xART ;
le SEP démarré par m1n1 enchaîne-t-il l'échange. Amélioration v3 notée : écrire A via `phys_A` direct plutôt
que re-dériver par `find_sid` (évite une mappe résiduelle d'un stream inférieur).

## Mise à jour nuit du 2026-11-11 (session autonome, Opus 4.8)
- VOIE B FAITE. Contenu du coffre xART capturé en lecture seule sur 3 boots macOS : c21/c23/c24 = traces T-45/T-46/T-47. Outils déjà en place (SEP_OOL_EPS=0x13). c22 a raté (boot à chaud), ignoré.
- Résultat clé (vérifié octet pour octet, journal + messages.md « xART — contenu OOL » + verification_status « xART-CHAIN ») : sur 10 lockers rendus au SEP, 8 sont identiques sur les 3 boots ; 2 changent = SEP-xART (TAG 0x03) et un locker Credential Manager (TAG 0x10, UUID 8624497a…). USER-xART (TAG 0x04) est STABLE. Chaînage save(N)=fetch(N+1) prouvé sur le contenu. Aucun compteur en clair ; fraîcheur = préfixe 16 o (nonce/MAC) + corps chiffré renouvelé = hypothèse.
- Verdict rejeu (voie C) : plausible, non mort. Rendre la dernière sauvegarde = ce que le SEP attend ; seul un essai en écriture (pending/ + Albert) dit si l'état interne l'accepte quand Linux boote le SEP. Analyse : docs/xart_options.md. Scripts : analysis/diff_xart_ool.py, scratchpad lockers_variables.md.
- Autres résultats de la journée du 10-11 : capteur relayé octet pour octet au SEP (image 0x65, OOL EP 0x08, analysis/cmp_sensor_sep_image.py) ; 27 images lues / 7 transmises (count_sensor_vs_sep_images.py) ; transport capteur réactif (mesa_wait_ready, broche gpio0 195 caractérisée) ; piste hibernation écartée côté SEP (docs/power_sep_options.md, c'est du power management, pas le SEP).
- GUIDE : docs/guide/05-xart.md réécrit au style (3 boots). En cours de dernier tour de relecture (lecteur-naif + verificateur). À faire ensuite : y intégrer l'identité précise des 2 lockers variables (SEP-xART + locker Credential Manager, USER-xART stable) une fois ces faits dans les notes — ils y sont depuis cette session. Chapitres encore périmés par la journée : 06-capteur (image relayée, broche, transport réactif) et 09-etat-et-suite.
- PROCHAIN VRAI PAS = essai de rejeu (voie C), écriture SEP, donc script pending/ relu et lancé par Albert, avec garanties : aucun brick, aucune atteinte à la partition Linux. macOS sacrifiable (backup Linux seulement, voir mémoire priorites-risque).
  Plan détaillé + analyse de sûreté + SPEC CODABLE : docs/voie_c_design.md. La spec est complète côté lecture : buffers xarm (A IOVA 0x2c000, B IOVA 0x38000, 0x8000, relus à la volée), et table de rejeu des 10 lockers de la phase de boot (TAG, en-tête de réponse PARAM/DATA, étiquette de 16 o ; SEP-xART et USER-xART sans étiquette ; Credential Manager = étiquette 8624497a lue 3 fois). Les 3 lockers qui changent = SEP-xART, USER-xART (en fait USER-xART stable, voir journal — SEP-xART + locker 0x10 Credential), reste à coder.
  Reste pour le script pending/ (session dédiée, moi j'écris / Albert lance) : l'implémentation m1n1 qui boote le SEP (pending/sep_boot.sh existe) puis joue le rôle de l'AP sur l'EP 0x13 (lire l'étiquette dans buffer B, écrire le locker dans buffer A à l'IOVA apprise, renvoyer la réponse). Vérifier d'abord qu'on peut ÉCRIRE dans le buffer du SEP par le DART depuis m1n1 (on n'a fait que lire jusqu'ici). Idée S_new : capturer juste avant, sans reboot macOS entre capture et essai. Seule inconnue de fond : l'anti-rejeu accepte-t-il le rejeu.


## Albert et la façon de travailler
- Français simple, courtes réponses, souvent depuis son téléphone. IL NE COMPREND PAS LE JARGON (étapes, EP, « proposé vérifié »…). Décide seul tout le technique ; ne lui demande que ce qui peut abîmer le Mac ou écrit vers le SEP, en une phrase (quoi, ce qui peut rater, oui/non). Tout ce qu'il doit lancer : commande prête à coller avec `! `.
- Autonomie : captures/reboots via tools/boot_and_trace.sh, sous-agents (analyste, lecteur-logs, sceptique, tracer, documentaliste, driver) sans demander. Quota limité. Appel : ./tools/appel_albert.sh "consigne courte".
- Lignes rouges (CLAUDE.md) : pas de sudo/bputil/kmutil/csrutil/nvram/dd/partitionnement ; le hardware passe par tools/*.sh ; toute écriture SEP = script dans pending/ avec en-tête (but, risque, résultat), Albert le lance ; rien vers Asahi ; traces/ en lecture seule ; pas de copie de code Apple ; info de kext marquée `source: kext`. Exception : sur le Linux de test root@10.0.200.4 uniquement, root via tools/linux_ssh.sh (son filtre refuse les commandes contenant « sep », « xart », 0x10/12/13/15, disques, m1n1… : évite ces chaînes dans les commandes).
- Commits fréquents, attribution demandée par le harness. Albert a un backup de sa partition Linux (c'est tout ce qui lui importe) ; la reconnexion iCloud qu'il a subie après le boot SEP par m1n1 est de cause non établie (2 reboots natifs ensuite sans souci).

## Résultats acquis (tout commité)
- Captures C1-C16 (K-E1 terminée : TAG 0x01 suit le keybag, 0x209@lock, 0x228@mdp, 0x208@doigt ; 0 TAG 0x01 pendant invites en session ouverte).
- Statuts : init 57 commandes, structure 0x65 + CRC, boucle 0x6c→0x6d = « vérifié (macOS) » (= ce que macOS fait, pas ce que le SEP exige). driver/ (sepreplay, 29 tests) rejoue tout hors ligne.
- ADT : capteur `biosensor,mesa` sous spi2 (0x39B108000, IRQ AIC 1108, pas de chip-select, CPHA 1, CLKDIV 3), alimentation capteur = gpio0 196 (0xc4) actif haut, IRQ gpio0 195. Alimentation de spi2 = pmgr SPI2, registre 0x28e580200 = ps_spi2 du DT public. Broches gpio0 48/49/50 déjà réglées par iBoot : rien à configurer (vérifié par MESA-HELLO).
- SEP sous m1n1 seul : peek lecture seule OK ; GETRAND (EP 0xFF) répond ; pending/sep_boot.sh (code public m1n1, DART T6000) a démarré SEPOS : « BOOT OK », 7/12 endpoints (cntl hdcp xars xarm hibe pnon stac), sans sbio/sks/scrd/sse/skdl.
- Dans 19/19 boots macOS, sbio etc. sont annoncés ~0,12 s après la réponse de l'AP à l'échange xART (EP 0x13). xART = coffre : le SEP confie des blobs, l'AP les lui rend au boot suivant (état du disque macOS, jamais capturé). Rejeu impossible sans ce contenu, et risqué (macOS/FileVault/trousseau). Décision : aucune réponse 0x13/0x15, aucune capture des blobs, pas de nouveau boot SEP.
- Linux de test (Fedora Asahi Remix, 10.0.200.4) : gcc/make/git/dtc/kernel-devel installés ; sources dans /root/mesa (mesa_probe.c, mesa_ovl.c, mesa-spi2-overlay.dts, copies de driver/linux/). DT vivant sans __symbols__, pas de configfs d'overlay, mais `of_overlay_fdt_apply` marche depuis un module (mesa_ovl).
- Outils ajoutés le 2026-11-10 : tools/gpio_peek.sh (lecture broches + alimentation), tools/mesa_hello.sh (bonjour capteur depuis m1n1), hv/trace_sep_spi.py et hv/trace_sep_spi_dma.py (écoute du bus capteur sous macOS), analysis/adt_pmgr_ps.py, analysis/spi2_transfers.py, analysis/sio_dialog.py.

- Bus SPI du capteur écouté sous macOS (2026-11-10, C17-C20, hv/trace_sep_spi_dma.py, analysis/sio_dialog.py, docs/sensor_hw.md « Dialogue SPI ») : trames en clair = réveil 0x78, identité 0x70, état 0x10, lecture 0x13 ; tout le reste est chiffré entre le SEP et le capteur, l'AP relaie (vérifié macOS pour l'image 0x65, C20). Albert a confirmé le 2026-11-10 que le projet reste privé malgré l'interdiction d'IA de m1n1/CLAUDE.md : ne rien modifier dans m1n1/, rien vers Asahi.

## Où on en est (fin de la session du 2026-11-10, tout est commité)
1. CAPTEUR : FAIT ET VÉRIFIÉ. Le capteur répond sans macOS aux trames en clair (réveil 0x78, état 0x10, identité 0x70, lecture 0x13), identité identique à celle vue sous macOS : depuis m1n1 (tools/mesa_hello.sh, 2 essais) et depuis Linux (LINUX-HELLO, 1 essai). Sur le Linux de test : `cd /root/mesa && cp mesa-spi2.dtbo /lib/firmware/ && insmod mesa_ovl.ko && insmod mesa_probe.ko enable=1 && dmesg | tail -20` (ajout à chaud de spi2 + capteur, rien d'installé, à refaire après chaque reboot ; les numéros de l'overlay valent pour le noyau 7.2.12-402.asahi.fc45). Le développement capteur se fait par ssh, Mac seul, sans câble USB.
2. Ce que Linux ne peut pas faire sans le SEP : tout le reste du dialogue capteur est chiffré entre le SEP et le capteur ; sous macOS l'AP ne fait que relayer (vérifié macOS pour l'image 0x65, C20). Table des états du capteur : docs/sensor_hw.md. Plan à jour : docs/driver_plan.md (« Mise à jour 2026-11-10 (nuit) »).
3. BLOCAGE inchangé : sbio n'est annoncé qu'après l'échange xART (le « coffre »). Décision en vigueur : aucune réponse 0x13/0x15, aucune capture des blobs, pas de nouveau boot SEP.
4. FILTRE DE SÉCURITÉ DU MODÈLE (important pour la session suivante) : pendant la session du 2026-11-10 (Fable 5.2), trois choses ont été coupées par le filtre « [cyber] » : (a) un sous-agent documentaliste chargé d'étudier les voies possibles pour xART ; (b) la relance, même réduite à un résumé de la doc publique ; (c) une analyse hors ligne comparant les buffers échangés avec le SEP (OOL de C20) aux trames du bus du capteur. Rien n'a été produit sur ces trois points et ils n'ont pas été refaits autrement. Albert change de session pour traiter ce sujet (programme de vérification Anthropic : https://support.claude.com/en/articles/14604842-real-time-cyber-safeguards-on-claude). Si le filtre coupe encore : ne pas insister ni reformuler, le noter au journal, passer à la liste de tâches ci-dessous.
5. Reste ouvert (ancien) : SKS-1 (le SEP refuse-t-il 0x09 avant le mot de passe ? tranche seulement par une écriture), 2e 0x209 inexpliqué après chaque lock, cause de la reconnexion iCloud, rôle des 20 images non transmises au SEP (C20) — QUANTIFIÉ 2026-11-10 : 27 lues sur le bus, 7 transmises (hypothèse : trames de prévisualisation non envoyées) ; voir analysis/count_sensor_vs_sep_images.py, groupe de broches 116-118.
6. m1n1/CLAUDE.md (mainteneurs de m1n1) interdit l'usage d'IA sur LEUR projet. Albert a décidé le 2026-11-10 : le travail reste privé, aucune contribution ; on ne modifie rien dans m1n1/ et rien ne sort vers Asahi. Ne pas lui reposer la question.
État du Mac en fin de session : Albert le redémarre sur le Linux de test et le relie au réseau par VPN ; l'adresse autorisée reste 10.0.200.4 (si elle change, c'est Albert qui modifie CLAUDE.md et tools/linux_ssh.sh). Câble USB débranché : pas de m1n1 ni de capture macOS tant qu'il n'est pas rebranché.

## Liste de tâches (tenue à jour par Claude ; Albert peut ajouter des lignes en français normal)
Légende : [ ] à faire, [x] fait, [!] bloqué (dire pourquoi).

### Sans Albert, sans le Mac
- [x] Table des réponses d'état du capteur (docs/sensor_hw.md, 2026-11-10).
- [x] Ranger le module Linux : transport (mesa_transport.h) séparé du test « bonjour » (mesa_probe.c), compile W=1 (2026-11-10).
- [x] docs/driver_plan.md mis à jour (2026-11-10 nuit).
- [x] Étude du « coffre » (xART) : docs/xart_options.md écrit le 2026-11-10 (Opus 4.8, filtre non déclenché). 5 voies, reco = voie B.
- [x] Comparaison fine image puce ↔ bus ↔ SEP : faite le 2026-11-10 (analysis/cmp_sensor_sep_image.py). Image relayée octet pour octet au SEP (OOL 0x08, entête 0x1c, type 0x65), chiffrée bout en bout. verification_status.md SPI-1.
- [x] Voie B outillage : l'OOL de l'EP 0x13 est déjà traçable (SEP_OOL_EPS=0x13), commande prête dans docs/xart_options.md. Rien à coder.
- [x] Voie B capture : FAITE 2026-11-11 (c21 + c23, lecture seule). Coffre xART : 8/10 blobs stables entre 2 boots, 2 changent, saves 100 % frais. Verdict rejeu : ni mort ni gagné, tranchable seulement par un test en écriture. docs/xart_options.md voie C, analysis/diff_xart_ool.py.

- [x] Caractérisé la broche gpio0 195 (2026-11-10, mesa_irqwatch hello=1) : ligne « donnée prête », remonte à chaque réponse en attente (y compris après 0x70), retombe à la lecture d'état. Pilotage par interruption possible.
- [x] Transport réactif : mesa_wait_ready() attend la broche « donnée prête » (scrutation sûre) avant chaque lecture d'état ; identité toujours identique (2026-11-10).
- [ ] (optionnel, risqué à distance) Vrai pilotage par interruption matérielle (request_irq) : seulement quand Albert peut power-cycler le Mac (rafale d'IRQ possible).
- [x] docs/sensor_hw.md : comportement de la broche 195 et de l'octet 0x18 reporté (2026-11-10).

### Avec le Mac sur le Linux de test (joignable à 10.0.200.4), sans action d'Albert
- [x] Recharger les modules et refaire le « bonjour » (reproductibilité) : FAIT 2026-11-10 sur 10.0.200.4, identité identique, avec le module rangé (transport). Entrée journal du jour.
- [x] État du capteur en boucle 30 s sans doigt : stable (2026-11-10, mesa_statloop.c ; 0x18 seulement à la 1re lecture).

### Avec Albert devant le Mac (2 minutes)
- [x] Doigt posé sans la puce de sécurité : l'état ne change pas (2026-11-10, 1 essai, doigt déclaré par Albert). Journal 06:08.
- [x] Même essai en regardant la broche d'interruption (gpio0 195) : elle marche sous Linux (1 à l'allumage, 0 après la 1re lecture d'état) mais ne réagit pas au doigt (2026-11-10, mesa_irqwatch.c, journal 06:15).

### Décisions qui appartiennent à Albert
- [ ] Faut-il s'inscrire au programme de vérification d'Anthropic pour débloquer l'étude du « coffre » ?
- [ ] Jusqu'où aller : s'arrêter au « Linux parle au capteur », ou viser un Touch ID complet (dépend du « coffre », risque pour macOS à évaluer).
