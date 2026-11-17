#!/usr/bin/env bash
# tools/apfs_list_volumes.sh — liste les volumes APFS (oid, rôle, nom) de conteneurs donnés,
#   en LECTURE SEULE, pour localiser le volume de rôle xART (0x100) = là où vit le coffre/gigalocker.
#
# Portage Python (lecture seule) de la marche APFS de m1n1 (rust/src/apfs.rs) : NXSB -> checkpoint
#   le plus récent -> omap conteneur (B-tree) -> pour chaque fs_oid, résout l'APSB et lit son rôle.
#   Objectif : savoir si un volume de rôle xART existe, et dans quel conteneur (get_gigalocker ne
#   scanne QUE le conteneur 69646961 ; on vérifie tous les conteneurs APFS du disque).
#
# LECTURE SEULE : nvme_init + nvme_read uniquement. Aucune écriture, aucun SEP, aucun dd.
# Hypothèse : block APFS = LBA = 4096 o. Omap B-tree supposé de niveau 0 (petits conteneurs).
#
# Usage : ./tools/apfs_list_volumes.sh "LBA_part1 LBA_part2 ..."  (défaut : conteneurs APFS du GPT)
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_mac
export APFS_PARTS="${1:-6 128006 20725510 119516699 120827419}" M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
M1N1TIMEOUT="${M1N1TIMEOUT:-25}" timeout 180 "$M1N1_PYTHON" - <<'PY'
import os, sys, struct
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
iface = UartInterface(); p = M1N1Proxy(iface, debug=False); bootstrap_port(iface, p)
u = ProxyUtils(p); p.nvme_init()
BS = 4096
buf = u.heap.memalign(0x4000, BS)
NXSB_MAGIC = 0x4253584E  # 'NXSB'
APSB_MAGIC = 0x42535041  # 'APSB'
XART = 0x100
ROLE = {0:"(none)",1:"SYSTEM",2:"USER",4:"RECOVERY",8:"VM",0x10:"PREBOOT",0x20:"INSTALLER",
        0x40:"DATA",0x80:"BASEBAND",0x100:"xART / UPDATE",0x200:"HARDWARE",0x400:"BACKUP"}
BTINFO_SIZE = 40; BTN_HDR = 56; ROOT_FLAG = 1; FIXED_KV = 4  # BTreeNodePhys::FIXED_KV_SIZE

def u16(b,o): return struct.unpack_from("<H", b, o)[0]
def u32(b,o): return struct.unpack_from("<I", b, o)[0]
def u64(b,o): return struct.unpack_from("<Q", b, o)[0]

def rd(lba):
    iface.writemem(buf, b"\x00"*BS); p.nvme_read(1, lba, buf); return iface.readmem(buf, BS)

def lookup_omap(node, key):
    # node = bytes d'un B-tree node (4096). Cherche la clé oid=key, renvoie (size, paddr) de la valeur.
    flags = u16(node,32); level = u16(node,34); nkeys = u32(node,36)
    if level != 0: return ("LEVEL!=0", None)
    if not (flags & FIXED_KV): return ("NOT_FIXED_KV", None)
    ts_off = u16(node,40); ts_len = u16(node,42)
    toc_off = ts_off + BTN_HDR
    key_start = toc_off + ts_len
    val_end = len(node) - (BTINFO_SIZE if (flags & ROOT_FLAG) else 0)
    for i in range(nkeys):
        k = u16(node, toc_off + i*4); v = u16(node, toc_off + i*4 + 2)
        key_off = k + key_start
        oid = u64(node, key_off)        # OmapKey.oid @0
        if oid == key:
            val_off = val_end - v
            size = u32(node, val_off + 4) # OmapVal.size @4
            paddr = u64(node, val_off + 8)# OmapVal.paddr @8
            return (size, paddr)
    return (None, None)

for base in [int(x) for x in os.environ["APFS_PARTS"].split()]:
    print(f"\n=== conteneur @ LBA {base} ===", flush=True)
    sb = rd(base)
    if u32(sb,32) != NXSB_MAGIC:
        print("  pas un NXSB (pas un conteneur APFS ici)."); continue
    sb_xid = u64(sb,16)
    xp_blocks = u32(sb,104); xp_base = u64(sb,112)
    # checkpoint le plus récent
    best = sb; best_xid = sb_xid
    for i in range(min(xp_blocks, 64)):
        c = rd(base + xp_base + i)
        if u32(c,32) == NXSB_MAGIC and u64(c,16) > best_xid:
            best = c; best_xid = u64(c,16)
    sb = best
    omap_oid = u64(sb,160)
    cont_omap = rd(base + omap_oid)           # OmapPhys ; tree_oid @48
    tree_oid = u64(cont_omap,48)
    cont_node = rd(base + tree_oid)
    found_xart = False; nvol = 0
    for i in range(100):
        fs_id = u64(sb, 184 + 8*i)
        if fs_id == 0: continue
        size, paddr = lookup_omap(cont_node, fs_id)
        if paddr is None:
            if size in ("LEVEL!=0","NOT_FIXED_KV"):
                print(f"  omap conteneur non trivial ({size}) -> marche B-tree multi-niveaux non portée. STOP ce conteneur.")
                break
            continue
        asb = rd(base + paddr)
        if u32(asb,32) != APSB_MAGIC:
            continue
        role = u16(asb,964); nvol += 1
        # nom de volume : apfs_volname (ASCII) — on tente de l'extraire proprement vers la fin de l'APSB
        name = ""
        for noff in (0x2C0, 0x2B0, 0x300):
            s = asb[noff:noff+64].split(b"\x00")[0]
            if s and all(32 <= c < 127 for c in s):
                name = s.decode(); break
        star = "   <<< rôle xART (0x100) = COFFRE ICI" if role == XART else ""
        print(f"  volume oid={fs_id:#x} rôle={role:#x} [{ROLE.get(role,'?')}] nom='{name}'{star}", flush=True)
        if role == XART: found_xart = True
    print(f"  -> {nvol} volume(s)."+(" VOLUME xART TROUVÉ." if found_xart else " pas de volume xART ici."), flush=True)
PY
echo "Terminé (lecture seule)."
