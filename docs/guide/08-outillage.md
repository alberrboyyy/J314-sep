# 8. Outillage

L'outillage est réutilisable au-delà de Touch ID : il permet d'observer et de piloter le SEP et
le capteur de façon contrôlée. Tout accès matériel passe par `tools/*.sh` ([chapitre 10](10-regles-et-risques.md)).

## Traceur SEP (`hv/trace_sep_filtered.py`)

Traceur mailbox sous hyperviseur m1n1, en **lecture seule**. Intercepte INBOX/OUTBOX, décode le
mot de 64 bits, et peut lire le contenu des buffers OOL via la traduction DART
([chapitre 2](02-architecture.md)). Principales variables d'environnement :

- `SEP_EPS` — filtre d'affichage par endpoint (ex. `0x13`), pour éviter la saturation de la console.
- `SEP_OOL_EPS` — endpoints dont on lit les buffers OOL à chaque message (ex. `0x08`, `0x13`).
  **Générique** : l'apprentissage de l'adresse/taille des buffers passe par les messages CNTL et
  fonctionne **même si l'affichage est filtré** sur un autre endpoint.
- `SEP_OOL_BYTES` — nombre d'octets lus par buffer (défaut 0x400).
- `SEP_OOL_FULL_TYPES` — types de messages dont on lit le buffer entier (défaut inclut 0x65).
- `SEP_OOL_SPLIT_DIR` — `>` lit le buffer A, `<` lit le buffer B (défaut).
- `SEP_SHMEM_DUMP` — lecture unique de l'en-tête de la mémoire partagée du SEP.

Sorties : `sep.log` (messages filtrés) et un dossier `sep.log.ool/` de fichiers `.bin` (contenus
OOL). **Vérifié** : lecture seule, traductions DART contrôlées contre la RAM.

## Capture (`tools/boot_and_trace.sh`)

Démarre macOS 13.5 sous m1n1 avec le traceur et enregistre la session. Arguments : un nom de
capture ; options par variables (`TRACE_SCRIPT`, `TRACE_TIMEOUT`, `LIVE_EPS`, plus les `SEP_*`
ci-dessus). Chaîne un m1n1 frais avant chaque capture (ABI instable). N'envoie rien au SEP :
observation pure. `tools/mark.sh` pose des marqueurs horaires pendant une capture (sessions
humaines).

## Boot du SEP sans macOS (`pending/sep_boot.sh`)

Script de démarrage de SEPOS sous m1n1 seul (code public m1n1, DART `t6000`). Classé dans
`pending/` car il écrit vers le SEP : **lancé par Albert**, pas par un agent. A produit SEP-BOOT
(7/12 endpoints, [chapitre 3](03-boot-sep.md)).

## Accès au Linux de test (`tools/linux_ssh.sh`)

Accès root à la partition Asahi de test (adresse `10.0.200.4`, via VPN), **uniquement** pour
compiler et charger les modules de `driver/linux/`. Filtre intégré refusant les commandes
touchant aux disques, au boot, à m1n1 ou au SEP. Journal : `logs/linux_ssh.log`.

## Pilote capteur Linux (`driver/linux/`)

- `mesa_transport.h` — **couche transport réutilisable**, base du futur pilote : prise/relâche du
  capteur, alimentation, émission, lecture, lecture d'état, et `mesa_wait_ready` (attente réactive
  de la broche « donnée prête » par scrutation bornée, [chapitre 6](06-capteur-mesa.md)).
- `mesa_probe.c` — client « bonjour » : rejoue la séquence vérifiée et lit l'identité. **Vérifié**
  sur le Mac (identité identique), transport réactif.
- `mesa_statloop.c`, `mesa_irqwatch.c` — clients de test (stabilité de l'état au repos ;
  caractérisation de la broche 195). Démontrent la réutilisation du transport.
- `mesa_ovl.c` + `mesa-spi2-overlay.dts` — ajout **à chaud** du nœud `spi2` et du capteur au
  device tree vivant (phandles numériques relevés sur le noyau de test), sans rien installer :
  un redémarrage enlève tout. **Vérifié** : le capteur apparaît et répond.

## Rejeu hors ligne (`driver/`)

Harnais de rejeu (`sepreplay`, 29 tests) qui rejoue les captures hors matériel : séquence
d'init `sbio`, structure des messages et CRC, transferts d'image (CRC et reconstitution),
export/import catacomb. Permet de valider des hypothèses de protocole sans toucher au Mac.

## Analyses (`analysis/`)

Scripts d'analyse hors ligne des traces, dont `cmp_sensor_sep_image.py` (comparaison image bus ↔
SEP) et `count_sensor_vs_sep_images.py` (comptage images lues/transmises), cités au
[chapitre 6](06-capteur-mesa.md).
