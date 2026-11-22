#!/usr/bin/env bash
# =============================================================================
# sep_native_sbio.sh — ROUTE NATIVE + SONDE sbio : sceller un xART FRAIS pour Linux,
#                       PUIS demander à sbio (0x08) s'il est VIVANT (poignée 0x73, SANS doigt).
#
# ─────────────────────────────────────────────────────────────────────────────
# EN LANGAGE CLAIR (décision go / no-go — Albert)
#   SUITE DIRECTE DE sep_native_persist.sh (qui a RÉUSSI le 2026-11-22) : en répondant « je n'ai pas
#   de xART » (absent) aux demandes du SEP puis en ACQUITTANT + STOCKANT l'état frais qu'il scelle, le
#   SEP s'est STABILISÉ (il arrête de re-sauver) et a ANNONCÉ sbio (0x08, le capteur Touch ID) + sks.
#   CE script-ci refait EXACTEMENT ce flux, PUIS, une fois le SEP stabilisé, pose UNE question à sbio :
#   la poignée de main 0x73 (la toute 1re chose que macOS dit à sbio). But : savoir si sbio est seulement
#   ANNONCÉ (un nom dans la liste) ou VRAIMENT VIVANT (il répond). C'est l'étape qui dit si la route native
#   « tient » jusqu'au capteur.
#
#   CE QUI EST ÉCRIT (⚠️ la vraie porte, IDENTIQUE à persist) :
#     - Booter le firmware SEP (IMG4) : écriture SEP, déjà éprouvée (routine depuis des semaines).
#     - Acquitter un SAVE fait AVANCER le compteur anti-rejeu scellé du SEP (matériel) : irréversible au
#       sens « on ne revient pas en arrière sur le compteur ». MÊME classe de risque que persist.
#     - La poignée 0x73 est BÉNIGNE : c'est juste « bonjour » à sbio. AUCUN doigt, AUCUN enrôlement,
#       AUCUN secret lu ni écrit. On lit la réponse et on s'arrête ; on n'acquitte rien après.
#     - Récupération : through-SEP = quasi toujours réparable par DFU (voie C, 16/11…), PAS prouvé sûr à
#       100 % (cf. Stockholm / inconnus). Backup + IPSW prêts. macOS sera désynchronisé — on s'en fiche
#       (il ne boote déjà plus). Linux : aucun risque.
#     - Budget de SAVE BORNÉ (MAX_SAVES, défaut 48). Au-delà sans stabilisation = « même mur que voie C »
#       → on s'arrête et la sonde sbio n'est PAS lancée.
#     - Fail-closed PARTOUT : si un CNTL d'ouverture de sbio n'est pas acquitté, ou si le fichier de
#       poignée (SBIO_A) n'est pas un vrai 0x73 → on n'envoie RIEN à sbio et on s'arrête.
#
#   CE QUE ÇA N'EST PAS : pas du rejeu. On ne sert JAMAIS un coffre macOS. On part VIDE (store neuf), le
#     SEP crée SON propre état et on le garde. « sbio VIVANT » ≠ « Touch ID marche » : il restera toute
#     la séquence d'init capteur + sks + un vrai match + l'enrôlement sous Linux (autres chantiers).
#
#   STORE SÉPARÉ (sécurité) : cet essai écrit dans XART_STORE = ./xart_store_sbio/ (dossier À PART), JAMAIS
#     dans ./xart_store_linux/ (l'état scellé précieux du run réussi, qu'on préserve). On part d'un store
#     VIDE, ce qui reproduit fidèlement le run réussi de ce soir.
#
#   ENDPOINTS TOUCHÉS : 0x00 (CNTL, amorçage), 0x13 (xART/gigalocker, comme persist), 0x08 (sbio, la sonde).
#   RÉSULTAT ATTENDU : soit « sbio VIVANT » (B8 répond un gt_packet +0x00=1/+0x14=0x73, ou un message
#     EP 0x08 TAG=0xfc/TYPE=0x73 ou TAG=0x04) ; soit « sbio ANNONCÉ mais muet » (3 causes possibles listées).
#   PRÉPARÉ PAR : Claude (Opus 4.8), 2026-11-22 — à relire et lancer par Albert, backup + DFU prêts.
#                 L'agent ne lance JAMAIS ce script en réel (uniquement SELFTEST=1 hors-ligne).
# ─────────────────────────────────────────────────────────────────────────────
#
# TECHNIQUE (politique native complète, docs/handler_0x13.md, gigalocker.md ; sonde = docs/messages.md §SBIO) :
#   PHASE 1 — NATIF (identique à sep_native_persist.sh) :
#     - 0x0e fw-boot / 0x13 os-uuid / 0x1d annonce / 0x07 absent-SEP : ack VU (idem recon).
#     - 0x00 FETCH maître  : si en store -> SERVIR (A = 0x11 zéros + charge, longueur 0x11+len) ; sinon ABSENT (len 0x11).
#     - 0x05 FETCH locker  : UUID lu en B ; si en store -> servir ; sinon ABSENT (len 0).
#     - 0x01 SAVE maître   : lire B (longueur = PARAM|DATA0<<8), STOCKER par type (1 USER / 2 SEP), ACK. ⚠️ écriture.
#     - 0x06 SAVE locker   : lire B, STOCKER (dump brut indexé), ACK. ⚠️ écriture.
#     Boucle jusqu'à `idle` (le SEP se tait pendant IDLE s = stabilisé), budget MAX_SAVES, fail-closed sur inconnu.
#   PHASE 2 — SONDE sbio (seulement si verdict=idle ET 0x08 annoncé ; source: kext pour la carte sbio) :
#     - ouvrir l'EP 0x08 : allouer A8/B8 (0x4000), IOVA 0x54000/0x5c000, mapper stream 0, annoncer par 4 CNTL (param=0x08).
#     - écrire dans A8 les octets EXACTS d'un 0x73 capturé (SBIO_A), vérifier +0x00==1 et +0x14==0x73 AVANT d'envoyer.
#     - envoyer > EP=0x08 TAG=0xfc TYPE=0x73 PARAM=0 DATA=0 ; écouter l'EP 0x08 ~6 s ; relire la faute DART ; lire/dumper B8.
#     - VERDICT : B8[0]==1 et B8[0x14]==0x73, OU message EP 0x08 TAG=0xfc/TYPE=0x73 (ou TAG=0x04) -> VIVANT ; sinon MUET.
#
# RED LINES : aucune op disque sur le Mac, pas de dd/nvram/sudo/partition. Le store est un fichier sur CE PC.
#   m1n1 : lu, jamais modifié/poussé. Le SEP-write (boot IMG4 + SAVE-ack) = lancé par Albert (ce script, pending/).
#
# USAGE
#   SELFTEST=1 ./pending/sep_native_sbio.sh            # hors-ligne : montre la politique + vérifie SBIO_A, ne touche pas le Mac
#   ./tools/catch_proxy.sh                             # D'ABORD (Claude) : attrape le Mac en proxy (tu power-cycles)
#   ./pending/sep_native_sbio.sh                       # PUIS run RÉEL d'ÉCRITURE + sonde (Albert lance)
#   MAX_SAVES=48 | OS_UUID_MODE=fixed|none | XART_STORE=<dir> | IDLE=25 | SBIO_A=<fichier.bin> | SBIO_STREAM15=0|1
#
# PRÉPARÉ PAR : Claude (Opus 4.8), 2026-11-22 — en-tête clair ci-dessus ; à lancer par Albert, backup+DFU prêts.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/../tools/env.sh"

