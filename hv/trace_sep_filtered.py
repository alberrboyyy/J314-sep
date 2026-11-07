# SPDX-License-Identifier: GPL-2.0-or-later
"""
trace_sep_filtered.py -- traceur du mailbox SEP, observation pure, filtré par endpoint.

Script destiné à `run_guest.py -m <ce fichier>` (lancé par tools/boot_and_trace.sh).
run_guest.py l'exécute via hv.run_script() -> runpy.run_path(init_globals=hv.shell_locals),
donc les globales `hv`, `p`, `u`, `iface`, `TraceMode`, `trace_range`, ... sont déjà définies.

Ce que fait ce script
---------------------
- Trace UNIQUEMENT 4 registres 64 bits du mailbox ASC du noeud ADT /arm-io/sep (reg[0]) :
    INBOX0/INBOX1   (+0x8800/+0x8808) en écriture  -> messages AP -> SEP  (dir '>')
    OUTBOX0/OUTBOX1 (+0x8830/+0x8838) en lecture   -> messages SEP -> AP  (dir '<')
  Offsets repris de m1n1 (proxyclient/m1n1/hw/asc.py ASCRegs, src/asc.c). Aucun autre registre,
  aucun autre périphérique, aucun autre traceur n'est activé.
- Observation pure : aucune écriture, aucun blocage, aucune injection. Le script n'appelle
  jamais u.write / p.write* / iface.writemem et n'utilise pas TraceMode.HOOK. En mode ASYNC
  (défaut) l'accès du guest est exécuté par m1n1 (EL2, en C) et seul un événement est remonté ;
  en mode SYNC c'est le code générique de l'hyperviseur (hv.handle_vm_hook_mapped) qui rejoue
  à l'identique l'accès du guest, comme pour tout traceur m1n1.
- Une ligne par message, dans un fichier, format :
    <timestamp> <dir> EP=0x.. TAG=0x.. TYPE=0x.. PARAM=0x.. DATA=0x.. [ool=...]
  champs du mot 0 (doc Asahi) : bits 0-7 EP, 8-15 TAG, 16-23 TYPE, 24-31 PARAM, 32-63 DATA.
  <timestamp> = heure de réception côté PC (time.time(), secondes, 6 décimales), PAS l'horloge
  du Mac. En ASYNC les événements sont bufferisés : le timestamp est l'heure de traitement.
  ool=... : présent seulement si le mot 1 du mailbox (INBOX1/OUTBOX1) a des bits non nuls hors
  des champs d'état FIFO connus (OUTCNT/INCNT/OUTPTR/INPTR, bits 40-56). Valeur brute
  `ool=m1:0x<16 hex>`. Ce n'est PAS un décodage de buffer out-of-line en mémoire partagée
  (non implémenté : aucun format vérifié).
- Lignes commençant par '#' : en-tête et méta (ignorées comme commentaires par
  analysis/parse_trace.py). Les annonces de noms d'endpoint (EP=0xFD TYPE=0, d'après
  m1n1 hw/sep.py `_handle_ep_discovery`) sont recopiées en commentaire `# epname ...`,
  quel que soit le filtre. Interprétation reprise de m1n1, non vérifiée sur macOS 13.5.

Variables d'environnement
-------------------------
  SEP_EPS          liste d'endpoints à garder, ex. "0x08,0x12,0x13" (virgules/espaces,
                   décimal ou 0x..). Vide ou absent = tous.
  SEP_TRACE_OUT    fichier de sortie. Défaut : <repo>/traces/sep_<AAAAMMJJ-HHMMSS>.log
                   (le chemin est affiché au démarrage et écrit en tête du fichier).
  SEP_TRACE_MODE   ASYNC (défaut) ou SYNC.
  SEP_FLUSH_S      intervalle max entre deux flush, secondes (défaut 0.5).

Console : un seul print au démarrage (+ un en cas d'erreur d'écriture). Aucun print par message.

NON TESTÉ SUR LE MATÉRIEL (écrit sans accès au Mac, vérifié uniquement par py_compile) :
- que macOS 13.5 écrive INBOX0 puis INBOX1 et lise OUTBOX0 puis OUTBOX1 dans cet ordre
  (c'est ce que fait m1n1 ; le traceur ASC générique de m1n1 suppose la même chose) ;
- que les sous-pages (granularité 4 octets, cf. src/hv/hv_vm.c) se mappent sans souci sur
  ce bloc ; que le mode ASYNC ne perde pas d'événements sous forte charge ;
- que /arm-io/sep reg[0] soit bien la base ASC sur j314c (m1n1 hw/sep.py le suppose) ;
- que le mot 1 du mailbox SEP soit toujours 0 hors champs FIFO (m1n1 envoie INBOX1=0).
"""

