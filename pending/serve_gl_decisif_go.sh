#!/usr/bin/env bash
# =============================================================================
# ⚠️⚠️  TEST DÉCISIF — RISQUÉ (ACK_SAVE)  ⚠️⚠️     (idée du sceptique, décidé par Albert le 2026-11-18)
#
#   Tape :  ! ./pending/serve_gl_decisif_go.sh
#
# Il lance EXACTEMENT :
#   M1N1TIMEOUT=20 SERVE_GL=1 ACK_SAVE=1 PROBE_SBIO=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
#
# EN CLAIR : comme serve_gl_go.sh, MAIS cette fois on NE s'arrête PLUS sur le SAVE — on l'ACQUITTE, pour
# laisser la puce AVANCER et voir ce qu'elle fait après :
#   - si elle se met à FETCH ses gigalockers (0x05) puis répond au 0x73  → VOIE C VIVANTE (énorme) ;
#   - si elle enchaîne des SAVE sans jamais devenir fonctionnelle (garde-fou à 40) → VOIE C FERMÉE (verdict B).
# C'est le SEUL test qui tranche définitivement la question.
#
# ⚠️ POURQUOI C'EST RISQUÉ (à lire avant de lancer) :
#   Acquitter le SAVE fait AVANCER le COMPTEUR ANTI-REJEU scellé de la puce (il vit dans un composant
#   matériel, pas sur le disque). Le coffre sur disque, lui, ne bouge pas → DÉSYNC → au prochain boot macOS
#   la puce peut REFUSER son état → Touch ID (et déverrouillage macOS) cassés. C'est une écriture qui ne se
#   « dé-fait » pas toute seule.
#
# 🛟 RÉCUPÉRATION (filet prêt, éprouvé le 2026-11-17) :
#   DFU Restore → puce ré-initialisée (SEP propre) → re-restore Linux depuis ~/mac-dfu/alarm_p5.img →
#   ré-enrôler Touch ID. Outils présents : ~/mac-dfu/UniversalMac_27.2.1_26B131_Restore.ipsw (+ idevicerestore),
#   ~/mac-dfu/alarm_p5.img (+ .sha256 à vérifier AVANT). macOS est sacrifiable.
#
# PRONOSTIC HONNÊTE : d'après tout ce qu'on a trouvé (fraîcheur dans une puce matérielle, nonce ROM non
#   semable côté AP, emballage prouvé correct), ce test va TRÈS PROBABLEMENT enchaîner des SAVE = confirmer
#   « voie C fermée ». Il apporte une CERTITUDE, pas un succès attendu. À faire en connaissance de cause.
#
# PRÉ-REQUIS AVANT DE LANCER (ordre) :
#   1. Backup vérifié : `cd ~/mac-dfu && sha256sum -c alarm_p5.img.sha256` → OK.
#   2. Mac en proxy m1n1 FRAIS (cold-boot physique + catch_proxy), comme serve_gl_go.sh.
#   3. (recommandé) avoir déjà fait les tests SANS risque d'abord (sbio E1, input pourri).
#   Vérif à blanc possible : SERVE_GL=1 ACK_SAVE=1 SELFTEST=1 ./pending/sep_xart_replay.sh traces/20261111-113919_snew-reel
#
# C'est une ÉCRITURE vers la puce, la plus risquée du projet : règle rouge = c'est TOI qui lances. L'agent
#   ne lance JAMAIS ça. APRÈS : on coupe ; prévoir le DFU Restore pour récupérer Touch ID.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
SNEW="${1:-traces/20261111-113919_snew-reel}"
exec env M1N1TIMEOUT=20 SERVE_GL=1 ACK_SAVE=1 PROBE_SBIO=1 ./pending/sep_xart_replay.sh "$SNEW"
