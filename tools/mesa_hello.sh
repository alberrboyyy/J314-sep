#!/usr/bin/env bash
# Premier dialogue avec le capteur Touch ID SANS macOS, depuis m1n1 en mode proxy.
# ÉCRIT vers le matériel (pas vers le SEP) : broche d'alimentation du capteur et contrôleur spi2.
#
# But      : vérifier que le transport lu sous macOS (docs/sensor_hw.md « Dialogue SPI », C17-C20) suffit pour
#            obtenir l'identité et l'état du capteur, seules trames en clair.
# Ce qui est écrit, et rien d'autre :
#   - gpio0 broche 196 (function-mesa_pwr de l'ADT) : les 3 valeurs écrites par macOS dans C17
#     (0x76802, 0x76a02 puis 0x76a03 = sortie à 1), puis 0x76a02 (éteint) et la valeur d'origine à la fin ;
#   - registres de /arm-io/spi2 : séquence du pilote public Linux spi-apple.c en mode scruté (FIFO), avec les
#     réglages vus sous macOS (CLKDIV 3, CPHA) ; valeurs d'origine remises à la fin ;
#   - sur le bus, uniquement des trames vues à l'identique dans C19 avant tout échange avec le SEP :
#       80 78 00 07 00 00 00            (réveil)
#       80 10 00 07 00 00 00 + 16 zéros (état, lecture simultanée de 0x17 octets)
#       80 70 00 07 00 00 00            (identité)
#       80 13 00 0b 00 00 00 1b 00 00 00 puis 0x1b zéros (lecture de la réponse de 0x1b octets),
#     cette dernière seulement si l'état annonce exactement 0x1b octets en attente.
# Jamais : SEP, broches SPI (déjà réglées par iBoot), pmgr (spi2 déjà allumé), trames chiffrées, correctif.
# Risque   : le capteur ne répond pas (octets à 0 ou 0xff), ou m1n1 se bloque (le Mac redémarre). L'alimentation
#            est coupée et les registres remis même en cas d'erreur Python ; pas si m1n1 plante.
# Attendu  : réponse d'état `80 20 00 10 …` et identité `80 d4 00 1b 00000000 70 02 19 c0 …` (celle de C18/C19).
#
# Usage : ./tools/mesa_hello.sh [nom]     SKIP_CHAINLOAD=1 pour ne pas rechainloader m1n1.
set -euo pipefail
source "$(dirname "$0")/env.sh"

