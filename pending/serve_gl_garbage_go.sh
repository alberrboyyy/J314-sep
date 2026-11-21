#!/usr/bin/env bash
# =============================================================================
# LANCEUR COURT — ESSAI DE CONTRÔLE « INPUT POURRI » (idée du sceptique, 2026-11-18)
#
#   Tape simplement :  ! ./pending/serve_gl_garbage_go.sh
#
# Il lance EXACTEMENT :
#   M1N1TIMEOUT=20 SERVE_GL=1 GL_GARBAGE=1 PROBE_SBIO=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
#
# EN CLAIR : comme serve_gl_go.sh, MAIS on sert à la puce des maîtres BIDON — même longueur, remplis de
# zéros au lieu du vrai contenu scellé. On regarde si elle réagit différemment.
#
# CE QUE ÇA TRANCHE :
#   - Si la puce donne le MÊME SAVE@TAG05 qu'avec les VRAIS maîtres → elle n'évalue même pas ce qu'on lui
#     sert → ça appuie fortement « B′ » (elle re-scelle quoi qu'on fasse, le rejeu pur est mort).
#   - Si le comportement CHANGE (autre message, erreur, autre point d'arrêt) → la puce ÉVALUE le contenu
#     → l'emballage/contenu compte encore, la voie « servir le bon coffre » reste à creuser.
#   À comparer au run de référence `traces/20261118-085250_xart_replay` (vrais maîtres corrects). Fais n>=2.
#
# SÛR (fail-closed, identique à serve_gl_go.sh) : on n'acquitte JAMAIS un SAVE → le compteur anti-rejeu
#   n'avance pas → AUCUNE écriture persistée dans la puce → pas de brick. Au pire : essai non concluant.
#   AUCUN disque touché, AUCUNE partition, AUCUN réglage Apple. Servir des zéros n'est pas plus risqué que
#   servir le vrai coffre (même classe d'écriture vers le tampon partagé, arrêt avant tout SAVE).
#
# C'est une ÉCRITURE vers la puce : règle rouge = c'est TOI qui lances, jamais l'agent.
# AVANT : Mac en proxy m1n1 FRAIS (cold-boot physique + catch_proxy, comme pour serve_gl_go.sh).
#   Vérifie d'abord à blanc :  SERVE_GL=1 GL_GARBAGE=1 SELFTEST=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
# APRÈS : quel que soit le résultat, on ne renvoie rien, on coupe, on redémarre le Mac.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
SNEW="${1:-traces/20261111-113919_snew-reel}"
exec env M1N1TIMEOUT=20 SERVE_GL=1 GL_GARBAGE=1 PROBE_SBIO=1 ./pending/sep_xart_replay.sh "$SNEW"
