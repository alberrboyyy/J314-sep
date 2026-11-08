#!/usr/bin/env python3
"""Index des lectures OOL d'une capture : rattache chaque ligne `# ool` de sep.log au message qui la
précède (ligne du message, dir, TAG, TYPE) et au .bin éventuel (lecture seule sur traces/).

Pour chaque lecture : taille du dump, fin du contenu non nul (dernier octet != 0, +1), nz, changed,
trunc. Le .bin n'existe que si le contenu a changé : pour une lecture `changed=none`, on rattache le
dernier .bin connu du même buffer (champ `src`).

Sortie : tableau texte (une ligne par lecture) ; réutilisable : `from ool_index import load_index`.

Usage :
    python3 analysis/ool_index.py traces/<capture>/ [--ep 0x08] [-o analysis/out/x.txt]
"""

import argparse
import hashlib
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from parse_trace import parse_line, write_output, resolve_trace_path  # noqa: E402

OOL_RE = re.compile(r"^# ool (?P<ts>[\d.]+) (?P<kv>.*)$")


def content_end(b):
    i = len(b)
    while i > 0 and b[i - 1] == 0:
        i -= 1
    return i


def load_index(capture, ep=0x08):
    log = resolve_trace_path(capture)
    ooldir = log + ".ool"
    last_msg = None
    last_file = {}
    rows = []
    with open(log, "r", encoding="utf-8", errors="replace") as f:
        for n, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            if not line.startswith("#"):
                fields, _ = parse_line(line)
                if fields:
                    fields["lineno"] = n
                    last_msg = fields
                continue
            m = OOL_RE.match(line)
            if not m:
                continue
            kv = dict(p.split("=", 1) for p in m.group("kv").split() if "=" in p)
            if int(kv.get("EP", "0"), 16) != ep:
                continue
            buf = kv["buf"]
            r = {"ool_line": n, "seq": int(kv["seq"]), "dir": kv["dir"], "buf": buf, "sha": kv["sha"],
                 "nz": int(kv["nz"]), "changed": kv["changed"], "len": int(kv["len"], 16),
                 "elapsed_ms": float(kv["elapsed_ms"]), "full": kv.get("full"), "trunc": kv.get("trunc", "0"),
                 "file": kv.get("file"), "msg": last_msg}
            # Le tracer compare chaque lecture à la précédente de même (EP, buffer, LONGUEUR)
            # (hv/trace_sep_filtered.py, `key = (ep, name, len(blob))`) : une ligne changed=none renvoie au
            # dernier .bin de même (buffer, longueur), pas au dernier .bin du buffer.
            key = (buf, r["len"])
            if r["file"]:
                last_file[key] = r["file"]
            r["src"] = r["file"] or last_file.get(key)
            data = b""
            if r["src"]:
                with open(os.path.join(ooldir, r["src"]), "rb") as g:
                    data = g.read()
            r["data"] = data
            r["end"] = content_end(data)
            # contrôle : sha256[:8] du contenu rattaché = sha du log (None si aucun .bin)
            r["sha_ok"] = (hashlib.sha256(data).hexdigest()[:8] == r["sha"]) if r["src"] else None
            rows.append(r)
    return rows


def render(capture, ep):
    rows = load_index(capture, ep)
    bad = [r for r in rows if r["sha_ok"] is False]
    miss = [r for r in rows if r["sha_ok"] is None]
    out = ["# ool_index : %s EP=0x%02x, %d lectures ; contrôle sha : %d faux, %d sans .bin" % (
               capture, ep, len(rows), len(bad), len(miss)),
           "ool_L  msg_L  dir buf TAG  TYPE  len    end    nz    trunc changed  file"]
    for r in rows:
        m = r["msg"]
        out.append("%-6d %-6d %s   %s   0x%02x 0x%02x  0x%-4x 0x%-4x %-5d %-5s %-8s %s" % (
            r["ool_line"], m["lineno"], r["dir"], r["buf"], m["tag"], m["type"], r["len"], r["end"], r["nz"],
            r["trunc"], r["changed"][:8], (r["file"] or ("(=%s)" % r["src"])) +
            ("" if r["sha_ok"] is not False else "  SHA_FAUX")))
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("capture")
    ap.add_argument("--ep", default="0x08")
    ap.add_argument("-o", dest="out")
    a = ap.parse_args(argv)
    text = render(a.capture, int(a.ep, 0))
    if a.out:
        write_output(a.out, text)
    else:
        sys.stdout.write(text)


if __name__ == "__main__":
    main()
