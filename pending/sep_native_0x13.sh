#!/usr/bin/env bash
# =============================================================================
# sep_native_0x13.sh — ROUTE NATIVE, 1er pas : « et si Linux n'avait PAS d'état xART ? »
#
# ─────────────────────────────────────────────────────────────────────────────
# EN LANGAGE CLAIR (pour décider go / no-go — Albert)
#   CE QU'ON TESTE :
#     La voie « rejeu » (resservir à la puce le coffre de macOS) est MORTE (prouvé).
#     L'idée opposée : et si on dit à la puce « je n'ai AUCUN état xART » (comme un
#     tout 1er démarrage) ? Un SEP sans état doit en CRÉER un neuf. S'il le fait, c'est
#     exactement ce qui « arme » le capteur Touch ID — mais pour Linux, proprement,
#     sans copier macOS.
#
#   CE QUE CE SCRIPT FAIT (et NE fait PAS) :
#     - Il démarre le SEP (routine, déjà faite des dizaines de fois sans incident).
#     - À chaque fois que la puce réclame un locker, il répond « ABSENT » (forme exacte reprise
#       du kext macOS : un FETCH vide, pas un code d'erreur — cf. détail TECHNIQUE plus bas).
#     - Il REGARDE ce que la puce fait alors (essaie-t-elle de sceller du neuf =
#       demande un « SAVE » ? annonce-t-elle le capteur « sbio » ?).
#     - Il N'ÉCRIT RIEN de permanent : si la puce demande un SAVE, il S'ARRÊTE SANS
#       l'accepter. Donc AUCUN compteur de sécurité n'avance.  ← c'est ce qui rend
#       ce run RÉCUPÉRABLE/sûr, de la même classe que nos anciens runs « OBSERVE ».
#
#   CE QUI PEUT MAL TOURNER (honnête) :
#     - Le plus probable : « non concluant ». On ne sait PAS encore sous quelle forme
#       exacte la puce attend un « absent » (macOS ne l'a jamais fait → pas de capture).
#       Si notre forme est fausse, la puce se bloque ou diverge → on s'arrête proprement,
#       on n'a rien cassé, on a juste « gâché » un démarrage (power-cycle).
#     - Brick : faible mais NON nul (comme toute manip du SEP ; through-SEP = quasi
#       toujours réparable par DFU, mais pas prouvé 100 % sûr). Filet : backup faite + DFU.
#     - macOS : aucun SAVE acquitté ici → on ne touche pas au compteur partagé → macOS
#       ne devrait pas bouger. (Le run d'ÉCRITURE viendra APRÈS, séparément.)
#
#   CE QUE ÇA N'EST PAS : ce n'est PAS le rejeu (on ne resert aucun coffre). C'est
#     l'inverse : on prétend n'avoir rien, pour voir la puce repartir de zéro.
#
#   APRÈS : selon ce qu'on voit, j'écris le run d'ÉCRITURE (PERSIST) qui, lui,
#     acceptera le SAVE (= ta vraie porte, avec DFU en filet).
# ─────────────────────────────────────────────────────────────────────────────
#
# TECHNIQUE (résumé)
#   Réutilise le scaffold ÉPROUVÉ (boot SEPOS, bootstrap CNTL EP0, tampons A/B) — notre
#   code, pas du rejeu. Réponses 0x13 tirées de nos modules VU (driver/sepreplay/xart*).
#   Politique NATIVE (docs/handler_0x13.md) :
#     - 0x0e fw-boot        -> ack (A vide, DATA=0x100)                           [VU]
#     - 0x13 UUID d'OS      -> écrit un UUID Linux en A, ack DATA=0               [VU format / UUID Linux = choix]
#     - 0x00 FETCH maître   -> ABSENT = TYPE=0x00, longueur 0x11 (préfixe seul), A=0x11 zéros  [kext]
#     - 0x05 FETCH locker   -> ABSENT = TYPE=0x00, longueur 0, A vide                          [kext]
#     - 0x07 absent (SEP)   -> ack DATA=0                                        [VU]
#     - 0x1d annonce EP     -> ack TYPE=0x16 DATA=(DATA&0xffffff00)              [VU]
#     - 0x01/0x06 SAVE      -> OBSERVE : STOP sans acquitter (aucune écriture)    [ta porte = un run séparé]
#   Forme d'« ABSENT » (ABSENT_FORM, défaut `kext`) : VU dans le kext AppleSEPXART::_handle_sep_driven_msg
#   (désassemblage 2026-11-21) — quand macOS NE TROUVE PAS un enregistrement, il NE renvoie PAS d'erreur :
#   il répond un FETCH NORMAL (TYPE=0x00) de longueur 0x11 pour un MAÎTRE (le préfixe seul, 0 charge) ou de
#   longueur 0 pour un GIGALOCKER, sélecteur ré-émis. (Recon n°1 avait essayé 0x07 -> faux -> SEP calé.)
#   Variantes de secours : ABSENT_FORM=0x07 (ancien essai) | empty (TYPE=0x00 longueur 0 partout).
#
# RED LINES respectées : aucune op disque, pas de dd/nvram/sudo/partition. Le seul write
#   SEP est le boot (IMG4 = firmware propre à la machine, déjà éprouvé, lancé par Albert).
#   AUCUN SAVE acquitté dans ce script (OBSERVE pur). m1n1 : lu, jamais modifié/poussé.
#
# USAGE
#   SELFTEST=1 ./pending/sep_native_0x13.sh      # hors-ligne : montre la politique, ne touche pas le Mac
#   ./tools/catch_proxy.sh                       # D'ABORD (Claude) : attrape le Mac en proxy (tu power-cycles)
#   ./pending/sep_native_0x13.sh                 # PUIS run réel RECON (Albert lance) : boot + absent + observe
#   ABSENT_FORM=empty ./pending/sep_native_0x13.sh   # variante de la forme « absent »
#   LINUX_OS_UUID=<32 hexa> ./pending/sep_native_0x13.sh  # UUID d'OS renvoyé à l'op 0x13
#
# PRÉPARÉ PAR : Claude (Opus 4.8), 2026-11-21 — à relire (langage clair ci-dessus) et lancer par Albert.
#   Écriture PERSIST (acquittement du SAVE) = PAS dans ce script : run séparé, après ce recon.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/../tools/env.sh"

