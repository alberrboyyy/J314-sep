#!/usr/bin/env python3
"""ool_view.py -- liste et compare les dumps de buffers OOL écrits par hv/trace_sep_filtered.py
(option SEP_OOL_EPS) dans `<SEP_TRACE_OUT>.ool/<seq>_<ep>_<buf>.bin`.

    python3 analysis/ool_view.py traces/<capture>/sep.log.ool/
    python3 analysis/ool_view.py traces/<capture>/ --ep 0x08 --buf A --max-rows 40

<dossier> : le dossier .ool lui-même, ou une capture contenant un unique `*.ool/`.
Lecture seule, stdlib uniquement, sortie sur stdout. Pour chaque (ep, buf), dans l'ordre des seq :
liste des dumps (taille, sha256[:8], octets non nuls), puis, entre deux dumps consécutifs, les
plages modifiées et un hexdump des lignes de 16 octets touchées (`-` ancien, `+` nouveau,
`^^` sous les octets modifiés). Le tracer n'écrit un .bin que si le contenu change : deux dumps
consécutifs ici ne sont donc pas forcément deux messages consécutifs (voir seq et sep.log).
Une différence est une observation, pas une interprétation.
"""

import argparse
import glob
import hashlib
import os
import re
import sys

NAME_RE = re.compile(r"^(\d+)_([0-9a-fA-F]{2})_([A-Za-z0-9]+)\.bin$")


def diff_ranges(old, new):
    """Plages (off, len) différentes ; une différence de longueur compte comme modifiée."""
    n = min(len(old), len(new))
    ranges, start = [], None
    for i in range(n):
        if old[i] != new[i]:
            if start is None:
                start = i
        elif start is not None:
            ranges.append((start, i - start))
            start = None
    if start is not None:
        ranges.append((start, n - start))
    if len(old) != len(new):
        hi = max(len(old), len(new))
        if ranges and sum(ranges[-1]) == n:
            s0 = ranges.pop()[0]
            ranges.append((s0, hi - s0))
        else:
            ranges.append((n, hi - n))
    return ranges


def find_dir(path):
    if os.path.isdir(path) and path.rstrip("/").endswith(".ool"):
        return path
    cands = sorted(glob.glob(os.path.join(path, "*.ool")))
    cands = [c for c in cands if os.path.isdir(c)]
    if len(cands) == 1:
        return cands[0]
    if not cands and os.path.isdir(path) and any(NAME_RE.match(f) for f in os.listdir(path)):
        return path
    raise SystemExit(f"ool_view: {path}: dossier .ool introuvable ou ambigu ({len(cands)} candidats)")


def list_dumps(d):
    """{(ep, buf): [(seq, chemin), ...]} trié par seq ; fichiers hors format ignorés (comptés)."""
    groups, ignored = {}, []
    for f in sorted(os.listdir(d)):
        m = NAME_RE.match(f)
        if not m:
            ignored.append(f)
            continue
        key = (int(m.group(2), 16), m.group(3))
        groups.setdefault(key, []).append((int(m.group(1)), os.path.join(d, f)))
    for v in groups.values():
        v.sort()
    return groups, ignored


def _hex(row, base, n):
    cells = []
    for i in range(16):
        j = base + i
        cells.append(f"{row[j]:02x}" if j < n else "  ")
    return " ".join(cells)


def hexdiff(old, new, max_rows):
    """Lignes de hexdump pour les rangées de 16 octets où old != new."""
    hi = max(len(old), len(new))
    out, rows = [], 0
    for base in range(0, hi, 16):
        a, b = old[base:base + 16], new[base:base + 16]
        if a == b:
            continue
        if rows >= max_rows:
            out.append(f"    ... (rangées suivantes omises, --max-rows {max_rows})")
            break
        rows += 1
        marks = " ".join("^^" if (i >= len(a) or i >= len(b) or a[i] != b[i]) and (i < len(a) or i < len(b))
                         else "  " for i in range(16))
        out.append(f"    {base:06x} - {_hex(old, base, len(old))}")
        out.append(f"    {base:06x} + {_hex(new, base, len(new))}")
        out.append(f"             {marks.rstrip()}")
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dir")
    ap.add_argument("--ep", type=lambda s: int(s, 0), help="ne garder qu'un endpoint")
    ap.add_argument("--buf", help="ne garder qu'un buffer (A, B, ...)")
    ap.add_argument("--max-rows", type=int, default=32, help="rangées de hexdump max par paire (défaut 32)")
    args = ap.parse_args(argv)

    d = find_dir(args.dir)
    groups, ignored = list_dumps(d)
    print(f"# ool_view {d} groupes={len(groups)} fichiers_ignorés={len(ignored)}")
    for (ep, buf), dumps in sorted(groups.items()):
        if args.ep is not None and ep != args.ep:
            continue
        if args.buf is not None and buf != args.buf:
            continue
        print(f"\n== EP=0x{ep:02x} buf={buf} dumps={len(dumps)}")
        prev = None
        for seq, path in dumps:
            with open(path, "rb") as f:
                data = f.read()
            sha = hashlib.sha256(data).hexdigest()[:8]
            nz = len(data) - data.count(0)
            print(f"  seq={seq} file={os.path.basename(path)} len=0x{len(data):x} sha={sha} nz={nz}")
            if prev is not None:
                pseq, pdata = prev
                rng = diff_ranges(pdata, data)
                txt = ",".join(f"0x{o:x}+0x{l:x}" for o, l in rng) or "aucune"
                print(f"   diff seq={pseq} -> seq={seq} plages={len(rng)} : {txt}")
                for line in hexdiff(pdata, data, args.max_rows):
                    print(line)
            prev = (seq, data)
    return 0


if __name__ == "__main__":
    sys.exit(main())
