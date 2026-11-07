#!/usr/bin/env bash
# Démarre macOS 13.5 sous l'hyperviseur m1n1 avec le tracer SEP, et enregistre la sortie.
# Observation pure : ce script n'envoie rien au SEP lui-même.
#
# Usage : ./tools/boot_and_trace.sh <nom-de-capture> [--interactive]
#   (défaut, AUTO) : capture de TRACE_TIMEOUT secondes, puis arrêt propre : SIGINT -> shell HV -> reboot()
#                    (reboot matériel du Mac via m1n1), et attente du retour de m1n1 en mode proxy.
#                    END_ACTION=none pour laisser macOS tourner sous HV (le client reste vivant jusqu'au timeout).
#   --interactive  : pas de timeout, stdin = ton terminal (Ctrl-C -> shell HV ; `reboot()` pour finir).
#   TRACE_SCRIPT=none : pas de tracer (expériences de type H2).
#   LIVE_EPS (mode AUTO) : endpoints affichés en direct dans le terminal à partir de sep.log
#                    (défaut 0x08 ; "all" = tous ; "none" = pas d'affichage direct). N'affecte pas
#                    le contenu de sep.log (filtré, lui, par SEP_EPS).
# Pendant une capture, $REPO_ROOT/.current_capture contient le dossier de capture et le PID de ce
# script (utilisé par tools/mark.sh) ; il est effacé en fin de capture (trap EXIT).
set -euo pipefail
source "$(dirname "$0")/env.sh"

NAME="${1:-}"; [ -n "$NAME" ] || die "usage: $0 <nom-de-capture> [--interactive]"
MODE="${2:-}"

