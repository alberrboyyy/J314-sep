#!/usr/bin/env bash
# tools/apfs_magic.sh — lit l'en-tête APFS (NXSB) de conteneurs donnés, en LECTURE SEULE.
# But : voir si le conteneur APFS se lit encore (magic NXSB) et sa VERSION de format
#   (incompatible_features) — pour savoir si le parseur public de m1n1 (mi-2026) est trop
#   ancien pour l'APFS de macOS 27.2.1 (cause probable que get_gigalocker ne trouve rien).
# LECTURE SEULE : nvme_init + nvme_read uniquement. Aucune écriture, aucun SEP.
# Usage : ./tools/apfs_magic.sh "LBA1 LBA2 ..."   (défaut : conteneurs du dump GPT)
set -euo pipefail
source "$(dirname "$0")/env.sh"
require_mac
export APFS_LBAS="${1:-6 128006 20725510 119516699 120827419}" M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
M1N1TIMEOUT="${M1N1TIMEOUT:-20}" timeout 90 "$M1N1_PYTHON" - <<'PY'
import os, sys, struct
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
iface = UartInterface(); p = M1N1Proxy(iface, debug=False); bootstrap_port(iface, p)
u = ProxyUtils(p); p.nvme_init()
BS = 4096
buf = u.heap.memalign(0x4000, BS)
def rd(lba):
    iface.writemem(buf, b"\x00"*BS); p.nvme_read(1, lba, buf); return iface.readmem(buf, BS)
for lba in [int(x) for x in os.environ["APFS_LBAS"].split()]:
    b = rd(lba)
    magic = b[0x20:0x24]
    if magic != b"NXSB":
        print(f"LBA {lba}: pas NXSB (magic={magic!r}, 1ers octets {b[:16].hex()})")
        continue
    block_size = struct.unpack("<I", b[0x24:0x28])[0]
    feat, ro, incompat = struct.unpack("<QQQ", b[0x30:0x48])
    print(f"LBA {lba}: NXSB  block_size={block_size}  features={feat:#x}  ro_compat={ro:#x}  "
          f"INCOMPAT={incompat:#x}  (incompat 1=v1 2=v2 ; bits plus hauts = format plus récent)")
PY
echo "Terminé (lecture seule)."
