# Journal

Une entrée par observation, capture ou décision. Plus récent en haut.

Format :
```
## AAAA-MM-JJ HH:MM — <agent ou Albert> — <titre>
- Trace : traces/<dossier> (ou —)
- Fait : ce qui a été fait
- Vu : ce qui a été observé (faits bruts)
- Interprété : ce qu'on en pense (hypothèses → docs/hypotheses.md)
- Incidents : gels, timeouts, reboots
```

---

## 2026-11-22 — Claude (agent driver, session ALARM) — J5 compilé : relais sbio noyau (/dev/sep_sbio) + sbiod (spidev/gpio) ; ouverture précoce `sbio_open`
- Trace : — (compilation et tests hors ligne seulement ; rien chargé, aucun accès matériel).
- Fait : `sep_native.rs` : paramètres `allow_sbio_relay` (défaut 0) et `sbio_open` (défaut 1 = précoce, 0 = tardive) ;
  ouverture précoce de sbio dès l'ack de l'annonce 0x1d 'sbio' (entrelacée avec le xART, acks CNTL par TAG, Halted si
  absent), 0x73 toujours après 2 s de calme ; relais typé `/dev/sep_sbio` (liste blanche ordonnée 0x17 0x15 0x16 0x42
  0x18 0x5f, longueurs exactes, gt_packet construit par le noyau, réassemblage fe/fd contrôlé, notifications TAG 0x01-0x04
  remontées). `sep-proto/src/sbio_gate.rs` (porte partagée), `sensor.rs` (trames relais, prélude, octet 0x29). Nouveau
  démon `driver/rust/sbiod` (spidev + gpio cdev v2, séquence 1→4, VERDICT). Scripts `pending/j5_sensor_run.sh`,
  `pending/j3_chained_run.sh` ; `j3_sbio_run.sh` passe `sbio_open=0`. Doc `driver/rust/kmod/SEP_NATIVE.md` points 9-10.
- Vu (hors ligne) : les gt_packets construits par la porte = octet pour octet les A8 de c12 (000300..000313) ; les B8 de
  c12 passent la porte, patch réassemblé 0x568e o ; run complet contre faux SEP/capteur OK. Phandles de
  `mesa-spi2-overlay.dts` (0x13, 0x31, 0x48) relus sur le DT vivant d'ALARM : inchangés. gpio0 = `gpiochip4`
  (sous `39b028000.pinctrl`, à côté de proxys `gpiolib_shared`) sur ce boot. `build.sh CLIPPY=1` : 0 avertissement ;
  cargo test/clippy verts (sep-proto, sepd, sbiod).
- Interprété : rien de neuf sur le protocole. Le push en PIO noyau (≈22 ms nominal à 8 MHz, IRQ par demi-FIFO) reste
  l'inconnue de J5 ; l'ouverture précoce reste à éprouver (j3_chained_run.sh).
- Incidents : aucun.

## 2026-11-22 (reprise, bloc autonome) — Règle SEP-depuis-Linux OUVERTE + roadmap + paquet de mission agent-Mac
- Trace : — (travail doc/code, aucun hardware ; Mac laissé en proxy, inutilisé).
- Fait : (1) Albert a autorisé l'ouverture de la ligne rouge + « étape 6 » → **CLAUDE.md « Exception 2e Linux de test » RÉÉCRITE** : SEP désormais autorisé depuis le Linux de test (sbio/SKS/xART/IMG4/DMA capteur) avec la MÊME discipline qu'en m1n1 (fail-closed, DFU+alarm_p5, 1er run classe/script neuf = go Albert, power-cycle = Albert, jamais Stockholm direct ; toujours interdit : disques/boot/m1n1/partition/macOS). (2) `documentaliste` a rendu `docs/linux_roadmap.md` (J0→J6, écarts à coder, lignes rouges par jalon). (3) Écrit `driver/linux/MISSION_AGENT_MAC.md` (paquet de mission auto-suffisant pour l'agent Claude qu'Albert lancera côté Mac sous Linux) + `driver/linux/env_probe.sh` (sonde T1 lecture seule : spi2/spi-apple, **sio/dart-sio/apple-sio = point décisif**, sep présence, gpio).
- Vu / rappels : apple-sio EXISTE et **boote le SIO** sous Linux (≠ m1n1) mais est **cyclique/TX-only** ; `spi-apple` reste **PIO-only** (pas client dmaengine) → le push 22 Ko DMA reste un écart à coder. `sep.rs` = amorceur (EP 0xff/0xfd), **pas** de transport 0x08/0x12/0x13 → à coder. Touch ID = « TBA » chez Asahi (terrain vierge). Mur de fond = J4 (xART/Secure Storage Component), inchangé.
- ⚠️ À FAIRE (flaggé, non fait seul car garde-fou sécurité) : le filtre `DENY` de `tools/linux_ssh.sh` bloque encore `sep|xart|gigalocker|0x1[0235]` → contredit la règle ouverte ce jour ; à ajuster pour n'interdire que disques/boot/m1n1/Stockholm. Proposé à Albert.
- Prochain pas : quand Albert boote le Mac **sous Linux** et lance un agent là-bas, lui transmettre `MISSION_AGENT_MAC.md` ; T1 (env_probe) + T2 (bring-up capteur) sont autorisés tout de suite ; J2+ (SEP) = go d'Albert + filtre ssh ajusté.
- Incidents : aucun.

## 2026-11-22 (reprise) — DÉCISION ALBERT : cible = Linux natif SANS tether + verdict DMA m1n1 (tracer)
- Trace : — (décision + étude documentaire, aucun hardware).
- Fait : (1) agent `tracer` a investigué la faisabilité d'un push DMA SIO 22 Ko depuis m1n1 proxyclient (lecture seule, rien modifié sous m1n1/) → `docs/voie_sbio.md` §8. (2) Albert a décidé la direction stratégique. (3) Lancé `documentaliste` pour la roadmap Linux → `docs/linux_roadmap.md` (en cours).
- Vu / conclu (tracer, §8) : **DMA SIO BLOQUÉ en m1n1.** Le proxyclient sait allouer un buffer contigu (`p.memalign`+`writemem`) et mapper un DART (`dart-sio`, API `iomap`), MAIS **aucun driver du coprocesseur SIO** : `fw/` n'a pas de module `sio`, le seul code SIO est un OBSERVATEUR (`hv/trace_*`), et `m1n1/src/sio.c` ne boote pas le SIO (il prépare juste les fwdata pour l'OS invité). En route native (SEPOS seul, sans macOS) **personne ne boote le SIO** → DMA mort. Le FIFO marche justement car il n'exige aucun coprocesseur. Faire du DMA en m1n1 = écrire un pilote SIO RTKit complet (bring-up + mailbox Setup/Config/SetupIO canal 0x18) = gros chantier inexistant.
- DÉCISION ALBERT : **cible finale = pilote Touch ID Linux NATIF, ne plus dépendre du m1n1-proxy tethered** (PC USB + power-cycle). Albert veut « tout, à terme » sous Linux, pour être mobile (SSH). m1n1 = échafaudage de reverse. Raison technique renforçante : **Linux boote le SIO (`apple-sio`) et fait le DMA nativement** → le mur du DMA (notre blocage) se dissout côté Linux. Mémoire [[cible-linux-natif-sans-tether]].
- Verrous identifiés (à ouvrir par Albert, pas par un agent) : SEPOS sous Linux (alias DT `sep` + IMG4 = écriture réservée = « étape 6 » driver_plan) ; ligne rouge CLAUDE.md « pas d'envoi au SEP depuis le Linux de test ». Capteur+DMA seuls sous Linux = déjà autorisés (sans SEP).
- Incidents : aucun. Mac encore en proxy (catcher en fond) ; Linux intact.

## 2026-11-22 (reprise, Opus 4.8) — sbio11 RUN : attendre l'IRQ ne débloque rien ; patch toujours non chargé (`0x60`) — « on lisait trop tôt » RÉFUTÉ
- Trace : traces/20261122-144709_native_sbio9 (⚠️ dossier mal nommé `native_sbio9` : le NAME interne du script copié n'a pas été changé ; c'est bien le run de `pending/sep_native_sbio11.sh`, store neuf `xart_store_sbio11_1`). Lancé par Claude (go d'Albert), proxy m1n1 v2.0.0 rattrapé par `tools/catch_loop.sh`, power-cycle Albert.
- Fait : route native complète refaite (persist → 0x73 sbio vivant → 0x17 → key exchange 0x15/0x16 → compteur 0x42/0x18 → patch 0x5f reçu+réassemblé 22158 o) PUIS push (prélude 0x60 + bloc en 2.2s) PUIS **boucle d'attente sbio11** (IRQ gpio195 + relecture st[8] pendant 1.5s, lecture seule).
- Vu (faits bruts, `push_load_trace.txt`) : état capteur AVANT push = `…60 00 00 00…` (sans correctif, bien formé). Après push, sur 1.5s de poll : IRQ gpio195 **haute aux 3 premiers reads (t=0.000→0.110) puis basse** ; **un seul read propre** (t=0.110) = **st8=`0x60`** (SANS correctif) ; **tous les autres reads = tout zéro** (pas de trame status valide). st8 n'atteint **JAMAIS** `0x29`. Phase 7 non lancée (fail-closed, critère strict). Capteur power_off+restore. Compteur +12.
- Interprété : (1) **attendre/poller l'IRQ ne révèle AUCUN patch chargé** → l'hypothèse « on lisait trop tôt » (sbio11) est **RÉFUTÉE** : même en attendant, le seul état propre lisible est `0x60` = sans correctif. Le mur est réel, le capteur **n'accepte pas le bloc poussé**. (2) **L'IRQ gpio195 n'est PAS un signal fiable « patch load done » dans notre montage** (haute dès t=0, avant tout traitement, puis basse) — à ne pas sur-interpréter ; l'interprétation auto imprimée par le script (« IRQ montée ⇒ rejet crypto ») est **invalide** car st=tout-zéro ≠ trame valide (bug de lecture : je n'ai pas gaté sur en-tête `80 20 00 10` avant de lire st[8]). (3) Les **zéros** = l'interface SPI du capteur répond mal au status juste après les 22 Ko (instable). (4) L'état propre `0x60` = « prélude pris, attend le bloc » (= état macOS AVANT le bloc, cf. C19) plutôt qu'un état d'erreur post-réception → penche (faiblement) vers **(A) réception du bloc non terminée** (timing/trous d'horloge du FIFO ~2.2s vs 74ms DMA) plutôt que (C) rejet crypto. NON tranché proprement (IRQ inexploitable ici).
- CONSÉQUENCE : le test pas cher est épuisé. Prochain = **pousser le bloc vite et contigu comme macOS = DMA SIO** (le vrai « extremely involved »), chaîne kext déjà cartographiée (sbio_session.md §3b). À défaut, un push FIFO bien plus rapide (moins d'allers-retours tunnel) pour re-tester (A). Décision Albert sur l'ampleur.
- Incidents : dossier trace mal nommé (cosmétique, NAME interne à corriger dans sbio11). RAS matériel ; Linux intact ; DFU + alarm_p5.img prêts.

## 2026-11-22 (reprise, Opus 4.8) — CORRECTION : le patch NE charge PAS (l'état `60000008` post-push est un état « SANS correctif ») — sbio8/9 relus
- Trace : relecture seule de traces/20261122-041705_native_sbio8 + 045408_native_sbio9 (jamais journalisés avant) ; recoupe docs/sensor_hw.md l.112-115.
- Fait : parse des `push_status_apres.bin`, `p7_00_0x5d_status.bin`, `wall_summary.txt`, `native_sbio9.log` des deux runs. Aucune action hardware.
- Vu (faits bruts) : état capteur 0x10 **après push** (sbio8 ET sbio9, identiques) = `80 20 00 10 | 00000000 | 60 00 00 08 | 52 33 00 00`, soit les 9 o d'état `00 60 00 00 08 52 33 00 00`. `sensor_hw.md` l.112 liste **`…08…` comme VARIANTE de l'état « repos capteur SANS correctif » (octet 2 = `60`)** ; l'état « correctif chargé » est `00 29 01 00 7c 52 33 00 16` (octet 2 = `29`, l.115). Au 1er param 0x5d → état capteur = **tout zéro** (en-tête ≠ `80 20 00 10`) → STOP fail-closed. Le SEP, lui, produit bien le 0x5d (B8 `…5d…3a…` chiffré) ; c'est le CAPTEUR qui refuse.
- Interprété : **le patch ne s'active pas.** La conclusion du 03:42 (« état `60000000`→`60000008` = push accepté ») était une **sur-lecture** : `60000008` n'est pas « chargé », c'est la variante `…08…` de « SANS correctif ». Le transport SPI marche (CS tenu, 22158 o en 2.3-2.4 s, pas de timeout — ça, acquis sbio7), mais le capteur **reçoit les octets et rejette/n'active pas** le patch. La bannière FIN du handoff (« CS lâche → DMA ») **mal-diagnostique** : le DMA est un faux problème. Candidats réels (à trancher par décompil LoadPatch) : (a) cadrage du bloc poussé (prélude/longueur/CRC/trailer), (b) étape verify/activate manquante après le push, (c) patch chiffré lié à la clé de session 0x72 mal établie côté capteur, (d) attente IRQ gpio0 195 avant relecture. Agent `reverseur` lancé sur le protocole LoadPatch côté kext.
- Recoupe trace C19 (`analysis/sio_dialog.py traces/20261110-002829_c19-spi-dma-boot`, lecture seule) — séquence d'état macOS autour du patch (lignes sio_dialog 40-48) : `…60000000` (idle) → TX prélude `80 60 00 07` → `…60000008` (**prélude pris, attend le bloc**) → TX bloc `0x568e` (UN transfert, **74 ms**) → `…2901007c` (**chargé**) → SEULEMENT APRÈS, TX `80 55 00 40` (1er param 0x5d). ⇒ (1) **AUCUNE commande verify/activate** entre le bloc et l'état chargé (candidat (b) écarté) ; (2) **notre état final `60000008` = l'état macOS APRÈS le prélude mais AVANT le bloc** → chez nous le bloc **n'a pas fait avancer** le capteur (resté « attend le bloc »), le capteur n'a PAS accepté le bloc. Piste forte réorientée : macOS pousse le bloc en **74 ms (DMA)**, nous en **2.3 s (FIFO/tunnel, ~30×)** avec trous d'horloge entre remplissages FIFO → **fenêtre de réception capteur probablement expirée** → bloc abandonné. ⇒ le DMA SIO pourrait être requis pour la **vitesse/continuité d'horloge** (PAS pour le CS, qui tient). À trancher : reverseur (kext) + test « push plus rapide » si faisable sans DMA complet.
- Incidents : aucun (lecture seule).

## 2026-11-22 03:42 — Albert (go) + Claude (LANCE, 1er lancement autonome) — 🎯🎯 PATCH POUSSÉ au capteur en FIFO (22Ko en 2.4s, PAS de DMA) : le dernier mur SPI dur tombe
- Trace : traces/20261122-035658_native_sbio7 (patch_spi_push.bin, push_status_avant/apres.bin). **1er lancement par Claude** après « go » d'Albert (règle relâchée 2026-11-22).
- Fait : `M1N1TIMEOUT=20 XART_STORE=…xart_store_sbio7_1 ./pending/sep_native_sbio7.sh` (Claude lance seul). KX + compteur + réception patch (fe/fd, 22158o) OK. PUSH : état capteur avant `80200010…60000000…` → prélude `80600007` + **bloc patch 22158o émis en UN transfert FIFO en 2.4s, SANS timeout** → état capteur après `80200010…60000008…` (BIEN FORMÉ + CHANGÉ). Teardown OK.
- Vu (faits bruts) : le bloc de 22158o passe en FIFO scruté en **2.4s**, le contrôleur SPI2 **tient le CS asserté** (aucun timeout sur 60s de marge), l'état capteur 0x10 change (`60000000`→`60000008`). → **le FIFO suffit, PAS besoin du DMA SIO.**
- Interprété : **LE DERNIER MUR SPI DUR EST TOMBÉ** — le push du patch marche en FIFO. RÉSERVE : « status changé + bien formé » = push **accepté** (signal fort) ; « patch pleinement chargé » reste à confirmer en enchaînant les **params 0x5d/0x5c/0x55** (si le patch n'était pas chargé, le capteur les refuserait). Reste : params (faciles, même relais), n° série module, calibration (mailbox, pas SPI), puis **enroll + match (doigts, session humaine)**.
- Incidents : RAS. Compteur anti-rejeu +12 (xart_store_sbio7_1). Capteur restauré. 1er lancement autonome par Claude = OK.

## 2026-11-22 03:30 — Albert — DÉCISION : règle de lancement SEP RELÂCHÉE
- Albert relâche la ligne rouge « seul Albert lance les écritures SEP » (CLAUDE.md, « Écriture SEP » + « Qui décide quoi »).
- NOUVELLE RÈGLE : Claude **lance lui-même** les scripts `pending/` **déjà éprouvés** (relus + déjà tournés propre sur matériel : classe route-native/sbio-climb = boot IMG4, ACK SAVE xART 0x13, relais capteur 0x08). Toute **classe jamais testée** (gigalocker en écriture, SKS 0x12 écriture, enrôlement, **1er run d'un script neuf**) = Claude montre + attend le « go » d'Albert.
- Le **power-cycle physique reste Albert** (reboot logiciel fige le PMU/SPMI — non automatisable). Filet : backup `alarm_p5.img` + DFU.
- Conséquence : les RE-RUNS de scripts prouvés = autonomes ; un script NEUF (ex. sbio7, le push patch) = toujours « go » d'Albert.

## 2026-11-22 03:18 — Albert (lance) + Claude (Opus 4.8) — patch capteur REÇU+RÉASSEMBLÉ nativement (poignée fe/fd, 22158o) ; reste le PUSH (DMA) au capteur
- Trace : traces/20261122-033138_native_sbio6 (patch_spi_push.bin = prélude+bloc construit, NON émis).
- Fait : `./pending/sep_native_sbio6.sh` (Albert lance, store neuf). KX + compteur relayés (connus). PHASE 6 RECON : envoi 0x5f → fragment TAG=0xfc (op=0x5f kind=1 total=0x568e offset=0 fraglen=0x3fe4=16356, tête `8c563a…`) → réclame suite (TAG=0xfe) → fragment TAG=0xfd (offset=0x3fe4 fraglen=0x16aa=5802) → **patch 22158o (0x568e) réassemblé, préfixe 2o == total-2**. Trame de push construite (prélude `80600007` + bloc) NON émise, dumpée. STOP avant push. Teardown OK.
- Vu (faits bruts) : le SEP livre le patch SEP→AP via la poignée GenericTransfer `fe/fd` **exactement comme macOS** (2 fragments, mêmes tailles). Réception + réassemblage natif validés sur matériel.
- Interprété : **la livraison du patch marche nativement.** Reste UN seul mur SPI : **pousser les 22Ko au capteur** (prélude 0x60 + bloc en 1 transfert ; macOS = DMA SIO ; FIFO scruté = non testé, CS-maintenu incertain) = sbio7. Puis params (0x55, faciles), n° série module, calibration (mailbox, pas SPI), puis enroll + match (doigts).
- Incidents : RAS. Compteur +12 (xart_store_sbio6_1). Capteur restauré. Linux intact ; DFU prêt.

## 2026-11-22 03:05 — Albert (lance) + Claude (Opus 4.8) — 🎯 COMPTEUR DE SÉQUENCE RELAYÉ : 2e maillon lockstep (0x42/0x18, frame 0x73) ; mur suivant = patch 0x5f (DMA)
- Trace : traces/20261122-031411_native_sbio5 (store neuf xart_store_sbio5_1 ; cnt_0x42_B.bin, spi_0x73_resp_raw.bin).
- Fait : `./pending/sep_native_sbio5.sh` (Albert lance). Phase 1-4 OK (key exchange relayé de nouveau). Phase 5 : 0x42 → le SEP rend blob 64o `3a0000000000003e9f8ad3…` → relais SPI trame 0x73 (71o, en-tête `80730047000000`) → état 0x10 = 0x4b (75) → réponse 75o → 64o @ offset 9 → 0x18 → **le SEP ACQUITTE (`< EP=0x08 TYPE=0x18`)**.
- Vu (faits bruts) : 2e relais lockstep réussi. La fonction générique `spi_relay`/`build_spi_frame` marche pour 0x72 ET 0x73 (non-régression du 0x72 prouvée au SELFTEST + au run). Le blob compteur commence par `3a…` (enveloppe 0x3a + compteur, cf. sbio_session : le patch aussi).
- Interprété : **le pattern de relais lockstep généralise** — 2 commandes capteur relayées nativement, toute « petite trame » se relaie pareil. Reste avant la fin de l'init capteur : le **PATCH (0x5f, ~22Ko, 1 burst DMA SIO)** = le seul vrai mur SPI restant ; puis params (0x55, faciles), n° série module, calibration (mailbox, PAS SPI). Puis enroll + match (doigts, session humaine).
- Incidents : RAS. Compteur anti-rejeu +12 (xart_store_sbio5_1). Capteur restauré. Linux intact ; DFU prêt.

## 2026-11-22 02:50 — Albert (lance) + Claude (Opus 4.8) — 🎯 KEY EXCHANGE RELAYÉ nativement : 1er dialogue chiffré SEP↔capteur en lockstep (frame 0x72 corrigée + store neuf)
- Trace : traces/20261122-0247*_native_sbio4 (store NEUF xart_store_sbio4b ; kx_0x15_B.bin, spi_0x72_resp_raw.bin, kx_0x16_B.bin). Script : pending/sep_native_sbio4.sh (frame 0x72 = 0x2f corrigée).
- Fait : `M1N1TIMEOUT=20 XART_STORE=…xart_store_sbio4b ./pending/sep_native_sbio4.sh` (Albert lance). Phase 1-3 OK (stab, sbio vivant, 0x17 franchi). Phase 4 : 0x15 → le SEP rend blob 40o `ea88c46a…3092300a` → relais SPI trame 0x72 (47o, en-tête `8072002f000000`) → état 0x10 = **0x33 (51)** → réponse 51o `80d4003300000000 72 <40o> <crc>` → 40o extraits @ offset 9 → 0x16 → **le SEP ACQUITTE (`< EP=0x08 TYPE=0x16`)**.
- Vu (faits bruts) : état 0x10 = 0x33 (= les 51o attendus ; avant le fix : 0x0b = erreur status=2). Réponse capteur 51o, charge-clé 40o à offset 9. Le SEP a acquitté 0x16. 2 causes du run raté précédent réglées : (a) frame 0x72 longueur totale 0x2f (était 0x28) ; (b) store POLLUÉ (réutilisait xart_store_sbio4 du run précédent → servait un vieux master → sbio n'ouvrait plus) → store NEUF.
- Interprété : **le relais lockstep du key exchange fonctionne nativement** — l'AP comme pur relais d'octets est validé de bout en bout sur matériel (`sbio_keyexchange.md` confirmé en vrai). Les commandes capteur suivantes (0x42/0x18 compteur via trame 0x73, params via 0x55) suivent le MÊME pattern → sbio5 relaiera toute la session capteur. Reste : patch/calibration (blobs, rejouables), puis enroll + match (doigts, session humaine).
- Incidents : RAS (hormis un flake USB transitoire au catch — port apparu/disparu, réglé au power-cycle suivant). Compteur anti-rejeu +12 (xart_store_sbio4b). Capteur restauré. Linux intact ; DFU prêt.

## 2026-11-22 02:36 — Albert (lance) + Claude (Opus 4.8) — sbio4 : key exchange relayé à MOITIÉ (le SEP rend bien le blob 40o ; la réponse SPI capteur = 11o, pas 40 → enveloppe SPI du 0x72 à reverser)
- Trace : traces/20261122-023626_native_sbio4 (spi_0x72_resp_raw.bin, kx_0x15_B.bin).
- Fait : `M1N1TIMEOUT=20 ./pending/sep_native_sbio4.sh` (Albert lance). Phase 1-3 OK (stab **n=7**, sbio vivant **n=6**, 0x17 franchi). Phase 4 : 0x15 envoyé → le SEP rend un blob de 40o (0x28) `7ad7436c0366aa4e59891dbb3a16f6b4feeb23bb0456de33f062ea4fd7da28a7958cbf8492e296ff` (offset +0x1c, taille confirmée par capture). Relais SPI trame 0x72 (47o) → poll état 0x10 : pending = **0x0b (11o)** → réponse brute **11o = `80d4000b00000000 0272 ed57`** (≠ 40o attendus) → STOP fail-closed (on ne devine pas). Teardown capteur (power_off+restore) OK.
- Vu (faits bruts) : la moitié SEP du key exchange fonctionne (blob 40o produit). La réponse du capteur au 0x72 = 11o `80d4000b00000000 0272 ed57` (forme `80 d4 00 <len> 00000000 <payload>`, payload = `02 72` + CRC `ed57` ; ressemble à un ACK/status court, PAS la réponse-clé de 40o).
- Interprété : le mur = l'**ENVELOPPE SPI du 0x72** (comment obtenir la réponse de 40o du capteur), point explicitement non reversé (`sbio_keyexchange.md §8`). Hypothèses à tester : réponse-clé via un **2e read** après l'ACK court ; délai de calcul capteur (re-poll) ; ou frame 0x72 à ajuster. À reverser depuis les captures du bus capteur + kext `SessionKeyExchange`/`transferData`.
- Incidents : RAS. Compteur +12 (xart_store_sbio4). Capteur restauré. Linux intact ; DFU prêt.

## 2026-11-22 02:13 — Albert (lance) + Claude (Opus 4.8) — 🎯 0x17 FRANCHI nativement : l'AP lit le serial capteur EN DIRECT et le SEP l'accepte ; mur suivant = 0x15 key exchange
- Trace : traces/20261122-021249_native_sbio3. Script : pending/sep_native_sbio3.sh (relu, SELFTEST vert) ; moteur SPI : analysis/mesa_spi_proxy.py.
- Fait : `M1N1TIMEOUT=20 ./pending/sep_native_sbio3.sh` (Albert lance, après reboot + catcher permanent). PHASE 1 persist (**stab n=6**) + PHASE 2 0x73 (**sbio vivant n=5**) + PHASE 3 : dans la MÊME session proxy, `MesaSPI(iface,p,u)` → `power_on()` → `read_id()` → identité capteur `80d4001b00000000 70 0219c05c0fd2aa349a81c76e030200d8 7576` ; série [9:25] = `0219c05c0fd2aa349a81c76e030200d8` (== gabarit c12) ; construit la commande 0x17 (gabarit + série lue live) → envoie EP 0x08 TAG=0xfc TYPE=0x17.
- Vu (faits bruts) : le SEP **acquitte** : `< EP=0x08 TAG=0xfc TYPE=0x17`, B8 `+0x14=0x17`. Puis déroulé post-0x17 → **mur suivant = commande 0x15 performKeyExchange** [SPI] (réf c12 000305_08_A.bin : gt_packet `+0x14=0x15`, `+0x18=0x04`, charge = `01000000` = sessionType=1). Teardown capteur : `power_off` + `restore` (état iBoot) OK.
- Interprété : **le relais SEP↔capteur fonctionne pour 0x17** (donner le serial lu live) — 1ère étape de relais capteur franchie nativement, sans macOS. Prochain mur = **0x15 = échange de clés chiffré** : le vrai crux (l'AP est-il un **pur relais d'octets** — faisable — OU doit-il **détenir/générer une clé** — mur dur ?). Analyse en cours → `docs/sbio_keyexchange.md`.
- Incidents : RAS. Compteur anti-rejeu +12 (xart_store_sbio3). Capteur restauré état iBoot. Linux intact ; DFU prêt.

## 2026-11-22 01:58 — Albert (lance) + Claude (Opus 4.8) — sbio au-delà du 0x73 : le 1er mur = 0x17 prepareSession, et il PORTE le serial du capteur (qu'on sait lire)
- Trace : traces/20261122-015806_native_sbio2 (wall_A8/B8.bin, wall_ref_17_A.bin). Sanity capteur : traces/20261122-015340_sensor_sanity (identité capteur = macOS, état restauré). Script : pending/sep_native_sbio2.sh (relu).
- Fait : `M1N1TIMEOUT=20 ./pending/sep_native_sbio2.sh` (Albert lance). PHASE 1 persist (stabilisation **n=5**) + PHASE 2 0x73 (**sbio vivant n=4**) + PHASE 3 déroulé post-0x73 (fail-closed, store séparé xart_store_sbio2).
- Vu (faits bruts) : AUCUN message EP 0x08 spontané après le 0x73 — le SEP **attend que l'AP pilote la commande suivante** (comme macOS). Mur = étape 0 = commande **0x17 prepareSession** classe [SPI]. Réf capture c12 (000303_08_A.bin) : gt_packet `+0x14=0x17`, `+0x18=0x10` (len), charge `+0x1c = 0219c05c0fd2aa349a81c76e030200d8`. Cette charge **== les 16 octets de série lus du capteur par SPI** (sanity : identité `80d4001b00000000 70 0219c05c0fd2aa349a81c76e030200d8 7576`).
- Interprété : **0x17 prepareSession = l'AP DONNE au SEP le n° de série du capteur** (qu'il a lu par SPI). Comme on sait lire ces 16 octets (mesa_hello / `analysis/mesa_spi_proxy.py`, identité identique sur CE Mac), on peut **franchir 0x17 nativement** → script `sep_native_sbio3.sh` (en construction) le fait (lire identité live → la servir dans 0x17 → envoyer). Mur SUIVANT attendu = **0x15 performKeyExchange** = le vrai lockstep chiffré SEP↔capteur (prochain défi).
- Incidents : RAS. Compteur anti-rejeu +12 (xart_store_sbio2). Catcher : fix baseline (un port disparu sort de la baseline → réapparition saisie) + run en arrière-plan OK. Linux intact ; DFU prêt.

## 2026-11-22 01:05 — Albert (lance) + Claude (Opus 4.8) — 🎯 sbio VIVANT : répond au 0x73 exactement comme macOS, via le stream 0 (la route native tient jusqu'au capteur)
- Trace : traces/<...>_native_sbio (B8 dumpé dans OUT/sbio_probe_B.bin) ; store SÉPARÉ xart_store_sbio/ (xart_store_linux/ préservé). Script : pending/sep_native_sbio.sh (relu par Claude avant lancement ; SELFTEST vert). Proxy rattrapé par catcher v2 (t+15s).
- Fait : `M1N1TIMEOUT=20 ./pending/sep_native_sbio.sh` (Albert lance). Cold-boot. PHASE 1 = flux PERSIST reproduit à l'identique (12 SAVE : 8 xART + 4 locker ; idle ; sbio+sks annoncés) = **stabilisation reproduite n=2**. PHASE 2 = sonde sbio.
- Vu (faits bruts) : après idle, ouverture sbio OK (4 CNTL acquittés), A8 (IOVA 0x54000) mappé dans le stream **[0] seulement**, envoi `EP=0x08 TAG=0xfc TYPE=0x73`. Le SEP a RÉPONDU : `< EP=0x08 TAG=0x04 TYPE=0x00` puis `< EP=0x08 TAG=0xfc TYPE=0x73` ; **B8 = gt_packet +0x00=1, +0x14=0x73** (= réponse de référence macOS c12, octet pour octet). Faute DART : FLAG=0 avant ET après le 0x73 (aucune faute neuve ; le sid=10/WRITE du baseline = bits rémanents non flaggués).
- Interprété : **sbio est VIVANT sous la route native**, pas seulement annoncé — réponse IDENTIQUE à macOS. Il lit son OOL via le **stream 0 normal** (pas besoin du stream 15) → ça TRANCHE la question « canal vs état » de `voie_sbio.md §5/§6` : le silence de la voie C venait de l'**ÉTAT** (sbio pas armé car xART non scellé légitimement), **PAS** du canal DART. Confirme la thèse de `route_native.md`.
- RÉSERVE (pas encore vérifié) : n=1 pour la SONDE elle-même (reproduire n≥3 pour « vérifié »). « sbio vivant » ≠ « Touch ID marche » : reste la suite d'init sbio (clé capteur SPI…), un vrai **match**, le trousseau **sks (0x12)**, et l'**enrôlement sous Linux** (gabarits macOS non transférables → enrôlement propre, doigt = session humaine).
- Incidents : warning bénin `Permission denied` (catch nœud brut avant droits udev, cf. entrée 00:46). Compteur anti-rejeu avancé de +12 (dans xart_store_sbio). Linux intact ; filet DFU + alarm_p5.img prêts. Rien poussé.

## 2026-11-22 00:46 — Albert (lance) + Claude (Opus 4.8) — 🎯 ROUTE NATIVE CONFIRMÉE : le SEP scelle un état frais pour Linux, SE STABILISE, et arme sbio + sks
- Trace : traces/20261122-004526_native_persist (log complet). Store scellé : xart_store_linux/ (master_2.bin 420o + glsave_0..3.bin 106/56/613/385o). Proxy rattrapé en local par catcher v2 ; check lecture seule traces/20261122-004523_proxy_check.
- Fait :
  1. Catcher v2 réécrit (tools/catch_lib.sh) : surveille le NŒUD BRUT /dev/ttyACM* (pas le lien udev), baseline des ports préexistants (anti-fantôme), vérif produit/fabricant USB (ignore un CDC-ACM non-m1n1 type téléphone). Rattrapé le proxy en LOCAL au 1er coup (t+13s), chainload m1n1 frais OK.
  2. sep_peek lecture seule : SEP vivant (CPU RUN=0 pré-boot ; mailboxes A2I/I2A EMPTY=1 ENABLE=1).
  3. PERSIST (Albert lance, `M1N1TIMEOUT=20 ./pending/sep_native_persist.sh`) : boot SEPOS, xarm annoncé, réponses ABSENT (forme kext) aux FETCH maîtres → le SEP ACQUITTÉ les SAVE (12) → **idle** (budget 48 NON atteint).
- Vu (faits bruts du log) :
  - Séquence : fw-boot ack → os-uuid (UUID Linux servi) → FETCH-maître ×2 → ABSENT → annonces 'sbi','skd','sse','sks','scr' (ack 0x16) → 12 SAVE (8 SAVE-xART + 4 SAVE-locker) tous ACK+stockés → absent(SEP) ×1 → puis plus rien pendant 25 s = **idle**.
  - Tailles des SAVE maîtres croissantes puis stables (127→225→323→420 o, répétées par paire) ; lockers 106/56/613/385 o.
  - Endpoints finaux : cntl, **sbio(0x08)**, scrd(0x0a), sse(0x0c), hdcp(0x0e), xars(0x10), **sks(0x12)**, xarm(0x13), hibe(0x14), pnon(0x15), skdl(0x17), stac(0x18).
- Interprété :
  - **La question décisive de `route_native.md` §6 est tranchée : OUI.** Acquitter les SAVE d'un état FRAIS (jamais du rejeu macOS) → le SEP SE STABILISE (idle, pas la boucle de re-SAVE de la voie C) et laisse **sbio ET sks** armés. C'est l'état scellé légitime natif, obtenu sans macOS. Mur de fond franchi.
  - RÉSERVE (pas encore vérifié) : « annoncé ≠ vivant ». sbio/sks sont ANNONCÉS, pas prouvés fonctionnels. n=1 pour la stabilisation-sur-ack (le recon absent→annonce→SAVE était n≥2, cf. 20261121-164915). À confirmer : sonde sbio (0x73 « vivant ? », sans doigt) et sks ; test inter-boot (resservir le store → le SEP reconnaît-il son état sans re-sceller ?) ; puis enrôlement (doigt = session humaine).
- Incidents : warning bénin `catch_lib.sh:83 /dev/ttyACM0: Permission denied` (ouverture du nœud brut avant que udev pose les droits uucp ; le chainload a pris le relais dans la fenêtre → catch réussi). À durcir : retry d'ouverture ~50 ms. Compteur anti-rejeu avancé de 12 crans (écriture irréversible, prévu). macOS désynchronisé (ne bootait déjà plus) ; Linux intact ; filet DFU + alarm_p5.img prêts. Rien poussé.

## 2026-11-21 (après-midi) — Claude (Opus 4.8) — BLOCAGE : catch proxy KO (m1n1 file sur Arch) ; Linux OK, Mac récupérable ; diagnostic écrit
- Trace : — (Albert au taf ensuite ; je bosse hors-hardware). Lecture m1n1/src/main.c.
- Fait : après le script PERSIST prêt, impossible de rattraper le Mac en proxy (plusieurs power-cycles). Le Mac a bootloopé macOS un moment (« passé sous macOS »), startup options/1TR bouclent, puis il boote **Arch normalement** (Linux INTACT, rien perdu). Tenté catch intégré aux scripts natifs → marchait pas chez Albert → **reverti** (scripts natifs = connexion seule ; catch via `tools/catch_proxy.sh` que Claude lance). Rendu le catcher **agressif** (saisie immédiate de if02, boucle serrée) dans `tools/catch_lib.sh` (+ `catch_proxy.sh` refactoré dessus, faux-échec UartTimeout corrigé).
- Vu (code m1n1) : la fenêtre de catch (5 s, `EARLY_PROXY_TIMEOUT`) ne s'ouvre QUE si `cur_boot_args.video.display==0` **ET** `lp_sip0==127` ; sinon m1n1 saute direct au payload (Arch). → c'est pourquoi le catch rate maintenant (une des 2 conditions a basculé ; cohérent avec « boot policy changée »). Diagnostic complet + test « lire l'écran » + arbre de décision : `docs/catch_proxy_diagnostic.md`.
- Interprété : on n'a jamais touché la boot policy par script (ligne rouge tenue) ; cause probable = coupures d'alim répétées / tentatives macOS ont basculé le disque par défaut et/ou la LocalPolicy. **Non confirmé** — à trancher en lisant le texte m1n1 à l'écran au prochain boot (lignes « Boot policy: sip0 = N », « video: display: 0x… », et si « Waiting for proxy connection... » s'affiche).
- Incidents : aucun dommage matériel. Mac récupérable (DFU en dernier recours, filet prêt). Rien poussé.

## 2026-11-21 — Claude (Opus 4.8) — Script PERSIST prêt (pending/sep_native_persist.sh) — run d'ÉCRITURE, à lancer par Albert
- Trace : — (hors-hardware, SELFTEST OK). Store xART Linux sur CE PC : `xart_store_linux/` (vide au départ).
- Fait : écrit `pending/sep_native_persist.sh` = politique native complète. Acquitte + STOCKE les SAVE (maître par type 1/2, gigalocker brut indexé — clé UUID = TODO), SERT depuis le store au re-FETCH (maître = 0x11 zéros + charge ; gl par UUID), ABSENT sinon (formes kext). Budget SAVE borné (MAX_SAVES=48). En-tête go/no-go en langage clair.
- But : trancher si « sceller du frais + le STOCKER + le re-servir » STABILISE le SEP (idle après SAVE, sbio reste armé) vs boucle de re-SAVE (= même mur que voie-C FOLLOW). Différence clé vs FOLLOW : on stocke et on ressert (FOLLOW acquittait en servant du périmé).
- ⚠️ ÉCRITURE : acquitter un SAVE fait avancer le compteur scellé → DFU derrière (backup prêt ; macOS sacrifié, on s'en fiche). Décision + lancement = Albert. Store sur ce PC ; transfert vers le Linux du Mac par USB = étape future (driver natif noyau).
- Incidents : — (pas encore lancé). Rien poussé.

## 2026-11-21 — Albert (lancé) — ⭐ RECON natif n°2 : la forme d'absent kext MARCHE → SEP annonce sbio + VEUT SCELLER DU FRAIS (SAVE)
- Trace : traces/<dernier _native_0x13> (native_0x13.log). `SKIP_CHAINLOAD=1 ./pending/sep_native_0x13.sh` (ABSENT_FORM=kext, OS_UUID_MODE=fixed), m1n1 frais (catch OK).
- Fait : boot SEPOS + politique native OBSERVE avec la forme d'absent fidèle au kext (TYPE=0x00, maître len 0x11 / gl len 0).
- Vu (vs recon n°1 qui CALAIT au 1er maître) : fw-boot→ack ; os-uuid→UUID Linux ; **FETCH maître TAG=0x03 (sel=1 SEP) → ABSENT** ; **FETCH maître TAG=0x04 (sel=0 USER) → ABSENT** (le SEP demande MAINTENANT les DEUX maîtres) ; puis **annonces sbi/skd/sse/sks/scr** (ackées 0x16) ; puis **SAVE-xART TAG=0x05** = la puce veut re-sceller → **on s'est ARRÊTÉ SANS acquitter** (OBSERVE). Endpoints finaux : cntl, **0x08:sbio**, 0x0a:scrd, 0x0c:sse, 0x0e:hdcp, 0x10:xars, 0x13:xarm, 0x14:hibe, 0x15:pnon, 0x17:skdl, 0x18:stac. **sbio ANNONCÉ.**
- Interprété : l'hypothèse « absent → le SEP scelle du frais » est **SOUTENUE** — refuser proprement les 2 maîtres amène le SEP à annoncer toute la pile biométrique (sbio/skdl/sse/scrd) puis à demander un SAVE pour sceller son propre xART frais. **AUCUNE écriture** (SAVE non acquitté → compteur non avancé → récupérable). ⚠️ HONNÊTETÉ : ce point (annonces + SAVE@TAG05) est **le MÊME** qu'atteignait voie-C FOLLOW ; la différence qui doit compter = le run PERSIST **stockera** le blob frais (cohérent au re-fetch), là où FOLLOW ne faisait qu'acquitter en servant du périmé → re-SAVE sans fin. « sbio annoncé » ≠ « sbio fonctionnel » (question annoncé/vivant encore ouverte).
- Incidents : aucun. Prochain = run PERSIST (acquitter + STOCKER le SAVE) = ÉCRITURE SEP = porte Albert (backup+DFU prêts). Rien poussé.

## 2026-11-21 — Claude (Opus 4.8) — KEXT (2 vérifs avant recon n°2) : OS-UUID « absent » = TYPE=0x02 ; préfixe maître 0x11 = zéros (confirmé)
- Trace : — (décompil, même fonction + dispatch). Opcode du message = **octet TYPE** (byte 2) ; table de saut à 0x9986db8 pour op 0..0x0e, op 0x13 traité à part.
- Vu : (1) op 0x13 (os-uuid) : `_determineOsUuidGated` lit `apfs-preboot-uuid` ; si flag `[this+0xd9]==0` (pas d'UUID) → réponse **TYPE=0x02**, rien en A ; sinon 16 o en A + TYPE=0x00. (2) préfixe maître : `strb wzr,[x21],#0x11` + `memset(A+1,0x10,0)` → **A[0..0x11]=0x11 zéros** (mon script était déjà correct).
- Interprété : pour Linux (pas d'apfs-preboot-uuid) le « pas d'UUID d'OS » fidèle = TYPE=0x02. Ajouté `OS_UUID_MODE` au script (défaut `fixed` = UUID Linux comme au recon n°1, pour ne changer QU'UNE variable — la forme d'absent — au recon n°2 ; `none` = TYPE=0x02 dispo pour un recon n°3). SELFTEST OK (2 modes). Doc : gigalocker.md.
- Incidents : aucun. Script prêt pour recon n°2 (ABSENT_FORM=kext). Rien poussé.

## 2026-11-21 — Claude (Opus 4.8) — KEXT : forme exacte de la réponse « introuvable » trouvée (explique le cale du recon n°1)
- Trace : — (décompil hors-ligne ; `AppleSEPXART::_handle_sep_driven_msg` @0xfffffe0009986588, kernel.macho / com.apple.driver.AppleSEPManager ; capstone venv scratchpad). Autorisé par Albert (droit suisse, usage perso).
- Fait : désassemblé le handler 0x13 côté AP pour trouver comment macOS répond quand un enregistrement est ABSENT (notre recon n°1 avait deviné 0x07 → SEP calé).
- Vu (source: kext) : réponse écrite dans la struct message (8 o = mot mailbox) : octet2=TYPE(code retour, 0=ok), octets3-4=longueur → **PARAM=len&0xff, DATA0=len>>8** (confirme notre codec depuis le binaire), octet5=sélecteur ré-émis. « Introuvable » **n'est pas une erreur** : FETCH normal TYPE=0x00 avec **maître → longueur 0x11 (préfixe seul, A=0x11 zéros)** ; **gigalocker → longueur 0, A vide**. CRC-16 CCITT (poly 0x1021) sur la charge pour le log, pas dans le message. Aussi : `_determineOsUuidGated` lit `apfs-preboot-uuid` de `/chosen` avec un chemin explicite « OS UUID determined not to exist » (macOS tourne SANS UUID d'OS).
- Interprété : **ça débloque le recon** — on utilisait une forme invalide (0x07). Corrigé `pending/sep_native_0x13.sh` : ABSENT_FORM=kext (défaut) = maître len 0x11 / gl len 0, TYPE=0x00. Détail dans `gigalocker.md` §Réponse… SELFTEST OK.
- ⚠️ NON résolu (reste du pari) : que le SEP, recevant un maître VIDE, **génère du frais + SAVE** (le kext dit ce que macOS ENVOIE, pas ce que le SEP fait ensuite sur un store vide) ; l'UUID d'OS à donner sous Linux (fake vs « aucun » — à retracer dans setup_OS_UUID) ; contenu exact du préfixe 0x11.
- Incidents : aucun. m1n1 non touché. Rien poussé.

## 2026-11-21 — Albert (lancé) — RECON natif n°1 : ABSENT (forme 0x07) sur le 1er FETCH maître → le SEP CALE (pas de SAVE, pas de sbio)
- Trace : traces/<dernier _native_0x13> (native_0x13.log). Lancé `SKIP_CHAINLOAD=1 ./pending/sep_native_0x13.sh` sur m1n1 frais (catch_proxy OK, « Running proxy »).
- Fait : boot SEPOS + politique native OBSERVE (absent sur FETCH, stop sans acquitter sur SAVE).
- Vu : BOOT OK ; endpoints annoncés = cntl, hdcp(0x0e), xars(0x10), xarm(0x13), hibe(0x14), pnon(0x15), stac(0x18) — **ni sks(0x12) ni sbio(0x08)**. Séquence : fw-boot(TAG 0x02)→ack ; os-uuid(TAG 0x01)→UUID Linux servi ; **FETCH-maître TAG=0x03 DATA=0x100 (sél=1 = SEP-xART) → on répond ABSENT (0x07) → SILENCE** (idle 20 s, aucune autre requête). bilan : FETCH-maître×1, fw-boot×1, os-uuid×1.
- Interprété : la forme d'« absent » 0x07 (AP→SEP) n'a **pas** déclenché de scellage frais ; le SEP **cale** sur le 1er maître refusé. Hypothèses : (a) 0x07 n'est pas la bonne forme « introuvable » dans ce sens ; (b) le SEP lit le **tampon A** et un A vide le bloque. NON tranché. **AUCUNE écriture** (le SEP n'a jamais demandé de SAVE → compteur non avancé → rien à récupérer ; garde-fou OK).
- Décision (Albert) : **prioriser la route kext/hors-hardware** — trouver dans `AppleSEPManager` (handler 0x13) la forme exacte « locker introuvable » que le SEP attend, AVANT de re-tenter sur matériel (chaque essai = 1 power-cycle). Décompilation large autorisée (droit suisse, usage personnel).
- Incidents : aucun. Rien committé/poussé.

## 2026-11-21 — Claude (Opus 4.8) — Script de RECON natif préparé (pending/sep_native_0x13.sh), OBSERVE pur, à lancer par Albert
- Trace : — (prépa hors-hardware ; SELFTEST validé, Mac non branché). Décision technique déléguée par Albert (« je suis l'architecte »).
- Fait : écrit `pending/sep_native_0x13.sh` — 1er pas de la route native, en 1 temps RECON (OBSERVE pur, aucune écriture au-delà du boot routine). Boot SEPOS (scaffold éprouvé) → répond **ABSENT** aux FETCH maître/locker (hypothèse : forme = op 0x07, que le SEP utilise lui-même ; variante `empty`) → ack VU pour fw-boot/os-uuid/annonce → **STOP sans acquitter sur SAVE** (donc compteur NON avancé). But : voir si « prétendre n'avoir aucun xART » pousse la puce à vouloir sceller du frais (émettre un SAVE) et annoncer sbio.
- Vu : en-tête en **langage clair** pour la décision go/no-go d'Albert (ce que ça fait, risque, récupérable). SELFTEST OK (2 formes d'absent). Fail-closed sur op inconnue et sur SAVE.
- Interprété : inconnue assumée — la **forme AP->SEP d'un « absent »** n'a aucune capture (macOS avait toujours ses lockers) ; ce recon sert aussi à la découvrir. Risque = classe OBSERVE (pas de SAVE-ack → pas d'avancement de compteur → récupérable comme nos runs passés). L'UUID d'OS Linux renvoyé (op 0x13) = un choix (`4c494e5558…` = "LINUX"+0), à ajuster.
- Incidents : aucun. Le run d'ÉCRITURE (PERSIST = acquitter+persister le SAVE = la vraie porte) n'est **pas** écrit : je l'écrirai APRÈS avoir vu la réaction du recon. Rien committé, rien poussé.

## 2026-11-21 — Claude (Opus 4.8) — Recadrage : booter SEPOS n'est PAS une porte à ouvrir (déjà fait en routine) ; la vraie porte = politique 0x13 native (SAVE-ack)
- Trace : — (lecture de `pending/sep_xart_replay.sh` l.17-20/520 + `m1n1/proxyclient/m1n1/hw/sep.py`). Lecture seule, rien poussé.
- Fait : prépa hors-hardware de la route native. En lisant notre propre harnais, constaté que **le boot SEPOS est déjà effectué à chaque run** (`sep.boot()` = GET_STATUS/BOOT_TZ0/**BOOT_IMG4**/SET_SHMEM), « déjà lancé sans incident » (= ouverture de tous les essais voie C). L'IMG4 = firmware SEP **propre à la machine** (ADT `/chosen/memory-map` SEPFW, préchargé iBoot), pas un leak.
- Vu : `route_native.md` §3.1/§6 et `handler_0x13.md` §4 présentaient à tort « booter SEPOS » comme la 1re porte non franchie. CORRIGÉ : le boot est franchi en routine via proxyclient ; le « SEP | WIP » d'Asahi concerne leur **driver noyau** (`sep.rs`, désactivé), pas notre chemin.
- Interprété : la **vraie** porte de la route native = la **politique 0x13 native** (répondre *absent* aux FETCH pour laisser la puce sceller du frais, puis **acquitter + persister le SAVE**). Le **SAVE-ack** est l'écriture qui fait avancer le compteur scellé = porte Albert (backup+DFU en filet). Le harnais `sep_xart_replay.sh` (boot + bootstrap CNTL + tampons A/B) est le **scaffold réutilisable** ; le handler natif en est un mode frère — l'**opposé** du replay (mort) : il ne resert pas le coffre macOS, il laisse sceller du frais.
- Incidents : aucun. m1n1 lu, non modifié, non poussé (ban IA = contribution, pas lecture — accord Albert 2026-11-21). Prochain pas = écrire le `pending/` du run natif (en-tête but/risque/résultat, fail-closed, budget SAVE borné) — après relecture de la politique par Albert.

## 2026-11-20 (matin) — Claude (Opus 4.8) — CRC des slots .gl IDENTIFIÉ et vérifié (12/12) : CRC-32/ISO-HDLC de la charge
- Trace : traces/20261117-224724_xart_read/*.gl.bin (coffre réel, 12 lockers). Analyse hors-ligne (chercheur de CRC générique, catalogue CRC-16/32 × régions).
- Fait : confronté le CRC stocké (+0x16, u32 LE) de chaque locker à un catalogue d'algos sur plusieurs régions.
- Vu : **CRC-32/ISO-HDLC (`zlib.crc32`) de la CHARGE seule `[0x22:0x22+longueur]` reproduit les 12/12 CRC stockés**, exactement. Aucun autre algo/région ne matche. → passe `gigalocker.md` « algo non vérifié » à **VÉRIFIÉ**. Ajouté `xart.slot_crc()` + `Locker.crc_ok` + `serialize_locker()` (round-trip d'un slot À L'OCTET PRÈS, testé) + `build_header()` (nouveau locker). step6 = 10 tests verts (dont CRC 12/12 et round-trip).
- Vu aussi : un **u16 à +0x1a** (puis 6 o nuls) varie par locker ; **PAS** un CRC-16 courant de la charge ni une longueur (toutes variantes du catalogue écartées). Champ **inconnu**, documenté ; mis à 0 par `build_header` avec un ⚠️ (à confirmer sur matériel avant un vrai SAVE natif).
- Interprété : le format `.gl` est maintenant **entièrement sérialisable en VU** sauf ce u16. Débloque proprement le « store xART écrivable » du handler natif (handler_0x13.md §4bis) — le seul reste hypothétique est le u16 + la POLITIQUE (quand écrire), qui restent porte Albert.
- Incidents : aucun. Rien committé. (chercheur de CRC = scratchpad, exploratoire ; l'algo retenu est dans xart.py avec test.)

## 2026-11-20 (matin) — Claude (Opus 4.8) — Étape 7 : modèle de la réponse AP à l'EP 0x13 (xART), VU, validé en reproduisant snew-reel
- Trace : traces/20261111-113919_snew-reel (EP 0x13, 30 échanges). Hors-hardware, rien émis vers le SEP.
- Fait : écrit `driver/sepreplay/xart_responder.py` (modèle du côté AP du protocole 0x13) + `driver/tests/test_step7_xart_responder.py` (8 tests, verts). Fait suite au codec VU de l'étape 6 (`xart.py`).
- Vu (reproduit ligne à ligne sur snew-reel) : macOS répond à CHAQUE requête 0x13 du SEP de façon régulière —
  - fw-boot (TYPE 0x0e) → ack `TYPE=0x00 DATA=0x100` ;
  - OS-UUID (0x13) → `TYPE=0x00 DATA=0` + 16 o d'UUID écrits en tampon A ;
  - FETCH maître/gigalocker (0x00/0x05) → `TYPE=0x00`, longueur `PARAM|DATA0<<8` + **sélecteur ré-émis** (DATA[1]) — reproduit exactement par notre codec à partir de la longueur encodée ;
  - locker-absent émis par le SEP (0x07, TAG 0x0b) → simple ack `DATA=0` ;
  - **SAVE (0x01 maître / 0x06 locker, TAG 0x13/0x14/0x15) → macOS ACQUITTE** : `TYPE=0x00 DATA = req.data & 0xFFFFFF00` ;
  - annonce d'endpoint (0x1d) → ack `TYPE=0x16 DATA = req.data & 0xFFFFFF00`.
- Interprété : le côté AP du 0x13 est entièrement déterministe et VU ; notre modèle le reproduit → base solide du futur handler natif. ⚠️ La POLITIQUE native (répondre « absent » quand le store Linux est vide ; **persister** le blob d'un SAVE) DIVERGE de macOS sur 2 points seulement, isolés dans `native_fetch_decision()`/`native_on_save()`, marqués HYPOTHÈSE — **aucune vérité terrain**, validables seulement sur matériel (porte Albert, cf. handler_0x13.md §2/§3, route_native.md).
- Incidents : aucun. Suite : step1-4+6+7 verts ; step5_daemon échoue encore (compteur de captures codé en dur 18 ≠ 23 réelles — pré-existant, indépendant de ce travail). Rien committé.

## 2026-11-18 (midi) — Claude (Opus 4.8) — ⭐ HANDOFF / ÉTAT DES LIEUX : voie C (rejeu xART) fermée avec confiance élevée ; R3 (décisif) préparé mais optionnel
- Trace : — (synthèse ; détails dans les entrées ci-dessous et les 4 rapports d'agents).
- **CONCLUSION (confiance élevée, non prouvée à 100 %)** : **rejouer le coffre xART pour obtenir Touch ID sous Linux ne marche pas**, pour des raisons MATÉRIELLES, pas par manque d'essais. Faisceau convergent :
  - **R2 (input pourri)** : servir des maîtres ZÉROS donne le MÊME comportement que le vrai coffre (SAVE@TAG05, gl:0). → **la puce n'évalue pas ce qu'on sert**, elle re-scelle sur son propre état interne. C'est le résultat le plus décisif.
  - **R1 (sbio stream 15)** : le silence de la sonde 0x73 n'est PAS un problème de canal DART (stream 15 programmé, A8 mappé sid 0 ET 15, toujours muet). → sbio n'est pas « armé » tant que le xART n'est pas scellé.
  - **Guide Apple** (documentaliste) : la fraîcheur/entropie vit dans une **puce matérielle séparée** (Secure Storage Component, bus I2C dédié SEP-only), PAS sur le disque → rejouer un coffre disque ne peut pas la restituer.
  - **Nonce** (analyste) : nonce xART généré par la ROM du SEP, **aucun levier côté AP** pour le fixer/semer.
  - **Désassemblage** (analyste) : notre emballage maître (préfixe 0x11) est **prouvé conforme** → le re-scellement n'est pas un bug à nous.
- **IL RESTE 1 test risqué, OPTIONNEL — R3 (ACK_SAVE)** : `pending/serve_gl_decisif_go.sh`. Acquitte le SAVE → fait AVANCER le compteur anti-rejeu matériel → certitude A/B à 100 %, mais ⚠️ Touch ID à récupérer par DFU ensuite. Pronostic : confirmera la fermeture (enchaîne des SAVE). **Décision d'Albert, backup frais d'abord.**
- **Pattern macOS** : dès qu'on pilote le SEP par m1n1, **macOS refuse de booter ensuite** (notre sécurité baissée + étage de boot m1n1 = incompatible avec un boot macOS normal) ; **Linux boote toujours**. Récupération = **DFU Restore** (remet tout d'usine, puce intacte). Ce n'est PAS un brick profond : R1/R2 n'ont rien gravé ni avancé aucun compteur.
- **FILET DE RÉCUP (vérifié)** : `~/mac-dfu/alarm_p5.img` (242 Go, image LUKS de la partition Linux p5, **sha256 OK**) + `~/mac-dfu/UniversalMac_27.2.1_26B131_Restore.ipsw` (DFU). Chaîne éprouvée le 2026-11-17. macOS sacrifiable. Albert refait une backup fraîche avant R3.
- **PLAN** : backup fraîche (Albert, aprem) → ce soir, posé : cold-boot → proxy (`tools/catch_proxy.sh`) → **R3** → DFU → re-restore alarm_p5.img → ré-enrôler Touch ID. macOS n'est plus requis pour le projet.
- **Lanceurs prêts dans pending/** (Albert lance, jamais l'agent) : `probe_sbio_stream15_go.sh` (R1, sûr), `serve_gl_garbage_go.sh` (R2, sûr), `serve_gl_decisif_go.sh` (R3, risqué). Flags du core : `SBIO_STREAM15`, `GL_GARBAGE`, `ACK_SAVE` dans `sep_xart_replay.sh` (défauts OFF).
- **Outillage** : `tools/catch_proxy.sh` reçoit `M1N1TIMEOUT=20` (le `UartTimeout` au chainload était un faux échec — le proxy monte quand même). Rien n'est committé.
- Incidents : aucun dommage. macOS non-bootable (attendu, → DFU ce soir).

## 2026-11-18 (midi) — Albert (lancé) — R2 : input POURRI (maîtres zéros) → comportement IDENTIQUE → la puce ignore le contenu servi (B′ confirmé)
- Trace : traces/<dernier _xart_replay de R2> (follow_B dumpé). Lancé : `./pending/serve_gl_garbage_go.sh` (GL_GARBAGE=1), puce fraîche (cold-boot).
- Fait : servi des maîtres de MÊME longueur mais remplis de ZÉROS, reste du flux inchangé.
- Vu : `FETCH maître sel=1/0 [GARBAGE: contenu nul]` → annonces sbio/skdl/sse/sks/scrd (acquittées 0x16) → **SAVE op 0x01 à TAG=0x05, gl:0** (re-scellé head=ca700f8d…). **IDENTIQUE** aux runs à vrai coffre (082622/085250) et à coffre croisé.
- Interprété : **la puce n'évalue pas le contenu des maîtres** (vrai coffre, inversé, ou zéros → même SAVE@TAG05). Elle re-scelle sur son état interne (fraîcheur matérielle), pas sur notre input. **Confirme (B′)** ; voie C fermée côté « rejeu d'un coffre disque ». n cumulé = 4 runs / 3 inputs différents, même résultat.
- Incidents : catch_proxy a reporté un exit 1 cosmétique (proxy monté quand même). Aucune écriture SEP persistée (fail-closed sur SAVE).

## 2026-11-18 (midi) — Albert (lancé) — R1 : sonde sbio avec stream 15 DART → toujours muet → cause « canal DART » ÉCARTÉE, c'est l'état (sbio non armé)
- Trace : traces/<_xart_replay de R1>. Lancé : `./pending/probe_sbio_stream15_go.sh` (SBIO_STREAM15=1), puce fraîche.
- Fait : servi le vrai coffre (pour arriver au point d'annonce sbio), programmé AUSSI le stream 15 du dart-sep, mappé A8/B8 en sid 0 ET 15 (écriture DART côté AP seulement, aucune écriture SEP), ré-envoyé le 0x73.
- Vu : diagnostic `A8 (IOVA 0x54000) mappé dans les streams : [0, 15]` (stream 0 préservé) → 0x73 envoyé → **B8 nul, aucun message EP 0x08**. (xART re-scelle au même point, head 6b0a27b8…)
- Interprété : le silence du 0x73 **n'est PAS un problème de canal DART** (cause i de `docs/voie_sbio.md` écartée). sbio est muet car **non armé tant que le xART n'est pas scellé** (cause ii/iii). → piloter sbio directement sans franchir le SAVE est fermé. Détail : `docs/voie_sbio.md`.
- Incidents : catch_proxy exit 1 cosmétique (proxy OK). Aucune écriture SEP, aucun compteur avancé.

## 2026-11-18 (après-midi) — Claude (Opus 4.8, documentaliste) — Guide « Apple Platform Security » autorisé : le modèle de conception appuie B′ (fraîcheur hors-disque, matérielle)
- Trace : — (recherche doc publique, pas de hardware)
- Fait : Albert a autorisé le guide public « Apple Platform Security » (support.apple.com) pour départager (a) compteur de version vs (b) nonce par boot. Lu la page « Secure Enclave » (`.../secure-enclave-sec59b0b31ff/web`). Citations + analyse dans `docs/public_linux_state.md` §H–L et `docs/sources.md`.
- Vu (verbatim guide) : le SEP est apparié à un **Secure Storage Component** matériel (entropie), via **I2C dédié** + **protocole chiffré/authentifié à accès exclusif** ; **toutes les clés data-user sont enracinées dans l'entropie de ce NV** ; services anti-rejeu NV = révocation aux « anti-replay boundaries » (code, biométrie, Apple Pay, EACS) — **le boot n'en fait pas partie** ; clé de protection **mémoire (RAM)** régénérée **à chaque démarrage**. Le guide **n'utilise pas** « xART / boot nonce / monotonic counter » et **ne dit pas** que l'état NV périme au boot.
- Interprété : le guide **penche contre (b) pur** pour le NV (l'état survit à un boot simple → plutôt (a)-like), **mais tranche un point plus fort** : la fraîcheur/entropie n'est **PAS dans le blob disque**, elle vit dans une **puce que seul le SEP adresse**. → **rejouer le coffre figé du disque est insuffisant par conception, (a) comme (b)**. Cohérent avec notre **hypothèse B′** (re-scellement observé = le SEP ne retrouve pas le contexte d'entropie matériel sous boot m1n1). Le guide **appuie** cette lecture sans la **prouver** (il ne décrit pas le protocole de boot SEP↔Secure Storage Component). Pour le sceptique : pas de contradiction doc↔traces, le guide donne le « pourquoi » plausible du re-scellement.
- Incidents : — : la divergence SAVE@TAG05 PERSISTE → les maîtres croisés n'étaient PAS la cause (recentre vers anti-rejeu)
- Trace : traces/20261118-085250_xart_replay (follow_B/001_tag05_op01.bin). Albert a power-cyclé (proxy ré-armé après plusieurs essais) puis lancé `./pending/serve_gl_go.sh` avec les 2 correctifs (sel-mapping + gigalocker byte1).
- Fait : servi le vrai coffre, maîtres dans le BON sens cette fois.
- Vu : (a) correctif sel-mapping **confirmé appliqué** : `sel=1 → type 0x02 SEP (850 o)`, `sel=0 → type 0x01 USER (1344 o)` (inverse du run 08:26). (b) **MALGRÉ ÇA, comportement IDENTIQUE** : 5 annonces 0x1d acquittées, puis **SAVE op 0x01 à TAG=0x05, gl:0** (aucun gigalocker réclamé). (c) blob re-scellé nz=126 head=1dad4bb6… (≠ run 08:26 nz=127 head=da87a669…). ⚠️ CORRECTION (sceptique) : ces têtes diffèrent **de run en run même à entrée identique** (un SAVE-xART re-chiffre tout à chaque seal ; VU 2026-11-12) → la différence NE prouve PAS que la puce a lu des maîtres différents, et comparer les deux follow_B ne tranche RIEN. (d) sonde sbio 0x73 : toujours aucune réponse. (e) correctif gigalocker byte1 **jamais exercé** (gl:0).
- Interprété : **hypothèse « maîtres croisés = cause du SAVE@TAG05 » RÉFUTÉE** (n=2 : croisés ET corrects donnent le même SAVE@TAG05). ⚠️ CORRECTION (sceptique) : conclusion correcte = « l'**ORDRE** sel↔maître n'est PAS le déclencheur », PAS « le contenu des maîtres est hors de cause » (les 2 runs ne varient que l'affectation sel↔blob, pas le préfixe 0x11 ni la charge ni la fraîcheur). Le vrai pilier de « penche B » n'est pas ce n=2 mais le **désassemblage kext §9** (aucun levier de nonce côté AP ; nonce ROM 20 o par boot, non semable). Ça **recentre vers (B)/(B′)** : la puce re-scelle car l'amorçage m1n1 (`sep_boot.sh`) **n'établit jamais le contexte de session** (pas de generateROMNonce ni pnon 0x15) → son nonce n'a aucun rapport avec celui sous lequel le `.gl` fut scellé → re-scellement quel que soit l'input. (B′ = pas de rejeu pur possible ; distinct de B « compteur disque ».) macOS réussit car il RESTAURE puis RE-SCELLE sous le nonce iBoot, il ne rejoue pas un état figé. Le correctif sel↔type reste **juste** mais n'était pas la cause. Doute d'emballage restant : **préfixe 0x11** (partiellement vérifiable offline : colle déjà à snew-reel seq 000094/000096 ; reste à désassembler op 0x00/0x01).
- Statut voie C : **penche plus nettement vers fragile/fermée**, SANS être prouvée fermée (reste le doute préfixe + le fait que « SAVE ≠ refus » en général). Le test **décisif** = acquitter le SAVE (écriture risquée, compteur) → exige **Albert + backup disque** (inexistant, cf. [[priorites-risque]]). Ne PAS gâcher d'autres runs à deviner l'emballage.
- Incidents : ré-arment du proxy laborieux (catch_proxy a signalé UartTimeout au chainload mais le Mac est quand même revenu en proxy frais → le run a tourné). Aucun dommage, aucune écriture SEP (arrêt avant d'acquitter le SAVE). Mac à redémarrer.

## 2026-11-18 (analyse, hors ligne) — Claude (Opus 4.8) — BUG D'EMBALLAGE TROUVÉ : maîtres SEP/USER servis CROISÉS (mapping sel↔type inversé) → cause probable du SAVE@TAG05
- Trace : — (logs noyau macOS snew-reel + c5-ool-boot ; aucun hardware).
- Fait : cherché, dans les `hv_uart.log` de macOS, les lignes « Fetched %s-xART with CRC ». Elles **tranchent** la correspondance sel↔maître.
- Vu : snew-reel/hv_uart.log L1573 « Fetched **SEP**-xART » → réponse au **TAG 0x03** (requête SEP portant **sel=1**) ; L1575 « Fetched **USER**-xART » → **TAG 0x04** (**sel=0**). Confirmé par c5-ool-boot (L1525 SEP, L1541 USER). Donc **sel=1 → SEP-xART, sel=0 → USER-xART**.
- Bug : `serve_from_gl` faisait l'INVERSE (`sel==1 → USER type 0x01`). **On servait les deux maîtres croisés** : à la requête sel=1 (la puce veut son SEP-xART = sa racine), on envoyait le USER-xART, et vice-versa. Un maître racine erroné → la puce ne peut pas restaurer son état → elle re-scelle (**SAVE op 0x01 à TAG=0x05, gl:0**). Explique naturellement la divergence vue en SERVE_GL ET en FOLLOW.
- Origine de l'erreur : note kext §8 (L260) « sélecteur SEP(0)/USER(1) » — **lecture inversée** du `tst w22,#1`. La L286 du même doc (« TAG 0x03 = SEP-xART ») et les logs macOS avaient raison. Docs corrigées (kext §8 L260, gigalocker.md).
- Correctif 1 (hors ligne, prêt) : 1 ligne dans `serve_from_gl` → `mtype = 0x02 if sel==1 else 0x01`. Syntaxe OK. Sûreté inchangée (on n'acquitte toujours pas un SAVE ; fail-closed). **Hypothèse à tester** : avec les maîtres dans le bon sens, la puce devrait **réclamer ses gigalockers (op 0x05)** au lieu de SAVE@TAG05. Si oui → « emballage faux » confirmé, **voie C vivante**. Si elle re-scelle encore → penche anti-rejeu.
- **2e BUG trouvé en blindant la suite** (op 0x05 gigalocker) : la réponse doit **ré-émettre l'octet1 de DATA de la requête** (drapeau 0x00/0x01), comme la réponse maître ré-émet le sélecteur. VU **17/17** dans snew-reel (req byte1 == resp byte1). Le script mettait byte1=0 → décalage sur les 13 gigalockers à byte1=0x01. **Corrigé** : `DATA=((L>>8)&0xff) | (m.DATA & 0x0000ff00)`. C'était le **mur suivant** (il aurait bloqué juste après le correctif 1). Validé en SELFTEST (aucune erreur). Avec les 2 correctifs, un run propre devrait, si l'emballage était bien la cause, **servir les maîtres + ~14 gigalockers puis s'arrêter sur le 1er VRAI SAVE vers TAG 0x13** (comme macOS) — et non plus SAVE@TAG05.
- À FAIRE : au retour d'Albert, UN run propre (cold-boot → proxy → `./pending/serve_gl_go.sh`). C'est l'expérience qui fait avancer la question A/B sans écriture risquée (on s'arrête toujours avant d'acquitter un SAVE).
- Incidents : aucun.

## 2026-11-18 08:26 — Claude (Opus 4.8) — ESSAI E (correctif 0x1d) APRÈS power-cycle : flux complet → le SEP demande un SAVE à TAG=0x05 (divergence réelle, sûre)
- Trace : traces/20261118-082622_xart_replay (xart_replay.log ; **follow_B/001_tag05_op01.bin** = blob re-scellé dumpé au SAVE ; sbio_probe_B.bin). Albert a power-cyclé le Mac (BOOT OK, heap 0x1001028c000 ≠ runs précédents = puce fraîche) puis lancé `./pending/serve_gl_go.sh`.
- Fait : servi le vrai coffre, avec le **correctif 0x1d actif** (acquitte les annonces d'endpoint au lieu de stopper). Flux allé jusqu'à la 1re divergence, puis sonde sbio 0x73.
- Vu (faits bruts) :
  - Servi sans erreur : fw-boot (0x0e), UUID-OS (0x13) 74980dee…, **maître sel=1 type 0x01 USER (1344 o)**, **maître sel=0 type 0x02 SEP (850 o)**. (Idem 07:53.)
  - **Correctif 0x1d OK** : le SEP a annoncé 5 endpoints par TYPE 0x1d — **'sbio', 'skdl', 'sse ', 'sks ', 'scrd'** — chacun **acquitté par `> 0x16`** ; le service a **continué** (plus de faux-arrêt). NB : le nom **`sks`** (trousseau) EST annoncé ici via 0x1d.
  - **Puis : SAVE (op 0x01) à TAG=0x05.** Le SEP veut re-sceller. Responder : **ARRÊT SANS acquitter** (compteur anti-rejeu non avancé, pas de brick). Blob B re-scellé : nz=127/32768, head=`da87a66904d56e4b…`, dumpé dans follow_B/.
  - **gl:0** : le SEP n'a FETCHé **aucun gigalocker** (op 0x05). Il est passé des 2 maîtres + annonces **directement au SAVE** à TAG=0x05 — là où, sous macOS (snew-reel), TAG=0x05 est le 1er FETCH gigalocker.
  - Écoute 10 s : 11 endpoints annoncés (FD) dont **0x08 sbio** ; **0x12 sks ABSENT de cette liste FD** (bien que son NOM ait été annoncé via 0x1d plus haut). Même set qu'au 07:53.
  - Sonde sbio 0x73 (sans doigt) : **toujours AUCUNE réponse** (B8 nul, aucun msg EP 0x08).
- Interprété (→ hypotheses.md) :
  - Le **SAVE à TAG=0x05 est la VRAIE divergence** (reproductible à viser, n≥3). Il **NE TRANCHE PAS** accept vs refus : (1) emballage faux de notre part (préfixe maître 0x11, octet-près charge, UUID/offset, valeurs fixes) → **non concluant, voie C ouverte** ; OU (2) vrai refus anti-rejeu → voie C fermée. Indécidable sur ce seul run. On a maintenant le **blob re-scellé** (follow_B) et le **point exact** de divergence pour attaquer l'emballage.
  - Léger penchant « maîtres au moins bien formés » : la puce a pris les 2 maîtres, acquitté 5 annonces, et n'a demandé le SAVE **qu'après** (pas de SAVE immédiat après le 1er maître). FAIBLE, à ne pas sur-vendre.
  - `gl:0` + SAVE au lieu de FETCH gigalocker : cohérent avec HV1 (sous m1n1 le SEP passe en phase SAVE plus tôt que macOS). À creuser : pourquoi aucun 0x05 ?
  - sbio/sks « annoncés ≠ fonctionnels » : sbio silencieux au 0x73 (3 causes non tranchées, cf. hypotheses HV3) ; sks nom annoncé mais 0x12 absent de la liste FD.
- Incidents : aucun (run propre, arrêt volontaire sans danger). Mac à redémarrer (le script l'indique).

## 2026-11-18 (analyse, hors ligne) — Claude (Opus 4.8) — Recadrage du SAVE@TAG05 : un SAVE n'est pas un refus ; le vrai coffre reproduit la divergence connue
- Trace : — (analyse de `20261118-082622` + capture `snew-reel`, aucun hardware).
- Fait : comparé le flux de notre run à la capture macOS (EP 0x13, TAG/TYPE) ; décodé le blob re-scellé en B.
- Vu : (a) macOS émet aussi des SAVE (op 0x01/0x06) aux TAG 0x13/0x14/0x15 et **les acquitte** → un SAVE ≠ un refus. (b) macOS FETCH ses 14 gigalockers (TAG 0x05→0x12) AVANT tout SAVE ; nous, SAVE direct à TAG=0x05 sans aucun FETCH gigalocker. (c) blob re-scellé = 127 o puis vide (petite structure racine, pas un maître). (d) la divergence SAVE@TAG05 était DÉJÀ vue en FOLLOW (12/11, vieux blobs) ; elle **se reproduit avec le VRAI coffre**.
- Interprété : deux lectures encore ouvertes — (B) re-scellement par rejet de fraîcheur/contexte même avec le bon coffre (penche B, voie C fragile) ; OU emballage maître faux de notre part (préfixe 0x11 / mapping sel↔type / octet-près) qui corrompt des blobs corrects (→ A, voie C ouverte). **Indécidable offline** : trancher exige d'acquitter le SAVE = écriture risquée (compteur) → Albert + **backup disque** (inexistant). Détail dans hypotheses.md HV1 (MAJ MAJEURE).
- À FAIRE (offline, sans gâcher de run) : **vérifier l'emballage du maître contre `kext_sepmanager.md` §8** — (1) le préfixe de 0x11 octets est-il réel/juste ? (2) le mapping sel↔type (sel=1→USER, sel=0→SEP) est-il prouvé ou supposé ? (indice faible : tailles relatives inversées vs snew-reel, mais puces ≠). Tant que ces doutes tiennent, « emballage faux » reste possible → ne pas conclure « voie C fermée ». Le test décisif (acquitter le SAVE) attend un backup disque.
- Incidents : aucun.

## 2026-11-18 (soir) — Claude (Opus 4.8) — Relance ESSAI E (avec correctif 0x1d) : BOOT SEP BLOQUÉ, pas de power-cycle depuis le run du matin
- Trace : — (aucun dossier créé ; run coupé avant de servir quoi que ce soit).
- Fait : Albert a relancé `./pending/serve_gl_go.sh` (chainload m1n1 OK, python a démarré). Bloqué à « démarrage du SEP par m1n1 (séquence publique)… » **sans jamais atteindre `BOOT OK`** (>2 min). Run tué (TaskStop) ; rien d'écrit vers le SEP (coincé AVANT la phase de service).
- Vu : au run de 07:53 le `BOOT OK` tombait immédiatement ; ici, silence. Le port proxy (`/dev/serial/by-id/...uartproxy...`) et m1n1.bin étaient OK ; le coffre et l'UUID aussi (toutes les gardes pré-boot passent).
- Interprété (hypothèse) : le SEP était **déjà démarré + servi** au run du matin (avancé jusqu'à sbio, puis coupé SANS redémarrer le Mac). Dans cet état « déjà utilisé », le chainload m1n1 (qui ré-initialise l'AP) ne ré-initialise PAS le SEP → la séquence de boot publique attend une réponse qui ne vient pas. **Un chainload m1n1 ne reset pas le SEP ; il faut un démarrage à froid (power-cycle SoC).**
- 2e relance (08:20, sans power-cycle) : **échec différent et pire** — `chainload.py` meurt sur `m1n1.proxy.UartTimeout: Reconnection timed out` (le Mac ne revient pas après le reset de chainload ; `xart_replay.log` vide, rien servi). Confirme que l'état se dégrade à chaque relance sans cold-boot (1re relance = boot SEP figé ; 2e = m1n1 ne reconnecte plus). Erreur dans `chainload.log`, pas à l'écran (tee >/dev/null) → sortie terminal vide, trompeuse.
- À FAIRE avant toute relance (session suivante) : **power-cycle physique du Mac** (Albert) → ré-armer le proxy m1n1 → UN run propre de `./pending/serve_gl_go.sh`. Le correctif 0x1d est en place. Ne pas relancer sans cold-boot (ça échoue au boot/chainload, de pire en pire).
- Incidents : 1) boot SEP figé (pas de BOOT OK), run tué proprement ; 2) chainload UartTimeout. Aucun dommage, AUCUNE écriture SEP (les deux échecs sont AVANT la phase de service).

## 2026-11-18 07:53 — Claude (Opus 4.8) — ESSAI E LANCÉ (Albert) : le SEP prend les 2 maîtres SANS SAVE, annonce sbio, mais le responder s'arrête à tort sur l'annonce (0x1d)
- Trace : traces/20261118-075343_xart_replay (xart_replay.log, sbio_probe_B.bin). Coffre servi = le vrai .gl lu sur disque (UUID d'OS 74980dee…). Albert a lancé `./pending/serve_gl_go.sh`.
- Fait : m1n1 a démarré le SEP (BOOT OK, xarm 0x13 annoncé), mappé A/B, puis le responder a SERVI le coffre réel aux FETCH, puis sonde sbio 0x73 (sans doigt).
- Vu (faits bruts) :
  - Servi, sans erreur côté SEP : fw-boot (0x0e) acquitté ; UUID-OS (0x13) = 74980dee… ; **FETCH maître sel=1 (type 0x01 USER-xART) → 1344 o** ; **FETCH maître sel=0 (type 0x02 SEP-xART) → 850 o**. Tally `{master:2, gl:0, osuuid:1, fw:1}`.
  - **AUCUN SAVE (0x01/0x06) émis** par le SEP après réception des 2 maîtres. Le SEP n'a PAS redemandé de re-scellement.
  - Le message qui a stoppé le service — logué « op inconnue 0x1d TAG=0x00 » — est **l'annonce d'endpoint** `< EP=0x13 TAG=0x00 TYPE=0x1d PARAM=0x6f DATA=0x00736269` = « sbio » (identique à snew-reel L30). Le responder ne gérait pas 0x1d → chute dans « inconnue → STOP ». **Faux-arrêt** (même classe que 0x07 ; cf. mémo protocole-complet-avant-de-repondre).
  - Écoute 10 s après : le SEP a annoncé **11 endpoints** dont **0x08 sbio**, 0x0a scrd, 0x0c sse, 0x17 skdl (+ 0x00 cntl, 0x0e hdcp, 0x10 xars, 0x13 xarm, 0x14 hibe, 0x15 pnon, 0x18 stac). **sks (0x12, trousseau) ABSENT** (comme aux boots hv précédents, cf. 2026-11-?? entrées sbio).
  - Sonde sbio 0x73 (ESSAI D) : 0x73 écrit en A8, commande envoyée → **B8 = 0 octet non nul, aucun message EP 0x08**. Pas de réponse.
- Interprété (→ docs/hypotheses.md) :
  - Positif mais NON conclusif : le SEP a accepté les 2 maîtres (aucun SAVE) et a avancé jusqu'aux endpoints applicatifs dont sbio. Le flux a été **tronqué par un bug à nous** (STOP sur 0x1d), pas par un refus de la puce. « Accepté » reste à CONFIRMER après correctif + reproductibilité (n≥3). Ce n'est PAS une preuve de Touch ID.
  - gl:0 (aucun gigalocker fetché) : ordre différent de snew-reel (où 14 fetchs 0x05 précédaient l'annonce sbio). Ici le SEP a annoncé sbio juste après les 2 maîtres. Ne pas sur-interpréter : le STOP a pu couper avant des 0x05, et les ordres d'annonce varient déjà (hypotheses.md).
  - Silence sbio au 0x73 : 3 causes NON tranchées (stream/sid DART de sbio sous m1n1 inconnu ; ouverture tardive insuffisante ; état restauré n'active pas sbio). **Ne pas conclure « sbio mort ».**
- Correctif (hors ligne, prêt pour relance par Albert) : ajout dans `serve_from_gl` du cas **op 0x1d → acquitter `> TYPE=0x16 DATA=(DATA & 0xFFFFFF00)` et CONTINUER** (format VU dans snew-reel L46-54). La sûreté est inchangée : on N'ACQUITTE TOUJOURS PAS un SAVE (0x01/0x06) → compteur anti-rejeu non avancé → pas de brick. Prochaine étape : Albert relance `./pending/serve_gl_go.sh` ; on verra si le SEP, une fois les annonces acquittées, fetch des gigalockers (0x05) / va plus loin / émet un SAVE.
- Incidents : aucun (pas de gel ; script a coupé proprement, Mac à redémarrer par Albert).

## 2026-11-17 (nuit) — Claude (Opus 4.8) — ESSAI E préparé : RENDRE le vrai coffre (.gl) à la puce (mode SERVE_GL, pending/, Albert lance)
- Trace : — (préparation + SELFTEST hors ligne ; rien lancé vers le Mac). Proxy m1n1 up.
- Contexte : on a enfin un coffre QUI COLLE (le .gl lu sur disque). Albert a dit « Oui, construis l'essai ».
- Fait (hors ligne) :
  - Ajout du mode **`SERVE_GL=1`** à `pending/sep_xart_replay.sh` + lanceur `pending/serve_gl_go.sh` (SERVE_GL+PROBE_SBIO).
    Au lieu de rejouer un OOL périmé, le script SERT à la puce son coffre réel : op 0x00 (maître SEP/USER depuis slots
    type 0x02/0x01), op 0x05 (gigalocker par UUID lu en B), op 0x13 (UUID d'OS = nom du .gl), op 0x0e (fw). Format de
    réponse recalculé (longueur = PARAM|DATA0<<8 ; maître préfixé 0x11, gigalocker non) — cf. docs/gigalocker.md.
  - **Sûreté** : on N'ACQUITTE JAMAIS un SAVE (0x01/0x06). Si la puce rejette (mauvais emballage ou coffre jugé non
    courant), elle émet un SAVE → STOP sans acquitter → compteur non avancé → **pas de brick** (c'est l'ack de SAVE,
    évité ici, qui avait cassé le boot). Gigalocker absent → STOP. Échec FERMÉ partout.
  - **Protocole décodé avant de coder** (règle CLAUDE.md) : format de réponse FETCH craqué sur c24 (longueur=PARAM|DATA0<<8,
    vérifié maîtres 0x364/0x814 + gigalocker 0xc0c ; DATA1=sélecteur SEP/USER ; CRC dans le blob). HYPOTHÈSES non
    vérifiables sans capture de CETTE puce (hyperviseur 13.5 perdu) : charge fil = .gl+0x22 à l'octet près ; préfixe maître
    = 0x11 nuls ; ordre UUID d'OS. Si fausses → essai non concluant (power-cycle gâché), PAS un brick. docs/gigalocker.md.
  - Correctifs **sceptique** (revue PROBE_SBIO d'avant, jamais appliqués car redirection) appliqués : purge `sep.msgs[0x08]`
    avant le 0x73 (faux positif), honnêteté IOVA/stream DART dans le verdict négatif, TypeError SELFTEST.
  - Vérifs : `bash -n` OK, `py_compile` OK (763 l.), SELFTEST SERVE_GL montre 2 maîtres (SEP-xART 0x352, USER-xART 0x540) +
    10 gigalockers + UUID d'OS 16 o.
  - Relecture **sceptique** du mode SERVE_GL : **sûreté CONFIRMÉE** — aucun chemin n'acquitte un SAVE ni n'avance le
    compteur scellé, fail-closed réel, pas de brick, aucun endpoint interdit hors 0x13 (cible)/0x08 (autorisé). 4 corrections
    appliquées : (1) la branche SAVE + le résumé disent qu'un SAVE **ne tranche pas** (emballage faux = non concluant VS vrai
    refus) ; (2) verdict dédié SERVE_GL (l'ancien imprimait « 0 rejoués / divergence 0/N », absurde) ; (3) liste d'hypothèses
    complétée (d valeurs fixes 0x0e/0x13, e UUID lu à l'offset 0 de B, f pas de sélecteur gigalocker) ; (4) garde pré-boot
    GL_FILE/GL_OS_UUID (meurt proprement sans toucher le Mac si coffre absent/UUID invalide). Re-vérif bash/py/SELFTEST OK.
- PROCHAIN PAS : Albert fait une sauvegarde (idéal) → lance `! ./pending/serve_gl_go.sh`. Si la puce
  accepte et sbio répond au 0x73 → biométrie fonctionnelle sous Linux (1re fois). Si SAVE/rejet → non concluant, on affine
  l'emballage (le log dira où ça diverge). **Rien lancé par l'agent.**
- Incidents : aucun.

## 2026-11-17 (nuit) — Claude (Opus 4.8) — Coffre décortiqué : 12 lockers (2 maîtres + 10 gigalockers), UUID stables au DFU
- Trace : analyse hors ligne du dump `traces/20261117-224724_xart_read/…_.gl.bin`. Aucun matériel.
- Fait : parsé le fichier gigalocker (6 Mo) → `docs/gigalocker.md` + `analysis/parse_gigalocker.py` (reproductible).
- Vu (FAITS, parse du dump) :
  - Fichier = tableau de **slots de 0x9000 o** ; **12 lockers** (slots 0,1,3,4,5,6,7,8,9,10,11,12 ; slot 2 vide).
  - En-tête d'un locker : +0x00=0, **+0x01=type**, **+0x02..0x12=UUID (16 o, gigalockers)**, **+0x12=longueur (u32)**,
    +0x16=CRC (u32), **+0x22=charge** (scellée). Taille = 0x22+longueur (recoupe la zone non nulle).
  - Types : **0x01 = USER-xART (maître)**, **0x02 = SEP-xART (maître)** (sans UUID) ; **0x03/0x04 = gigalocker** (avec UUID).
    → **2 maîtres + 10 gigalockers**. (Rapproché handoff : SEP-xART+Credential variables, USER-xART stable.)
  - **UUID STABLES au DFU** : 6 des 10 UUID de gigalockers (slots 0,4,5,8,10,11 ; dont Credential Manager 8624497a ×6)
    se retrouvent **à l'octet près** dans les tampons OOL des captures c21/c23/c24 (puce d'AVANT le DFU du 16/11).
- Interprété : ces UUID sont liés à l'appareil (pas à l'état) → les demandes du SEP sous m1n1 correspondront aux slots de
  ce `.gl`. Le coffre actuel contient TOUT ce que le SEP réclame (2 maîtres + gigalockers par UUID) → le « mur » FOLLOW
  (« le SEP réclame un gigalocker qu'on ne sert pas ») devient franchissable en servant depuis ce fichier. Réserve inchangée :
  l'anti-rejeu interne (nonce, probablement dans le maître SEP-xART slot 6) peut encore refuser ; lire ≠ prouver le rejeu.
- PROCHAIN PAS : préparer un mode « servir les FETCH (op 0x00 maître + op 0x05 gigalocker par UUID) depuis le `.gl` » dans
  `pending/` (lancé par Albert). D'abord lire le format EXACT de la réponse FETCH (capture macOS + kext §8) — règle
  « protocole complet avant de répondre ».
- Incidents : aucun (hors ligne).

## 2026-11-17 (nuit) — Claude (Opus 4.8) — ✅ COFFRE LU sur le disque de la puce réparée (lecture seule, sans macOS)
- Trace : `traces/20261117-224724_xart_read/` (liste + dump du gigalocker). Proxy m1n1 up, lecture seule.
- Suite de l'entrée précédente (« coffre pas trouvé par get_gigalocker »). Albert a choisi « cherche où est le coffre ».
- Fait : porté en Python (lecture seule) la marche APFS de m1n1 (`apfs.rs`) : `tools/apfs_list_volumes.sh` (liste les
  volumes + rôles de chaque conteneur) puis `tools/read_xart.sh` (parcourt le volume xART : fs-tree racine → dir-records
  → extents → dump des fichiers). **Rien dans m1n1/.**
- Vu (FAITS, lectures seules sur la puce actuelle) :
  - Le volume de **rôle xART (0x100) EXISTE**, dans le conteneur #0 (iBootSystemContainer, LBA 6), nommé `xART` —
    exactement là où m1n1 cherche. Les autres conteneurs (macOS #1, ALARM, UEFI, Recovery) n'ont pas de volume xART.
  - Le volume xART contient **UN** fichier : `74980DEE-AD6A-5674-B233-B7E10A7FD0CB.gl` (inode 0x10, 1 extent,
    **6 291 456 o = 0x600000**, dont **18912 octets non nuls** = creux). SHA256 `8c5498a4fcb925b1…`.
    Tête : `00042438821b3dc0faf876d7aad6ca4dc668b9010000223e09baa500000000…`.
  - → **COFFRE RÉCUPÉRÉ** : il COLLE à la puce réparée + Touch ID ré-enrôlé (lu en direct sur l'install macOS 27.2.1),
    sans réinstaller de macOS traçable, sans hyperviseur. C'est ce qui manquait (le snew-reel 11/11 était périmé).
- Interprété : si `get_gigalocker` (m1n1 tout-fait) renvoyait vide, c'est le m1n1 en place (v2.0.0-92-g70757dc7) qui est
  **antérieur** au commit ajoutant l'op (07c2c3af, 2026-07-16) → firmware sans l'op 0x1400. Le portage Python contourne.
- PROCHAIN PAS (hors ligne d'abord, sans risque) : **parser la structure du .gl** (lockers par UUID, cf. Asahi
  public_linux_state §B : UUID @0x01, long @0x12, CRC @0x16, payload @0x22) pour (a) comprendre ce qu'il contient, (b)
  pouvoir **servir les FETCH gigalocker (op 0x05) par UUID** que le SEP réclame sous m1n1 (le « mur » de l'essai FOLLOW).
  Reste la réserve de fond : l'anti-rejeu interne SEP peut encore refuser ; mais on teste enfin avec un coffre QUI COLLE.
- Incidents : aucun. Aucune écriture nulle part.

## 2026-11-17 (nuit) — Claude (Opus 4.8) — Lire le coffre (gigalocker) sur le DISQUE sans macOS : outils OK, mais pas trouvé sur la puce réparée
- Trace : `traces/20261117-223*_gigalocker_cleanchip` (vide), `…_gpt` (table de partitions). Proxy m1n1 up, lecture seule.
- Contexte : le vieux coffre (snew-reel, 11/11) ne colle plus à la puce réparée (DFU 16/11) ; on ne peut plus capturer via
  l'hyperviseur (13.5 perdu). Albert a choisi : **chercher à LIRE le coffre directement** là où macOS le range, sans réinstaller.
- Fait (hors ligne + lectures seules via tools/) :
  - Découvert (déjà dans `public_linux_state.md` §D) que **m1n1 sait lire le coffre sur disque sans macOS** :
    `ProxyUtils.get_gigalocker()` (op proxy `P_READ_GIGALOCKER=0x1400`, `rust_read_gigalocker` dans m1n1/rust/src/apfs.rs).
    **100 % lecture** (vérifié : apfs.rs n'a que des `pread`, 0 `pwrite`). Ne touche NI SEP NI macOS NI table de partitions.
  - Écrit 3 outils lecture-seule (dans tools/, **rien dans m1n1/**) : `read_gigalocker.sh`, `dump_gpt.sh`, `apfs_magic.sh`.
- Vu (FAITS, lectures seules sur la puce actuelle) :
  - `get_gigalocker` → **AUCUNE donnée** (« volume xART introuvable »). Le NVMe s'initialise et lit bien (pas un pb de lien).
  - GPT (`dump_gpt.sh`) : 8 partitions. #0 `69646961-…` «iBootSystemContainer» (0,5 Go), #1 `7c3457ef` «Container» macOS (84 Go),
    #2 APFS (2,5 Go), #3 EFI, #4 Linux (401 Go), #5 APFS (2,5 Go), #6 EFI, #7 RecoveryOSContainer. **Un seul** conteneur `69646961`.
  - `scan_disks` de m1n1 ne scanne que la **1re** partition de GUID `69646961` (= #0) et n'essaie pas les autres conteneurs.
  - APFS (`apfs_magic.sh`) : tous les conteneurs = **NXSB standard, INCOMPAT=0x2 (APFS v2), block 4096** → **pas** un format trop récent.
- Interprété (HYPOTHÈSE) : le parseur public lit bien ces conteneurs (format standard) ; donc s'il ne trouve pas de volume de rôle
  xART dans #0, c'est que **le volume xART n'est pas dans #0 sur ce disque** (ailleurs, non scanné par m1n1), **ou pas encore créé**.
  Sur un Mac « normal » où `get_gigalocker` marche, le xART est dans le conteneur `69646961`. Pourquoi pas ici : à trancher.
- PROCHAIN PAS (read-only, sans risque) : **énumérer les volumes APFS** (rôle) de chaque conteneur (marche d'omap B-tree, portage
  Python de `apfs.rs`) pour localiser le volume de rôle xART (0x100), puis lire son gigalocker. Si introuvable partout → le coffre
  n'est pas (encore) matérialisé sur ce disque, et « lire le coffre » bute ici.
- RÉSERVE de fond inchangée : même avec le coffre lu, l'anti-rejeu (nonce interne SEP) peut refuser le rejeu ; lire le coffre sert
  surtout à avoir un coffre QUI COLLE (pour servir les FETCH gigalocker / tester « sbio vivant »), pas à prouver le rejeu.
- Incidents : un appel python-m1n1 direct (hors tools/) refusé par le classifieur (règle « hardware uniquement via tools/*.sh ») →
  rangé en `tools/apfs_magic.sh`. Aucune écriture nulle part.

## 2026-11-17 (nuit) — Claude (Opus 4.8) — ESSAI D préparé : sonde sbio « annoncé vs vivant » (mode PROBE_SBIO, pending/, à lancer par Albert)
- Trace : — (préparation ; aucune action hardware). Proxy m1n1 up (puce propre, Touch ID ré-enrôlé).
- Contexte : Albert a choisi « prépare l'essai » (réveiller la partie empreinte + lui poser une question
  inoffensive). C'est le PROCHAIN PAS (iii) déjà identifié dans hypotheses.md (« une fois sbio/sks annoncé,
  tester une lecture côté sbio pour annoncé-vs-vivant, script pending/, Albert »). 1re fois sur une puce VALIDE.
- Fait (hors ligne, rien lancé) :
  - Ajout du mode **`PROBE_SBIO=1` (exige FOLLOW=1)** à `pending/sep_xart_replay.sh` (v3.1 → +essai D) et
    lanceur court `pending/probe_sbio_go.sh`. Après que FOLLOW a fait annoncer sbio (0x08), le script ouvre
    l'EP 0x08 (alloue/mappe/annonce A8+B8 de 0x4000 par CNTL param=0x08, mécanique déjà éprouvée pour 0x13),
    écrit dans A8 les **octets EXACTS** du 1er `0x73` `initSbioCommunication` (rejoués depuis c12
    `000300_08_A.bin`, pas construits), envoie `> EP=0x08 TAG=0xfc TYPE=0x73`, lit B8 ~6 s, **n'acquitte rien,
    une seule commande, sans doigt**. Échec FERMÉ partout (sbio non annoncé / CNTL non acquitté / SBIO_A pas un
    0x73 → rien envoyé).
  - **Protocole complet avant de coder** (règle CLAUDE.md) : wire ancré octet-à-octet dans c12 — ouverture sbio
    (sep.log L126-135), `0x73` (L318), réponse SEP de référence `< TAG=0x04` puis `< TAG=0xfc TYPE=0x73`, B
    (000301_08_B.bin) = +0x00=1, +0x14=0x73. Verdict du script = B8[+0x00]==1 & B8[+0x14]==0x73, ou message EP 0x08.
  - Vérifs : `bash -n` OK ; Python embarqué (617 l.) `py_compile` OK ; SELFTEST PROBE_SBIO OK (valide que SBIO_A
    est bien un 0x73). Bug corrigé avant commit : `OUT` utilisé comme variable Python au lieu de `os.environ["OUT"]`
    (NameError sur un chemin non couvert par SELFTEST).
  - Relecture **sceptique** lancée (sous-agent) sur le seul mode PROBE_SBIO.
- Inconnu assumé (dit dans l'en-tête et la sortie) : le stream/IOVA DART que la GT de sbio lit sous m1n1 (on a mis
  les valeurs macOS 0x54000/0x5c000) ; si le SEP ne lit pas A8 là → silence = faux négatif possible (même classe
  d'inconnu que pour xART). Et « sbio vivant » ≠ « Touch ID marche » (reste l'init capteur + un vrai match).
- Incidents : aucun. **Rien lancé vers le Mac** — Albert relit + lance (`! ./pending/probe_sbio_go.sh`), de préférence après une sauvegarde ; récup si ça rate = power-cycle, au pire DFU Restore depuis le PC (déjà éprouvé).

## 2026-11-17 (soir) — Claude (Opus 4.8) + Albert — ✅ Proxy m1n1 ré-établi sans macOS 13.5 (backdoor csrutil + tools/catch_proxy.sh)
- Trace : — (pas de capture ; mise en place du proxy). Mac EN PROXY à la fin.
- Fait :
  - **Touch ID ré-enrôlé** par Albert (macOS 27.2.1) → état scellé SEP valide et courant.
  - **Backdoor Asahi activée** par Albert en recovery/1TR : `csrutil disable` sur **2 (alarm)** ET **3 (UEFI boot)**
    (pas macOS), + `nvram boot-args=-v`. Les deux sont nécessaires. Diagnostic clé : sans la backdoor, les m1n1
    installés (payload → ALARM) ne présentent **jamais** le proxy → échecs d'attrapage précédents expliqués.
  - **Nouvel outil `tools/catch_proxy.sh`** (Claude) : attend les ports USB du m1n1 au boot, ouvre if02, chainloade
    `m1n1/build/m1n1.bin`. Lancé en arrière-plan, Albert power-cycle → attrapé.
- Vu (FAITS) : `Waiting for proxy connection... Connected!` ; m1n1 **v2.0.0-92-g7075** up ; ports
  `usb-Asahi_Linux_m1n1_uartproxy_v2.0.0-92-g7075_WHFWP7FYXF-if00/if02` + `/dev/ttyACM0`/`ttyACM2` présents et stables.
  Modèle confirmé par m1n1 : MacBookPro18,4 / J314c / Chip-ID 0x6001 / M1 Max. `Boot policy: sip0 = 127` (SIP désactivé).
  - **Vérif lecture seule** (`SKIP_CHAINLOAD=1 ./tools/sep_peek.sh`, trace `20261117-220411_sep_peek_cleanchip`) :
    `sep_reg0_base=0x396400000` ; `CPU_CONTROL=0x0 RUN=0` ; `A2I_CONTROL=0x00028801` et `I2A_CONTROL=0x00029901`
    (les deux boîtes aux lettres `ENABLE=1`, `EMPTY=1` = au repos). Lien PC→m1n1→SEP OK de bout en bout sur la puce enrôlée.
- Interprété : **le proxy m1n1 (et tout le travail SEP) ne dépend PAS de macOS 13.5** — preuve par l'expérience (ré-établi
  sans 13.5). Le 13.5 ne servait qu'au tracing macOS sous hyperviseur (`run_guest.py`). Repère CLAUDE.md « 13.5 uniquement »
  périmé (doc Asahi : invités supportés 13.5 ET 14.8.3). Résout probablement le « tu as mal compris la 13.5 » d'Albert.
- Incidents : (1) `catch_proxy.sh` sort en exit 1 (chainload « Waiting for reconnection… » > M1N1TIMEOUT 3 s après ré-énum)
  mais le proxy EST up — cosmétique, à corriger. (2) `pkill -f catch_proxy.sh` dans la commande de lancement en arrière-plan
  se tue elle-même (self-match, exit 144) — ne plus le faire. Aucune écriture SEP ; aucune écriture disque.

## 2026-11-17 — Claude (Opus 4.8) + Albert — Mac récupéré ; reprise du projet sur SEP propre ; perte de macOS 13.5 actée
- Trace : — (aucun matériel ce jour ; récap d'état).
- Fait : constat d'état à la reprise. Docs remises à niveau (handoff bandeau, RECUPERATION_MAC marqué RÉSOLU,
  mémoire [[mac-boot-casse-recuperation]] enrichie de la conséquence stratégique).
- Vu (rapporté par Albert) : **macOS 27.2.1 neuf ET ALARM réinstallé bootent tous les deux normalement**
  (ALARM par image bloc `alarm_p5.img` + GRUB refabriqué ; fstab /efi corrigé par Albert). **SEP propre/neuf.**
  **Perdu et non réinstallés** : partitions jetables **macOS 13.5** et **Fedora de test (10.0.200.4)**.
  Décision d'Albert : « linux et macos sont bons … on continue sur 2 » = reprendre le projet Touch ID.
- Interprété (conséquences, pas des faits neufs sur le SEP) :
  - ⚠️ **À REPRENDRE AVEC ALBERT** : le 2026-11-17 il a dit « je crois pas que tu as compris ce qui s'est passé avec
    la 13.5 », puis « continue en autonomie » sans détailler. Le point ci-dessous est donc **mon hypothèse NON validée**.
  - **(hypothèse) Capture SEP sous macOS = close.** J'avais déduit : l'hyperviseur m1n1 (`run_guest.py`) ciblait macOS
    **13.5** (README/CLAUDE.md), 13.5 ne serait plus signé → plus d'observation de macOS faisant Touch ID. À confirmer/
    corriger avec Albert. Robuste quoi qu'il arrive : l'essentiel du protocole est déjà sorti par décompilation (sans Mac),
    et la stratégie était déjà « driver natif + SEP propre ».
  - **m1n1 proxy à refaire** : il vivait sur le volume 13.5 (install kmutil). ALARM boote via m1n1 (ESP) mais le mode
    *proxy* nu (« Running proxy… », `sep_boot`/`sep_peek` sans macOS) reste à remonter avant toute reprise SEP matérielle.
  - **Base inédite** : 1re fois qu'on pourrait essayer contre une puce **valide et à jour** (après ré-enrôlement Touch ID),
    là où avant l'état SEP était cassé/invalide donc rien n'était *validable*.
- Prochain (matériel, Albert, pas urgent) : ré-enrôler Touch ID (macOS 27.2.1) → revalide l'état scellé ; réinstaller
  m1n1 proxy ; image disque avant toute écriture SEP. Offline (Claude, maintenant) : consolider le protocole sorti des
  kexts (opcodes nommés sbio EP 0x08, archi SKS EP 0x12) dans messages.md/driver_plan.md, prêt pour le driver.
- Incidents : aucun.

## 2026-11-13 — Claude (Opus 4.8) — Consolidation hors ligne : verification_status.md + driver_plan.md remis à niveau
- Trace : — (aucun matériel ; Mac inchangé, à power-cycler avant tout SEP).
- Fait : les deux docs « aval » étaient en retard sur la session décompilation (verification_status s'arrêtait au 11-11, driver_plan
  datait du 08-11). Ajout daté dans chacun, à partir du journal 12-13/11 et de kext_sepmanager.md §9/§12c/§13/§14 (pas de fait neuf créé).
- Vu / reporté : format fil sbio `gt_packet_t` **VÉRIFIÉ** contre capture (c12, outil `analysis/sbio_gt_packet.py`) ; pont opcode↔opération
  (§12c) ; voie C / nonce xART = quasi-morte côté AP (§9, hypothèse kext) ; SKS (0x12) = RPC à params DER, pas des opcodes (§14, hypothèse kext).
- Interprété : driver_plan acte le basculement de stratégie (Touch ID = driver natif + état SEP valide via DFU restore côté Albert, pas un rejeu).
- Incidents : aucun.

## 2026-11-12 (22:38) — Claude (Opus 4.8) + Albert — ESSAI B reproduit (n=2) : sks/sbio ré-annoncés + l'enveloppe 16 o se sépare en digest déterministe (locker) vs variable par boot (xART)
- Trace : `traces/20261112-223837_xart_replay` (+ `follow_B/`, 13 blobs). Albert a lancé `follow_go.sh`. Comparé à `…215313` (n=1).
- Fait : rejeu de la même capture (`…113919_snew-reel`) une 2e fois ; diff croisé des deux jeux de 13 blobs B.
- Vu (FAITS) :
  - **Reproduit** : 13 ops acquittées, **sks (0x12) ET sbio (0x08) ré-annoncés** (n=2).
  - **Intra-run reproduit** : l'op `0x07` (locker-absent, blob 010) ne change **que les 16 premiers octets** (`009→010 : 16 o diff @ 0x0000-0x000f`), corps identique — identique au run 1.
  - **Croisé entre les 2 runs (fait neuf)** : les **16 premiers octets** sont **IDENTIQUES d'un run à l'autre** pour tous les SAVE-**locker** (TYPE 0x06 : blobs 002/005/008/012) **et** pour le 0x07 (010) ; ils **DIFFÈRENT** pour tous les SAVE-**xART** (TYPE 0x01). Les octets **16+** et le corps diffèrent entre runs **partout**.
  - Les 16 o de tête des lockers sont **distincts entre lockers** (407e94c4… / 9133c5d5… / e01e3b5e… / 2438821b… / 0x07=d15bc8da…) → pas une constante globale.
- Interprété (HYPOTHÈSE, raffine l'entrée « Fraîcheur SAVE » et [[voie-c-xart-fraicheur]]) : l'« enveloppe 16 o » n'est pas monolithique.
  Pour un **locker**, les 16 premiers octets = **empreinte déterministe du contenu** (le locker est rejoué à l'identique → même empreinte
  aux 2 runs), **pas** un nonce. La matière **variable par boot** (la fraîcheur) vit dans les **blobs xART maîtres** (TYPE 0x01, dont les
  16 premiers octets changent par boot) et dans les octets **16+** de tout blob (chiffrés/MAC avec la matière de session). Cohérent avec le
  §9 : le SEP mêle une matière de session par boot que l'AP ne contrôle pas → un vieux blob xART rejoué ne colle pas au nonce du boot courant.
  RÉSERVE : n=2, lecture de tampon ; « empreinte » vs « MAC tronqué » non tranché ; ne change pas la conclusion voie C (rejeu impossible côté AP).
- Incidents : 13 re-scellements (SEP, vraies écritures) ; côté macOS déjà cassé, Linux/données intacts. Power-cycle demandé après le run.

## 2026-11-12 (soir, hors ligne) — Claude (Opus 4.8) — VÉRIFIÉ : verdict de match Touch ID (opcode 0x09 → match_info_t) sur 3 captures
- Trace : `c6-doigt-ool`, `c8-doigt-ool`, `c11-doigt-tranchant` (buffers OOL EP 0x08 déjà capturés, doigt sur capteur). Outil `analysis/sbio_gt_packet.py`.
- Fait : parsé les transactions de match (opcode 0x09) et leurs réponses (buffer B = `gt_packet_t`), extrait le verdict en tête du `match_info_t`.
- Vu (FAIT **VÉRIFIÉ**, reproductible, ~35 réponses sur 3 captures) : commande match = `gt_packet_t` op 0x09 payload vide ; réponse = `gt_packet_t`
  op 0x09, payload `match_info_t` (0xca2 o). **Verdict en tête : `+0x00 = 0x1f5` (succès, user 501) + identifiant 16 o `fe6003d8cea5414fb48a0338dc7c371b`
  (le doigt enrôlé) ; `0xffffffff` + zéros = échec.** Tous les succès = même identifiant ; tous les échecs = zéros. 0 faux positif.
- Interprété : c'est le **signal « doigt reconnu »** que le driver Linux lira (rattache `handleMatch`→`match_info_t` du kext au marqueur
  `0x1f5`/`fe6003d8…` déjà noté par l'analyste, messages.md §SBIO). Les ~3200 o restants = métadonnées image/score (non décodés).
- Incidents : aucun (hors ligne, captures existantes).

## 2026-11-12 (soir, hors ligne) — Claude (Opus 4.8) — VÉRIFIÉ : format fil sbio (gt_packet_t) confirmé par capture + outil d'analyse
- Trace : `traces/20261108-032454_c12-boot-ho/sep.log.ool/*_08_A.bin` (dumps OOL EP 0x08 déjà capturés). Désassemblage AppleSEPGenericTransfer.
- Fait : décodé la chaîne `sepTransact → AppleSEPGenericTransfer::transact (0x9939900) → message 0xfc (0x9937348) → gt_packet_t (0x9937570)` ;
  **vérifié** le format contre les buffers capturés ; écrit l'outil `analysis/sbio_gt_packet.py`. Docs : `kext_sepmanager.md §13/§13b`.
- Vu (FAIT **VÉRIFIÉ** par trace, 14 buffers A + fragmentation) : un message EP 0x08 `type=0xfc` (tag = compteur++) porte un buffer OOL
  = **`gt_packet_t`** : `+0x00 kind=1`, `+0x04 total`, `+0x08 offset`, `+0x0c flags`, `+0x14 OPCODE`, `+0x18 longueur fragment`,
  `+0x1c payload`. Confirmé sur c12 : `+0x00=1` 14/14 ; opcodes lus = 0x17 (n° série), 0x15/0x16 (clé session), 0x42/0x18 (compteur),
  0x5f (patch, 16 Ko), 0x1f (match policy)… ; **fragmentation vérifiée** (opcode 0x5b, total 0xfc99, offset 0→0x3fe4→0x7fc8→0xbfac).
- Interprété (noms = `source: kext`) : séquence d'init capteur c12 = série → clé(0x15/0x16) → compteur(0x42/0x18) → patch(0x5f) →
  params(0x5d) → switchToProd(0x32) → matchPolicy(0x1f) → calib(0x63) → reset(0x19). Le **format fil sbio est maintenant VÉRIFIÉ**
  (les noms d'opérations restent hypothèse kext). On peut parser l'opcode de toute transaction EP 0x08 (`analysis/sbio_gt_packet.py`).
- Incidents : aucun (hors ligne).

## 2026-11-12 (soir, hors ligne) — Claude (Opus 4.8) — Table opcode sbio ↔ opération ↔ TAG fil (pont kext↔traces, socle driver)
- Trace : — (scan `scratchpad/scan_opcodes.py` + lecture de contexte sur `macos/kernel.macho` ; non commité). Aucun matériel.
- Fait : repéré les appels virtuels à `sepTransact` (slot +0x9e0) dans tout le `__text` Mesa et lu l'opcode (`mov w1,#imm`) par opération.
  Écrit `docs/kext_sepmanager.md §12c`.
- Vu (FAITS, source: kext) : opcodes EP 0x08 par opération — `handleMatch`=**0x09** (puis 0x0c), `handleEnrollment`=0x08,
  `commandStartEnroll`=0x03, `forceNoMatch`=0x06, `asyncCaptureHandler`=0x07/0x22, `performKeyExchange`=0x15,
  `cacheMatchPolicy`=0x1f, `initializeSequenceCounter`=0x42, `applySensorParams`=0x5d, `setCalibrationData`=0x63, `seaCookieHandleMessage`=0x4a.
- Interprété / RECOUPEMENT : plusieurs opcodes (0x03/0x06/0x07/0x09/0x1f/0x22) sont **exactement** les octets de la sous-séquence de
  match `23 06 65 07 09 1f 22 70 03 21` déjà vue en trace → ce sont les **sous-commandes capteur d'un match** ; `0x09` = l'ordre de match
  (= le `<09` ~240 ms de C3/C8). Et 0x42=compteur, 0x15=clé de session recoupent §4. **Pont kext↔traces établi** = socle du driver (phase 2+).
  Statut `hypothèse` (source: kext), partiellement cross-validé. Reste des opcodes chargés via registre (HandleReset/LoadPatch…) à finir.
- Incidents : aucun (hors ligne).

## 2026-11-12 (soir, hors ligne) — Claude (Opus 4.8) — Carte des opérations sbio : vtable AppleMesaSEPDriver résolue (noms de méthodes)
- Trace : — (désassemblage + résolution de vtable `macos/kernel.macho` ; outil `scratchpad/vtable_dump.py`, non commité). Aucun matériel.
- Fait : résolu la vtable `__ZTV18AppleMesaSEPDriver` (chained-fixup arm64e auth-rebase, base `0xfffffe0007004000`) → 344 slots nommés ;
  isolé les méthodes propres au driver = surface d'opérations sbio. Désassemblé `getProvisioningState`, `diagnostics`. Écrit `kext_sepmanager.md §12`.
- Vu (FAITS, source: kext) : primitive d'envoi = `sepTransact(uint opcode, in, inLen, out, outLen, …)` (slot 316, appelée **en virtuel**).
  Opérations nommées : provision/unpair/unprovision/`provisionNavajo`/`provisionSandDollar`/`lockRootKeyInSensor`/`establishDiffieHellmanSession`/
  `LoadPatch` = **mutations** ; `getPreImage`/`getSerialisedTemplates` = **données biométriques (interdit de sonder)** ;
  `getProvisioningState` = **caché côté AP** (désassemblé : empaquette `getProvisioningStateInt`, aucun aller-retour SEP) ;
  `diagnostics` = interface à sous-commandes (sélecteur `in[0]`=1..5). (Navajo, SandDollar = noms Apple du capteur Touch ID.)
- Interprété : pas de « ping statut » fil **trivial et sans effet de bord** à cette couche → la sonde « vivant » n'est pas un one-shot.
  Prochain pas sonde : suivre une sous-commande de `diagnostics` ou `getSepTimeMeasurements` pour isoler une lecture `sepTransact` propre.
  La carte reste surtout utile pour le **driver** (phase 2+). Statut `hypothèse` (noms de méthodes).
- Incidents : aucun (hors ligne).

## 2026-11-12 (soir, hors ligne) — Claude (Opus 4.8) — Reconnaissance sbio (EP 0x08) : pas de lecture-statut fil triviale ; dispatch par vtable
- Trace : — (désassemblage AppleMesaSEPDriver, `kdis.py func`, venv capstone ; listings non commités). Aucun matériel.
- Fait : cherché un message sbio de lecture pure pour une sonde « vivant ». Désassemblé `getProvisioningStateInt`, `provisionSensor`.
  Écrit `docs/kext_sepmanager.md §11`.
- Vu (FAITS, source: kext) : (1) `getProvisioningStateInt` lit des champs **cachés côté AP** (`_provisionStatus` +0x1f0…), aucun
  aller-retour SEP → « statut provision » ne prouve pas le lien vivant *maintenant*. (2) Les opérations sbio passent par **méthodes
  virtuelles** du driver Mesa (`provisionSensor` → `this+0xa48`/`+0xa58`) ; opcodes fil dans la vtable, stack **stateful**.
- Interprété : la sonde « vivant » sbio n'est **pas** un one-shot simple → cohérent avec la prudence « annoncé ≠ vivant ». Prochain pas
  utile (surtout pour le driver) : **marcher la vtable Mesa** pour nommer les opcodes EP 0x08, croisés avec les TAGs fil de `messages.md`.
- Incidents : aucun (hors ligne).

## 2026-11-12 (soir, hors ligne) — Claude (Opus 4.8) — Décompilation du nonce xART/ROM : aucun levier AP pour fixer la fraîcheur (verrou maître voie C)
- Trace : — (désassemblage `macos/kernel.macho`, bundle AppleSEPManager, `analysis/kext/kdis.py func`, venv capstone du scratchpad ;
  listings non commités). Aucun matériel. Cible choisie car c'est le **verrou maître de la voie C**.
- Fait : désassemblé `generateROMNonce`, `_nonce_action` + son block_invoke, `nonce_generate`/`nonce_read` ; cherché toute API set/seed-nonce
  et les usages NVRAM d'AppleSEPManager. Complété `docs/kext_sepmanager.md §9`.
- Vu (FAITS, source: kext) : (1) sélecteurs `nonce_generate`=0x0f, `nonce_read`=0x10 ; nonce = **20 o / 160 bits**. (2) `generateROMNonce`
  envoie une requête **constante** `0x00030100` (aucune graine), le SEP répond **opcode 0x67 + data 0xa0** (NONCE_BIT_LEN=160), l'AP **lit**
  mot par mot. (3) **Aucun symbole** set/seed/write-nonce côté SEP/XART/Booter (recherche vide). (4) NVRAM vue par AppleSEPManager =
  `oblit-inprogress`, `auto-boot`, `sep-debug-args` seulement — **pas** de `boot-nonce`/graine xART.
- Interprété (HYPOTHÈSE renforcée) : **côté AP, aucun levier pour fixer/semer/reproduire le nonce de fraîcheur** → un rejeu (statique ou
  relais) d'un état scellé sous un ancien nonce ne peut pas être rendu « frais » sous Linux → le re-scellement (op 0x01 à TAG=0x05) est le
  comportement **attendu** ; la voie C « faire accepter un rejeu » penche **fortement vers impossible côté AP**. RÉSERVE : prouve l'absence
  d'API AP, pas que la ROM SEP n'a pas sa propre graine interne (non observable d'ici). Détaille/raffine HV1(B)/HV2 et [[voie-c-xart-fraicheur]].
- Incidents : aucun (hors ligne).

## 2026-11-12 (soir, hors ligne) — Claude (Opus 4.8) — Étude SKS (EP 0x12) démarrée : inventaire pour une sonde « annoncé vs vivant »
- Trace : — (lecture du kernel `macos/kernel.macho` via `analysis/kext/ksyms.py` ; aucun matériel). Filtre cyber : **n'a pas coupé** sous Opus 4.8.
- Fait : relié les symboles keystore aux messages EP 0x12 de `docs/messages.md`, pour trier lecture pure vs mutation. Écrit `docs/kext_sepmanager.md §10`.
- Vu (FAITS, source: kext) : transport du keybag = `com.apple.driver.AppleSEPKeyStore` (EP 0x12, bundle présent). Classes `AppleKeyStore`
  (`unload_keybag`, `set_volume_keybag`, `tdm_*`) et `AppleFDEKeyStore` (`setPassphrase`, `deleteKey`…) = méthodes majoritairement mutantes.
- Interprété / conclusion (hypothèse) : commandes on-wire 0x2f (verrouille), 0x41/0x18 (déverrouillent) = **mutations** ; **0x04/0x06
  (→0x84/0x86) = seul candidat LECTURE** (reflète l'état login, jamais vu muter), **non vérifié**. (1) EP 0x12 = **ligne rouge écriture** →
  toute sonde va dans `pending/`, lancée par Albert. (2) Le TYPE = compteur de transaction → une requête hors-séquence peut désync.
  (3) **`sbio` (EP 0x08) n'est PAS sur la liste rouge** → porte de sonde plus sûre que sks pour tester « vivant ».
- Incidents : aucun (hors ligne).

## 2026-11-12 (soir, hors ligne) — Claude (Opus 4.8) — Analyse des 13 blobs B re-scellés : l'op 0x07 ne change QUE 16 octets de tête, corps identique
- Trace : `traces/20261112-215313_xart_replay/follow_B/` (13 blobs de 32768 o, lecture seule). Aucun matériel.
  Script : `scratchpad/analyze_blobs.py` (régions non nulles, diff consécutif, octets stables, recherche de compteur, entropie).
- Fait : diff octet par octet des 13 tampons B que la puce a re-scellés pendant l'ESSAI B, pour répondre à
  « que re-scelle-t-elle ? un nonce/compteur bouge-t-il ? ».
- Vu (FAITS) :
  - Données concentrées **au début** du tampon (0x0000 → au plus 0x0264 = 612 o) ; tout le reste des 32 Ko = 0.
  - Zone non nulle **croissante** à mesure que les lockers s'accumulent : 127 → 225 → 323 → 420 o
    (pic à **613 o** au blob 008 = un SAVE-locker 0x06, puis retombe à 322).
  - Diff consécutif : entre deux SAVE de **contenu différent**, **toute** la zone non nulle change (ré-écrite).
  - **EXCEPTION nette — blob 009 → blob 010 (l'op `0x07` locker-absent)** : **seuls les 16 premiers octets (0x00–0x0f)
    changent** ; le corps `0x10`→`0x142` (**307 o**) est **byte-à-byte identique**. Vérifié à part : corps identique = `True`,
    tête `009`=`b460a57e…4542e8`, `010`=`d15bc8da…24b264`.
  - Les 16 octets de tête sont à **entropie quasi-maximale** (≈4 bits/oct, 15–16 valeurs distinctes sur 16) sur les 13 blobs.
  - **Aucun** octet non nul **stable** commun aux 13 ; **aucun compteur en clair monotone** (largeurs 1/2/4 oct, LE) dans les 0x400 premiers octets.
- Interprété (HYPOTHÈSE, lecture de tampon, n=1) :
  - Structure probable du B re-scellé : **[16 o d'enveloppe de fraîcheur (nonce ou MAC/tag, haute entropie)] + [corps scellé]**.
  - L'op `0x07` re-scelle **sans nouveau contenu** → le corps ne bouge pas, **seule l'enveloppe 16 o est rafraîchie**. C'est la
    signature d'un **anti-rejeu** : la fraîcheur avance à **chaque** scellement, même à contenu constant. Et le corps **identique**
    montre qu'il n'est **pas** re-chiffré sur un 0x07 (ciphertext stocké tel quel ; seule la tête 16 o est recalculée).
  - **Pas de compteur en clair** = cohérent avec un **compteur scellé interne** ([[voie-c-xart-fraicheur]]) : s'il existe, il est
    sous le MAC/chiffrement, invisible en clair. Renforce HV1(B)/HV2 : rejouer un **vieux** B figé serait rejeté car sa tête 16 o
    est liée à l'état de fraîcheur interne, qui a avancé.
  - RÉSERVE : on ne connaît ni la clé ni l'algo ; « enveloppe = nonce/MAC » est une **déduction de structure**, pas une preuve.
    On a montré « 16 o de tête changent à contenu égal », pas « c'est un GMAC » ni « c'est un IV ». Seul un essai en écriture (Albert) tranche.
- Incidents : aucun (hors ligne).

## 2026-11-12 (soir, 21:53) — Claude (Opus 4.8) + Albert — ESSAI B v3.1 : en acquittant le 0x07, la puce annonce `sks` (0x12) pour la 1re fois
- Trace : `traces/20261112-215313_xart_replay` (+ 13 blobs B dumpés dans `follow_B/`). Albert a lancé après
  reboot + **changement de port USB** (Bus 008→001) : plusieurs gels de lien avant (voir Incidents).
- Fait : `FOLLOW=1` (v3.1, lanceur `pending/follow_go.sh`). Correctif v3.1 en action : 0x07 désormais acquitté.
- Vu (FAITS) : boot SEP OK, tampons OK. Après les 4 lockers maîtres, la puce a enchaîné **13 ops acquittées** :
  9 SAVE (0x01/0x06, TAG 0x05→0x0d, blobs B 125→613 o) **puis un 0x07 (locker-absent, TAG=0x0e) — acquitté
  cette fois** — **puis 3 SAVE de plus** (TAG 0x0f/0x10/0x11, B 322→418 o), puis **timeout** (la puce n'a plus
  rien demandé). **Endpoints finaux : incluent `0x12 sks`** (ABSENT au run 21:28 ; sbio/scrd/sse/skdl aussi présents).
  (La ligne auto « sks ABSENT » du script était un FAUX NÉGATIF : le nom d'endpoint = `"\x00sks"` (octet nul de tête)
  → le test par chaîne ratait. La LISTE des endpoints, elle, montre bien 0x12. Corrigé : test par numéro d'EP.)
- Interprété (HYPOTHÈSE) : acquitter le 0x07 (correctif v3.1) a laissé la puce **avancer** jusqu'à annoncer le
  trousseau `sks` (0x12) — 1re apparition sous m1n1. L'annonce de sks semble **conditionnée à la progression xART**
  (au run précédent, arrêt au 0x07 → pas de sks). RÉSERVES : (1) « annoncé ≠ fonctionnel » (même réserve que sbio) —
  ce n'est PAS « Touch ID marche » ; (2) **n=1** ; (3) la puce n'a PAS suivi la séquence FETCH de macOS : elle a fait
  sa propre chaîne de 13 re-scellements puis s'est tue → état atteint par re-scellement, pas par restauration des
  gigalockers ; (4) les 13 SAVE = **vraies écritures SEP** (état scellé avancé), aucune persistance disque.
- Fait (suite) : bug d'affichage sks/sbio corrigé dans `pending/sep_xart_replay.sh` (test par numéro d'EP). Revalidé
  (bash -n + py_compile). Dumps B à analyser (que re-scelle la puce ? croissance 125→613 o).
- Incidents : plusieurs `UartTimeout` (gel du proxy m1n1 PENDANT le boot SEP, point variable = flakiness de lien,
  pas le script) ; power-cycles + **changement de port USB** (Bus 008→001) pour obtenir un run propre. Aucun côté disque.
- RAPPEL m1n1 : en vérifiant un détail j'ai rouvert `m1n1/.../sep.py` → avis mainteneurs « pas d'IA sur m1n1 » (journal
  session 1). Lecture du code m1n1 stoppée ; info tirée de la sortie + nos docs. Contrainte = ne rien contribuer à Asahi (respecté).

## 2026-11-12 (soir, ~21:30) — Claude (Opus 4.8) + Albert — ESSAI B (FOLLOW) LANCÉ : 9 re-scellements puis op 0x07 ; sks absent mais arrêt prématuré
- Trace : `traces/20261112-212820_xart_replay` (run réussi ; Albert a lancé). Deux runs avortés avant :
  `…211716` (UartTimeout au DÉBUT du rejeu, 0 écrit) et `…212238` (chainload NOP timeout, m1n1 coincé) →
  power-cycle. Flakiness de lien connue (~1 bon chainload par power-cycle).
- Fait : Albert a lancé `FOLLOW=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel`. Nouveau
  mode FOLLOW : à la divergence, acquitte les SAVE au lieu de s'arrêter. (Écriture SEP, lancée par Albert.)
- Vu (FAITS) : boot SEP OK ; endpoints de base annoncés (cntl/hdcp/xars/xarm/hibe/pnon/stac) ; SECMODE +
  tampons A/B OK. Rejeu des 4 lockers maîtres OK, puis divergence (comme essai 1, n≥3). **Le SEP a alors
  enchaîné 9 SAVE** (TAG 0x05→0x0d, alternance TYPE 0x01 xART / 0x06 locker ; blobs B croissants :
  nz 126→127→225→321→611), tous acquittés. **Puis TAG=0x0e TYPE=0x07** (op « locker-absent », PARAM=0x10
  DATA=0) — le script v3 ne gérait QUE 0x01/0x06 → **arrêt sur ce 0x07**. Ensuite silence (0 msg 0x13 en 30 s).
  Endpoints finaux : cntl, **sbio(0x08)**, scrd, sse, hdcp, xars, xarm, hibe, pnon, skdl, stac. **sks (0x12) ABSENT.**
- Interprété (HYPOTHÈSE) : (1) sbio annoncé mais sks absent = comme essai 1. (2) **Le « sks absent » n'est PAS
  concluant** : la capture macOS snew-reel montre qu'un op 0x07 (TAG=0x0b) est acquitté par macOS (> TYPE=0x00
  PARAM=0x00 DATA=0) et le boot continue. Le script s'est donc arrêté UN CRAN TROP TÔT. (3) Les 9 SAVE acquittés
  SONT de vraies écritures SEP (état scellé interne avancé) ; aucune persistance disque (l'AP n'a pas réécrit le
  gigalocker) → le SEP « croit » avoir sauvé. Côté Apple déjà cassé ; Linux/données intacts.
- Fait (suite) : corrigé en **v3.1** — 0x07 ajouté à ACKABLE (on le suit comme macOS), arrêt seulement sur un
  FETCH-locker (0x05) non servi ou op inconnue ; dump des blobs B re-scellés dans `OUT/follow_B/`. Lanceur court
  `pending/follow_go.sh` (pour lancer depuis le tél en RC). SELFTEST + py_compile OK. NON relancé (choix d'Albert).
- Incidents : 2 gels de lien (UartTimeout), power-cycles par Albert. Aucun côté disque.

## 2026-11-12 (soir) — Claude (Opus 4.8) — Mac rebranché (USB local) ; script ESSAI B (FOLLOW) écrit, prêt pour Albert
- Trace : — (aucune action hardware ; le script n'est PAS lancé. Travail hors ligne + lecture capture.)
- Fait : (1) Vérifié le lien : Mac en **USB local direct** (ttyACM0/1, m1n1 uartproxy v2.0.0-92-g7075,
  `WHFWP7FYXF`, énuméré 20:59), pas de tunnel. Pas de `sep_peek` lancé (le chainload peut se coincer, cf.
  incident 2026-11-11 23:56 ; device clairement vivant, on garde le proxy propre pour le run d'Albert).
  (2) Lu la séquence EP 0x13 de `traces/20261111-113919_snew-reel` : identifié le protocole d'**acquittement
  d'un SAVE** piloté par le SEP (tags 0x13/0x14/0x15) → `> TYPE=0x00 PARAM=0x00 DATA=(DATA_reçu & 0xffffff00)`.
  (3) Ajouté le **mode FOLLOW** à `pending/sep_xart_replay.sh` (v3) : à la divergence, acquitte les SAVE
  (0x01/0x06) au lieu de s'arrêter, ré-attend, puis écoute ~30 s en continuant d'acquitter, pour voir si
  `sks` (0x12) finit par être annoncé. N'injecte PAS de locker sur un FETCH post-divergence (observation).
  Budget SAVE borné à 16 (anti-boucle). Boot/CNTL/DART/rejeu inchangés (déjà validés octet pour octet).
- Vu : SELFTEST OK (séquence relue, ACK SAVE = 0x89290100/0x551e0100/0xcad30100, identiques à la capture) ;
  `bash -n` OK ; bloc Python `py_compile` OK.
- Interprété : FOLLOW est l'ESSAI observationnel du handoff 2026-11-12. C'est une **écriture SEP** (acquitter
  un SAVE fait avancer le re-scellement xART) → lancée par **Albert** seulement. Côté Apple déjà cassé
  (bootloop) : l'enjeu « casser le boot Apple » est caduc ; Linux + données = aucun risque.
- Décision/limite : rien envoyé au Mac. En attente d'Albert : (a) image disque oui/non (confort, pas un vrai
  filet) ; (b) lancer `FOLLOW=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel`.
- Incidents : aucun.

## 2026-11-12 ~08:40 — Claude (Opus 4.8) + Albert — Récupération ALARM après gel PMU ; handoff
- Trace : — (opérations matérielles de récupération, aucune capture SEP)
- Fait : relance du tethered boot ALARM. 1er essai (`linux.py`) planté au `PMU.reset_panic_counter` →
  `UartTimeout` SPMI. Rechargé un m1n1 frais (`CHAIN=1`) : **même plantage au PMU**. Albert a fait une
  **coupure complète du courant** du Mac. Au redémarrage, m1n1 « running proxy » à l'écran mais **aucun
  périphérique USB côté PC** (ni ttyACM ni lsusb). Après **changement de câble/port USB-C**, le proxy est
  revenu (`serial/by-id …WHFWP7FYXF`). Relancé `tools/tethered_boot.sh alarm` → PMU OK, noyau chargé (35 Mo),
  « Preparing to boot kernel ». Albert confirme : « j'ai le mac » (ALARM repris).
- Vu : le gel PMU/SPMI survit à un m1n1 frais ; seule la coupure d'alim le lève. Le proxy USB ne réénumère
  pas tout seul après coupure → câble/port à reprendre. `linux.py` en tâche de fond finit par
  `termios.error: Inappropriate ioctl for device` (ttymode sans terminal) = bénin, noyau déjà parti.
- Interprété : les manips SEP du jour (sep_peek / voie C) laissent le bus PMU dans un état qui ne se
  réinitialise qu'à froid. (hypothèse)
- Incidents : 2 × UartTimeout PMU ; 1 power-cycle physique ; ré-énumération USB manuelle. Aucun SEP write.
- Suite : handoff mis à jour (docs/handoff.md, section 2026-11-12). Prochain pas SEP = essai observationnel
  (relais du **dernier SAVE**, suit le SEP) — script `pending/` à écrire, lancé par Albert. En attente :
  décision image disque + moment. Mémoire [[mac-boot-casse-recuperation]] complétée (piège PMU + USB).

## 2026-11-12 — analyste — xART : la fraîcheur du FETCH est variable par boot (4 boots, lecture seule)
- Trace : `traces/20261111-010323_c21-xart-ool`, `…011447_c23…`, `…013303_c24…`, `…113919_snew-reel` (OOL EP 0x13 0x8000).
  `c22` (`…010943`) inexploitable (0 fichier OOL, boot avorté). Aucun hardware, aucune écriture SEP.
- Fait : apparié les tampons OOL 0x13 par rôle (TAG/TYPE/PARAM) sur les 4 boots, SHA-256 + byte-diff
  (`analysis/diff_xart_ool.py` + scratchpad `xart5.py`/`bmap.py`/`bdiff.py`).
- Vu : (1) UUID d'OS (tampon A `000092`, 16 o) = `EFF3C698-A740-4F41-AB86-99C85C0EB880` CONSTANT 4/4 (= apfs-preboot-uuid).
  (2) Coffre FETCH = 10 blobs : 8 CONSTANTS octet pour octet, 2 VARIABLES à chaque boot = **SEP-xART maître** (`000094`, fetché
  AVANT sbio ; ~846/867 o changent ; 17 premiers octets = 0, pas de nonce en clair) et **locker Credential Manager** (`000222`).
  **USER-xART** (`000096`) STABLE 4/4. (3) Les 16 o des `< TYPE=0x05` (B) = UUID d'adressage CONSTANTS, pas des nonces ; les SAVE
  (B, ~849 o) 100 % variables. (4) Chaînage octet pour octet : dernier SAVE SEP-xART c21 = FETCH SEP-xART c23 → `fetch(N)=save(N-1)`.
  (5) pnon 0x15 non tracé ; le `nonce-seeds 0x203` du hv_uart est une écriture NVRAM macOS, pas une valeur du FETCH 0x13.
- Interprété (→ hypotheses.md) : la fraîcheur validée avant l'acceptation (sbio) est portée par des octets **variables par boot**
  (SEP-xART maître), pas constants → rejeu statique impossible ; mais ce blob = le dernier SAVE du boot d'avant → voie C = relais du
  dernier SAVE. Indécidable en lecture si l'état scellé interne a un compteur/graine en plus de la clé → seul un essai écriture tranche.
  Renforce HV1(B)/HV2 (re-scellement observé = attendu d'un rejeu sans le bon contexte de fraîcheur). Statut `hypothèse` (pas d'écrit).
- Incidents : aucun.

## 2026-11-12 — Claude (Opus 4.8) — Phase 2 : d'où vient la fraîcheur xART (nonce) → le re-scellement de la voie C est l'attendu
- Trace : — (analyse pure `macos/kernel.macho`, aucun hardware ; 2 sous-agents lancés en //: documentaliste=sources publiques nonce,
  analyste=nonce constant/variable dans les traces de boot).
- Fait : désassemblé la chaîne nonce du kext AppleSEPManager : `nonce_generate/read/invalidate` → `_nonce_action` →
  `_runOperation` → **`AppleSEPXART::_xmsgSend`** (le nonce passe par l'EP xART 0x13) ; `AppleSEPUserClient::getOrGenerateNonce`
  (logs « Current/New SEP Nonce ») ; **`AppleSEPBooter::generateROMNonce`** (opcode `BootOpcode::ReportNonceWord`, nonce produit
  par la ROM du SEP), appelé seulement via user-client `DispatchUserClientGenerateROMNonce`. Et `_determineOsUuidGated` (op 0x13)
  lit `/chosen` → `apfs-preboot-uuid`. Consigné `kext_sepmanager.md` §9.
- Vu (FAITS kext) : l'état xART est ancré à (1) l'UUID d'OS = apfs-preboot-uuid (CONSTANT par install → rejouable) et (2) un
  **nonce produit par le SEP** (xART et/ou ROM), l'AP ne choisit pas sa valeur.
- Interprété (HYPOTHÈSE, source: kext) : comme la fraîcheur vient d'un nonce SEP (pas d'une valeur AP), un rejeu de lockers scellés
  à un autre boot est lié à un **ancien** nonce → au boot m1n1, le SEP charge les 2 blobs maîtres + l'UUID puis **re-scelle (op 0x01)**
  au lieu d'aller aux gigalockers (op 0x05). = EXACTEMENT la bifurcation de l'essai voie C. Donc le re-scellement est le comportement
  **attendu**. SEULE porte de sortie possible, non tranchée par le kext : le nonce de boot est-il dérivé d'une **graine réglable**
  (NVRAM « boot nonce ») — rejeu possible — ou interne/aléatoire par boot — rejeu impossible ? → sous-agent documentaliste.
- Décision/limite : rien envoyé au Mac. Aucune relance voie C. L'étape qui écrirait reste Albert + image disque d'abord.
- Incidents : aucun.

## 2026-11-12 — documentaliste — xART anti-rejeu / nonce : ce que le PUBLIC établit (réponse à la question ouverte ci-dessus)
- Trace : — (sources publiques seules : doc Asahi sep/ + platform/security/, clone m1n1, rappel linux-asahi).
- Vu (FAITS publics) : (1) Asahi affirme la finalité anti-rejeu — « The xART prevents replay attacks from capturing the VEK »
  (platform/security/) — mais **ne décrit aucun mécanisme** (ni compteur monotone, ni nonce, ni ancre de fraîcheur). (2) EP 0x10
  `xars`, 0x13 `xart manager` (gigalockers/keybags, needed for SKS), 0x15 `pnon` = « boot policy related / Machine owner credentials
  handoff » — `pnon` n'est **pas** décrit comme un nonce anti-rejeu. (3) m1n1 lit déjà le gigalocker du disque :
  `rust_read_gigalocker` / `get_gigalocker` (commit 07c2c3af, S. Finkelstein, 2026-07-16 ; volume APFS rôle xART 0x100) → le
  **stockage AP est trivialement rejouable**. (4) `nonce` dans m1n1 ne concerne que l'aléa de boot Linux (rng-seed), jamais xART.
  Aucune notion ap-nonce/sep-nonce/BootNonce liée à la fraîcheur xART dans le public.
- Interprété : le public donne l'**intention** (anti-rejeu) + prouve que le blob AP est rejouable, mais **ne tranche pas** entre
  « nonce régénéré par boot » (rejeu du dernier état impossible) et « simple monotonie de version » (dernier état toujours acceptable).
  → Conclusion publique = **(c) indéterminé**. La question ne se tranche que par l'expérience (voie B : chercher un nonce/compteur par
  boot dans l'échange 0x13), pas par la doc. Complète, sans contredire, l'hypothèse kext ci-dessus (nonce SEP) : le kext suggère
  « nonce SEP », mais aucune source PUBLIQUE ne le confirme ni ne dit s'il est réglable.
- Détail et citations : docs/public_linux_state.md, section « 2026-11-12 — xART anti-rejeu / nonce (sources publiques) ».
- Incidents : aucun (aucune action hardware).

## 2026-11-11 (23:56) — Claude (Opus 4.8) — Mac revenu en USB local ; sep_peek tenté, m1n1 coincé au chainload
- Trace : traces/20261111-235625_etat_retour (chainload.log ; pas de lecture MMIO — échec avant).
- Fait : lien proxy de retour en **USB local** (ttyACM0/1, m1n1 v2.0.0-92-g7075). Lancé `tools/sep_peek.sh` (lecture seule).
- Vu : le chainload du m1n1 frais va jusqu'à « Preparing to run next stage », puis **reconnexion USB timeout** ; ensuite
  **plus aucun /dev/serial/by-id** (vérifié 5×). Le nouveau m1n1 ne réénumère pas → m1n1 **coincé**.
- Interprété : flakiness connue du chainload (cf. récup ALARM). Aucune donnée touchée, aucune écriture SEP (échec avant toute
  lecture MMIO). Récup = **power-cycle physique** du Mac par Albert (présent) pour relancer m1n1 en mode proxy.
- Incidents : m1n1 coincé après chainload ; pas insisté (règle « Mac ne répond plus → ne pas insister »).

## 2026-11-11 — Claude (Opus 4.8) — Phase 2 : désassemblage du dispatch xART (EP 0x13) — pourquoi le SEP a demandé SAVE à TAG=0x05
- Trace : — (aucun hardware ; lien proxy hors ligne depuis le PC — ni USB ni tunnel. Analyse pure sur `macos/kernel.macho`.)
- Fait : désassemblé `AppleSEPXART::_handle_sep_driven_msg` (vm 0xfffffe0009986588, kext AppleSEPManager) avec
  `analysis/kext/kdis.py` (capstone, venv scratchpad ; listing non commité). Décodé la table de saut des opérations xART.
  Résultat consigné en `docs/kext_sepmanager.md` §8 (source: kext).
- Vu (FAITS kext, certains) : l'octet 2 du message = l'opération. **op 0x00 = FETCH xART maître** (« Fetched %s-xART with CRC »),
  **op 0x01 = SAVE xART maître** (« Saving %s-xART with CRC »), **op 0x05 = FETCH gigalocker par UUID** (16 o d'UUID dans le
  tampon B → locker rendu dans A), op 0x06 = save/fetch gigalocker, op 0x07 = locker supprimé/introuvable, op 0x0e = état
  fw-boot (sepfw-loaded…), **op 0x13 = `_determineOsUuidGated` (rend 16 o d'UUID d'OS)**. Tampons : `this+0xc8` = A (AP→SEP),
  `this+0xd0` = B (SEP→AP) — concorde avec la convention de trace. La classe expose un sous-système de nonce/graines de session
  (`nonce_generate/read/invalidate`, `commit_hash`, `erase_session_seeds_for_UUID`, `setup_OS_UUID`).
- Interprété (HYPOTHÈSE) : l'essai voie C n°1 a rejoué TAG 0x02=op0x0e (fw), 0x01=op0x13 (UUID), 0x03=op0x00 (SEP-xART),
  0x04=op0x00 (USER-xART) — donc **2 blobs maîtres + UUID + drapeau fw**, pas « 4 gigalockers ». Là où macOS fait ensuite des
  **op 0x05 (FETCH gigalocker)**, le SEP sous m1n1 a émis **op 0x01 (SAVE xART maître)** : il veut **ré-écrire** son xART, pas
  restaurer la suite. Cela renforce l'hypothèse B de HV1 (état jugé non valide/courant → re-scellement), et un SAVE acquitté
  ferait a priori avancer le compteur scellé → cohérent avec la casse du boot Apple après l'essai. Reste `hypothèse` (le *pourquoi*
  interne est dans SEPOS, pas dans ce kext).
- Décision/limite : **ne relance PAS la voie C.** L'étape hardware suivante (Essai A, rejeu observationnel) est une **écriture SEP**
  → interdite à l'agent, et bloquée par la règle « pas de réécriture SEP sans image disque d'abord » (voie C a cassé le boot
  Apple, 2026-11-11 nuit). Rien envoyé au Mac dans cette session.
- Incidents : aucun (aucune action hardware).

## 2026-11-11 (nuit) — Albert + Claude (Opus 4.8) — RÉCUPÉRATION : ALARM bootable par tethered boot (Mac usable malgré le côté Apple cassé)
- Trace : — (aucune capture SEP ; récupération système).
- Fait :
  - **ALARM récupéré par tethered boot** depuis le PC, non destructif. Outil créé : `tools/tethered_boot.sh`
    (mode `shell` = s'arrête dans l'initramfs en lecture seule ; mode `alarm` = boot complet, auto-unlock
    LUKS via clé embarquée, monte `@`, lance sshd, notch).
  - Noyau + initramfs + DTB extraits du backup **restic** `/latif/data/backup/m1max` (dépôt local ;
    mdp vaultwarden « restic m1max », mis par Albert dans `~/.rp` pour l'autonomie) :
    `restic restore latest --include /boot` → `~/alarm-recovery/boot/`.
  - Nettoyé `docs/RECUPERATION_MAC.md` (retrait des formulations « à répéter à Albert pour le rassurer »,
    « à dire à Albert », etc. — demande d'Albert).
- Vu (FAITS, obstacles franchis dans l'ordre) :
  1. Noyau `vmlinuz-linux-asahi` = Image ARM64 **brute** → `linux.py --compression none` (sinon ValueError).
  2. m1n1 `kboot_prepare_dt` échoue « failed to add node 'smbios' » : le DTB contenait **déjà** un nœud
     `smbios` (+ DTB compacté, 0 octet libre). Fix côté nous : « open_into » maison (+16 Ko d'espace) et
     neutralisation du nœud `smbios` existant (NOP).
  3. Puis « DT CPU MPIDR mismatch / CPU 0 not alive » : le DTB `dtbs-pmp/t6001-j314c-pmp.dtb` (vieux projet
     d'Albert) a les CPU **dans le désordre** (`cpu@0` pas en premier). Mauvais DTB.
  4. Le DTB `asahi-boot` (73 Ko) passe le boot mais ALARM est **dégradé** : pas de clavier interne / trackpad,
     wifi KO, écran/notch faux. Cause : ce DTB **manque les nœuds** hid(clavier/trackpad)=0 et dcp(écran)=2.
  5. **Le bon DTB = le DTB complet du noyau** `/usr/lib/modules/<ver>/dtbs/t6001-j314c.dtb` (~101 Ko :
     hid=2, dcp=25). Préparé en `~/alarm-recovery/boot/t6001-j314c-full.dtb` (open_into +16 Ko). Avec lui :
     ALARM complet — clavier interne + trackpad OK, écran 3024x1964 @1.33x 120 Hz, Hyprland, réseau via **wg10**
     (10.0.200.3, le tunnel du projet ; pas de wifi en tethered). Bootarg `appledrm.show_notch=1` ajouté.
  - Chainload de m1n1 **redondant** (le m1n1 installé = même version que notre build) → `CHAIN=1` optionnel.
  - Après chaque boot du noyau, le proxy USB m1n1 **disparaît** (plus de console vers le PC pendant qu'ALARM
    tourne) → il faut un **power-cycle physique** du Mac pour relancer un boot.
- Interprété : macOS/recovery/**Startup Options** restent cassés (état scellé SEP bousculé par la voie C ;
  Revive n'y change rien). Réparer le côté Apple = **DFU Restore** destructif (2e Mac) → `RESTORE.md` du backup.
  Reporté : on reste en tethered le temps du SEP (ça garde m1n1 en proxy, nécessaire pour tracer macOS sous hv).
- Décision : (a) ALARM se lance via `tools/tethered_boot.sh alarm` quand on en a besoin ; (b) **aucune
  réécriture SEP** sans faire l'**image disque** d'abord (la voie C a cassé le boot) ; (c) répa Apple = plus tard.
  m1n1 interdit l'IA côté projet (`m1n1/CLAUDE.md`) : usage privé local d'Albert = OK, on ne modifie pas leur
  code et rien ne sort vers Asahi.
- Incidents : plusieurs boots échoués avant le bon DTB (compression, smbios en double, ordre CPU, flakiness smp
  due aux chainloads empilés). Aucune perte de données, non destructif (noyau en RAM). m1n1 recollé par
  power-cycle à chaque fois. Mémoire `mac-boot-casse-recuperation` mise à jour.

## 2026-11-11 (soir) — Albert + Claude (Opus 4.8) — INCIDENT : le Mac ne démarre plus (menu Apple cassé) après voie C
- Fait : après l'essai voie C reproduit (rejeu xART au SEP), le Mac ne charge plus le menu de démarrage ni la récupération 1TR (bootloop) ; macOS boucle ; seul m1n1 démarre (« Running proxy… »). DFU Revive fait (firmware rafraîchi) → n'a PAS réparé (Revive ne reset pas l'état scellé du SEP). Double-appui maintenu + maintien 15 s (1TR) testés : rien.
- Interprété : les écritures SEP de la voie C ont bousculé l'état scellé de la puce → le boot sécurisé Apple (menu/1TR/macOS) échoue ; seul le boot permissif m1n1 passe. Le risque « brick faible mais non nul / macOS perturbé » de l'en-tête du script s'est matérialisé, et a débordé sur le menu (donc sur l'accès à ALARM).
- SÛR : ALARM (Linux quotidien) + données = intactes (aucune écriture disque jamais faite) ; backup Linux OK ; Mac non brické. Albert avait mis m1n1 en défaut volontairement.
- Décision : STOP voie C. Récupération = tethered boot (non destructif, sans 2e Mac) ou, en dernier recours, DFU Restore + réinstall depuis backup. Procédure complète : docs/RECUPERATION_MAC.md ; bandeau en tête de handoff.md ; mémoire mac-boot-casse-recuperation. Albert fera la récupération en session fraîche.

## 2026-11-11 (fin journée) — Albert lance / Claude (Opus 4.8) — essai 1 REPRODUIT (n=2) ; m1n1 coincé ; observation pas encore capturée
- Trace : traces/20261111-124327_… (échec chainload), 20261111-12xx (run 2 OK, même sortie que l'essai 1), 20261111-125023/125142 (chainload desync/0 octet).
- Fait : après rallumage des 2 Macs, lien proxy désynchronisé → relancé tunnel.py (2×, via Albert qui approuve le kill ; script tools/restart_tunnel.sh ajouté). Sur lien propre, 1 run complet = REPRODUCTION exacte de l'essai 1.
- Vu (FAIT, n=2 maintenant) : 4 lockers rejoués (090/092/094/096), sbio/scrd/sse/skdl annoncés, DIVERGENCE à TAG=0x05 TYPE=0x01 (= SAVE, vs TYPE=0x05=FETCH macOS). Identique à l'essai 1 → le point de bifurcation est reproductible. Message du script corrigé (« 4 lockers rejoués puis divergence », plus « tampons seuls »).
- Incident : le lien redécroche après CHAQUE run (octets périmés → chainload suivant desync ; puis m1n1 « 0 octet » = coincé). Récup partielle = relancer tunnel.py ; mais un m1n1 coincé = reboot PHYSIQUE (Mac distant chez Erdem, impossible sur le moment). Albert part en cours.
- Observation (essai A) PAS encore obtenue : la lecture de B à la divergence n'a pas pu tourner (Albert relançait la commande sans OBSERVE puis le lien a lâché). OBSERVE est désormais le DÉFAUT du script → le prochain run sain capturera B automatiquement.
- Statut : point de divergence = reproductible (vérifié n=2). Contenu de B à la divergence (SAVE ~849 o ?) = à capturer au prochain run sain. NE PAS conclure « voie C gagnée ».
- À reprendre (session future, hardware sain) : relancer tunnel.py si besoin, 1 run (OBSERVE par défaut) sur traces/20261111-113919_snew-reel si macOS pas rebooté (sinon recapturer S_new), lire B à la divergence.

## 2026-11-11 (fin journée) — Claude (Opus 4.8) — hardware hors ligne ; essai A (OBSERVE) prêt et en attente
- Fait : préparé l'essai A observationnel dans pending/sep_xart_replay.sh (OBSERVE=1 : rejoue puis écoute B en lecture seule sans répondre sur 0x13, n'acquitte pas le SAVE). SELFTEST + compile Python OK. Commité.
- Incident : après reboot_mac.sh, proxy en UartTimeout. Cause confirmée par Albert : le MacBook ET le Mac relais d'Erdem (10.0.200.5) sont ÉTEINTS — plus de lien. (Restart tunnel.py inutile ; de toute façon le kill est bloqué par le mode auto.) Conforme à CLAUDE.md : ne pas insister, passer aux tâches hors hardware.
- En attente : quand les Macs reviennent, relancer tunnel.py si besoin, puis Albert lance la commande OBSERVE sur traces/20261111-113919_snew-reel (toujours valide tant que macOS n'a pas rebooté ; sinon recapturer un S_new). Reproductibilité : 3 runs OBSERVE, reboot m1n1 entre chaque, sans boot macOS.

## 2026-11-11 (fin journée) — Albert lance / Claude (Opus 4.8) — ESSAI VOIE C n°1 : sbio RÉVEILLÉ, mais le rejeu a DIVERGÉ (sbio ≠ rejeu accepté)
- Trace : traces/20261111-120142_xart_replay/ (xart_replay.log, chainload.log) — PREMIÈRE écriture SEP du projet, lancée par Albert.
- Fait : pending/sep_xart_replay.sh sur le S_new traces/20261111-113919_snew-reel. m1n1 démarre le SEP, met en place les tampons xART (A iova=0x2c000, B iova=0x38000, sid=0) via CNTL (SECMODE + 4 CNTL acquittés), puis tente le rejeu de l'échange EP 0x13.
- Vu (FAITS — corrigé après relecture de la trace ; voir CORRECTION ci-dessous) :
  - BOOT OK ; au démarrage, 7 endpoints seuls (cntl hdcp xars xarm hibe pnon stac) — comme sep_boot.sh.
  - Les requêtes xART du SEP sont numérotées en série (macOS : TAG 0x02→0x01→0x03→0x04→0x05→0x06…). La divergence de l'essai 1 porte sur « attendu TAG=0x05 » : les 4 premières transactions (TAG 0x02/0x01/0x03/0x04) sont donc PASSÉES → **4 lockers RÉELLEMENT rejoués** (tampons A 090/092/094/096, dont 094=SEP-xART et 096=USER-xART, les 2 « frais »). Puis à la 5e requête le SEP envoie TAG=0x05 **TYPE=0x01** au lieu du TYPE=0x05 de macOS ; le script (rejeu rigide de la trace macOS) s'arrête là.
  - `TAG=0x05 TYPE=0x01` n'existe NULLE PART dans la capture macOS (vérifié par grep du sep.log). TYPE=0x01 est un type de requête xART valide (macOS l'émet mais seulement à TAG=0x13). Donc le SEP sous m1n1 a sauté les transactions 5→18 de macOS et demandé directement une opération TYPE=0x01 : vrai chemin différent, pas un décalage de file.
  - Pendant l'échange, entre TAG=0x04 et TAG=0x05 (comme sous macOS), le SEP annonce ses endpoints (TYPE=0x1d) : 11 au total dont **0x08 sbio (biométrie)**, 0x0a scrd, 0x0c sse, 0x17 skdl. Toujours ABSENT : sks (0x12, trousseau).
- CORRECTION d'une erreur de lecture (le même jour) : j'avais d'abord écrit « 0 locker rejoué / sbio apparaît sans rejeu ». FAUX. La divergence à TAG=0x05 prouve que 4 transactions ont abouti avant. sbio apparaît DANS un échange xART partiel (au point normal, après 4 lockers), pas à partir des seuls tampons.
- Interprété (HYPOTHÈSE) :
  - Le SEP sous m1n1 a ENGAGÉ l'échange xART, repris 4 lockers (dont les 2 frais) sans les rejeter, et annoncé la biométrie — puis a divergé à la 5e requête. Encourageant : l'échange démarre. MAIS « sbio annoncé » reste ≠ « Touch ID fonctionne » (sks absent ; annonce des endpoints = étape normale, ne prouve pas la validation des lockers).
  - Pourquoi TYPE=0x01 à TAG=0x05 (vs la longue suite de TYPE=0x05 de macOS) : inconnu. Piste : le SEP sous Linux n'a pas les mêmes lockers à réclamer, ou l'un des 4 premiers lui a fait changer de branche. À creuser : rendre le rejeu ADAPTATIF (répondre à ce que le SEP demande vraiment, pas rejouer la trace macOS à l'identique) ; désassemblage xarm = piste phase 2.
  - Le message « rejeu accepté » du script était trompeur (il ne testait que la présence de sbio). CORRIGÉ dans le script : il distingue rejeu complet vs divergé et compte les réponses rejouées.
- Incidents : aucun. Aucune op disque. SEP laissé en état booté-avec-endpoints ; Mac redémarré en m1n1 après coup (reboot matériel, n'avance pas le compteur). macOS non rebooté.
- Statut : FAITS = vérifiés (log). Cause de la divergence TYPE=0x01 = ouvert. NE PAS conclure « voie C gagnée ». À trancher : rejeu adaptatif (pending/, Albert lance) + contrôles de reproductibilité.

## 2026-11-11 (fin journée) — Claude (Opus 4.8) — S_new réel capturé (tampons complets 0x8000), script voie C prêt à lancer
- Trace : traces/20261111-113919_snew-reel (lecture seule, EP 0x13, SEP_OOL_BYTES=0x8000, END_ACTION=reboot).
- Fait : capturé un vrai S_new via boot_and_trace (M1N1TIMEOUT=20). Boot macOS OK sur tunnel, reboot auto en m1n1 à la fin.
- Vu : 14 tampons A rendus au SEP, TOUS à 32768 octets (0x8000) — la troncature 0x400 de cntl-study3 est corrigée. 15 tampons B. SELFTEST du script sur cette capture : OK (60 étapes EP 0x13, 30 réponses AP, 14 écritures A, séquence xART complète, annonces endpoints sbio/sks/sse/scrd rejouées côté AP). sep_peek après reboot : SEP à l'arrêt (CPU_CONTROL RUN=0), mailbox lisible = m1n1 propre.
- Interprété : S_new valide et frais pour l'essai voie C. Rien envoyé au SEP (tout lecture seule + selftest hors-ligne).
- Suite : Albert lance pending/sep_xart_replay.sh sur ce dossier (écriture SEP ; agent n'exécute pas). Ne PAS booter macOS avant.

## 2026-11-11 (fin journée) — Claude (Opus 4.8) — voie C : v2 relue OK (sceptique), M1N1TIMEOUT trouvé, S_new à refaire
- Fait : trouvé que run_guest échouait faute de M1N1TIMEOUT (défaut 3 s) → export M1N1TIMEOUT=20 → boot macOS OK sur tunnel. Capture cntl-study3 (non filtrée) VALIDE le protocole CNTL octet pour octet (SECMODE 0x14, tampons 0x04/0x02/0x05/0x03 PARAM=0x13, IOVA 0x2c/0x38, ack TYPE 0x01 même tag). v2 du script écrite (rôle AP) et relue par sceptique = « lançable, sûre, 0 disque ».
- Vu / erreur : cntl-study3 capturé avec nbytes=0x400 → lockers .ool tronqués (1024 o au lieu de 32768) → INUTILISABLE comme S_new. Présenté à tort comme prêt (glissement de session longue). Procédure corrigée dans handoff.md : capturer S_new avec SEP_OOL_BYTES=0x8000.
- Incertitudes voie C (tranchées par l'essai) : stream DART lu par xarm ; tampons 0x18/0x0e ; enchaînement xART sous m1n1.

## 2026-11-11 (journée, autonome) — Claude (Opus 4.8) — Mac à distance via tunnel relais ; script de rejeu v1 + blocage trouvé par le sceptique
- Trace : nombreuses captures de test (premier_contact, chainN, clN, reset…, en lecture seule). Config d'accès : Mac non en USB local mais derrière un relais TCP `10.0.200.5` (ports 4000 proxy / 4001 console), via `tunnel.py` (voir mémoire tunnel-relais-mac).
- Fait :
  - Fiabilisé le lien distant : `tunnel.sh` socat nu recréait le PTY à chaque coupure → cassait la session proxy ; écrit `tunnel.py` (PTY stable + contre-pression) → **chainload 6/6**, PTY ne change plus, coupures (ré-énum USB) rattrapées. Côté relais : ajouter `fork` au socat (évite le trou de reconnexion). Ajout `SKIP_CHAINLOAD=1` à `boot_and_trace.sh`. Correctif `env.sh` (HV_UART `|| true` sous set -e sans appareil).
  - Écrit `pending/sep_xart_replay.sh` (v1) : rejeu fidèle de l'échange EP 0x13 d'une capture S_new (sep.log + .ool), apprentissage prévu des tampons, écriture DART+writemem. Validé hors-ligne (SELFTEST sur c24 : 60 étapes, 12 écritures tampon A, ordre correct).
  - Relecture critique (agent sceptique).
- Vu :
  - **BLOCAGE sceptique** : les IOVA des tampons OOL A/B de l'EP 0x13 sont annoncées **AP→SEP** (les lignes `# ool learn` du traceur ne sortent que pour `tx=True`), pas SEP→AP. C'est macOS qui ALLOUE A/B dans sa mémoire DART et les DONNE au SEP. La v1 attend donc des IOVA qui n'arriveront jamais → sortie propre « tampons non appris », **aucune écriture SEP** (sûr), mais ne teste rien. Correctif détaillé : docs/voie_c_design.md « Correctif voie C ».
  - **run_guest (boot macOS sous hyperviseur) PAS fiable à travers le tunnel** : échoue quasi systématiquement au bootstrap (UartTimeout / UartCMDError de désync), même avec `SKIP_CHAINLOAD`. Le succès d'un boot complet plus tôt dans la journée (macOS 13.5 affiché, batterie 80 %) était un coup de chance. chainload et lectures SEP, eux, passent bien (6/6).
- Interprété : voie C reste ouverte mais la v1 doit être refondue (ajouter le rôle AP : allouer + mapper + annoncer les tampons). Le TAG/amorçage exact des CNTL manque → à lever par une capture non filtrée **en USB direct**, ou par désassemblage d'AppleSEPManager (phase 2). Hypothèses, pas vérifié.
- Incidents : un `run_guest` avorté laisse le m1n1 en état mi-hyperviseur / proxy désynchronisé ; récupération = redémarrer `tunnel.py` (vide les octets périmés) puis chainload (remet m1n1 propre). Pas besoin de reboot physique.
- Décision Albert (2026-11-11) : je peux éditer le repo y compris `m1n1/` (rien ne sort = seule contrainte) ; macOS sacrifiable mais à ménager ; pleine autonomie pour tout sauf le lancement de l'écriture SEP.

## 2026-11-11 — Claude (Opus 4.8) + analyste — xART : 3 boots, les 2 lockers variables identifiés, chaînage prouvé octet pour octet
- Trace : traces/*c21-xart-ool [T-45], *c23-xart-ool [T-46], *c24-xart-ool [T-47] (lecture seule). Scripts : analysis/diff_xart_ool.py, scratchpad/diff3.py, scratchpad/lockers_variables.md (sous-agent analyste). Correspondance seq->fichier->TAG->nom noyau via le mot 64 bits des lignes « Replied to xART app ».
- Vu (faits mesurés, 3 boots) :
  - Buffers A (rendus au SEP) : 12 par boot ; sur le bloc de boot (seq 090..222), 10 lockers dont 8 identiques octet pour octet sur les 3 boots et 2 variables. Les 2 buffers A tardifs (TAG 0x16, 0x18) sont aussi stables.
  - Les 2 variables sont : 000094 = TAG 0x03 = **SEP-xART** (blob nommé, pas d'UUID, ~0x363 o utiles) ; 000222 = TAG 0x10 = **locker du Credential Manager** adressé par UUID 8624497a8c2ff2582625a036fab3b8e3 (~0x307c o utiles, contexte AppleCredentialManager/ACMTRM). **USER-xART (TAG 0x04, 000096) NE change PAS** (CRC 0xfcf1 constant).
  - UUID des lockers identiques sur les 3 boots (ex. USER_XART « not found » = d15bc8da...). Le locker 222 a le même UUID aux 3 boots : c'est le même locker dont le contenu change.
  - Pas de compteur en clair : 000094 corps 0x11..0x363 entièrement renouvelé chaque boot ; 000222 tête 0x00..0x152 entièrement renouvelée, le reste (0x153..0x307c) identique sur les 3 boots. Aucun octet monotone.
  - Buffers B (sauvés) : 5 par boot, 15/15 distincts. Structure d'un save SEP-xART : 16 octets variables à chaque save (aspect nonce/MAC) + corps chiffré constant au sein d'un boot.
  - **Chaînage octet pour octet** : corps de A094(c23)==B231(c21), A094(c24)==B231(c23) ; A222(c23)==B229(c21) (après 16 o d'UUID), A222(c24)==B229(c23). Ce que le SEP sauve au boot N = ce que l'AP rend au boot N+1.
- Interprété (hypothèse) : la fraîcheur anti-rejeu est portée par le préfixe de 16 octets des saves + le corps chiffré renouvelé ; pas de compteur lisible. Le rejeu reste plausible : rendre la dernière sauvegarde = exactement ce que le SEP attend au boot suivant (save N = fetch N+1, prouvé). Reste à savoir, par un test en écriture seul, si l'état interne du SEP accepte ce rejeu quand c'est Linux et non macOS qui boote le SEP. Statut : faits = vérifiés (octets) ; mécanisme anti-rejeu = hypothèse.
- Incidents : c22 (entre c21 et c23) n'a pas démarré macOS, 0 message, ignoré.

## 2026-11-11 — Claude (Opus 4.8) — Coffre xART comparé sur 2 boots (c21 vs c23) : 80 % stable, fraîcheur isolée à 2 blobs
- Trace : traces/*c21-xart-ool et traces/*c23-xart-ool (2 boots macOS sous HV, lecture seule ; c22 raté entre les deux, boot à chaud).
  Script : analysis/diff_xart_ool.py. Les deux boots vont jusqu'à l'écran de connexion, SANS login (pas de mot de passe tapé).
- Vu (faits) : le coffre rendu au SEP (buffers A, fetch) = 10 blobs ; **8/10 identiques octet pour octet** entre les 2 boots ; 2 diffèrent
  (un de ~848 o = 000094, un de ~3 Ko = 000222). Ce que le SEP fait sauver (buffers B) = 5 blobs, **5/5 différents** à chaque boot.
  Les 8 A stables font 2043/3072/3072/3073/3074/3075/8182/8183 o.
- Interprété : `vérifié` pour les comptes. Lecture : la grande partie du coffre est **statique** (l'AP la stocke et la rend telle quelle →
  rejouable trivialement, confirme « le SEP n'a pas de disque »). La **fraîcheur anti-rejeu** est isolée à 2 petits blobs rendus (hypothèse :
  SEP-xART + USER-xART) et à tout ce que le SEP sauve (régénéré chaque session). Donc le rejeu (voie C) n'est ni mort ni gagné : il faudrait
  rendre la **dernière** version sauvée de ces 2 blobs, et seul un test en écriture (pending/ + Albert) dira si le compteur scellé du SEP l'accepte.
  Le compteur est chiffré dans le blob, invisible en lecture. Contrainte : ces 2 blobs périment dès que macOS reboote (il réécrit).
- Incidents : c23 fini en `client_exited` (Albert a débranché l'USB pour récupérer son câble) ; échange xART déjà complet, sans conséquence.

## 2026-11-11 — Claude (Opus 4.8) — VOIE B faite : 1re capture du CONTENU du coffre xART (EP 0x13 OOL)
- Trace : traces/20261111-010323_c21-xart-ool (SEP_EPS=0x13 SEP_OOL_EPS=0x13 SEP_OOL_BYTES=0x8000, boot macOS sous HV, lecture seule, reboot propre).
  2e boot c22 raté (macOS non démarré, 0 message SEP = panne connue « chainload à chaud ») ; 3e tentative c23 en cours.
- Fait : capturé pour la 1re fois le contenu OOL de l'échange xART au boot (avant : en-têtes seuls). 25 blobs OOL 0x13, buffers de 0x8000.
- Vu (faits) : structure d'échange identique aux 19 boots (TAG 2/0x0e attente, fetch SEP-xART TAG3 PARAM 0x64, USER-xART TAG4, puis sbio
  annoncé). Buffers A ('>', AP->SEP = coffre rendu) = lockers chiffrés, 2 à 8 Ko non nuls, **haute entropie dès le 1er octet (pas d'en-tête
  en clair)**. Buffers B ('<', SEP->AP = à sauver) : certains n'ont que **16 octets non nuls = un UUID de locker** (l'un = d15bc8da…, le
  locker USER-xART connu « not found »). Deux lockers partagent un suffixe de ~24 octets identiques (000144/000164).
- Interprété : `vérifié` pour les faits ci-dessus. L'anti-rejeu n'est **pas** un champ en clair : il est cryptographique (dans le blob scellé),
  donc invisible en lecture. La question « rejeu jouable ? » ne se tranche pas en lisant un blob ; il faut comparer deux boots (c21 vs un 2e bon
  boot) ou, en dernier ressort, un test en écriture (voie C, pending/ + Albert). Les lockers sont adressés par UUID de 16 o (nouveau détail).
- Incidents : c22 raté (boot à chaud), sans conséquence (reboot propre). Un démarrage à froid (Albert, appui long) fiabiliserait le 2e boot.

## 2026-11-10 — Claude (Opus 4.8) — xART : distinction rejeu vs forge (voie C réhabilitée, avec Albert)
- Trace : — (mise à jour de doc, discussion avec Albert). Aucune action matérielle.
- Fait : corrigé docs/xart_options.md. Albert a fait remarquer que le SEP n'a pas de disque et compte sur l'AP pour lui rendre ses blobs :
  donc **rejouer** l'état réel (voie C) ≠ **forger** un état (voie D, impossible sans clé interne). La voie C ne demande pas de comprendre
  les blobs (ils restent chiffrés), seulement de les stocker/rendre comme macOS.
- Vu : — (analyse). Verdict corrigé : le Touch ID complet n'est pas « mort par conception » ; il est derrière une seule question — l'anti-rejeu
  accepte-t-il un rejeu fidèle de l'état courant, ou y a-t-il un compteur/nonce par boot ? La voie B (lecture seule) doit la trancher.
- Interprété : la voie C devient la seule piste crédible vers un Touch ID complet, mais reste une **écriture SEP** (pending/ + Albert), conditionnée
  à la voie B, et bornée par les deux règles d'Albert (pas de brick, pas toucher Linux ; macOS sacrifiable). Idée 1 d'Albert (sommeil profond,
  RAM en auto-refresh, réveil au lid) = vrai sommeil profond mais géré par le power management / AOP, pas le SEP (hedge : partage de rôles non certifié).
- Incidents : aucun.

## 2026-11-10 — Claude (Opus 4.8) — Piste hibernation/veille via le SEP : étudiée, SEP probablement pas le bon levier
- Trace : — (analyse hors ligne : grep des 23 sep.log + doc publique). Rien vers Asahi. Aucune action matérielle.
- Fait : vérifié l'activité de `hibe` (EP 0x14) dans nos traces ; recherche publique sur la veille Asahi et le rôle du SEP. Doc : docs/power_sep_options.md.
- Vu : `hibe` n'apparaît que comme annonce de nom (0 message) dans 23/23 captures → aucune donnée de protocole. Public : Asahi n'a que s2idle
  (~1,3-2 W, vide la batterie en une nuit = symptôme d'Albert) ; le vrai sommeil profond (S3, que macOS utilise) n'est pas implémenté, bloqué
  par la gestion d'alimentation des périphériques, **pas par le SEP** ; hibernation absente aussi, clé d'image d'hibernation non documentée publiquement.
- Interprété : pour la batterie qui se vide la nuit, le levier est le sommeil profond / power management du noyau Asahi, hors de ce projet SEP.
  `hibe` reste intéressant car PAS derrière le coffre xART (contrairement au Touch ID), mais spéculatif : il faudrait d'abord le capturer pendant
  une vraie hibernation macOS (lecture seule), et l'utiliser = écriture SEP (pending/ + Albert). Décision de direction à Albert.
- Incidents : une recherche web (mode étendu) refusée par Albert ; les deux autres ont suffi.

## 2026-11-10 — Claude (Opus 4.8) — C20 : 27 images lues sur le bus, 7 seulement transmises au SEP (les « 20 non transmises » quantifiées)
- Trace : traces/20261110-003201_c20-doigt-spi (lecture seule). Script : analysis/count_sensor_vs_sep_images.py. Hors ligne.
- Fait : compté les images 0x7200 lues sur le bus capteur (sio.bufs/*_done_data.bin, pleins) et les tranches 0x65 envoyées au SEP (sep.log).
- Vu : 27 images lues sur le bus ; 14 tranches 0x65 vers le SEP = **7 images transmises** ; donc **20 images lues mais non transmises**.
  Les 7 transmises se répartissent sur les poses (fp_good_1/2:2 tranches, fp_good_3:4 = 2 images, fp_bad_1/2:2, + 2 vers lock_g1) et sont
  exactement les 7 retrouvées octet pour octet côté SEP (analysis/cmp_sensor_sep_image.py).
- Interprété : résout (en le chiffrant) l'ancien point ouvert « rôle des 20 images non transmises ». `vérifié` pour les comptes (27 / 7 / 20).
  Hypothèse pour le « pourquoi » : pendant une pose, le capteur (configuré par le SEP sous macOS) fournit plusieurs trames ; l'AP n'en relaie
  qu'une (parfois deux) au SEP pour la comparaison, les autres étant des trames de prévisualisation/qualité non envoyées. Non testable sans le SEP.
- Incidents : aucun.

## 2026-11-10 — Claude (Opus 4.8) — Transport réactif : « bonjour » attend la broche « donnée prête », identité toujours identique
- Trace : — (Linux de test 10.0.200.4, dmesg ; mesa_probe.ko enable=1, transport mesa_transport.h). Compilé W=1.
- Fait : ajouté mesa_wait_ready() au transport (scrutation bornée de gpio0 195, 50 ms max, repli si pas de montée ; broche lue seulement,
  jamais d'interruption matérielle — choix sûr à distance, ne peut pas bloquer la machine). mesa_probe l'appelle avant chaque lecture d'état.
- Vu : « RÉSULTAT : IDENTITÉ IDENTIQUE », aucun avertissement « pas montée » (donc la broche a bien été vue à chaque étape). Capteur éteint, fin 0.
- Interprété : `vérifié` (1 essai, identité identique) : le transport peut attendre la broche au lieu de pauses fixes, sans changer le résultat.
  mesa_probe reste la référence vérifiée, maintenant réactive. Le vrai pilotage par interruption matérielle (request_irq) reste un pas ultérieur,
  à faire quand Albert peut power-cycler le Mac (risque de rafale d'IRQ qui bloquerait la machine à distance).
- Incidents : aucun.

## 2026-11-10 — Claude (Opus 4.8) — La broche gpio0 195 = ligne « donnée prête » (remonte à chaque réponse en attente)
- Trace : — (Linux de test 10.0.200.4, dmesg ; mesa_irqwatch.ko enable=1 hello=1 ; broche lue seulement ; trames en clair). Compilé W=1.
- Fait : joué le « bonjour » en relevant la broche gpio0 195 avant/après chaque échange.
- Vu : allumage 1 ; réveil 1 ; après 1er état 0 ; **après demande d'identité (0x70) 1** ; 2e état annonce 27 (0x1b) octets puis broche 0 ;
  après lecture de la réponse 0 ; état final 0 ; extinction 0.
- Interprété : `vérifié` (1 passe pour la remontée post-0x70, cohérent avec les boucles d'état antérieures pour réveil→état) : la broche est une
  ligne « donnée prête / attention », active haute, qui monte dès qu'une réponse est en attente et retombe quand l'AP lit l'état (0x10).
  Conséquence : le transport peut être piloté par interruption (attendre la montée) au lieu de pauses fixes. Prochain pas : câbler l'IRQ dans
  l'overlay (irq-gpios / interrupts) et requérir l'interruption dans le pilote.
- Incidents : 1er insmod avec l'ancien module (push raté pendant la coupure VPN) a rejoué la boucle d'état ; re-poussé, rebuild, relancé : OK.

## 2026-11-10 — Claude (Opus 4.8) — Expérience prête : la broche d'interruption pendant toute la séquence « bonjour »
- Trace : — (code préparé hors ligne ; VPN retombé avant de lancer, Albert à l'école). Compilé W=1 sur le PC.
- Fait : ajouté un mode `hello=1` à driver/linux/mesa_irqwatch.c : joue le « bonjour » (réveil, état, identité, état, lecture, état) en
  relevant la broche gpio0 195 avant et après chaque échange. But : savoir si la broche remonte à CHAQUE réponse en attente (pas seulement
  après le réveil) ; si oui, le pilote pourra être piloté par interruption au lieu de pauses fixes. Lecture seule de la broche, trames en clair.
- Vu : — (pas encore lancé : `ssh 10.0.200.4` timeout).
- Interprété : à lancer quand le VPN revient : `cd /root/mesa && make ... modules && rmmod mesa_irqwatch 2>/dev/null; insmod mesa_irqwatch.ko enable=1 hello=1; dmesg | grep mesa-irqwatch | grep -v 'TX\|RX'`.
- Incidents : VPN de la partition de test intermittent (timeouts répétés).

## 2026-11-10 — Claude (Opus 4.8) — Image capteur ↔ SEP comparée octet pour octet (3e item du filtre, fait)
- Trace : traces/20261110-003201_c20-doigt-spi (lecture seule). Script neuf, reproductible : analysis/cmp_sensor_sep_image.py. Hors ligne, aucun hardware.
- Fait : comparé l'image lue sur le bus SPI du capteur (sio.bufs/*_done_data.bin, 0x7200 o) aux buffers OOL échangés avec le SEP sur l'EP 0x08
  (sep.log.ool/*_08_A.bin). C'était la 3e analyse coupée par le filtre le 2026-11-10 sous Fable ; passée ici sous Opus 4.8.
- Vu : 7 images complètes de 0x7200 o = concaténation de **deux** buffers A de 0x4000, chacun après un entête de 0x1c o, **identiques octet pour octet**
  des deux côtés (22 autres images : buffer SEP hors fenêtre de capture, non comparables). Entête décodé (LE32) : [0]=1, [1]=0x7200 (longueur totale),
  [2]=offset de tranche (0, puis 0x3fe4), [3]=0, [4]=0, [5]=0x65 (type image), [6]=longueur de tranche (0x3fe4, puis 0x321c ; somme 0x7200).
  Contrôle : 2 images différentes partagent 0 run de 32 o.
- Interprété : `vérifié` (octet pour octet) que l'AP relaie l'image au SEP **telle quelle** par l'OOL de l'EP 0x08, découpée en tranches de 0x4000
  avec un descripteur de 0x1c o (type 0x65). Lève la réserse de SPI-1 (verification_status.md). Le contenu est chiffré bout en bout capteur↔SEP
  (2 images ne partagent rien) : l'AP ne voit que du chiffré, donc Linux ne pourrait que relayer, pas interpréter. Sens des champs [0]/[3]/[4] = hypothèse.
- Incidents : aucun.

## 2026-11-10 — Claude (Opus 4.8) — Voie B (tracer l'OOL de l'EP 0x13) : déjà supportée, commande prête ; backup existe
- Trace : — (revue de code hors ligne ; aucune action matérielle). Albert à distance (école), Mac joignable seulement par la partition Linux de test (VPN), câble USB débranché.
- Fait : vérifié dans hv/trace_sep_filtered.py que la capture de l'OOL de l'EP 0x13 est déjà possible sans nouveau code : `SEP_OOL_EPS` est générique,
  l'apprentissage du buffer via le CNTL (EP 0x00 TYPE 2/3/4/5, ligne 495) tourne hors du filtre d'affichage `self.eps`, et le CNTL de 0x13 fournit
  les deux buffers (0x8000, messages.md L91-98). Commande voie B écrite dans docs/xart_options.md (SEP_EPS=0x13 SEP_OOL_EPS=0x13 SEP_OOL_BYTES=0x8000 ...).
- Vu : lecture seule (traduction DART vérifiée, aucune écriture au SEP/DART/mémoire). Même classe de capture que C1-C20.
- Interprété : la voie B ne demande que la capture physique (câble rebranché + reboot mode câble), donc Albert devant le Mac ; impossible à distance.
  Albert signale avoir un backup (2026-11-10) ; à clarifier : couvre-t-il macOS/FileVault (la voie B écoute un boot macOS) ou seulement sa partition Linux ?
- Incidents : aucun.

## 2026-11-10 — Claude (Opus 4.8) — Étude du « coffre » (xART) : écrite (filtre non déclenché cette fois)
- Trace : — (analyse hors ligne, aucune action matérielle). Sources : docs/messages.md « xART au boot », journal analyste du 2026-11-10, doc Asahi/m1n1 déjà citées.
- Fait : écrit docs/xart_options.md à la demande d'Albert (il a relancé une session, autre modèle). Rassemble public + nos traces sur l'EP 0x13,
  et liste 5 voies (A capteur sans SEP ; B tracer l'OOL de 0x13 en lecture seule ; C rejouer des blobs = écriture SEP ; D forger un locker ;
  E SEP « vierge »), avec pour chacune ligne rouge / risque / faisabilité. Recommandation : voie B (sûre) comme prochain pas ; C/D/E = écriture SEP, Albert seul.
- Vu : contrairement aux 3 tentatives du 2026-11-10 sous Fable 5.2 (sous-agent documentaliste, résumé réduit, comparaison de buffers), le filtre
  « [cyber] » n'a PAS coupé cette fois (modèle Opus 4.8, session relancée par Albert). Document produit en entier.
- Interprété : conclusion honnête = Touch ID complet sous Linux est probablement hors de portée sans forger un locker xART (clé interne au SEP
  qu'on s'interdit de chercher) ; but réaliste court terme = « Linux parle au capteur ». La voie B dira si ça change. Tout reste `hypothèse` côté mécanisme.
- Incidents : aucun.

## 2026-11-10 06:15 — Albert (doigt), Claude — DOIGT-LINUX-IRQ : la broche d'interruption du capteur marche sous Linux, mais ne réagit pas au doigt
- Trace : — (Linux de test 10.0.200.4, dmesg ; module driver/linux/mesa_irqwatch.c, broche gpio0 195 lue seulement toutes les 20 ms ; trames 0x78 et 0x10).
  Protocole et prédiction écrits avant : docs/hypotheses.md « DOIGT-LINUX-IRQ ».
- Fait : (a) 15 s sans doigt, état lu chaque seconde ; (b) 40 s, fenêtre 06:13:49 → 06:14:29, Albert annonce le doigt posé à 06:14:04
  (sans appuyer, ~15 s demandées, heure de retrait non donnée) ; (c') 10 s sans doigt et sans aucune lecture d'état (`etat_ms=0`).
- Vu : dans (a) et (b), même déroulé : broche = 0 capteur éteint, 1 après l'allumage, 1 après le réveil 0x78, puis **1 → 0 dans les 11 ms
  qui suivent la 1re lecture d'état** (celle qui porte l'octet 0x18), et plus aucun changement ensuite (0 jusqu'à la fin, 0 après extinction).
  (b) : aucun changement de la broche ni de l'état pendant le doigt (39 états identiques `… 09 60 00 00 00 00 00 00 00`).
  (c') : sans lecture d'état, la broche reste à 1 pendant les 10 s, puis 0 à l'extinction.
- Interprété :
  - `vérifié` (3 passes concordantes) : gpio0 195 est bien la ligne « le capteur a quelque chose à dire », active haute ; le capteur la lève
    seul après l'allumage et la baisse quand l'AP lit l'état. L'octet 0x18 de la 1re réponse d'état va avec cette demande (hypothèse sur son sens).
  - conforme à la prédiction (1 essai, doigt déclaré par Albert) : allumé et réveillé par Linux seul, le capteur ne signale pas le doigt, ni par
    l'état ni par la broche. Cohérent avec l'idée que la détection dépend de la configuration chiffrée envoyée par le SEP sous macOS (hypothèse).
  - l'étape (c) prévue (doigt sans lecture d'état) n'a pas de sens : la broche étant déjà à 1 tant que l'état n'est pas lu, un doigt n'y serait pas visible. Abandonnée.
- Limite : scrutation à 20 ms (impulsion plus courte invisible) ; un seul essai avec doigt.
- Incidents : aucun.

## 2026-11-10 06:08 — Albert (doigt), Claude — DOIGT-LINUX, 2e passe : doigt annoncé posé, état inchangé
- Trace : — (Linux de test 10.0.200.4, dmesg ; `insmod mesa_statloop.ko enable=1 duree=30`, fenêtre 06:07:42 → 06:08:12 heure du Mac).
- Fait : Albert a écrit « je le mets maintenant » ; boucle lancée aussitôt après son message (la 1re passe de 06:06 reste sans confirmation du doigt).
- Vu : 31 lectures, les deux mêmes formes que sans doigt : 1re `… 09 60 00 00 18 00 00 00 00`, puis 30 × `… 09 60 00 00 00 00 00 00 00`. Capteur éteint.
- Interprété : conforme à la prédiction écrite avant (docs/hypotheses.md DOIGT-LINUX) : allumé et réveillé par Linux seul, le capteur ne signale
  pas le doigt dans sa réponse d'état. Statut : `vérifié (1 essai)` pour « l'état lu par 0x10 ne change pas avec le doigt », sous réserve que le
  doigt soit resté posé pendant la fenêtre (déclaré par Albert, pas mesuré). Non testé : la broche d'interruption du capteur (gpio0 195), qui
  pourrait bouger sans que l'état change ; lecture à 1 Hz seulement.
- Précision d'Albert (après coup) : doigt posé à partir de ~06:07:55, donc présent pendant ~17 des 30 s (lectures 14 à 31 environ) ; aucune de ces lectures ne diffère.
  Question d'Albert : sous macOS 13.5, écran éteint, poser le doigt rallume l'écran. Hypothèse (non testée) : sous macOS le capteur a été configuré par le dialogue chiffré avec le SEP et signale le doigt par sa broche d'interruption (gpio0 195) ; ici il est seulement allumé et réveillé. À départager aussi : toucher ou appuyer (le bouton d'alimentation est sous le capteur).
- Incidents : aucun.

## 2026-11-10 06:07 — Claude (+ Albert à confirmer) — État du capteur en boucle depuis Linux : repos 30 s, puis essai DOIGT-LINUX 45 s
- Trace : — (Linux de test 10.0.200.4, tools/linux_ssh.sh, dmesg ; module driver/linux/mesa_statloop.c ; trames 0x78 et 0x10 seulement, rien vers le SEP).
- Fait : (1) sans doigt, `insmod mesa_statloop.ko enable=1 duree=30` ; (2) protocole DOIGT-LINUX de docs/hypotheses.md (prédiction écrite avant),
  `duree=45`, fenêtre 06:06:27 → 06:07:13 (heure du Mac), Albert appelé par tools/appel_albert.sh au lancement pour poser le doigt ~15 s.
- Vu : (1) 31 lectures : la 1re `80 20 00 10 000000 09 60 00 00 18 00 00 00 00`, les 30 suivantes `… 09 60 00 00 00 00 00 00 00`, toutes identiques.
  (2) 46 lectures : exactement les deux mêmes formes (1 + 45), aucun autre octet ne bouge. Capteur éteint à la fin des deux essais.
- Interprété : état stable au repos sur 30 s (vérifié, 1 essai). L'octet 0x18 n'est vu qu'à la 1re lecture après le réveil (hypothèse : drapeau
  effacé par la lecture). Pour le doigt : résultat conforme à la prédiction SEULEMENT SI le doigt était bien posé pendant la fenêtre —
  **non confirmé par Albert à l'heure de cette entrée** ; reste `hypothèse` jusqu'à sa réponse. Lecture à 1 Hz : un changement de moins d'1 s
  entre deux lectures passerait inaperçu.
- Incidents : aucun.

## 2026-11-10 — Claude — Reproductibilité du « bonjour » depuis Linux avec le module rangé (adresse VPN 10.0.200.4)
- Trace : — (Linux de test, via tools/linux_ssh.sh ; nouvelle adresse 10.0.200.4 donnée par Albert, voir ci-dessous).
- Fait : adresse du Linux de test passée à 10.0.200.4 (Albert l'a donnée en session ; mise à jour de tools/linux_ssh.sh,
  CLAUDE.md, handoff, hypotheses). Poussé les sources rangées (mesa_transport.h + mesa_probe.c), recompilé sur place,
  puis séquence « bonjour » : `cp mesa-spi2.dtbo /lib/firmware/ && insmod mesa_ovl.ko && insmod mesa_probe.ko enable=1`.
  Même noyau qu'avant (7.2.12-402.asahi.fc45), overlay toujours valide (ps_spi2 phandle 0x130).
- Vu : identité `80 d4 00 1b 00000000 70 02 19 c0 5c 0f d2 aa 34 9a 81 c7 6e 03 02 00 d8 75 76` = **identique** à macOS,
  m1n1 et au 1er LINUX-HELLO ; « RÉSULTAT : IDENTITÉ IDENTIQUE » ; état final `…00 60 00 00 00 52 33 00 00`, capteur éteint.
- Interprété : `vérifié` (2e essai depuis Linux, reproductible) : le capteur répond à l'identique depuis Linux, et la refonte
  de mesa_probe.c sur la couche transport mesa_transport.h n'a rien changé au comportement (même trames, même ordre).
- Incidents : après l'essai, le lien VPN est retombé (ssh timeout sur 10.0.200.4). La 2e expérience prévue — lire l'état en
  boucle 30 s sans doigt (module mesa_statloop.c, 2e client du transport, écrit et compilé W=1, poussé non) — n'a pas pu être
  lancée. À reprendre quand le VPN revient.

## 2026-11-10 — Claude — Rangement du module Linux : couche transport séparée du test « bonjour »
- Trace : — (travail hors ligne, hors Mac ; Albert installe le VPN de la partition de test).
- Fait : extrait de `driver/linux/mesa_probe.c` une couche transport réutilisable `driver/linux/mesa_transport.h`
  (`mesa_acquire`/`mesa_release`, `mesa_power_on`/`mesa_power_off`, `mesa_send`, `mesa_read`, `mesa_status` ;
  struct `mesa_dev` avec tampons tx/rx hors pile). `mesa_probe.c` devient le premier client = la seule séquence « bonjour ».
  Aucun changement de comportement, mêmes trames, même ordre, mêmes délais. Module toujours `mesa_probe.ko`,
  Makefile et commande de rechargement inchangés. README mis à jour.
- Vu : `mesa_probe.o` compile sans avertissement sous `W=1` contre les en-têtes du noyau du PC (x86, contrôle d'API).
  `mesa_ovl.o` échoue sur ce PC (`of_find_all_nodes` absent des en-têtes x86 ; compile sur l'Asahi du Linux de test),
  sans rapport avec le changement.
- Interprété : but = servir de base au pilote (le pilote inclura `mesa_transport.h` au lieu de recopier la séquence).
  Reste à vérifier sur le Mac : recharger et refaire « bonjour » (reproductibilité) quand 10.0.200.4 est joignable.
- Incidents : aucun.

## 2026-11-10 00:52 — Claude — MESA-HELLO : le capteur répond sans macOS (m1n1 seul)
- Trace : traces/20261110-005244_mesa_hello (tools/mesa_hello.sh ; écritures : broche 196 d'alimentation + registres spi2 en mode scruté ; rien vers le SEP, rien dans pmgr ni dans les broches SPI).
- Fait : alimentation comme macOS (C17), puis seulement les trames en clair vues dans C19 : 0x78, 0x10, 0x70, 0x10, 0x13 (0x1b), lecture de 0x1b octets, 0x10. CLKDIV 3, CFG 0x40002 (CPHA, scruté), FIFO de 16.
- Vu : état `80 20 00 10 000000 09 60 00 00 18…` après le réveil ; après 0x70 l'état annonce 0x1b octets ; réponse lue = `80d4001b00000000700219c05c0fd2aa349a81c76e030200d87576`, **identique octet pour octet à celle lue sous macOS** (C18, C19, C20) ; état final `…00 60 00 00 00 52 33 00 00` comme sous macOS. Registres et broche remis à leur valeur d'origine (relus).
- Interprété : passent à `vérifié` (expérience dédiée, 1er essai) : spi2 à 0x39b108000 atteint bien le capteur avec les broches telles qu'iBoot les laisse (donc sans pinctrl à ajouter), sans broche CS, alimentation active haute sur gpio0 196, CPHA = 1, et les 4 trames 0x78 / 0x10 / 0x70 / 0x13. Le groupe de broches 116-118 reste inexpliqué mais n'est pas nécessaire. Refait une fois (traces/20261110-005318_mesa_hello2) : même identité, même remise en état.
- Incidents : aucun ; Mac resté en mode proxy.

## 2026-11-10 01:20 — Claude — LINUX-HELLO : Linux parle au capteur (Linux de test, sans câble, sans rien installer)
- Trace : sortie dmesg ci-dessous (Linux de test 10.67.0.94, noyau 7.2.12-402.asahi.fc45 ; via tools/linux_ssh.sh, voir logs/linux_ssh.log). Pas de dossier traces/ (aucun m1n1).
- Fait : `driver/linux/mesa_ovl.ko` ajoute à chaud le nœud spi2 + capteur au device tree vivant (`of_overlay_fdt_apply`, fichier `mesa-spi2.dtbo` ; donne en mémoire un phandle au nœud ps_spi2 qui n'en avait pas ; phandles numériques relevés dans /root/live.dts). spi-apple a pris `39b108000.spi`, le capteur est apparu en `spi2.0`. Puis `insmod mesa_probe.ko enable=1` (module réécrit par l'agent driver : séquence de MESA-HELLO).
- Vu : état `80 20 00 10 000000 09 60 00 00 18…`, puis 0x1b octets en attente, réponse `80 d4 00 1b 00000000 70 02 19 c0 5c 0f d2 aa 34 9a 81 c7 6e 03 02 00 d8 75 76` = **identité identique** à macOS et à m1n1 ; état final `…00 60 00 00 00 52 33 00 00` ; capteur éteint. 8 MHz demandés, mode 0x1 (CPHA).
- Interprété : `vérifié` (1 essai) : le pilote public spi-apple pilote spi2 tel quel (son bit CS interne ne gêne pas, l'interruption AIC 1108 marche, ps_spi2 est géré par le noyau, horloge 24 MHz = phandle de spi3). Le développement du transport capteur peut se faire sur le Mac seul par ssh.
- Incidents : aucun. Seuls messages annexes : avertissements « Failed to create device link » de thunderbolt-apple-acio à l'application de l'overlay (sans effet vu).
- Pour refaire après un reboot : `cd /root/mesa && cp mesa-spi2.dtbo /lib/firmware/ && insmod mesa_ovl.ko && insmod mesa_probe.ko enable=1 && dmesg | tail -20`.

## 2026-11-10 01:05 — Claude — Étude « voies pour xART » : sous-agent arrêté par le filtre de sécurité du modèle
- Trace : —
- Fait : sous-agent documentaliste lancé à la demande d'Albert pour écrire docs/xart_options.md (sources publiques + nos traces, aucune action matérielle).
- Vu : arrêté dès le début par le filtre « [cyber] » de Fable 5.2 (même comportement que l'étude SKS du 2026-11-08). Aucun fichier produit.
- Décision : ne pas insister ni refaire l'étude autrement dans cette session. Options pour Albert : programme « Cyber Verification » d'Anthropic (réduit ces coupures), ou lire lui-même la doc publique Asahi sur le SEP.
- Incidents : aucun (aucun hardware).

## 2026-11-10 00:55 — Albert (doigt), Claude — C20 : doigt posé avec écoute du bus SPI du capteur
- Trace : traces/20261110-003201_c20-doigt-spi (`TRACE_SCRIPT=hv/trace_sep_spi_dma.py SEP_OOL_EPS=0x08`, tools/guide_doigt.sh ; 16 marques ; arrêt demandé après `end`). Protocole et prédiction écrits avant : docs/hypotheses.md « C20 ».
- Actions d'Albert (notes.txt) : mot de passe au login, 3 bons doigts = déverrouillé (o, o, o), 2 mauvais doigts = refusé (n, n), puis mot de passe. « tout bon ». ~2 min entre le login et le 1er verrouillage (Mac lent sous écoute).
- Vu : 0 erreur de lecture SIO. 27 lectures SPI de 0x7200 octets (en-tête `80 52 <n> 80 09 00 00 3a …`, n = 0x00, 0x0c, 0x18… : +12 par image d'une même pose), 7 envois SEP `> 0x65`, 6 `> 0x09`. **Les 7 envois 0x65 contiennent chacun la 1re image SPI d'une pose (n = 0x00, ou 0x0c une fois)** : 113 blocs de 256 o sur 114 retrouvés tels quels dans les buffers OOL A (le bloc manquant est à cheval sur la coupure en morceaux OOL). Les 20 autres images lues sur SPI ne sont dans aucun buffer envoyé au SEP.
- Vu (déroulé d'une pose) : en attente, demande d'état 0x10 toutes les ~0,5 s (réponse `…11 02 21 80 04 80808080`) ; au doigt l'état passe à `13 00 21 00 0e…` puis `07 00 21 00 8e 00 72 00 00` (0x7200 en attente) → 0x13 (longueur 0x7200) → lecture de l'image → SEP 0x23, 0x06, **0x65**, 0x07, 0x1e, 0x09 → `< TAG 0x01` (résultat) ; l'AP continue à lire des images pendant ce temps ; fin par trame 0x30, puis 0x40 avant la pose suivante.
- Interprété : prédiction « relais pur » confirmée 7/7 → `vérifié (macOS)` pour « la charge de 0x65 = image lue sur SPI, non transformée par l'AP » (réserve : comparaison par blocs de 256 o, pas un sha du transfert réassemblé). Hypothèses restantes : rôle des images non transmises (flux continu du capteur ?), sens des octets d'état, trames 0x30/0x40 = arrêt/reprise du balayage.
- Incidents : aucun ; m1n1 revenu en proxy.

## 2026-11-10 00:35 — Claude — C18/C19 : contenu du dialogue SPI AP ↔ capteur (écoute seule)
- Trace : traces/20261110-002417_c18-spi-dma-boot (200 s), traces/20261110-002829_c19-spi-dma-boot (120 s) ; boots macOS sans doigt, `TRACE_SCRIPT=hv/trace_sep_spi_dma.py` (boîte ASC de SIO en SYNC + lecture mémoire à travers dart-sio, aucune écriture).
- Vu : C18 : les offsets du code public m1n1 (trace_mesa.py, M1) marchent pour les échanges doubles, pas pour les écritures seules (66 buffers non lus). Cause lue dans les blocs de contrôle : le champ DATA du message SIO TYPE 6 choisit le descripteur (+0x40 + DATA*0xc). Traceur corrigé → C19 : 147 buffers lus, 0 erreur. Trames `80 <cmd> <len> 000000` : 0x10 état (47), 0x13 demande de réponse (10), 0x78/0x70 début, 0x72, 0x73, 0x60 + bloc de 0x568e / 0x70ce octets, 0x55 (9), 0x30, 0x40. Réponse 0x70 identique dans C18 et C19. Détail et table : docs/sensor_hw.md « Dialogue SPI ».
- Interprété (hypothèse) : l'AP relaie entre le SEP et le capteur des messages chiffrés (compteur de 8 octets par allumage) ; seules l'identité et l'état sont en clair.
- Incidents : aucun (2 captures, end_reason timeout, m1n1 revenu en proxy). Le mode SYNC sur SIO n'a pas gêné le boot.
- Suite : capture avec doigt (EXPÉRIENCE HUMAINE) pour voir le chemin de l'image.

## 2026-11-10 00:19 — Claude — C17 : premier relevé du bus SPI du capteur sous macOS (registres seulement)
- Trace : traces/20261110-001859_c17-spi-boot (boot macOS 240 s, sans doigt ; `TRACE_SCRIPT=hv/trace_sep_spi.py` : traceur SEP habituel + registres de spi2 + broches gpio0 48-51 et 195-196, mode ASYNC, aucune écriture). Analyse : `analysis/spi2_transfers.py <dossier> [--sep]`.
- Vu : 84 échanges SPI. **Aucun accès à TXDATA/RXDATA** : les données passent par DMA (SIO), seuls les compteurs sont visibles. Réglages constants : CLKDIV = 3, CFG = 0x40042 (bit 1 = CPHA dans la table publique m1n1, bits 6:5 = 2), SHIFTCFG 0x80c07, PIN = 0. Tailles : lecture/écriture 0x17 (40 fois, entre presque tous les autres échanges), écritures seules 0x07, 0x0b, 0x2f, 0x40, 0x47, 0x49, 0x4d, 0x56, échanges 0x1b, 0x33, 0x4b, et deux gros envois **0x568e** (21 ms) et **0x70ce** (29 ms).
- Vu (broches) : macOS n'écrit jamais les broches 48-51 (réglage d'iBoot conservé). Broche 196 : passée en sortie à 0 puis à 1 (alimentation active à l'état haut), avec deux cycles 0→1 de ~11 ms plus tard (t+28,575 et t+28,752) suivis chacun de la même suite d'échanges. Broche 195 : mode interruption, masquée/démasquée en permanence.
- Vu (ordre) : les échanges SPI alternent avec les commandes SEP de l'EP 0x08 : p. ex. `0x15` → écriture 0x2f ; `0x42` → écriture 0x47 puis échange 0x4b ; `0x5f` (transfert OOL depuis le SEP) → envoi 0x568e ; `0x5d`/`0x5c` → écritures 0x40 ; `0x31` → écriture 0x49 + échange 0x4b ; après t+32 s un échange 0x17 toutes les 0,5 s.
- Interprété (hypothèse) : l'AP sert de relais : le SEP fournit les blocs à envoyer au capteur (dont un gros bloc par allumage, probablement le correctif du capteur) et reçoit ses réponses ; 0x17 = lecture d'état. Fréquence réelle = 24 MHz / (3+1) = 6 MHz si la formule publique s'applique (l'ADT annonce 8 MHz) : non tranché. Contenu non vu → capture C18 avec lecture des buffers DMA (hv/trace_sep_spi_dma.py).
- Incidents : aucun (end_reason timeout, m1n1 revenu en proxy).

## 2026-11-10 00:15 — Claude — spi2 : registre d'alimentation trouvé (hors ligne), broches candidates 48/49/50 (lecture seule)
- Trace : traces/20261108-162919_adt/adt.bin (hors ligne, analysis/adt_pmgr_ps.py) ; traces/20261110-001208_gpio_peek (tools/gpio_peek.sh : 255 lectures de config de broches gpio0 + 6 lectures de registres d'alimentation pmgr, aucune écriture, rien vers le SEP, spi2 lui-même non lu).
- Vu (ADT, table pmgr.devices) : SPI2 id 144 (= `clock-gates` du nœud spi2), psreg 9, psidx 0, parent SPI_P → registre PS = pmgr.reg[2] + 0x200 = CPU **0x28e580200**. Contrôle de la formule : SPI1 → +0x1f8, SPI3 → +0x208, SPI4 → +0x210, identiques au fichier public Linux `t600x-pmgr.dtsi` (ps_spi1@1f8, **ps_spi2@200**, ps_spi3@208, ps_spi4@210, parent ps_spi_p).
- Vu (Mac sous m1n1 seul, état laissé par iBoot) : SPI_P, SPI1, SPI2, SPI3, SPI4 = 0x000000ff (TARGET 15, ACTUAL 15 = allumés). 80 broches de gpio0 en fonction périphérique. Motif commun aux bus SPI connus : 3 broches consécutives `0x008742a0, 0x00874220, 0x00874220` (périph 1 ; la 1re avec tirage bas) puis la broche CS : spi1 = 10, 11, 32 + CS 33 (sortie GPIO, = ADT GPIO 0x21) ; spi3 = 52-54 + CS 55 (ADT 0x37) ; spi4 = 56-58 + CS 59 (ADT 0x3b). Le même motif existe sur **48, 49, 50** (51 non configurée) et sur 116, 117, 118. Broche 195 (IRQ capteur) : entrée, tirage bas, lue à 1. Broche 196 (mesa_pwr) : non configurée (entrée coupée, pas en sortie).
- Correction : l'entrée du 2026-11-10 01:10 disait « pas de domaine d'alimentation pour spi2, @200 = afnc1_ls ». Faux : il y a deux `power-controller@200` dans deux blocs pmgr différents ; celui du bloc de spi1 (0x28e580000) est bien ps_spi2. Le DT vivant du Linux de test n'a pas été relu (Mac en mode proxy).
- Interprété (hypothèse, par élimination et par numérotation) : broches de spi2 = 48 (MISO), 49, 50 en fonction 1, déjà réglées par iBoot ; `function-spi_cs0 = 1:null()` = pas de broche CS du tout (et non « CS natif »). Le groupe 116-118 est un 5e bus sans contrôleur connu dans l'ADT : il empêche de dire « vérifié ». Capteur éteint sous m1n1 (196 pas en sortie) : hypothèse.
- Ce qui trancherait : voir les broches 48-50 bouger pendant un échange capteur (traceur GPIO sous macOS : ces broches ne sont pas des GPIO, donc invisible) ou un essai réel sous Linux avec spi2 + ces broches (DT à mettre dans la charge m1n1 = Albert).
- Incidents : aucun. Mac resté en mode proxy.

## 2026-11-10 01:10 — Claude — Test capteur sur le Linux de test : arrêt avant d'alimenter spi2
- Trace : /root/live.dts sur 10.67.0.94 (dump du DT vivant, lecture seule) ; aucune charge de module.
- Vu : DT vivant sans `__symbols__` (overlay par labels impossible, phandles numériques seulement) ; spi1 : power-domains 0x5f (pmgr `power-controller@1f8`, label spi1), clocks 0x31/0x5d, interrupt-parent 0x13 (AIC), pinctrl@39b028000 = 0x48 (255 broches). **Pas de domaine d'alimentation pour spi2** : `power-controller@200` existe seulement dans un autre bloc pmgr et s'appelle `afnc1_ls` (toujours allumé), donc l'hypothèse « ps_spi2 = pmgr 0x200 » du documentaliste ne tient pas dans ce DT. Pas de pinctrl spi2. Pas de configfs d'overlay (OF_OVERLAY=y seulement).
- Interprété : alimenter et brancher spi2 demande de deviner un registre pmgr et des broches : risque matériel non justifié par le gain (le statut capteur brut n'est pas garanti lisible sans la requête du SEP). Test non fait.
- Décision : pas d'overlay sur le Mac. Suite possible = lire l'ADT pmgr (power-state de spi2 côté macOS) en lecture seule via m1n1, ou arrêter.

## 2026-11-10 00:50 — analyste — Échange xART (EP 0x13) et EP 0x00 avant sbio, 19 boots macOS (hors ligne)
- Trace : les 19 `sep.log` + `hv_uart.log` de traces/ (lecture seule). Scripts : analysis/xart_boot.py, xart_cntl.py, xart_boot_crc.py, xart_chain.py ; sorties analysis/out/xart_*.txt.
- Vu : 46 premiers messages 0x13 identiques en TAG/TYPE/PARAM/DATA dans 19/19 (hors jitter de quelques ms). SEP attend 2,8-3,8 s la 1re réponse de l'AP (TAG 2/0x0e), puis 4 requêtes (TAG 1, 3, 4) ; 0,122 s après la réponse TAG 4 il annonce sbio puis skdl, sse, sks, scrd (TYPE 0x1d, acquittés par `> TYPE 0x16`) ; 14 « fetch locker » suivent (TAG 5-0x12). EP 0x00 avant : 0x0d, 0x29, requête 0x14 (réponse 3), 0x10 ; CNTL TAG 7/8 permuté. Réponses AP : entêtes constants (PARAM/DATA), mais le contenu (CRC noyau) de SEP-xART, USER-xART et d'un locker varie ; il est égal à ce que le SEP a fait sauver au boot précédent (15/15 et 16/16 paires consécutives). Le CRC des « Saving » est recopié par l'AP (252/252).
- Interprété (hypothèse) : réponses = entête constant + contenu d'état lu sur le disque ; rejeu mécanique possible sur le papier mais il manque le contenu des buffers xarm (jamais tracé : pas d'OOL sur 0x13), et toute réponse sur 0x13 est une écriture SEP (pending/, Albert). Détail dans docs/messages.md « xART au boot — traces ».
- Incidents : aucun (aucun accès hardware).

## 2026-11-10 00:20 — Albert, Claude — Contrôle iCloud : 2 reboots natifs sans demande de connexion
- Rapport d'Albert : deux redémarrages normaux sous macOS, aucun problème de login.
- Interprété : la déconnexion n'est pas un état durable ; cause toujours non établie (effet unique du boot SEP par m1n1, ou événement indépendant). Pas de preuve contre le boot SEP, mais pas de dégât persistant observé.
- Suite décidée (Claude, CLAUDE.md) : analyse hors ligne de l'échange xART (EP 0x13) des boots macOS ; aucune écriture SEP.

## 2026-11-10 00:10 — Claude — Pourquoi 7/12 : ce qui précède sbio dans les boots macOS (lecture seule)
- Trace : les 19 sep.log de traces/ (C1…C16) ; détail C1 : traces/20261107-033436_c1-boot/sep.log.
- Vu : macOS envoie exactement la même séquence de boot que m1n1 (GET_STATUS, BOOT_TZ0, GET_STATUS, BOOT_IMG4 + SET_SHMEM) ; 7 endpoints (cntl, hdcp, xars, xarm, hibe, pnon, stac) annoncés ~0,6 s après, avec dès ce moment 1 message `< EP=0x13 TAG=0x02 TYPE=0x0e` et 2-3 messages `< EP=0x00` (0x0d, 0x29…) = **les 4 messages restés en attente dans SEP-BOOT** (1 sur 0x13, 3 sur EP 0). Les 5 autres (sbio…) sont annoncés ~3 s plus tard, **19/19 boots précédés de messages AP→SEP sur EP 0x13 (xART)** dans les 12 lignes d'avant.
- Interprété (hypothèse renforcée, causalité non prouvée) : sbio/sks… n'apparaissent qu'après un échange xART avec l'AP ; m1n1 n'ayant pas répondu, SEPOS est resté à 7/12. Aucune écriture n'est justifiée tant que la cause iCloud n'est pas écartée (revue sceptique : lire dans Console la raison de la demande de connexion, ou 2 reboots natifs).
- Incidents : aucun.

## 2026-11-09 23:50 — sceptique — Revue des conclusions SEP-BOOT / iCloud / SKS-1
- Trace : traces/20261109-221029_sep_boot, traces/20261107-033436_c1-boot/sep.log (lecture seule)
- Fait : relecture des 3 conclusions du jour ; détail dans docs/hypotheses.md « Revue sceptique du 2026-11-09 ».
- Vu : dans C1 (macOS), les mêmes 7 EP sont annoncés en 7 ms avant tout message AP ; les 5 autres arrivent 3,4 à 3,8 s plus tard, après SECMODE/CNTL/hdcp/stac/xART. Donc 7/12 est le comportement normal de la 1re phase : le boot m1n1 a probablement réussi.
- Interprété : (a) cause « attend xART/pnon » non distinguée de « attend CNTL » ou d'un message sans réponse (les 4 messages en attente n'ont jamais été imprimés) ; (b) la reconnexion iCloud a au moins 5 autres causes (boot natif vs hyperviseur, reboots brutaux, horloge, serveur Apple...), et le SEP redémarre avec le Mac donc le mécanisme est peu clair ; (c) SKS-1 n'a aucune observation positive (jamais de 0x09 à l'état 0x0015).
- Incidents : aucun. Aucun hardware, aucune écriture SEP.

---

## 2026-11-09 23:40 — Claude — spi2 : adresse confirmée par l'ADT
- Trace : traces/20261108-162919_adt/adt.txt L1042-1080
- Vu : spi2 `reg = 0x19B108000` (taille 0x4000) → adresse CPU **0x39B108000** (= 0x200000000 + 0x19B108000), confirme la déduction du documentaliste ; interrupts [1108], clock-gates 144, `function-spi_cs0 = 1:null()` (pas de GPIO pour le chip-select) ; aucune propriété de broches (pinctrl) dans le nœud ; mesa `reg = 00000000 f4010000 00010108 …` (sens non décodé).
- Interprété (hypothèse) : le chip-select est le CS natif du contrôleur ; les broches SPI de spi2 ne sont pas listées dans l'ADT, donc soit fonction fixe, soit configurées par iBoot/pmgr : à ne pas deviner. Pour un overlay Linux : reg 0x39b108000, interruption 1108 (IRQ AIC, déjà connue des autres spi), power-domain ps_spi2 (pmgr 0x200), horloge fixe 24 MHz ; manque : pinctrl.
- Incidents : aucun.

## 2026-11-09 23:30 — Claude (analyste) — messages.md : EP 0xFF/0xFE sans macOS, colonne « annoncé sans macOS »
- Trace : traces/20261109-210517_sep_peek, 20261109-212150_sep_getrand, 20261109-221029_sep_boot (lecture seule)
- Fait : nouvelle section « EP 0xFF / 0xFE (boot ROM) — traces du 2026-11-09 » dans docs/messages.md ; colonne « Annoncé sans macOS ? » dans la table des endpoints (oui : cntl, hdcp, xars, xarm, hibe, pnon, stac ; non vu : sbio, scrd, sse, sks, skdl).
- Vu : GETRAND répondu ; séquence de boot « BOOT OK » ; 7/12 endpoints. Rien d'autre n'est passé à « vu » ; le reste reste connu-doc.
- Interprété : effet de bord de reconnexion au compte Apple rappelé comme hypothèse (un seul cas). Aucun statut « vérifié ».
- Incidents : aucun.

## 2026-11-09 23:00 — Claude — Linux de test (Fedora Asahi Remix, 10.67.0.94) : module compilé
- Fait : exception root dans CLAUDE.md (ajoutée par Albert) ; tools/linux_ssh.sh (run/put/get, interdits : disques, boot, m1n1, SEP ; journal logs/linux_ssh.log) ; installé gcc, make, git, kernel-devel sur le Linux de test ; copié et compilé driver/linux/mesa_probe.c → mesa_probe.ko OK (noyau 7.2.12-402.asahi.fc45 16k).
- Vu : le DT de ce Linux ne décrit que spi@39b104000 (flash, = spi1 ADT) et spi@39b10c000 (hid-transport, = spi3 ADT). **spi2 (ADT, capteur) n'y est pas** : pas de nœud `biosensor,mesa`, donc le module ne se liera à rien tant que le DT n'est pas changé. dtc/fdtoverlay absents ; support des overlays non confirmé.
- Interprété : pour tester le capteur il faut un DT avec spi2 + mesa (overlay si le noyau le permet, sinon DT dans la charge m1n1 = installation m1n1, réservée à Albert).
- Incidents : aucun.

## 2026-11-09 23:00 — Claude (driver) — Squelette Linux du capteur, hors ligne
- Trace : traces/20261108-162919_adt/mesa.txt (lecture seule)
- Fait : driver/linux/ : fragment DT (spi2, 8 MHz, IRQ gpio0 195, alim gpio0 0xc4, délais 7/10), module spi `mesa_probe` (enable=0 par défaut, lecture 16 o du statut, aucun envoi SEP), README. `.gitignore` : `linux/` -> `/linux/` pour pouvoir versionner driver/linux.
- Vu : rien de nouveau (aucun hardware, rien compilé).
- Interprété : adresse spi2, horloge, type d'IRQ, CS, phase, polarité/unité des délais = suppositions marquées dans le .dtsi ; reset via AOP inconnu.

## 2026-11-09 22:20 — Albert, Claude — Après SEP-BOOT : retour sous macOS
- Rapport d'Albert : macOS démarre, tout va bien, **mais il a dû se reconnecter à son compte Apple** (iCloud).
- Interprété (hypothèse) : effet de bord probable du démarrage du SEP par m1n1 (le SEP a perdu/invalidé un état lié aux jetons du compte), puisque ~20 reboots/captures sous hyperviseur avant n'avaient rien provoqué de tel (aucun signalement). Non prouvé : Touch ID non testé dans ce message.
- Décision : **pause avant toute réponse xART/pnon** (zones liées au disque chiffré et au trousseau). Pas de nouveau boot SEP par m1n1 sans nouvelle décision d'Albert.

## 2026-11-09 22:10 — Albert (lancé), Claude (noté) — SEP-BOOT : SEPOS démarre depuis m1n1 seul
- Trace : traces/20261109-221029_sep_boot (pending/sep_boot.sh corrigé : DART T6000 explicite)
- Fait : séquence publique m1n1 (GET_STATUS → BOOT_TZ0 → GET_STATUS → BOOT_IMG4 + SET_SHMEM) avec le firmware SEPFW déjà en RAM, puis écoute 30 s.
- Vu : « BOOT OK » (les 4 réponses attendues reçues). Endpoints annoncés sur 0xFD : **7 sur 12** — cntl 0x00, hdcp 0x0e, xars 0x10, xarm 0x13, hibe 0x14, pnon 0x15, stac 0x18. **Absents** : sbio 0x08, scrd 0x0a, sse 0x0c, sks 0x12, skdl 0x17. Messages en attente non lus : 3 sur EP 0x00, 1 sur EP 0x13 (contenu non affiché par le script, perdu).
- Interprété (hypothèse) : SEPOS tourne et attend l'AP (xART/politique de boot) ; les services biométrie/clés (sbio, sks…) ne sont annoncés qu'après ces échanges, comme sous macOS où xart/pnon passent d'abord. Non établi. Le message en attente sur 0x13 est probablement une demande xART.
- Suite : répondre à xART/pnon = écriture vers 0x13/0x15, lignes rouges → script pending/ + décision d'Albert. Rien fait. Contrôle demandé à Albert : redémarrer sous macOS, ouvrir la session, tester Touch ID.
- Incidents : aucun.

## 2026-11-09 22:00 — Albert (lancé), Claude (noté) — SEP-BOOT : plantage de m1n1 avant tout message au SEP
- Trace : sortie console du lancement de pending/sep_boot.sh (pas de dossier de trace : crash avant l'écriture des logs).
- Vu : « Exception: SYNC / data abort » dans m1n1 pendant `dart_map` (create_shmem), avant tout `send_msg` ; Mac redémarré par m1n1.
- Interprété : incompatibilité du code Python public `SEP.__init__` avec ce m1n1 : `dart_init` côté C prend (base, device, keep_pts, type), le Python passe (base, sid, type) → type de DART faux (T8020 au lieu de T6000). Aucun message n'a été envoyé au SEP (le boot commence après create_shmem). Script corrigé (DART T6000 explicite), non relancé.
- Incidents : reboot du Mac (prévu). 

## 2026-11-09 22:00 — Claude (documentaliste) — Sources publiques : EP 0xFF et passage SEPROM → SEPOS
- Trace : — (sources publiques seulement ; détail dans docs/public_linux_state.md §5)
- Vu : m1n1 `sep.py` donne les messages de l'EP 0xFF : GET_STATUS=2 (réponse 0x66), BOOT_TZ0=5, BOOT_IMG4=6 ; GETRAND=16 (réponse 116). Doc Asahi : iBoot précharge, XNU amorce (boottz0 puis IMG4). Le mot SEPROM n'est pas dans la doc.
- Interprété : état du SEP sous m1n1 non écrit publiquement ; SEPOS probablement pas amorcé (hypothèse). Désaccord doc/code sur le rôle de 0xFE/0xFF noté pour le sceptique.
- Incidents : aucun.

## 2026-11-09 21:21 — Albert (lancé), Claude (noté) — SEP-GETRAND : le SEP répond sous m1n1 seul
- Trace : traces/20261109-212150_sep_getrand (pending/sep_getrand.sh corrigé)
- Vu : appel de sep_get_random (EP 0xFF, commande 16) : réponse reçue, 4 octets aléatoires (6e 0a 78 60), aucun plantage, Mac resté en mode proxy.
- Interprété (hypothèse) : le SEP répond au message de découverte « ROM » sans macOS, comme m1n1 l'attend à chaque boot Linux. Cela ne prouve PAS que SEPOS (le logiciel complet : biométrie, sbio) tourne : la doc publique Asahi attribue l'EP 0xFF à la ROM du SEP. À trancher : est-ce que les endpoints 0xFD (annonce des services) apparaissent sans macOS ?
- Incidents : aucun.

## 2026-11-09 21:20 — Claude — Correction SEP-GETRAND : le plantage venait de MON adresse
- Trace : traces/20261109-211835_check_sym et traces/20261109-211849_check_sym (tools/check_sep_sym.sh : lecture de 16 octets de m1n1, rien d'autre)
- Vu : à base+0x40e40 (adresse que j'avais appelée) la mémoire contient des NOP ; la fonction sep_get_random est à base+0x30e40 (contrôle : octets lus = octets attendus, « ADRESSE BONNE »). Le décalage est celui de 0x10000 entre l'adresse du fichier ELF et le chargement du .bin.
- Interprété : le 1er essai (211028) a sauté dans une zone de NOP, pas dans la fonction : **il ne dit rien sur le SEP**, et le message GETRAND n'a très probablement jamais été envoyé. La conclusion « le SEP fait planter m1n1 » de l'entrée précédente est **retirée**. pending/sep_getrand.sh corrigé (-0x10000), non relancé.
- Incidents : aucun cette fois ; Mac en mode proxy.

## 2026-11-09 21:10 — Albert (lancé), Claude (noté) — SEP-GETRAND : m1n1 plante au premier appel
- Trace : traces/20261109-211028_sep_getrand (meta, chainload.log, getrand.log)
- Fait : pending/sep_getrand.sh lancé par Albert ; appel de sep_get_random (offset 0x40e40 du m1n1 chargé).
- Vu : m1n1 rechargé OK (ADT, proxy vivant), puis à l'appel : « ValueError: 4 is not a valid START » côté PC (le Mac a envoyé un message de reprise inattendu) ; Albert : « acm device closed » affiché, puis **le Mac a redémarré tout seul**. Aucune réponse GETRAND lue.
- Interprété (hypothèse) : soit l'adresse appelée n'est pas la bonne (base de m1n1 ≠ base + offset ELF), soit l'envoi/attente sur la boîte du SEP a fait planter m1n1. Non tranché. Un redémarrage est le mode d'échec prévu ; aucune donnée touchée.
- Incidents : reboot du Mac. Pas de nouvelle tentative sans accord d'Albert ; un « peek » de contrôle a été proposé puis refusé par Albert.

## 2026-11-09 21:05 — Claude — SEP-PEEK : état du SEP sous m1n1 seul (lecture seule)
- Trace : traces/20261109-210517_sep_peek (tools/sep_peek.sh : 3 lectures de registres d'état, aucune écriture, aucun message dépilé)
- Vu : base 0x396400000 ; CPU_CONTROL = 0 (RUN bit4 = 0) ; boîte AP→SEP et SEP→AP : vides, activées, non pleines ; compteurs de lecture/écriture ≠ 0 (5/5 et 6/6).
- Interprété (hypothèse) : des messages ont déjà circulé dans les deux sens depuis le boot (iBoot ↔ SEP), puis tout a été consommé : la boîte n'est pas « vierge ». CPU_CONTROL = 0 ne prouve pas que le SEP est arrêté : ce registre pilote le démarrage d'un ASC classique, et le SEP est lancé par iBoot autrement (non établi). Donc **inconnu** : si SEPOS tourne déjà sous m1n1 seul. Pour trancher il faudrait un message de découverte, donc une écriture.
- Incidents : aucun. Mac reste en mode proxy.

## 2026-11-09 — sceptique — Tranchage des lignes « vérifié (proposé) »
- Trace : — (relecture de docs/verification_status.md, journal, driver/tests ; aucun hardware, aucune écriture SEP)
- Fait : règle CLAUDE.md « Qui décide quoi » appliquée. Sens de `vérifié` précisé : comportement observé de macOS, reproductible ; jamais « le SEP exige ».
- Vu : passent à `vérifié` (macOS) : init de 57 commandes (8/8 boots + rejeu 18/18 captures dont C13-C16 hors échantillon ; réserve : coupure à 57 choisie après coup), structure 0x65 + CRC des 12 tranches (468/468, 3 sessions), boucle 0x6c -> 0x6d (prédiction C12 écrite avant, exacte ; réserve : gros blob C8 -> C9 partiel), `<03` => `>21` (50/50, déjà vérifié).
- Reste `hypothèse` : « `<01` suit le keybag, pas le verdict » (K-E1 : une session, prédiction 0x209@lock partiellement fausse), ordre petit/gros blob, contenu des 0x65, tout « exigé par le SEP ».
- Incidents : aucun. Docs modifiées : verification_status.md, messages.md (ligne 0x65), driver/README.md.

## 2026-11-08 — driver — Étape 5 (hors ligne) : « démon » d'init (57 commandes) et boucle de blobs 0x6c -> 0x6d
- Trace : les 18 captures contenant des commandes sbio (init) ; C8, C9, C10b, C11, C12 pour les blobs. Lecture seule, rien n'est émis.
- Fait : `driver/sepreplay/daemon.py` (INIT_SEQUENCE de 57 TYPE, `BlobStore`, `InitPlan`, requête 0x6c = uid u32 + 20 zéros) + `driver/tests/test_step5_daemon.py`.
- Vu : la séquence produite par le démon = les 57 premières commandes `> fc` de 18/18 captures (C10 sans sbio exclue). C11 -> C12 : les 2 blobs 0x6d de C12 sont identiques (octet pour octet) aux derniers 0x6c de C11 (uid -1 0xf4 o, uid 501 0x9245 o) ; les 14 réponses 0x6c de C11 (7 paires) sont complètes, requêtes = `export_request(uid)` 14/14. C9 -> C11 via store rechargé : 2/2 identiques. C8 -> C9 : petit blob identique ; gros : longueur annoncée 0x9317 identique et 3 x 996 o lus identiques (le tracer n'a pas dumpé 0x6c en entier en C8) : PARTIEL.
- Interprété : confirme la boucle export->import (déjà `vérifié (HO)`), rien de nouveau. Ne dit RIEN sur l'acceptation d'un 0x6d par le SEP (écriture, hors périmètre). 29/29 tests OK au total.
- Incidents : aucun.

## 2026-11-08 — driver — Étape 4 (hors ligne) : réassemblage GT fc/fd/fe + CRC des tranches 0x65
- Trace : toutes les captures avec sep.log (compteur) ; OOL de C6, C8, C11, C12 (réassemblage), lecture seule.
- Fait : `driver/sepreplay/gt.py` (règle de compteur, relecture OOL avec report `changed=none`, réassemblage par en-tête 0x1c, contrôle de tranches) + `driver/tests/test_step4_gt.py`.
- Vu : règle de compteur (fc = 0 ; fe = nb de fd déjà vus ; fd = ce nb + 1) : 5086 messages GT sur 18 traces, 0 exception (la doc cite 4006/14 traces : ensemble de traces différent). sha des .bin = sha du log pour toutes les lectures de C6/C8/C11/C12. C11 : 24/24 transferts 0x65 de 0x7200 o, 288/288 tranches (en-tête `80 52`, longueur 0x980, CRC-16/ARC) ; C6+C8+C11 : 39/39 images, 468/468 tranches. Une tranche corrompue est détectée. 0x5b = 0xfc99 o (sha d5a6117d), 0x5f = 0x568e puis 0x70ce o, complets en C11 et C12.
- Vu (limites) : le réassemblage 0x65 doit se limiter à dir '>' tampon A (anciens tracers sans split_dir relisent la même charge sous '<' : 12 au lieu de 6 pour C6). Transferts incomplets uniquement par troncature du tracer : 0x5f de C5/C6 (2 chacun, 0x5f pas encore dans full_types) et 0x6c de C8 (3 gros blobs, 2988 o lus sur ~37 Ko).
- Interprété : rien de nouveau ; la règle de compteur reste « vérifié (côté macOS) ». 22/22 tests OK.
- Incidents : aucun.

## 2026-11-08 — driver — Étape 3 (hors ligne) : parseur de trame capteur et du statut `80 20 00 10000000 ...`
- Trace : hv_uart.log de 20 captures (ligne `AppleBiometricSensor: start(): SensorStatus: 16B | ...`), lecture seule.
- Fait : `driver/sepreplay/sensor.py` (trame `80 op idx u32len charge`, statut, constructeur de la demande de lecture `80 13`), `crc.py` (CRC-16/ARC, vecteur standard 0xBB3D) ; `driver/tests/test_step3_sensor.py`.
- Vu : 20/20 lignes SensorStatus portent les mêmes 16 octets (la doc disait 16/16 : 4 traces de plus depuis) ; en-tête, longueur 0x10 = taille réelle ; les 2 derniers octets (00 00) ne sont pas le CRC-16/ARC (0x35de calculé), comme dit dans messages.md. Octet +7 = 0, u32 +0xc = 0x3352 : exposés bruts, NON interprétés.
- Interprété : rien ; statut capteur reste `hypothèse`. Aucun nœud DT, aucun bus. 15/15 tests OK.
- Incidents : aucun.

## 2026-11-08 — driver — Étape 2 (hors ligne) : table de découverte 0xFD (nom -> EP, tailles)
- Trace : C5, C6, C7, C8, C9, C10b, C11, C12 (8 boots), lecture seule.
- Fait : `driver/sepreplay/discovery.py` + `driver/tests/test_step2_discovery.py` ; recherche par nom (`find("sbio")` = 0x08), aucun n° codé en dur dans le module.
- Vu : 12 EP annoncés dans chacun des 8 boots, noms = table de messages.md 8/8 ; tailles FD TYPE 1 lues (octet0 min envoi, octet1 max envoi, octet2 min recv, octet3 max recv, pages 0x4000) : T4/T5 des ouvertures CNTL = octet1/octet3 x 0x4000 dans 67/67 séquences (prédiction écrite avant) ; sbio C11 : A=0x64000, B=0x6c000, 0x4000/0x4000.
- Vu (écart) : l'ORDRE d'annonce n'est PAS identique : 3 ordres sur 8 boots (C7 : 0x17,0x0c avant 0x08 ; C9 : 0x0e avant 0x15). verification_status.md disait « C6..C12 ont le même ordre » : inexact. Ensemble identique 8/8, 4 premiers identiques. Conséquence : le pilote doit chercher par nom.
- Interprété : le sens des 4 octets de tailles reste `hypothèse` (cohérent 67/67, mais la prédiction vient du motif lu).
- Incidents : aucun. 10/10 tests OK.

## 2026-11-08 — driver — Étape 1 (hors ligne) : décodeur de mots mailbox + lecteur de sep.log
- Trace : C8 (004657), C11 (025802), C12 (032454), lecture seule.
- Fait : `driver/sepreplay/mailbox.py`, `driver/tests/test_step1_mailbox.py` ; aucun hardware, aucun tools/*.sh.
- Vu : 3981 / 6348 / 641 messages = `# end seen=logged` du tracer, 0 ligne invalide, aller-retour mot 64 bits exact pour chaque message ;
  lectures OOL 480 (C8) / 994 (C11, = journal) / 151 (C12). 5/5 tests OK.
- Interprété : rien de nouveau ; le découpage reste `hypothèse (cohérent)` dans verification_status.md.
- Incidents : aucun.

## 2026-11-08 18:55 — Claude — C16 (K-E1, 2e moitié : lock → mdp → lock → doigt → lock → 20 s → doigt)
- Trace : traces/20261108-183948_c16-ke1 (marks.txt, notes.txt : good_lockb = o, good_lockc = o) ; capture arrêtée avec stop_capture.sh.
- Vu : chaque lock → `<08/01 TYPE=0x09 P2` à +0,5-0,9 s ; mot de passe → `<12 TAG=0x09`, `<12 TAG=0x00` puis `<08/01 0x28 P2` (+1,4 s) ; doigt 10 s après lock : 0x09 puis `<12 TAG=0` (-501) + `<08/01 0x08 P2` ×2 (avant et après la réponse 0x09) + `<08 TAG=0x03` ; doigt 28 s après lock : mêmes notifs précédées de 3 `<12 TAG=0x01` (volume P1, puis 2 autres) vus ~11 s après le lock, et après le doigt `<12 TAG=0` ×3 (P1 puis P0 P0) ; un 2e `<08/01 0x09` apparaît 10-20 s après chaque lock, **y compris après le doigt dans lock_b** (+10,2 s après la marque doigt).
- Interprété : K-E1 : 0x209 à chaque lock ✓, 0x228 au mot de passe ✓, 0x208 au doigt ✓, 0 TAG 0x01 pendant les invites session ouverte ✓ (C15). **Écart** : le 2e 0x209 n'est pas propre au cas « attendre 20 s » (vu après tous les locks) ; Touch ID réussit avec ou sans verrouillage du volume. Reste hypothèse (n=1 par cas).
- Incidents : aucun.

## 2026-11-08 18:40 — Claude — C15 (K-E1 partielle, session ouverte)
- Trace : traces/20261108-181424_c15-ke1 (marks.txt : ke1_good_1/2/3, ke1_bad_1, ke1_lock_a, ke1_pw) ; capture coupée par TRACE_TIMEOUT=1200 s juste après ke1_pw (« le Mac a reboot » = fin de capture, pas un incident). Moitié finale (lock_b, lock_c) non faite.
- Vu : 4 invites en session ouverte (3 bon doigt, 1 mauvais) = séquence `23 06 65 07 09 1f` identique, 0x09 en ~215-290 ms ; **0 `<08 TAG=0x01`** pendant les 4 invites (seul `<08 TAG=0x03` ~0,7-1 s après chaque marque, y compris mauvais doigt) ; aucune requête AP→0x12 pendant les invites ; au lock (ke1_lock_a +0,9 s) un seul `<08 TAG=0x01 TYPE=0x08 PARAM=0x02 DATA=0x1f5` = **0x208, pas 0x209 prédit**.
- Interprété : TAG 0x01 n'est pas émis par un verdict biométrique en session ouverte (4/4) → soutient la lecture keybag de K1 ; 0x208 au lock, sens à revoir (0x209 différé ?). Reste hypothèse : n=4, une seule trace. Refaire lock_b/lock_c avec TRACE_TIMEOUT plus long.

## 2026-11-08 16:55 — Claude — Cause de l'échec C13 : veille inactive au login
- Trace : traces/20261108-163401_c13-ke1/hv_uart.log L2742-2800 (« going to sleep », FB0 ON→OFF, IOCPUSleepKernel)
- Vu : boot complet jusqu'à launchd + keybag, puis veille système ~9,5 min après le début ; seule autre veille : C6. Les captures « boot seul » duraient ≤ 300 s.
- Interprété : veille d'inactivité à l'écran de connexion (personne n'a tapé le mot de passe), pas un échec de boot. Relance C14 avec Albert devant le Mac.

## 2026-11-08 16:35 — Claude — C13 (K-E1) avortée : pas de session ouverte
- Trace : traces/20261108-163401_c13-ke1 (timeout 900 s, reboot propre, proxy revenu)
- Vu : noyau jusqu'à launchd, puis mise en veille (S2R, « pmu go hib ») vers 16:44 ; Albert rapporte « macOS a pas boot » (écran sans login ?). Aucune étape K-E1 faite.
- Interprété : inconnu (écran de login jamais atteint côté affichage, ou veille avant saisie).
- Incidents : capture inutilisable pour K-E1.

## 2026-11-08 — Claude — ADT-1 : dump du device tree (lecture seule)
- Trace : traces/20261108-162919_adt (tools/dump_adt.sh, analysis/adt_find_mesa.py)
- Fait : dump ADT 507904 octets, m1n1 frais chainloadé, aucune écriture.
- Vu : capteur `biosensor,mesa` = enfant de **spi2** (interrupts 1108, clock-gate 144, phandle 44) ; spi-frequency 8 MHz ; power-on-delay 7, power-off-delay 10 ; `function-mesa_pwr` = GPIO(0xc4, 0x101) sur gpio0 (phandle 132) ; IRQ capteur = gpio0 [195, 3] ; pas de function-mesa_reset / _pwr1v8 dans ce nœud ; reg = f4010000 00010108 ... (octets bruts, sens non décodé).
- Interprété : le reset passe par l'AOP (cohérent avec docs/sensor_hw.md) ; sens du pin 0xc4 et de 0x101 = hypothèse.
- Incidents : aucun. Mac reste en mode proxy.

## 2026-11-08 — Claude — SKS-1 : symboles AppleKeyStore ↔ messages EP 0x12
- Trace : — (relecture docs/messages.md, kext_sepmanager.md ; analysis/out/sks_symbols.txt)
- Fait : relié les noms de symboles aux messages 0x12 ; hypothèse SKS-1 dans docs/hypotheses.md.
- Vu : chemin doigt sans requête AP→0x12 ; lockState annoncé par le SEP.
- Interprété : le SEP applique probablement lui-même le blocage bio ; non tranché sans écriture (pending/).
- Incidents : /dev/ttyACM* absent → Mac injoignable, pas de hardware ce tour.

## 2026-11-08 — analyste — Kext : écarts d'init K6-1..3, +0x14 de 0x09, 0x63/0x61
- Trace : traces/ C5..C12 (comparaison) ; analysis/out/c{6,8,11}_payloads ; source: kext (AppleMesaSEPDriver, kernel.macho 13.5).
- Fait : lecture de loadPatch, applySensorParams, setCalibrationData, resetSensorAndLoadPatch ; extraction C11 `ool_attempts.py --dump-dir analysis/out/c11_payloads/`.
- Vu : 5d 5c 6a [6f], 31 32 et 0x01 sont dans loadPatch ; 0x6f exige un octet posé par setCalibrationData ; 0x61 = ratio de modulation, conditionné à une propriété `modulation-ratio` ; +0x14 = 0 sur 29/29 réponses 0x09 ; 0x63 = GetCalibrationDataInfo.
- Interprété : détails et réserves dans docs/kext_sepmanager.md (dernière section). Rien changé dans messages.md/hypotheses.md.
- Incidents : aucun (pas de hardware).

## 2026-11-08 — sceptique — Tableau de statut de vérification
- Trace : — (relecture de docs/messages.md, kext_sepmanager.md, hypotheses.md, journal C12)
- Fait : `docs/verification_status.md` (1 ligne par message/champ, statut selon CLAUDE.md, manque pour `vérifié`, 3 expériences).
- Vu : vérifié (proposé) = encodage GT, ordre d'init, séquence match + verdict 0x09, 0x65 (structure), `<03`→`>21`, HO/0x6c-0x6d, `<01/09` au verrou ; le reste hypothèse.
- Interprété : « vérifié » = comportement de macOS ; aucune écriture SEP donc rien sur ce que le SEP exige.

## 2026-11-08 — driver — Plan d'architecture du pilote Touch ID (docs/driver_plan.md)
- Trace : —
- Fait : lu messages.md (kext, 0x65, C8-C12), kext_sepmanager.md, public_linux_state.md, hypotheses.md (K1-K7) ; écrit docs/driver_plan.md (composants, dépendances avec statuts, prérequis hors agent, étapes, inconnues classées). Aucun code, aucun hardware.
- Vu : —
- Interprété : bloquants principaux = SEPOS sous Linux (IMG4, réservé Albert), keybag SKS (0x0015 au boot), nœud DT du capteur inconnu.
- Incidents : aucun

## 2026-11-08 — analyste — Contrôleur SPI / broches du capteur (j314c) : ADT absent
- Trace : traces/20261107-033436_c1-boot/hv_uart.log:176,182-184,910,912,2078 ; macos/kernel.macho (plist prelink, strings).
- Fait : recherche d'un dump ADT dans traces/macos/m1n1/docs/analysis (aucun) ; lu trace_mesa.py ; noms de propriétés `mesa*`/`function-mesa_*` du kernel.
- Vu : 4 contrôleurs spi1-4 démarrés ; capteur = enfant `biosensor,mesa` d'un AppleARMSPIDevice ; noms `function-mesa_pwr/_pwr1v8/_reset`. Contrôleur et broches non identifiables sans ADT.
- Interprété : voir docs/sensor_hw.md (spi2/spi4 candidats, 0xc4 = valeur M1 non transposable). Demande EXPÉRIENCE ADT-1 dans docs/hypotheses.md (non exécutée).
- Incidents : aucun (pas de hardware).

## 2026-11-08 — documentaliste — État public côté Linux (SEP, spi-apple, AOP, mesa)
- Trace : — (sources publiques) ; recoupé avec traces/20261107-033436_c1-boot/hv_uart.log:176-184.
- Fait : lu m1n1 local (`70757dc7`) : src/sep.c, src/kboot.c, src/main.c, hw/sep.py, hv/trace_mesa.py,
  hv/trace_aop.py. Lu linux-asahi branche `asahi` (raw.githubusercontent) : drivers/soc/apple/{sep.rs,aop.rs,Kconfig},
  drivers/spi/{spi-apple.c,Kconfig}, drivers/dma/apple-sio.c, DT t600x-*/t6001-j314c/t8103*/t8112. Vérifié la présence
  dans le mainline et lu la doc Asahi (sep, feature-support/m1, subsystems, devicetree-bindings). Détail et citations dans
  docs/public_linux_state.md.
- Vu (public) : Linux a un pilote SEP « stub » (`sep.rs`, downstream) qui ne fait qu'amorcer SEPOS (BOOT_TZ0, BOOT_IMG4 de
  `sepfw`, SET_SHMEM, découverte EP 0xfd ignorée). Aucun code SBIO, SKS ou xART. Sur t600x, le nœud `sep` est
  `disabled` et j314/j316 n'a pas d'alias `sep`, donc m1n1 ne transmet pas `sepfw`. m1n1 parle au SEPROM (EP 0xff,
  GETRAND) pour les graines. `spi-apple` est mainline (6.15), sans DMA ; son Kconfig cite « fingerprint sensor ». Le DT
  t600x ne décrit que spi1 (NVRAM) et spi3 (HID), aucun nœud mesa. trace_mesa.py (M1) : capteur sous `spi-1,spimc`,
  DMA via SIO EP 0x20, GPIO `mesa_pwr` 0xc4, « command buffer is encrypted after the poweron sequence », message de
  0x7200 octets. aop.rs ne connaît que aop-audio, als et las. TouchID = « TBA » dans le feature support.
- Vu (trace) : macOS démarre spi1 à spi4 sur notre j314c ; spi2 et spi4 sont absents du DT Linux.
- Interprété : sous Linux publié, le SEP reste sous SEPROM sur j314c. Rien de public pour SBIO ni pour le reset mesa via
  l'AOP. trace_mesa.py recoupe la lecture du kext (SPI de l'AP, chiffrement après échange de clé, 0x7200 octets).
  Contradiction mineure : la doc Asahi donne type = bits 16-24 et param = 25-31, alors que le code fait 16-23/24-31
  (pour le sceptique). La page des bindings Asahi dit SPI « not submitted upstream », ce qui est périmé.
- Incidents : `gh api` refusé par les permissions ; lectures faites via WebFetch et raw.githubusercontent.

## 2026-11-08 — analyste — Phase 2 : AppleSEPManager (boot, CNTL, découverte, ouverture d'EP) + lockState IOBiometricFamily
- Trace : — (kernelcache 13.5 `macos/kernel.macho`) ; recoupé avec C11 (sep.log L3-148, L348-L2100, L558-L5980 ;
  hv_uart L643-766, L1515, L1555), C1 L39-41, C12 L39-49.
- Fait : `analysis/kext/kdump_syms.py` (listing par fonction nommée LC_SYMTAB, sortie analysis/out/kext/, non versionné) ;
  lecture d'AppleSEPBooter (bootSEP, _bootAction), AppleSEPControl (cmsg*, _cmsgSend, _cmsgAction), AppleSEPDiscovery
  (_msgReceived), AppleSEPEndpoint (enable, setSend/ReceiveOOLBuffer), AppleSEPManager (_sendMessageGated), GT
  (init, enableEndpoint), Mesa (getSEP, handleSEPMessage, prepareSession, performKeyExchange, initializeSequenceCounter,
  setCalibrationData), IOBiometricFamily (sksQueueProcess, isAtLeastOne*, check*Timer). Slots de vtable résolus par
  symboles. Aucune copie de code. Synthèse : `docs/kext_sepmanager.md` (messages.md non modifié : autres agents).
- Vu (kext) : `> EP=0xFE` = taille shmem en pages dans les octets 2-3 (« TYPE 0x1c » = 0x1c000 o, uart L660) ; CNTL
  2/4 = SET_OOL_IN (buffer d'envoi AP→SEP), 3/5 = SET_OOL_OUT (réception), tailles en octets, adresses >> 12, buffers
  alloués par l'AP (GT, 0x4000 pour sbio) ; tag CNTL = index du pool + 1 (s'inverse entre C1 et C11) ; CNTL reçus 0x0d/0x15
  = « OS actif », 0x29 = non sollicité (uart L765) ; FD TYPE 1 = [min,max] pages envoi / réception ; pas de numéro
  d'endpoint codé en dur (nub `sep-endpoint,sbio`). lockState : bit 0 verrouillé, bit 1 blocage code, bit 2 blocage bio,
  bit 5 code validé (noms des fonctions qui testent les bits). TAG 0x02 → champ « biométrie présente » du contexte.
  0x17 = n° de série capteur ; 0x15/0x16 = clé de session SEP↔capteur (AP relaie) ; 0x5b, 0x6d, 0x71 = blobs utilisateur.
- Vu (trace) : 0x0228 3/3 juste après une saisie de mot de passe (C11 L851, L860, L5980), 1 ms après `< EP=0x12
  TAG=0x98 TYPE=0x67` (L850) ; 0x0015 au boot ; `<02` 1× après le 2e `> 0x6d` (L548 → L562).
- Interprété : après boot, la bio est bloquée tant que le keybag n'a pas validé le code via SKS (EP 0x12) → bloquant
  probable pour Linux (dépendance D2 de kext_sepmanager.md). Tout reste `hypothèse` (source: kext).
- Incidents : venv capstone du scratchpad absent → recréé dans le scratchpad de cette session. `> EP=0xFF TYPE 0x1b` /
  `< 0x7f` non attribués.

## 2026-11-08 — Claude (session principale) — K4 : tailles et CRC des 0x65 de C11
- Trace : traces/20261108-025802_c11-doigt-tranchant.
- Fait : `analysis/ool_transfers.py --types 0x65 --dump-dir analysis/out/c11_65` puis `analysis/slice_crc.py` sur les charges.
- Vu : 24/24 transferts `> A 0x65` font exactement 0x7200 octets ; 288/288 tranches (24 × 12) passent le contrôle trame + CRC-16/ARC
  décrit par le kext. Avec C6+C8 (180/180) : 468/468 tranches, 39/39 transferts à 0x7200 (compte C6/C8 : rapport analyste).
- Conclusion : K4 (0x65 = 12 tranches capteur de 0x980, taille 0x7200) confirmé sur 3 traces → proposé `vérifié`.
- Incidents : aucun.

## 2026-11-08 — analyste — Phase 2 : d'où vient l'image 0x65 (AppleBiometricSensor, AppleSPUMesaDriver)
- Trace : — (kernelcache 13.5 `macos/kernel.macho`) ; recoupé avec C8/C6 (`analysis/out/c{6,8}_payloads/*_65.bin`,
  `*outB_07.bin`) et uart C11 L685-703.
- Fait : `analysis/kext/ksyms.py` (table de symboles LC_SYMTAB du kernelcache : les fonctions des kexts sont nommées) ;
  `analysis/slice_crc.py` (contrôle trame/CRC des tranches 0x65) ; lecture de AppleMesa::start, readSensorData,
  handleStateMachine, dispatchCaptureReady, AppleSandDollar::_checkImageCRC, crc16ansi, AppleSPUMesaDriver, et dans
  Mesa : handleCapture, asyncCaptureHandler (0x65, 0x07), séquences SEP/capteur (slots de vtable résolus par symboles).
  Personnalités IOKit lues dans le plist prelink. Code public m1n1 `proxyclient/hv/trace_mesa.py` lu. Listings dans
  analysis/out/kext/abs/ (non versionné). Aucune copie de code.
- Vu (kext) : AppleSandDollar se rattache à `biosensor,mesa` sur un AppleARMSPIDevice (capteur SPI de l'AP) ; l'AOP
  (AppleSPUMesaDriver, HID SPU page 0x20/usage 0x13) ne sert qu'au reset (commandes 0x20/0x21, `function-mesa_reset`).
  Lecture image = trame `80 13 00 0b000000 <size>` puis lecture SPI ; tranches contrôlées par CRC-16/ARC ; chemin
  jusqu'à `> 0x65` = recopies seulement. Init : SEP 0x15 → capteur SessionKeyExchange → SEP 0x16, 0x42 → capteur → 0x18,
  0x5f → capteur Patch → 0x01, 0x5d/0x5c/0x6a/0x6f → paramètres/commandes chiffrés vers le capteur. 0x07 : champs
  nommés (assessment, feedback, contrast…) ; 0x130/0x193 = codes de retour de la transaction.
- Vu (trace) : 180/180 tranches 0x65 (C8+C6) passent le contrôle du kext (en-tête `80 52 NN`, longueur 0x980 à +3,
  CRC-16/ARC). Réponses 0x07 : `+0x85` = 0x37 15/15 ; abandons assessment 2 / feedback 0xc9.
- Interprété : 0x65 = image brute du capteur recopiée telle quelle, chiffrée par le capteur avec une clé de session
  négociée par le SEP via l'AP. Linux : `spi-apple` + pilote mesa (alim/IRQ/trames/CRC) + relais vers l'EP 0x08. Statut
  `hypothèse` (source: kext) ; non vérifié sur ce Mac : nœud ADT/spi/pins (m1n1 donne `/arm-io/spi2` et SIO sur M1).
- Incidents : aucun (pas de hardware).

## 2026-11-08 — analyste — Phase 2 : lecture de AppleMesaSEPDriver + AppleSEPGenericTransfer (TYPE sbio → noms)
- Trace : — (kernelcache macOS 13.5 `macos/kernel.macho` ; recoupé avec C1, C3, C8, C11, C12 via docs/messages.md)
- Fait : `analysis/kext/macho_fileset.py` (segments d'une entrée MH_FILESET), `analysis/kext/kdis.py` (capstone dans un venv
  du scratchpad : index des chaînes par fonction, appels virtuels `sepTransact` vtable +0x9e0 / `sepTransactToIOMD` +0x9d8
  avec la constante en w1), `analysis/kext/mesa_cmd_map.py` + `mesa_case_reach.py` (cases du répartiteur user-client
  `performSpecificCommandGated` → noms de commandes, attribution par accessibilité : 27/27 non ambigus). Sorties dans
  analysis/out/kext/ (non versionné). Aucune copie de code ; tout est décrit en prose dans docs/messages.md (source: kext).
- Vu (kext) : 98 + 16 appels avec TYPE constant ; GT construit le mot mailbox (TAG = request 0xfc/0xfd/0xfe, bits 16-47 =
  commande, bits 48-63 = compteur de messages de la transaction) et l'en-tête OOL de 0x1c o (version 1, total, offset,
  champ +0x0c, 0, commande, taille du morceau). 0x09 : réponse exigée = 0xca2 o (`match_info_t`), +0x00 = uid (−1 =
  pas de correspondance). 0x65 : 0x7200 o = 12 tranches capteur. 0x22 = `kEnableBgOpsUpdate`, 0x63 =
  `kGTGetCalibrationDataInfo` (noms de constantes lus dans des asserts). 0x6c = PrepareSaveCatacomb (entrée 0x18 o),
  0x37 = ConfirmSaveCatacomb, 0x6d = LoadCatacomb, 0x70/0x71 = Save/LoadBioLockoutRecord. Notifications TAG 0x01 :
  passées à IOBiometricFamily `sksQueueProcess` (« userID, lockState ») ; TAG 0x03 → `checkBgOpsResult` → 0x21 ;
  `> TAG 0x26 DATA=uid` = `dropUnlockToken`.
- Interprété : recoupe l'en-tête OOL, les fragments, les séquences d'init et de tentative observés ; les `<01/08`,
  `<01/09`, `<01/45` seraient des états de keybag (SKS) et non des résultats biométriques (contredit l'ancienne lecture
  de `<01/08`). Le blob catacomb n'est pas stocké par le kext (relais vers l'espace utilisateur). Statut : `hypothèse`
  (source: kext) partout ; lectures incertaines signalées dans messages.md (+0x0c de l'en-tête, request 0xff, sens de 0x1e,
  branche principale de la réponse 0x07, `+0xc24` non interprété par le kext).
- Incidents : aucun (pas de hardware). 1re attribution « case le plus proche » fausse pour 0x6c/0x37/0x38 (branches
  « version 2 » hors ligne) ; corrigée par l'analyse d'accessibilité.

## 2026-11-08 — Albert — Passage en phase 2 (KEXTS)
- Albert a modifié lui-même la ligne PHASE de CLAUDE.md (`## PHASE ACTUELLE : 2 — KEXTS`).
- Rappel des règles phase 2 : désassemblage des kexts uniquement pour le protocole AP↔SEP, aucune copie de code Apple dans `driver/`,
  `source: kext` sur chaque info tirée d'un kext. Lignes rouges inchangées (pas d'écriture SEP par un agent, SEPOS hors périmètre).
- Albert a proposé « prendre du code Apple » : refusé par Claude (droit d'auteur + règle CLAUDE.md) ; approche « doc du protocole → driver neuf ».
- Kexts cibles repérés dans macos/kernel.macho (LC_FILESET_ENTRY) : AppleMesaSEPDriver (fileoff 0x42b2d0), AppleBiometricSensor (0x2d28e0),
  AppleBiometricServices (0x2dd8b0), IOBiometricFamily (0x6de8b0), AppleSEPManager (0x49e030), AppleSEPKeyStore (0x49a270),
  AppleSEPGenericTransfer (0x497bf0). Outils dispo : llvm-objdump seulement (pas de Ghidra/r2).

## 2026-11-08 — Claude (session principale) — C12 : test de la prédiction HO (boot sans humain après C11)
- Trace : traces/20261108-032454_c12-boot-ho (TRACE_TIMEOUT=300, config OOL de C11 avec 0x6c/0x6d complets ; sortie C11 par reboot() HV, aucun boot natif).
- Prédiction écrite AVANT la capture (analyste, rapport C11) : le `> A 0x6d` d'init de C12 = dernier export `< B 0x6c` de C11,
  L6959 (0x9245 o, sha 83613e39) et L6983 (0xf4 o, sha 5e58a78d).
- Vu (`analysis/ool_transfers.py --types 0x6d`, sortie analysis/out/c12_transfers.txt) : C12 L520 `>A 0x6d` total 0x9245, lu 0x9245,
  sha 83613e39, magic LTFC, uid 0x1f5 ; L494 `>A 0x6d` total 0xf4, sha 5e58a78d, uid 0xffffffff. Les deux identiques octet pour octet
  (sha sur la totalité) à la prédiction. 0 ool_error.
- Conclusion : HO (blob LTFC exporté par le SEP via 0x6c après un succès, conservé par macOS, renvoyé tel quel au boot via 0x6d)
  confirmée par une prédiction a priori sur une trace dédiée → **candidat `vérifié`** au sens de CLAUDE.md, à valider par Albert.
  Non établi : où macOS stocke le blob, ce qu'il contient (chiffré), si le SEP refuse un blob absent/ancien (non testable sans écriture).
- Incidents : aucun.

## 2026-11-08 — analyste — Analyse C11 (session doigt tranchante)
- Trace : traces/20261108-025802_c11-doigt-tranchant (sep.log, sep.log.ool/, hv_uart.log, marks.txt, notes.txt d'Albert).
- Fait : nouveaux `analysis/attempt_fields.py` (champs OOL par tentative) et `analysis/ool_transfers.py` (transferts
  recollés). Sorties : `analysis/out/c11_attempt_fields.txt`, `c11_lock_cycles.txt`, `c11_transfers.txt`, `c11_transfers/`,
  `c11_uart_timeline.txt`. Table : docs/messages.md section C11.
- Vu : 24 tentatives (12 correspondances, 6 refus, 6 abandons). Réponse 0x09 : 0x1f5 + identifiant dans 12/12 correspondances,
  0xffffffff + zéros dans 6/6 refus, y compris dans l'invite session ouverte (L6871 : 0x1f5 sans notif SKS -501 ni `<01/08` ;
  L7155 : -1). `+0xc24` : succès 1-4, bout du doigt 0x1e, mauvais doigt 0x29/0x2d/0x2e. Nouvelle commande 0x1e entre 0x07 et
  0x09 dans 4 tentatives où 0x07 avait `+0x06..07`=`00 00`. Abandons : `00 00` 6/6. `+0x44` identique pour mauvais puis bon
  doigt du même verrouillage. 0x54 / 0x6e / 0x7a et `> A 0x6d` d'init = C9 ; chaîne 0x21(N) = 0x09(N+1) 12/12. 7 exports
  0x6c complets (magic LTFC, ~8 bits/o, re-chiffrés à chaque fois). Série de 3 mauvais doigts : aucun `<01/45`, puis
  fp_good_locked = correspondance normale et UNLOCKED. Effleurements : tous reconnus (pas d'abandon). « lock change » : 33/33
  valeurs, 30/33 dans le même ordre. GeneratedUID ≠ identifiant 16 o (notes.txt).
- Interprété (hypothèses) : verdict dans 0x09 indépendant du keybag ; `+0xc24` = score (seuil 4/5) ; 0x07 `00 00` = acquisition
  faible, l'AP abandonne ou relance (0x1e) ; `+0x44` = compteur de session ; l'enregistrement est mis à jour à chaque
  correspondance et réexporté chiffré (0x6c).
- Incidents : aucun côté analyse.

## 2026-11-08 — Claude (session principale) — C10b : contrôle de persistance (HI/HO)
- Trace : traces/20261108-012015_c10b-boot-ool-stable (TRACE_TIMEOUT=300, config OOL de C9, aucun humain, aucun boot natif entre C9 et C10b).
- Vu : boot complet (hv_uart 2168 lignes, sep.log 779, 0 ool_error). `analysis/init_persist.py --ref C9` : réponses d'init 0x54 (0xbf4 o),
  0x6e, 0x7a = 0 octet différent de C9. Les 4 lectures `# ool` du `> A 0x6d` d'init ont les mêmes sha/nz que C9 (e87ef868, 7e50186d, fa51f810, 791868ac).
- Interprété (hypothèse) : sans succès entre deux boots, macOS renvoie le même blob 0x6d et le SEP rend la même 0x54 → cohérent avec HO
  (blob exporté par 0x6c après succès, conservé par macOS, renvoyé au boot). Ne distingue pas encore « 0x54 dérivée du blob » de « état SEP propre » :
  il faudrait un boot où macOS ne renvoie pas le blob, ce qu'on ne peut pas provoquer en phase 1 sans écriture.
- Incidents : aucun.

## 2026-11-08 — analyste — Correctif ool_index, test HO sur C9, invariants d'en-tête C5-C9
- Trace : traces/20261108-004657_c8-doigt-ool, traces/20261108-010915_c9-boot-ool-persist ; C5, C6, C7 pour les invariants.
- Fait : `analysis/ool_index.py` : les lignes `changed=none` sont maintenant rattachées au dernier .bin de même (buffer,
  longueur), comme la comparaison du tracer ; contrôle sha256[:8] de chaque contenu rattaché (`sha_ok`). Ancienne version :
  15 rattachements faux dans C8 (L1684, 2209, 2361, 2430, 2840, 2978, 3001, 3493, 3631, 3833, 3836, 3866, 4089, 4227, 4383),
  0 dans C5/C6/C7/C9 ; nouvelle : 0 faux sur C5-C9. Test synthétique ajouté (25/25 OK). `c8_ool_index.txt` régénéré ;
  `c8_ool_attempts.txt` inchangé (les charges des tentatives n'étaient pas touchées). docs/messages.md corrigé : en-tête
  TYPE 430/430 sans exception, `<fe` = B entièrement nul (14/14), répartition des notifications refaite.
  Nouveau `analysis/ool_invariants.py` → `analysis/out/c5_c9_ool_invariants.txt`.
- Vu (HO) : `> A 0x6d` d'init identique dans C5-C8 et **changé dans C9** : petit blob (0xf4) = export `< B 0x6c` de C8 L3250
  (même sha), gros blob 0x9317 o = longueur de l'export C8 L3226 (fp_good_3), 0x3e4 premiers octets identiques (seuls lus
  dans C8). `> A 0x5b` (0xfc99 o) identique C5-C9. `< B 0x5f` différent à chaque boot. Blobs 0x6c/0x6d : magic `LTFC`,
  u32 0x0a, uid, puis ~8 bits/octet.
- Vu (invariants C5-C9, 1695 lectures) : 0 violation sur `+0x00` ∈ {0,1} ⇔ nul, TYPE, longueur de morceau, `+0x0c`/`+0x10`=0 ;
  51 cas d'octets au-delà de la fin du morceau, tous = reste de la lecture précédente du même buffer.
- Vu (`+0xc24`, C6+C8) : pas une fonction de `+0x48`/`+0x07` de 0x06 ni de `+0x24` de 0x07 (C6, `+0x48`=0 : 5, 0x1b, 6, 0x1b).
  1er flottant de 0x07 (`+0x18`) : 0.040-0.048 pour les 3 mauvais doigts, 0.103-0.146 pour les 12 autres tentatives à 0x09 ou
  abandonnées (C6+C8) — confondu avec `+0x44`=5 / fin de session (réserve du sceptique).
- Interprété (hypothèse) : HO soutenue — le SEP exporte un blob chiffré par uid après chaque succès (0x6c), macOS le stocke
  et le renvoie au boot (0x6d) ; l'enregistrement 0x54 (HI) en dérive. Conséquence pour un futur driver : il devrait
  conserver et renvoyer ce blob. 1 boot, export lu tronqué : à confirmer (0x6c en lecture complète, C10/C11).
- Incidents : aucun (aucune action hardware).

## 2026-11-08 — Claude (session principale) — C10 : boot de contrôle bloqué
- Trace : traces/20261108-011515_c10-boot-ool-stable (TRACE_TIMEOUT=200, même config OOL que C9).
- Vu : hv_uart.log s'arrête à 806 lignes (C9 : 2631), dernière ligne `IOPort::registerService(): [Port-MagSafe 3@1] Regi` tronquée ;
  sep.log 256 lignes, 5 messages EP 0x08, aucune réponse 0x54/0x6e/0x7a ; 0 ool_error ; aucun panic dans l'uart. end_reason=timeout, proxy revenu.
- Interprété : boot de macOS bloqué ou très ralenti avant l'init SBIO ; cause inconnue. Capture inutilisable pour HI.
- Fait : relance (C10b) avec TRACE_TIMEOUT=300.
- Incidents : blocage de boot ci-dessus.

## 2026-11-08 — tracer — Script de session humaine C11 (outillage, aucune action hardware)
- Trace : — (protocole : docs/hypotheses.md « Revue sceptique de C8 », section « C10 — Session doigt », renommée C11 ;
  C10 = boot de contrôle traces/20261108-011515_c10-boot-ool-stable)
- Fait : `tools/guide_doigt_c11.sh` (forme de `guide_doigt.sh`). Étiquettes : loginwin, pw_login, lock_m1, fp_bad_1, fp_good_1,
  lock_m2, fp_tap_1..3, fp_good_2, lock_m3, fp_tip_1, fp_good_3, fp_app_prompt, fp_app_good, fp_app_quit, fp_app_prompt2,
  fp_app_bad, uid_check, end. Notes : res_* , uid_id_u, uid_generateduid, fin. Invite session ouverte : Réglages Système >
  Mots de passe (reverrouillée en quittant Réglages Système ; non vérifié sur ce Mac, repli = marque `anomalie`).
  Config recommandée en en-tête : SEP_OOL_EPS=0x08, SEP_OOL_BYTES=0x400, SEP_OOL_SPLIT_DIR=1,
  SEP_OOL_FULL_TYPES=0x09,0x21,0x45,0x54,0x5b,0x5f,0x65,0x6c,0x6d, TRACE_TIMEOUT=1500. `bash -n` OK. Non commité.
- Vu (lecture seule de hv/trace_sep_filtered.py) : 0x6c est accepté : SEP_OOL_FULL_TYPES passe par `_parse_eps` (toute valeur
  0..0xff) et `_ool_dump` teste `typ in full_types` ; seul EP 0x08 est concerné (SEP_OOL_EPS). Coût : 3 lectures B de 0x4000
  par succès ; plafond SEP_OOL_MAX_MB=64 non menacé (C8 : 2,7 Mo de .bin).
- Interprété : — . Point ouvert : la fin par `stop_capture.sh` = reboot() HV (arrêt non propre, piège (a) de HO) ; un arrêt
  propre de macOS avant le boot de test de persistance (C12 ?) est à décider par Albert.
- Incidents : aucun.

## 2026-11-08 — analyste — C9 : test HI (réponse 0x54 d'init après la session C8)
- Trace : traces/20261108-010915_c9-boot-ool-persist (boot sans humain, même config OOL que C7/C8, 0 `ool_error`, aucune
  tentative doigt) ; références : C5, C6, C7, C8 (init) et réponses 0x09/0x21 des 3 succès de C8.
- Fait : `analysis/init_persist.py` → `analysis/out/c9_init_persist.txt` (diff octet par octet, offsets dans la charge).
- Vu : requête `> A 0x54` (L554) identique à C5-C8. Réponse `< B 0x54` (L556, 0xbf4 o) : 24 octets différents de l'init
  C5/C6/C7/C8 ; 6 différents de la copie dans 0x09 de fp_good_3 ; **0 différent** de la copie dans la réponse 0x21 de
  fp_good_3 (C8 L3054 ; offsets 0x06-0x2d de l'enregistrement non comparables, recouverts dans 0x21). Même chaîne dans C8 :
  0x21 du succès N = 0x09 du succès N+1 (2/2). Les 3 essais mauvais doigt n'ont rien changé. Réponses d'init 0x6e (L572) et
  0x7a (L576) : identiques à C5-C8 (l'identifiant 16 o ne change pas).
- Interprété (hypothèse HI, une seule observation de boot) : l'enregistrement est conservé par le SEP au reboot et mis à jour
  à chaque succès ; 0x09 donne l'état avant, 0x21 l'état après. Lieu de stockage (xART ?) et sens des champs : inconnus.
  Ne passe pas en `vérifié` : à confirmer par le sceptique (ex. 2e boot sans succès : 0x54 doit rester égal à C9).
- Incidents : aucun.

## 2026-11-08 — lecteur-logs (intégré par l'analyste) — C8 : alignement hv_uart ↔ sep.log, chemins SKS doigt / mot de passe
- Trace : traces/20261108-004657_c8-doigt-ool (hv_uart.log, sep.log, marks.txt) ; recoupements C3 (traces/20261107-035930_c3-touchid)
  et C1 (traces/20261107-033436_c1-boot).
- Fait (lecteur-logs) : `analysis/uart_timeline.py` → `analysis/out/c8_uart_timeline.txt` ; rapport `analysis/out/c8_uart_align.md`.
  98 ancrages primaires (24 CRC xART, 45 TAG xART, 29 lock change SKS), monotones, 0 rejeté ; horloge Mac : PC − Mac ≈ +71546 s,
  dérive ~0.8 s/100 s (17 points), donc ±1 s pour les lignes ACMTRM.
- Fait (analyste) : recompte indépendant des points repris dans docs/messages.md (section « SKS (0x12) et xART (0x13) — C8 ») ;
  correction d'une ligne citée (2e déverrouillage mot de passe : L4287, pas L4288) ; `analysis/lock_cycles.py` lit maintenant
  `now=N(B)` (epoch = N + B ; C8 = secondes + base) et ramène l'heure Mac à l'heure PC (`--mac-offset auto`, via
  uart_timeline ; ignoré si < 2 s → sortie C3 inchangée) ; tests 24/24 ; `analysis/out/c8_lock_cycles.txt` régénéré (états
  écran enfin rattachés : LOCKED/UNLOCKED autour de chaque tentative).
- Vu : uart « Sending lock change X for handle H value V » ↔ `< EP=0x12 TAG=X TYPE=V DATA=H`, rang à rang : C8 29/29, C3 34/34,
  C1 6/6 (TAG=0x01 = verrouillage, 0x00 = déverrouillage). 2 « Saving USER-xART with CRC » (`< EP=0x13 TYPE=0x01 PARAM=0x9c`)
  par tentative atteignant 0x09, succès comme échec (6/6 ; C3 19/20), aucun dans les abandons. Le 2e `<01/09` d'un
  verrouillage suit de 1-4 ms le verrouillage keybag/volume (`> EP=0x12 TAG=0x2f` → 3 × `< TAG=0x01`) : C8 4/4, C3 3/4.
  Doigt : aucune requête AP 0x12 ; notif -501 émise par le SEP pendant 0x09, dans les 3 succès seulement (recoupe la
  réponse OOL 0x09 de l'analyste). Mot de passe : `> TAG=0x41 DATA=0x01c80000` puis `> TAG=0x18 DATA=0x007c0000` → -501.
  Échec doigt : aucune ligne noyau (ni erreur biométrique, ni keybag). Aucune ligne `AppleBiometric*`/`AppleMesa*` pendant
  les essais. `lock_g1` posée ~26 s avant le verrouillage réel.
- Interprété (hypothèses) : le SEP déverrouille lui-même le keybag 501 quand la comparaison réussit ; USER-xART = état
  sauvegardé à chaque comparaison (compteur d'essais ?), indépendant du résultat.
- Incidents : aucun (aucune action hardware).

## 2026-11-08 01:07 — analyste — Analyse C8 (session doigt, OOL allégé) : contenu des réponses 0x09/0x21/0x07
- Trace : traces/20261108-004657_c8-doigt-ool (sep.log, sep.log.ool/, marks.txt, notes.txt). Comparaisons :
  traces/20261107-035930_c3-touchid (séquences), traces/20261107-043828_c6-doigt-ool (OOL, 5 refus bon doigt),
  C5/C7 (réponse 0x54 de l'init).
- Fait : nouveaux scripts `analysis/sbio_latency.py`, `attempt_compare.py`, `ool_index.py`, `ool_attempts.py`
  (+ `analysis/tests/test_c8_tools.py`, synthétique ; 22/22 tests OK). Sorties : `analysis/out/c8_latency.txt`,
  `c8_attempts.txt`, `c8_lock_cycles.txt`, `c8_ool_index.txt`, `c8_ool_attempts.txt`, `c8_payloads/`, `c8_stats.txt`,
  `c3_c8_diff_ep08.txt`, `c6_ool_attempts.txt`, `c6_payloads/`. Table : `docs/messages.md` section C8.
- Vu (latence) : `# ool_stats` L4480 : 480 lectures, 0.45 ms moy. (max 1.50), 216 ms au total, 0 `ool_error`.
  Requête→réponse 0xfc : moyenne des paires < 50 ms = 3.62 ms (même définition : C3 2.35, C7 2.47) ; médiane 1.59 ms ;
  sur les seuls TYPE présents dans C7 : 2.17 ms (C7 2.21). L'écart vient des commandes doigt longues (0x07 ~20 ms,
  0x23 ~6.6 ms) absentes de C7 ; TYPE par TYPE, C8 ≈ C7.
- Vu (séquences) : séquence « succès » de 25 mots de C3 L2147 reproduite bit à bit dans fp_good_2 (L2399) et fp_good_3
  (L2968) ; fp_good_1 (L1698) : mêmes mots, `<03/00` avant `<fc 70`. 3 abandons `23 06 65 07 22` avant un succès
  (L1674, L2351, L2375). Mauvais doigt : 3 tentatives (L3621, L3687, L4217) = séquence échec de C3, + `2b` après `<fc 70`
  dans 2/3. 0x09 : succès 235-250 ms, échecs 277-303 ms.
- Vu (OOL) : en-tête commun de 0x1c octets (1, longueur totale, offset du morceau, 0, 0, TYPE, longueur du morceau).
  Réponse 0x09 (0xca2 o, 6/6) : succès 3/3 = 0x1f5 + 16 octets fixes `fe6003d8…371b` + copie de la réponse 0x54 de
  l'init (L556 ; 0xbf4 o, identique dans C5/C6/C7/C8) ; échecs 3/3 C8 + 5/5 C6 = 0xffffffff + zéros sur 0x40-0xbff.
  Réponse 0x21 = même contenu que 0x09 réarrangé. Réponse 0x07 : `+0x06..07` = `01 01` dans les 11 tentatives suivies
  de 0x09, `00 00` dans les 4 abandons (C8+C6). Requête 0x65 = 12 blocs de 0x980 o, en-tête de 0x17 o avec compteurs,
  corps à ~8 bits/octet, incompressible. Réponse 0x70 = magic `HRLB` + 0x48 octets à haute entropie. Le 0x1f répond `05 05`
  partout. Aucune notification n'a de contenu OOL propre.
- Interprété (hypothèses HE-HJ dans docs/hypotheses.md) : le résultat de la comparaison est dans la réponse 0x09
  (uid/identifiant/enregistrement si correspondance, -1/zéros sinon), le mot mailbox ne le porte pas ; `+0xc24` est un
  code ou un score (succès 2, 2, 1 ; mauvais doigt 0x2e ×3 ; C6 5, 5, 0x1b, 6, 0x1b) ; 0x07 décide abandon/comparaison ;
  0x65 = trames capteur chiffrées ou compressées (contenu non interprété).
- Limites : `lock_cycles.py` colonne « état écran » inutilisable dans C8 (horloge du Mac `now=504…992`, pas un epoch) :
  rattachement fait par les marques + notes.txt. Un seul utilisateur et un seul doigt enrôlé (supposé) : l'identifiant
  16 o ne peut pas être attribué (utilisateur, gabarit, appareil). 3 succès / 3 échecs mauvais doigt : petits nombres.
- Incidents : aucun (aucune action hardware).

## 2026-11-07 — tracer — Lecture OOL allégée (SEP_OOL_BYTES=0x400, types complets, une direction, cache IOVA→PA)
- Trace : — (aucune action hardware). Chiffres tirés de traces/20261107-043309_c5-ool-boot et
  traces/20261107-043828_c6-doigt-ool (sep.log lignes `# ool`, fichiers sep.log.ool/*.bin), et de C3
  (traces/20261107-035930_c3-touchid) pour la référence.
- Constat (mesuré par la session principale) : latence requête→réponse SBIO 2.35 ms (C3, ASYNC, sans OOL) →
  7.36 ms (C6, SYNC + SEP_OOL_EPS=0x08). Dans C6 le seul essai bon doigt a échoué (0x22 = abandon puis reprise,
  0x09 sans notif 01/08, puis 01/45), puis macOS s'est mis en veille (cause non établie). Lien avec la lenteur :
  possible, non établi.
- Vu (C5/C6, ce que j'ai recompté) : `elapsed_ms` = 1.83-1.94 ms par buffer (max 2.44), identique pour A et B,
  = 4 commandes de traduction + 1 readmem 0x4000 ; 2 buffers par message → ~3.7 ms, dont ~3.7 ms côté `>`
  avant que le message n'atteigne le SEP. Taille de contenu (dumps C6, mesure session principale) : 136 vides,
  234 < 0x400, 11 < 0x1000, 23 jusqu'à 0x4000 ; gros (>0x1000) : `> 0xfc|0xfd/0x65 A` (6+6), `> 0xfd/0x5b A` (3),
  `< 0xfc|0xfd/0x5f B` (2+2), `> 0xfd/0x6d A` (2), `> 0xfc/0x5b A`, `> 0xfc/0x6d A`.
  Recompte de la fin du contenu non nul dans les .bin : entre 0x400 et 0x1000 → `< B` TYPE 0x09 (0xcbe, 4/5),
  0x45 (0xcbe, 1/3), 0x21 (0xcaa, 5/5), 0x54 (0xc0f) — ces réponses seront TRONQUÉES avec le défaut 0x400.
- Vu (choix d'une seule direction) : `> B` = tout à zéro (sha 4fe7b59a = 0x4000 zéros) dans 71/73 (C5) et
  141/143 (C6) cas ; les 2+2 autres ont `changed=none` (identiques à la lecture `<` B précédente). `< A` :
  `changed=none` dans 78/78 (C5) et 156/162 (C6) ; les 6 autres sont une remise à zéro complète (sha 4fe7b59a).
  Donc lire A seulement sur `>` et B seulement sur `<` n'aurait perdu aucun contenu non nul nouveau dans C5/C6 ;
  seule perte : l'instant où A est remis à zéro (6 cas C6) et où B l'est (visible au `<` suivant).
- Fait (`hv/trace_sep_filtered.py`, rien dans m1n1, non commité) : SEP_OOL_BYTES défaut 0x400 ;
  SEP_OOL_FULL_TYPES (défaut 0x65,0x5b,0x5f,0x6d) = lecture de la taille apprise entière ; SEP_OOL_SPLIT_DIR
  (défaut 1 : `>`→A, `<`→B ; 0 = ancien comportement) ; traduction IOVA→PA en plages contiguës mise en cache par
  buffer (un readmem par plage contiguë ; invalidée sur erreur de lecture et sur CNTL 2/3/4/5 qui change
  IOVA/taille ; revalidée toutes les SEP_OOL_REVALIDATE_N=64 lectures → `# ool remap` si changée) ; ligne
  `# ool` + `full= xlat=hit|miss|reval rm= [trunc=1]` ; `changed` compare des lectures de même longueur ;
  `# ool_stats` (n, mean/max/total ms, octets, nb traductions, par direction) avant `# end`.
- Vérifié hors ligne : py_compile ; stubs m1n1 + faux DART t6000/RAM (scratchpad) : 1 readmem par lecture en
  cache, fusion de 2 pages contiguës en 1 plage (3 pages → 2 readmem), remap détecté, erreur → cache invalidé,
  `# ool_stats` cohérent.
- Estimation (NON mesurée) : en supposant ~0.12 ms par commande proxy et ~1.3 ms pour readmem 0x4000 (déduit de
  1.86 ms = 4 petites commandes + 1 gros readmem, répartition non mesurée), côté `>` : ~0.2 ms (TYPE courant)
  ou ~1.4 ms (TYPE complet) au lieu de ~3.7 ms → latence SBIO attendue ~3.9 ms (types complets ~5 ms), pas
  2.35 ms : le reste (~1.3 ms) vient des exceptions SYNC elles-mêmes, que ce changement ne touche pas.
- Risques : avec le cache, un remappage de l'IOVA sans message CNTL ferait lire l'ancienne PA (toujours vérifiée
  dans la RAM, lecture seule) jusqu'à la revalidation ; les réponses `< B` 0x09/0x21/0x45/0x54 sont coupées à
  0x400 (`trunc=1`) sauf à les ajouter à SEP_OOL_FULL_TYPES (coût après dépilement de la réponse, pas sur la
  latence requête→réponse).
- Interprété (hypothèse, non vérifiée) : TYPE 0x65 (`>` A, 12 fois dans C6, contenu jusqu'à 0x4000, absent de
  C5 sans doigt) = relais de données capteur AP→SEP. Repose sur une corrélation temporelle avec l'essai doigt.
- Incidents : aucun (aucune action hardware).

## 2026-11-07 — tracer — Option SEP_OOL_EPS (lecture seule des buffers OOL par endpoint, validée par Albert)
- Trace : — (aucune action hardware). Conçu d'après traces/20261107-042414_c4-shmem/sep.log L136-L144
  (`> EP=0x00 TAG=0x07 TYPE=0x04/0x02/0x05/0x03 PARAM=0x08 DATA=0x4000/0x54/0x4000/0x5c`) et L14-L23 (dart-sep
  `dart,t6000` sid 0, 0x4000 octets lus en 2.4 ms).
- Fait : `hv/trace_sep_filtered.py` (rien dans m1n1). Désactivé par défaut (SEP_OOL_EPS vide). Si actif :
  - apprentissage depuis `> EP=0x00` TYPE 2/3/4/5, EP cible = PARAM : A = (TYPE 2 → IOVA=DATA<<12, TYPE 4 → taille),
    B = (TYPE 3, TYPE 5) ; ligne `# ool learn` par valeur ; rien de codé en dur ;
  - INBOX et OUTBOX en SYNC toute la session (header `mode=SYNC(forcé par SEP_OOL_EPS)`) ; à chaque message
    (> et <) d'un EP de la liste, lecture de min(SEP_OOL_BYTES=0x4000, taille) octets de chaque buffer connu via
    SepDartReader (lecture seule, PA vérifiées dans la RAM, stream mémorisé par buffer) ;
  - ligne `# ool <ts> seq= EP= dir= buf= sha= nz= changed= len= elapsed_ms= [file=]` juste après la ligne du
    message ; `.bin` seulement si changement (`<SEP_TRACE_OUT>.ool/<seq>_<ep>_<buf>.bin`), plafond SEP_OOL_MAX_MB
    (64) → `# ool_cap` ; toute exception → `# ool_error`, le tracing continue.
  - `analysis/ool_view.py` + `analysis/tests/test_ool_view.py` (fixtures synthétiques `analysis/tests/fake_ool/`).
- Vérifié hors ligne : py_compile ; test avec stubs m1n1/hv et fausse mémoire + faux DART t6000 (scratchpad, non
  versionné) : apprentissage, init/changed/none, `.bin` seulement si changé, erreur contexte async, erreur TCR
  bypass sans arrêt, plafond, aucune écriture appelée. diff_ranges du tracer = celui d'ool_view (3000 cas
  aléatoires). Tests analysis : 19/19 OK.
- Interprété (hypothèses) : l'association TYPE 2/4 = A et 3/5 = B, et « un buffer par direction », viennent de
  l'analyste ; non vérifiées. seq = compteur `seen` de tous les messages (1 = premier), pas un numéro de ligne.
- NON TESTÉ sur le Mac : SYNC permanent des deux boîtes (coût par accès MMIO = aller-retour USB) ; durée réelle
  (estimation ~5 ms/message pour 2 × 0x4000, soit ~0.1-0.2 s par rafale SBIO de 25 messages) ; tolérance de
  macOS/SEP à ce ralentissement (timeouts possibles) ; cohérence des dumps : le SEP lit/écrit ces buffers et
  continue de tourner pendant la lecture (seuls les CPU du guest sont arrêtés), un dump peut être partiel.
  Moment : '>' avant que le SEP ne reçoive le message, '<' après dépilement par l'AP.
- Note : `boot_and_trace.sh` transmet l'environnement (SEP_OOL_EPS passe), mais meta.txt n'enregistre que
  SEP_EPS ; la config OOL est dans l'en-tête de sep.log.
- Incidents : aucun.

## 2026-11-07 04:35 — tracer — Option SEP_SHMEM_DUMP (lecture unique de l'en-tête shmem SEP, validée par Albert)
- Trace : — (aucune action hardware ; déclencheur choisi d'après traces/20261107-033436_c1-boot et
  traces/20261107-035422_c3-touchid/sep.log L13 `> EP=0xfe TAG=0x01 TYPE=0x1c DATA=0x00000580`)
- Fait : `hv/trace_sep_filtered.py` (rien dans m1n1). Désactivé par défaut. `SEP_SHMEM_DUMP=1` : au premier
  `> EP=0xfe` TYPE 0x1c ou 0x18, IOVA = DATA<<12 (hypothèse m1n1 hw/sep.py), lecture de 0x4000 octets via
  `/arm-io/dart-sep` → `<SEP_TRACE_OUT>.shmem_hdr.bin` + lignes `# shmem trigger|dart|hdr|table|entry|region|done`
  dans sep.log ; erreurs → `# shmem_error ...`, le tracing continue. `SEP_SHMEM_DUMP_FULL=<octets>` : dump de
  chaque région de la table (plafond par région, total ≤ 32 MiB). `SEP_SHMEM_WHEN=trigger|next`,
  `SEP_SHMEM_SYNC_MAX` (défaut 64 messages AP→SEP sans déclencheur → abandon).
- Vu (lecture du code m1n1, pas d'expérience) : en ASYNC le handler tourne dans `proxy.py reply()` pendant que le
  guest tourne ; une commande proxy à ce moment ferait entrer m1n1 dans `hv_tick` → USER_INTERRUPT → shell HV.
  Lecture mémoire possible seulement dans une exception (`hv.ctx` non nul). Donc avec SEP_SHMEM_DUMP=1, INBOX
  (écritures AP→SEP seulement) est tracé en SYNC jusqu'à la lecture, puis repasse dans le mode normal.
  En SYNC le handler tourne avant que m1n1 ne rejoue l'écriture INBOX1 : en mode `trigger` le SEP n'a pas
  encore reçu le message EP=0xfe quand on lit.
- Traduction DART refaite en lecture seule (TCR/TTBR par read32, PTE 8 octets, adresses vérifiées dans
  [hv.ram_base, +ram_size)), compatibles dart,t8020/t6000 seulement ; stream 0 essayé d'abord, puis les autres
  streams actifs. Aucune écriture SEP/DART/mémoire guest.
- Vérifié hors ligne : py_compile ; test avec un faux hv/DART/RAM (scratchpad) : table décodée, régions plafonnées,
  erreurs (contexte async, IOVA non mappée, PA hors RAM) → `# shmem_error`, retour au mode normal appelé.
- Non testé : tout sur le matériel (compat et stream de dart-sep sous 13.5, DATA<<12, format de la table côté
  macOS, mélange SYNC/ASYNC et bascule en cours de route, durée réelle, réaction du SEP à la pause).
  `boot_and_trace.sh` n'écrit pas SEP_SHMEM_* dans meta.txt (seule la ligne `# trace_sep_filtered start ... shmem=`
  de sep.log le note).
- Incidents : aucun.

## 2026-11-07 04:30 — analyste — Analyse de C3 (Touch ID : lock, mot de passe, bon/mauvais doigt)
- Trace : traces/20261107-035930_c3-touchid/ (sep.log 5841 lignes, 887 msgs EP 0x08 ; hv_uart.log 5264 lignes ; marks.txt).
  Capture avortée traces/20261107-035422_c3-touchid (login trop tôt, marque `abort_protocole_casse`) : notée, **non analysée**.
- Fait : nouveau script `analysis/lock_cycles.py` (états `LOCKED/UNLOCKED now=` de hv_uart + découpage des tentatives SBIO
  `0x23…0x21`) → `analysis/out/c3_lock_cycles.txt` ; `align_uart.py` → `analysis/out/c3_align.txt` ; rapport
  `analysis/out/c3_report.md` ; section C3 ajoutée dans `docs/messages.md`. Aucune action hardware.
- Vu :
  - Marques décalées : 11 LOCKED / 11 UNLOCKED dans hv_uart (uart L2089…L5233) pour 6 `lock_*` marqués ; plusieurs actions
    avant leur marque (LOCKED 616 vs `lock1` 596 ; unlock doigt 937-938 avant `fp_good_3`). Décalage Mac/PC < ~2 s
    (ancrages CRC uart L3397 ↔ L2158, L2778 ↔ L727). Aucun événement « buttonIndex » (Ctrl+Cmd+Q).
  - Chaque LOCKED (10/10) : `< 0x01/0x09 P2 0x1f5` puis `2b 2b 7d 2b` ; 30 s de lock sans doigt (616-646) : aucun 0x23.
  - Séquence `23 06 65 07 09 … 1f 22 0b 70 <03 21` identique bit à bit 8 fois (L2147…L4966), = C1 L1109, chaque fois avant
    un UNLOCKED. 12 tentatives sans UNLOCKED : pas de `<01/08`, pas de `0b`, 0x09 296-356 ms (vs 240-245). 2 abandons `23 06 65 07 22`.
  - Le 5e échec consécutif (cycle 1100) porte `<01/45` ×3 ; puis déverrouillage au mot de passe (L5723-5760, avec un `<01/08`).
  - fp_bad_1 a déverrouillé (L4966, UNLOCKED now=1097, uart L4942).
  - fp_prelogin et fp_noprompt : 0 message SBIO. SKS TAG 0x84/0x86 : PARAM 0xfd → 0x00 au login (L688 → L697), comme C1 et C2a.
  - Rafale `6b 79 6c 37 33 36 6c 37` ~15 s après chaque unlock doigt (5/5).
- Interprété (hypothèses) : `<01/09` + `2b…` = armement au lock ; 0x09 = comparaison, `<01/08` = correspondance ; le verdict
  succès/échec est visible dans le mailbox (pas seulement dans l'OOL) ; `<01/45` = blocage après 5 échecs (1 seul cycle).
  Quel doigt a produit les échecs : inconnu (marques peu fiables). Rien en `vérifié`.
- Incidents : aucun.

## 2026-11-07 03:50 — analyste — Analyse de C1 (boot + login mdp + lock + unlock doigt)
- Trace : traces/20261107-033436_c1-boot/ (sep.log 1865 msgs tous EP, hv_uart.log 3045 lignes, lecture seule)
- Fait : stats `analysis/parse_trace.py` ; nouveaux scripts `analysis/sbio_transactions.py` (paires 0xfc, fragments,
  rafales) et `analysis/align_uart.py` (ancrages sep.log ↔ hv_uart.log par TAG xART, CRC, handle SKS ; epochs macOS).
  Mise à jour de `docs/messages.md` ; chronologie et candidats dans `analysis/out/c1_report.md`.
- Vu :
  - 12 noms 0xFD = les 12 EP de la doc Asahi. CNTL `TYPE 4/2/5/3 PARAM=ep` pour 9 EP, même ordre que « SEP EP n enabled » (uart) ;
    DATA de T2/T3 suit exactement « + taille/0x1000 + 4 » sur les 9.
  - 36/36 « Replied to xART app » ↔ `> EP=0x13` par TAG (22 identiques bit à bit) ; 5/5 handles SKS du noyau ↔
    `< EP=0x12 TAG=0x00 DATA=handle` (L550, 639, 641, 697/1124, 1624).
  - Epochs macOS dans hv_uart : UNLOCKED `now=1794018972` (uart L2661, login), LOCKED `now=1794019015` (L2748),
    UNLOCKED `now=1794019020` (L2806, `lastDuration=5`). Lignes noyau sans horodatage.
  - SBIO : 100 % des messages 0xfc ont PARAM=0 DATA=0 ; 0x23/0x06/0x65/0x07/0x09/0x22/0x21 seulement à L1109-1145
    (03:36:59.9–03:37:00.4), encadrés par les ancrages xART L1122/L1140 entre LOCKED et UNLOCKED ; L1224-1247 (03:37:15) est
    ancré **après** UNLOCKED.
  - uart L2736-2739 : un seul événement « SMC HID buttonIndex=6 » press/release, juste avant le lock.
- Interprété (hypothèses) : login mdp ≈ SKS L632-642 (03:36:09–12) ; unlock doigt ≈ SBIO L1109-1145, 0x09 = candidat
  « match » ; la rafale de 03:37:15 est post-unlock (contredit l'alignement A de HC). Lock non isolé (écran verrouillé 5 s
  seulement ; lock probablement fait en appuyant sur la touche Touch ID). Rien en `vérifié`.
- Incidents : aucun (pas d'accès hardware). Un `sed` en lecture sur traces/ a été refusé par une règle ; refait en Python.

## 2026-11-07 ~03:50 — tracer — Repères (mark.sh), affichage direct, --between, étude OOL
- Trace : traces/20261107-033436_c1-boot/sep.log (lecture seule, pour l'étude) ; aucune capture lancée.
- Fait (aucune action hardware ; capture C2a de l'orchestrateur en cours pendant ce travail) :
  - `tools/boot_and_trace.sh.new` (PAS installé : le script tourne, bash le lit au fil de l'eau ; `mv` à faire
    par l'orchestrateur après la capture) : un seul `trap cleanup EXIT` (les deux traps précédents s'écrasaient) ;
    écrit `$REPO_ROOT/.current_capture` (ligne 1 dossier, ligne 2 PID du script), effacé en fin de capture s'il
    désigne encore cette capture ; mode AUTO : affichage direct `tail --pid=$$ -F sep.log | gawk` filtré par
    `LIVE_EPS` (défaut 0x08, `all`, `none`), validé avant tout accès au Mac ; `live_eps:` et `marks:` dans meta.txt.
  - `tools/mark.sh <étiquette>` : `date +%s.%6N` (CLOCK_REALTIME du PC = horloge du `time.time()` du tracer)
    → `marks.txt` du dossier en cours ; refuse sans capture, PID mort, dossier hors traces/, étiquette hors
    `[A-Za-z0-9._:-]+`. Ne source pas env.sh (aucun accès aux ports).
  - `.gitignore` : `.current_capture`.
  - `analysis/parse_trace.py --between E1 E2` : fenêtre [1re E1, 1re E2 après E1], bornes incluses, d'après
    marks.txt du dossier ; erreur rc=2 si marks.txt ou étiquette absents. Fixture synthétique
    `analysis/tests/fake_marks/`, 4 tests ajoutés : 15/15 OK.
- Vérifs : `bash -n` (boot_and_trace.sh.new, mark.sh), `py_compile`, tests unitaires ; pipeline tail/gawk testé
  sur un fichier factice du scratchpad (pas de tail/gawk orphelin après la sortie du script) ; mark.sh testé dans
  un faux repo du scratchpad (accepte / refuse les 5 cas). Pas testé sur une vraie capture.
- Vu (c1-boot, lecture) : `EP=0xfe TYPE=0x1c DATA=0x00000580` (L13) après `EP=0xff TYPE=0x06 DATA=0x4` (L12) ;
  m1n1 envoie SET_SHMEM = EP 0xFE TYPE **0x18** DATA=IOVA>>12 (`m1n1/proxyclient/m1n1/hw/sep.py:118-123`).
  EP 0xFD TYPE 1 : DATA 0x01010101 (0x08, 0x0a, 0x0c, 0x0e, 0x14, 0x17), 0x02020202 (0x10, 0x13, 0x18),
  0x02020404 (0x15), 0x02010201 (0x12), 0x00000000 (0x00).
- Interprété (hypothèses, rien de vérifié) : 0xFE/0x1c pourrait être l'équivalent 13.5 de SET_SHMEM (IOVA 0x580000
  si même décalage) ; les octets de DATA (0xFD/1) pourraient être des tailles/compteurs OOL par EP. m1n1 ne décode
  pas 0xFD TYPE 1 (`hw/sep.py:151-159` ne traite que TYPE 0) ; aucune source locale ne parle d'OOL.
- Incidents : deux commandes de test refusées par le système de permissions (création de mark.sh via heredoc ;
  test avec `rm -rf`/`sleep &`) ; refaites avec Write et des commandes plus simples.

## 2026-11-07 ~03:23 — Albert / Claude — 2e essai H2 réussi (client connecté)
- Trace : traces/20261107_h2-notrace-2/ (console.log 44 343 o ; hv_uart.log ~229 Ko, 3210 lignes à 03:25, boot complet)
- Fait : arrêt complet du Mac, démarrage à froid sur m1n1, chainload OK, run_guest.py sans tracer.
- Vu : PID run_guest.py vivant à 03:25:36, plus de déconnexion USB ; Albert : macOS tourne, lock / unlock Touch ID OK.
  Repérage rapide dans hv_uart.log (grep, comptes après masquage des nombres) : lignes `AppleSEPBooter ... SEP status: 2`,
  `AppleSEPXART (EP: 19) received unknown SEP request op 29` (×5), `AppleSEPXART ... Fetched SEP-xART Locker / USER-xART Locker`,
  `AppleBiometricSensor: loaded patch vers=22`, nombreux `AppleSEPKeyStore ... operation failed (sel: 7|17|23|75 ...)`.
- Interprété (hypothèses) : EP 19 = 0x13 (xART), cohérent avec la doc Asahi. Le chainload bloqué de 03:13 serait dû au
  redémarrage à chaud (le démarrage à froid a marché) — une seule observation, pas vérifié.
- Incidents : aucun pendant cet essai.

## 2026-11-07 ~03:13 — Albert / Claude — 3e essai : chainload bloqué au « Reloading into stub »
- Trace : — (sortie collée par Albert, non sauvegardée dans traces/)
- Vu : m1n1 réapparu en USB à 03:13:02 (1-1, ttyACM0/1), après une disparition à 03:09:54 (cause inconnue).
  chainload.py : copie SEPFW/preoslog/TrustCache, chargement, « Reloading into stub at 0x10010a90240 », puis
  `UartTimeout` sur la réponse à P_VECTOR. **Pas de déconnexion USB ensuite** (contrairement au 1er essai réussi,
  où le reload provoquait disconnect + reconnexion).
  Différences avec le boot de 02:52 dans la sortie du m1n1 installé : `Unknown payload at 0x100050b8000 (magic: 4d697373)`
  au lieu de `No more payloads`, et `pmgr: Enabling 0.ANS2 / 0.DEBUG` en plus. Sens inconnu.
- Interprété : aucune explication vérifiée. Ce boot venait d'un redémarrage à chaud après macOS-sous-HV ; un démarrage
  à froid est le premier test à faire.

## 2026-11-07 ~03:06 — Albert / Claude — 2e essai H2 avorté : mauvais port série
- Trace : — (rien capturé)
- Vu : un téléphone Samsung (CDC-ACM, branché 03:04:19) a pris /dev/ttyACM0 ; m1n1 est passé en ttyACM1 (if00, proxy)
  / ttyACM2 (if02, UART HV). chainload.py a parlé au modem du téléphone (réponses `+CME Error` / `OK`) → UartTimeout.
  Rien n'a été envoyé au Mac.
- Fait : `tools/env.sh` résout désormais les ports par `/dev/serial/by-id/usb-Asahi_Linux_m1n1_uartproxy_*-if00|if02`
  (fonction `refresh_ports`, rappelée par `require_mac`, donc après le chainload) ; ports notés dans meta.txt.

## 2026-11-07 ~02:53 — Albert (lancé) / Claude (lecture) — Premier essai H2, sans tracer
- Trace : traces/20261107_h2-notrace/ (console.log 46 237 o, hv_uart.log 6 497 o, 78 lignes)
- Fait : chainload.py -r m1n1.bin (OK, « Proxy is alive again »), puis run_guest.py macos/kernel.macho sans -m,
  bootargs de la doc. UART HV lu avec `sudo cat > hv_uart.log`, relancé une fois (le 2e `>` a écrasé le 1er : début du boot perdu).
- Vu :
  - console.log : kernel chargé (fileset OK), SEPFW copié, 10 CPU démarrés côté invité, puis `run_guest.py` meurt dans
    `hv_start` : `SerialException: device reports readiness to read but returned no data`.
  - Log noyau du PC : `usb 1-1: USB disconnect` à 02:53:24, ré-énumération 1209:316d (m1n1) à 02:53:25.
  - hv_uart.log continue à se remplir jusqu'à ~02:56 : logs macOS en espace utilisateur (triald, siri embeddedspeech,
    nearbyd, écriture nvram battery-health) et `AppleSEPKeyStore ... operation failed (sel: 7 ret: e00002c2 ...)`,
    `unexpected session: 100031 uid: -1`, une fois `sel: 75 ret: e00002ce`.
- Interprété (hypothèses) : macOS a continué à tourner sous l'hyperviseur après la perte du client Python ;
  le SEP répond aux requêtes keystore (erreurs probablement liées à l'absence de session utilisateur). À confirmer.
  Cause de la déconnexion USB : inconnue.
- H2 : Albert rapporte « le mac est lent mais le Touch ID fonctionne encore » → H2 confirmée une fois (observation humaine, voir hypotheses.md). Détails : écran verrouillé, 3 essais bon doigt OK, essais mauvais doigt faits (résultat non noté).
- Incidents : client proxy perdu ; aucun panic vu dans les 78 lignes conservées.

## 2026-11-07 — Claude (session principale) — Reprise du travail sur m1n1, kernel, commande H2
- Trace : —
- Décision (Albert) : on continue à travailler sur le clone m1n1 malgré `m1n1/CLAUDE.md` (licence MIT/GPLv2,
  usage privé, rien ne sort du repo). Les tâches suspendues plus bas sont reprises.
- Vu (code m1n1 70757dc7) :
  - `run_guest.py` charge la charge utile avec `hv.load_macho()` ; `m1n1/macho.py` gère les filesets (LC_FILESET_ENTRY), pas l'IMG4.
  - `macos/kernel.macho` parsé hors ligne par `m1n1.macho.MachO` : entry 0xfffffe00083f0540, 357 entrées fileset.
  - Doc Asahi m1n1-hypervisor : extraction img4tool en 2 étapes (équivalente à pyimg4), bootargs identiques à `MACOS_BOOTARGS`.
  - `asn1` est importé en tête de `m1n1/hv/__init__.py` → indispensable pour `run_guest.py`.
  - `chainload.py` préserve le SEPFW par défaut (`-n` pour ne pas le faire) : copie du blob + mise à jour de l'adresse dans l'ADT (`src/chainload.c`).
  - J'ai confirmé qu'aucun `SEPTracer` n'existe (`git log --all -S SEPTracer` ne renvoie rien), ce qui recoupe l'entrée du tracer.
- Fait : `tools/env.sh` → `M1N1_PYTHON` (venv `~/.venvs/m1n1` si présent, sinon python3), utilisé par `tools/*.sh` ;
  `boot_and_trace.sh` exporte `SEP_TRACE_OUT=$OUT/sep.log` et note `sep_eps`/`sep_lines` dans meta.txt ;
  `parse_trace.py` lit `<dossier>/sep.log` en priorité. Commande H2 manuelle écrite dans `docs/hypotheses.md`.
- Non vérifié : tout ce qui demande le Mac (chargement réel du kernel, tracer, H2).
- Incidents : aucun (aucune action hardware).

## 2026-11-07 — tracer — Localisation du « tracer SEP » m1n1, écriture de hv/trace_sep_filtered.py
- Trace : — (aucune action hardware, lecture de code + py_compile uniquement)
- Fait :
  - Recherche `SEPTracer` / `sep` dans `m1n1/proxyclient` (trace/, hv/, fw/, hw/) et dans tout l'historique
    git (`git log --all -S SEPTracer`, 2928 commits, clone non shallow, toutes branches distantes) :
    **aucun `SEPTracer` n'existe dans m1n1 public**, ni maintenant ni dans l'historique. Pas de `hv/trace_sep.py`.
    Seule mention : `proxyclient/hv/trace_mesa.py:5` (« sven's old SEP tracer »), code non publié dans le dépôt.
  - Ce qui existe côté SEP :
    - `proxyclient/m1n1/hw/sep.py` : `SEPMessage` (Register64 : EP 7:0, TAG 15:8, TYPE 23:16, PARAM 31:24,
      DATA 63:32 = doc Asahi), `SEP` (boot de SEPOS *par m1n1* : messages ROM EP 0xFF/0xFE, `BootRomMsg`,
      `BootRomStatus` ; découverte des noms d'endpoints EP 0xFD TYPE 0 → PARAM = n° d'EP, DATA = 4 caractères).
      Ce n'est pas un traceur : il écrit dans le mailbox (INBOX0 puis INBOX1=0). Hors périmètre pour nous.
    - `src/sep.c` : `sep_get_random` (EP 0xFF, cmd 16 → réponse 116), via `asc_init("/arm-io/sep")`.
    - `proxyclient/hv/trace_dart.py` : trace `/arm-io/dart-sep` (DARTTracer, verbose=3) parmi d'autres DART.
  - Le traceur générique applicable au SEP est `proxyclient/m1n1/trace/asc.py` :
    `BaseASCTracer(ADTDevTracer)` (l.100), `DEFAULT_MODE = TraceMode.SYNC`, regmap `ASCRegs` sur reg[0]
    (`hw/asc.py` : INBOX0 +0x8800, INBOX1 +0x8808, OUTBOX0 +0x8830, OUTBOX1 +0x8838, CTRL +0x8110/+0x8114).
    Hooks `w_INBOX1` (l.117, TX) et `r_OUTBOX1` (l.124, RX) → `handle_msg` (l.134) qui route par
    `r1.EP` = bits 7:0 **du mot 1**. `ASCTracer` (l.264) n'a que EP 0 Management et EP 2 Syslog.
  - Activation : pas de `-m` dédié. Il faudrait un script `run_guest.py -m` qui fait
    `ASCTracer(hv, "/arm-io/sep", verbose=N).start()` (modèle : `hv/trace_smc.py`, `hv/trace_aop.py`), ou
    `hv/trace_all.py` (trace tout `/arm-io` en ASYNC via PrintTracer, SEP compris).
    `run_guest.py` exécute chaque `-m` par `hv.run_script()` = `runpy.run_path(init_globals=hv.shell_locals)` :
    globales `hv, iface, p, u, trace, TraceMode` + toutes les méthodes de `hv` (`trace_range`, `trace_device`…).
  - `hv/trace_sep_filtered.py` écrit (repo projet, rien modifié dans m1n1, aucun commit m1n1) :
    sous-classe `ADTDevTracer`, ne trace que INBOX0/1 (écritures) et OUTBOX0/1 (lectures) de `/arm-io/sep`
    reg[0] (sous-pages de 0x10 octets, granularité 4 octets supportée par `src/hv/hv_vm.c`), mode ASYNC par
    défaut (`SEP_TRACE_MODE=SYNC` possible). Décode le mot 0 selon la doc Asahi, filtre `SEP_EPS`, écrit une
    ligne par message dans `SEP_TRACE_OUT` (défaut `traces/sep_<AAAAMMJJ-HHMMSS>.log`), flush toutes les
    0,5 s (`SEP_FLUSH_S`) + à la sortie, en-tête/fin en lignes `#`, un seul print console au démarrage.
    `ool=m1:0x…` = mot 1 brut, seulement si bits non nuls hors champs FIFO (40-56). Noms d'EP (0xFD/TYPE 0)
    recopiés en commentaire `# epname`, quel que soit le filtre. Aucune écriture, aucun HOOK, aucune injection.
  - `tools/reboot_mac.sh` : API vérifiée, correcte (voir Vu), seul le commentaire TODO remplacé.
- Vu (lecture de code) :
  - **Le traceur ASC générique décode mal le SEP** : le SEP porte l'endpoint dans le mot 0 (bits 7:0,
    `hw/sep.py`, `src/sep.c`) et m1n1 écrit INBOX1=0 → `handle_msg` routerait tout vers EP 0 et le décoderait
    comme `ManagementMessage` (TYPE = bits 59:52 du mot 0, `fw/asc/mgmt.py`), donc TYPE faux.
  - Sources du spam (si on applique `ASCTracer`/`trace_all` au SEP) : mode SYNC = chaque accès tracé
    remonte en Python par USB ; à `verbose>=2` deux lignes par message (`SEND:/RECV:` + ligne EP) ; à
    `verbose==2` chaque registre sans handler (polls de `INBOX_CTRL`/`OUTBOX_CTRL`, OUTBOX0…) est loggé ; à
    `verbose>=3` chaque accès MMIO ; `w_OUTBOX_CTRL`/`w_INBOX_CTRL`/`w_CPU_CONTROL` loggent toujours. Tout
    passe par `hv.log()` = `print()` console (+ fichier `-l`). `trace_all.py` loggue chaque accès MMIO du bloc.
  - Version macOS : aucun code SEP de m1n1 ne dépend d'une version de macOS (ni Big Sur ni Monterey
    mentionnés). Rien à « mettre à jour pour 13.5 » identifiable. Je ne sais pas si 13.5 change l'usage du mot 1
    ou l'ordre des accès.
  - API reboot : `m1n1/setup.py` (pas de `__all__`) définit `iface, p = M1N1Proxy(...), u, mon, hv` et
    reset le panic counter ; `M1N1Proxy.reboot()` (`proxy.py:834`) = `request(P_REBOOT=0x010, no_reply=True)`,
    traité par `src/proxy.c` → `reboot()`. `proxyclient/tools/reboot.py` fait exactement la même chose.
  - `m1n1/macho.py` gère `FILESET_ENTRY` (`load_fileset`) : `hv.load_macho` lit a priori un Mach-O fileset
    (répond en partie au « non vérifié » de la session 1 ; non testé).
- Interprété : le « tracer SEP actuel qui spamme » du CLAUDE.md n'est pas un fichier de m1n1 public ; c'est
  vraisemblablement l'`ASCTracer` générique (ou `trace_all.py`) appliqué à `/arm-io/sep` — hypothèse.
- Non testé (aucun accès Mac) : tout le comportement à l'exécution de `trace_sep_filtered.py` ; ordre
  INBOX0→INBOX1 / OUTBOX0→OUTBOX1 sous macOS 13.5 ; accès 64 bits (des accès 32 bits casseraient le décodage) ;
  `/arm-io/sep` reg[0] = base ASC sur j314c ; pertes d'événements en ASYNC sous charge ; contenu réel du
  mot 1 ; timestamp = heure PC de traitement, pas l'horloge du Mac. À noter : `boot_and_trace.sh` n'exporte pas
  `SEP_TRACE_OUT` → la sortie va dans `traces/sep_<stamp>.log`, hors du dossier de capture (suggestion :
  `export SEP_TRACE_OUT="$OUT/sep.log"` avant l'étape 3, à décider par Albert).
- Incidents : aucun.

## 2026-11-07 — Claude (session principale) — Session 1 : outillage hors hardware
- Trace : —
- Fait :
  - Clone `https://github.com/AsahiLinux/m1n1` (--recursive) dans `m1n1/`, branche `sep-touchid` créée
    sur le commit `70757dc7` (« kboot: fix M2 dcpext handling »). Submodule artwork : `80d14f8b`.
  - `./tools/build_m1n1.sh` : OK, `m1n1/build/m1n1.bin` = 5 046 272 octets. Le build compile `rust/`
    (cargo) même sans `CHAINLOADING=1`.
  - Dépendances proxyclient lues dans `m1n1/requirements.ini` : pyserial, construct, asn1.
    `asn1` absent du PC et des dépôts officiels Arch. SETUP-ARCH.md corrigé.
  - `albert` n'est pas dans le groupe `uucp` (sortie de `groups`).
  - Kernel : `macos/kernelcache` = IMG4 (IM4P `krnl`, `KernelManagement_host-354.140.3`, payload LZFSE `bvx2`).
    Extraction avec pyimg4 0.8.9 (venv jetable) : `img4 extract -p` puis `im4p extract`
    → `macos/kernel.macho` : Mach-O 64-bit arm64e, filetype=12 (MH_FILESET), 96 763 904 octets.
    sha256 kernelcache `8c62bae3…0c92`, kernel.macho `35695639…78a3`.
  - Agent analyste : `analysis/parse_trace.py` (`parse_file()` réutilisable, stats par EP/dir/type/param avec lignes sources, lignes invalides comptées), `analysis/diff_traces.py` (ensembles + `--seq` via difflib, TAG/DATA ignorés). Tests synthétiques dans `analysis/tests/` : 11/11 OK (relancés par la session principale). Pas encore testés sur une vraie capture.
- Vu : **les fichiers `m1n1/CLAUDE.md`, `m1n1/AGENTS.md`, `m1n1/GEMINI.md` déclarent que les mainteneurs
  de m1n1 interdisent tout usage d'outils IA/LLM sur le projet (« for legal reasons »)** et renvoient vers
  https://asahilinux.org/slop/. Ça dépasse le « ne rien soumettre à Asahi » du README.
- Décision : arrêt de tout travail d'agent qui lit en détail ou modifie le code m1n1 (tâche 3 : SEPTracer,
  `hv/trace_sep_filtered.py`, API de reboot ; tâche 2 : format attendu par `run_guest.py`),
  en attendant la décision d'Albert. Le clone et le build étaient déjà faits.
- Non vérifié : `run_guest.py` accepte-t-il le Mach-O fileset, ou le kernelcache brut ? Non lu.
- Incidents : aucun (aucune action hardware).

## 2026-11-07 — Albert — État du Mac avant la session 1 (rapporté par Albert)
- Trace : —
- macOS 13.5 installé sur le volume `macos13.5` (groupe de volumes EFF3C698-A740-4F41-AB86-99C85C0EB880), Touch ID enrôlé.
- `bputil -nkcas` + `csrutil disable` : `bputil -d` affiche « Security Mode: Permissive » (coih absent).
  Le déverrouillage Touch ID fonctionne dans ce mode (boot natif de macOS) → H1 réfutée.
- m1n1 compilé sur Asahi (`make ARCH=`) et installé par `kmutil` sur macos13.5 : démarre en mode proxy
  (« Running proxy... »). Le Mac s'identifie comme `apple,j314c`.
- Kernelcache 13.5 copié dans `macos/kernelcache`.
- PC : aarch64-linux-gnu-gcc, python-pyserial, python-construct, imagemagick, dtc, tmux, rustup
  + cible aarch64-unknown-none-softfloat.

## 2026-11-06 — Albert — Démarrage du projet
- Phase 1 (traces seules) décidée. Passage en phase 2 (kexts) si le jalon 1 est prometteur.
- Hôte : PC Ryzen sous Arch. Cible : MacBook Pro 14" M1 Max.
- Contrainte : hyperviseur m1n1 = macOS 13.5 uniquement → volume macOS 13.5 dédié au tracing.

## 2026-11-09 — documentaliste — SPI t6001 dans le DT public Linux
- Source : linux-asahi `asahi`, t600x-die0.dtsi, t600x-pmgr.dtsi, t600x-gpio-pins.dtsi, t600x-common.dtsi (lus en ligne).
- Vu : seuls spi1 (0x39b104000, IRQ 1107, clk_200m) et spi3 (0x39b10c000, IRQ 1109, clkref) sont décrits ; pas de
  spi0/spi2/spi4, même désactivés. Mais ps_spi0..ps_spi4 existent dans le PMGR. Pas de pinctrl spi2/spi4. Pas de mesa.
- Déduit (hypothèse) : pas de 0x4000 par contrôleur => spi2 = 0x39b108000, IRQ 1108. Rien en trace à ce jour. À lire dans l'ADT.
- Détail et lignes : docs/public_linux_state.md, section « 2026-11-09 — SPI t6001 ».

## 2026-11-17 — documentaliste — m1n1 proxy sans macOS 13.5 (doc publique)
- Question : obtenir un m1n1 mode proxy après DFU Restore (Asahi réinstallé UEFI-only, m1n1 déjà sur l'ESP,
  macOS 13.5 effacé, macOS 27.2.1 présent).
- Sources (lues 2026-11-17) : asahilinux.org/docs tethered-boot, m1n1-user-guide, m1n1-hypervisor, platform/introduction.
- Trouvé : le m1n1 dev est DÉJÀ installé (stage 2 = ESP `m1n1/boot.bin`). Voie recommandée = flag en recovery/1TR
  `csrutil disable && nvram boot-args=-v` SUR le volume Asahi → m1n1 attend 5 s → l'hôte ouvre le 2e port série
  (picocom-sec.sh) → proxy → `chainload.py -r build/m1n1.bin`. Plus besoin de kmutil ni de macOS 13.5.
  L'étape recovery (outils Apple, boot policy) = Albert à la main (ligne rouge).
- Voie Linux-only (remplacer `boot.bin` par un m1n1 sans payload → proxy auto) : plausible mais [déduit], non
  documentée, et « toucher à m1n1 » = Albert aussi.
- Changement de compréhension : la doc hyperviseur liste désormais macOS 14.8.3 (M1→M3) EN PLUS de 13.5 comme
  invité supporté ; macOS 27.2.1 n'est PAS supporté comme invité. « 13.5 only » (CLAUDE.md/README) est à mettre à jour.
- Détail et citations : docs/public_linux_state.md, section « 2026-11-17 — m1n1 proxy sans macOS 13.5 ».

## 2026-11-18 — analyste — Structure du blob re-scellé au SAVE (SERVE_GL)
- Source (lecture seule) : `traces/20261118-082622_xart_replay/follow_B/001_tag05_op01.bin` (maîtres croisés, nz=127),
  `…085250…/001_tag05_op01.bin` (maîtres corrects, nz=126), + rafales FOLLOW `…20261112-215313…` et `…223837…`
  (001..013). Comparé au coffre `traces/20261117-224724_xart_read/…74980DEE….gl.bin` (parse_gigalocker.py) et aux
  SAVE macOS de `traces/20261107-043828_c6-doigt-ool/hv_uart.log` (lignes 2002-2025).
- VU : le 1er SAVE est un SAVE-xART **maître** (TYPE 0x01) de ~127 o, haute entropie, **régénéré à chaque run**
  (0 octet constant sur 4 runs, têtes ≠ tous UUID du `.gl`). 127 o ≠ toute taille de slot du coffre (maîtres
  850/1344 o) → petite structure indépendante, pas une copie de maître. DATA du SAVE = `0x0100`+CRC-16 (recoupe
  « Saving … with CRC »). macOS normal persiste un enregistrement **complet** (gl_rec_write type 2) ; pas de blob
  de re-scellement macOS directement comparable en capture.
- INTERPRÉTÉ (hypothèse, non tranché) : faisceau penche vers « état neuf/défaut, anti-rejeu » (B) plutôt que
  « réparation de notre input » (A) — même 1er SAVE pour croisés / corrects / rejeu brut. Opaque = non prouvé.
- Détail et citations : docs/gigalocker.md, section « 2026-11-18 — Structure du blob RE-SCELLÉ ».

## 2026-11-19 — Claude (Opus 4.8) — Carte de doc + décision 13.5 + E1 sbio rendue concluante
Aucune expérience réelle (pas de Mac ce soir, Albert dans le bus). Travail 100 % hors hardware : rangement
doc, décision stratégique, outillage E1 validé par SELFTEST.
- **Carte de navigation créée** : `docs/INDEX.md` (agent bibliothécaire, lecture seule). Classe les 20 docs en
  4 familles + « par où commencer » + liste des recouvrements (handoff/journal, sources/annexe-sources, etc.).
  Rien déplacé/fusionné : la carte signale, Albert décide. Signalé : `CLAUDE.md`/`README` « 13.5 uniquement »
  périmé ; `agent-macos.md` statut `périmé?` ; bandeau `handoff.md` (17/11) en retard sur le journal (18/11).
- **Décision 13.5 (tranchée avec Albert)** : la partition macOS 13.5 n'existe plus (effacée au DFU) mais est
  recréable. **Pas recréée** : elle ne sert QUE au tracing macOS sous hyperviseur, et le match complet par sbio
  dépend de toute façon du lien SPI capteur + blobs scellés (voir voie_sbio §6). 13.5 = outil de *compréhension*,
  pas raccourci vers Touch ID. Invité hv possible = 13.5 OU 14.8.3 (pas 27.2.1). Mémoire mise à jour.
- **Voie sbio = seule piste vivante ; E1 rendue concluante** (sceptique + tracer, SELFTEST OK, Mac non touché) :
  - Sceptique : E1 **sûre** (aucun SAVE acquitté possible, fail-closed intact ; seules écritures en plus = tables
    DART côté AP). Mais un run E1 seul ne tranche pas → il faut un run de contrôle + idéalement le registre de faute.
  - Tracer : ajout d'une **lecture seule du registre de faute du dart-sep** (`DART_ERROR=0x40`, sid 27:24,
    READ_FAULT bit 4 ; source lecture m1n1 `hw/dart8020.py`/`src/dart.c`) avant/après le 0x73
    (`pending/sep_xart_replay.sh` l.462-479, 928-966) ; **lanceur de contrôle** `pending/probe_sbio_control_go.sh`
    (sans stream 15) ; **protocole en 2 runs** écrit dans `probe_sbio_stream15_go.sh` ; wording « (i) écartée »
    → « (i) fortement affaiblie ». Les deux SELFTEST passent, rien envoyé au SEP.
  - **Discriminant net** : au run de contrôle (sans stream 15), une faute de LECTURE neuve sur **sid 15** =
    preuve directe que le SEP lit l'OOL sbio via sid 15 (cause « canal »), même si sbio reste muet.
- **À FAIRE PAR ALBERT (au Mac, quand dispo)** : cold-boot + proxy m1n1 → `./pending/probe_sbio_stream15_go.sh`
  (E1) → cold-boot → `./pending/probe_sbio_control_go.sh` (contrôle) → comparer verdicts + lignes `[DART-faute …]`.
  Ligne rouge : c'est Albert qui lance (SERVE_GL). Backup données = `alarm_p5.img` (ne répare pas un SEP cassé).
- **Incertitudes notées (non affirmées)** : le DMA de l'OOL sbio passe-t-il vraiment par CE dart-sep ? la faute
  est-elle latchée ? décodage sid/causes à confirmer au 1er run réel. Détail : `docs/voie_sbio.md` §6.

## 2026-11-19 — Albert (runs) + Claude (analyse) — E1 + contrôle sbio : le silence n'est PAS le canal DART
- Source : 2 runs réels d'Albert sur le Mac (proxy m1n1 v1.6.1, SEP booté par m1n1, OS FW 13.5), boots frais,
  cold-boot entre les deux. `./pending/probe_sbio_stream15_go.sh` (E1) puis `./pending/probe_sbio_control_go.sh`
  (contrôle). catch_proxy sortait en exit 1 cosmétique (proxy up quand même, confirmé par les runs).
- VU — E1 (stream 15) : A8 mappé en sid **[0, 15]** ; 0x73 → **B8 nul, aucun msg EP 0x08** ; faute dart-sep
  `FLAG=0` avant/après. Contrôle (sans stream 15) : A8 en sid **[0]** ; 0x73 → **B8 nul** ; faute `FLAG=0`
  avant/après, **aucune faute de lecture sur sid 15**. Dans les deux : SERVE_GL va jusqu'au SAVE, arrêt sans
  acquitter (compteur non avancé), sbio (0x08) annoncé. (B du SAVE : nz=127 en E1, nz=126 en contrôle.)
- INTERPRÉTÉ : cause (i) « le SEP lit l'OOL sbio via sid 15 non programmé » **écartée par l'expérience**
  (ouvrir sid 15 ne change rien ; sans sid 15 pas de faute sid 15). Reste la cause **(ii)/(iii) : l'ÉTAT** —
  sbio annoncé mais pas armé, probablement tant que xART n'est pas scellé.
- Réserves : E1 n=1 (muet sans-stream-15 désormais n=4) → répéter E1 n≥3 pour clouer ; « aucune faute DART »
  suppose DMA sbio par ce dart-sep + faute latchée (non prouvé).
- CONSÉQUENCE : le test décisif de l'état = sceller xART, or sceller = acquitter SAVE = avancer le compteur =
  **écriture SEP = ligne rouge** (ce qui a bické en voie C). Décision Albert. Détail : `docs/voie_sbio.md` §7.

## 2026-11-19 (soir) — Albert (chat Asahi) + Claude — PALIER : Touch ID sous Linux CONFIRMÉ faisable
Albert a posé des questions GÉNÉRIQUES au chat Asahi (#asahi-dev, OFTC/Matrix). Réponses = témoignages de
**membres du board** (haute autorité, mais « non vérifié par nous »). Consigné verbatim dans `docs/sources.md`
§« Chat communauté Asahi ». Rappel règle : on tire l'info, on ne pousse rien (Asahi interdit les contribs IA ;
projet 100% Claude → [[asahi-ban-pas-secret]]).
- **James Calligeros (dev SEP du board)** : Touch ID sous Linux « **definitely possible** », « looked at » mais
  « not high on priority, extremely involved » ; « tracing SEP is excruciatingly slow, a massive time sink » ;
  « break gigalocker → you earn yourself a dfu restore ». → (1) **faisabilité confirmée** (fondation du projet
  acquise) ; (2) **terrain largement ouvert** ; (3) **tracer SEP = LE time-sink** (valide priorité tracer du
  CLAUDE.md) ; (4) casser gigalocker = **DFU-récupérable**. [[touchid-linux-faisable-james]]
- **« Michael Reeves »** : le danger DÉFINITIF = Secure Element **« Stockholm »** (séparé du SEP) touché en
  DIRECT (DFU n'aide pas) ; via le SEP = « should be fine but still risky ». On n'a aucun accès direct → notre
  classe = récupérable. [[stockholm-se-brick-definitif]]
- **« chaos_princess » (Sasha Finkelstein, board)** : casse le gigalocker exprès sur un mac mini sacrificiel,
  « still alive » → classe through-SEP récupérable.
- **Conclusion stratégique** : la route = **driver natif** (sbio ne s'arme pas en rejeu m1n1, mur d'état prouvé
  E1+contrôle ce soir) ; le but est **validé faisable** ; le risque est **borné** (through-SEP = DFU, permanent
  seulement via Stockholm direct qu'on ne touche pas). Ligne rouge SEP **maintenue** (justifiée par Stockholm) ;
  SAVE-ack **non fait** (gain borné). Prochain : définir le 1er pas concret de la route native + lire d'éventuelles
  notes prior-art Asahi (si James en pointe).

## 2026-11-22 — agent (étude DMA spi2, lecture seule) — mur DMA J5 : SIO Linux ≈ SIO macOS, il manque un slave_sg
- Sources : `~/kbuild/src/linux-asahi-7.2.12-3` (`drivers/dma/apple-sio.c`, `drivers/spi/spi-apple.c`, `spi.c`, DT
  t600x, `.config`), m1n1 `src/sio.c`, DT vivant `/proc/device-tree/soc/sio@39bc00000`, trace C19
  (`traces/20261110-002829_c19-spi-dma-boot/{sio.log,spi2.log}`, relue, non modifiée). Rien chargé, compilé ni envoyé.
- VU (C19) : le patch 0x568e part en **un seul `ISSUE` canal 0x18, un seul descripteur, un seul `REPORT`** ~23 ms après
  l'ACK (`sio.log:854-858`) ; TX seul ⇒ 0x19 inutilisé ; aucun `TERMINATE`/`NACK` sur toute la capture. Séquence
  spi2 relevée : `RXCNT=0, TXCNT=len, STATUS=0x400023, CFG=0x40042, CTRL=0xd` puis `CFG=0x40002, CTRL=0`
  (`spi2.log:820-850`).
- VU (DT vivant vs C19) : `apple,sio-firmware-params` Linux = mêmes clés/tailles que les `SETUP` macOS (dont dmashim
  `SSPI` et device-type `dSPI`) ; seules les IOVA diffèrent (+ shmem 0x1000 vs 0xaaa). Phandle `sio` = 0x38.
- DÉDUIT : layout descripteur Linux (offset 56, 48 o, DATA = 4×index) = celui lu par notre traceur (`+0x40+DATA*0xc`,
  ptr +8) ; `apple-sio` est cyclique seulement et rebouclerait (`sio.c:353`) ⇒ ajouter `prep_slave_sg`. Bug latent
  `desc_allocated` (2 o). rmmod/insmod d'`apple_sio` = SIO probablement mort jusqu'au reboot.
- Livrables : `docs/dma_spi2_design.md`, brouillon `driver/linux/patches/0001-spi-apple-dmaengine-draft.patch`
  (non appliqué ; dry-run OK). Chemin recommandé : forks hors arbre (spi2 par `compatible` propre + SIO via blacklist
  + reboot), précédé d'un essai « patch en PIO noyau ». Tout 1er run = go d'Albert. Statut : **hypothèses**.

## 2026-11-22 — Claude (Opus 5.5) — squelette `sep_native` (Rust) + overlay `sep_native_ovl` (C), compilés, jamais chargés
- Fait (hors matériel, rien chargé, rien envoyé) : `driver/rust/kmod/sep_native.rs`, `driver/linux/sep_native_ovl.c`,
  `driver/linux/sep-native-overlay.dts`, `driver/rust/kmod/SEP_NATIVE.md` ; option (b) de `docs/driver_rust_design.md`.
  Build : `build.sh` et `build.sh CLIPPY=1` sans avertissement ; overlay C compilé en W=1 dans le scratchpad ; vermagic
  `7.2.12-3-1-ARCH` ; tous les symboles indéfinis présents dans `Module.symvers`.
- VU (lecture de code public) : `GET_STATUS` = EP 0xFF TYPE 2 → 0x66 (m1n1 `hw/sep.py`) ; m1n1 mappe le firmware sans bit
  de protection DART (`src/dart.c`) alors que `sep.rs` utilise DMA_TO_DEVICE (→ NO_WRITE, `io-pgtable-dart.c:209`) ;
  `sep.rs::remove` passe l'adresse physique (et non l'IOVA) à `dma_unmap_resource` ; le Rust de cet arbre n'a pas de
  spinlock coupant les IRQ ni de `dma_wmb`.
- DÉDUIT : anneau RX atomique (1 producteur sous `mbox->rx_lock`, 1 work) au lieu d'un `SpinLock` ; DATA de 0x66
  contrôlée strictement (1 puis 2, `source: kext`). Statut : **hypothèses** ; 1er `allow_boot=1` = go d'Albert.

## 2026-11-22 — Albert + Claude (session ALARM, Opus 5.5) — J2 préparé : DT avec alias `sep` installé dans m1n1
- Go d'Albert pour J2 (option 2 : sans câble). Albert a lancé `sudo DTBS=~/kbuild/j2/t6001-j314c-sep.dtb update-m1n1`
  (« m1n1 updated at /run/.system-efi/m1n1/boot.bin », ESP /dev/nvme0n1p7 ; l'ancien est gardé en `boot.bin.old`).
- DTB = DTB du noyau 7.2.12-3-1-ARCH + `/aliases/sep = "/soc/sep@396400000"` seulement ; nœud `apple,sep` toujours
  `disabled` (sep.rs ne se lie pas). GRUB : aucune ligne `devicetree` (vérifié par Albert).
- Prochaine étape : reboot normal, puis docs/j2_runbook.md étape 4 (lecture seule, puis `allow_boot=1`).
- Retour arrière : `sudo update-m1n1` (DT stock). Secours : tethered boot (fichiers sur le PC, ~/alarm-recovery/j2).
- 17:58 (après reboot) : sep_native en lecture seule OK. Overlay appliqué (sepfw phys 0x1000550c000 taille 0x5b0000,
  mbox 0x35, DART sep 0x36 sid 0, ps 0x37). sep_native : manifestes lpol 0xb7b o / ibot 0x15cc o, shmem 0x30000 o à
  IOVA 0xfffc0000, magic « CINP », mailbox prise, allow_boot=0 → aucun envoi. Suite : rmmod puis allow_boot=1.
- 18:06 : **J2 RÉUSSI : SEPOS démarré depuis Linux natif par sep_native (allow_boot=1)**, sans câble.
  Séquence vue : GET_STATUS → 0x66 DATA 1 ; BOOT_TZ0 → 0x69 DATA 0, 0xD2 DATA 2 ; GET_STATUS → 0x66 DATA 2 ;
  fw mappé IOVA 0xff800000 ; BOOT_IMG4 (0x000ff800000600ff) + SET_SHMEM (0x000fff80001800fe) → 0x6A ; fw démappé.
  Découverte 0xFD : 7 EP — hibe 0x14 [1,1,1,1], stac 0x18 [2,2,2,2], cntl 0x00, xars 0x10 [2,2,2,2],
  xarm 0x13 [2,2,2,2], pnon 0x15 [7,7,5,5], hdcp 0x0e [1,1,1,1] (= SEP-BOOT sous m1n1, sans sbio/sks tant que
  xART n'est pas servi). CNTL spontanés 0x0d, 0x29, 0x10 (rien envoyé). xarm : 1re requête TYPE 0x0e reçue,
  NON servie. État final Running. Aucun ACK envoyé, aucun SAVE.

## 2026-11-22 — Claude (driver) — J4 étape 7 préparée : service xART dans sep_native + démon sepd (compilé, rien chargé)
- `sep_native.rs` : `allow_xart` (ouverture CNTL 0x13 SECMODE + A/B 0x8000 comme `sep_native_persist.sh`, puis
  `/dev/sep_native`) et `allow_xart_save_ack` (sinon SAVE → Halted). Noyau sans store ni politique : il contrôle chaque
  réponse du démon par `sep-proto/src/xart_gate.rs::check_reply` avant envoi. Détails : `driver/rust/kmod/SEP_NATIVE.md`.
- `driver/rust/sepd` : démon (store `/var/lib/sepd`, UUID d'OS dans `/etc/sepd/os_uuid`, absent → refus de démarrer).
  Tests : 30 paires 0x13 de snew-reel reproduites (mot + tampon A), branches natives ABSENT/SAVE testées hors ligne.
- Build : `build.sh` et `CLIPPY=1` sans avertissement, vermagic 7.2.12-3-1-ARCH. Aucun chargement, aucun matériel.
- 1er run `allow_xart=1 allow_xart_save_ack=1` = classe neuve pour ce pilote → go d'Albert.
- Correctif (demande de la coordination) : après ouverture de 0x13, messages des autres EP annoncés et annonces 0xFD
  journalisés et ignorés (comme le harnais m1n1), plus de Halted pour eux ; ligne « sbio annoncé » à l'annonce de 0x08.

## 2026-11-22 18:38 — Albert + Claude (session ALARM) — J4 étape 7 : xART servi nativement, **sbio et sks annoncés**
- Go d'Albert (session ALARM). Reboot propre (alias `sep`, `sepfw` réservé), puis `pending/j4_xart_run.sh` :
  sep_native allow_boot=1 allow_xart=1 allow_xart_save_ack=1 + sepd (store neuf vide, UUID 4c494e55580000…).
- Logs bruts : `logs/20261122-183847_j4-xart-native/{kernel.log,sepd.log}`.
- Vu : boot SEPOS OK (7 EP) ; ouverture CNTL 0x13 OK ; requêtes servies : 0x0e, 0x13 (UUID), FETCH maître → ABSENT,
  puis **12 SAVE acquittés** (maître t2 ×…, lockers ×4), un 0x07 acquitté. Aucun Halt, 0 message ignoré.
- **Annonces 0xFD après scellement : sbio (EP 0x08), skdl (0x17), sse (0x0c), scrd (0x0a), puis sks (0x12)** —
  = même résultat que le run m1n1 `native_persist`, cette fois depuis Linux natif.
- Store `/var/lib/sepd` : master_2.bin (420 o) + 4 locker_save_*.bin. Compteur scellé avancé de 12 (attendu).
- Suite : J3, ouverture de sbio (EP 0x08) et poignée 0x73 — demander d'abord la liste protocole vérifiée à c9.

## 2026-11-22 — Claude (driver, session ALARM) — J3 préparé : `allow_sbio` dans sep_native (compilé, rien chargé)
- `sep_native.rs` : `allow_sbio` (exige `allow_xart=1`) selon `docs/j3_sbio_open.md` : attente de `sbio` annoncé en 0x08
  et du xART calme (aucune requête en attente, 2 s sans mot 0x13), 4 CNTL PARAM 0x08 (A8/B8 0x4000, sans SECMODE),
  UNE poignée `> 0x08 TAG 0xfc TYPE 0x73` (A8 = `driver/rust/kmod/sbio_hello_0x73.bin`, copie de
  `traces/20261108-032454_c12-boot-ho/sep.log.ool/000300_08_A.bin`, embarquée), écoute 6 s, dumps de B8, ligne VERDICT.
  Porte d'envoi : 0x08 = ce seul mot, une fois. Détails : `driver/rust/kmod/SEP_NATIVE.md` point 8.
- `pending/j3_sbio_run.sh` (store en argument, défaut neuf `/var/lib/sepd-run-<horodatage>`). Question ouverte : servir
  le store J4 ou repartir neuf (à trancher avec l'orchestrateur). 1er run = go d'Albert.
- Build : `build.sh` et `CLIPPY=1` sans avertissement ; tests sepd et sep-proto verts. Aucun chargement, aucun matériel.

## 2026-11-22 18:56 — Albert + Claude (session ALARM) — J3 : xART SERVI depuis le store → accepté sans re-scellement ; ouverture sbio sans ack
- Go d'Albert. Reboot, puis `j3_sbio_run.sh /var/lib/sepd` (store du run J4 servi). Logs bruts :
  `logs/20261122-185633_j3-sbio-open/`.
- **Vu : FETCH maître t2 → SERVI (437 o = 0x11 + 420) ; maître t1 → ABSENT ; AUCUN SAVE** ; annonces 0x1d immédiates
  (sbio, skdl, sse, sks, scrd) ; 2 FETCH locker 0x05 (UUID 407e94c4f60495b3f2fbf5a8a31ae719, = nom d'un
  locker_save_ du run J4) → ABSENT (sepd ne re-sert pas les lockers), et le SEP s'en contente.
  ⇒ **le master scellé au boot précédent est accepté au reboot suivant (chaînage cross-reboot, n=1)**, et l'UUID du
  locker = les 16 premiers octets de B au SAVE (le nom de fichier concorde).
- sbio : xART calme 2 s, puis 1er CNTL d'ouverture `> 0x0000400008040600` (EP 0, TAG 06, TYPE 04, PARAM 08,
  DATA 0x4000) → **AUCUN ack en 5 s** → Halted (fail-closed). Rien d'autre envoyé à 0x08. Cause inconnue.
- 19:04 (J3 bis, reboot) : sepd sert aussi les lockers. Le SEP redemande le locker 407e94c4… deux fois → SERVI
  (106 o, PARAM 0x6a) ; 0 SAVE, aucune autre requête. sbio annoncé (0x1d puis 0xFD [1,1,1,1]). Ouverture CNTL 0x08,
  même 1er message `> 0x0000400008040600` → **toujours aucun ack en 5 s** → Halted. Logs :
  `logs/20261122-190438_j3b-sbio-lockers/`. L'hypothèse « lockers manquants » ne suffit pas.
- 19:20 (J3 ter, reboot, **store NEUF**) : seal frais (FETCH maître ABSENT, 12 SAVE), sbio annoncé, 2 s de calme,
  puis ouverture CNTL 0x08 TAG 06/07/08/01 → **les 4 ackés** ; 0x73 envoyé → `< 0x08 TAG 0x04 TYPE 0x00` puis
  `< 0x08 TAG 0xfc TYPE 0x73` ; B8 = version 1, opcode 0x73. **VERDICT sbio : VIVANT** (1re fois en Linux natif).
  ⇒ L'ouverture de 0x08 exige l'état « seal frais » : après un chaînage (master servi), le CNTL 0x08 reste sans ack,
  même avec les lockers servis. Tension persistance ↔ armement de sbio, à résoudre. Logs :
  `logs/20261122-192013_j3c-sbio-fresh/`.
- 19:57 (J3 chaîné + ouverture TÔT, store sepd-run-20261122-192013 servi, `j3_chained_run.sh`) : master t2 servi,
  0 SAVE ; dès l'ack du 0x1d 'sbio' → 4 CNTL 0x08 (TAG 06/07/08/01) **ACKÉS** (1re fois sur un boot chaîné : l'ouverture
  tôt débloque le CNTL, confirme le timing c12). Puis 2 s de calme, 0x73 → **MUET** (aucun mot 0x08, B8 vide en 6 s).
  ⇒ progrès partiel : sur un boot chaîné, le CNTL passe s'il est tôt, mais la poignée 0x73 envoyée 2 s plus tard ne
  répond pas. Logs : `logs/20261122-195701_j3d-chained-early/`.

## 2026-11-22 20:10 — Claude (analyste, session ALARM) — J3d relu contre c12 : le 0x73 arrive 26 s APRÈS l'ouverture, précédé de tout le trafic SKS 0x12
- Source : `traces/20261108-032454_c12-boot-ho/sep.log` (boot macOS chaîné), l. 126-318, comparé à `logs/20261122-195701_j3d-chained-early/`.
- VU (c12) : CNTL 0x08 ouvert à t=711.371 (TYPE 04/02/05/03, comme nous). Le `> 0x08 TAG 0xfc TYPE 0x73` part à t=737.730,
  soit **~26 s plus tard**. Entre-temps : skdl 0x17 ouvert, sks 0x12 ouvert (A/B 0x8000) puis **~25 échanges SKS 0x12**
  (TYPE 0x01→0x19, dont 0x09/0x0b/0x18), scrd 0x0a, pnon 0x15, et des FETCH locker 0x05 servis (PARAM 0x82/0xb6/0x01/0x28/0x7c/0x1f)
  + 2 SAVE locker. Le dernier mot avant le 0x73 = `< 0x12 TAG 0x99 TYPE 0x19 PARAM 0xfd`.
- VU (nous, J3d) : 0x73 envoyé 2 s après l'ouverture, **aucun trafic 0x12/0x0a/0x17/0x15** → 0x73 muet.
- INTERPRÉTÉ (hypothèse) : sur un boot chaîné, sbio ne répond au 0x73 qu'une fois le keybag chargé côté SKS (0x12) ; sur un
  seal frais il n'y a pas de keybag, donc sbio répond tout de suite. Ce n'est PAS un problème de délai (macOS attend 26 s).
  L'expérience qui tranche demande d'écrire en SKS 0x12 = classe jamais testée → protocole vérifié à demander à c9, puis go d'Albert.

## 2026-11-22 20:30 — Claude (session ALARM) — relecture complète du repo ; corrections de cohérence (rien lancé)
- `pending/j5_sensor_run.sh` (jamais lancé) : refuse un STORE non vide sauf `ALLOW_CHAINED=1` (boot chaîné = sbio
  gated, J3d) ; `sepd` tué par le trap à toute sortie ; libellé du critère 0x29 aligné sur le code (corps[8]).
- Docs alignées sur l'état réel : `SEP_NATIVE.md` (lockers re-servis, ouverture 0x13 exécutée par le pilote),
  `driver/README.md` (écritures SEP présentes derrière `allow_*`), en-têtes `j3_sbio_run.sh` / `j3_chained_run.sh` (lancés).
- Incohérence notée (non corrigée, à trancher) : `messages.md` dit SKS `TAG = commande, TYPE = compteur` ;
  `sks_sequence_c12.md` dit `TYPE = opcode séquentiel`. Même observation (TYPE +1 par requête) : l'opération est
  dans le DER (kext §15.2), le TAG reste à interpréter. Hypothèse ouverte : sur un état scellé par Linux (sans keybag
  utilisateur), sbio n'exige peut-être que l'ouverture 0x12 + négociation IPC, pas les 25 RPC de c12.

## 2026-11-22 20:12 — Claude (session ALARM) — avis c9 sur J5 ; Mac PAS encore rebooté
- c9 (session PC « Plan d'expérience sbio ALARM ») : séquence J5 VALIDÉE telle quelle (0x17 16→0, 0x15 4→40, 0x16 40→0,
  0x42 0→64, 0x18 64→0, 0x5f 2→22158 o ; trames SPI 0x72/0x73 ; prélude `80 60 00 07 00 00 00` + bloc en 1 transfert PIO ;
  verdict corps[8]==0x29). PRIORITÉ = J5 maintenant (sbio frais, pas besoin de SKS) ; SKS (persistance) ensuite.
- État : boot du Mac 19:55:58 (= boot de J3d), `sep_native` encore chargé → reboot du Mac requis avant J5.
- À la reprise (nouvelle session ALARM) : sur go d'Albert, `sudo pending/j5_sensor_run.sh` (store neuf par défaut).
- (Correction : l'entrée « 20:30 » ci-dessus a été écrite vers 20:10 ; l'heure était fausse.)

## 2026-11-22 20:16 — Albert + Claude (session ALARM) — J5 : relais capteur COMPLET en Linux natif jusqu'au patch ; patch REFUSÉ malgré un push en 48 ms
- Go d'Albert (reboot 20:13, lancé par Albert : `sudo pending/j5_sensor_run.sh`, store neuf). Logs bruts :
  `logs/20261122-201601_j5-sensor-native/` (console, run, sbiod, kernel).
- VU, côté SEP : seal frais (2 FETCH maître ABSENT, 12 SAVE acquittés, 0 ignoré), sbio VIVANT au 0x73 (n=2 en natif
  sur seal frais avec J3c).
- VU, relais : identité capteur OK (n° de série 0219c05c…d8) → 0x17 (16→0) → 0x15 (4→40) → trame SPI 0x72 (réponse
  0x33) → 0x16 (40→0) → 0x42 (0→64) → trame SPI 0x73 (réponse 0x4b) → 0x18 (64→0) → 0x5f (2→22158 o, fragments
  fe/fd réassemblés). **Toute la chaîne fonctionne en natif, 1re fois depuis Linux.**
- VU, push : état avant `80200010 00000000 60000000 52330000` ; prélude `80 60 00 07 00 00 00` puis bloc de 22158 o en
  **UN transfert PIO de 48 ms** (m1n1 : ~2,2 s ; macOS DMA : ~74 ms). IRQ 195 haute dès t+0, lectures d'état à zéro
  pendant ~1 s (capteur occupé ?), puis à t+1020 ms état `80200010 00000000 60000008 52330000` et IRQ retombe.
  **Octet d'état 0x60 → jamais 0x29 ⇒ VERDICT sbiod : patch refusé.** Même état final (variante `…08…`) que sous m1n1.
- INTERPRÉTÉ (hypothèse) : la vitesse/continuité du transfert n'est PAS la cause (48 ms < 74 ms macOS) → hypothèse
  « FIFO trop lent / trous d'horloge » **réfutée** (n=1). Le capteur reçoit, traite ~1 s, puis revient à l'état sans
  correctif avec le bit 0x08 levé (code de rejet ?). Pistes restantes : cadrage du bloc (prélude/longueur/trailer),
  étape manquante entre 0x18 et le push (comparer octet-près aux trames SPI de c17/c20), ou contenu lié à la session.
- Après le run : sepd tourne encore (lancé en root par Albert) ; SEP Running, rien d'autre envoyé. Power-cycle = Albert.

## 2026-11-22 21:00 — Claude (analyste) — J5 contre macOS (C17-C20), phase patch, octet par octet : une étape manque après le prélude
- Sources : `logs/20261122-201601_j5-sensor-native/sbiod.log:49-57` ; `traces/20261110-00{1859_c17,2417_c18,2829_c19,3201_c20}*/spi2.log`
  (registres spi2 + gpio0 195/196) et `sio.log`/`sio.bufs` (C18-C20) ; blocs complets de nos runs m1n1
  `traces/20261122-0*_native_sbio{6,7,8,9}/patch_reassembled.bin`. Outils : `analysis/sio_dialog.py --sep`, nouveau
  `analysis/spi2_gpio_timeline.py <trace> --patch` (chronologie spi2 + broche 195, mode décodé selon `pinctrl-apple-gpio.c`).
- VU, macOS, 8 pushes sur 8 (C17-C20, 2 passes chacun) : prélude 7 o → la broche 195, armée en « IRQ niveau haut »
  (`0x6a85`), est masquée (`0x6a81`) en même temps que la fin du prélude (C17 : DONE −1,5 ms et masque −1,5 ms) → **lecture
  d'état 0x10** (0x17 o) → **bloc** (C17 : 0,6 ms après cette lecture). Exemple C19 `sio.log:840-858` : état lu entre
  les deux = `…00 60 00 00 08 52 33 00 00` (C19 2/2 ; C20 2/2 donne `…00 60 00 00 00 52 33 00 00`).
- VU, nous (J5 et m1n1 sbio8/9/11) : prélude, pause fixe de 10 ms (`GAP_MS`, `driver/rust/sbiod/src/lib.rs:251`), bloc,
  **sans lecture d'état entre les deux**.
- VU, après le bloc chez macOS (8/8) : 195 réarmée juste après DONE, puis masquée 38 à 55 ms plus tard (1re passe : +63,8 à
  +64,8 ms après le début du bloc ; 2e passe : +83 à +84 ms) ; **une seule** lecture d'état, après ce masquage → `…29 01 00 7c…`.
  Aucune lecture avant. Nous : 1re lecture ≈3 ms après le bloc, puis une toutes les ~63 ms ; réponses tout à zéro pendant ~1 s.
- VU, débit : bloc macOS de START à DONE = 21,3 ms (C17, 22158 o) / 27,9 ms (C17, 28878 o), soit ≈8,3 Mbit/s, continu à
  8 MHz ; 24 à 34 ms sous le traceur DMA. Nous : 48 ms (≈3,7 Mbit/s). **Correction de l'entrée 20:16** : les « 74 ms macOS »
  comptaient l'attente de l'IRQ ; le vrai burst dure ~21-26 ms, donc notre PIO met environ 2 fois plus longtemps. L'hypothèse
  « trous d'horloge » n'est donc **pas** réfutée.
- VU, registres : la transaction du bloc a exactement les mêmes registres spi2 que les petites trames (CLKDIV 3, CFG
  `0x40042`, SHIFTCFG `0x80c07`, +0x00c = 0) ; aucun canal RX (0x19) n'est programmé pendant le bloc (`sio.log:855-858`).
  Nous : un seul `SPI_IOC_MESSAGE`, rx_buf = 0. Pas d'écart.
- VU, contenu : entrée 0x5f = `02 00` chez macOS (C12 `000313_08_A.bin`, `000357_08_A.bin`) comme chez nous ; taille 22158 o
  identique ; sur 4 blocs à nous, seules les positions 0-8 et 15-17 sont constantes (`8c 56 3a 00 00 00 00 00 00` … `00 56 6a`),
  et elles sont identiques à celles des blocs macOS. Le bloc porte le même en-tête `3a` + compteur que 0x73/0x55, décalé de 2 o :
  compteur du bloc = compteur du 0x73 + 1 chez macOS (4/4 : `…46ee`→`…46ef`, `…0056`→`…0057`, `…aa65`→`…aa66`, `…adfe`→`…adff`)
  et chez nous (5/5 : J5 `…e876`→`…e877`, sbio6-9 `…37fa`→`…37fb`, `…143f`→`…1440`, `…1190`→`…1191`, `…78f1`→`…78f2`).
- VU, états : avant le prélude, macOS et nous lisons le même état (`…60 00 00 00 52 33 00 00`). Notre état final
  `…60 00 00 08 52 33 00 00` est celui que macOS lit **entre le prélude et le bloc** (C19).
- INTERPRÉTÉ (hypothèse) : le prélude lève l'IRQ (événement « prêt pour le patch », bit 0x08 ?) et macOS l'acquitte en lisant
  l'état avant d'envoyer le bloc. Nous ne l'acquittons pas : l'IRQ « haute à t+0 » de J5 serait cette IRQ du prélude, pas une
  fin de chargement. Notre état final ressemble à « prélude pris, bloc jamais terminé ». Deuxième écart possible : nos lectures
  d'état pendant que le capteur traite le bloc (macOS n'en fait jamais). Le débit deux fois plus lent vient en troisième.
  Rien n'indique un problème de session ou de compteur.
- Expérience proposée (sceptique/driver) : même route J5, push modifié comme macOS : prélude → attendre 195 haute (≤ 50 ms)
  → 1 lecture d'état (en-tête valide attendu, 195 doit retomber) → bloc sans pause → ne rien lire avant que 195 remonte (≤ 300 ms)
  → 1 seule lecture. Si `29…7c` : écart trouvé. Sinon : refaire la même chose en DMA (débit).

## 2026-11-22 — Claude (driver, session ALARM) — sbiod v2 : push du patch « comme macOS » (compilé, rien lancé)
- Contrôle de l'analyse (c19 `sio.log:836-858`, VU) : après le prélude `80600007…` (seq 758 done), macOS envoie `8010…`
  et lit 0x17 o d'état (seq 761/763), PUIS le bloc `8c563a…` 0x568e (seq 765). Écart confirmé avec J5 v1.
- `driver/rust/sbiod/src/lib.rs::push_patch` réécrit : prélude sans pause → attente IRQ 195 (≤ 50 ms) → UNE lecture
  d'état (stop si non reconnue) → bloc en un transfert, sans pause → AUCUN SPI : si IRQ encore haute, attente qu'elle
  retombe, puis qu'elle remonte (≤ 300 ms chacun) → UNE lecture (0x29 = chargé) ; sinon une lecture tardive à +500 ms
  (diagnostic). Rien de neuf émis vers le SEP ; côté capteur, seule la lecture d'état (déjà émise des dizaines de fois)
  change de place.
- Tests : faux capteur durci (n'accepte que si l'état est lu entre prélude et bloc) ; ordre des trames vérifié
  (prélude, état, bloc, état, rien d'autre) ; sbiod 4/4, sep-proto verts, clippy 0. Binaire installé dans
  `~/kbuild/j5/sbiod` (sha256 a2b40c01…), ancien gardé en `sbiod.v1` (5be67e47…).
- 1er run v2 = go d'Albert ; power-cycle d'abord (le SEP et sepd du run v1 tournent encore).

## 2026-11-22 20:43 — Albert + Claude (session ALARM) — 🎯 J5 v2 : PATCH CAPTEUR CHARGÉ en Linux natif (0x29)
- Go d'Albert (power-cycle, puis `sudo pending/j5_sensor_run.sh`, store neuf, sbiod v2 sha256 a2b40c01…). Logs bruts :
  `logs/20261122-204249_j5b-patch-loaded/`.
- VU : seal frais, sbio VIVANT, relais 0x17 → 0x15/0x72/0x16 → 0x42/0x73/0x18 → 0x5f (22158 o) comme v1. Puis :
  état avant `80200010 00000000 60000000 52330000` ; prélude → IRQ 195 haute à t+0 ; **lecture d'état entre prélude
  et bloc** = `…60000008 5233…` (= ce que macOS lit en C19 au même point) ; bloc en un transfert, **29 ms**, IRQ basse
  avant ; IRQ remonte à **t+43 ms** (macOS : 38-55 ms) ; une lecture : **`80200010 00000000 2901007c 52330016`**.
  **Octet d'état 0x60 → 0x29, marqueur `29 01 00 7c` = « correctif chargé » (sensor_hw.md, sbio_session.md Q4).**
  VERDICT sbiod : patch chargé. Capteur éteint ensuite.
- ⇒ Le mur du patch (bloquant sous m1n1 depuis sbio6) est tombé : la cause était la **séquence** (lecture d'état
  manquante entre prélude et bloc + lectures pendant le chargement), PAS le DMA. Statut : n=1 → à reproduire pour
  `vérifié` (le sceptique tranche) ; l'hypothèse « débit » est sans objet pour le chargement (PIO 29 ms suffit).
- Suite (J5 étape 2) : params 0x5d/0x5c/0x55 (+CRC16) et calibration 0x5b — liste blanche à étendre (après 0x5f,
  rien n'est autorisé aujourd'hui) ; protocole vérifié à demander d'abord (session PC).
