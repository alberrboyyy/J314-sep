#!/usr/bin/env bash
# tools/catch_loop.sh — garde le Mac en proxy EN PERMANENCE (catcher permanent).
#
# Lancer UNE fois en arrière-plan ; ensuite, à CHAQUE power-cycle du Mac, le proxy est
# re-rattrapé automatiquement — plus besoin de relancer catch_proxy à la main.
#
# Fonctionnement :
#   1. catch un boot (via catch_lib.sh : saisie du nœud brut + chainload d'un m1n1 frais) ;
#   2. attend que CE port DISPARAISSE (= prochain power-cycle du Mac) ;
#   3. re-catch au boot suivant. En boucle.
# Tant que le proxy est up, il ne fait que SURVEILLER la présence du port (il ne l'ouvre pas)
#   -> AUCUNE interférence avec un script pending/ qui tourne sur ce proxy.
#
# NON DESTRUCTIF : uniquement du chainload (RAM), comme catch_proxy. Aucune écriture SEP/disque.
# Arrêt : pkill -f '[c]atch_loop.sh'
#
# On ne met PAS `-e` : une fenêtre ratée (die -> exit 1 dans le sous-shell) ne doit PAS tuer la boucle.
set -uo pipefail
source "$(dirname "$0")/env.sh"
source "$(dirname "$0")/catch_lib.sh"
export WAIT_S="${WAIT_S:-90}"   # fenêtre d'attente par itération

echo ">>> [catch_loop] démarré. Power-cycle le Mac quand tu veux : je rattrape le proxy à chaque fois."
while true; do
  # catch_proxy_run peut appeler die() (exit 1) sur une fenêtre ratée -> sous-shell pour contenir l'exit.
  if ( catch_proxy_run ); then
    refresh_ports
    port="${M1N1DEVICE:-}"
    echo ">>> [catch_loop] PROXY UP ($port). J'attends le prochain power-cycle (disparition du port)…"
    while [ -n "$port" ] && [ -e "$port" ]; do sleep 1; done
    echo ">>> [catch_loop] port disparu -> je re-catch au prochain boot."
  else
    sleep 1   # fenêtre ratée/timeout : on repart attendre
  fi
done
