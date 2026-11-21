#!/usr/bin/env bash
# =============================================================================
# LANCEUR COURT — EXPÉRIENCE E1 (SBIO + STREAM 15 DU DART), pour lancer depuis le tél.
#
#   Tape simplement :  ! ./pending/probe_sbio_stream15_go.sh
#
# Il lance EXACTEMENT :
#   M1N1TIMEOUT=20 SERVE_GL=1 PROBE_SBIO=1 SBIO_STREAM15=1 \
#       ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
#
# BUT, en clair : on sait (voie_sbio.md, n=3) que lorsqu'on démarre la puce par m1n1, qu'on lui
# REND son vrai coffre, puis qu'on pose la question « tu es là ? » (commande 0x73) à la partie
# empreinte (sbio), elle reste MUETTE. Le composant de traduction d'adresses (DART) de la puce
# annonce DEUX canaux (stream 0 ET stream 15), mais m1n1 n'en ouvre qu'UN (le 0). Hypothèse : la
# puce lit peut-être notre commande par le canal 15, qu'on n'a jamais ouvert -> elle ne la voit pas.
# Ce test OUVRE AUSSI le canal 15, place la commande sur les DEUX canaux, repose la même question,
# et lit la réponse.
#
# CE QUE ÇA TRANCHE (verdict imprimé à la fin) :
#   - La puce RÉPOND avec le canal 15 ouvert -> c'était bien un problème de CANAL (grande avancée,
#     sans risque). Le futur pilote devra utiliser le canal 15 pour la partie empreinte.
#   - Elle reste MUETTE -> ce n'est PAS le canal, c'est l'ÉTAT (sbio pas « armé » tant que le coffre
#     xART n'est pas re-scellé). On n'ira pas plus loin par cette voie sans écriture.
#
# NATURE DE L'ACTION / SÛRETÉ :
#   - « Ouvrir le canal 15 » = ÉCRITURE dans les tables de traduction d'adresses CÔTÉ PC (AP),
#     EXACTEMENT la même classe d'opération que l'ouverture du canal 0 déjà faite à chaque boot.
#     Ce n'est PAS une écriture vers la puce (pas 0x12/0x13/0x10/0x15, pas de gigalocker, pas d'IMG4).
#   - SERVE_GL : si la puce refuse le coffre et demande à re-sceller (SAVE), le script S'ARRÊTE SANS
#     acquitter -> le compteur n'avance PAS -> pas de brick. Au pire : essai « non concluant ».
#   - Le stream 0 reste programmé comme d'habitude : on n'enlève rien, on AJOUTE le stream 15.
#   - AUCUN disque touché, AUCUNE partition, AUCUN réglage Apple.
#
# C'est TOI qui lances (ligne rouge : écriture via SERVE_GL). L'agent ne lance pas.
#
# >>> PROTOCOLE EN 2 RUNS (obligatoire pour que ça tranche — un seul run ne suffit pas) :
#   Un run E1 seul ne prouve rien : il faut un JUMEAU sans le canal 15, pour comparer.
#   (1) RUN E1 : cold-boot physique -> puce en proxy -> lance CE script (avec canal 15).
#       Note le VERDICT imprimé + la ligne « [DART-faute après 0x73] » (sid fauté, causes, adresse).
#   (2) POWER-CYCLE physique OBLIGATOIRE entre les deux runs (cold-boot : chaque run part d'un état propre,
#       et le registre de faute DART repart à FLAG=0, sinon la comparaison est faussée).
#   (3) RUN DE CONTRÔLE : ./pending/probe_sbio_control_go.sh  (EXACTEMENT le même run, SANS le canal 15).
#   (4) COMPARE les deux. Lecture clé :
#       - sbio RÉPOND avec le canal 15, MUET sans -> c'était le CANAL (le pilote devra utiliser le canal 15).
#       - MUET dans les deux -> ce n'est PAS le canal, c'est l'ÉTAT de la puce.
#       - « [DART-faute] » : une faute de LECTURE sur le canal 15 au run de CONTRÔLE (sans canal 15 ouvert)
#         = preuve DIRECTE que la puce lit la commande par le canal 15, même muette.
#   DANS LES DEUX RUNS, vérifie que la comparaison est valide : sbio (0x08) bien ANNONCÉ, les 4 CNTL
#   d'ouverture sbio « acquittés », et le « 0x73 écrit … Envoi de la commande » bien présent. Si l'un
#   manque (ex. coffre refusé -> SAVE -> arrêt avant la sonde), le run ne compte pas : recommence.
#
# AVANT : COLD-BOOT REQUIS (power-cycle physique), puis puce en m1n1 proxy (« running proxy »,
#   ttyACM présent). Idéalement une sauvegarde faite.
#   Vérifie d'abord à blanc (ne touche pas le Mac) :
#     SERVE_GL=1 PROBE_SBIO=1 SBIO_STREAM15=1 SELFTEST=1 \
#         ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
# APRÈS : quel que soit le résultat, on ne renvoie rien, on coupe, on redémarre le Mac. Si ça fige :
#   POWER-CYCLE physique ; au pire DFU Restore depuis le PC (pending/dfu_restore.sh, éprouvé le 16/11).
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
SNEW="${1:-traces/20261111-113919_snew-reel}"
exec env M1N1TIMEOUT=20 SERVE_GL=1 PROBE_SBIO=1 SBIO_STREAM15=1 \
  ./pending/sep_xart_replay.sh "$SNEW"