import atexit
import os
import sys
import time

from m1n1.hv import TraceMode
from m1n1.hw.asc import ASCRegs
from m1n1.trace import ADTDevTracer

SEP_NODE = "/arm-io/sep"

# Offsets relatifs à reg[0] (ASCRegs) ; 2 registres 64 bits contigus chacun.
INBOX_OFF = 0x8800    # INBOX0, INBOX1
OUTBOX_OFF = 0x8830   # OUTBOX0, OUTBOX1
PAIR_SIZE = 0x10

# Champs d'état FIFO du mot 1 côté OUTBOX (R_OUTBOX1 dans m1n1 hw/asc.py : bits 40..56).
MSG1_FIFO_MASK = ((1 << 57) - 1) & ~((1 << 40) - 1)


def _parse_eps(txt):
    txt = (txt or "").replace(",", " ").split()
    if not txt:
        return None
    eps = set()
    for t in txt:
        v = int(t, 0)
        if not 0 <= v <= 0xFF:
            raise ValueError(f"SEP_EPS: endpoint hors plage 0..0xff : {t}")
        eps.add(v)
    return frozenset(eps)


def _default_out():
    try:
        here = os.path.dirname(os.path.abspath(__file__))
        repo = os.path.dirname(here)
    except NameError:
        repo = os.getcwd()
    stamp = time.strftime("%Y%m%d-%H%M%S")
    return os.path.join(repo, "traces", f"sep_{stamp}.log")


