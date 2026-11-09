# SPDX-License-Identifier: GPL-2.0-or-later
"""
trace_sep_spi_dma.py -- trace_sep_spi.py + contenu des échanges SPI du capteur (transferts DMA via SIO).

Usage : TRACE_SCRIPT=hv/trace_sep_spi_dma.py ./tools/boot_and_trace.sh <nom>
Observation pure : aucune écriture MMIO ni mémoire, aucun message injecté, rien vers le SEP.

Les données SPI du capteur ne passent pas par les registres de spi2 (capture C17 : aucun accès TXDATA/RXDATA) :
c'est le coprocesseur SIO qui fait les transferts (ADT spi2 dma-channels 0x18 et 0x19). Ce script observe donc
la boîte aux lettres ASC de /arm-io/sio (mêmes offsets INBOX/OUTBOX que le SEP) en mode SYNC, et lit en mémoire
(lecture seule, à travers les tables de /arm-io/dart-sio) le bloc de contrôle et les buffers des canaux 0x18/0x19.

Sorties dans le dossier de sep.log :
  sio.log            une ligne par message SIO : <ts> <dir> EP=.. TAG=.. TYPE=.. PARAM=.. DATA=.. m1=0x..
                     + lignes `# buf ...` (lecture d'un buffer) et `# err ...`
  sio.bufs/NNNNNN_<canal>_<moment>_ctrl.bin   bloc de contrôle (0x400 octets à l'IOVA annoncée)
  sio.bufs/NNNNNN_<canal>_<moment>_data.bin   buffer du transfert (si pointeur/taille plausibles)

HYPOTHÈSES reprises du code public m1n1 proxyclient/hv/trace_mesa.py (écrit pour M1, 2022), NON vérifiées ici :
  - message TYPE 3, EP 0, PARAM 1 : DATA << 12 = IOVA du bloc de contrôle ;
  - trace_mesa.py lit : canal 0x18 -> pointeur à +0xa8, taille à +0xb0 ; canal 0x19 -> +0x48 / +0x50.
VU dans C18 (traces/20261110-002417_c18-spi-dma-boot) : ce n'est pas le canal mais le champ DATA du message
TYPE 6 qui choisit le descripteur : descripteur à +0x40 + DATA*0xc, pointeur à +8, taille à +0x10
(DATA=0 -> +0x48/+0x50 ; DATA=8 -> +0xa8/+0xb0). Une écriture seule (canal 0x18, DATA=0) utilise donc +0x48.
Le descripteur vu au TYPE 6 est mémorisé par canal et réutilisé à la fin du transfert (TYPE 0x68).
SIO_ALL_EPS=1 : lire aussi le bloc de contrôle pour les autres canaux (défaut : 0x18 et 0x19 seulement).
"""
import os, struct, time, atexit

_here2 = os.path.dirname(os.path.abspath(__file__))
_spi = os.path.join(_here2, "trace_sep_spi.py")
exec(compile(open(_spi).read(), _spi, "exec"), globals())

SIO_NODE = "/arm-io/sio"
DART_SIO_NODE = "/arm-io/dart-sio"
SIO_CHANNELS = (0x18, 0x19)
SIO_CTRL_SIZE = 0x400
SIO_BUF_MAX = 0x10000
SIO_TOTAL_MAX = 64 << 20


