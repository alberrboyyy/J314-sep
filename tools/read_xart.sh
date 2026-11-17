#!/usr/bin/env bash
# tools/read_xart.sh — lit le CONTENU du volume APFS de rôle xART (le coffre) en LECTURE SEULE :
#   liste les fichiers de sa racine et dump chaque fichier (dont le/les gigalocker .gl) dans traces/.
#
# Pourquoi : get_gigalocker de m1n1 trouve le volume xART mais échoue à lire le fichier gigalocker
#   dessus (probablement nom/structure du .gl différents sur macOS 27.2.1). On parcourt nous-mêmes le
#   système de fichiers (portage lecture seule de m1n1/rust/src/apfs.rs : omap -> APSB xART -> fs-tree
#   -> dir records racine -> extents) pour voir CE QU'IL Y A et récupérer le coffre qui colle à la puce.
#
# LECTURE SEULE : nvme_init + nvme_read uniquement. Aucune écriture, aucun SEP.
# Hypothèses : block=LBA=4096 ; B-trees de niveau 0 (petit volume). Si un arbre est multi-niveaux,
#   le script le dit et s'arrête proprement (rien d'écrit).
#
# Usage : ./tools/read_xart.sh [LBA_conteneur]   (défaut 6 = iBootSystemContainer)
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_mac
STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_xart_read"; mkdir -p "$OUT"
echo "date: $STAMP" > "$OUT/meta.txt"; echo "op: nvme_read (lecture seule), parse APFS xART" >> "$OUT/meta.txt"
export XART_BASE="${1:-6}" XART_OUT="$OUT" M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
M1N1TIMEOUT="${M1N1TIMEOUT:-25}" timeout 180 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "$OUT/xart.log"
import os, sys, struct, hashlib
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
iface = UartInterface(); p = M1N1Proxy(iface, debug=False); bootstrap_port(iface, p)
u = ProxyUtils(p); p.nvme_init()
BS=4096; base=int(os.environ["XART_BASE"]); OUT=os.environ["XART_OUT"]
NXSB=0x4253584E; APSB=0x42535041; XART=0x100
TY_DREC=9; TY_EXTENT=8; SHIFT=60; ROOT_INO=2
buf=u.heap.memalign(0x4000,BS)
U16=lambda b,o: struct.unpack_from("<H",b,o)[0]
U32=lambda b,o: struct.unpack_from("<I",b,o)[0]
U64=lambda b,o: struct.unpack_from("<Q",b,o)[0]
def rd(lba):
    iface.writemem(buf,b"\x00"*BS); p.nvme_read(1,lba,buf); return iface.readmem(buf,BS)

def omap_lookup(node,key):   # B-tree omap FIXED_KV niveau 0 -> paddr
    fl=U16(node,32); lvl=U16(node,34); nk=U32(node,36)
    if lvl!=0 or not (fl&4): return None
    toc=U16(node,40)+56; ks=toc+U16(node,42); ve=len(node)-(40 if fl&1 else 0)
    for i in range(nk):
        k=U16(node,toc+i*4); v=U16(node,toc+i*4+2)
        if U64(node,k+ks)==key:
            vo=ve-v; return U64(node,vo+8)   # OmapVal.paddr@8
    return None

# 1. conteneur -> superblock le plus récent -> omap -> APSB de rôle xART
sb=rd(base)
if U32(sb,32)!=NXSB: print("pas un conteneur APFS"); sys.exit(2)
bx=U64(sb,16); best=sb
for i in range(min(U32(sb,104),64)):
    c=rd(base+U64(sb,112)+i)
    if U32(c,32)==NXSB and U64(c,16)>bx: best=c; bx=U64(c,16)
sb=best
cont_omap=rd(base+U64(sb,160)); cont_node=rd(base+U64(cont_omap,48))
xart_paddr=None
for i in range(100):
    fs=U64(sb,184+8*i)
    if not fs: continue
    pa=omap_lookup(cont_node,fs)
    if pa is None: continue
    asb=rd(base+pa)
    if U32(asb,32)==APSB and U16(asb,964)==XART:
        xart_paddr=pa; break
