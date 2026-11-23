# CLAUDE.md — sep-touchid

Projet privé de reverse engineering du SEP (Secure Enclave Processor) d'un MacBook Pro M1 Max,
objectif à terme : Touch ID sous Linux. Lis `README.md` pour le contexte et le setup.

## PHASE ACTUELLE : 2 — KEXTS

> Seul Albert modifie cette ligne. Un agent ne change jamais de phase, même s'il est bloqué :
> il note le blocage dans `docs/hypotheses.md` et propose le passage en phase 2 dans son rapport.

## Lignes rouges (toutes phases, non négociables)

- **Jamais de matériel Apple leaké** (sources internes, firmwares déchiffrés non publics, dumps). Ne pas en chercher sur le web.
- **Écriture SEP — règle RELÂCHÉE par Albert (2026-11-22).** Claude peut **lancer lui-même** un script `pending/`
  **déjà éprouvé** : relu par Claude ET déjà exécuté proprement sur matériel (classe « route native / sbio-climb » :
  boot IMG4, ACK des SAVE xART 0x13, relais capteur 0x08 — key exchange, compteur, réception patch). Pour toute
  écriture d'une **classe encore JAMAIS testée sur matériel** (ex. écriture/persistance gigalocker, **SKS 0x12 en
  écriture**, enrôlement, ou le **1er run d'un script neuf**), Claude prépare le script dans `pending/` (en-tête
  but/risque/résultat), le **montre à Albert et attend son « go »**. Toujours : fail-closed, backup disque +
  DFU en filet. Le **power-cycle physique reste Albert** (le reboot logiciel **via le proxy m1n1** fige le PMU/SPMI).
  Sous **Linux natif**, un `reboot` normal (SMC) remet le SEP en ROM : il suffit entre deux runs (VU n=7, `docs/sep_reconnect.md`,
  journal 2026-11-23) ; le reboot reste une action d'Albert.
- **Le hardware passe uniquement par `tools/*.sh`.** Pas d'appel direct à `m1n1/proxyclient`, pas de script Python ad hoc qui ouvre `/dev/ttyACM*`.
- **Jamais** : `bputil`, `kmutil`, `csrutil`, `nvram`, partitionnement, `dd`, `sudo`. Boot policy et install de m1n1 = Albert, à la main.
- **Rien ne sort de ce repo vers Asahi** (issues, PR, doc, IRC/Matrix). Projet privé.
- **`traces/` est en lecture seule après capture.** On ne modifie jamais un log brut ; les analyses vont dans `docs/`.

## Qui décide quoi (accord d'Albert, 2026-11-09)

- L'agent décide seul : lecture, analyse, docs, outils sur le PC, captures en lecture seule, et les validations techniques
  (le sceptique tranche « vérifié » ou « hypothèse » ; ce qui reste incertain est noté, pas renvoyé à Albert).
