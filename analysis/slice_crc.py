#!/usr/bin/env python3
"""Contrôle des tranches capteur dans les charges OOL 0x65 (AP -> SEP).

Hypothèse testée (lecture de AppleSandDollar::_checkImageCRC, source: kext, 2026-11-08) :
l'image capteur est découpée en N tranches de même taille ; chaque tranche porte sa propre
longueur en u32 LE à +3 et se termine par un CRC-16 LE calculé sur tout ce qui précède dans
la tranche. Le CRC est le CRC-16 standard « ARC » (polynôme réfléchi 0xA001, valeur initiale 0,
pas de XOR final) : la table du kext est identique à la table ARC (contrôlé le 2026-11-08).

Si la charge 0x65 vue sur le mailbox est une recopie octet pour octet de ce que le capteur envoie
sur le bus SPI, toutes les tranches doivent passer le contrôle.

  slice_crc.py [--slice 0x980] FICHIER.bin...      # p.ex. analysis/out/c8_payloads/*inA_65.bin
"""
import argparse
import struct
import sys


def crc16_arc(data):
    crc = 0
    for byte in data:
        crc ^= byte
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def check(buf, slice_len):
    out = []
    for k in range(len(buf) // slice_len):
        s = buf[k * slice_len:(k + 1) * slice_len]
        length = struct.unpack_from("<I", s, 3)[0]
        want = s[-2] | (s[-1] << 8)
        got = crc16_arc(s[:-2])
        out.append((k, s[0], s[1], s[2], length, want, got, length == slice_len and want == got))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--slice", type=lambda x: int(x, 0), default=0x980)
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    tot = ok = 0
    for f in a.files:
        with open(f, "rb") as fh:
            buf = fh.read()
        res = check(buf, a.slice)
        n_ok = sum(r[-1] for r in res)
        tot += len(res)
        ok += n_ok
        rest = len(buf) % a.slice
        print(f"{f}: {len(buf):#x} octets, {n_ok}/{len(res)} tranches OK" + (f", reste {rest:#x}" if rest else ""))
        for k, b0, b1, b2, length, want, got, good in res:
            if not good:
                print(f"  tranche {k}: {b0:02x} {b1:02x} {b2:02x} len={length:#x} crc lu={want:#06x} calculé={got:#06x}")
    print(f"total : {ok}/{tot} tranches OK")
    return 0 if ok == tot else 1


if __name__ == "__main__":
    sys.exit(main())
