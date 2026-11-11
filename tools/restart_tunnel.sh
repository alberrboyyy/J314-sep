#!/usr/bin/env bash
# Relance le tunnel relais (pur transport, aucun accès SEP) : vide les octets périmés
# après une extinction / un reboot du Mac. Voir mémoire tunnel-relais-mac.
# Usage : ./tools/restart_tunnel.sh
cd "$(dirname "$0")/.."
echo "arrêt de l'ancien tunnel…"
pkill -f '[t]unnel.py' 2>/dev/null && sleep 1 || echo "  (aucun tunnel à arrêter)"
echo "démarrage d'un tunnel neuf…"
setsid -f python3 tunnel.py >/tmp/tunnel.log 2>&1
sleep 2
if pgrep -f '[t]unnel.py' >/dev/null && [ -e /tmp/m1n1 ]; then
  echo "tunnel relancé  ->  $(ls -l /tmp/m1n1 | awk '{print $NF}')"
else
  echo "ÉCHEC : tunnel non démarré (voir /tmp/tunnel.log)"
  tail -3 /tmp/tunnel.log 2>/dev/null
fi