export SELFTEST="${SELFTEST:-0}"
export OS_UUID_MODE="${OS_UUID_MODE:-fixed}"
export LINUX_OS_UUID="${LINUX_OS_UUID:-4c494e55580000000000000000000000}"
export MAX_SAVES="${MAX_SAVES:-48}"
export IDLE="${IDLE:-25}"
# Store SÉPARÉ : NE JAMAIS écrire dans xart_store_linux/ (état scellé précieux). On part VIDE.
export XART_STORE="${XART_STORE:-$REPO_ROOT/xart_store_sbio}"
# Poignée de main sbio rejouée OCTET POUR OCTET depuis une capture (pas de gt_packet construit à la main).
export SBIO_A="${SBIO_A:-traces/20261108-032454_c12-boot-ho/sep.log.ool/000300_08_A.bin}"
# Le dart-sep déclare sids=0x8001 (streams 0 ET 15) mais m1n1 ne programme QUE le stream 0. SBIO_STREAM15=1
# programme AUSSI le stream 15 côté AP (lecture/écriture DART de l'AP uniquement, AUCUNE écriture SEP).
# Option DIAGNOSTIC facultative (défaut 0) : non nécessaire pour trancher « vivant vs muet ».
export SBIO_STREAM15="${SBIO_STREAM15:-0}"
export M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
mkdir -p "$XART_STORE"

