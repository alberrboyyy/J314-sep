#!/usr/bin/env python3
"""Fusionne hv_uart.log (log noyau macOS, sans horodatage PC) et sep.log (horloge PC) d'une capture
en une chronologie unique, fenêtre par fenêtre (marques de marks.txt). Lecture seule sur traces/ ;
sortie uniquement sous analysis/out/ (-o).

Méthode (tout est une approximation, à dire dans les rapports) :
  1. Ancrages uart -> heure PC, uniquement des correspondances UNIQUES et monotones :
     - « with CRC: 0xNNNN » (Saving/Fetched) <-> '<' EP=0x13 dont DATA>>16 == NNNN (une seule ligne sep) ;
     - « Replied to xART app: 0x....XX13 » <-> '>' EP=0x13 TAG=XX (une seule ligne sep).
     - k-ième « Sending lock change X for handle H value V » <-> k-ième '<' EP=0x12 TAG=X (0/1) TYPE=V
       DATA=H, seulement si les deux suites ont même longueur et concordent champ à champ ;
     Un ancrage qui casserait l'ordre (heure PC décroissante quand la ligne uart croît) est écarté.
     Ancrages secondaires (±1 s) : horloge du Mac (IOConsoleUsers « now <epoch> », ACMTRM « now=N(boot) »),
     décalage PC-Mac mesuré sur les lignes Mac encadrées à < 1 s par des primaires, dérive linéaire.
  2. Chaque ligne uart reçoit l'intervalle [heure ancrage précédent ; heure ancrage suivant] et une heure
     estimée par interpolation linéaire sur le numéro de ligne (l'uart n'a pas de débit constant :
     l'estimation sert seulement à intercaler ; seul l'intervalle est garanti, sous l'hypothèse des ancrages).
  3. Lignes uart retenues : motifs listés dans UART_KEEP (le reste, DCP/apfs/… est ignoré).
     IOConsoleUsers gIOScreenLockState : seulement quand la valeur change.
  4. Messages sep retenus : EP 0x08 (tous), EP 0x12 '<' TAG=0x00/0x01/0x09 (notifications), EP 0x13.

Usage :
    python3 analysis/uart_timeline.py traces/<capture>/ [--ep08-only] [-o analysis/out/x.txt]
"""

import argparse
import bisect
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_file, write_output  # noqa: E402

CRC_RE = re.compile(r"with CRC: 0x([0-9a-fA-F]+)")
XART_RE = re.compile(r"Replied to xART app: 0x([0-9a-fA-F]{16})")
LOCKSTATE_RE = re.compile(r"gIOScreenLockState (\d+)")
LOCKCHANGE_RE = re.compile(r"Sending lock change (\d+) for handle (-?\d+) value (\d+)")
IOC_NOW_RE =re.compile(r"gIOScreenLockState \d+, hs \d+, bs \d+, now (\d{10})")
ACM_NOW_RE = re.compile(r"ACMTRM: _publish:.*now=(\d+)\((\d{10})\)")

UART_KEEP = [
    re.compile(p) for p in (
        r"ACMTRM: _publish:",
        r"ACMTRM: _onBio",
        r"ACMTRM: _registerBio",
        r"TRM_DeviceLocked",
        r"TRM_PolicyReason",
        r"AppleSEPKeyStore:\d+:\d+: Sending lock change",
        r"AppleSEPKeyStore:\d+:\d+: (Unlock|Lock) notification",
        r"AppleSEPKeyStore:\d+:\d+: Sent notification",
        r"AppleSEPKeyStore:\d+:\d+: set handle",
        r"AppleSEPKeyStore:\d+:\d+: AppleKeyStoreUserClient",
        r"AppleSEPKeyStore:\d+:\d+: invalid handle -501",
        r"operation failed \(sel: \d+ ret: [0-9a-f]+, 501,",
        r"handle_keybag_(un)?lock",
        r"AppleSEPXART",
        r"SEP EP \d+",
        r"AppleBiometric|AppleMesa|Mesa|biometric|SandDollar|sensorStateHandler",
        r"AppleCredentialManager",
        r"session_uid",
        r"SMC HID|buttonIndex",
    )
]


def hhmmss(ts):
    return time.strftime("%H:%M:%S", time.localtime(ts)) + ("%.3f" % (ts % 1))[1:]


def read_uart(path):
    with open(path, "rb") as f:
        raw = f.read().decode("utf-8", errors="replace")
    return raw.split("\n")  # numéros = grep -n


def read_marks(path):
    marks = []
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for raw in f:
            parts = raw.split()
            if len(parts) >= 2:
                try:
                    marks.append((float(parts[0]), " ".join(parts[1:])))
                except ValueError:
                    pass
    marks.sort()
    return marks


