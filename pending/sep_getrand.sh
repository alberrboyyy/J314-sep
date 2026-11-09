#!/usr/bin/env bash
# BUT : savoir si le SEP répond à m1n1 seul (sans macOS). On envoie UNE question « donne-moi 4 octets
#   aléatoires » au SEP et on regarde s'il répond. Rien n'est démarré, rien n'est enregistré dans le SEP.
# ENDPOINTS TOUCHÉS : EP 0xFF (« ROM »), commande 16 (GETRAND), 1 message AP→SEP puis 1 réponse SEP→AP.
#   Pas de SKS (0x12), pas de xART (0x13), pas d'IMG4, pas de gigalocker.
# RISQUE : très faible. C'est exactement ce que m1n1 fait lui-même à chaque démarrage de Linux
#   (src/kboot.c : sep_get_random pour kaslr-seed et rng-seed ; code public m1n1/src/sep.c). Pire cas
#   plausible : le SEP ne répond pas (timeout 1 s) -> le script le dit, on redémarre le Mac si besoin.
#   Le Mac ne touche à aucune partition ni à la boot policy. Après ce script, le Mac reste en mode proxy.
# RÉSULTAT ATTENDU : « getrand OK, 4 octets : xx xx xx xx » (le SEP répond même sans macOS) OU
#   « getrand : 0 octet » (pas de réponse). Dans les deux cas, on note dans docs/journal.md.
# PRÉPARÉ PAR : Claude (Sonnet 5.5), 2026-11-09 — à relire puis lancer par Albert.
set -euo pipefail
source "$(dirname "$0")/../tools/env.sh"
require_mac
[ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUT="$TRACES_DIR/${STAMP}_sep_getrand"
mkdir -p "$OUT"
SYM=$(nm "$M1N1_DIR/build/m1n1.elf" | awk '$3=="sep_get_random"{print $1}')
[ -n "$SYM" ] || die "symbole sep_get_random introuvable dans m1n1.elf"
echo "symbole sep_get_random offset 0x$SYM" | tee "$OUT/meta.txt"

"$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log"
sleep 2
require_mac

export OUT M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient" SYMOFF="0x$SYM"
timeout 60 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "$OUT/getrand.log"
import os, sys
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import bootstrap_port
iface = UartInterface()
p = M1N1Proxy(iface, debug=False)
bootstrap_port(iface, p)
buf = p.malloc(16)
n = p.call(p.get_base() + int(os.environ["SYMOFF"], 16) - 0x10000, buf, 4)  # adresse vérifiée par tools/check_sep_sym.sh
data = iface.readmem(buf, 4) if n == 4 else b""
print("getrand OK, 4 octets : " + data.hex(" ") if n == 4 else f"getrand : {n} octet(s) (pas de réponse)")
p.free(buf)
PY
chmod a-w "$OUT"/*.log "$OUT"/meta.txt
echo "Terminé -> $OUT. Le Mac reste en mode proxy. Dis à Claude le résultat."
