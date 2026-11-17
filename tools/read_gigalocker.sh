#!/usr/bin/env bash
# tools/read_gigalocker.sh — LIT le coffre xART (gigalocker) sur le DISQUE, en LECTURE SEULE.
#
# POURQUOI : le « coffre » que le SEP se fait rendre au boot (ses lockers xART) est stocké côté AP
#   dans un fichier sur le volume APFS de rôle xART (`/System/Volumes/xarts/<UUID>.gl`). m1n1 sait
#   déjà le lire sans macOS : `ProxyUtils.get_gigalocker()` scanne le GPT, trouve le volume xART
#   (VOL_ROLE_XART=0x100), suit le fichier gigalocker et renvoie son contenu brut. Tout est `pread`
#   (lecture), aucune écriture (vérifié dans m1n1/rust/src/apfs.rs : que des pread, 0 pwrite).
#   But : obtenir un coffre qui COLLE à la puce actuelle (lu en direct sur l'install 27.2.1), sans
#   réinstaller de macOS traçable, pour servir les FETCH gigalocker du SEP / tester « sbio vivant ».
#
# LECTURE SEULE — ne touche NI le SEP, NI macOS, NI la table de partitions : lit le disque via le
#   parseur APFS read-only de m1n1 (comme Asahi `get_gigalocker`). Aucune écriture disque, aucun
#   message SEP, aucun dd/partition/sudo. Le Mac est en proxy (aucun OS ne monte le disque).
#
# Usage : ./tools/read_gigalocker.sh [nom]        (défaut "gigalocker" -> traces/<horodatage>_gigalocker/)
#   SKIP_CHAINLOAD=1 : utiliser le m1n1 proxy déjà en place (ne pas rechainloader).
# Si le proxy ne connaît pas l'op (vieux m1n1) : échec propre (read_gigalocker renvoie vide/erreur) ->
#   rebuild m1n1 (tools/build_m1n1.sh) puis relancer.
set -euo pipefail
source "$(dirname "$0")/env.sh"

NAME="${1:-gigalocker}"
require_mac
[ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$TRACES_DIR/${STAMP}_${NAME}"
mkdir -p "$OUT"

{
  echo "date: $STAMP"
  echo "name: $NAME"
  echo "m1n1_commit: $(git -C "$M1N1_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
  echo "proxy_port: $M1N1DEVICE"
  echo "chainload: $([ "${SKIP_CHAINLOAD:-0}" = 1 ] && echo non || echo oui)"
  echo "op: ProxyUtils.get_gigalocker (lecture seule, APFS role xART)"
} > "$OUT/meta.txt"

if [ "${SKIP_CHAINLOAD:-0}" != 1 ]; then
  "$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log"
  sleep 2
  require_mac
fi

export GL_OUT="$OUT" M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
timeout 180 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "$OUT/read.log"
import os, sys, hashlib
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
out = os.environ["GL_OUT"]
iface = UartInterface()
p = M1N1Proxy(iface, debug=False)
bootstrap_port(iface, p)
u = ProxyUtils(p)

print("lecture du gigalocker (APFS role xART, lecture seule)...", flush=True)
try:
    data = u.get_gigalocker()
except Exception as e:
    print(f"ERREUR get_gigalocker : {e}", flush=True)
    print("Si c'est 'unknown request'/op non supportée : le m1n1 en place n'a pas l'op 0x1400 "
          "-> rebuild (tools/build_m1n1.sh) et relancer.", flush=True)
    sys.exit(2)

if not data:
    print("Aucune donnée renvoyée (volume xART introuvable, ou fichier gigalocker absent).", flush=True)
    sys.exit(3)

with open(out + "/gigalocker.bin", "wb") as f:
    f.write(data)
sha = hashlib.sha256(data).hexdigest()
nz = sum(1 for b in data if b)
print(f"gigalocker lu : {len(data)} octets ({len(data):#x}), non nuls {nz}, sha256 {sha}", flush=True)
print(f"256 premiers octets : {data[:256].hex()}", flush=True)
# repères de structure (lockers : UUID à +0x01, longueur, CRC — cf. doc Asahi / public_linux_state §B)
print(f"tête (0..0x40) : {data[:0x40].hex()}", flush=True)
PY

# Dump lecture seule (policy traces/ en lecture seule après capture).
if [ -n "${OUT:-}" ]; then chmod a-w "$OUT"/*.log "$OUT"/*.bin 2>/dev/null || true; fi
echo "Terminé (lecture seule). Coffre -> $OUT/gigalocker.bin"
