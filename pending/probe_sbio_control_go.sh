#!/usr/bin/env bash
# =============================================================================
# LANCEUR COURT — RUN DE CONTRÔLE de l'EXPÉRIENCE E1 (SBIO, SANS stream 15), pour le tél.
#
#   Tape simplement :  ! ./pending/probe_sbio_control_go.sh
#
# Il lance EXACTEMENT :
#   M1N1TIMEOUT=20 SERVE_GL=1 PROBE_SBIO=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
#
# C'est le JUMEAU de probe_sbio_stream15_go.sh, mais SANS ouvrir le canal 15 (pas de SBIO_STREAM15=1) :
# la puce est interrogée dans les conditions NORMALES de m1n1 (seul le canal 0 est ouvert). Tout le reste
# est identique : on rend le vrai coffre (SERVE_GL), puis on pose la commande « tu es là ? » (0x73) à la
# partie empreinte (sbio) et on lit la réponse + l'état de faute du composant de traduction (DART).
#
# POURQUOI CE RUN : un run E1 (avec canal 15) tout seul ne tranche pas. Il faut COMPARER E1 à ce contrôle.
#   - Si sbio reste MUET AVEC le canal 15 ET sans -> ce n'est pas le canal (c'est l'état de la puce).
#   - Si sbio RÉPOND avec le canal 15 mais reste MUET ici -> c'était bien le canal 15 (grande avancée).
#   - Lecture de faute DART : si ici (sans canal 15) la puce déclenche une faute de LECTURE sur le canal 15,
#     c'est la preuve DIRECTE qu'elle lit la commande par le canal 15 — même si elle reste muette.
#
# NATURE DE L'ACTION / SÛRETÉ : identique à probe_sbio_stream15_go.sh SAUF qu'on n'ajoute PAS le canal 15.
#   - SERVE_GL : si la puce refuse le coffre et demande à re-sceller (SAVE), le script S'ARRÊTE SANS
#     acquitter -> le compteur n'avance PAS -> pas de brick. Au pire : essai « non concluant ».
#   - Lecture du registre de faute DART = un simple relevé (lecture seule), aucun risque.
#   - AUCUN disque touché, AUCUNE partition, AUCUN réglage Apple, aucune écriture vers la puce.
#
# C'est TOI qui lances (ligne rouge : écriture via SERVE_GL). L'agent ne lance pas.
#
# AVANT : COLD-BOOT REQUIS (power-cycle physique), puis puce en m1n1 proxy (« running proxy »,
#   ttyACM présent). Le run de contrôle doit se faire sur un boot DIFFÉRENT du run E1 (cold-boot
#   obligatoire ENTRE les deux runs : voir probe_sbio_stream15_go.sh « PROTOCOLE EN 2 RUNS »).
#   Vérifie d'abord à blanc (ne touche pas le Mac) :
#     SERVE_GL=1 PROBE_SBIO=1 SELFTEST=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
# APRÈS : quel que soit le résultat, on ne renvoie rien, on coupe, on redémarre le Mac. Si ça fige :
#   POWER-CYCLE physique ; au pire DFU Restore depuis le PC (pending/dfu_restore.sh, éprouvé le 16/11).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
SNEW="${1:-traces/20261111-113919_snew-reel}"
exec env M1N1TIMEOUT=20 SERVE_GL=1 PROBE_SBIO=1 \
  ./pending/sep_xart_replay.sh "$SNEW"
