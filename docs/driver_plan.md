# Plan d'architecture d'un futur pilote Linux Touch ID (j314c) — phase 2, document de planification

2026-11-08 — driver. **Aucun code, aucune action hardware.** Synthèse de ce qui est déjà documenté ; rien de nouveau n'est
établi ici. Statuts : `vérifié` = proposé `vérifié` dans « Confrontation kext ↔ traces » de `docs/hypotheses.md` (K1-K7)
**mais la décision revient à Albert** (CLAUDE.md) ; tant que `docs/messages.md` n'est pas mis à jour, on les traite comme
« vérifié (macOS) ». `hypothèse` = lecture de kext ou de trace sans expérience. `inconnu` = rien de documenté.
Référence courte : KS = `docs/kext_sepmanager.md`, M = `docs/messages.md`, H = `docs/hypotheses.md`, P = `docs/public_linux_state.md`.
Rappel : le driver ne s'écrit qu'à partir de messages `vérifié` ; ce plan liste donc aussi ce qui manque pour y arriver.

## 1. Composants et messages dont ils dépendent

### C-A. Nœud DT + pilote client SPI du capteur (Mesa / SandDollar)
Rôle : alimentation, reset, lecture du statut, lecture des trames d'image (0x7200 o), exécution des commandes capteur que
le SEP demande (GetSerialNumber, SessionKeyExchange, InitializeSequenceCounter, Patch…). L'AP ne fabrique rien (KS §7).
- Nœud DT : le capteur est un périphérique SPI ordinaire sous un contrôleur de l'AP, compatible ADT `biosensor,mesa`
  (hypothèse, source: kext + m1n1 trace_mesa.py, M « Capteur (Mesa) », P §2.3). **Contrôleur : spi2, 8 MHz, IRQ gpio0 195, alim gpio0 0xc4 (ADT-1, 2026-11-08) ; chip-select/phase/reset : inconnus** (P §2.2 : aucun nœud dans linux-asahi, à lire dans l'ADT).
- Transport : `spi-apple` mainline (P §2.1), sans DMA ; macOS passe par SIO (P §2.3). 0x7200 o en PIO : possible, non éprouvé (inconnu).
- Trame capteur `[0x80][opcode][index][u32 LE longueur][charge]`, lecture d'image = trame `80 13 00 0b000000 <size>` puis lecture de
  `size` o (hypothèse, source: kext). Contrôle : 12 tranches de 0x980, CRC-16/ARC en fin de tranche (**vérifié (macOS)**, K4, 39 images / 468 tranches).
- Machine d'état de déclenchement : octet d'état = 7 → données disponibles (hypothèse, source: kext).
- Chiffrement : commandes et image chiffrées après l'échange de clé de session ; la clé vient du SEP, l'AP la transporte
  (hypothèse, KS §7.B.3). Format interne du statut complet : inconnu (M, « Statut au démarrage »).
- Reset/alimentation via l'AOP (`function-mesa-reset-ntfy`, commandes AOP 0x20/0x21) : hypothèse (source: kext) ; **rien de public sous Linux** (P §3, P « Ce qui en découle » 3). Interface exacte : inconnu.

### C-B. Transport mailbox SEP + endpoint 0x08 (`sbio`) avec buffers OOL A/B
Rôle : parler à l'ASC/mailbox SEP, découvrir les endpoints, ouvrir `sbio`, fragmenter/réassembler les transferts GT.
- Mot mailbox : bits 0-7 EP, 8-15 TAG, 16-23 TYPE, 24-31 PARAM, 32-63 DATA (CLAUDE.md, KS §1, P §1.4) : **vérifié** (M « Contrôles de cohérence », C1).
  L'AP pose l'octet EP lui-même ; états de boot : seuls EP 0xFE/0xFF acceptés (hypothèse, KS §1).
- Découverte EP 0xFD : `< 0xFD TYPE 0x00 PARAM=n DATA="sbio"` ; `TYPE 0x01 DATA` = quatre octets de tailles OOL (min/max envoi,
  min/max réception ; pages de 0x4000 ici). Annonces vues 12/12 (M « Endpoints », C1) ; sens des octets : hypothèse (KS §4). Pas de table
  statique : chercher le nom, ne pas coder 0x08 en dur (hypothèse, KS §4).
- Ouverture d'un endpoint via CNTL (EP 0x00) : `T4` (taille envoi) `T2` (adresse envoi >>12) `T5` (taille réception) `T3` (adresse réception >>12),
  PARAM = n° d'EP, chaque message acquitté (TYPE 1, même tag). Observé C1/C11/C12 ; sémantique A = AP→SEP, B = SEP→AP : hypothèse (source: kext, KS §3, §5).
  Rien n'est envoyé à l'EP 0x08 pour l'ouvrir ; la 1re commande est 0x73 (KS §5.4, hypothèse).
- Allocation des buffers : l'AP alloue deux tampons 0x4000 visibles du SEP (IOVA via DART SEP). Équivalent Linux (DART `sep_dart`, IOVA) : inconnu à tester ; l'écart de 4 pages observé n'est pas expliqué (KS §5.3).
- Encodage GT : TAG ∈ {0xfc, 0xfd, 0xfe}, TYPE = commande, PARAM = 0, DATA = compteur << 16, compteur remis à 0 à chaque transfert et par sens ;
  rôle fc = premier paquet, fd = suivant, fe = accusé/demande du suivant : **vérifié (macOS)**, K2 (4006/4006 messages, 14 traces). Morceau de 0x3fe4 o de charge dans le tampon de 0x4000, en-tête OOL
  (`+0x00` = 1 si valide, TYPE, longueur) : vérifié par invariants (M « 0x6c/0x6d… », 1695 lectures) mais statut formel `vu`. Transaction max 0x4b000 (hypothèse, KS §5.1). TAG 0xff : jamais vu, non élucidé.
- Notifications TAG < 0xfc passées au client : `0x01` (DATA = uid, TYPE + PARAM·0x100 = lockState) — `<01/09 p2` à chaque verrouillage **vérifié (macOS)** K1 ; reste = hypothèse (sens des bits : KS §6, inconnu pour 3, 4, 6, 9).
  `0x03` → l'AP répond `> 0x21` : **vérifié (macOS)** K5 (50/50). `0x04` : inconnu (sens). `0x02` : inconnu. `0xfb` : jamais vu.
- Séquence d'init SBIO (57 premières commandes identiques sur 8 boots) : **vérifié (macOS)** K6 ; attribution fonction-kext → sous-séquence : hypothèse avec 3 écarts (0x01, 0x6f, 0x61).
- Prérequis CNTL (SECMODE 0x14, « OS actif » 0x0d/0x15 avant tout autre envoi) : hypothèse (KS §3). Messages de boot EP 0xFF/0xFE : voir §3, hors périmètre agent.

### C-C. Relais des commandes capteur et de l'image (0x65)
Rôle : le SEP demande des opérations sur le capteur ; l'AP les exécute sur SPI et renvoie le résultat via sbio.
- Init capteur (KS §7.B) : `0x17` (n° de série lu sur le capteur) → `0x15`/`0x16` (clé de session emballée par le SEP, 40 o aller-retour avec le capteur) →
  `0x42`/`0x18` (compteur de séquence) → `0x5f` (patch fourni par le SEP, 0x568e/0x70ce o, différent à chaque boot) → `0x01` ; `0x19` reset puis 2e passe. Ordre : vérifié (macOS) K6 ; rôles : hypothèse.
- Capture/match (KS §7.C, M C11) : `0x23` → `0x06` (entrée 0xa7 o `_lastImageProcessingParams`) → `0x65` (image 0x7200 o, lue sur SPI, recopiée par l'AP) → `0x07` → [`0x1e`] → `0x09` (sortie 0xca2 o, `+0x00` = uid ou −1) → `0x1f` → `0x22` ; `<03` → `>21`.
  Séquence et tailles `0x65` : vérifié (macOS) K4/K5 ; `0x1e` (relance après 0x07 défavorable) : hypothèse ; `+0xc24` du 0x09 (code d'échec/qualité) : hypothèse ; `0x09` `+0x14` : non testé (K3). Origine des 0xa7 o de `0x06` : **inconnu**.
- `0x27`/`0x25` (commandStartMatch) : absents des traces (vérifié, K7) → ne pas implémenter. Enrôlement (`0x03`, etc.) : jamais observé, inconnu.
- Chiffrement du corps des tranches (~8 bits/octet) : hypothèse (H « HH ») ; l'AP n'a pas à le déchiffrer si le relais est transparent (hypothèse).

### C-D. Démon userland : garde et renvoi des blobs (catacomb 0x6c → 0x6d, calibration 0x5b, lockout 0x70/0x71)
Rôle : remplace biometrickitd pour les blobs que le SEP exporte et réclame (le SEP ne stocke pas ses gabarits lui-même).
- `0x6c` export après chaque succès doigt (blob ~0x9200-0x9461 o + petit 0xf4 o uid −1, magic `LTFC`, scellé) ; `0x6d` import à l'init (2×, petit puis gros) ; C9 : le `0x6d` rejoue exactement le dernier `0x6c` de C8
  (M « 0x6c/0x6d… », C9, C11, C12) : comportement observé, **vérifié (macOS) pour la boucle export→import** (reproduit C9, C11, C12) ; statut formel dans messages.md à confirmer par Albert.
- Que le SEP accepte un `0x6d` rejoué depuis un autre OS/boot (lié à la clé du SEP, pas de l'AP) : **inconnu** (rejoue observé uniquement sous macOS).
- `0x5b` calibration : blob fixe de 0xfc99 o identique C5-C9, signé, lié au n° de série capteur (hypothèse, KS §7.B.7). Où le prendre sous Linux : inconnu (extraction depuis le disque macOS = lecture d'un fichier utilisateur, à cadrer par Albert).
- `0x70`/`0x71` BioLockoutRecord (`HRLB`) : nécessité inconnue (KS D5). `0x54`, `0x6e`, `0x7a`, `0x2b`, `0x33`, `0x36`, `0x39`, `0x28`, `0x7c`, `0x7d`, `0x0b`, `0x40` : requêtes pilotées par biometrickitd ; nécessité pour un match inconnue (KS §7.B.9). Le `0x09` N+1 reprend la copie `0x21` du succès N (12/12, hypothèse « chaîne »).
- Enrôlement sous Linux (création de gabarits) : inconnu, autre chantier.

### C-E. Interface vers libfprint / PAM
Rôle : exposer l'authentification. Aucune dépendance protocolaire nouvelle ; mais :
- Le résultat de match est `0x09 +0x00` = uid (0x1f5 = uid Unix 501 : vérifié par `id -u`, M C11) ou 0xffffffff ; le mapping uid SEP ↔ compte Linux : inconnu pour d'autres comptes (un seul compte testé).
- Pas de verdict biométrique dans TAG 0x01 (vérifié (macOS) pour le sens « keybag », K1) ; ne pas s'en servir comme succès.
- Forme de l'interface (périphérique char/sysfs du noyau vs. démon unique parlant à libfprint, driver libfprint de type « SEP » avec l'image jamais exposée) : **décision d'architecture ouverte**, rien de documenté. Proposition : le noyau expose un nœud de contrôle simple et un démon traduit pour libfprint/PAM, car le SEP ne rend jamais l'image à l'AP (les images vont à destination du SEP seulement).

## 2. Dépendances hors sbio (SKS / xART / keybag)
- Lecture KS §7 D2 : lockState au boot = 0x0015 (blocage bio) jusqu'à « code validé » (0x0228, 1 ms après une réponse SKS EP 0x12). **Inconnu : le SEP refuse-t-il `0x09` sous blocage bio ou macOS s'abstient-il seulement.** Candidat bloquant n°1.
- SKS (0x12), xART/gigalocker (0x13/0x10), boot policy (0x15) : structure et alignement noyau en aperçu (M « SKS », « C8 »), protocole SKS inconnu. La doc Asahi dit 0x13 nécessaire à SKS (P §1.3). SBIO sans eux : non trouvé publiquement.
- **Tout code qui écrira vers 0x12, 0x13, 0x10, 0x15 ou gigalockers sera derrière un paramètre de module désactivé par défaut et signalé.** Ce plan n'en propose aucun avant l'étape 6.

## 3. Prérequis hors périmètre agent
1. Démarrage de SEPOS sous Linux : alias DT `sep` + `status = "okay"` sur j314c, m1n1 transmet `sepfw` / manifests, puis le pilote (stub downstream `sep.rs`) envoie boottz0 + **IMG4**
   au SEP (P §1.2-1.3). C'est un envoi IMG4 = écriture SEP, **réservé à Albert via `pending/`** (script avec en-tête but/risque/résultat attendu). Un IMG4 invalide panique le SEP (doc Asahi).
2. Boot ROM EP 0xFF / mémoire partagée EP 0xFE (séquence KS §2) : écritures SEP, même régime. Le « 0x1b/0x7f » sur 0xFF : origine inconnue (KS « Incertitudes »).
3. Tout test SKS/xART/0x6d/0x5b vers le SEP : écriture, `pending/` uniquement.
4. Test sur le Mac : `tools/boot_test_kernel.sh` est soumis à confirmation d'Albert ; build via `tools/build_kernel.sh`.
5. Boot policy / install de m1n1 : Albert à la main.
6. Si le SEP reste sous SEPROM (cas par défaut P §1.3) : aucune communication SBIO possible ; seules les étapes 1-2 ci-dessous s'appliquent.

## 4. Ordre d'implémentation (étapes testables)
0. **Sans hardware** : relire K3/K4 manquants (`+0x14` des 0x09, CRC C11 déjà fait), faire passer les `vérifié (macOS)` dans messages.md (Albert), et lire l'ADT pour identifier le contrôleur SPI du capteur.
1. **Lecture seule SEP** : pilote mailbox minimal (DT `sep` en lecture : mapping mailbox + IRQ, aucun envoi, ou envois EP 0xFF seulement GETRAND comme m1n1 si Albert l'autorise) qui **journalise** les messages reçus ; test : lecture de l'état SEPROM, aucune émission SEPOS. Critère : le décodage de mots (bits 0-63) correspond à `sep.log` des traces.
   Alternative sans hardware : banc de décodage rejouant les `sep.log`/OOL de `traces/` contre le parseur (tests unitaires).
2. **Décodeur de découverte 0xFD + table nom → EP** (rejeu de traces) : vérifie `sbio` → 0x08, tailles 0x4000.
3. **Nœud DT capteur + sonde SPI, lecture seule** : activer le contrôleur candidat, lire le statut au démarrage (`80 20 00 10000000 …`, identique 16/16 traces). Aucune émission vers le SEP ; alimentation/reset du capteur = GPIO de l'AP (pas de SEP), mais l'alimentation du capteur sans l'AOP peut être inopérante : risque matériel faible, à relire par Albert (inconnu).
4. **Fragmentation GT** (rejeu hors ligne) : réassemblage `fc/fd/fe` et vérification contre C8/C11 (0x5b, 0x5f, 0x6c, 0x6d, 0x65), CRC des 12 tranches.
5. **Démon blobs** (hors ligne) : extraire/rejouer les 0x6c, formats `LTFC`/en-tête ; tester que le démon reproduit exactement la séquence d'init (57 commandes) contre une trace.
6. **Écriture SEP** (réservée Albert, `pending/`) : boot SEPOS minimal, puis CNTL/ouverture `sbio`, `0x73`, init capteur 17→15→16… ; derrière paramètre de module désactivé par défaut. Puis, seulement si nécessaire, SKS (module param séparé).
7. Match : `23 06 65 07 09 21 22` ; expériences humaines si besoin ; puis interface libfprint/PAM.

## 5. Inconnues bloquantes, classées
Classe 1 — bloquantes pour toute communication
1. SEPOS ne tourne pas sous Linux sans alias `sep` + IMG4 (écriture réservée) ; comportement SEP après un boot Linux (préchargement iBoot, état SEPROM) : inconnu (P §1.1, §1.3).
2. Séquence de boot EP 0xFF/0xFE et DART SEP côté Linux (IOVA des OOL) : hypothèse (KS §2), non testée.
3. SKS/keybag : le SEP refuse-t-il `0x09` sans mot de passe validé (lockState 0x0015) ? Protocole EP 0x12 inconnu (KS D2).
Classe 2 — bloquantes pour le capteur
4. Contrôleur SPI, CS, IRQ, GPIO d'alimentation/reset de `biosensor,mesa` sur t6001 : inconnus (P §2.2).
5. Reset/alimentation via l'AOP (`mesa-reset-ntfy`) sans pilote Linux : inconnu.
6. PIO 0x7200 o via spi-apple sans SIO : non éprouvé.
Classe 3 — bloquantes pour un match
7. Origine du paramètre `0x06` (0xa7 o) ; nécessité de `0x71`, `0x54`/`0x6e`/`0x7a` ; rôle de `0x1e`, `0x27`/`0x25`.
8. Acceptation par le SEP d'un `0x6d` rejoué / d'un `0x5b` rejoué sous un autre OS (clés liées au SEP, pas à l'AP : hypothèse).
9. Provenance du blob `0x5b` sous Linux (fichier macOS ?), enrôlement sous Linux.
Classe 4 — non bloquantes
10. Sens des bits 3, 4, 6, 9 du lockState ; TAG 0x02/0x04 ; compteur GT exact dans le kext ; écarts K6 ; expérience K-E1 ; mapping multi-uid.


## Mise à jour 2026-11-09 : étapes 1 à 5 faites hors ligne
- Fait dans `driver/` (module `sepreplay/`, 29 tests) : décodeur de mots mailbox, table 0xFD (recherche par nom), parseur du statut capteur, réassemblage GT + CRC des 0x65, rejeu de la séquence d'init (57 commandes, 18/18 captures) et des blobs 0x6c→0x6d. Aucune émission vers le SEP.
- Corrigé : l'ordre d'annonce des endpoints n'est pas fixe (3 ordres sur 8 boots) → toujours chercher par nom.
- Nœud DT capteur : spi2, 8 MHz, IRQ gpio0 195, alim gpio0 0xc4 (ADT-1). Reste inconnu : chip-select, phase, reset (via l'AOP).
- SKS (question « le SEP refuse-t-il 0x09 avant le mot de passe ? ») : non tranchée sans écriture ; sera visible à l'étape 6 (SEP piloté par Linux seul).
- Reste : étape 6 (décision d'Albert : Linux qui boote sur le Mac + SEPOS), puis étape 7.

## Mise à jour 2026-11-09 (soir) : le SEP sous m1n1 seul
- VU : le SEP répond à GETRAND (EP 0xFF) sans macOS (traces/20261109-212150_sep_getrand, 4 octets). Boîtes vides au repos, compteurs ≠ 0 (traces/20261109-210517_sep_peek).
- Doc publique (m1n1 `proxyclient/m1n1/hw/sep.py`, docs Asahi « SEP boot flow ») : la séquence de boot est GET_STATUS (0x66) → BOOT_TZ0 → GET_STATUS → BOOT_IMG4 (+ SET_SHMEM sur 0xFE). C'est l'OS (ou m1n1) qui envoie le firmware SEPOS ; iBoot ne fait que le précharger. Si SEPOS tourne déjà quand m1n1 prend la main : non documenté, hypothèse « plutôt non ».
- DÉCISION (Claude, d'après CLAUDE.md) : pas d'autre message vers le SEP pour l'instant. GET_STATUS serait un 2e test d'écriture à faible valeur (GETRAND a déjà montré que la ROM répond). La suite réelle = BOOT_TZ0/BOOT_IMG4 (étape 6, fichier IMG4 : hors périmètre agent, réservé Albert).

## Mise à jour 2026-11-10 : xART au boot (analyse hors ligne, 19 boots)
- VU : le SEP annonce sbio/skdl/sse/sks/scrd 0,122 s après la réponse de l'AP au TAG 4 de l'EP 0x13, 19/19. L'AP ne fait que rendre au SEP des blobs qu'il lui avait donnés à sauvegarder (CRC rendu = dernier « Saving » du boot précédent : 15/15 et 16/16 ; recopie des CRC 252/252). Contenu = état du disque macOS (fichier gigalocker du volume xART), non capturé.
- INTERPRÉTÉ : un Linux qui veut voir sbio doit tenir ce stockage (fournir au SEP ses propres blobs). Un rejeu « à vide » ou périmé est probablement refusé ; le SEP peut aussi invalider son état s'il reçoit un blob qui ne correspond pas à ses compteurs (non vérifié). Risque pour macOS/FileVault/trousseau.
- DÉCISION (Claude, CLAUDE.md) : pas de réponse 0x13, pas de capture des blobs (secrets probables). Étape 6 suspendue ici ; les étapes sans SEP (pilote capteur sur spi2, rejeu) continuent.

## Mise à jour 2026-11-10 (nuit) : composant C-A (capteur) fait, étape 3 terminée
Sources : docs/sensor_hw.md (« Alimentation et broches », « Dialogue SPI », « Essai sans macOS », table des états),
docs/verification_status.md SPI-1 à SPI-4, journal du 2026-11-10 (C17-C20, MESA-HELLO, LINUX-HELLO).
- **Étape 3 : faite et vérifiée sur le matériel.** spi2 (0x39b108000, IRQ AIC 1108, alimentation `ps_spi2`, horloge 24 MHz,
  broches laissées par iBoot, pas de chip-select, CPHA = 1), alimentation du capteur par gpio0 196 (actif haut), trames en
  clair 0x78 / 0x10 / 0x70 / 0x13. Le capteur rend la même identité sous macOS, depuis m1n1 et depuis Linux (pilote public
  spi-apple + `driver/linux/mesa_ovl.c` qui ajoute le nœud à chaud + `mesa_probe.c`). Le reset par l'AOP craint à l'étape 3
  n'est pas nécessaire pour ces trames.
- **C-C (relais) précisé** : sous macOS l'AP relaie ; l'image lue sur SPI (0x7200 o, 12 tranches) est la charge de `> 0x65`
  (vérifié macOS, C20). Les commandes au capteur après l'identité sont chiffrées et suivent chacune une commande sbio
  (vu : 0x15 → trame 0x72, 0x42 → 0x73, 0x5f → 0x60 + gros bloc, 0x5d/0x5c/0x6a/0x6f/0x31 → 0x55) : un pilote n'a pas à
  les fabriquer, seulement à les transporter (hypothèse pour tout sauf l'image).
- **Ce que Linux peut faire aujourd'hui sans le SEP** : allumer le capteur, lire identité et état. Tous les états liés au
  doigt n'apparaissent sous macOS qu'après l'envoi du gros bloc (correctif) fourni par le SEP.
- **Blocage inchangé** : étape 6 (sbio absent sans échange xART). L'étude des voies possibles a été arrêtée par le filtre
  de sécurité du modèle (journal 2026-11-10 01:05) : décision d'Albert en attente (docs/handoff.md, liste de tâches).
- Prochain travail possible sans SEP : séparer dans `driver/linux` un petit transport (alimentation, état, lecture de
  réponse) du test « bonjour ».

## Mise à jour 2026-11-10 (Opus 4.8) : transport propre et réactif, xART étudié, images chiffrées
Sources : journal du 2026-11-10 (entrées Opus 4.8), docs/verification_status.md SPI-1, docs/xart_options.md, docs/sensor_hw.md.
- **Transport isolé et réactif.** `driver/linux/mesa_transport.h` (couche réutilisable : acquire/release, power on/off, send,
  read, status, **wait_ready**) ; `mesa_probe.c` = 1er client « bonjour », `mesa_statloop.c`/`mesa_irqwatch.c` = clients de test.
  Le transport attend la broche « donnée prête » (gpio0 195) avant chaque lecture d'état au lieu d'une pause fixe ;
  identité toujours identique (vérifié sur le Mac via le Linux de test). Étape 3 : non seulement faite, mais maintenant propre.
- **Broche gpio0 195 caractérisée** (vérifié) : ligne « donnée prête » active haute, monte à chaque réponse en attente (démarrage,
  puis après 0x70), retombe à la lecture d'état. => pilotage par interruption possible plus tard (request_irq), mais risque de
  rafale bloquante à distance : réservé au moment où Albert peut power-cycler (handoff).
- **C-C (relais image) renforcé** (vérifié octet pour octet, analysis/cmp_sensor_sep_image.py) : l'image (0x7200 o) est relayée au
  SEP telle quelle par l'OOL de l'EP 0x08, en 2 tranches de 0x4000 précédées d'un entête de 0x1c o
  (`[1]=longueur totale [2]=offset [5]=type 0x65 [6]=longueur de tranche`). Chiffrée bout en bout capteur↔SEP (2 images ne
  partagent rien) : **un pilote Linux ne peut que transporter, jamais interpréter**. Sur C20 : 27 images lues sur le bus, 7 seulement
  transmises au SEP (20 non transmises = trames de prévisualisation, hypothèse ; analysis/count_sensor_vs_sep_images.py).
- **Étape 6 (blocage) étudiée** : docs/xart_options.md (5 voies). La voie B (tracer l'OOL de l'EP 0x13 au boot macOS, en lecture
  seule) est **prête sans nouveau code** (`SEP_OOL_EPS=0x13`), attend le câble USB + Albert. Les voies qui écrivent vers le SEP
  (rejeu/forge de lockers) butent sur une clé interne au SEP qu'on s'interdit de chercher : Touch ID complet probablement hors de
  portée sans elle. But réaliste court terme : « Linux parle au capteur », atteint.

## Mise à jour 2026-11-12/13 (Opus 4.8) : stratégie, pont opcode↔opération, archi SKS
Sources : journal 2026-11-12/13, docs/kext_sepmanager.md §9/§12c/§13/§14, docs/verification_status.md (ajout 2026-11-12/13),
[[voie-c-xart-fraicheur]]. Rien de nouveau n'est écrit vers le SEP ici ; que de la lecture/décompilation.

- **Basculement de stratégie.** Touch ID sous Linux = **driver natif + état SEP valide et courant**, **pas** un rejeu de lockers.
  La voie C (« faire accepter un rejeu xART ») **penche fortement vers impossible côté AP** (§9, ci-dessous). Conséquence pratique :
  le vrai déblocage dépend d'un **état SEP propre** (keybag + empreintes enrôlées), qui vit dans macOS — or macOS est cassé. Donc à
  un moment : **DFU Restore + ré-enrôler Touch ID + backup disque** (matériel, **Albert**). Tant que cet état n'existe pas, aucun essai
  SEP en écriture n'est *validable*. Ça ne change pas les composants C-A..C-E ; ça fixe l'ordre : le capteur (C-A) est acquis, le reste
  attend un SEP sain.
- **C-B / C-C affermis — format fil sbio VÉRIFIÉ et pont opcode↔opération.** Le buffer OOL d'un message EP 0x08 `type=0xfc` est un
  `gt_packet_t` (`+0x14 = OPCODE`, `+0x18 = longueur fragment`, `+0x1c = charge`), **vérifié contre capture** (c12, 14/14, fragmentation
  0x5b) via `analysis/sbio_gt_packet.py`. Le pont kext↔traces est établi (§12c) : `handleMatch`=**0x09**, `handleEnrollment`=0x08,
  `commandStartEnroll`=0x03, `forceNoMatch`=0x06, `asyncCaptureHandler`=0x07/0x22, `performKeyExchange`=0x15, `cacheMatchPolicy`=0x1f,
  `initializeSequenceCounter`=0x42, `applySensorParams`=0x5d, `setCalibrationData`=0x63. Le driver peut donc **nommer et parser l'opcode
  de toute transaction EP 0x08**. Noms d'opérations = `hypothèse (kext)` ; format fil = `vérifié`.
- **§2 / D2 précisé — SKS (EP 0x12) = RPC à params DER, pas des opcodes** (§14/§14b). L'AP passe par l'API **AKS** (`aks_ref_key_*`,
  `aks_params_*` **sérialisés DER**) → `__aks_operation` → endpoint SKS ; le mot mailbox 0x12 ne porte qu'un compteur + la longueur.
  → un driver Linux devrait **produire le même DER** (schéma à extraire), pas un opcode. Reste ouvert (classe 1, inconnue n°3 / D2) :
  l'énum numérique `kAppleKeyStore*` ↔ TAG fil (0x2f/0x41/0x18), le format DER exact, et **la question décisive** : le SEP refuse-t-il
  `0x09` tant que le keybag est verrouillé ? Non testable sans écriture (EP 0x12 = ligne rouge, Albert). Décompil SKS plus loin = long
  et non testable → **faible priorité**.
- **Voie C / nonce (met à jour l'inconnue n°8).** Le nonce de fraîcheur xART (20 o) est **généré par le SEP** (xART + ROM) ; **aucune
  API AP pour le poser/semer**, aucune graine NVRAM (§9). → l'acceptation d'un `0x6d`/locker rejoué sous un autre boot n'est plus
  seulement « inconnue » mais **défavorable côté AP** (hypothèse kext ; réserve : ne couvre pas une graine interne ROM). ESSAI B n=2
  (journal 12/11) confirme : re-scellement reproductible, fraîcheur dans les blobs xART maîtres. **Ne pas relancer ESSAI B.**

## Mise à jour 2026-11-17 (analyste) : carte opcode↔opération EP 0x08 intégrée à messages.md
- `docs/messages.md` section « SBIO (0x08) — carte opcode↔opération + statut fil » consolide : **format fil `gt_packet_t`**
  (`vérifié` contre c12, opcode à `+0x14`, outil `analysis/sbio_gt_packet.py`) et **verdict de match 0x09** (`vérifié` c6/c8/c11,
  `+0x00`=0x1f5/−1). Noms d'opérations (`handleMatch`=0x09, `handleEnrollment`=0x08, `commandStartEnroll`=0x03, `forceNoMatch`=0x06,
  `asyncCaptureHandler`=0x07/0x22, `performKeyExchange`=0x15, `cacheMatchPolicy`=0x1f, `initializeSequenceCounter`=0x42,
  `applySensorParams`=0x5d, `setCalibrationData`=0x63) = `hypothèse (source: kext)`. → le driver peut **nommer et parser l'opcode de
  toute transaction EP 0x08** (= `gt_packet_t.+0x14` du buffer A) à partir de messages nommés, format fil vérifié.
