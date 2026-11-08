#!/usr/bin/env python3
"""Listings par fonction nommée (LC_SYMTAB) d'un kext du fileset — phase 2, extraction de protocole uniquement.

Combine kdis.Kext (capstone) et ksyms.symbols : chaque symbole du __text du kext devient un début de fonction,
les cibles `bl` et les adrp+add sont annotées par le symbole le plus proche. Un fichier .s par fonction.
Les listings sont du code Apple désassemblé : ils vont dans analysis/out/ (ignoré par git), jamais dans le repo.

  kdump_syms.py KERNEL BUNDLE REGEX OUTDIR
  ex. kdump_syms.py macos/kernel.macho com.apple.driver.AppleSEPManager 'AppleSEPControl' analysis/out/kext/sepm
"""
import bisect
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kdis import Kext  # noqa: E402
from ksyms import symbols  # noqa: E402


def main():
    kern, bundle, rx, outdir = sys.argv[1:5]
    k = Kext(kern, bundle)
    syms = symbols(k.img.buf)
    starts = set(k.fstarts)
    for a in syms:
        if k.text_va <= a < k.text_va + k.text_size:
            starts.add(a)
    k.fstarts = sorted(starts)
    addrs = sorted(syms)

    def symat(v):
        i = bisect.bisect_right(addrs, v) - 1
        return f"{syms[addrs[i]]}+{v - addrs[i]:#x}" if i >= 0 else "?"

    r = re.compile(rx)
    os.makedirs(outdir, exist_ok=True)
    n = 0
    for a, name in sorted(syms.items()):
        if not (k.text_va <= a < k.text_va + k.text_size) or not r.search(name) or a not in k.idx:
            continue
        lines = []
        for line in k.listing(a):
            m = re.search(r"\bbl #(0x[0-9a-f]+)", line)
            if m:
                line += "  ; " + symat(int(m.group(1), 16))
            m = re.search(r"; (0x[0-9a-f]+)$", line)
            if m and not k.is_str(int(m.group(1), 16)):
                line += " " + symat(int(m.group(1), 16))
            lines.append(line)
        fn = re.sub(r"[^A-Za-z0-9_]", "_", name)[:150]
        with open(os.path.join(outdir, fn + ".s"), "w") as f:
            f.write(f"; {name} @ {a:#x}\n" + "\n".join(lines) + "\n")
        n += 1
    print(f"{n} fonctions -> {outdir}")


if __name__ == "__main__":
    main()
