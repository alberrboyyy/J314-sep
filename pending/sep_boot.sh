#!/usr/bin/env bash
# BUT : démarrer le logiciel du SEP (SEPOS) depuis m1n1, SANS macOS, avec le code PUBLIC de m1n1
#   (proxyclient/m1n1/hw/sep.py, classe SEP.boot()), puis ÉCOUTER 30 s ce que le SEP annonce (EP 0xFD :
#   liste de ses services, dont « sbio » si la biométrie est là). On utilise le firmware du SEP déjà
#   présent dans la mémoire du Mac (SEPFW, préchargé par iBoot, visible dans le log de m1n1) : rien n'est
#   téléchargé, rien n'est déchiffré.
# ENDPOINTS TOUCHÉS : EP 0xFF (GET_STATUS, BOOT_TZ0, BOOT_IMG4) et EP 0xFE (SET_SHMEM) — envoi d'IMG4 inclus.
#   Pas de SKS (0x12), pas de xART (0x13), pas de gigalocker. Après le boot : écoute seulement.
# RISQUE : modéré-faible. Au pire le SEP ne démarre pas ou se bloque ; un redémarrage du Mac règle ça.
#   SEPOS démarré sans macOS n'a pas de stockage (xART/keybag) : il ne peut rien écrire sur ton disque.
#   Le seul inconnu : l'état secret du SEP après un démarrage « pas fait par macOS ». Redémarre sous macOS
#   ensuite pour vérifier que Touch ID et la session fonctionnent comme avant. Aucune partition, boot policy
#   ni NVRAM touchée. Le script s'arrête tout seul au bout de 150 s au pire.
# RÉSULTAT ATTENDU : « BOOT OK » puis une liste d'endpoints (nom -> numéro). Si « sbio » apparaît : le SEP
#   biométrique tourne sans macOS (très bonne nouvelle). Sinon : on sait que Linux devra fournir plus (SKS…).
# PRÉPARÉ PAR : Claude (Sonnet 5.5), 2026-11-09 — à relire puis lancer par Albert. Backup : Albert dit l'avoir.
set -euo pipefail
source "$(dirname "$0")/../tools/env.sh"
require_mac
[ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé"
STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_sep_boot"; mkdir -p "$OUT"
"$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" 2>&1 | tee "$OUT/chainload.log" >/dev/null
sleep 2; require_mac
export OUT M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
timeout 150 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "$OUT/boot.log"
import os, sys, time
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
from m1n1.hw.sep import SEP
iface = UartInterface(); p = M1N1Proxy(iface, debug=False); bootstrap_port(iface, p)
u = ProxyUtils(p)
# Le constructeur SEP() de m1n1 appelle dart_init avec l'ancienne signature (crash constaté le 2026-11-09 21:5x :
# mauvais type de DART). On le construit à la main avec la bonne : dart_init(base, 0, keep_pts=0, type=T6000=2).
from collections import defaultdict, deque
from m1n1.trace.asc import ASCRegs
sep = SEP.__new__(SEP)
sep.i, sep.p, sep.u = iface, p, u
sep.sep_base = u.adt["/arm-io/sep"].get_reg(0)[0]
sep.dart_base = u.adt["/arm-io/dart-sep"].get_reg(0)[0]
sep.asc = ASCRegs(u, sep.sep_base)
sep.dart_handle = p.request(p.P_DART_INIT, sep.dart_base, 0, 0, 2)
sep.epnum2name, sep.epname2num, sep.msgs = {}, {}, defaultdict(deque)
print(f"dart_handle={sep.dart_handle:#x}", flush=True)
print("boot SEP (public m1n1 sequence)...", flush=True)
sep.boot()
print("BOOT OK", flush=True)
t0 = time.time()
while time.time() - t0 < 30:
    sep._try_recv_msgs()
    time.sleep(0.05)
print("Endpoints annoncés :", flush=True)
for num, name in sorted(sep.epnum2name.items()):
    print(f"  0x{num:02x} {name}")
print("Messages restants par EP :", {hex(k): len(v) for k, v in sep.msgs.items() if len(v)})
PY
chmod a-w "$OUT"/*.log
echo "Terminé -> $OUT. Dis à Claude ce qui s'affiche (BOOT OK ? liste ?). Pour revenir à macOS : redémarre le Mac."
