#!/usr/bin/env bash
# Démarre macOS 13.5 sous l'hyperviseur m1n1 avec le tracer SEP, et enregistre la sortie.
# Observation pure : ce script n'envoie rien au SEP lui-même.
#
# Usage : ./tools/boot_and_trace.sh <nom-de-capture> [--interactive]
#   --interactive : pas de timeout, pour les sessions humaines (doigt sur le capteur…)
set -euo pipefail
source "$(dirname "$0")/env.sh"

NAME="${1:-}"; [ -n "$NAME" ] || die "usage: $0 <nom-de-capture> [--interactive]"
MODE="${2:-}"

require_mac
[ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
[ -f "$MACOS_KERNEL" ] || die "kernel macOS absent : $MACOS_KERNEL (voir README §3)"
[ -f "$TRACE_SCRIPT" ] || die "script de trace absent : $TRACE_SCRIPT (tâche de l'agent tracer)"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$TRACES_DIR/${STAMP}_${NAME}"
mkdir -p "$OUT"

{
  echo "date: $STAMP"
  echo "name: $NAME"
  echo "mode: ${MODE:-auto}"
  echo "m1n1_commit: $(git -C "$M1N1_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
  echo "trace_script: $TRACE_SCRIPT"
  echo "kernel: $MACOS_KERNEL"
  echo "bootargs: $MACOS_BOOTARGS"
} > "$OUT/meta.txt"

# 1. Chainload d'un m1n1 frais : obligatoire, l'ABI de l'hyperviseur est instable.
python3 "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log"
sleep 2
require_mac

# 2. UART virtuel de l'hyperviseur (logs macOS) en arrière-plan, si dispo.
if [ -e "$HV_UART" ]; then
  ( stty -F "$HV_UART" 500000 raw -echo 2>/dev/null; cat "$HV_UART" ) > "$OUT/hv_uart.log" 2>&1 &
  UART_PID=$!
  trap 'kill $UART_PID 2>/dev/null || true' EXIT
fi

# 3. macOS sous hyperviseur avec le tracer.
CMD=(python3 "$M1N1_DIR/proxyclient/tools/run_guest.py" -m "$TRACE_SCRIPT" "$MACOS_KERNEL" -- "$MACOS_BOOTARGS")
echo "Capture -> $OUT"
if [ "$MODE" = "--interactive" ]; then
  "${CMD[@]}" 2>&1 | tee "$OUT/trace.log"
else
  timeout --signal=INT "$TRACE_TIMEOUT" "${CMD[@]}" 2>&1 | tee "$OUT/trace.log" || true
fi

echo "lines: $(wc -l < "$OUT/trace.log")" >> "$OUT/meta.txt"
echo "Terminé. Pense à noter la capture dans docs/journal.md."
