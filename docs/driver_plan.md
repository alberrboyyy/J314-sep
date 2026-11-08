# Plan d'architecture d'un futur pilote Linux Touch ID (j314c) — phase 2, document de planification

2026-11-08 — driver. **Aucun code, aucune action hardware.** Synthèse de ce qui est déjà documenté ; rien de nouveau n'est
établi ici. Statuts : `vérifié` = proposé `vérifié` dans « Confrontation kext ↔ traces » de `docs/hypotheses.md` (K1-K7)
**mais la décision revient à Albert** (CLAUDE.md) ; tant que `docs/messages.md` n'est pas mis à jour, on les traite comme
« vérifié (proposé) ». `hypothèse` = lecture de kext ou de trace sans expérience. `inconnu` = rien de documenté.
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
  `size` o (hypothèse, source: kext). Contrôle : 12 tranches de 0x980, CRC-16/ARC en fin de tranche (**vérifié (proposé)**, K4, 39 images / 468 tranches).
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
  rôle fc = premier paquet, fd = suivant, fe = accusé/demande du suivant : **vérifié (proposé)**, K2 (4006/4006 messages, 14 traces). Morceau de 0x3fe4 o de charge dans le tampon de 0x4000, en-tête OOL
  (`+0x00` = 1 si valide, TYPE, longueur) : vérifié par invariants (M « 0x6c/0x6d… », 1695 lectures) mais statut formel `vu`. Transaction max 0x4b000 (hypothèse, KS §5.1). TAG 0xff : jamais vu, non élucidé.
- Notifications TAG < 0xfc passées au client : `0x01` (DATA = uid, TYPE + PARAM·0x100 = lockState) — `<01/09 p2` à chaque verrouillage **vérifié (proposé)** K1 ; reste = hypothèse (sens des bits : KS §6, inconnu pour 3, 4, 6, 9).
  `0x03` → l'AP répond `> 0x21` : **vérifié (proposé)** K5 (50/50). `0x04` : inconnu (sens). `0x02` : inconnu. `0xfb` : jamais vu.
- Séquence d'init SBIO (57 premières commandes identiques sur 8 boots) : **vérifié (proposé)** K6 ; attribution fonction-kext → sous-séquence : hypothèse avec 3 écarts (0x01, 0x6f, 0x61).
- Prérequis CNTL (SECMODE 0x14, « OS actif » 0x0d/0x15 avant tout autre envoi) : hypothèse (KS §3). Messages de boot EP 0xFF/0xFE : voir §3, hors périmètre agent.

### C-C. Relais des commandes capteur et de l'image (0x65)
Rôle : le SEP demande des opérations sur le capteur ; l'AP les exécute sur SPI et renvoie le résultat via sbio.
- Init capteur (KS §7.B) : `0x17` (n° de série lu sur le capteur) → `0x15`/`0x16` (clé de session emballée par le SEP, 40 o aller-retour avec le capteur) →
  `0x42`/`0x18` (compteur de séquence) → `0x5f` (patch fourni par le SEP, 0x568e/0x70ce o, différent à chaque boot) → `0x01` ; `0x19` reset puis 2e passe. Ordre : vérifié (proposé) K6 ; rôles : hypothèse.
- Capture/match (KS §7.C, M C11) : `0x23` → `0x06` (entrée 0xa7 o `_lastImageProcessingParams`) → `0x65` (image 0x7200 o, lue sur SPI, recopiée par l'AP) → `0x07` → [`0x1e`] → `0x09` (sortie 0xca2 o, `+0x00` = uid ou −1) → `0x1f` → `0x22` ; `<03` → `>21`.
  Séquence et tailles `0x65` : vérifié (proposé) K4/K5 ; `0x1e` (relance après 0x07 défavorable) : hypothèse ; `+0xc24` du 0x09 (code d'échec/qualité) : hypothèse ; `0x09` `+0x14` : non testé (K3). Origine des 0xa7 o de `0x06` : **inconnu**.
- `0x27`/`0x25` (commandStartMatch) : absents des traces (vérifié, K7) → ne pas implémenter. Enrôlement (`0x03`, etc.) : jamais observé, inconnu.
- Chiffrement du corps des tranches (~8 bits/octet) : hypothèse (H « HH ») ; l'AP n'a pas à le déchiffrer si le relais est transparent (hypothèse).

### C-D. Démon userland : garde et renvoi des blobs (catacomb 0x6c → 0x6d, calibration 0x5b, lockout 0x70/0x71)
Rôle : remplace biometrickitd pour les blobs que le SEP exporte et réclame (le SEP ne stocke pas ses gabarits lui-même).
- `0x6c` export après chaque succès doigt (blob ~0x9200-0x9461 o + petit 0xf4 o uid −1, magic `LTFC`, scellé) ; `0x6d` import à l'init (2×, petit puis gros) ; C9 : le `0x6d` rejoue exactement le dernier `0x6c` de C8
  (M « 0x6c/0x6d… », C9, C11, C12) : comportement observé, **vérifié (proposé) pour la boucle export→import** (reproduit C9, C11, C12) ; statut formel dans messages.md à confirmer par Albert.
- Que le SEP accepte un `0x6d` rejoué depuis un autre OS/boot (lié à la clé du SEP, pas de l'AP) : **inconnu** (rejoue observé uniquement sous macOS).
- `0x5b` calibration : blob fixe de 0xfc99 o identique C5-C9, signé, lié au n° de série capteur (hypothèse, KS §7.B.7). Où le prendre sous Linux : inconnu (extraction depuis le disque macOS = lecture d'un fichier utilisateur, à cadrer par Albert).
- `0x70`/`0x71` BioLockoutRecord (`HRLB`) : nécessité inconnue (KS D5). `0x54`, `0x6e`, `0x7a`, `0x2b`, `0x33`, `0x36`, `0x39`, `0x28`, `0x7c`, `0x7d`, `0x0b`, `0x40` : requêtes pilotées par biometrickitd ; nécessité pour un match inconnue (KS §7.B.9). Le `0x09` N+1 reprend la copie `0x21` du succès N (12/12, hypothèse « chaîne »).
- Enrôlement sous Linux (création de gabarits) : inconnu, autre chantier.

### C-E. Interface vers libfprint / PAM
Rôle : exposer l'authentification. Aucune dépendance protocolaire nouvelle ; mais :
- Le résultat de match est `0x09 +0x00` = uid (0x1f5 = uid Unix 501 : vérifié par `id -u`, M C11) ou 0xffffffff ; le mapping uid SEP ↔ compte Linux : inconnu pour d'autres comptes (un seul compte testé).
- Pas de verdict biométrique dans TAG 0x01 (vérifié (proposé) pour le sens « keybag », K1) ; ne pas s'en servir comme succès.
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
0. **Sans hardware** : relire K3/K4 manquants (`+0x14` des 0x09, CRC C11 déjà fait), faire passer les `vérifié (proposé)` dans messages.md (Albert), et lire l'ADT pour identifier le contrôleur SPI du capteur.
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
