# CLAUDE.md — sep-touchid

Projet privé de reverse engineering du SEP (Secure Enclave Processor) d'un MacBook Pro M1 Max,
objectif à terme : Touch ID sous Linux. Lis `README.md` pour le contexte et le setup.

## PHASE ACTUELLE : 2 — KEXTS

> Seul Albert modifie cette ligne. Un agent ne change jamais de phase, même s'il est bloqué :
> il note le blocage dans `docs/hypotheses.md` et propose le passage en phase 2 dans son rapport.

## Lignes rouges (toutes phases, non négociables)

- **Jamais de matériel Apple leaké** (sources internes, firmwares déchiffrés non publics, dumps). Ne pas en chercher sur le web.
- **Aucune écriture vers le SEP par un agent** : endpoints 0x12 (SKS), 0x13 (xART), 0x10, 0x15, gigalockers, envoi d'IMG4.
  Un agent qui pense qu'une écriture est nécessaire écrit un script dans `pending/` avec un en-tête expliquant
  le but, le risque et le résultat attendu, puis s'arrête. Albert relit et lance.
- **Le hardware passe uniquement par `tools/*.sh`.** Pas d'appel direct à `m1n1/proxyclient`, pas de script Python ad hoc qui ouvre `/dev/ttyACM*`.
- **Jamais** : `bputil`, `kmutil`, `csrutil`, `nvram`, partitionnement, `dd`, `sudo`. Boot policy et install de m1n1 = Albert, à la main.
- **Rien ne sort de ce repo vers Asahi** (issues, PR, doc, IRC/Matrix). Projet privé.
- **`traces/` est en lecture seule après capture.** On ne modifie jamais un log brut ; les analyses vont dans `docs/`.

## Qui décide quoi (accord d'Albert, 2026-11-09)

- L'agent décide seul : lecture, analyse, docs, outils sur le PC, captures en lecture seule, et les validations techniques
  (le sceptique tranche « vérifié » ou « hypothèse » ; ce qui reste incertain est noté, pas renvoyé à Albert).
- L'agent demande à Albert **seulement** si l'action peut abîmer le Mac ou écrit vers le SEP, en une phrase simple
  (ce qu'on fait, ce qui peut rater, oui/non). Pas de jargon dans les questions.
- Les lignes rouges ci-dessus ne changent pas. Albert prévoit un backup du Mac plus tard : tant qu'il n'existe pas,
  aucune action risquée pour les données.

## Phase 1 — sources autorisées

- Traces capturées ici (`traces/`).
- Doc publique Asahi (asahilinux.org/docs), code public de m1n1 et linux-asahi.
- Code open source Apple publié (opensource.apple.com / apple-oss-distributions : xnu, IOKitUser…).

Interdit en phase 1 : désassembler/décompiler **tout** binaire Apple (kexts compris).

## Phase 2 — règles (inactives tant que la ligne PHASE ne dit pas 2)

- Désassemblage des kexts macOS autorisé **uniquement** pour extraire le protocole AP↔SEP
  (format des messages, séquences, constantes). Kexts cibles : AppleSEPManager et drivers biométriques,
  plus AppleSEPKeyStore (ajouté par Albert le 2026-11-08) pour le seul protocole de l'EP 0x12 (SKS), tel que
  le dernier maillon entre un match biométrique et le déverrouillage. Mêmes règles : protocole uniquement,
  aucune clé ni secret extrait, et toute écriture vers l'EP 0x12 reste un script dans `pending/` lancé par Albert.
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

## Exception : 2e Linux de test (accord d'Albert)

- Sur le Linux de test `root@10.0.200.4` (partition Asahi d'Albert, jetable) uniquement : l'agent peut y agir en root, via `tools/linux_ssh.sh` seulement, pour compiler et charger les modules de `driver/linux/`.
- Interdit même là : partitionner, toucher à m1n1, à la boot policy ou à macOS, et envoyer quoi que ce soit au SEP (0x12, 0x13, 0x10, 0x15, gigalockers, IMG4).
