#!/usr/bin/env bash
# Pose un repère horodaté dans la capture EN COURS (lancée par tools/boot_and_trace.sh).
# N'accède pas au Mac : écrit seulement une ligne dans <dossier de capture>/marks.txt.
#
# Usage : ./tools/mark.sh <étiquette>
#   Étiquette : un seul mot, [A-Za-z0-9._:-]+ (ex. doigt_pose, unlock-1).
#   Ligne écrite : "<epoch, 6 décimales> <étiquette>".
#   Horloge : temps réel du PC (date +%s.%6N = CLOCK_REALTIME), la même que le time.time() du
#   tracer hv/trace_sep_filtered.py, qui tourne sur le même PC.
# Refuse s'il n'y a pas de capture en cours ($REPO_ROOT/.current_capture absent, ou PID mort).
# Exploitation : python3 analysis/parse_trace.py <dossier> --between <étiq1> <étiq2>
set -euo pipefail
# Pas de `source env.sh` : il résout les ports série ; ce script ne doit rien toucher côté matériel.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRACES_DIR="$REPO_ROOT/traces"
die() { echo "ERREUR: $*" >&2; exit 1; }

LABEL="${1:-}"
[ $# -eq 1 ] && [ -n "$LABEL" ] || die "usage: $0 <étiquette>  (un seul argument)"
[[ "$LABEL" =~ ^[A-Za-z0-9._:-]+$ ]] || die "étiquette invalide : '$LABEL' (autorisé : A-Z a-z 0-9 . _ : -)"

STATE_FILE="$REPO_ROOT/.current_capture"
[ -f "$STATE_FILE" ] || die "pas de capture en cours ($STATE_FILE absent)."
OUT="$(sed -n 1p "$STATE_FILE")"
PID="$(sed -n 2p "$STATE_FILE")"
[[ "$PID" =~ ^[0-9]+$ ]] && kill -0 "$PID" 2>/dev/null \
  || die "pas de capture en cours : $STATE_FILE est périmé (PID '${PID}' mort). Fichier laissé tel quel."
[ -d "$OUT" ] || die "dossier de capture introuvable : $OUT"
case "$(realpath "$OUT")/" in
  "$(realpath "$TRACES_DIR")"/*/) ;;
  *) die "dossier de capture hors de traces/ : $OUT" ;;
esac

TS="$(date +%s.%6N)"
[[ "$TS" =~ ^[0-9]+\.[0-9]{6}$ ]] || die "horloge : sortie inattendue de date ($TS)"
printf '%s %s\n' "$TS" "$LABEL" >> "$OUT/marks.txt"
echo "$(date -d "@$TS" +%H:%M:%S.%6N)  $LABEL  ($TS -> $OUT/marks.txt)"
