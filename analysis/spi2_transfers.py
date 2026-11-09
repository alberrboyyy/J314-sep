#!/usr/bin/env python3
"""Résumé des échanges sur le bus SPI du capteur (spi2.log écrit par hv/trace_sep_spi.py).

Usage : analysis/spi2_transfers.py traces/<dossier> [--sep]
Un échange = de l'écriture CTRL (+0x000) avec RUN=1 jusqu'au CTRL=0 suivant. Pour chacun : heure relative,
RXCNT (+0x034) et TXCNT (+0x04c) programmés, CLKDIV (+0x030), CFG (+0x004), nombre d'accès TXDATA/RXDATA.
Les lignes gpio0 (broches 195 = IRQ, 196 = alimentation) sont affichées à leur place.
--sep : intercale les messages SEP de l'EP 0x08 (sep.log) pour situer les échanges.
VU seulement : aucun décodage du contenu (les données passent par DMA, pas par ces registres).
"""
import os, sys

d = sys.argv[1]
with_sep = "--sep" in sys.argv
ev = []
for l in open(os.path.join(d, "spi2.log")):
    if l.startswith("#"):
        continue
    ts, rw, dev, off, width, val = l.split()
    ev.append((float(ts), "reg", rw, dev, int(off, 16), int(val, 16)))
if with_sep:
    for l in open(os.path.join(d, "sep.log"), errors="replace"):
        if l.startswith("#") or " EP=0x08 " not in l:
            continue
        ts, rest = l.split(" ", 1)
        ev.append((float(ts), "sep", rest.strip()))
ev.sort(key=lambda e: e[0])
t0 = ev[0][0]
PIN = {0x30c: "broche195(IRQ)", 0x310: "broche196(alim)", 0xc0: "broche48", 0xc4: "broche49", 0xc8: "broche50", 0xcc: "broche51"}
cur = None
n = 0
last_pin = {}
for e in ev:
    t = e[0] - t0
    if e[1] == "sep":
        print(f"{t:9.3f}  SEP {e[2]}")
        continue
    _, _, rw, dev, off, val = e
    if dev == "gpio0":
        if rw == "W" and last_pin.get(off) != val:
            # la broche 195 est masquée/démasquée en permanence : n'afficher que les changements de mode
            if off == 0x30c and last_pin.get(off) is not None and (last_pin[off] ^ val) & ~0x0e == 0:
                last_pin[off] = val
                continue
            print(f"{t:9.3f}  GPIO {PIN.get(off, hex(off))} <- {val:#x} (mode={(val>>1)&7} data={val&1})")
            last_pin[off] = val
        continue
    if rw == "W" and off == 0x34:
        cur = cur or {}
        cur["rx"] = val
    elif rw == "W" and off == 0x4c:
        cur = cur or {}
        cur["tx"] = val
    elif rw == "W" and off == 0x30:
        cur = cur or {}
        cur["div"] = val
    elif rw == "W" and off == 0x04 and cur is not None and "cfg" not in cur:
        cur["cfg"] = val
    elif off in (0x10, 0x20) and cur is not None:
        cur["fifo"] = cur.get("fifo", 0) + 1
    elif rw == "W" and off == 0x00 and val & 1:
        cur = cur or {}
        cur["start"] = t
    elif rw == "W" and off == 0x00 and val == 0 and cur and "start" in cur:
        n += 1
        print(f"{cur['start']:9.3f}  SPI #{n:<3} rx={cur.get('rx', 0):#06x} tx={cur.get('tx', 0):#06x} "
              f"clkdiv={cur.get('div', -1)} cfg={cur.get('cfg', 0):#x} fifo_acc={cur.get('fifo', 0)} "
              f"durée={1000 * (t - cur['start']):.1f} ms")
        cur = None
print(f"# {n} échanges")