if xart_paddr is None: print("volume xART introuvable dans ce conteneur"); sys.exit(3)
asb=rd(base+xart_paddr)
print(f"volume xART : APSB @ block {xart_paddr:#x}, omap_oid={U64(asb,128):#x}, root_tree_oid={U64(asb,136):#x}", flush=True)

# 2. omap du volume -> noeud racine du système de fichiers
vol_omap=rd(base+U64(asb,128)); vol_node=rd(base+U64(vol_omap,48))
root_pa=omap_lookup(vol_node,U64(asb,136))
if root_pa is None: print("racine fs introuvable (omap volume multi-niveaux ?)"); sys.exit(4)
fsroot=rd(base+root_pa)
fl=U16(fsroot,32); lvl=U16(fsroot,34); nk=U32(fsroot,36)
print(f"fs-root : niveau={lvl} nkeys={nk} flags={fl:#x}", flush=True)
if lvl!=0: print("fs-tree multi-niveaux (non porté). STOP, rien écrit."); sys.exit(5)
toc=U16(fsroot,40)+56; ks=toc+U16(fsroot,42); ve=len(fsroot)-(40 if fl&1 else 0)

# 3. parcourir les entrées : lister les dir-records (noms) et mémoriser les extents par inode
drecs=[]; extents={}
for i in range(nk):
    ko=U16(fsroot,toc+i*8); kl=U16(fsroot,toc+i*8+2); vo=U16(fsroot,toc+i*8+4); vl=U16(fsroot,toc+i*8+6)
    key=fsroot[ks+ko:ks+ko+kl]; val=fsroot[ve-vo:ve-vo+vl]
    if len(key)<8: continue
    oid_type=U64(key,0); ino=oid_type & ((1<<SHIFT)-1); typ=oid_type>>SHIFT
    if typ==TY_DREC and ino==ROOT_INO and len(key)>=12:
        nlen=(U32(key,8)&0x3ff); name=key[12:12+max(nlen-1,0)].decode("utf-8","replace")
        file_id=U64(val,0) if len(val)>=8 else 0
        drecs.append((name,file_id))
    elif typ==TY_EXTENT and len(val)>=16:
        length=U64(val,0)&0x00ffffffffffffff; phys=U64(val,8)
        extents.setdefault(ino,[]).append((U64(key,8),length,phys))  # (logical_addr, len, phys_block)

print(f"\nFichiers à la racine du volume xART ({len(drecs)}):", flush=True)
for name,fid in drecs:
    exts=extents.get(fid,[])
    tot=sum(l for _,l,_ in exts)
    print(f"  '{name}'  inode={fid:#x}  extents={len(exts)}  taille≈{tot} o ({tot:#x})", flush=True)

# 4. dump chaque fichier qui a des extents (dont le gigalocker .gl)
for name,fid in drecs:
    exts=sorted(extents.get(fid,[]))
    if not exts: continue
    data=bytearray()
    ok=True
    for logical,length,phys in exts:
        n=length; cur=phys; got=bytearray()
        while n>0:
            blk=rd(base+cur); take=min(BS,n); got+=blk[:take]; n-=take; cur+=1
            if n>0 and cur> phys+ (length//BS)+2: ok=False; break
        data+=got
    safe="".join(ch if ch.isalnum() or ch in "._-" else "_" for ch in name) or "file"
    fn=os.path.join(OUT,f"xart__{safe}.bin")
    with open(fn,"wb") as f: f.write(data)
    sha=hashlib.sha256(bytes(data)).hexdigest()
    nz=sum(1 for x in data if x)
    print(f"\n  dump '{name}' -> {os.path.basename(fn)} : {len(data)} o, non nuls {nz}, sha256 {sha[:16]}", flush=True)
    print(f"    tête(0x40) : {bytes(data[:0x40]).hex()}", flush=True)
PY
[ -n "${OUT:-}" ] && chmod a-w "$OUT"/*.log "$OUT"/*.bin 2>/dev/null || true
echo "Terminé (lecture seule) -> $OUT/"
