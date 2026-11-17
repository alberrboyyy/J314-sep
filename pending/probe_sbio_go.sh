#!/usr/bin/env bash
# =============================================================================
# LANCEUR COURT — ESSAI D (SONDE sbio), pour lancer depuis le tél (Remote Control).
#
#   Tape simplement :  ! ./pending/probe_sbio_go.sh
#
# Il lance EXACTEMENT :
#   M1N1TIMEOUT=20 PROBE_SBIO=1 FOLLOW=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
#
# CE QUE ÇA FAIT, en clair : démarre la puce par m1n1, lui rend son « coffre » (FOLLOW) jusqu'à
# ce qu'elle réveille la partie empreinte (sbio), puis lui pose UNE question inoffensive
# (« tu es là ? », commande 0x73, SANS doigt) et lit sa réponse. But : savoir si la partie
# empreinte est seulement allumée de nom, ou si elle répond vraiment.
#
# C'est une ÉCRITURE vers la puce (FOLLOW acquitte des re-scellements) : règle rouge = c'est TOI
# qui lances, jamais l'agent. Ce lanceur ne fait que fixer les variables et appeler le vrai script
# (dont l'en-tête explique but/risque/résultat, section « MODE PROBE_SBIO »). Il ne touche AUCUN
# disque, AUCUNE partition, AUCUN réglage Apple.
#
# AVANT : la puce doit être en m1n1 proxy (écran « running proxy », ttyACM présent). Idéalement,
#   une sauvegarde faite. Si ça rate / fige : récup = POWER-CYCLE PHYSIQUE, et au pire DFU Restore
#   depuis le PC (pending/dfu_restore.sh, déjà éprouvé le 16/11).
# APRÈS : quel que soit le résultat, on ne renvoie rien, on coupe, on redémarre le Mac.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
SNEW="${1:-traces/20261111-113919_snew-reel}"
exec env M1N1TIMEOUT=20 PROBE_SBIO=1 FOLLOW=1 ./pending/sep_xart_replay.sh "$SNEW"
