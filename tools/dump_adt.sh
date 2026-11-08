#!/usr/bin/env bash
# Dump du device tree (ADT) du Mac en LECTURE SEULE, pour localiser le capteur Touch ID
# (docs/hypotheses.md « EXPÉRIENCE ADT-1 », docs/sensor_hw.md). Aucun hyperviseur, aucun guest macOS,
# aucune écriture MMIO, rien vers le SEP : seulement des readmem sur le blob ADT que m1n1 a reçu d'iBoot.
#
# Usage : ./tools/dump_adt.sh [nom]          (défaut : "adt" -> traces/<horodatage>_adt/)
#   SKIP_CHAINLOAD=1 : ne pas rechainloader m1n1 (si m1n1 frais déjà en mode proxy).
# Sortie : adt.bin (blob brut), adt.txt (arbre décodé par m1n1.adt), mesa.txt (analysis/adt_find_mesa.py),
#          meta.txt, dump.log.
# On n'utilise PAS m1n1.setup : il appelle PMU.reset_panic_counter() (écriture). Le client ci-dessous
# n'ouvre que le proxy et appelle get_adt() (readmem).
set -euo pipefail
source "$(dirname "$0")/env.sh"

NAME="${1:-adt}"
require_mac
[ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$TRACES_DIR/${STAMP}_${NAME}"
mkdir -p "$OUT"

{
  echo "date: $STAMP"
  echo "name: $NAME"
  echo "m1n1_commit: $(git -C "$M1N1_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
  echo "proxy_port: $M1N1DEVICE"
  echo "chainload: $([ "${SKIP_CHAINLOAD:-0}" = 1 ] && echo non || echo oui)"
} > "$OUT/meta.txt"

# 1. m1n1 frais (ABI instable), comme boot_and_trace.sh.
if [ "${SKIP_CHAINLOAD:-0}" != 1 ]; then
  "$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log"
  sleep 2
  require_mac
fi

# 2. Lecture de l'ADT (readmem uniquement).
export ADT_OUT="$OUT" M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
timeout 120 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "$OUT/dump.log"
import os, sys
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
from m1n1 import adt
out = os.environ["ADT_OUT"]
iface = UartInterface()
p = M1N1Proxy(iface, debug=False)
bootstrap_port(iface, p)
u = ProxyUtils(p)
data = u.get_adt()           # readmem
open(out + "/adt.bin", "wb").write(data)
tree = adt.load_adt(data)
open(out + "/adt.txt", "w").write(str(tree) + "\n")
print(f"ADT: {len(data)} octets")
PY

# 3. Vérifications et analyse locale.
[ -s "$OUT/adt.bin" ] && [ -s "$OUT/adt.txt" ] || die "dump vide ou absent : voir $OUT/dump.log"
grep -q 'biosensor,mesa' "$OUT/adt.txt" || echo "ATTENTION : 'biosensor,mesa' absent de adt.txt (dump tronqué ou nœud différent)."
python3 "$REPO_ROOT/analysis/adt_find_mesa.py" "$OUT/adt.txt" > "$OUT/mesa.txt" 2>&1 || echo "analyse échouée : voir $OUT/mesa.txt"
{ echo "adt_bytes: $(wc -c < "$OUT/adt.bin")"; echo "adt_txt_lines: $(wc -l < "$OUT/adt.txt")"; } >> "$OUT/meta.txt"
chmod a-w "$OUT"/adt.bin "$OUT"/adt.txt
echo "Terminé -> $OUT. Noter dans docs/journal.md ; le Mac reste en mode proxy (pas de reboot)."
