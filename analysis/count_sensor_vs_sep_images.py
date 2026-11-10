#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Combien d'images le capteur fournit-il sur le bus SPI, et combien l'AP en transmet-il au SEP ?
Capture « doigt » (C20). Compte les images 0x7200 lues sur le bus (sio.bufs/*_done_data.bin) et les
images 0x65 envoyées au SEP (sep.log : messages `> EP=0x08 TYPE=0x65`, 2 tranches par image), et range
les envois par phase (marque de pose de doigt). Lecture seule, hors ligne.

Résultat C20 (2026-11-10) : 27 images lues sur le bus, 7 transmises au SEP (14 tranches 0x65) -> ~20
images lues mais NON transmises. Les 7 transmises tombent sur les poses (≈1 par pose) et sont celles
retrouvées octet pour octet côté SEP (voir analysis/cmp_sensor_sep_image.py).
"""
import glob
import os
import re
import sys
from collections import Counter


def main():
    trace = sys.argv[1] if len(sys.argv) > 1 else sorted(glob.glob(
        os.path.join(os.path.dirname(__file__), "..", "traces", "*c20*")))[-1]
    sep = open(os.path.join(trace, "sep.log"), encoding="utf-8", errors="replace").read().splitlines()
    marks = [(float(t), n) for t, n in (l.split() for l in open(os.path.join(trace, "marks.txt")))]

    img_ts = [float(m.group(1)) for m in
              (re.match(r"([\d.]+) > EP=0x08 .*TYPE=0x65 ", l) for l in sep if not l.startswith("#"))
              if m]

    sio = os.path.join(trace, "sio.bufs")
    def nz(p):
        return sum(1 for x in open(p, "rb").read() if x)
    done = [f for f in os.listdir(sio)
            if "done_data" in f and os.path.getsize(os.path.join(sio, f)) == 0x7200
            and nz(os.path.join(sio, f)) > 20000]

    def phase(ts):
        cur = "(avant)"
        for mt, mn in marks:
            if ts >= mt:
                cur = mn
            else:
                break
        return cur

    print("trace :", os.path.basename(os.path.abspath(trace)))
    print("images lues sur le bus capteur (done_data 0x7200 pleins) :", len(done))
    print("tranches 0x65 vers le SEP :", len(img_ts), f"  => {len(img_ts)//2} images transmises")
    print("images lues mais NON transmises au SEP :", len(done) - len(img_ts) // 2)
    print("\ntranches 0x65 par phase (marque en cours) :")
    for k, v in sorted(Counter(phase(t) for t in img_ts).items(), key=lambda x: -x[1]):
        print(f"  {v:3d}  {k}")


if __name__ == "__main__":
    main()
