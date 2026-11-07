# sep-touchid

Projet perso : comprendre le Secure Enclave Processor (SEP) d'un MacBook Pro 14" M1 Max
et, si possible, faire fonctionner Touch ID sous Linux.

> **Projet privé, non publié.** Ce travail est fait avec l'aide d'une IA. Il ne doit jamais
> être soumis au projet Asahi Linux (voir leur politique : https://asahilinux.org/llm-policy/).
> Rien de ce qui est découvert ici ne va dans leurs issues, leur doc ou sur #asahi-dev.

## Architecture

```
[PC Ryzen — Arch Linux]  ──── USB-C données ────  [MacBook Pro M1 Max]
  Claude Code + agents                              m1n1 dev (proxy / hyperviseur)
  m1n1/proxyclient (Python)                           └─ macOS 13.5 invité, tracé
  traces/, docs/, driver/
```

Tout le travail se fait sur le PC. Le Mac n'est que le banc de test.

## Phases

| Phase | Sources autorisées | Objectif |
|-------|--------------------|----------|
| **1 — Traces seules** (actuelle) | Traces m1n1 capturées ici, doc publique Asahi, code public m1n1/linux-asahi, open source Apple (xnu…) | Tracer le boot du SEP et un déverrouillage Touch ID, identifier SBIO (EP 0x08) et le keystore |
| **2 — Traces + kexts** (si phase 1 prometteuse) | + désassemblage des kexts macOS (protocole AP↔SEP uniquement) | Comprendre enrôlement/vérification, écrire le driver |

Le passage en phase 2 est une décision d'Albert, prise à la main dans `CLAUDE.md`.
**Lire des kexts est irréversible** (ferme définitivement la porte des contributions à Asahi).

## Jalon 1 (go / no-go)

1. Setup : PC hôte, m1n1 dev sur le Mac, macOS 13.5 sous hyperviseur.
2. Trace propre d'un boot complet du SEP.
3. Trace d'un déverrouillage Touch ID (doigt réel, session humaine).
4. Repérer les messages SBIO et ceux du keystore qui les précèdent.

**Question de sortie :** l'enrôlement / la vérification dépendent-ils d'un état que seul macOS peut créer ?

## Setup

### 1. PC (Arch)

Voir `SETUP-ARCH.md`.

### 2. macOS 13.5 sur le Mac — ⚠️ important

Le m1n1 hyperviseur **cible macOS Ventura 13.5** ; les versions plus récentes ne sont pas supportées
sous hyperviseur. Il te faut donc **un volume macOS 13.5 séparé**, uniquement pour le tracing
(ton macOS principal peut rester tel quel).

- Le firmware SEP est déterminé par la version de macOS la plus récente jamais installée sur
  la machine, mais le protocole IPC est rétrocompatible (négocié à la baisse) : tracer sous 13.5 reste pertinent.
- Dans ce macOS 13.5 : crée un utilisateur et **enrôle une empreinte Touch ID**.

### 3. Récupérer le kernelcache (depuis macOS 13.5, à la main)

Chemin : `/System/Volumes/Preboot/<UUID>/boot/<hash>/System/Library/Caches/com.apple.kernelcaches/kernelcache`

Copier sur le PC dans `macos/`, puis extraire le Mach-O :
```
img4tool -e -o macos/kernel.macho macos/kernelcache
```
(ou `pyimg4` si img4tool n'est pas dispo).

### 4. m1n1 dev sur le Mac (à la main — jamais par un agent)

Suivre **la doc officielle**, pas une version de mémoire :
- https://asahilinux.org/docs/sw/m1n1-user-guide/
- https://asahilinux.org/docs/sw/m1n1-hypervisor/

Le but : une entrée de démarrage avec un m1n1 sans payload → il tombe en **mode proxy**
et expose deux ports série USB sur le PC (`/dev/ttyACM0` = proxy, `/dev/ttyACM1` = UART virtuel de l'hyperviseur).

### 5. Premier test

```
./tools/build_m1n1.sh
./tools/boot_and_trace.sh boot-sep-test
```

## Structure

```
CLAUDE.md            règles pour Claude Code (lignes rouges, phase, workflow)
.claude/agents/      tracer, analyste, sceptique, driver
.claude/settings.json permissions (scripts sûrs autorisés, le reste demandé/interdit)
tools/               seuls points d'entrée vers le hardware (config dans tools/env.sh)
hv/                  scripts de tracing passés à run_guest.py (tracer SEP filtré)
analysis/            scripts d'analyse des traces
traces/              logs bruts (jamais modifiés après capture)
docs/journal.md      qui a observé quoi, comment, quand
docs/messages.md     table des messages SEP (vérifié / hypothèse)
docs/hypotheses.md   hypothèses ouvertes + expérience pour les trancher
pending/             scripts qui ÉCRIVENT vers le SEP → relus et lancés par Albert uniquement
m1n1/                clone du repo m1n1 (non versionné ici)
driver/              code du driver Linux (phase 2+)
```