export SELFTEST="${SELFTEST:-0}"
export ABSENT_FORM="${ABSENT_FORM:-kext}"       # kext (défaut, fidèle au désassemblage) | 0x07 | empty
export LINUX_OS_UUID="${LINUX_OS_UUID:-4c494e55580000000000000000000000}"  # "LINUX"+0 (choix ; voir header)
# UUID d'OS (op 0x13). VU kext : si macOS n'a pas d'UUID -> réponse TYPE=0x02 (rien en A). fixed = on sert
# LINUX_OS_UUID (TYPE=0x00) ; none = on dit « pas d'UUID d'OS » (TYPE=0x02, fidèle au cas Linux sans apfs-preboot-uuid).
export OS_UUID_MODE="${OS_UUID_MODE:-fixed}"    # fixed (défaut : 1 seule variable changée vs recon n°1) | none
export M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"

if [ "$SELFTEST" != 1 ]; then
  [ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
  STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_native_0x13"; mkdir -p "$OUT"; export OUT
  # Le Mac doit DÉJÀ être en proxy : lancer ./tools/catch_proxy.sh AVANT (Claude le fait + power-cycle).
  require_mac
fi

timeout 300 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "${OUT:-/tmp}/native_0x13.log"
import os, sys, time, struct
SELFTEST = os.environ["SELFTEST"] == "1"
ABSENT_FORM = os.environ.get("ABSENT_FORM", "kext")
OS_UUID_MODE = os.environ.get("OS_UUID_MODE", "fixed")
LINUX_OS_UUID = bytes.fromhex(os.environ["LINUX_OS_UUID"])

# ops 0x13 (VU, docs/gigalocker.md / driver/sepreplay/xart.py)
OP_FWBOOT, OP_OSUUID, OP_FETCH_MASTER, OP_FETCH_GL = 0x0e, 0x13, 0x00, 0x05
OP_ABSENT, OP_ANNOUNCE, OP_SAVE_XART, OP_SAVE_LOCKER = 0x07, 0x1d, 0x01, 0x06
RESP_DONE, RESP_ANNOUNCE = 0x00, 0x16
ACK_MASK = 0xFFFFFF00
OPNAME = {OP_FWBOOT:"fw-boot", OP_OSUUID:"os-uuid", OP_FETCH_MASTER:"FETCH-maître",
          OP_FETCH_GL:"FETCH-locker", OP_ABSENT:"absent(SEP)", OP_ANNOUNCE:"annonce-EP",
          OP_SAVE_XART:"SAVE-xART", OP_SAVE_LOCKER:"SAVE-locker"}

if SELFTEST:
    print("--- SELFTEST (hors-ligne, le Mac n'est pas touché) ---", flush=True)
    print("Politique NATIVE qui serait appliquée à chaque requête du SEP sur 0x13 :", flush=True)
    print("  fw-boot(0x0e)      -> ack (A vide, DATA=0x100)", flush=True)
    if OS_UUID_MODE == "none":
        print("  os-uuid(0x13)      -> 'pas d'UUID d'OS' (TYPE=0x02, kext) [OS_UUID_MODE=none]", flush=True)
    else:
        print(f"  os-uuid(0x13)      -> écrit UUID d'OS Linux {LINUX_OS_UUID.hex()} en A, ack TYPE=0x00 [OS_UUID_MODE=fixed]", flush=True)
    print(f"  FETCH maître(0x00) -> ABSENT (forme={ABSENT_FORM}) : TYPE=0x00 longueur 0x11 (préfixe), A=0x11 zéros", flush=True)
    print(f"  FETCH locker(0x05) -> ABSENT (forme={ABSENT_FORM}) : TYPE=0x00 longueur 0, A vide", flush=True)
    print("  absent du SEP(0x07)-> ack DATA=0", flush=True)
    print("  annonce EP(0x1d)   -> ack TYPE=0x16 DATA=(DATA&0xffffff00)", flush=True)
    print("  SAVE(0x01/0x06)    -> STOP sans acquitter (OBSERVE : AUCUNE écriture, compteur NON avancé)", flush=True)
    assert ABSENT_FORM in ("kext", "0x07", "empty"), "ABSENT_FORM doit être kext | 0x07 | empty"
    assert OS_UUID_MODE in ("fixed", "none"), "OS_UUID_MODE doit être fixed | none"
    assert len(LINUX_OS_UUID) == 16, "LINUX_OS_UUID doit faire 16 octets (32 hexa)"
    print("SELFTEST OK (rien envoyé au SEP).", flush=True)
    sys.exit(0)

# ----------------------------- RUN RÉEL : scaffold éprouvé -----------------------------
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
from m1n1.hw.sep import SEP, SEPMessage
from m1n1.trace.asc import ASCRegs
from collections import defaultdict, deque

iface = UartInterface(); p = M1N1Proxy(iface, debug=False); bootstrap_port(iface, p)
u = ProxyUtils(p)

sep = SEP.__new__(SEP)
sep.i, sep.p, sep.u = iface, p, u
sep.sep_base = u.adt["/arm-io/sep"].get_reg(0)[0]
sep.dart_base = u.adt["/arm-io/dart-sep"].get_reg(0)[0]
sep.asc = ASCRegs(u, sep.sep_base)
sep.dart_handle = p.request(p.P_DART_INIT, sep.dart_base, 0, 0, 2)
sep.epnum2name, sep.epname2num, sep.msgs = {}, {}, defaultdict(deque)

CNTL_EP = 0
cntl_acks, cntl_tag = set(), [0]

def pump_ep0():
    sep._try_recv_msgs()
    while sep.msgs[CNTL_EP]:
        m = sep.msgs[CNTL_EP].popleft()
        if m.TYPE == 0x01:   cntl_acks.add(m.TAG)
        elif m.TYPE == 0x11: sep.send_msg(SEPMessage(EP=0, TAG=m.TAG, TYPE=0x12))   # NAP -> NAP_OK

def cntl_send(typ, data, param, label, timeout_s=5):
    cntl_tag[0] = cntl_tag[0] % 8 + 1; tag = cntl_tag[0]
    sep.send_msg(SEPMessage(EP=0, TAG=tag, TYPE=typ, PARAM=param, DATA=data))
    t = time.time()
    while time.time() - t < timeout_s:
        pump_ep0()
        if tag in cntl_acks: cntl_acks.discard(tag); return True
        time.sleep(0.01)
    return False

def next_sep_13(timeout_s=10):
    t = time.time()
    while time.time() - t < timeout_s:
        pump_ep0()
        if sep.msgs[0x13]: return sep.msgs[0x13].popleft()
        time.sleep(0.01)
    return None

# --- DART write (pour écrire l'UUID d'OS dans A) : traduction IOVA->PA + writemem ---
DART_TCR, DART_TTBR, DART_PAGE = 0x100, 0x200, 0x4000
TCR_TRANSLATE_ENABLE, TCR_BYPASS_DART = 1 << 7, 1 << 8
TTBR_VALID, TTBR_ADDR_MASK = 1 << 31, (1 << 31) - 1
PTE_OFFSET = {"dart,t8020": (14, 39), "dart,t6000": (10, 39)}
ram_lo = u.adt["/chosen"].dram_base; ram_hi = ram_lo + u.adt["/chosen"].dram_size
dart_node = u.adt["/arm-io/dart-sep"]; dart_base = dart_node.get_reg(0)[0]
pte_lo, pte_hi = PTE_OFFSET[dart_node.compatible[0]]; pte_mask = (1 << (pte_hi - pte_lo + 1)) - 1

def _check(pa, size):
    if not (ram_lo <= pa and pa + size <= ram_hi): raise RuntimeError("PA hors RAM")
def _pte(table_pa, idx):
    pa = table_pa + 8*idx; _check(pa, 8); return struct.unpack("<Q", iface.readmem(pa, 8))[0]
def translate_page(sid, iova):
    tcr = p.read32(dart_base + DART_TCR + 4*sid)
    if tcr & TCR_BYPASS_DART or not tcr & TCR_TRANSLATE_ENABLE: return None
    if (iova >> 36) >= 4: return None
    ttbr = p.read32(dart_base + DART_TTBR + 16*sid + 4*(iova >> 36))
    if not ttbr & TTBR_VALID: return None
    l1 = _pte((ttbr & TTBR_ADDR_MASK) << 12, (iova >> 25) & 0x7FF)
    if not l1 & 1: return None
    l2 = _pte(((l1 >> pte_lo) & pte_mask) << 14, (iova >> 14) & 0x7FF)
    if not l2 & 1: return None
    return ((l2 >> pte_lo) & pte_mask) << 14
def find_sid(iova):
    for sid in range(16):
        try:
            if translate_page(sid, iova & ~(DART_PAGE-1)) is not None: return sid
        except RuntimeError: continue
    raise RuntimeError("IOVA non mappée")
def dart_write(sid, iova, data):
    cur, end, off = iova, iova + len(data), 0
    while cur < end:
        page = cur & ~(DART_PAGE-1); n = min(end, page+DART_PAGE) - cur
        pa = translate_page(sid, page)
        if pa is None: raise RuntimeError("page non mappée (écriture refusée)")
        pa += cur - page; _check(pa, n); iface.writemem(pa, data[off:off+n]); off += n; cur += n

print("démarrage du SEP par m1n1 (séquence publique, routine)...", flush=True)
sep.boot(); print("BOOT OK", flush=True)

t0 = time.time()
while time.time() - t0 < 8:
    pump_ep0()
    if 0x13 in sep.epnum2name: break
    time.sleep(0.02)
if 0x13 not in sep.epnum2name:
    print(f"ERREUR: EP 0x13 (xarm) non annoncé. Endpoints={sep.epnum2name}. Abandon.", flush=True); sys.exit(2)
print("xarm (0x13) annoncé. Endpoints : "
      + ", ".join(f"0x{n:02x}:{nm}" for n, nm in sorted(sep.epnum2name.items())), flush=True)

if not cntl_send(0x14, 0, 0x00, "SECMODE"):
    print("ERREUR: pas d'ack SECMODE. Abandon.", flush=True); sys.exit(3)
SIZE, IOVA_A, IOVA_B = 0x8000, 0x2c000, 0x38000
phys_A = u.heap.memalign(0x4000, SIZE); phys_B = u.heap.memalign(0x4000, SIZE)
iface.writemem(phys_A, b"\x00"*SIZE); iface.writemem(phys_B, b"\x00"*SIZE)
p.dart_map(sep.dart_handle, IOVA_A, phys_A, SIZE); p.dart_map(sep.dart_handle, IOVA_B, phys_B, SIZE)
for label, typ, data in [("A taille",0x04,SIZE),("A adresse",0x02,IOVA_A>>12),
                         ("B taille",0x05,SIZE),("B adresse",0x03,IOVA_B>>12)]:
    if not cntl_send(typ, data, 0x13, label):
        print(f"ERREUR: pas d'ack CNTL {label}. Abandon.", flush=True); sys.exit(3)
sid_A = find_sid(IOVA_A)
print(f"tampons prêts (A sid={sid_A}). On répond désormais ABSENT aux FETCH et on OBSERVE.", flush=True)

def write_A_uuid(uuid16):
    iface.writemem(phys_A, b"\x00"*SIZE); dart_write(sid_A, IOVA_A, uuid16)

def respond_absent(m):
    """Répond « introuvable » à un FETCH. Défaut `kext` = fidèle au désassemblage
    AppleSEPXART::_handle_sep_driven_msg : réponse FETCH NORMALE (TYPE=0x00), longueur 0x11 pour un
    maître (préfixe seul) / 0 pour un gigalocker, sélecteur (DATA[1]) ré-émis. A = préfixe/zéros."""
    sel = (m.DATA >> 8) & 0xFF
    if ABSENT_FORM == "0x07":                          # ancien essai (recon n°1 : a fait caler le SEP)
        write_A_uuid(b""); sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=OP_ABSENT, PARAM=0x00, DATA=0x00000000))
    elif ABSENT_FORM == "empty":                       # TYPE=0x00 longueur 0 partout
        write_A_uuid(b""); sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=RESP_DONE, PARAM=0x00, DATA=sel << 8))
    else:                                              # kext (défaut)
        if m.TYPE == OP_FETCH_MASTER:
            write_A_uuid(b"\x00" * 0x11)               # 0x11 octets de préfixe (zéros) dans A
            sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=RESP_DONE, PARAM=0x11, DATA=sel << 8))
        else:                                          # OP_FETCH_GL
            write_A_uuid(b"")
            sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=RESP_DONE, PARAM=0x00, DATA=sel << 8))