def find_anchors(msgs, uart):
    ep13_crc, ep13_ap = {}, {}
    for m in msgs:
        if m.ep != 0x13:
            continue
        if m.dir == "<":
            ep13_crc.setdefault(m.data >> 16, []).append(m)
        else:
            ep13_ap.setdefault(m.tag, []).append(m)
    cands = []
    for i, line in enumerate(uart, 1):
        c = CRC_RE.search(line)
        if c:
            hits = ep13_crc.get(int(c.group(1), 16), [])
            if len(hits) == 1:
                cands.append((i, hits[0].ts, hits[0].lineno, "CRC 0x%s" % c.group(1)))
            continue
        x = XART_RE.search(line)
        if x:
            tag = (int(x.group(1), 16) >> 8) & 0xFF
            hits = ep13_ap.get(tag, [])
            if len(hits) == 1:
                cands.append((i, hits[0].ts, hits[0].lineno, "xART TAG=0x%02x" % tag))
    # SKS : k-ième « Sending lock change X for handle H value V » <-> k-ième '<' EP=0x12 TAG=X (0/1)
    # TYPE=V DATA=H. Utilisé seulement si les deux suites ont la même longueur et concordent
    # champ à champ (règle observée dans C8, hypothèse).
    lc = [(i, int(m.group(1)), int(m.group(2)), int(m.group(3)))
          for i, line in enumerate(uart, 1) for m in [LOCKCHANGE_RE.search(line)] if m]
    sk = [m for m in msgs if m.ep == 0x12 and m.dir == "<" and m.tag in (0, 1)]
    sks_ok = len(lc) == len(sk) and all(
        (u[1], u[3], u[2] & 0xFFFFFFFF) == (m.tag, m.type, m.data) for u, m in zip(lc, sk))
    if sks_ok:
        for u, m in zip(lc, sk):
            cands.append((u[0], m.ts, m.lineno, "SKS lock change %d handle %d value %d" % (u[1], u[2], u[3])))
    cands.sort(key=lambda a: a[0])
    # monotonie : on garde la plus longue sous-suite croissante en heure (simple glouton + rejet)
    kept, rejected = [], []
    for a in cands:
        if kept and a[1] < kept[-1][1]:
            rejected.append(a)
            continue
        kept.append(a)
    return kept, rejected


def mac_epoch(line):
    """Epoch de l'horloge du Mac écrit dans la ligne (entier, tronqué), ou None."""
    m = IOC_NOW_RE.search(line)
    if m:
        return int(m.group(1))
    a = ACM_NOW_RE.search(line)
    if a:
        return int(a.group(1)) + int(a.group(2))  # uptime + heure de boot : ±1 s
    return None


def mac_clock_anchors(uart, anchors):
    """Ancrages secondaires (horloge du Mac). Décalage PC-Mac mesuré sur les lignes Mac encadrées
    par deux ancrages primaires à < 1 s ; régression linéaire décalage = a + b*pc (dérive observée).
    Retourne (liste d'ancrages, (a, b), points de mesure)."""
    pts = []
    for i, line in enumerate(uart, 1):
        mac = mac_epoch(line)
        if mac is None or not IOC_NOW_RE.search(line):
            continue
        tmin, _, tmax = uart_time(i, anchors)
        if tmin and tmax and tmax - tmin < 1.0:
            # Mac vrai dans [mac, mac+1) -> décalage dans (tmin-mac-1, tmax-mac] ; milieu
            pts.append(((tmin + tmax) / 2, (tmin + tmax) / 2 - mac - 0.5, i))
    if len(pts) < 2:
        return [], None, pts
    n = len(pts)
    mx = sum(p[0] for p in pts) / n
    my = sum(p[1] for p in pts) / n
    sxx = sum((p[0] - mx) ** 2 for p in pts)
    b = sum((p[0] - mx) * (p[1] - my) for p in pts) / sxx if sxx else 0.0
    a = my - b * mx
    sec = []
    for i, line in enumerate(uart, 1):
        mac = mac_epoch(line)
        if mac is None:
            continue
        # pc = mac + 0.5 + a + b*pc  ->  pc = (mac + 0.5 + a) / (1 - b)
        pc = (mac + 0.5 + a) / (1 - b)
        sec.append((i, pc, 0, "horloge Mac %d (±1 s)" % mac))
    return sec, (a, b), pts


def merge_anchors(primary, secondary):
    """Ajoute les ancrages secondaires compatibles (ordre respecté) entre deux primaires."""
    allv = sorted(primary + secondary, key=lambda a: a[0])
    prim_lines = {a[0] for a in primary}
    out = []
    for a in allv:
        if a[0] in prim_lines and a in primary:
            # retire les secondaires précédents devenus incompatibles
            while out and out[-1][2] == 0 and out[-1][1] > a[1]:
                out.pop()
            out.append(a)
        else:
            if out and a[1] < out[-1][1]:
                continue
            out.append(a)
    # un secondaire doit aussi précéder le primaire suivant
    res = []
    for k, a in enumerate(out):
        if a[2] == 0:
            nxt = next((b for b in out[k + 1:] if b[2] != 0), None)
            if nxt and a[1] > nxt[1]:
                continue
        res.append(a)
    return res


