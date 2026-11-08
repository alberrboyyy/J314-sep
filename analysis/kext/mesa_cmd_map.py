#!/usr/bin/env python3
"""Correspondance commande user-client (performSpecificCommandGated) -> commande SEP (TYPE sbio).

Phase 2, source: kext (AppleMesaSEPDriver, macOS 13.5). Lit :
  - la table de noms des commandes user-client (pointeurs vers "GetCmdProtocolVersion"...),
  - la table de sauts du switch de performSpecificCommandGated (cases 1..0x57),
  - les sites d'appel virtuels de sepTransact (vtable +0x9e0) / sepTransactToIOMD (+0x9d8)
    produits par `kdis.py ... vcallers` (fichiers analysis/out/kext/mesa_vcallers_0x9e0.txt / _0x9d8.txt).
Chaque site est attribué au case dont l'adresse de début est la plus proche en dessous.
Limite : un case peut sauter dans le code d'un autre (code partagé) ; l'attribution est alors fausse.

  mesa_cmd_map.py KERNEL
"""
import bisect
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
from macho_fileset import Image, strip  # noqa: E402

NAMES = 0xfffffe0007d5ed18      # table de noms (ldr x0, [x9, w8, sxtw #3], index = cmd-1)
JT = 0xfffffe0009782ec0         # table de sauts du switch (cmd-1, 0..0x56)
JT_BASE = 0xfffffe000977f080    # adr x17 de référence
OUT = os.path.join(os.path.dirname(__file__), "..", "out", "kext")
PSC = 0xfffffe000977eecc


def main():
    im = Image(sys.argv[1])
    names = {}
    for i in range(0x58):
        p = im.u64(NAMES + 8 * i)
        names[i + 1] = im.cstr(strip(p), 60)
    cases = {}
    for i in range(0x57):
        off = struct.unpack("<i", im.read(JT + 4 * i, 4))[0]
        cases.setdefault(JT_BASE + off, []).append(i + 1)
    starts = sorted(cases)
    for fn, kind in (("mesa_vcallers_0x9e0.txt", "sepTransact"), ("mesa_vcallers_0x9d8.txt", "sepTransactToIOMD")):
        for line in open(os.path.join(OUT, fn)):
            a, f, fname, cmd = line.split("\t")[:4]
            a, f = int(a, 16), int(f, 16)
            if f != PSC:
                continue
            j = bisect.bisect_right(starts, a) - 1
            cs = cases[starts[j]] if j >= 0 else []
            print(f"{a:#x}\t{kind}\t{cmd.replace('mov w1, ', '')}\tcase@{starts[j]:#x}\t"
                  + ", ".join(f"{c:#x}={names[c]}" for c in cs))
    print("# table des noms user-client")
    for c in sorted(names):
        print(f"#  {c:#04x} {names[c]}")


if __name__ == "__main__":
    main()
