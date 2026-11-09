#!/usr/bin/env bash
# État du SEP vu depuis m1n1 en mode proxy, SANS macOS, en LECTURE SEULE stricte.
#   1. Propriétés du nœud ADT /arm-io/sep (et /arm-io/dart-sep) : readmem du blob ADT, rien d'autre.
#   2. TROIS lectures MMIO 32 bits, toutes des registres d'état que m1n1 (src/asc.c) lit lui-même
#      pour savoir s'il peut envoyer/recevoir, sans jamais dépiler de message :
#        base+0x0044  CPU_CONTROL      (asc_is_running : read32 & START)
#        base+0x8110  A2I_CONTROL      (boîte AP->SEP : bits FULL/EMPTY/compteurs ; asc_can_send)
#        base+0x8114  I2A_CONTROL      (boîte SEP->AP : bits FULL/EMPTY/compteurs ; asc_can_recv)
#      base = adresse du reg[0] du nœud /arm-io/sep.
#   JAMAIS lus : 0x8830/0x8838 (OUTBOX, la lecture dépile un message), 0x8800/0x8808 (INBOX, envoi),
#   0x8810/0x8818 (A2I RECV), 0x8820/0x8828 (I2A SEND). CPU_STATUS (0x48) : non lu, effet de bord non
#   confirmé par une source publique. Aucune écriture, pas de m1n1.setup (qui écrit dans le PMU).
#
# Usage : ./tools/sep_peek.sh [nom]       (défaut "sep_peek" -> traces/<horodatage>_sep_peek/)
#   SKIP_CHAINLOAD=1 : ne pas rechainloader m1n1.
# Risque résiduel : lire un bloc non alimenté peut figer le bus ; le SEP est toujours alimenté
# (m1n1 le lit déjà au boot dans sep_init), et le script ne lit que si l'offset est dans la taille du reg.
set -euo pipefail
source "$(dirname "$0")/env.sh"

NAME="${1:-sep_peek}"
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
  echo "mmio_reads: CPU_CONTROL(+0x44) A2I_CONTROL(+0x8110) I2A_CONTROL(+0x8114)"
} > "$OUT/meta.txt"

if [ "${SKIP_CHAINLOAD:-0}" != 1 ]; then
  "$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log"
  sleep 2
  require_mac
fi

export PEEK_OUT="$OUT" M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
timeout 120 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "$OUT/peek.log"
import os, sys
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
from m1n1 import adt
out = os.environ["PEEK_OUT"]
iface = UartInterface()
p = M1N1Proxy(iface, debug=False)
bootstrap_port(iface, p)
u = ProxyUtils(p)
data = u.get_adt()                       # readmem
tree = adt.load_adt(data)

with open(out + "/adt_sep.txt", "w") as f:
    for path in ("/arm-io/sep", "/arm-io/dart-sep"):
        try:
            f.write(f"=== {path}\n{tree[path]}\n\n")
        except Exception as e:
            f.write(f"=== {path} : absent ({e})\n\n")
print("ADT sep écrit")

base, size = tree["/arm-io/sep"].get_reg(0)
lines = [f"sep_reg0_base: {base:#x}", f"sep_reg0_size: {size:#x}"]
# Liste blanche stricte : (nom, offset). Rien d'autre n'est lu.
WHITELIST = [("CPU_CONTROL", 0x44), ("A2I_CONTROL", 0x8110), ("I2A_CONTROL", 0x8114)]
for name, off in WHITELIST:
    if off + 4 > size:
        lines.append(f"{name} @ {base+off:#x}: NON LU (hors du reg[0], taille {size:#x})")
        continue
    v = p.read32(base + off)             # lecture MMIO 32 bits, sans effet de bord
    s = f"{name} @ {base+off:#x} = {v:#010x}"
    if name != "CPU_CONTROL":
        s += (f"  EMPTY={(v>>17)&1} FULL={(v>>16)&1} FIFOCNT={(v>>20)&0xf}"
              f" OVERFLOW={(v>>18)&1} RPTR={(v>>12)&0xf} WPTR={(v>>8)&0xf} ENABLE={v&1}")
    else:
        s += f"  RUN(bit4)={(v>>4)&1}"
    lines.append(s)
open(out + "/mailbox_state.txt", "w").write("\n".join(lines) + "\n")
print("\n".join(lines))
PY

[ -s "$OUT/adt_sep.txt" ] && [ -s "$OUT/mailbox_state.txt" ] || die "sortie vide : voir $OUT/peek.log"
grep -q 'compatible' "$OUT/adt_sep.txt" || echo "ATTENTION : pas de 'compatible' dans adt_sep.txt (nœud absent ?)."
chmod a-w "$OUT"/adt_sep.txt "$OUT"/mailbox_state.txt "$OUT"/peek.log "$OUT"/meta.txt
[ -f "$OUT/chainload.log" ] && chmod a-w "$OUT/chainload.log"
echo "Terminé -> $OUT. Noter dans docs/journal.md ; le Mac reste en mode proxy."
