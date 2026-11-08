#!/usr/bin/env python3
"""Compare les réponses SBIO d'init (`< B 0xfc` TYPE 0x54, 0x6e, 0x7a par défaut) d'une capture à celles
d'autres captures, et la réponse 0x54 aux copies vues dans les réponses 0x09 de succès (lecture seule).

Test de l'hypothèse HI (docs/hypotheses.md) : l'enregistrement 0x54 (0xbf4 o) est-il persistant et mis à jour
après un succès ? Copie dans 0x09 = charge 0x09[0x2c:0x2c+len(0x54)] ; copie dans 0x21 = 0x21[0x30:...], offsets 0x06-0x2d
de l'enregistrement exclus (recouverts) — offsets OBSERVÉS dans C8, pas une spécification.

Usage :
    python3 analysis/init_persist.py traces/<cible>/ --ref traces/<A>/ [--ref ...] [--succ traces/<C8>/] [-o analysis/out/x.txt]
"""

import argparse
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import write_output  # noqa: E402
from ool_index import load_index  # noqa: E402
import ool_attempts  # noqa: E402

HDR = 0x1C
COPY_OFF = 0x2C
COPY21_OFF = 0x30          # copie dans la réponse 0x21 (OBSERVÉ C8)
COPY21_MASK = (0x06, 0x2E)  # offsets de l'enregistrement recouverts par l'en-tête de 0x21 : non comparés


def payload(r):
    d = r["data"]
    if len(d) < HDR:
        return None
    one, total, off, _, _, t, clen = struct.unpack_from("<7I", d, 0)
    return d[HDR:HDR + min(clen, len(d) - HDR)], total


def init_responses(capture, types):
    out = {}
    for r in load_index(capture, 0x08):
        m = r["msg"]
        if r["dir"] == "<" and r["buf"] == "B" and m["tag"] == 0xFC and m["type"] in types and m["type"] not in out:
            p = payload(r)
            if p:
                out[m["type"]] = (p[0], p[1], m["lineno"])
    return out


def success_copies(capture, n):
    res = []
    for a in ool_attempts.collect(capture):
        k = ("<", "B", 0x09)
        if k in a["payloads"] and a["payloads"][k][1][:4] == b"\xf5\x01\x00\x00":
            b = a["payloads"][k][1]
            res.append(("%s L%d %s" % (os.path.basename(os.path.normpath(capture)), a["lo"], a["label"]),
                        b[COPY_OFF:COPY_OFF + n]))
    return res


def success_copies21(capture, n):
    res = []
    for a in ool_attempts.collect(capture):
        k = ("<", "B", 0x21)
        if k in a["payloads"] and a["payloads"][k][1][4:8] == b"\xf5\x01\x00\x00":
            b = a["payloads"][k][1]
            res.append(("%s L%d %s [0x21]" % (os.path.basename(os.path.normpath(capture)), a["lo"], a["label"]),
                        b[COPY21_OFF:COPY21_OFF + n]))
    return res


def diff(a, b, mask=None):
    n = min(len(a), len(b))
    d = [i for i in range(n) if a[i] != b[i] and not (mask and mask[0] <= i < mask[1])]
    return d, len(a) != len(b)


def groups(offs):
    out, s, p = [], None, None
    for i in offs:
        if s is None:
            s = p = i
        elif i == p + 1:
            p = i
        else:
            out.append((s, p))
            s = p = i
    if s is not None:
        out.append((s, p))
    return ", ".join("0x%x" % a if a == b else "0x%x-0x%x" % (a, b) for a, b in out)


def render(target, refs, succ, types):
    out = ["# init_persist : cible %s" % target]
    tgt = init_responses(target, types)
    for t in types:
        if t not in tgt:
            out.append("## TYPE 0x%02x : absent de la cible" % t)
            continue
        p, total, ln = tgt[t]
        out.append("## TYPE 0x%02x : cible L%d, longueur 0x%x (lue 0x%x)" % (t, ln, total, len(p)))
        cands = []
        for r in refs:
            rr = init_responses(r, [t])
            if t in rr:
                cands.append(("%s init L%d" % (os.path.basename(os.path.normpath(r)), rr[t][2]), rr[t][0]))
        if t == 0x54 and succ:
            cands += success_copies(succ, len(p))
            cands += success_copies21(succ, len(p))
        for name, q in cands:
            d, lendiff = diff(p, q, COPY21_MASK if name.endswith("[0x21]") else None)
            out.append("  vs %-40s : %d octets différents%s%s" % (
                name, len(d), " (longueurs différentes)" if lendiff else "", (" @ " + groups(d)) if d else ""))
            if d:
                out.append("     cible : " + " ".join("%x=%02x" % (i, p[i]) for i in d[:24]))
                out.append("     autre : " + " ".join("%x=%02x" % (i, q[i]) for i in d[:24]))
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("target")
    ap.add_argument("--ref", action="append", default=[])
    ap.add_argument("--succ")
    ap.add_argument("--types", default="0x54,0x6e,0x7a")
    ap.add_argument("-o", dest="out")
    a = ap.parse_args(argv)
    types = [int(x, 0) for x in a.types.split(",")]
    text = render(a.target, a.ref, a.succ, types)
    if a.out:
        write_output(a.out, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
