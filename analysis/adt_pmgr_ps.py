#!/usr/bin/env python3
"""Hors ligne : adresse du registre d'alimentation (PS) d'un périphérique pmgr, depuis un dump adt.bin.

Usage : analysis/adt_pmgr_ps.py traces/<..>_adt/adt.bin [NOM ...]   (défaut : SPI1 SPI2 SPI3 SPI4)
Aucun accès hardware : lit le fichier. Utilise le décodeur public m1n1 (m1n1.adt) comme bibliothèque.
Formule = celle du code public m1n1 src/pmgr.c (pmgr_device_get_addr) :
  adresse = pmgr.reg[ps-regs[psreg].reg].addr + ps-regs[psreg].offset + psidx*8   (+ base arm-io pour l'adresse CPU)
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "m1n1", "proxyclient"))
from m1n1 import adt

path = sys.argv[1]
names = sys.argv[2:] or ["SPI1", "SPI2", "SPI3", "SPI4"]
tree = adt.load_adt(open(path, "rb").read())
pmgr = tree["/arm-io/pmgr"]
ranges = tree["/arm-io"].ranges
regs = pmgr.reg
psregs = pmgr.ps_regs if hasattr(pmgr, "ps_regs") else getattr(pmgr, "ps-regs")
devs = {d.name: d for d in pmgr.devices}
byid = {d.id2: d.name for d in pmgr.devices}

def cpu(addr):
    for r in ranges:
        if r.bus_addr <= addr < r.bus_addr + r.size:
            return addr - r.bus_addr + r.parent_addr
    return None

print(f"pmgr.reg : {[(hex(r.addr), hex(r.size)) for r in regs]}")
for n in names:
    d = devs.get(n)
    if d is None:
        print(f"{n}: absent de pmgr.devices"); continue
    ps = psregs[d.psreg]
    r = regs[ps.reg]
    off = ps.offset + d.psidx * 8
    a = r.addr + off
    par = [byid.get(p, p) for p in d.parents_un.u16id.parents if p]
    print(f"{n}: id={d.id2} psreg={d.psreg} psidx={d.psidx} -> pmgr.reg[{ps.reg}] (bus {r.addr:#x}) + {off:#x}"
          f" = bus {a:#x}, CPU {cpu(a):#x} ; parents={par} flags: on={d.flags.on} critical={d.flags.critical} no_ps={d.flags.no_ps}")
