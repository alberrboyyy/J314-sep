#!/usr/bin/env bash
# Tente un reboot du Mac via le proxy m1n1. Ne marche que si m1n1 répond encore.
# Si le Mac est complètement gelé : appui long sur power (humain).
set -euo pipefail
source "$(dirname "$0")/env.sh"

require_mac
# API vérifiée (tracer, 2026-11-07, m1n1 70757dc7) : m1n1/setup.py crée `p = M1N1Proxy(...)`
# (pas de __all__, donc exporté par `import *`) ; M1N1Proxy.reboot() envoie P_REBOOT (0x010)
# avec no_reply=True (src/proxy.c -> reboot()). Équivalent upstream : proxyclient/tools/reboot.py.
# Ne marche que si m1n1 est en mode proxy (pas pendant qu'un guest tourne sous run_guest.py).
cd "$M1N1_DIR/proxyclient"
timeout 20 "$M1N1_PYTHON" -c 'from m1n1.setup import *; p.reboot()' \
  || die "reboot via proxy impossible : intervention physique nécessaire."
echo "Reboot demandé."