NAME="${1:-mesa_hello}"
require_mac
[ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$TRACES_DIR/${STAMP}_${NAME}"
mkdir -p "$OUT"
{
  echo "date: $STAMP"; echo "name: $NAME"
  echo "m1n1_commit: $(git -C "$M1N1_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
  echo "proxy_port: $M1N1DEVICE"
  echo "chainload: $([ "${SKIP_CHAINLOAD:-0}" = 1 ] && echo non || echo oui)"
  echo "writes: gpio0 pin196 (alim capteur), spi2 (mode scruté), trames 0x78 0x10 0x70 0x13 ; rien vers le SEP"
} > "$OUT/meta.txt"

if [ "${SKIP_CHAINLOAD:-0}" != 1 ]; then
  "$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log"
  sleep 2
  require_mac
fi

export HELLO_OUT="$OUT" M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
timeout 120 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "$OUT/hello.log"
import os, sys, time
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
from m1n1 import adt
out = os.environ["HELLO_OUT"]
iface = UartInterface()
p = M1N1Proxy(iface, debug=False)
bootstrap_port(iface, p)
u = ProxyUtils(p)
tree = adt.load_adt(u.get_adt())

log = open(out + "/dialog.txt", "w")
def say(s):
    print(s); log.write(s + "\n"); log.flush()

# --- adresses (ADT) et contrôles préalables, en lecture
spi = tree["/arm-io/spi2"]
assert [c.compatible[0] for c in spi if hasattr(c, "compatible")] == ["biosensor,mesa"], "spi2 sans capteur mesa"
SPI, spi_size = spi.get_reg(0)
GPIO, _ = tree["/arm-io/gpio0"].get_reg(0)
PWR = GPIO + 4 * 196
pmgr = tree["/arm-io/pmgr"]
dev = {d.name: d for d in pmgr.devices}["SPI2"]
ps = getattr(pmgr, "ps-regs")[dev.psreg]
ps_addr = pmgr.get_reg(ps.reg)[0] + ps.offset + dev.psidx * 8
ps_val = p.read32(ps_addr)
say(f"spi2={SPI:#x} gpio0={GPIO:#x} PS(SPI2)@{ps_addr:#x}={ps_val:#x}")
assert (ps_val & 0xff) == 0xff, "spi2 non alimenté : arrêt (on n'écrit pas dans pmgr)"
pins = [p.read32(GPIO + 4 * n) for n in (48, 49, 50)]
say("broches 48-50 : " + " ".join(f"{v:#x}" for v in pins))
assert pins == [0x8742a0, 0x874220, 0x874220], "broches SPI pas dans l'état laissé par iBoot : arrêt"

CTRL, CFG, STATUS, PIN, TXDATA, RXDATA, CLKDIV, RXCNT, WDELAY, TXCNT = 0x0, 0x4, 0x8, 0xc, 0x10, 0x20, 0x30, 0x34, 0x38, 0x4c
FIFOSTAT, IE_XFER, IF_XFER, IE_FIFO, IF_FIFO = 0x10c, 0x130, 0x134, 0x138, 0x13c
saved = {r: p.read32(SPI + r) for r in (CTRL, CFG, PIN, CLKDIV, WDELAY, IE_XFER, IE_FIFO)}
pwr_orig = p.read32(PWR)
say("spi2 avant : " + " ".join(f"+{r:#x}={v:#x}" for r, v in saved.items()) + f" ; broche196={pwr_orig:#x}")
assert pwr_orig == 0x7680e, f"broche 196 dans un état inattendu ({pwr_orig:#x}) : arrêt"

def xfer(tx, rx_len):
    """Un échange : émet tx (bytes), reçoit rx_len octets (0 ou len(tx)). Séquence de spi-apple.c, mode scruté."""
    n = len(tx)
    assert rx_len in (0, n)
    p.write32(SPI + CTRL, 0xc)                 # reset des FIFO
    p.write32(SPI + IF_XFER, 0xffffffff)
    p.write32(SPI + IF_FIFO, 0xffffffff)
    p.write32(SPI + TXCNT, n)
    p.write32(SPI + RXCNT, rx_len)
    sent, rx = 0, bytearray()
    def fill():
        nonlocal sent
        lvl = (p.read32(SPI + FIFOSTAT) >> 8) & 0xff
        k = min(n - sent, 16 - lvl)
        for b in tx[sent:sent + max(k, 0)]:
            p.write32(SPI + TXDATA, b)
        sent += max(k, 0)
    def drain():
        lvl = (p.read32(SPI + FIFOSTAT) >> 24) & 0xff
        for _ in range(min(lvl, rx_len - len(rx))):
            rx.append(p.read32(SPI + RXDATA) & 0xff)
    fill()
    p.write32(SPI + CTRL, 0x1)                 # RUN
    t0 = time.monotonic()
    while True:
        fill(); drain()
        flags = p.read32(SPI + IF_XFER)
        if sent == n and len(rx) == rx_len and (flags & 2):
            break
        if time.monotonic() - t0 > 2.0:
            raise TimeoutError(f"échange bloqué : émis {sent}/{n}, reçu {len(rx)}/{rx_len}, IF_XFER={flags:#x} "
                               f"FIFOSTAT={p.read32(SPI + FIFOSTAT):#x}")
    p.write32(SPI + CTRL, 0)
    say(f"  TX {bytes(tx).hex()}" + (f"\n  RX {bytes(rx).hex()}" if rx_len else ""))
    return bytes(rx)

def status():
    r = xfer(bytes.fromhex("80100007000000") + bytes(16), 0x17)
    return r[7:]

ID_ATTENDU = "80d4001b00000000700219c05c0fd2aa349a81c76e030200d87576"
try:
    # réglages du contrôleur (macOS : CLKDIV 3, CFG 0x40042 en DMA -> 0x40002 en scruté, PIN 0, délais 0)
    p.write32(SPI + CTRL, 0)
    p.write32(SPI + IE_XFER, 0)
    p.write32(SPI + IE_FIFO, 0)
    p.write32(SPI + PIN, 0)
    p.write32(SPI + CLKDIV, 3)
    p.write32(SPI + WDELAY, 0)
    p.write32(SPI + CFG, 0x40002)
    # alimentation, comme macOS dans C17
    say("alimentation du capteur")
    p.write32(PWR, 0x76802); p.write32(PWR, 0x76a02)
    time.sleep(0.04)
    p.write32(PWR, 0x76a03)
    time.sleep(0.06)
    say("réveil (0x78)");   xfer(bytes.fromhex("80780007000000"), 0); time.sleep(0.01)
    say("état");            st = status(); time.sleep(0.01)
    say("identité (0x70)"); xfer(bytes.fromhex("80700007000000"), 0); time.sleep(0.01)
    say("état");            st = status()
    ok_status = st[:4] == bytes.fromhex("80200010")
    pending = st[12] | (st[13] << 8) if ok_status else None
    say(f"  état reconnu : {ok_status} ; réponse en attente : {pending if pending is None else hex(pending)}")
    ident = None
    if pending == 0x1b:
        time.sleep(0.01)
        say("demande de la réponse (0x13, 0x1b octets)")
        xfer(bytes.fromhex("8013000b0000001b000000"), 0); time.sleep(0.01)
        ident = xfer(bytes(0x1b), 0x1b); time.sleep(0.01)
        say("état"); status()
    if ident is None:
        say("RÉSULTAT : pas d'identité lue (le capteur n'a pas annoncé la réponse attendue)")
    elif ident.hex() == ID_ATTENDU:
        say("RÉSULTAT : IDENTITÉ IDENTIQUE à celle lue sous macOS (C18/C19)")
    else:
        say("RÉSULTAT : réponse différente de celle lue sous macOS")
finally:
    try:
        p.write32(SPI + CTRL, 0)
        p.write32(PWR, 0x76a02)                # capteur éteint
        time.sleep(0.02)
        p.write32(PWR, pwr_orig)
        for r in (CFG, PIN, CLKDIV, WDELAY, IE_XFER, IE_FIFO, CTRL):
            p.write32(SPI + r, saved[r])
        say(f"remis en état : broche196={p.read32(PWR):#x} CFG={p.read32(SPI + CFG):#x} CTRL={p.read32(SPI + CTRL):#x}")
    except Exception as e:
        say(f"ATTENTION : remise en état incomplète : {e}")
PY

[ -s "$OUT/dialog.txt" ] || die "sortie vide : voir $OUT/hello.log"
chmod a-w "$OUT"/*
echo "Terminé -> $OUT. Noter dans docs/journal.md ; le Mac reste en mode proxy."
