#!/usr/bin/env python3
"""Tableau, une ligne par tentative doigt, des champs OOL repérés dans C8 (lecture seule).

Champs (offsets dans la charge, OBSERVÉS dans C6/C8, pas une spécification) :
  0x06 (A) : +0x44 u32, +0x48 u32, +0x07 u8
  0x07 (B) : +0x02 u8, +0x06..07, +0x28 u8, float32 +0x18
  0x09 (B) : +0x00 u32 (0x1f5 / 0xffffffff), 16 o +0x04 (4 premiers), +0xc24 u32, durée 0x09 (ms)
  0x21 (B) : +0x02 u16, +0x04 u32
  séquence (lock_cycles.summarize), notif SKS -501 (`< EP=0x12 TAG=0 DATA=0xfffffe0b`) pendant la tentative,
  marque en cours et résultat noté (notes.txt, ligne `res_<marque> o|n` si présente).

Usage :
    python3 analysis/attempt_fields.py traces/<capture>/ [-o analysis/out/x.txt]
"""

import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_file, write_output, load_marks, marks_path_for  # noqa: E402
from lock_cycles import attempts, label_at, summarize  # noqa: E402
import ool_attempts  # noqa: E402


def notes(capture):
    res = {}
    p = os.path.join(capture, "notes.txt")
    if os.path.exists(p):
        for line in open(p, encoding="utf-8", errors="replace"):
            parts = line.split()
            if len(parts) >= 3 and parts[1].startswith("res_"):
                res[parts[1][4:]] = parts[2]
    return res


def u32(b, o):
    return struct.unpack_from("<I", b, o)[0] if b and len(b) >= o + 4 else None


def render(capture):
    msgs, _ = parse_file(capture)
    sb = [m for m in msgs if m.ep == 0x08]
    sks = [m for m in msgs if m.ep == 0x12 and m.dir == "<" and m.tag == 0 and m.data == 0xFFFFFE0B]
    mp = marks_path_for(capture)
    marks = load_marks(mp) if os.path.exists(mp) else []
    res = notes(capture)
    col = {a["lo"]: a for a in ool_attempts.collect(capture)}
    out = ["# attempt_fields : %s" % capture,
           "L_début | marque | res | 06:+44 +48 +07 | 07:+02 +06 +28 f18 | 09:+00 id c24 ms | 21:+02 +04 | -501 | séquence"]
    for att in attempts(sb):
        lo, hi = att[0].lineno, att[-1].lineno
        lab = label_at(marks, att[0].ts)
        p = col.get(lo, {}).get("payloads", {})
        g = lambda k: p.get(k, (0, b""))[1]  # noqa: E731
        a6, b7, b9, b21 = g((">", "A", 0x06)), g(("<", "B", 0x07)), g(("<", "B", 0x09)), g(("<", "B", 0x21))
        req = [m for m in att if m.tag == 0xFC and m.type == 0x09]
        ms = "%.0f" % ((req[1].ts - req[0].ts) * 1000) if len(req) >= 2 else "-"
        f18 = "%.3f" % struct.unpack_from("<f", b7, 0x18)[0] if len(b7) >= 0x1C else "-"
        neg = any(lo <= m.lineno <= hi for m in sks)
        out.append("L%d | %s | %s | %s %s %s | %s %s %s %s | %s %s %s %s | %s %s | %s | %s" % (
            lo, lab, res.get(lab, "?"),
            u32(a6, 0x44), u32(a6, 0x48), a6[7] if len(a6) > 7 else None,
            b7[2] if b7 else None, b7[6:8].hex() if b7 else None, b7[0x28] if len(b7) > 0x28 else None, f18,
            ("%x" % u32(b9, 0)) if b9 else "-", b9[4:8].hex() if b9 else "-",
            ("%x" % u32(b9, 0xC24)) if len(b9) > 0xC28 else "-", ms,
            struct.unpack_from("<H", b21, 2)[0] if len(b21) >= 4 else "-", ("%x" % u32(b21, 4)) if len(b21) >= 8 else "-",
            "oui" if neg else "non", summarize(att)))
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("capture")
    ap.add_argument("-o", dest="out")
    a = ap.parse_args(argv)
    text = render(a.capture)
    if a.out:
        write_output(a.out, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
