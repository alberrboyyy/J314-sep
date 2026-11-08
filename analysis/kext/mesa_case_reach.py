#!/usr/bin/env python3
"""Attribution robuste des appels sepTransact aux cases de performSpecificCommandGated
par accessibilité dans le graphe de flot (phase 2, source: kext).

Depuis le début de chaque case, on suit fall-through et branchements (b, b.cc, cbz/cbnz, tbz/tbnz)
sans traverser le début d'un autre case. Un site atteint par un seul case est non ambigu.
Entrée : analysis/out/kext/f_psc.txt (listing produit par `kdis.py ... func 0xfffffe000977eecc`).
"""
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
from macho_fileset import Image, strip  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "out", "kext")


def main():
    im = Image(sys.argv[1])
    names = {i + 1: im.cstr(strip(im.u64(0xfffffe0007d5ed18 + 8 * i)), 40) for i in range(0x58)}
    cases = {}
    for i in range(0x57):
        off = struct.unpack("<i", im.read(0xfffffe0009782ec0 + 4 * i, 4))[0]
        cases.setdefault(0xfffffe000977f080 + off, []).append(i + 1)
    ins = []
    for line in open(os.path.join(OUT, "f_psc.txt")):
        a, b = line.split(": ", 1)
        ins.append((int(a, 16), b.split("  ;")[0].strip()))
    idx = {a: n for n, (a, _) in enumerate(ins)}
    sites = {}
    for fn in ("mesa_vcallers_0x9e0.txt", "mesa_vcallers_0x9d8.txt"):
        for line in open(os.path.join(OUT, fn)):
            p = line.split("\t")
            if int(p[1], 16) == 0xfffffe000977eecc:
                sites[int(p[0], 16)] = p[3].replace("mov w1, ", "") + (" (IOMD)" if "9d8" in fn else "")
    reach = {s: [] for s in sites}
    for cs in cases:
        seen, todo = set(), [cs]
        while todo:
            a = todo.pop()
            if a in seen or a not in idx or (a in cases and a != cs):
                continue
            seen.add(a)
            n = idx[a]
            m = ins[n][1]
            op = m.split()[0]
            tgt = re.search(r"#(0x[0-9a-f]+)$", m)
            if op in ("ret", "retab", "br") or op.startswith("brk"):
                continue
            if op == "b":
                todo.append(int(tgt.group(1), 16))
                continue
            if op.startswith("b.") or op in ("cbz", "cbnz", "tbz", "tbnz"):
                todo.append(int(tgt.group(1), 16))
            if n + 1 < len(ins):
                todo.append(ins[n + 1][0])
        for s in sites:
            if s in seen:
                reach[s].append(cs)
    for s in sorted(sites):
        who = [f"{c:#x}={names[c]}" for cs in reach[s] for c in cases[cs]]
        print(f"{s:#x}\t{sites[s]}\t{'UNIQUE' if len(reach[s]) == 1 else 'AMBIGU'}\t{', '.join(who)}")


if __name__ == "__main__":
    main()