# ------------------------------- boucle RECON (OBSERVE pur) -------------------------------
counts = defaultdict(int); last = time.time(); IDLE = 20
print(f"=== RECON NATIF : absent sur FETCH, STOP sans acquitter sur SAVE (idle {IDLE}s) ===", flush=True)
while time.time() - last < IDLE:
    m = next_sep_13(timeout_s=2)
    if m is None: continue
    last = time.time(); op = m.TYPE; counts[op] += 1
    name = OPNAME.get(op, f"op_0x{op:02x}")
    if op == OP_FWBOOT:
        write_A_uuid(b""); sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=RESP_DONE, PARAM=0x00, DATA=0x00000100))
        print(f"  SEP> {name} TAG=0x{m.TAG:02x} -> ack", flush=True)
    elif op == OP_OSUUID:
        if OS_UUID_MODE == "none":   # kext : pas d'UUID d'OS -> TYPE=0x02, rien écrit en A
            sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=0x02, PARAM=0x00, DATA=0x00000000))
            print(f"  SEP> {name} TAG=0x{m.TAG:02x} -> 'pas d'UUID d'OS' (TYPE=0x02)", flush=True)
        else:                        # fixed : UUID Linux en A, TYPE=0x00
            write_A_uuid(LINUX_OS_UUID)
            sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=RESP_DONE, PARAM=0x00, DATA=0x00000000))
            print(f"  SEP> {name} TAG=0x{m.TAG:02x} -> servi UUID Linux {LINUX_OS_UUID.hex()}", flush=True)
    elif op in (OP_FETCH_MASTER, OP_FETCH_GL):
        respond_absent(m)
        print(f"  SEP> {name} TAG=0x{m.TAG:02x} DATA=0x{m.DATA:08x} -> ABSENT ({ABSENT_FORM})", flush=True)
    elif op == OP_ABSENT:
        sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=RESP_DONE, PARAM=0x00, DATA=0x00000000))
        print(f"  SEP> {name} TAG=0x{m.TAG:02x} -> ack", flush=True)
    elif op == OP_ANNOUNCE:
        sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=RESP_ANNOUNCE, PARAM=0x00, DATA=m.DATA & ACK_MASK))
        ep = "".join(chr((m.DATA >> (i*8)) & 0xff) for i in (2,1,0))
        print(f"  SEP> {name} TAG=0x{m.TAG:02x} ('{ep}') -> ack 0x16", flush=True)
    elif op in (OP_SAVE_XART, OP_SAVE_LOCKER):
        print(f"  SEP> {name} TAG=0x{m.TAG:02x} : la puce VEUT SCELLER DU FRAIS (SAVE).", flush=True)
        print(f"      >>> C'EST LE SIGNAL ENCOURAGEANT (absent a marché). On S'ARRÊTE SANS acquitter :", flush=True)
        print(f"          OBSERVE pur, aucun compteur avancé. Le run d'ÉCRITURE (PERSIST) viendra après.", flush=True)
        break
    else:
        print(f"  SEP> op INCONNUE 0x{op:02x} TAG=0x{m.TAG:02x} DATA=0x{m.DATA:08x} -> STOP (fail-closed).", flush=True)
        break

print("--- bilan recon : " + ", ".join(f"{OPNAME.get(o,hex(o))}×{c}" for o, c in sorted(counts.items())), flush=True)
print("endpoints finaux : " + ", ".join(f"0x{n:02x}:{nm}" for n, nm in sorted(sep.epnum2name.items())), flush=True)
sbio = [nm for nm in sep.epnum2name.values() if nm in ("sbio", "sbi")]
print(f">>> sbio annoncé ? {'OUI' if sbio else 'non'}. (annoncé ≠ fonctionnel ; prochaine étape = PERSIST puis sonde.)", flush=True)
PY
