#!/usr/bin/env bash
# =============================================================================
# LANCEUR COURT — ESSAI E (RENDRE LE VRAI COFFRE), pour lancer depuis le tél.
#
#   Tape simplement :  ! ./pending/serve_gl_go.sh
#
# Il lance EXACTEMENT :
#   M1N1TIMEOUT=20 SERVE_GL=1 PROBE_SBIO=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
#
# EN CLAIR : démarre la puce par m1n1, lui REND SON VRAI COFFRE (lu sur ton disque, celui qui colle à
# ta puce réparée + Touch ID ré-enrôlé), et regarde si elle va jusqu'au bout — jusqu'à réveiller la
# partie empreinte. Si oui, lui pose UNE question inoffensive (0x73, SANS doigt) pour voir si elle
# RÉPOND vraiment. C'est le premier vrai test de toute l'approche avec un coffre qui colle.
#
# C'est une ÉCRITURE vers la puce : règle rouge = c'est TOI qui lances, jamais l'agent.
# SÛR : si la puce refuse le coffre, elle demande à re-sceller (SAVE) et le script S'ARRÊTE SANS
#   acquitter → le compteur n'avance pas → pas de brick. Au pire : essai « non concluant ».
# AUCUN disque touché, AUCUNE partition, AUCUN réglage Apple.
#
# AVANT : puce en m1n1 proxy (« running proxy », ttyACM présent). Idéalement une sauvegarde faite.
#   Vérifie d'abord à blanc :  SERVE_GL=1 SELFTEST=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
#   (montre ce qui serait servi, sans toucher le Mac).
# APRÈS : quel que soit le résultat, on ne renvoie rien, on coupe, on redémarre le Mac. Si ça fige :
#   POWER-CYCLE physique ; au pire DFU Restore depuis le PC (pending/dfu_restore.sh, éprouvé le 16/11).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
SNEW="${1:-traces/20261111-113919_snew-reel}"
exec env M1N1TIMEOUT=20 SERVE_GL=1 PROBE_SBIO=1 ./pending/sep_xart_replay.sh "$SNEW"
