#!/usr/bin/env bash
# =============================================================================
# sep_native_persist.sh — ROUTE NATIVE, run d'ÉCRITURE : laisser le SEP sceller un xART FRAIS pour Linux.
#
# ─────────────────────────────────────────────────────────────────────────────
# EN LANGAGE CLAIR (décision go / no-go — Albert)
#   SUITE DU RECON n°2 : en répondant « je n'ai pas de xART » (absent), le SEP a annoncé toute la pile
#   biométrique (sbio, skdl, sse, sks, scrd) PUIS a demandé à SCELLER un état frais (SAVE). On s'était
#   arrêté là sans écrire. CE script-ci FRANCHIT ce pas : il **acquitte le SAVE et STOCKE** le blob frais
#   sur CE PC, puis le **re-sert** si le SEP le redemande. But : voir si « sceller du frais » STABILISE le
#   SEP (il s'arrête de re-sauver, garde sbio armé) — au lieu de la boucle de re-SAVE qu'on avait en voie C.
#
#   CE QUI EST ÉCRIT (⚠️ la vraie porte) :
#     - Acquitter un SAVE fait **AVANCER le compteur anti-rejeu scellé** du SEP (matériel). C'est une
#       écriture irréversible au sens « on ne revient pas en arrière sur le compteur ».
#     - Récupération : through-SEP = **quasi toujours réparable par DFU** (voie C, 16/11…), **pas prouvé
#       sûr à 100 %** (cf. Stockholm/ inconnus). Backup + IPSW prêts. macOS sera désynchronisé — on s'en fiche
#       (il ne boote déjà plus ; et on a vu que ça n'empêche pas le SEP de tourner). Linux : aucun risque.
#     - Budget de SAVE **borné** (MAX_SAVES, défaut 48). Si le SEP enchaîne au-delà sans se stabiliser =
#       verdict « même mur que voie C » → on s'arrête.
#
#   CE QUE ÇA N'EST PAS : pas du rejeu. On ne sert JAMAIS un coffre macOS. On part VIDE, le SEP crée son
#     propre état, on le garde. « sbio armé » ≠ « Touch ID marche » (il faudra sbio+sks + un doigt ensuite).
#
#   OÙ EST STOCKÉ L'ÉTAT : sur CE PC (XART_STORE, défaut ./xart_store_linux/). C'est lui l'« AP ». Le
#     transfert vers le Linux du Mac (ALARM) par USB = étape FUTURE (quand le driver sera natif dans le noyau).
# ─────────────────────────────────────────────────────────────────────────────
#
# TECHNIQUE (politique native complète, docs/handler_0x13.md, gigalocker.md §Réponse…) :
#   - 0x0e fw-boot / 0x13 os-uuid / 0x1d annonce / 0x07 absent-SEP : ack VU (idem recon).
#   - 0x00 FETCH maître  : si en store -> SERVIR (A = 0x11 zéros + charge, longueur 0x11+len) ; sinon ABSENT (len 0x11).
#   - 0x05 FETCH locker  : UUID lu en B ; si en store -> servir ; sinon ABSENT (len 0).
#   - 0x01 SAVE maître   : lire B (longueur = PARAM|DATA0<<8), STOCKER par type (1 USER / 2 SEP), ACK (DATA&0xffffff00). ⚠️ écriture.
#   - 0x06 SAVE locker   : lire B, STOCKER (clé UUID = best-effort ; sinon dump brut indexé), ACK. ⚠️ écriture.
#   Le store est chargé au démarrage (maîtres) et ré-écrit à chaque SAVE -> persistance inter-boot.
#
# RED LINES : aucune op disque sur le Mac, pas de dd/nvram/sudo/partition. Le store est un fichier sur CE PC.
#   m1n1 : lu, jamais modifié/poussé. Le SEP-write (boot IMG4 + SAVE-ack) = lancé par Albert (ce script, pending/).
#
# USAGE
#   SELFTEST=1 ./pending/sep_native_persist.sh          # hors-ligne : montre la politique, ne touche pas le Mac
#   ./tools/catch_proxy.sh                              # D'ABORD (Claude) : attrape le Mac en proxy (tu power-cycles)
#   ./pending/sep_native_persist.sh                     # PUIS run RÉEL d'ÉCRITURE (Albert lance)
#   MAX_SAVES=48 | OS_UUID_MODE=fixed|none | XART_STORE=<dir> | IDLE=25
#
# PRÉPARÉ PAR : Claude (Opus 4.8), 2026-11-21 — en-tête clair ci-dessus ; à lancer par Albert, backup+DFU prêts.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/../tools/env.sh"

