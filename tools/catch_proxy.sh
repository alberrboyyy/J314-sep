#!/usr/bin/env bash
# tools/catch_proxy.sh — attrape m1n1 dans sa fenêtre d'attente au boot pour le FIXER en mode PROXY.
#
# POURQUOI : depuis la réinstall Asahi (installeur « UEFI only »/option 5), le m1n1 installé a un
#   payload (il enchaîne m1n1 -> U-Boot -> GRUB -> ALARM). Avec la backdoor activée en 1TR par Albert
#   (csrutil disable + nvram boot-args=-v), m1n1 ATTEND quelques secondes au boot que l'hôte l'attrape ;
#   si personne ne l'attrape, il continue sur Linux. Avant la réinstall, un m1n1 SANS payload tombait
#   en proxy tout seul (il était posé sur le volume macOS 13.5, aujourd'hui effacé).
#
# CE QUE FAIT CE SCRIPT (logique dans tools/catch_lib.sh, partagée avec les scripts pending/ natifs) :
#   1. attend (scrutation rapide) que les ports USB du m1n1 apparaissent — c.-à-d. que TU power-cycles
#      le Mac pendant que ce script tourne ;
#   2. ouvre le 2e port (if02) pour tenir la fenêtre (déclencheur « 2e TTY ouvert », doc Asahi) ;
#   3. chainloade un m1n1 frais -> le Mac reste sur « Running proxy... », prêt pour sep_peek / tethered_boot.
#   Le UartTimeout de ré-énumération après chainload est TOLÉRÉ (cosmétique) : le succès = port proxy présent.
#
# NON DESTRUCTIF : chainload = m1n1 envoyé en RAM. AUCUNE écriture disque, AUCUNE écriture SEP,
#   aucune commande Apple (bputil/kmutil/nvram), aucun partitionnement. Un simple reboot annule tout.
#
# USAGE :
#   ./tools/catch_proxy.sh        # puis POWER-CYCLE PHYSIQUE du Mac (bouton power)
#   WAIT_S=120 (défaut)           # délai max d'attente des ports
set -euo pipefail
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/catch_lib.sh"
catch_proxy_run
echo "   Prêt : ./tools/sep_peek.sh (lecture seule), ou un script pending/ natif (il re-catch tout seul)."
