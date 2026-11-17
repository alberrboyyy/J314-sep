#!/usr/bin/env python3
"""Parse le fichier coffre xART (gigalocker .gl) lu sur disque par tools/read_xart.sh.

Décode les lockers (slots de 0x9000) : type, UUID, longueur, CRC, charge. Voir docs/gigalocker.md.
Usage :
  python3 -I analysis/parse_gigalocker.py <coffre.gl.bin> [capture_dir ...]
Les capture_dir (optionnels) sont des dossiers de trace EP 0x13 : on y cherche chaque UUID (16 o)
dans les tampons OOL (sep.log.ool/*.bin) pour montrer la stabilité des UUID.
LECTURE SEULE de fichiers ; ne touche pas le matériel.
"""
import sys, struct, glob, os

SLOT = 0x9000
TYPE_NAME = {0x01: "USER-xART (maître)", 0x02: "SEP-xART (maître)",
             0x03: "gigalocker", 0x04: "gigalocker"}


def parse(path):
    data = open(path, "rb").read()
    lockers = []
    for k in range(len(data) // SLOT + 1):
        base = k * SLOT
        if base + 0x22 > len(data) or not any(data[base:base + SLOT]):
            continue
        typ = data[base + 0x01]
        uuid = data[base + 0x02:base + 0x12] if typ in (0x03, 0x04) else b""
        ln = struct.unpack_from("<I", data, base + 0x12)[0]
        crc = struct.unpack_from("<I", data, base + 0x16)[0]
        payload = data[base + 0x22:base + 0x22 + ln]
        lockers.append(dict(slot=k, type=typ, uuid=uuid, length=ln, crc=crc, payload=payload))
    return data, lockers


def main():
    if len(sys.argv) < 2:
        print(__doc__); sys.exit(1)
    path = sys.argv[1]
    capdirs = sys.argv[2:]
    data, lockers = parse(path)
    print(f"{path}: {len(data)} o ({len(data):#x}), {len(lockers)} lockers\n")
    bins = []
    for d in capdirs:
        bins += glob.glob(os.path.join(d, "sep.log.ool", "*.bin"))
    hdr = "slot type  UUID                               len     crc"
    if bins:
        hdr += f"     dans {len(capdirs)} capture(s)"
    print(hdr)
    for L in lockers:
        name = TYPE_NAME.get(L["type"], "?")
        uu = L["uuid"].hex() if L["uuid"] else "-" * 32
        line = f" {L['slot']:2d}  0x{L['type']:02x}  {uu}  {L['length']:#06x}  {L['crc']:#010x}"
        if bins and L["uuid"]:
            n = sum(1 for f in bins if L["uuid"] in open(f, "rb").read())
            line += f"  {n} hit(s)"
        line += f"   [{name}]"
        print(line)
    masters = [L for L in lockers if L["type"] in (0x01, 0x02)]
    gls = [L for L in lockers if L["type"] in (0x03, 0x04)]
    print(f"\n{len(masters)} maître(s), {len(gls)} gigalocker(s).")


if __name__ == "__main__":
    main()
