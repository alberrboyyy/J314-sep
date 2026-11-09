# SPDX-License-Identifier: GPL-2.0-or-later
"""
trace_sep_spi.py -- traceur SEP habituel + écoute passive du bus SPI du capteur (spi2).

Usage : TRACE_SCRIPT=hv/trace_sep_spi.py ./tools/boot_and_trace.sh <nom>
Observation pure : aucun hook, aucune écriture, aucune injection. Mode ASYNC : m1n1 exécute lui-même
l'accès du guest (une seule fois) et remonte un événement.

1. Lance hv/trace_sep_filtered.py tel quel (mêmes variables d'environnement, même sep.log).
2. Trace les registres du contrôleur /arm-io/spi2 (reg[0] entier) et, dans /arm-io/gpio0, seulement les
   registres de configuration des broches 48..51 (candidates SPI) et 195..196 (IRQ et alimentation du capteur).
   Rien sur la console : une ligne par accès dans <dossier de sep.log>/spi2.log :
     <ts hôte> <R|W> <spi2|gpio0> +0x<offset> <largeur en octets> 0x<valeur>
"""
import os, time, atexit

_here = os.path.dirname(os.path.abspath(__file__))
_sep = os.path.join(_here, "trace_sep_filtered.py")
exec(compile(open(_sep).read(), _sep, "exec"), globals())

from m1n1.trace import ADTDevTracer as _ADTDevTracer


class _QuietRegTracer(_ADTDevTracer):
    REGMAPS = []
    NAMES = []

    def __init__(self, hv, devpath, label, out, zones):
        super().__init__(hv, devpath, verbose=0)
        self.label = label
        self.out = out
        self.zones = zones          # liste (offset, taille) dans reg[0]
        self.n = 0
        self._last = time.monotonic()

    def start(self):
        self.base, size = self.dev.get_reg(0)
        for off, sz in self.zones:
            if sz is None:
                sz = size - off
            assert off + sz <= size
            self.trace(self.base + off, sz, TraceMode.ASYNC, read=True, write=True)
        return self.base

    def evt_rw(self, evt, regmap=None, prefix=None):
        try:
            self.n += 1
            self.out.write(f"{time.time():.6f} {'W' if evt.flags.WRITE else 'R'} {self.label} "
                           f"+0x{evt.addr - self.base:03x} {1 << evt.flags.WIDTH} 0x{evt.data:x}\n")
            now = time.monotonic()
            if now - self._last > 0.5:
                self.out.flush()
                self._last = now
        except Exception:
            pass


def _setup_spi():
    out_dir = os.path.dirname(os.path.abspath(os.environ.get("SEP_TRACE_OUT") or _default_out()))
    path = os.path.join(out_dir, "spi2.log")
    out = open(path, "a", buffering=1 << 16)
    spi = _QuietRegTracer(hv, "/arm-io/spi2", "spi2", out, [(0, None)])
    b1 = spi.start()
    gpio = _QuietRegTracer(hv, "/arm-io/gpio0", "gpio0", out, [(4 * 48, 16), (4 * 195, 8)])
    b2 = gpio.start()
    out.write(f"# trace_sep_spi start {time.time():.6f} spi2=0x{b1:x} gpio0=0x{b2:x} (broches 48-51, 195-196) mode=ASYNC\n")
    out.write("# format: <ts> <R|W> <dev> +0x<offset> <octets> 0x<valeur>\n")
    out.flush()
    atexit.register(lambda: (out.flush(), out.close()))
    print(f"[trace_sep_spi] spi2@0x{b1:x} + gpio0@0x{b2:x} -> {path}")
    return spi, gpio


spi2_tracer, gpio_mesa_tracer = _setup_spi()
