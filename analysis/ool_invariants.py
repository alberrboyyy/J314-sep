#!/usr/bin/env python3
"""Invariants de l'en-tête OOL observé (0x1c octets, u32 LE : +0x00, +0x04 total, +0x08 offset,
+0x0c, +0x10, +0x14 TYPE, +0x18 longueur du morceau) sur une ou plusieurs captures (lecture seule).

Contrôles (sur les lectures dont le contenu rattaché passe le contrôle sha de ool_index) :
  I1 +0x00 == 0  <=>  buffer entièrement nul
  I2 si +0x00 == 1 : TYPE en-tête == TYPE du mot mailbox (messages TAG 0xfc/0xfd/0xfe)
  I3 longueur du morceau == min(0x3fe4, total - offset)
  I4 +0x0c == +0x10 == 0
  I5 +0x00 ∈ {0, 1}
  I6 octets non nuls au-delà de 0x1c + longueur du morceau : aucun
Une violation est listée avec sa ligne ; c'est une observation, pas une conclusion.

Usage :
    python3 analysis/ool_invariants.py traces/<A>/ [traces/<B>/ ...] [-o analysis/out/x.txt]
"""

import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import write_output  # noqa: E402
from ool_index import load_index  # noqa: E402

CHUNK = 0x3FE4


def check(capture):
    viol = {k: [] for k in ("I1", "I2", "I3", "I4", "I5", "I6")}
    n = n1 = 0
    for r in load_index(capture, 0x08):
        d, m = r["data"], r["msg"]
        if r["sha_ok"] is not True or len(d) < 0x1C:
            continue
        n += 1
        h0, tot, off, c, x, t, clen = struct.unpack_from("<7I", d, 0)
        ln = m["lineno"]
        allzero = not any(d)
        if (h0 == 0) != allzero:
            viol["I1"].append(ln)
        if h0 not in (0, 1):
            viol["I5"].append(ln)
        if h0 != 1:
            continue
        n1 += 1
        if m["tag"] in (0xFC, 0xFD, 0xFE) and t != m["type"]:
            viol["I2"].append(ln)
        if clen != min(CHUNK, tot - off) if tot >= off else True:
            viol["I3"].append(ln)
        if c or x:
            viol["I4"].append(ln)
        if any(d[0x1C + clen:]):
            viol["I6"].append(ln)
    return n, n1, viol


def render(paths):
    out = []
    for p in paths:
        n, n1, viol = check(p)
        out.append("## %s : %d lectures contrôlées, %d avec +0x00=1" % (p, n, n1))
        for k, v in viol.items():
            out.append("  %s : %d violation(s)%s" % (k, len(v), (" L" + ", L".join(map(str, v[:20]))) if v else ""))
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("paths", nargs="+")
    ap.add_argument("-o", dest="out")
    a = ap.parse_args(argv)
    text = render(a.paths)
    if a.out:
        write_output(a.out, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