export SELFTEST="${SELFTEST:-0}"
export OS_UUID_MODE="${OS_UUID_MODE:-fixed}"
export LINUX_OS_UUID="${LINUX_OS_UUID:-4c494e55580000000000000000000000}"
export MAX_SAVES="${MAX_SAVES:-48}"
export IDLE="${IDLE:-25}"
export XART_STORE="${XART_STORE:-$REPO_ROOT/xart_store_linux}"
export M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
mkdir -p "$XART_STORE"

if [ "$SELFTEST" != 1 ]; then
  [ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
  STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_native_persist"; mkdir -p "$OUT"; export OUT
  # Le Mac doit DÉJÀ être en proxy : lancer ./tools/catch_proxy.sh AVANT (Claude le fait + power-cycle).
  require_mac
fi

timeout 300 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "${OUT:-/tmp}/native_persist.log"
import os, sys, time, struct, glob
SELFTEST = os.environ["SELFTEST"] == "1"
OS_UUID_MODE = os.environ.get("OS_UUID_MODE", "fixed")
LINUX_OS_UUID = bytes.fromhex(os.environ["LINUX_OS_UUID"])
MAX_SAVES = int(os.environ.get("MAX_SAVES", "48"))
IDLE = int(os.environ.get("IDLE", "25"))
XART_STORE = os.environ["XART_STORE"]

OP_FWBOOT, OP_OSUUID, OP_FETCH_MASTER, OP_FETCH_GL = 0x0e, 0x13, 0x00, 0x05
OP_ABSENT, OP_ANNOUNCE, OP_SAVE_XART, OP_SAVE_LOCKER = 0x07, 0x1d, 0x01, 0x06
RESP_DONE, RESP_ANNOUNCE = 0x00, 0x16
ACK_MASK = 0xFFFFFF00
OPNAME = {OP_FWBOOT:"fw-boot", OP_OSUUID:"os-uuid", OP_FETCH_MASTER:"FETCH-maître",
          OP_FETCH_GL:"FETCH-locker", OP_ABSENT:"absent(SEP)", OP_ANNOUNCE:"annonce-EP",
          OP_SAVE_XART:"SAVE-xART", OP_SAVE_LOCKER:"SAVE-locker"}

def declen(param, data): return (param & 0xFF) | ((data & 0xFF) << 8)

# --- store xART Linux sur CE PC : maîtres par type (1/2), gigalockers par UUID + dump brut ---
store_masters = {}   # type(1/2) -> charge (payload scellé)
store_gls = {}       # uuid(16o) -> charge
def store_load():
    for f in glob.glob(os.path.join(XART_STORE, "master_*.bin")):
        t = int(os.path.basename(f)[7:-4]); store_masters[t] = open(f, "rb").read()
    for f in glob.glob(os.path.join(XART_STORE, "gl_*.bin")):
        uuid = bytes.fromhex(os.path.basename(f)[3:-4]); store_gls[uuid] = open(f, "rb").read()
def store_put_master(t, blob):
    store_masters[t] = blob; open(os.path.join(XART_STORE, f"master_{t}.bin"), "wb").write(blob)
def store_put_gl(uuid, blob):
    store_gls[uuid] = blob; open(os.path.join(XART_STORE, f"gl_{uuid.hex()}.bin"), "wb").write(blob)

if SELFTEST:
    print("--- SELFTEST (hors-ligne, le Mac n'est pas touché) ---", flush=True)
    print(f"store xART Linux : {XART_STORE}  (maîtres={len(glob.glob(os.path.join(XART_STORE,'master_*.bin')))}, "
          f"gl={len(glob.glob(os.path.join(XART_STORE,'gl_*.bin')))})", flush=True)
    print("Politique native PERSIST :", flush=True)
    print("  fw-boot/os-uuid/annonce/absent-SEP : ack (idem recon)", flush=True)
    print("  FETCH maître : store? -> SERVIR (0x11 zéros + charge) ; sinon ABSENT (len 0x11)", flush=True)
    print("  FETCH locker : UUID en B ; store? -> servir ; sinon ABSENT (len 0)", flush=True)
    print(f"  SAVE 0x01/0x06 : lire B, STOCKER, ACK (DATA&0xffffff00)  ⚠️ ÉCRITURE  (budget {MAX_SAVES})", flush=True)
    assert OS_UUID_MODE in ("fixed", "none") and len(LINUX_OS_UUID) == 16
    print("SELFTEST OK (rien envoyé au SEP).", flush=True)
    sys.exit(0)

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
        elif m.TYPE == 0x11: sep.send_msg(SEPMessage(EP=0, TAG=m.TAG, TYPE=0x12))

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
def dart_rw(sid, iova, data=None, size=0):
    """data!=None -> écrit ; sinon lit `size` octets. Page par page (IOVA->PA)."""
    read = data is None; end = iova + (size if read else len(data)); cur, off, out = iova, 0, []
    while cur < end:
        page = cur & ~(DART_PAGE-1); n = min(end, page+DART_PAGE) - cur
        pa = translate_page(sid, page)
        if pa is None: raise RuntimeError("page non mappée")
        pa += cur - page; _check(pa, n)
        if read: out.append(iface.readmem(pa, n))
        else: iface.writemem(pa, data[off:off+n]); off += n
        cur += n
    return b"".join(out) if read else None

print("démarrage du SEP par m1n1 (séquence publique, routine)...", flush=True)
sep.boot(); print("BOOT OK", flush=True)
t0 = time.time()
while time.time() - t0 < 8:
    pump_ep0()
    if 0x13 in sep.epnum2name: break
    time.sleep(0.02)
if 0x13 not in sep.epnum2name:
    print(f"ERREUR: EP 0x13 non annoncé. {sep.epnum2name}. Abandon.", flush=True); sys.exit(2)
print("xarm (0x13) annoncé : " + ", ".join(f"0x{n:02x}:{nm}" for n, nm in sorted(sep.epnum2name.items())), flush=True)
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
sid_A = find_sid(IOVA_A); sid_B = find_sid(IOVA_B)
store_load()
print(f"tampons prêts (A sid={sid_A}, B sid={sid_B}). store: maîtres={sorted(store_masters)}, gl={len(store_gls)}.", flush=True)

def write_A(data):
    iface.writemem(phys_A, b"\x00"*SIZE); dart_rw(sid_A, IOVA_A, data=data[:SIZE])

def send(m, typ, param, data): sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=typ, PARAM=param, DATA=data))