require_mac
[ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
[ -f "$MACOS_KERNEL" ] || die "kernel macOS absent : $MACOS_KERNEL (voir README §3)"
[ "$TRACE_SCRIPT" = none ] || [ -f "$TRACE_SCRIPT" ] || die "script de trace absent : $TRACE_SCRIPT"
END_ACTION="${END_ACTION:-reboot}"

# Filtre d'affichage direct, validé AVANT de toucher au Mac (set -e ne doit pas tuer le script en pleine capture).
LIVE_EPS="${LIVE_EPS:-0x08}"
live_re='.'
case "$LIVE_EPS" in
  all|none) ;;
  *) live_re=""
     for e in ${LIVE_EPS//,/ }; do
       [[ "$e" =~ ^(0[xX][0-9a-fA-F]{1,2}|[0-9]{1,3})$ ]] && (( e <= 0xff )) || die "LIVE_EPS invalide : $e"
       live_re+="${live_re:+|}EP=$(printf '0x%02x' "$e")"
     done
     live_re=" ($live_re) " ;;
esac
[ "$LIVE_EPS" = none ] || command -v gawk >/dev/null || die "gawk requis pour l'affichage direct (ou LIVE_EPS=none)"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$TRACES_DIR/${STAMP}_${NAME}"
mkdir -p "$OUT"

# Nettoyage unique (un seul trap EXIT : les traps successifs s'écrasaient).
STATE_FILE="$REPO_ROOT/.current_capture"
UART_PID=""; LIVE_PID=""; CTLDIR=""
cleanup() {
  [ -n "$LIVE_PID" ] && kill "$LIVE_PID" 2>/dev/null || true
  [ -n "$UART_PID" ] && kill "$UART_PID" 2>/dev/null || true
  [ -n "$CTLDIR" ] && rm -rf "$CTLDIR"
  # N'efface l'état que s'il désigne encore cette capture.
  if [ -f "$STATE_FILE" ] && [ "$(head -n1 "$STATE_FILE" 2>/dev/null)" = "$OUT" ]; then
    rm -f "$STATE_FILE"
  fi
}
trap cleanup EXIT
printf '%s\n%s\n' "$OUT" "$$" > "$STATE_FILE"

{
  echo "date: $STAMP"
  echo "name: $NAME"
  echo "mode: ${MODE:-auto}"
  echo "timeout_s: $TRACE_TIMEOUT"
  echo "end_action: $END_ACTION"
  echo "m1n1_commit: $(git -C "$M1N1_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
  echo "trace_script: $TRACE_SCRIPT"
  echo "kernel: $MACOS_KERNEL"
  echo "bootargs: $MACOS_BOOTARGS"
  echo "proxy_port: $M1N1DEVICE"
} > "$OUT/meta.txt"

# 1. Chainload d'un m1n1 frais : obligatoire, l'ABI de l'hyperviseur est instable.
"$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log"
sleep 2
require_mac

echo "hv_uart_port: ${HV_UART:-absent}" >> "$OUT/meta.txt"

# 2. UART virtuel de l'hyperviseur (logs macOS) en arrière-plan, si dispo.
if [ -e "$HV_UART" ]; then
  ( stty -F "$HV_UART" 500000 raw -echo 2>/dev/null; cat "$HV_UART" ) > "$OUT/hv_uart.log" 2>&1 &
  UART_PID=$!
fi

# 3. macOS sous hyperviseur avec le tracer (messages SEP -> $OUT/sep.log, console -> trace.log).
export SEP_TRACE_OUT="$OUT/sep.log"
CMD=("$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/run_guest.py")
[ "$TRACE_SCRIPT" = none ] || CMD+=(-m "$TRACE_SCRIPT")
CMD+=("$MACOS_KERNEL" -- "$MACOS_BOOTARGS")
echo "Capture -> $OUT"
if [ "$MODE" = "--interactive" ]; then
  "${CMD[@]}" 2>&1 | tee "$OUT/trace.log" || true
else
  # stdin du client = FIFO de contrôle : permet d'envoyer des commandes au shell HV sans terminal.
  CTLDIR="$(mktemp -d)"; CTL="$CTLDIR/hvctl"; mkfifo "$CTL"
  exec 3<>"$CTL"                       # garde la FIFO ouverte (pas d'EOF pour le shell)
  "${CMD[@]}" <"$CTL" > >(tee "$OUT/trace.log") 2>&1 &
  GPID=$!
  # Affichage direct (lecture seule de sep.log). tail --pid=$$ : tail meurt avec ce script même
  # en cas de kill brutal ; awk s'arrête sur EOF quand tail meurt. Pas d'orphelin.
  if [ "$TRACE_SCRIPT" != none ] && [ "$LIVE_EPS" != none ]; then
    tail --pid=$$ -n +1 -F "$SEP_TRACE_OUT" 2>/dev/null > >(gawk -v re="$live_re" '
      /^#/ { next }
      $0 ~ re { printf "[sep %s.%03d] %s\n", strftime("%H:%M:%S", int($1)), int(($1 - int($1)) * 1000),
                       substr($0, index($0, " ") + 1); fflush() }') &
    LIVE_PID=$!
    echo "affichage direct : EP ${LIVE_EPS} (LIVE_EPS) depuis $SEP_TRACE_OUT"
  fi
  end_reason="timeout"
  for ((t=0; t<TRACE_TIMEOUT; t+=5)); do
    sleep 5
    kill -0 "$GPID" 2>/dev/null || { end_reason="client_exited"; break; }
    # Arrêt anticipé demandé par tools/stop_capture.sh
    [ -f "$REPO_ROOT/.stop_capture" ] && { rm -f "$REPO_ROOT/.stop_capture"; end_reason="stop_requested"; break; }
  done
  echo "end_reason: $end_reason" >> "$OUT/meta.txt"
  if kill -0 "$GPID" 2>/dev/null && [ "$END_ACTION" = reboot ]; then
    echo ">> arrêt : SIGINT -> shell HV"
    kill -INT "$GPID"
    for ((t=0; t<30; t++)); do grep -q "Entering hypervisor shell" "$OUT/trace.log" 2>/dev/null && break; sleep 1; done
    echo ">> reboot() via shell HV"
    echo 'reboot()' >&3
    for ((t=0; t<30; t++)); do kill -0 "$GPID" 2>/dev/null || break; sleep 1; done
    kill -0 "$GPID" 2>/dev/null && { echo "client toujours vivant : SIGTERM"; kill -TERM "$GPID" || true; }
    echo ">> attente du retour de m1n1 en mode proxy (180 s max)"
    back=no
    for ((t=0; t<180; t+=3)); do sleep 3; [ -n "$(m1n1_port if00)" ] && { back=yes; break; }; done
    echo "proxy_back_after_reboot: $back" >> "$OUT/meta.txt"
    [ "$back" = yes ] || echo "ATTENTION : m1n1 n'est pas revenu en mode proxy : intervention physique nécessaire."
  fi
  wait "$GPID" 2>/dev/null || true
  exec 3>&-
fi

# Laisse tail afficher les dernières lignes puis l'arrête (le trap EXIT le ferait aussi).
if [ -n "$LIVE_PID" ]; then sleep 1; kill "$LIVE_PID" 2>/dev/null || true; LIVE_PID=""; fi
echo "lines: $(wc -l < "$OUT/trace.log")" >> "$OUT/meta.txt"
echo "live_eps: ${LIVE_EPS:-none}" >> "$OUT/meta.txt"
[ -f "$OUT/marks.txt" ] && echo "marks: $(grep -vc '^#' "$OUT/marks.txt")" >> "$OUT/meta.txt"
echo "sep_eps: ${SEP_EPS:-all}" >> "$OUT/meta.txt"
[ -f "$OUT/sep.log" ] && echo "sep_lines: $(wc -l < "$OUT/sep.log")" >> "$OUT/meta.txt"
echo "Terminé. Pense à noter la capture dans docs/journal.md."
