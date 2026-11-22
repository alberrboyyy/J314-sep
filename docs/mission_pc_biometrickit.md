# Mission session PC — contenu réel des commandes sbio 0x03 (enroll) et 0x06 (match), depuis l'IPSW public

Demandée par Albert le 2026-11-22 (session ALARM). À faire **sur le PC**, rien ne touche au Mac.

## Pourquoi
- En Linux natif, toute l'init capteur de macOS (2 passes, 0x73 → 0x63×2) marche (journal 2026-11-22 20:43 → 22:11).
- J6a (journal 23:04, `logs/20261122-230441_j6a-enroll-start/`) : un `0x03` de 68 o **à zéro** → le SEP répond
  `TAG 0xff TYPE 0x03` (refus probable), sans charge.
- Le contenu de `0x03` (`enroll_indata_v2_t`, 0x44 o) et de `0x06` (0xa7 o, nonce par verrouillage) est construit en
  **espace utilisateur** macOS (biometrickitd / BiometricKit), pas dans le kext → `docs/j6_enroll_match_protocol.md`.
- Récupérer ces binaires sans macOS : macOS ne démarre plus proprement (état SEP/xART modifié) et un DFU effacerait
  tout le disque. → **IPSW public** d'Apple (logiciel distribué publiquement, pas du matériel leaké).

## Étapes
1. Outil open source `ipsw` (github.com/blacktop/ipsw), dernière release.
2. `ipsw download ipsw --device MacBookPro18,2 --version <version installée, 27.2.1 d'après handoff>` (~17 Go), dans
   `macos/` (gitignoré).
3. Extraire : `ipsw extract --dyld <ipsw>` (cache dyld du cryptex OS, image AEA déchiffrée par `ipsw` via la clé
   publique fournie par Apple), et `/usr/libexec/biometrickitd` depuis l'image système (`ipsw extract --files
   --pattern 'biometrickitd'` ou montage de la dmg).
4. Dans le cache dyld : `BiometricKit.framework`, éventuellement `BiometricSupport`/`MesaSupport` (noms à vérifier) —
   `ipsw dyld split` ou `ipsw dyld disass`.

## Questions (protocole uniquement, aucune clé, aucun secret, rien de copié dans driver/)
1. Construction de `enroll_indata_v2_t` (68 o) envoyé par `commandStartEnroll` (opcode 0x03) : champ par champ
   (u32 +0x00 bit 0 = ?, uid ?, type de doigt, options, acmContext ?).
2. Construction du `0x06` (0xa7 o) du match : d'où vient le nonce, dépend-il de SKS/ACM (EP 0x12) ?
3. Préconditions avant `0x03` : autre commande (0x7c ? acmContext 0x27/0x25 ?), keybag déverrouillé requis ?
4. Sens d'une réponse sbio `TAG 0xff` (code d'erreur ? où le lire ?) — aussi dans AppleMesaSEPDriver (kext).
5. Nombre de poses / boucle 0x23/06/65/07 → 0x1e → 0x08 côté userland ; export catacomb 0x6c.

## Livrable
`docs/biometrickit_protocol.md` (VU adresse/symbole vs hypothèse, `source: userland`), puis message à la session
ALARM avec le contenu proposé pour 0x03/0x06. Le prochain run (J6b) sera préparé côté ALARM ; 1er run = go d'Albert.
