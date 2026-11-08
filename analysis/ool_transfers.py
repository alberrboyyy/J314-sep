#!/usr/bin/env python3
"""Liste les transferts OOL SBIO en plusieurs morceaux (TYPE 0x5b, 0x5f, 0x6c, 0x6d par défaut) d'une capture,
recollés selon l'en-tête observé (offset +0x08, longueur du morceau +0x18) : ligne, sens/buffer, total, octets
lus, sha256[:8], magic, uid (+0x08 de la charge). Lecture seule. `--dump-dir` écrit les blobs recollés.

Usage :
    python3 analysis/ool_transfers.py traces/<capture>/ [--types 0x6c,0x6d] [--dump-dir analysis/out/<x>/] [-o ...]
"""

import argparse
import hashlib
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import write_output, safe_output_path  # noqa: E402
from ool_index import load_index  # noqa: E402


def transfers(capture, types=(0x5B, 0x5F, 0x6C, 0x6D)):
    out, cur = [], {}
    for r in load_index(capture, 0x08):
        m, d = r["msg"], r["data"]
        if m["tag"] not in (0xFC, 0xFD, 0xFE) or m["type"] not in types or len(d) < 0x1C or d[0] != 1:
            continue
        h = struct.unpack_from("<7I", d, 0)
        if h[5] != m["type"]:
            continue
        key = (r["dir"], r["buf"], m["type"])
        if h[2] == 0:
            cur[key] = {"key": key, "line": m["lineno"], "total": h[1], "chunks": {}, "trunc": False}
            out.append(cur[key])
        t = cur.get(key)
        if t is None:
            continue
        avail = len(d) - 0x1C
        t["chunks"][h[2]] = d[0x1C:0x1C + min(h[6], avail)]
        if avail < h[6]:
            t["trunc"] = True
    for t in out:
        t["blob"] = b"".join(t["chunks"][k] for k in sorted(t["chunks"]))
        t["sha"] = hashlib.sha256(t["blob"]).hexdigest()[:8]
    return out


def render(capture, types, dump_dir):
    lines = ["# ool_transfers : %s" % capture,
             "ligne  sens  TYPE  total   lu      tronqué sha      magic     uid"]
    for t in transfers(capture, types):
        b = t["blob"]
        uid = struct.unpack_from("<I", b, 8)[0] if len(b) >= 12 else None
        lines.append("L%-5d %s%s   0x%02x  0x%-5x 0x%-5x %-7s %s %-9s %s" % (
            t["line"], t["key"][0], t["key"][1], t["key"][2], t["total"], len(b), t["trunc"], t["sha"],
            b[:4].hex(), "-" if uid is None else "%x" % uid))
        if dump_dir:
            with open(os.path.join(dump_dir, "L%05d_%s%s_%02x.bin" % (t["line"], "in" if t["key"][0] == ">" else "out",
                                                                     t["key"][1], t["key"][2])), "wb") as f:
                f.write(b)
    return "\n".join(lines) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("capture")
    ap.add_argument("--types", default="0x5b,0x5f,0x6c,0x6d")
    ap.add_argument("--dump-dir")
    ap.add_argument("-o", dest="out")
    a = ap.parse_args(argv)
    dd = None
    if a.dump_dir:
        dd = safe_output_path(a.dump_dir)
        os.makedirs(dd, exist_ok=True)
    text = render(a.capture, tuple(int(x, 0) for x in a.types.split(",")), dd)
    if a.out:
        write_output(a.out, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