def serve_master(m):
    sel = (m.DATA >> 8) & 0xFF; mtype = 2 if (sel & 1) else 1
    pay = store_masters.get(mtype)
    if pay is None:                                  # absent (kext) : len 0x11, préfixe seul
        write_A(b"\x00" * 0x11); send(m, RESP_DONE, 0x11, sel << 8); return f"ABSENT maître t{mtype}"
    A = b"\x00" * 0x11 + pay; ln = len(A); write_A(A)
    send(m, RESP_DONE, ln & 0xFF, ((ln >> 8) & 0xFF) | (sel << 8)); return f"SERVI maître t{mtype} ({ln}o)"

def serve_gl(m):
    sel = (m.DATA >> 8) & 0xFF; uuid = dart_rw(sid_B, IOVA_B, size=16)
    pay = store_gls.get(uuid)
    if pay is None:
        write_A(b""); send(m, RESP_DONE, 0x00, sel << 8); return f"ABSENT gl {uuid.hex()}"
    ln = len(pay); write_A(pay)
    send(m, RESP_DONE, ln & 0xFF, ((ln >> 8) & 0xFF) | (sel << 8)); return f"SERVI gl {uuid.hex()} ({ln}o)"

gl_raw = []
def handle_save(m):
    sel = (m.DATA >> 8) & 0xFF; ln = declen(m.PARAM, m.DATA)
    blob = dart_rw(sid_B, IOVA_B, size=ln) if ln else b""
    if m.TYPE == OP_SAVE_XART:
        mtype = 2 if (sel & 1) else 1; store_put_master(mtype, blob); tag = f"maître t{mtype}"
    else:
        idx = len(gl_raw); gl_raw.append(blob)
        open(os.path.join(XART_STORE, f"glsave_{idx}.bin"), "wb").write(blob)  # UUID-keying = TODO
        tag = f"gigalocker brut #{idx}"
    send(m, RESP_DONE, 0x00, m.DATA & ACK_MASK)      # ⚠️ ACK : le compteur scellé avance
    return tag, ln

