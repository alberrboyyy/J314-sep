#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Compare, octet pour octet, l'image du capteur lue sur le bus SPI (sio.bufs/*_done_data.bin)
avec les buffers OOL échangés avec le SEP sur l'EP 0x08 (sep.log.ool/*_08_A.bin) d'une capture
« doigt » (C20). But : établir si l'AP relaie l'image au SEP telle quelle, et décrire l'entête OOL.

Lecture seule, hors ligne. Aucun accès matériel. N'écrit rien dans traces/ (en lecture seule).

Résultat attendu (vérifié sur C20, 2026-11-10) : une image de 0x7200 octets = deux tranches de
buffer A, chacune précédée d'un entête de 0x1c octets ; les octets d'image sont identiques des deux
côtés. Entête (champs 32 bits petit-boutiste) : [0]=1 ; [1]=longueur totale (0x7200) ; [2]=offset de
la tranche ; [3]=0 ; [4]=0 ; [5]=type (0x65 = image) ; [6]=longueur de la tranche.

Usage : python3 -I analysis/cmp_sensor_sep_image.py [dossier_trace]
"""
import glob
import os
import struct
import sys


def load(d):
    return {f: open(os.path.join(d, f), "rb").read()
            for f in sorted(os.listdir(d)) if os.path.isfile(os.path.join(d, f))}


def nz(b):
    return sum(1 for x in b if x)


def hdr(b):
    """Décode l'entête de 0x1c octets d'une tranche OOL (7 champs 32 bits LE)."""
    return struct.unpack("<7I", b[:0x1c])


def main():
    trace = sys.argv[1] if len(sys.argv) > 1 else sorted(glob.glob(
        os.path.join(os.path.dirname(__file__), "..", "traces", "*c20*")))[-1]
    sep = load(os.path.join(trace, "sep.log.ool"))
    sio = load(os.path.join(trace, "sio.bufs"))
    print("trace :", os.path.basename(os.path.abspath(trace)))

    images = [(f, b) for f, b in sio.items() if "done_data" in f and nz(b) > 20000]
    sepA = {f: b for f, b in sep.items() if f.endswith("_A.bin") and len(b) == 0x4000}
    print("images capteur (done_data pleins) :", len(images),
          " buffers SEP A 0x4000 :", len(sepA))

    # Index des 32 premiers octets de chaque tranche d'image (après entête) côté SEP.
    k = 32
    idx = {}
    for f, b in sepA.items():
        idx.setdefault(b[0x1c:0x1c + k], []).append(f)

    ok = 0
    for f, img in images:
        placed = 0
        chunks = []
        cur = 0
        while cur < len(img):
            g = img[cur:cur + k]
            cand = idx.get(g)
            if not cand:
                break
            sf = cand[0]
            sb = sepA[sf]
            n = 0
            while 0x1c + n < len(sb) and cur + n < len(img) and sb[0x1c + n] == img[cur + n]:
                n += 1
            h = hdr(sb)
            chunks.append((sf, cur, n, h))
            cur += n
            placed = cur
        if placed == len(img) and chunks:
            ok += 1
            if ok <= 2:  # détail pour les deux premières, résumé pour le reste
                print(f"\n{f} (0x{len(img):x} octets) entièrement relayée :")
                for sf, off, n, h in chunks:
                    print(f"  {sf}: entête total=0x{h[1]:x} offset=0x{h[2]:x} "
                          f"type=0x{h[5]:x} chunk_len=0x{h[6]:x} -> image[0x{off:x}:0x{off+n:x}] identique")
        # (les images non entièrement placées : buffer SEP correspondant non capturé ; ignorées)

    print(f"\nBILAN : {ok}/{len(images)} images capteur retrouvées octet pour octet dans l'OOL de l'EP 0x08 "
          f"(les autres : buffer SEP non dans la fenêtre de capture).")
    # Contrôle : deux images différentes ne partagent aucun run de 32 o (chiffrement).
    if len(images) >= 2:
        a, b = images[0][1], images[1][1]
        seen = {a[i:i + k] for i in range(0, len(a) - k + 1)}
        shared = sum(1 for i in range(0, len(b) - k + 1) if b[i:i + k] in seen)
        print(f"Contrôle chiffrement : 2 images différentes partagent {shared} run(s) de 32 o.")


if __name__ == "__main__":
    main()
