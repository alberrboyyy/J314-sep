#!/usr/bin/env bash
# Broches et alimentation du bus SPI du capteur (spi2), vues depuis m1n1 en mode proxy, SANS macOS,
# en LECTURE SEULE stricte. But : trouver quelles broches de gpio0 sont en « fonction périphérique »
# (état laissé par iBoot) et l'état des registres d'alimentation SPI1..SPI4.
#   1. readmem du blob ADT (adresses de gpio0 et de pmgr, table pmgr.devices).
#   2. 255 lectures MMIO 32 bits : registre de configuration de chaque broche de /arm-io/gpio0
#      (base + 4*n, n < #gpio-pins). Ce sont les registres que le pilote public Linux pinctrl-apple-gpio
#      lit sans effet de bord. JAMAIS lus : les registres d'interruption (base+0x800 et plus).
#   3. Lecture 32 bits du registre d'état d'alimentation (PS) de SPI_P, SPI1, SPI2, SPI3, SPI4, SIO :
#      adresse calculée comme src/pmgr.c de m1n1 (ps-regs[psreg] + psidx*8). m1n1 lit ces registres lui-même.
# Aucune écriture, pas de m1n1.setup (qui écrit dans le PMU), rien vers le SEP, spi2 lui-même n'est pas lu
# (bloc peut-être non alimenté).
#
# Usage : ./tools/gpio_peek.sh [nom]      (défaut "gpio_peek" -> traces/<horodatage>_gpio_peek/)
#   SKIP_CHAINLOAD=1 : ne pas rechainloader m1n1.
set -euo pipefail
source "$(dirname "$0")/env.sh"

NAME="${1:-gpio_peek}"
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
  echo "mmio_reads: gpio0 config broches 0..N-1 ; pmgr PS SPI_P SPI1 SPI2 SPI3 SPI4 SIO"
} > "$OUT/meta.txt"

if [ "${SKIP_CHAINLOAD:-0}" != 1 ]; then
  "$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log"
  sleep 2
  require_mac
fi

export PEEK_OUT="$OUT" M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
timeout 180 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "$OUT/peek.log"
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
tree = adt.load_adt(u.get_adt())          # readmem

# --- pmgr : registres PS (lecture)
pmgr = tree["/arm-io/pmgr"]
psregs = getattr(pmgr, "ps-regs")
devs = {d.name: d for d in pmgr.devices}
lines = []
for n in ("SPI_P", "SPI1", "SPI2", "SPI3", "SPI4", "SIO"):
    d = devs.get(n)
    if d is None:
        lines.append(f"{n}: absent de pmgr.devices"); continue
    ps = psregs[d.psreg]
    base, size = pmgr.get_reg(ps.reg)
    off = ps.offset + d.psidx * 8
    if off + 4 > size:
        lines.append(f"{n}: NON LU (hors reg)"); continue
    v = p.read32(base + off)
    lines.append(f"{n} @ {base+off:#x} = {v:#010x}  TARGET={v&0xf} ACTUAL={(v>>4)&0xf}")
open(out + "/pmgr_ps.txt", "w").write("\n".join(lines) + "\n")
print("\n".join(lines))

# --- gpio0 : configuration des broches (lecture)
g = tree["/arm-io/gpio0"]
base, size = g.get_reg(0)
npins = getattr(g, "#gpio-pins")
assert 4 * npins <= 0x800 and 4 * npins <= size, "plage inattendue"
MODES = {0: "in", 1: "out", 2: "irq_hi", 3: "irq_lo", 4: "irq_up", 5: "irq_dn", 6: "irq_any", 7: "irq_off"}
rows = [f"# gpio0 base {base:#x}, {npins} broches ; valeur brute puis champs (format du pilote public Linux)"]
for n in range(npins):
    v = p.read32(base + 4 * n)
    rows.append(f"{n:3d} {v:#010x} data={v&1} mode={MODES[(v>>1)&7]} periph={(v>>5)&3} pull={(v>>7)&3}"
                f" in_en={(v>>9)&1} drv={(v>>10)&3} grp={(v>>16)&7} lock={(v>>21)&1}")
open(out + "/gpio0_pins.txt", "w").write("\n".join(rows) + "\n")
per = [r for r in rows[1:] if " periph=0 " not in r]
print(f"gpio0 : {npins} broches lues, {len(per)} en fonction périphérique")
PY

[ -s "$OUT/gpio0_pins.txt" ] && [ -s "$OUT/pmgr_ps.txt" ] || die "sortie vide : voir $OUT/peek.log"
chmod a-w "$OUT"/*
echo "Terminé -> $OUT. Noter dans docs/journal.md ; le Mac reste en mode proxy."
