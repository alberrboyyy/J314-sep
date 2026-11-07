#!/usr/bin/env bash
# Demande l'arrêt anticipé de la capture en cours (mode auto) : boot_and_trace.sh fera
# SIGINT -> shell HV -> reboot() dans les 5 s, comme à la fin normale du timeout.
cd "$(dirname "$0")/.."
[ -f .current_capture ] || { echo "aucune capture en cours"; exit 1; }
./tools/mark.sh stop_requested >/dev/null 2>&1 || true
touch .stop_capture
echo "arrêt demandé pour $(sed -n 1p .current_capture)"