class SIOMailboxObserver(ADTDevTracer):
    REGMAPS = []
    NAMES = []

    def __init__(self, hv, out, bufdir):
        super().__init__(hv, SIO_NODE, verbose=0)
        self.out = out
        self.bufdir = bufdir
        self.seq = 0
        self.setup = {}
        self.desc = {}
        self.dart = None
        self.sid = None
        self.written = 0
        self.all_eps = os.environ.get("SIO_ALL_EPS", "0") not in ("", "0")
        self._last = time.monotonic()

    def start(self):
        base, size = self.dev.get_reg(0)
        assert size >= OUTBOX_OFF + PAIR_SIZE
        regmap = ASCRegs(self._cache, base)
        regmap.cached = ASCRegs(self._cache.cached, base)
        self.regmaps[base] = regmap
        self.asc = regmap
        self.trace(base + INBOX_OFF, PAIR_SIZE, TraceMode.SYNC, read=False, write=True, regmap=regmap)
        self.trace(base + OUTBOX_OFF, PAIR_SIZE, TraceMode.SYNC, read=True, write=False, regmap=regmap)
        return base

    def w_INBOX1(self, inbox1):
        self._emit(">", self.asc.cached.INBOX0.reg.value, inbox1.value)

    def r_OUTBOX1(self, outbox1):
        self._emit("<", self.asc.cached.OUTBOX0.reg.value, outbox1.value)

    def _emit(self, d, m0, m1):
        try:
            self.seq += 1
            ep, tag, typ = m0 & 0xFF, (m0 >> 8) & 0xFF, (m0 >> 16) & 0xFF
            param, data = (m0 >> 24) & 0xFF, (m0 >> 32) & 0xFFFFFFFF
            self.out.write(f"{time.time():.6f} {d} EP=0x{ep:02x} TAG=0x{tag:02x} TYPE=0x{typ:02x} "
                           f"PARAM=0x{param:02x} DATA=0x{data:08x} m1=0x{m1:016x}\n")
            if (m1 & 0xFF) == 0x20 or True:
                if d == ">" and typ == 3 and ep == 0:
                    self.setup[param] = data
                want = ep in SIO_CHANNELS or (self.all_eps and ep != 0)
                if want and d == ">" and typ == 6:
                    self.desc[ep] = data
                    self._grab(ep, "setup", data)
                elif want and d == "<" and typ == 0x68 and ep in self.desc:
                    self._grab(ep, "done", self.desc[ep])
            now = time.monotonic()
            if now - self._last > 0.5:
                self.out.flush()
                self._last = now
        except Exception as e:
            try:
                self.out.write(f"# err seq={self.seq} {type(e).__name__}: {e}\n")
            except Exception:
                pass

    def _grab(self, ep, when, slot):
        if self.written >= SIO_TOTAL_MAX or 1 not in self.setup:
            return
        iova = self.setup[1] << 12
        if self.dart is None:
            self.dart = SepDartReader(self.hv, DART_SIO_NODE)
        if self.sid is None:
            self.sid, _ = self.dart.find_sid(iova)
        ctrl = self.dart.read(self.sid, iova, SIO_CTRL_SIZE)
        stem = os.path.join(self.bufdir, f"{self.seq:06d}_{ep:02x}_{when}")
        open(stem + "_ctrl.bin", "wb").write(ctrl)
        self.written += len(ctrl)
        po, so = 0x40 + slot * 0xc + 8, 0x40 + slot * 0xc + 0x10
        if so + 4 > len(ctrl):
            return
        ptr = struct.unpack_from("<Q", ctrl, po)[0]
        size = struct.unpack_from("<I", ctrl, so)[0]
        if not (0 < size <= SIO_BUF_MAX) or ptr < 0x4000:
            self.out.write(f"# buf seq={self.seq} ep=0x{ep:02x} {when} ptr=0x{ptr:x} size=0x{size:x} : non lu (implausible)\n")
            return
        try:
            buf = self.dart.read(self.sid, ptr, size)
        except Exception as e:
            self.out.write(f"# buf seq={self.seq} ep=0x{ep:02x} {when} ptr=0x{ptr:x} size=0x{size:x} : erreur {e}\n")
            return
        open(stem + "_data.bin", "wb").write(buf)
        self.written += len(buf)
        self.out.write(f"# buf seq={self.seq} ep=0x{ep:02x} {when} ptr=0x{ptr:x} size=0x{size:x} "
                       f"debut={buf[:16].hex()}\n")


def _setup_sio():
    out_dir = os.path.dirname(os.path.abspath(os.environ.get("SEP_TRACE_OUT") or _default_out()))
    bufdir = os.path.join(out_dir, "sio.bufs")
    os.makedirs(bufdir, exist_ok=True)
    path = os.path.join(out_dir, "sio.log")
    out = open(path, "a", buffering=1 << 16)
    t = SIOMailboxObserver(hv, out, bufdir)
    base = t.start()
    out.write(f"# trace_sep_spi_dma start {time.time():.6f} sio=0x{base:x} mode=SYNC canaux=0x18,0x19\n")
    out.flush()
    atexit.register(lambda: (out.flush(), out.close()))
    print(f"[trace_sep_spi_dma] sio@0x{base:x} -> {path}")
    return t


sio_tracer = _setup_sio()
