#!/usr/bin/env python3
"""Chronologie compacte spi2 + broches gpio0 195/196 depuis un spi2.log (hv/trace_sep_spi*.py).

Usage :
  analysis/spi2_gpio_timeline.py traces/<dossier> --patch [avant_ms] [apres_ms]
      fenêtre autour de chaque transaction de patch (len 0x568e ou 0x70ce), temps relatifs au bloc
  analysis/spi2_gpio_timeline.py traces/<dossier> <ts_debut> <ts_fin>
      fenêtre absolue

Une transaction spi2 = W +0x04c (longueur), W +0x000 0xd (START), R +0x10c (DONE).
gpio0 +0x30c = broche 195 (IRQ capteur), +0x310 = broche 196 (alim). Décodage du mode (bits 3:1) selon le
pilote public Linux pinctrl-apple-gpio.c (REG_GPIOx_MODE : 0 = entrée sans IRQ, 2 = IRQ niveau haut, 7 = IRQ off).
VU seulement : on n'interprète pas le contenu.
"""
import sys

MODES = {0: "entrée sans IRQ (masquée)", 1: "sortie", 2: "IRQ niveau haut", 3: "IRQ niveau bas",
         4: "IRQ front montant", 5: "IRQ front descendant", 6: "IRQ deux fronts", 7: "IRQ off"}
USUAL = {"+0x004": ("0x40042", "0x40002"), "+0x030": ("0x3",), "+0x150": ("0x80c07",)}


def events(d):
    for l in open(d + "/spi2.log"):
        if l[0] == "#":
            continue
        p = l.split()
        yield float(p[0]), p[1], p[2], p[3], p[5]


def line(rw, dev, off, val):
    if dev == "gpio0" and rw == "W":
        pin = {"+0x30c": 195, "+0x310": 196}.get(off)
        mode = MODES.get((int(val, 16) >> 1) & 7, "?")
        return f"GPIO {pin} = {val} ({mode})"
    if dev != "spi2":
        return None
    if rw == "W" and off == "+0x04c":
        return f"SPI  len={int(val, 16):#x}"
    if rw == "W" and off == "+0x000" and val == "0xd":
        return "SPI  START"
    if rw == "R" and off == "+0x10c":
        return f"SPI  DONE ({val})"
    if rw == "W" and off in USUAL and val not in USUAL[off]:
        return f"SPI  REG {off}={val} (inhabituel)"
    return None


def show(d, lo, hi, ref=None):
    for ts, rw, dev, off, val in events(d):
        if lo <= ts <= hi:
            s = line(rw, dev, off, val)
            if s:
                t = f"{(ts - ref) * 1000:+8.1f} ms" if ref is not None else f"{ts:.6f}"
                print(f"{t}  {s}")


def main():
    d = sys.argv[1]
    if sys.argv[2] == "--patch":
        before = float(sys.argv[3]) if len(sys.argv) > 3 else 30.0
        after = float(sys.argv[4]) if len(sys.argv) > 4 else 100.0
        refs = [ts for ts, rw, dev, off, val in events(d)
                if dev == "spi2" and rw == "W" and off == "+0x04c" and int(val, 16) in (0x568e, 0x70ce)]
        for r in refs:
            print(f"=== bloc patch @ {r:.6f}")
            show(d, r - before / 1000, r + after / 1000, r)
    else:
        show(d, float(sys.argv[2]), float(sys.argv[3]))


if __name__ == "__main__":
    main()