class SEPMailboxObserver(ADTDevTracer):
    """Observateur du mailbox SEP. Sous-classe ADTDevTracer (m1n1/trace/__init__.py) sans
    rien modifier dans m1n1 : seuls les handlers w_INBOX1 / r_OUTBOX1 sont définis,
    appelés par Tracer.evt_rw() après mise à jour du cache de registres."""

    DEFAULT_MODE = TraceMode.ASYNC
    REGMAPS = []   # on ne trace pas tout reg[0] : voir start()
    NAMES = []

    def __init__(self, hv, devpath, out, eps=None, mode=None, flush_s=0.5):
        super().__init__(hv, devpath, verbose=0)
        self.out = out
        self.eps = eps
        self.mode = mode or self.DEFAULT_MODE
        self.flush_s = flush_s
        self._last_flush = time.monotonic()
        self._write_failed = False
        self.n_seen = 0
        self.n_logged = 0
        self.epnames = {}

    def start(self):
        base, size = self.dev.get_reg(0)
        if size < OUTBOX_OFF + PAIR_SIZE:
            raise Exception(f"{SEP_NODE} reg[0] trop petit ({size:#x}) pour le mailbox ASC")
        regmap = ASCRegs(self._cache, base)
        regmap.cached = ASCRegs(self._cache.cached, base)
        self.regmaps[base] = regmap
        self.asc = regmap
        # Écritures du guest sur INBOX0/1 seulement ; lectures sur OUTBOX0/1 seulement.
        self.trace(base + INBOX_OFF, PAIR_SIZE, self.mode, read=False, write=True, regmap=regmap)
        self.trace(base + OUTBOX_OFF, PAIR_SIZE, self.mode, read=True, write=False, regmap=regmap)
        return base

    # --- handlers appelés par Tracer.evt_rw ---------------------------------------------

    def w_INBOX1(self, inbox1):
        inbox0 = self.asc.cached.INBOX0.reg
        self._emit(">", inbox0.value, inbox1.value, tx=True)

    def r_OUTBOX1(self, outbox1):
        outbox0 = self.asc.cached.OUTBOX0.reg
        self._emit("<", outbox0.value, outbox1.value, tx=False)

    # --- sortie --------------------------------------------------------------------------

    def _emit(self, d, m0, m1, tx):
        ts = time.time()
        self.n_seen += 1
        ep = m0 & 0xFF
        tag = (m0 >> 8) & 0xFF
        typ = (m0 >> 16) & 0xFF
        param = (m0 >> 24) & 0xFF
        data = (m0 >> 32) & 0xFFFFFFFF

        lines = []
        if not tx and ep == 0xFD and typ == 0:
            # Annonce de nom d'endpoint (interprétation m1n1 hw/sep.py, non vérifiée 13.5).
            name = "".join(chr((data >> (i * 8)) & 0xFF) for i in range(3, -1, -1))
            if self.epnames.get(param) != name:
                self.epnames[param] = name
                safe = name.encode("ascii", "backslashreplace").decode("ascii")
                lines.append(f"# epname {ts:.6f} EP=0x{param:02x} NAME={safe!r}\n")

        if self.eps is None or ep in self.eps:
            extra = m1 if tx else (m1 & ~MSG1_FIFO_MASK)
            line = (f"{ts:.6f} {d} EP=0x{ep:02x} TAG=0x{tag:02x} TYPE=0x{typ:02x} "
                    f"PARAM=0x{param:02x} DATA=0x{data:08x}")
            if extra:
                line += f" ool=m1:0x{m1:016x}"
            lines.append(line + "\n")
            self.n_logged += 1

        if lines:
            self._write("".join(lines))

    def _write(self, s):
        try:
            self.out.write(s)
            now = time.monotonic()
            if now - self._last_flush >= self.flush_s:
                self.out.flush()
                self._last_flush = now
        except Exception as e:
            if not self._write_failed:
                self._write_failed = True
                print(f"[trace_sep_filtered] ERREUR écriture {getattr(self.out, 'name', '?')}: {e}",
                      file=sys.stderr)

    def close(self):
        try:
            self.out.write(f"# end {time.time():.6f} seen={self.n_seen} logged={self.n_logged}\n")
            self.out.flush()
            self.out.close()
        except Exception:
            pass


def _setup():
    eps = _parse_eps(os.environ.get("SEP_EPS", ""))
    mode_txt = os.environ.get("SEP_TRACE_MODE", "ASYNC").strip().upper()
    if mode_txt not in ("ASYNC", "SYNC"):
        raise ValueError(f"SEP_TRACE_MODE doit valoir ASYNC ou SYNC, pas {mode_txt!r}")
    mode = TraceMode[mode_txt]
    flush_s = float(os.environ.get("SEP_FLUSH_S", "0.5"))
    out_path = os.environ.get("SEP_TRACE_OUT") or _default_out()

    try:
        hv.adt[SEP_NODE]
    except KeyError:
        raise Exception(f"noeud ADT {SEP_NODE} absent : rien à tracer")

    os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
    out = open(out_path, "a", buffering=1 << 16)

    tracer = SEPMailboxObserver(hv, SEP_NODE, out, eps=eps, mode=mode, flush_s=flush_s)
    base = tracer.start()

    eps_txt = "all" if eps is None else ",".join(f"0x{e:02x}" for e in sorted(eps))
    out.write(f"# trace_sep_filtered start {time.time():.6f} node={SEP_NODE} base=0x{base:x} "
              f"mode={mode_txt} eps={eps_txt} ts=host_time_time\n")
    out.write("# format: <ts> <dir> EP=0x.. TAG=0x.. TYPE=0x.. PARAM=0x.. DATA=0x.. [ool=...]"
              " ; '>' AP->SEP (INBOX), '<' SEP->AP (OUTBOX)\n")
    out.flush()
    atexit.register(tracer.close)

    print(f"[trace_sep_filtered] mailbox {SEP_NODE}@0x{base:x} mode={mode_txt} eps={eps_txt} "
          f"-> {os.path.abspath(out_path)}")
    return tracer


sep_tracer = _setup()
