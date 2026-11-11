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
