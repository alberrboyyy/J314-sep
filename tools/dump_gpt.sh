#!/usr/bin/env bash
# tools/dump_gpt.sh — liste la table de partitions (GPT) du SSD interne, en LECTURE SEULE.
#
# POURQUOI : get_gigalocker de m1n1 ne scanne que le 1er conteneur APFS du disque ; après la récup
#   (macOS + Asahi), il y a plusieurs conteneurs. Ce script lit le GPT (nvme_read, lecture seule) et
#   affiche chaque partition (type GUID, LBA début/fin, nom) pour voir l'ordre des conteneurs APFS
#   et localiser celui de macOS (qui porte le volume xART / le gigalocker).
#
# LECTURE SEULE : uniquement nvme_init + nvme_read (op 0xf02). Aucune écriture, aucun SEP, aucun dd.
# Hypothèse : blocs logiques de 4096 o (SSD Apple interne). Si le parse échoue, essayer BS=512.
#
# Usage : ./tools/dump_gpt.sh          (SKIP_CHAINLOAD=1 pour réutiliser le proxy en place)
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_mac
[ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_gpt"; mkdir -p "$OUT"
echo "date: $STAMP" > "$OUT/meta.txt"; echo "op: nvme_read (lecture seule)" >> "$OUT/meta.txt"

if [ "${SKIP_CHAINLOAD:-0}" != 1 ]; then
  "$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log"
  sleep 2; require_mac
fi

export GPT_OUT="$OUT" M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient" BS="${BS:-4096}"
timeout 120 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "$OUT/gpt.log"
import os, sys, struct
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
BS = int(os.environ["BS"])
iface = UartInterface(); p = M1N1Proxy(iface, debug=False); bootstrap_port(iface, p)
u = ProxyUtils(p)
p.nvme_init()
buf = u.heap.memalign(0x4000, max(BS, 0x1000))

def rd(lba):
    iface.writemem(buf, b"\x00" * BS)
    p.nvme_read(1, lba, buf)
    return iface.readmem(buf, BS)

hdr = rd(1)  # l'en-tête GPT est toujours en LBA 1
if hdr[:8] != b"EFI PART":
    print(f"Pas de signature GPT en LBA1 (BS={BS}). tête={hdr[:16].hex()}. Essayer BS=512.", flush=True)
    sys.exit(2)
part_lba = struct.unpack("<Q", hdr[72:80])[0]
n_ent    = struct.unpack("<I", hdr[80:84])[0]
ent_sz   = struct.unpack("<I", hdr[84:88])[0]
print(f"GPT OK : {n_ent} entrées max de {ent_sz} o à partir du LBA {part_lba} (BS={BS})", flush=True)

def guid_str(b):
    d1,d2,d3 = struct.unpack("<IHH", b[:8]); d4 = b[8:16]
    return f"{d1:08x}-{d2:04x}-{d3:04x}-{d4[:2].hex()}-{d4[2:].hex()}"

APFS = "7c3457ef-0000-11aa-aa11-00306543ecac"
per_lba = BS // ent_sz
shown = 0
for i in range(n_ent):
    lba = part_lba + i // per_lba
    off = (i % per_lba) * ent_sz
    if off == 0:
        blk = rd(lba)
    e = blk[off:off+ent_sz]
    tguid = e[:16]
    if tguid == b"\x00"*16:
        continue
    first, last = struct.unpack("<QQ", e[32:48])
    name = e[56:128].decode("utf-16-le", "replace").rstrip("\x00")
    g = guid_str(tguid)
    tag = "  <-- APFS" if g == APFS else ""
    size_gb = (last - first + 1) * BS / 1e9
    print(f"  #{i:2d} {g}{tag}  LBA {first}..{last} (~{size_gb:.1f} Go)  « {name} »", flush=True)
    shown += 1
print(f"{shown} partitions. Les '<-- APFS' sont les conteneurs ; get_gigalocker ne lit QUE le 1er.", flush=True)
PY
[ -n "${OUT:-}" ] && chmod a-w "$OUT"/*.log 2>/dev/null || true
echo "Terminé (lecture seule) -> $OUT/gpt.log"