if [ "$SELFTEST" != 1 ]; then
  [ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
  STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_native_sbio"; mkdir -p "$OUT"; export OUT
  # Le Mac doit DÉJÀ être en proxy : lancer ./tools/catch_proxy.sh AVANT (Claude le fait + power-cycle).
  require_mac
fi

timeout 360 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "${OUT:-/tmp}/native_sbio.log"
import os, sys, time, struct, glob
SELFTEST = os.environ["SELFTEST"] == "1"
OS_UUID_MODE = os.environ.get("OS_UUID_MODE", "fixed")
LINUX_OS_UUID = bytes.fromhex(os.environ["LINUX_OS_UUID"])
MAX_SAVES = int(os.environ.get("MAX_SAVES", "48"))
IDLE = int(os.environ.get("IDLE", "25"))
XART_STORE = os.environ["XART_STORE"]
SBIO_A = os.environ.get("SBIO_A", "")
SBIO_STREAM15 = os.environ.get("SBIO_STREAM15", "0") == "1"

OP_FWBOOT, OP_OSUUID, OP_FETCH_MASTER, OP_FETCH_GL = 0x0e, 0x13, 0x00, 0x05
OP_ABSENT, OP_ANNOUNCE, OP_SAVE_XART, OP_SAVE_LOCKER = 0x07, 0x1d, 0x01, 0x06
RESP_DONE, RESP_ANNOUNCE = 0x00, 0x16
ACK_MASK = 0xFFFFFF00
OPNAME = {OP_FWBOOT:"fw-boot", OP_OSUUID:"os-uuid", OP_FETCH_MASTER:"FETCH-maître",
          OP_FETCH_GL:"FETCH-locker", OP_ABSENT:"absent(SEP)", OP_ANNOUNCE:"annonce-EP",
          OP_SAVE_XART:"SAVE-xART", OP_SAVE_LOCKER:"SAVE-locker"}

def declen(param, data): return (param & 0xFF) | ((data & 0xFF) << 8)

# --- store xART sbio sur CE PC : maîtres par type (1/2), gigalockers par UUID + dump brut ---
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
    print(f"store xART sbio : {XART_STORE}  (maîtres={len(glob.glob(os.path.join(XART_STORE,'master_*.bin')))}, "
          f"gl={len(glob.glob(os.path.join(XART_STORE,'gl_*.bin')))})  [SÉPARÉ de xart_store_linux]", flush=True)
    print("PHASE 1 — politique native PERSIST (identique à sep_native_persist.sh) :", flush=True)
    print("  fw-boot/os-uuid/annonce/absent-SEP : ack (idem recon)", flush=True)
    print("  FETCH maître : store? -> SERVIR (0x11 zéros + charge) ; sinon ABSENT (len 0x11)", flush=True)
    print("  FETCH locker : UUID en B ; store? -> servir ; sinon ABSENT (len 0)", flush=True)
    print(f"  SAVE 0x01/0x06 : lire B, STOCKER, ACK (DATA&0xffffff00)  ⚠️ ÉCRITURE  (budget {MAX_SAVES})", flush=True)
    print(f"  boucle jusqu'à idle ({IDLE}s de silence = SEP stabilisé) ; fail-closed sur op inconnue", flush=True)
    assert OS_UUID_MODE in ("fixed", "none") and len(LINUX_OS_UUID) == 16
    print("PHASE 2 — sonde sbio (seulement si verdict=idle ET 0x08 annoncé) :", flush=True)
    if SBIO_A and os.path.exists(SBIO_A):
        b = open(SBIO_A, "rb").read()
        v0 = b[0x00] if b else None
        op = b[0x14] if len(b) > 0x14 else None
        ophex = f"0x{op:02x}" if op is not None else "??"
        print(f"  sonde sbio : enverrait {os.path.basename(SBIO_A)} ({len(b)} o) dans le tampon A8 de l'EP 0x08 ;", flush=True)
        print(f"               gt_packet version=+0x00={v0} opcode=+0x14={ophex} (attendu : +0x00=1, +0x14=0x73),", flush=True)
        print("               puis > EP=0x08 TAG=0xfc TYPE=0x73 PARAM=0 DATA=0, puis LECTURE de B8.", flush=True)
        print("  (lecture registre faute DART au run réel : ERROR@0x40/ADDR@0x50-0x54 du dart-sep, read32 only,", flush=True)
        print("   avant et après le 0x73 — non exécutée en SELFTEST.)", flush=True)
        if SBIO_STREAM15:
            print("  E1 (SBIO_STREAM15=1) : au run réel, la sonde programmerait AUSSI le stream 15 du dart-sep et", flush=True)
            print("     mapperait A8/B8 en sid 0 ET sid 15 (écriture DART AP seulement, AUCUNE écriture SEP). Option.", flush=True)
        # asserts : le fichier doit être un vrai gt_packet 0x73 (sinon rien ne serait envoyé au run réel).
        assert len(b) > 0x14, f"SBIO_A trop court ({len(b)} o) : pas un gt_packet"
        assert b[0x00] == 1, f"SBIO_A +0x00={b[0x00]} (attendu 1) : pas un 0x73 valide"
        assert b[0x14] == 0x73, f"SBIO_A +0x14={b[0x14]:#x} (attendu 0x73) : pas un 0x73 valide"
        print("  SBIO_A vérifié : gt_packet 0x73 valide (+0x00=1, +0x14=0x73).", flush=True)
    else:
        print(f"  sonde sbio : ERREUR — fichier SBIO_A introuvable : {SBIO_A!r}.", flush=True)
        print("  Donner un .bin de tampon A d'un 0x73 (ex. traces/…c12…/sep.log.ool/000300_08_A.bin).", flush=True)
        raise SystemExit(1)
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

# ---------------------------------------------------------------------------
# LECTURE SEULE de l'état de faute du dart-sep (porté de sep_xart_replay.sh, E1 2026-11-18).
#   But : après le 0x73, voir si une TRADUCTION a fauté côté dart-sep, sur quel stream/sid, à quelle adresse.
#   Offsets/décodage = définitions PUBLIQUES de m1n1 (proxyclient/m1n1/hw/dart8020.py:11-23/67-69 ; src/dart.c).
#   dart-sep = famille t8020/t6000 : même carte DART8020Regs -> ERROR@0x40 / ADDR_LO@0x50 / ADDR_HI@0x54.
#   ON NE FAIT QUE read32 : AUCUNE écriture, on NE remet PAS le registre à zéro (la RAZ = write, interdite).
#   LIMITE : le registre LATCHE la faute jusqu'à une RAZ ; si le baseline a déjà FLAG=1, une nouvelle faute
#   peut ne PAS s'y inscrire -> on ne peut alors pas trancher (refaire sur cold-boot propre, baseline FLAG=0).
DART_ERROR, DART_ERROR_ADDR_LO, DART_ERROR_ADDR_HI = 0x40, 0x50, 0x54
_DART_ERR_BITS = (("NO_DAPF_MATCH", 11), ("WRITE", 10), ("SUBPAGE_PROT", 7), ("PTE_READ_FAULT", 6),
                  ("READ_FAULT", 4), ("WRITE_FAULT", 3), ("NO_PTE", 2), ("NO_PMD", 1), ("NO_TTBR", 0))

def read_dart_fault():
    """Lit (read32 only) l'état de faute du dart-sep. Retourne un dict décodé. Aucune écriture."""
    raw = p.read32(dart_base + DART_ERROR)
    addr = (p.read32(dart_base + DART_ERROR_ADDR_HI) << 32) | p.read32(dart_base + DART_ERROR_ADDR_LO)
    bits = [nm for nm, b in _DART_ERR_BITS if raw & (1 << b)]
    return {"raw": raw, "flag": (raw >> 31) & 1, "sid": (raw >> 24) & 0xf, "bits": bits, "addr": addr}

def print_dart_fault(label):
    f = read_dart_fault()
    print(f"  [DART-faute {label}] ERROR=0x{f['raw']:08x} FLAG={f['flag']} sid={f['sid']} "
          f"causes={','.join(f['bits']) or '—'} ADDR=0x{f['addr']:x}", flush=True)
    return f

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

# ===========================================================================
# PHASE 2 — sonde sbio (0x73, SANS DOIGT, UNE seule commande). Portée FIDÈLEMENT de
# sep_xart_replay.sh (probe_sbio()). À n'appeler qu'après que le SEP s'est stabilisé (idle) ET
# a annoncé sbio (0x08). Fait EXACTEMENT ce que macOS fait en 1er avec sbio (docs/messages.md §SBIO).
# ===========================================================================
def probe_sbio():
    print("=== SONDE sbio (0x73, sans doigt, une seule commande) ===", flush=True)
    if 0x08 not in sep.epnum2name:
        print("  sbio (0x08) n'est PAS annoncé : rien à sonder. On ne fait rien.", flush=True)
        return
    if not (SBIO_A and os.path.exists(SBIO_A)):
        print(f"  ERREUR: fichier SBIO_A introuvable ({SBIO_A!r}). On n'envoie RIEN.", flush=True)
        return
    a_bytes = open(SBIO_A, "rb").read()
    if len(a_bytes) <= 0x14 or a_bytes[0x14] != 0x73 or a_bytes[0] != 1:
        print(f"  ERREUR: SBIO_A n'est pas un gt_packet 0x73 (+0x00={a_bytes[:1].hex()} "
              f"+0x14={a_bytes[0x14:0x15].hex()}). On n'envoie RIEN.", flush=True)
        return

    # 1. ouvrir sbio : allouer + mapper + annoncer A8/B8 (0x4000). IOVA = celles de macOS pour sbio
    #    (c12 : A=0x54000, B=0x5c000), distinctes des IOVA xART (0x2c000/0x38000) déjà mappées.
    SZ8 = 0x4000
    IOVA_A8, IOVA_B8 = 0x54000, 0x5c000
    try:
        phys_A8 = u.heap.memalign(0x4000, SZ8)
        phys_B8 = u.heap.memalign(0x4000, SZ8)
        iface.writemem(phys_A8, b"\x00" * SZ8)
        iface.writemem(phys_B8, b"\x00" * SZ8)
        # Stream 0 (comportement normal m1n1) : toujours mappé.
        p.dart_map(sep.dart_handle, IOVA_A8, phys_A8, SZ8)
        p.dart_map(sep.dart_handle, IOVA_B8, phys_B8, SZ8)
        # Option E1 : programmer AUSSI le stream 15 du dart-sep et y mapper A8/B8 (mêmes phys). Même DART,
        # même type T6000 (=2), on change SEULEMENT le sid (0 -> 15). find_sid() scanne 0 d'abord, donc
        # dart_rw continue de passer par le stream 0 : l'existant est intact. Écriture DART AP seulement.
        if SBIO_STREAM15:
            dart_handle_15 = p.request(p.P_DART_INIT, sep.dart_base, 15, 0, 2)  # T6000, sid=15
            p.dart_map(dart_handle_15, IOVA_A8, phys_A8, SZ8)
            p.dart_map(dart_handle_15, IOVA_B8, phys_B8, SZ8)
            print("  E1 : stream 15 du dart-sep PROGRAMMÉ ; A8/B8 mappés en sid 0 ET sid 15 "
                  "(écriture DART côté AP seulement, aucune écriture SEP).", flush=True)
    except Exception as e:
        print(f"  ERREUR à l'allocation/mapping des tampons sbio : {e}. On n'envoie RIEN de plus.", flush=True)
        return
    for label, typ, data in [("A8 taille", 0x04, SZ8), ("A8 adresse", 0x02, IOVA_A8 >> 12),
                             ("B8 taille", 0x05, SZ8), ("B8 adresse", 0x03, IOVA_B8 >> 12)]:
        if not cntl_send(typ, data, 0x08, label):
            print(f"  le SEP n'a PAS acquitté le CNTL {label} (ouverture sbio) en 5 s. "
                  f"-> sbio ne s'ouvre pas tard sous m1n1. On s'arrête, RIEN envoyé à l'EP 0x08.", flush=True)
            return
        print(f"  CNTL {label} (ouverture sbio) : acquitté", flush=True)

    # Diagnostic : lister TOUS les streams où A8 est désormais traduisible. N'envoie rien ; lectures DART.
    def _maps(sid):
        try:
            return translate_page(sid, IOVA_A8) is not None
        except RuntimeError:
            return False
    sids_A8 = [s for s in range(16) if _maps(s)]
    print(f"  A8 (IOVA 0x{IOVA_A8:x}) mappé dans les streams : {sids_A8}", flush=True)
    if SBIO_STREAM15 and 15 not in sids_A8:
        print("  !! E1 : le stream 15 n'apparaît PAS mappé malgré SBIO_STREAM15=1 — l'init du sid 15 a "
              "échoué ; le test E1 n'est pas valide. On continue (stream 0 reste bon) mais ne pas conclure sur E1.", flush=True)

    # 2. écrire le 0x73 dans A8 (octets exacts de la capture), puis 3. l'envoyer.
    try:
        sid_A8 = find_sid(IOVA_A8)
        dart_rw(sid_A8, IOVA_A8, data=a_bytes[:SZ8])
    except Exception as e:
        print(f"  ERREUR à l'écriture du 0x73 dans A8 : {e}. RIEN envoyé à l'EP 0x08.", flush=True)
        return
    print(f"  0x73 écrit dans A8 (depuis {os.path.basename(SBIO_A)}). Envoi de la commande...", flush=True)
    # PURGER tout message 0x08 spontané accumulé AVANT l'envoi (sinon faux positif « vivant » sur un
    # résidu antérieur au 0x73).
    pump_ep0(); sep.msgs[0x08].clear()
    # Baseline de l'état de faute du dart-sep AVANT le 0x73 (lecture seule), comparé à l'après-envoi.
    fault_before = print_dart_fault("avant 0x73 (baseline)")
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x73, PARAM=0x00, DATA=0x00000000))

    # 4. écouter l'EP 0x08 ~6 s et lire B8. On N'ACQUITTE RIEN, on n'envoie pas de 2e commande.
    got = []
    t0 = time.time()   # APRÈS l'envoi : seuls les messages POST-commande comptent
    while time.time() - t0 < 6:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft()
            got.append((m.TAG, m.TYPE))
            print(f"  SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} "
                  f"DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    # État de faute du dart-sep APRÈS le 0x73 (lecture seule), puis comparaison au baseline.
    fault_after = print_dart_fault("après 0x73")
    changed = (fault_after["raw"] != fault_before["raw"]) or (fault_after["addr"] != fault_before["addr"])
    if fault_after["flag"] and (fault_before["flag"] == 0 or changed):
        rf = "READ_FAULT" in fault_after["bits"]
        print(f"  >>> FAUTE DART NEUVE après le 0x73 : sid={fault_after['sid']} "
              f"causes={','.join(fault_after['bits']) or '—'} adresse=0x{fault_after['addr']:x}.", flush=True)
        if fault_after["sid"] == 15 and rf:
            print("      sid=15 + READ_FAULT => le SEP a TENTÉ de LIRE l'OOL sbio via le stream 15 "
                  "(preuve directe du canal). Attendu : SANS stream 15 (run de contrôle) cette faute "
                  "apparaît ; AVEC stream 15 ouvert, elle disparaît et sbio répond.", flush=True)
        elif fault_after["sid"] == 0:
            print("      sid=0 => faute sur le stream DÉJÀ programmé : ce n'est pas le canal « sid 15 ».", flush=True)
        else:
            print(f"      sid={fault_after['sid']} => interpréter selon le mapping dart-sep ; ne pas sur-conclure.", flush=True)
    elif fault_before["flag"]:
        print("  >>> le registre de faute DART portait DÉJÀ un drapeau au baseline et n'a pas changé : "
              "on NE peut PAS trancher (le latch garde la 1re faute jusqu'à une RAZ qu'on ne fait pas). "
              "Refaire sur un cold-boot propre pour un baseline FLAG=0.", flush=True)
    else:
        print("  >>> AUCUNE faute DART neuve après le 0x73 (FLAG reste 0). Le silence ne vient donc PAS "
              "d'une traduction DART fautée latchée ici. Réserve : une faute peut n'être pas latchée, ou "
              "le DMA de l'OOL sbio peut ne pas passer par ce dart (hypothèse, à ne pas affirmer).", flush=True)
    try:
        b8 = iface.readmem(phys_B8, SZ8)
    except Exception as e:
        b8 = b""
        print(f"  (lecture de B8 impossible : {e})", flush=True)
    nz = sum(1 for x in b8 if x)
    if b8 and os.environ.get("OUT"):
        try:
            with open(os.path.join(os.environ["OUT"], "sbio_probe_B.bin"), "wb") as f:
                f.write(b8)
        except Exception:
            pass
    b_ok = len(b8) > 0x14 and b8[0] == 1 and b8[0x14] == 0x73
    msg_ok = any(typ == 0x73 for _, typ in got) or any(tag == 0x04 for tag, _ in got)
    print(f"  B8 : {nz} octets non nuls ; tête={b8[:0x20].hex() if b8 else '—'}", flush=True)
    if b_ok or msg_ok:
        print(">>> SONDE sbio : sbio a RÉPONDU au 0x73 (gt_packet B8 +0x14=0x73 et/ou message EP 0x08). "
              "sbio est VIVANT sous m1n1, pas seulement annoncé. Résultat majeur — à reproduire (n>=3) "
              "et à comparer à la réponse macOS c12 (B +0x00=1, +0x14=0x73). NE PAS conclure 'Touch ID "
              "marche' : il reste toute la séquence d'init (clé capteur, etc.) puis un vrai match.", flush=True)
        if SBIO_STREAM15:
            print(">>> VERDICT E1 : réponse obtenue AVEC le stream 15 programmé alors que les runs "
                  "sans stream 15 (n=3, docs/voie_sbio.md) étaient MUETS -> cause (i) CONFIRMÉE : le "
                  "silence venait du CANAL DART (le SEP lit l'OOL sbio via le sid 15, non programmé par "
                  "m1n1). Grande avancée, sans risque. Le driver devra mapper l'OOL sbio en sid 15. "
                  "À reproduire n>=3 et faire un run de contrôle SANS SBIO_STREAM15 (même boot) pour "
                  "confirmer que c'est bien le sid 15 qui fait la différence.", flush=True)
    else:
        if SBIO_STREAM15:
            print(">>> VERDICT E1 : TOUJOURS MUET malgré le stream 15 programmé et A8 mappé en sid 0 ET "
                  f"sid 15 (streams vus : {sids_A8}). -> cause (i) « canal DART » FORTEMENT AFFAIBLIE "
                  "(une PTE valide côté AP ne PROUVE pas que le SEP a TENTÉ de lire l'OOL via sid 15 ; "
                  "regarder l'état de faute DART ci-dessus : une faute READ neuve sur sid 15 au run de "
                  "CONTRÔLE — sans stream 15 — confirmerait le canal, son absence l'affaiblit encore). "
                  "Reste probable : l'ÉTAT (sbio pas armé tant que xART n'est pas scellé / endpoint non "
                  "prêt, cause ii/iii de docs/voie_sbio.md).", flush=True)
        print(">>> SONDE sbio : AUCUNE réponse au 0x73 (B8 nul, aucun message EP 0x08). sbio est ANNONCÉ, "
              "mais ici PAS de preuve qu'il traite la commande. 3 causes possibles, À NE PAS confondre : "
              "(1) le 0x73 n'a pas ATTEINT sbio — l'acquittement des CNTL prouve que le SEP a enregistré "
              "l'adresse de A8, PAS qu'il lit bien phys_A8 à l'IOVA 0x54000 sous m1n1 (même inconnu DART "
              "stream/sid que pour xART ; le succès de xART ne garantit pas le stream de sbio) ; "
              "(2) l'ouverture tardive de sbio sous m1n1 ne suffit pas ; (3) l'état restauré ne rend pas "
              "sbio fonctionnel. -> hypotheses.md. Ne pas conclure 'sbio mort' sur ce seul silence.", flush=True)

# ===========================================================================
# PHASE 1 — boucle native PERSIST (identique à sep_native_persist.sh) : ACK + STOCKE les SAVE.
# ===========================================================================
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
print(f">>> sbio annoncé ? {'OUI' if sbio else 'non'} ; SAVE acquittés : {nsave}.", flush=True)

# ---------------------------------------------------------------------------
# PHASE 2 : seulement si le SEP s'est STABILISÉ (verdict=idle) ET a annoncé sbio (0x08).
#   Si le flux s'est arrêté (budget/inconnu) on NE sonde PAS (fail-closed : on ne touche pas sbio sur un
#   état non stabilisé). Si idle mais 0x08 absent, rien à sonder.
# ---------------------------------------------------------------------------
if verdict != "idle":
    print(f">>> Flux non stabilisé (verdict={verdict}) : sonde sbio NON lancée (fail-closed).", flush=True)
elif 0x08 not in sep.epnum2name:
    print(">>> SEP stabilisé mais sbio (0x08) non annoncé : rien à sonder.", flush=True)
else:
    probe_sbio()
PY
