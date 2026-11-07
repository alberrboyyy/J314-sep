#!/usr/bin/env bash
# Tente un reboot du Mac via le proxy m1n1. Ne marche que si m1n1 répond encore.
# Si le Mac est complètement gelé : appui long sur power (humain).
set -euo pipefail
source "$(dirname "$0")/env.sh"

require_mac
# TODO (tracer) : vérifier l'API exacte dans m1n1/proxyclient (m1n1.setup / proxy.reboot).
cd "$M1N1_DIR/proxyclient"
timeout 20 python3 -c 'from m1n1.setup import *; p.reboot()' \
  || die "reboot via proxy impossible : intervention physique nécessaire."
echo "Reboot demandé."