counts = defaultdict(int); nsave = 0; last = time.time(); verdict = "idle"
print(f"=== PERSIST : on ACQUITTE + STOCKE les SAVE (écriture), budget {MAX_SAVES}, idle {IDLE}s ===", flush=True)
while time.time() - last < IDLE:
    m = next_sep_13(timeout_s=2)
    if m is None: continue
    last = time.time(); op = m.TYPE; counts[op] += 1; name = OPNAME.get(op, f"op_0x{op:02x}")
    if op == OP_FWBOOT:
        write_A(b""); send(m, RESP_DONE, 0x00, 0x00000100); print(f"  {name} TAG=0x{m.TAG:02x} -> ack", flush=True)
    elif op == OP_OSUUID:
        if OS_UUID_MODE == "none": send(m, 0x02, 0x00, 0x00000000); print(f"  {name} -> pas d'UUID (TYPE=0x02)", flush=True)
        else: write_A(LINUX_OS_UUID); send(m, RESP_DONE, 0x00, 0x00000000); print(f"  {name} -> UUID Linux", flush=True)
    elif op == OP_FETCH_MASTER:
        print(f"  {name} TAG=0x{m.TAG:02x} DATA=0x{m.DATA:08x} -> {serve_master(m)}", flush=True)
    elif op == OP_FETCH_GL:
        print(f"  {name} TAG=0x{m.TAG:02x} -> {serve_gl(m)}", flush=True)
    elif op == OP_ABSENT:
        send(m, RESP_DONE, 0x00, 0x00000000); print(f"  {name} TAG=0x{m.TAG:02x} -> ack", flush=True)
    elif op == OP_ANNOUNCE:
        send(m, RESP_ANNOUNCE, 0x00, m.DATA & ACK_MASK)
        ep = "".join(chr((m.DATA >> (i*8)) & 0xff) for i in (2,1,0))
        print(f"  {name} ('{ep}') -> ack 0x16", flush=True)
    elif op in (OP_SAVE_XART, OP_SAVE_LOCKER):
        nsave += 1; tag, ln = handle_save(m)
        print(f"  {name} TAG=0x{m.TAG:02x} -> ACK + STOCKÉ {tag} ({ln}o) [SAVE #{nsave}/{MAX_SAVES}]", flush=True)
        if nsave >= MAX_SAVES:
            verdict = "budget_atteint"; print(f"  >>> {MAX_SAVES} SAVE sans stabilisation = MÊME MUR QUE VOIE C. STOP.", flush=True); break
    else:
        verdict = "op_inconnue"; print(f"  op INCONNUE 0x{op:02x} TAG=0x{m.TAG:02x} -> STOP (fail-closed).", flush=True); break

print("--- bilan : " + ", ".join(f"{OPNAME.get(o,hex(o))}×{c}" for o, c in sorted(counts.items())), flush=True)
print(f"--- verdict flux : {verdict} (idle = le SEP s'est stabilisé après les SAVE ; sinon boucle/arrêt)", flush=True)
print("endpoints finaux : " + ", ".join(f"0x{n:02x}:{nm}" for n, nm in sorted(sep.epnum2name.items())), flush=True)
print(f"store après run : maîtres={sorted(store_masters)}, gl={len(store_gls)}, gl_bruts={len(gl_raw)} (dans {XART_STORE})", flush=True)
sbio = [nm for nm in sep.epnum2name.values() if nm in ("sbio", "sbi")]
print(f">>> sbio annoncé ? {'OUI' if sbio else 'non'} ; SAVE acquittés : {nsave}. (annoncé ≠ fonctionnel ; prochaine étape = sonder sbio/sks.)", flush=True)
PY