def uart_time(lineno, anchors):
    """(t_min, t_est, t_max) pour une ligne uart."""
    lines = [a[0] for a in anchors]
    k = bisect.bisect_right(lines, lineno)
    if k == 0:
        return (None, anchors[0][1], anchors[0][1])
    if k == len(anchors):
        return (anchors[-1][1], anchors[-1][1], None)
    (l0, t0, _, _), (l1, t1, _, _) = anchors[k - 1], anchors[k]
    est = t0 + (t1 - t0) * (lineno - l0) / max(1, (l1 - l0))
    return (t0, est, t1)


def keep_uart(uart):
    out = []
    last_state = None
    for i, line in enumerate(uart, 1):
        s = LOCKSTATE_RE.search(line)
        if s and "IOConsoleUsers" in line:
            if s.group(1) != last_state:
                out.append((i, line.strip()))
                last_state = s.group(1)
            continue
        if any(p.search(line) for p in UART_KEEP):
            out.append((i, line.strip()))
    return out


def fmt_msg(m):
    return "%s EP=0x%02x TAG=0x%02x TYPE=0x%02x PARAM=0x%02x DATA=0x%08x" % (
        m.dir, m.ep, m.tag, m.type, m.param, m.data)


def build(capture, ep08_only=False, maxlen=170):
    msgs, _ = parse_file(os.path.join(capture, "sep.log"))
    uart = read_uart(os.path.join(capture, "hv_uart.log"))
    marks = read_marks(os.path.join(capture, "marks.txt"))
    primary, rejected = find_anchors(msgs, uart)
    sec, fit, pts = mac_clock_anchors(uart, primary)
    anchors = merge_anchors(primary, sec)
    out = ["# Chronologie fusionnée uart + sep : %s" % capture,
           "# %d ancrages primaires (CRC/TAG xART) retenus, %d écartés (non monotones)" % (len(primary), len(rejected)),
           "# uart : 'U Lnnnn [tmin..tmax]' (heure estimée par interpolation) ; sep : 'S Lnnnn heure'", ""]
    out.append("## Ancrages")
    for a in primary:
        out.append("  uart L%-5d <-> sep L%-5d %s  %s" % (a[0], a[2], hhmmss(a[1]), a[3]))
    if fit:
        a, b = fit
        out.append("  horloge Mac : décalage PC-Mac = %.3f + %.6f*(pc-t0) s, t0 = %s, mesuré sur %d lignes "
                   "IOConsoleUsers encadrées à < 1 s (lignes uart %s)" % (
                       a + b * pts[0][0], b, hhmmss(pts[0][0]), len(pts),
                       ",".join(str(p[2]) for p in pts)))
        for p in pts:
            out.append("    point uart L%d : pc %s décalage %.3f (±0.6)" % (p[2], hhmmss(p[0]), p[1]))
        out.append("  %d ancrages secondaires (horloge Mac) intercalés" % sum(1 for x in anchors if x[2] == 0))
    for a in rejected:
        out.append("  ÉCARTÉ uart L%-5d <-> sep L%-5d %s  %s" % (a[0], a[2], hhmmss(a[1]), a[3]))
    out.append("")
    events = []
    for (i, text) in keep_uart(uart):
        tmin, test, tmax = uart_time(i, anchors)
        rng = "[%s..%s]" % (hhmmss(tmin) if tmin else "début", hhmmss(tmax) if tmax else "fin")
        events.append((test, 0, i, "U L%-5d %s %s" % (i, rng, text[:maxlen])))
    for m in msgs:
        if m.ep == 0x08 or (not ep08_only and ((m.ep == 0x12 and m.dir == "<" and m.tag in (0x00, 0x01, 0x09))
                                                or m.ep == 0x13)):
            events.append((m.ts, 1, m.lineno, "S L%-5d %s %s" % (m.lineno, hhmmss(m.ts), fmt_msg(m))))
    for (ts, label) in marks:
        events.append((ts, 2, 0, "M ---- %s MARQUE %s" % (hhmmss(ts), label)))
    events.sort(key=lambda e: (e[0], e[1], e[2]))
    out.append("## Chronologie")
    out.extend(e[3] for e in events)
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("capture")
    ap.add_argument("--ep08-only", action="store_true")
    ap.add_argument("-o", "--output")
    args = ap.parse_args(argv)
    text = build(args.capture, args.ep08_only)
    if args.output:
        print("écrit : %s" % write_output(args.output, text), file=sys.stderr)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
