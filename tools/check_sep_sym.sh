#!/usr/bin/env bash
# Contrôle en LECTURE SEULE : lit 16 octets de la mémoire de m1n1 à base + offset de sep_get_random
# et compare au code attendu (bin m1n1). Ne parle pas au SEP, n'appelle rien, n'écrit rien.
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_mac
STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_check_sym"; mkdir -p "$OUT"
SYM=$(nm "$M1N1_DIR/build/m1n1.elf" | awk '$3=="sep_get_random"{print $1}')
"$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log" >/dev/null
sleep 2; require_mac
export OUT SYMOFF="0x$SYM" M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient" M1N1BIN="$M1N1_DIR/build/m1n1.bin"
timeout 60 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "$OUT/check.log"
import os, sys
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import bootstrap_port
iface = UartInterface(); p = M1N1Proxy(iface, debug=False); bootstrap_port(iface, p)
base = p.get_base(); a = base + int(os.environ["SYMOFF"], 16) - 0x10000
got = iface.readmem(a, 16)
exp = open(os.environ["M1N1BIN"], "rb").read()[int(os.environ["SYMOFF"], 16) - 0x10000:][:16]
print(f"base={base:#x} addr={a:#x}\nlu      : {got.hex(' ')}\nattendu : {exp.hex(' ')}\n" + ("ADRESSE BONNE" if got == exp else "ADRESSE FAUSSE"))
PY
echo "Terminé -> $OUT (Mac en mode proxy)."
