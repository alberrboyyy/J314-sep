#!/usr/bin/env python3
"""Table des symboles (LC_SYMTAB) d'un kernelcache MH_FILESET : nom -> adresse.

Phase 2 (CLAUDE.md) : sert à nommer les fonctions d'un kext pour en extraire le protocole AP<->SEP.
N'extrait aucun code.

  ksyms.py KERNEL [REGEX]          # symboles définis (adresse, nom), filtrés par regex
  ksyms.py KERNEL --at ADDR        # symbole contenant ADDR (le plus proche en dessous)
"""
import bisect
import os
import re
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
from macho_fileset import LC_SYMTAB, cmds, fileset_entries  # noqa: E402


def symbols(buf):
    """Symboles définis (n_type & N_SECT) de l'en-tête principal et de chaque entrée du fileset."""
    out = {}
    offs = [0] + [fo for _n, _v, fo in fileset_entries(buf)]
    for off in offs:
        for cmd, p, _size in cmds(buf, off):
            if cmd != LC_SYMTAB:
                continue
            symoff, nsyms, stroff, _strsize = struct.unpack_from("<IIII", buf, p + 8)
            for i in range(nsyms):
                strx, ntype, _sect, _desc, value = struct.unpack_from("<IBBhQ", buf, symoff + 16 * i)
                if (ntype & 0x0e) != 0x0e or not value:
                    continue
                name = buf[stroff + strx:buf.index(b"\0", stroff + strx)].decode("latin-1")
                out[value] = name
    return out


def main():
    with open(sys.argv[1], "rb") as f:
        buf = f.read()
    syms = symbols(buf)
    if len(sys.argv) > 3 and sys.argv[2] == "--at":
        addrs = sorted(syms)
        for a in sys.argv[3:]:
            v = int(a, 16)
            i = bisect.bisect_right(addrs, v) - 1
            print(f"{v:#x} {syms[addrs[i]]}+{v - addrs[i]:#x}" if i >= 0 else f"{v:#x} ?")
        return
    rx = re.compile(sys.argv[2]) if len(sys.argv) > 2 else None
    for a in sorted(syms):
        if rx is None or rx.search(syms[a]):
            print(f"{a:#x} {syms[a]}")


if __name__ == "__main__":
    main()