- L'agent demande à Albert **seulement** si l'action peut abîmer le Mac, ou pour une **écriture SEP d'une classe
  jamais testée** (cf. ligne rouge « Écriture SEP », relâché 2026-11-22) ; les écritures SEP **déjà éprouvées**,
  Claude les lance seul. En une phrase simple (ce qu'on fait, ce qui peut rater, oui/non). Pas de jargon.
- Les **autres** lignes rouges ne changent pas. Backup disque (`alarm_p5.img`) + DFU restore = filet en place.

## Phase 1 — sources autorisées

- Traces capturées ici (`traces/`).
- Doc publique Asahi (asahilinux.org/docs), code public de m1n1 et linux-asahi.
- Code open source Apple publié (opensource.apple.com / apple-oss-distributions : xnu, IOKitUser…).

Désassemblage/décompilation de binaires Apple : **autorisé** (élargi par Albert le 2026-11-11 ;
avant, interdit en phase 1). But : extraire le protocole (format des messages, séquences, constantes).
Garde-fous conservés (côté légal) : **protocole uniquement**, aucune clé ni secret extrait, **aucune
copie de code Apple** (même réécrit) dans `driver/`, info issue d'un binaire marquée `source: kext`.

## Phase 2 — règles (inactives tant que la ligne PHASE ne dit pas 2)

- Désassemblage des binaires macOS autorisé pour extraire le protocole AP↔SEP / Touch ID (format des
  messages, séquences, constantes) : **tout binaire pertinent** (kexts SEP et biométrie — AppleSEPManager,
  AppleSEPKeyStore pour l'EP 0x12/SKS, IOBiometricFamily, AppleMesaSEPDriver… — et au-delà si utile).
  Élargi par Albert le 2026-11-11 (avant : seulement quelques kexts « uniquement pour le protocole »).
  Garde-fous : protocole uniquement, aucune clé ni secret extrait ; toute **écriture** vers le SEP (dont
  l'EP 0x12) reste un script dans `pending/` lancé par Albert.
- Jamais de copie de code Apple (même réécrit ligne à ligne) dans `driver/`. On documente le protocole dans
  `docs/messages.md`, et le driver s'écrit à partir de cette doc.
- Chaque information issue d'un kext est marquée `source: kext` dans la table.

## Rigueur

- Une hypothèse n'est **vérifiée** que si une expérience l'a confirmée (trace dédiée, comportement reproductible).
  Une interprétation de log, même convaincante, reste `hypothèse`.
- Le driver (phase 2+) ne s'écrit qu'à partir de messages marqués `vérifié`.
- Chaque observation va dans `docs/journal.md` : date, agent, trace source, ce qui a été vu, comment.
- En cas de doute, le dire. Mieux vaut « je ne sais pas » qu'un pattern inventé dans du binaire.

## Workflow

1. **tracer** améliore l'outillage et capture (`tools/boot_and_trace.sh`).
2. **analyste** lit les logs, met à jour `docs/messages.md`.
3. **sceptique** attaque les hypothèses, propose l'expérience qui tranche.
4. **driver** (phase 2+) code à partir des messages vérifiés.

Sessions nécessitant un humain (doigt sur le capteur, mot de passe, enrôlement, reboot physique) :
l'agent prépare l'expérience dans `docs/hypotheses.md` (« EXPÉRIENCE HUMAINE ») et s'arrête.

Si le Mac ne répond plus (`/dev/ttyACM0` absent, timeout) : ne pas insister, noter dans le journal,
passer aux tâches hors hardware (analyse, outillage).

## Repères techniques

- Format des messages SEP (doc Asahi) : bits 0-7 endpoint, 8-15 tag, 16-23 type, 24-31 param, 32-63 data.
- Endpoints connus : voir `docs/messages.md`.
- Hyperviseur : macOS **13.5** uniquement. Toujours chainloader un m1n1 frais avant `run_guest.py` (ABI instable) — `tools/boot_and_trace.sh` le fait.
- Le tracer SEP actuel spamme la console au point de faire paniquer : filtrer par endpoint est la priorité n°1.
- **RTFM d'abord** (erreur Claude, 2026-11-11) : avant de conclure qu'une opération « ne marche pas », lire les
  options du proxyclient m1n1. Le `UartInterface` lit **`M1N1TIMEOUT`** (défaut **3 s**). Sur lien distant à
  latence (tunnel relais, cf. mémoire tunnel-relais-mac), 3 s est trop court pour `run_guest` (boot hyperviseur) →
  `UartTimeout` au bootstrap. Fix : **`export M1N1TIMEOUT=20`** (ou plus). Les lectures courtes (sep_peek) et le
  chainload passent avec 3 s, pas le boot macOS. Autres vars utiles : `M1N1DEVICE`, `HV_UART`, `M1N1WAIT`, `M1N1HEAP`.
- **Protocole AVANT de coder la réponse** (erreur Claude, 2026-11-12) : avant d'écrire un script qui **répond** au SEP,
  lister TOUS les messages qu'il pilote et **comment macOS répond à chacun**, depuis la capture complète + `kext_sepmanager.md`
  §8 — pas depuis le seul sous-ensemble nommé dans la consigne. Erreur concrète : le mode FOLLOW n'acquittait que les SAVE
  (0x01/0x06) et traitait tout le reste en « inconnu → stop » ; or l'op **0x07 (locker-absent)** était déjà dans la capture
  (macOS l'acquitte, snew-reel TAG=0x0b) et documentée — l'arrêt « prudent » s'est déclenché sur un message connu et bénin,
  coûtant un run. La règle « inconnu → stop » reste bonne ; c'est la liste des « connus » qu'il faut bâtir exhaustivement.

## Exception : Linux sur le Mac (accord d'Albert ; SEP OUVERT le 2026-11-22 ; plus de Linux de test → partition PRINCIPALE)

- Le Linux de test jetable `root@10.0.200.4` **n'existe plus** (2026-11-22) → on travaille sur la **partition Linux PRINCIPALE d'Albert** (ALARM). ⚠️ **Elle n'est PAS jetable** : priorité « ne pas perdre Linux ». Albert fait un **snapshot** (protège les FICHIERS, PAS un brick SEP/boot). L'agent agit en root via `tools/linux_ssh.sh` (ou un agent Claude lancé localement sur le Mac), pour compiler/charger les modules de `driver/linux/`.
- **SEP désormais AUTORISÉ depuis ce Linux (ouvert par Albert le 2026-11-22 ; cible = pilote natif sans tether).** L'agent peut faire parler le SEP depuis Linux — boot SEPOS (IMG4/sepfw = ex-« étape 6 »), EP 0x08 (sbio), 0x12 (SKS), 0x13 (xART), 0x10/0x15, gigalockers, et le DMA capteur via apple-sio — avec la **MÊME discipline que les écritures SEP sous m1n1** :
  - **fail-closed** à la 1re incohérence ; **filet AVANT toute écriture SEP** = image disque OS (`alarm_p5.img`) + backup perso d'Albert (données depuis ~lundi) + DFU. (Albert 2026-11-22 : macOS **sacrifiable** — les écritures xART/enrôlement cassent probablement le Touch ID macOS + FileVault, récupérable DFU + ré-enrôlement, ACCEPTÉ, ne pas redemander pour ça.)
  - **tout 1er run d'une classe neuve OU d'un script neuf = « go » d'Albert** (cf. règle lancement SEP) ; les re-runs d'un script déjà éprouvé = autonomes.
  - **power-cycle physique = toujours Albert.**
  - **JAMAIS** le Secure Element « Stockholm » en direct (brick définitif).
- **Toujours interdit même là :** partitionner, `dd`, `bputil`/`kmutil`/`csrutil`/`nvram`, toucher à **m1n1** (install/upgrade), à la **boot policy** ou à **macOS** ; rien vers Asahi ; aucun matériel Apple leaké.

## Écriture dans docs/guide/
- Lire docs/guide/STYLE.md avant toute modification du guide.
- Le guide n'est pas le journal : aucun historique de travail, aucune
  consigne pour l'agent, aucune mention d'Albert à la 3e personne.
- Sources pour rédiger : verification_status.md, hypotheses.md,
  messages.md, annexe-sources.md. Le journal sert à vérifier, pas à copier.
- Jamais de fait inventé : un « pourquoi » manquant devient
  <!-- QUESTION ALBERT : ... -->.
- Après chaque modification d'un chapitre : lancer lecteur-naif puis
  verificateur, et corriger jusqu'à ce qu'ils ne signalent plus rien.
- Quand Albert corrige quelque chose, ajouter la règle correspondante
  (avec exemple) dans STYLE.md.
