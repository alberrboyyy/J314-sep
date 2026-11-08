#!/usr/bin/env python3
"""Lecture minimale d'un kernelcache Mach-O MH_FILESET (arm64e).

Phase 2 (CLAUDE.md) : sert uniquement à localiser les segments/sections d'un kext
pour en extraire le protocole AP<->SEP. Ne produit aucune copie de code.

Usage :
  macho_fileset.py KERNEL                 # liste les LC_FILESET_ENTRY
  macho_fileset.py KERNEL BUNDLE_ID       # segments/sections du kext
"""
import struct
import sys

LC_SEGMENT_64 = 0x19
LC_FILESET_ENTRY = 0x80000035
LC_SYMTAB = 0x2


def cmds(buf, off):
    magic, cpu, sub, ftype, ncmds, sizeofcmds, flags, _ = struct.unpack_from("<IiiIIIII", buf, off)
    assert magic == 0xfeedfacf, hex(magic)
    p = off + 32
    for _ in range(ncmds):
        cmd, size = struct.unpack_from("<II", buf, p)
        yield cmd, p, size
        p += size


def fileset_entries(buf):
    out = []
    for cmd, p, size in cmds(buf, 0):
        if cmd == LC_FILESET_ENTRY:
            vmaddr, fileoff, stroff = struct.unpack_from("<QQI", buf, p + 8)
            name = buf[p + stroff:buf.index(b"\0", p + stroff)].decode()
            out.append((name, vmaddr, fileoff))
    return out


def segments(buf, off):
    """Segments et sections d'un Mach-O à l'offset `off` (offsets fichier absolus dans le fileset)."""
    segs = []
    for cmd, p, size in cmds(buf, off):
        if cmd != LC_SEGMENT_64:
            continue
        segname = buf[p + 8:p + 24].rstrip(b"\0").decode()
        vmaddr, vmsize, fileoff, filesize = struct.unpack_from("<QQQQ", buf, p + 24)
        nsects = struct.unpack_from("<I", buf, p + 64)[0]
        sects = []
        q = p + 72
        for _ in range(nsects):
            sname = buf[q:q + 16].rstrip(b"\0").decode()
            addr, ssize, soff = struct.unpack_from("<QQI", buf, q + 32)
            sects.append((sname, addr, ssize, soff))
            q += 80
        segs.append((segname, vmaddr, vmsize, fileoff, filesize, sects))
    return segs


class Image:
    """Accès par adresse virtuelle au fileset entier (les kexts pointent dans tout le cache)."""

    def __init__(self, path):
        with open(path, "rb") as f:
            self.buf = f.read()
        self.map = []
        for name, vm, fo in [("kernel", 0, 0)] + fileset_entries(self.buf):
            for s in segments(self.buf, fo):
                if s[4]:
                    self.map.append((s[1], s[1] + s[4], s[3]))

    def off(self, va):
        va = strip(va)
        for a, b, fo in self.map:
            if a <= va < b:
                return fo + va - a
        return None

    def read(self, va, n):
        o = self.off(va)
        return None if o is None else self.buf[o:o + n]

    def cstr(self, va, maxlen=256):
        d = self.read(va, maxlen)
        if d is None:
            return None
        return d.split(b"\0", 1)[0].decode("latin-1")

    def u64(self, va):
        d = self.read(va, 8)
        return None if d is None else struct.unpack("<Q", d)[0]


def strip(v):
    """Pointeurs chaînés arm64e (DYLD_CHAINED_PTR_64_KERNEL_CACHE) -> adresse virtuelle."""
    if (v >> 40) == 0xfffffe:  # déjà une adresse noyau
        return v
    if v >> 32:  # pointeur chaîné : cible = base du cache + 30 bits bas
        return 0xfffffe0007004000 + (v & 0x3fffffff)
    return v


def main():
    with open(sys.argv[1], "rb") as f:
        buf = f.read()
    if len(sys.argv) == 2:
        for name, vm, fo in fileset_entries(buf):
            print(f"{vm:#x} {fo:#x} {name}")
        return
    for name, vm, fo in fileset_entries(buf):
        if name == sys.argv[2]:
            for seg in segments(buf, fo):
                print(f"{seg[0]:16} vm {seg[1]:#x}+{seg[2]:#x} file {seg[3]:#x}+{seg[4]:#x}")
                for s in seg[5]:
                    print(f"    {s[0]:20} {s[1]:#x} size {s[2]:#x} off {s[3]:#x}")
            return
    sys.exit("bundle introuvable")


if __name__ == "__main__":
    main()
