#!/usr/bin/env bash
# =============================================================================
# LANCEUR COURT — ESSAI B (FOLLOW), pour lancer depuis le tél (Remote Control).
#
#   Tape simplement :  ! ./pending/follow_go.sh
#
# Il lance EXACTEMENT :
#   M1N1TIMEOUT=20 FOLLOW=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
#
# C'est une ÉCRITURE vers le SEP (acquitte les re-scellements) : règle rouge = c'est TOI qui
# lances, jamais l'agent. Ce lanceur ne fait que fixer les variables et appeler le vrai script
# (dont l'en-tête explique but/risque/résultat). Il ne touche pas au disque.
#
# RAPPELS :
#   - Le Mac doit être en m1n1 proxy (écran « running proxy », ttyACM présent). Le script
#     chainloade un m1n1 frais tout seul.
#   - Si ça fige / UartTimeout : récup = POWER-CYCLE PHYSIQUE (impossible depuis le tél).
#   - Chaque power-cycle ne donne en gros qu'un seul bon essai (flakiness du lien connue).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
SNEW="${1:-traces/20261111-113919_snew-reel}"
exec env M1N1TIMEOUT=20 FOLLOW=1 ./pending/sep_xart_replay.sh "$SNEW"
