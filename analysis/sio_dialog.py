#!/usr/bin/env python3
"""Dialogue AP <-> capteur reconstruit depuis sio.log + sio.bufs/ (hv/trace_sep_spi_dma.py).

Usage : analysis/sio_dialog.py traces/<dossier> [--sep] [--full]
TX (canal 0x18) : buffer lu à la programmation (« setup ») ; RX (canal 0x19) : buffer lu à la fin (« done »).
--sep  : intercale les messages SEP de l'EP 0x08.   --full : hexdump complet (défaut : 48 premiers octets).
VU seulement : aucun décodage au-delà du découpage brut.
"""
import os, re, sys, hashlib
d = sys.argv[1]
full = "--full" in sys.argv
ev = []
last_ts = 0.0
for l in open(os.path.join(d, "sio.log")):
    if l[0].isdigit():
        last_ts = float(l.split()[0]); continue
    m = re.match(r"# buf seq=(\d+) ep=0x(\w+) (\w+) ptr=0x(\w+) size=0x(\w+)", l)
    if not m:
        continue
    seq, ep, when = int(m[1]), int(m[2], 16), m[3]
    if (ep, when) not in ((0x18, "setup"), (0x19, "done")):
        continue
    f = os.path.join(d, "sio.bufs", f"{seq:06d}_{ep:02x}_{when}_data.bin")
    data = open(f, "rb").read() if os.path.exists(f) else None
    ev.append((last_ts, "TX" if ep == 0x18 else "RX", int(m[5], 16), data))
if "--sep" in sys.argv:
    for l in open(os.path.join(d, "sep.log"), errors="replace"):
        if l[0].isdigit() and " EP=0x08 " in l:
            ts, rest = l.split(" ", 1)
            ev.append((float(ts), "SEP", 0, rest.strip()))
ev.sort(key=lambda e: e[0])
t0 = ev[0][0]
for ts, kind, size, data in ev:
    if kind == "SEP":
        print(f"{ts-t0:9.3f} SEP {data}"); continue
    if data is None:
        print(f"{ts-t0:9.3f} {kind} {size:#06x} (non lu)"); continue
    h = data.hex() if full or len(data) <= 48 else data[:48].hex() + f"… sha1={hashlib.sha1(data).hexdigest()[:12]}"
    print(f"{ts-t0:9.3f} {kind} {size:#06x} {h}")
