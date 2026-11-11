#!/usr/bin/env bash
# =============================================================================
# BUT
#   Tester si un SEP démarré par m1n1 (sans macOS) accepte qu'on lui REJOUE ses
#   derniers lockers xART, et annonce alors l'endpoint biométrique `sbio` (+ skdl,
#   sse, sks, scrd). C'est le seul test qui tranche : l'anti-rejeu du SEP accepte-t-il
#   un rejeu fidèle de l'état courant ? Si oui -> Touch ID devient atteignable sous
#   Linux (le SEP fait lui-même la comparaison d'empreinte).
#
#   Le script ne code RIEN en dur : il REJOUE fidèlement ce que macOS a fait pendant
#   une capture `S_new`, lue depuis son sep.log (ordre des messages EP 0x13) et ses
#   buffers .ool/*.bin (contenu exact écrit dans le tampon A). Les adresses des tampons
#   OOL (A = AP->SEP, B = SEP->AP) sont APPRISES en direct via les messages CNTL, jamais
#   codées en dur.
#
# ENDPOINTS TOUCHÉS
#   0xFF / 0xFE : démarrage du SEP (GET_STATUS, BOOT_TZ0, BOOT_IMG4, SET_SHMEM) =
#                 exactement la séquence de pending/sep_boot.sh (déjà lancée sans incident).
#   0x13 (xarm, xART) : on répond aux requêtes du SEP = le coeur du rejeu.
#   Firmware du SEP déjà en mémoire (SEPFW préchargé par iBoot). Rien de téléchargé/déchiffré.
#
# AUCUNE OPÉRATION DISQUE
#   Le script ne parle qu'au SEP par la mailbox et n'écrit que dans le tampon partagé du
#   SEP (RAM, via le DART). Il n'ouvre, ne monte, n'écrit AUCUN disque ; pas de partition,
#   pas de dd, pas de NVRAM, pas de boot policy, pas de sudo. La partition Linux n'est
#   jamais touchée. (À vérifier à la relecture : aucune commande disque ci-dessous.)
#
# RISQUE  (cf. docs/voie_c_design.md « Analyse de sûreté »)
#   - Linux : AUCUN (voir ci-dessus).
#   - Brick : faible mais non nul. Messages de même nature que sep_boot + réponses sur un
#     endpoint que le SEP attend déjà. Un SEP incohérent se réinitialise au redémarrage,
#     m1n1 garde la main. Pas de preuve formelle -> classé « risqué » par prudence.
#   - macOS : effet de bord possible (FileVault / trousseau / reconnexion compte Apple).
#     macOS sacrifiable (accord Albert). Ne déborde ni sur Linux ni sur le démarrage.
#
# RÉSULTAT ATTENDU
#   À la fin, liste des endpoints annoncés par le SEP. Si `sbio` (et skdl/sse/sks/scrd)
#   apparaissent -> le rejeu est accepté, Touch ID atteignable : TRÈS bonne nouvelle.
#   Sinon -> le SEP vérifie plus que save(N)=fetch(N+1) ; la voie C est close, on le saura.
#   Quel que soit le résultat : on n'envoie rien de plus, on coupe, Albert redémarre le Mac.
#
# PROCÉDURE (ordre impératif — voir docs/voie_c_design.md)
#   1. Capturer S_new SANS redémarrer macOS ensuite :
#        SEP_OOL_EPS=0x13 SEP_EPS=0x00,0x13 ./tools/boot_and_trace.sh snew-xart
#      (le SEP sauve ses derniers lockers pendant ce boot ; son compteur est alors à S_new.)
#   2. Redémarrer le Mac en m1n1 SANS rebooter macOS (un reboot *matériel* vers m1n1
#      n'avance pas le compteur ; seul un BOOT de macOS l'avancerait et périmerait S_new).
#   3. Lancer CE script en lui passant le dossier de capture S_new.
#
# ÉTAT : v2.1 — ESSAI 1 LANCÉ (2026-11-11, Albert) : 4 lockers rejoués (dont SEP-xART+USER-xART),
#   sbio/scrd/sse/skdl annoncés, puis divergence à la 5e transaction (SEP demande TAG=0x05
#   TYPE=0x01=SAVE au lieu de TYPE=0x05=FETCH). PROCHAIN PAS recommandé (sceptique) : OBSERVE=1
#   (ESSAI A) — rejoue pareil puis écoute B en lecture seule sans répondre, pour voir ce que le
#   SEP réclame après les 4 lockers. NE PAS acquitter le SAVE (compteur anti-rejeu). Détails :
#   docs/hypotheses.md « Revue sceptique — ESSAI VOIE C n°1 », docs/journal.md.
# ÉTAT v2 : le rôle AP est implémenté (allocation + mapping + annonce des tampons OOL via CNTL,
#   protocole du kext : docs/kext_sepmanager.md §3/§5). NON ENCORE LANCÉE.
#   Ce qui reste INCERTAIN, tranché seulement par l'essai (Albert lance) :
#   >>> le flux/IOVA DART : on mappe A/B à 0x2c000/0x38000 (valeurs macOS) ; pas garanti que
#       xarm du SEP les lise là sous m1n1. Si le SEP n'acquitte pas les CNTL ou ne lit pas A :
#       sortie propre (exit 2/3), AUCUN risque, et on ajuste l'IOVA/stream.
#   >>> amorçage EP 0 : SECMODE (CNTL 0x14) AJOUTÉ et validé contre la capture cntl-study3
#       (2026-11-11, non filtrée) ; le script répond aussi au NAP et ignore les notifications.
#   >>> la capture montre que l'AP met aussi en place les tampons de 0x18 et 0x0e (autres EP)
#       AVANT de répondre à xART. La v2 ne fait que 0x13. Si le SEP stagne, ajouter 0x18/0x0e.
#   >>> si le SEP démarré par m1n1 enchaîne l'échange xART une fois les tampons annoncés : c'est
#       justement la question de voie C.
#   NON VÉRIFIÉ (échoue proprement si faux) : u.adt["/chosen"].dram_base/.dram_size existe en
#   contexte proxy ; p.dart_map mappe bien dans le stream que xarm utilise.
#   À faire AVANT lancement : (a) relecture sceptique + Albert ; (b) SELFTEST (hors-ligne, ok) ;
#   (c) capturer S_new juste avant (SEP_OOL_EPS=0x13, M1N1TIMEOUT=20) sans rebooter macOS ;
#   (d) Albert lance lui-même (jamais un agent).
#
# PRÉCONDITION capture S_new : SEP_OOL_BYTES >= taille du tampon A (0x8000), sinon les .bin
#   sont tronqués et A serait rejoué incomplet. (c24/c21 utilisaient bien 0x8000.)
#
# Usage :
#   ./pending/sep_xart_replay.sh <dossier_capture_S_new>      # lancement réel (Albert)
#   OBSERVE=1 ./pending/sep_xart_replay.sh <dossier_capture>  # ESSAI A (observationnel) : rejoue
#                 jusqu'à la divergence puis ÉCOUTE ~20 s en lisant le tampon B (LECTURE SEULE),
#                 sans JAMAIS répondre sur 0x13 (donc n'acquitte PAS le SAVE -> n'avance pas le
#                 compteur anti-rejeu, S_new préservé). But : voir ce que le SEP demande après
#                 les 4 lockers (SAVE ? FETCH ? quel UUID / quelle taille de blob en B ?).
#   SELFTEST=1 ./pending/sep_xart_replay.sh <dossier_capture> # test hors-ligne, NE TOUCHE PAS le Mac
#   SKIP_CHAINLOAD=1 ...                                       # si un m1n1 frais tourne déjà
#
# PRÉPARÉ PAR : Claude (Opus 4.8), 2026-11-11 — à relire (sceptique + Albert) puis lancer par Albert.
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/../tools/env.sh"

SNEW="${1:?usage: $0 <dossier_capture_S_new (contenant sep.log et sep.log.ool/)>}"
[ -f "$SNEW/sep.log" ]      || die "sep.log introuvable dans $SNEW"
[ -d "$SNEW/sep.log.ool" ]  || die "sep.log.ool/ introuvable dans $SNEW (capture sans SEP_OOL_EPS=0x13 ?)"

export SNEW M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
export SELFTEST="${SELFTEST:-0}"
export OBSERVE="${OBSERVE:-0}"

if [ "$SELFTEST" != 1 ]; then
  require_mac
  [ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
  # Toujours créer le dossier de sortie, même en SKIP_CHAINLOAD : une écriture SEP doit
  # laisser une trace dans traces/ (et pas dans /tmp qu'on perd).
  STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_xart_replay"; mkdir -p "$OUT"; export OUT
  if [ "${SKIP_CHAINLOAD:-0}" != 1 ]; then
    "$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin" \
      2>&1 | tee "$OUT/chainload.log" >/dev/null
    sleep 2; require_mac
  fi
fi

timeout 400 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "${OUT:-/tmp}/xart_replay.log"
import os, sys, re, time, struct, glob
SELFTEST = os.environ["SELFTEST"] == "1"
OBSERVE = os.environ["OBSERVE"] == "1"
SNEW = os.environ["SNEW"]
sys.path.insert(0, os.environ["M1N1_PROXYCLIENT"])

# ---------------------------------------------------------------------------
# 1. LECTURE DE LA CAPTURE S_new : séquence EP 0x13 + quel '>' écrit le tampon A.
#    Chaque ligne message est suivie de sa ligne '# ool ...' quand il y a eu lecture
#    d'un tampon. Pour un '>' avec buf=A, le fichier .ool correspondant (seq) donne
#    les octets exacts que l'AP (macOS) a écrits dans A -> c'est ce qu'on rejoue.
# ---------------------------------------------------------------------------
MSG = re.compile(r'^([\d.]+) ([<>]) EP=0x13 TAG=0x([0-9a-f]+) TYPE=0x([0-9a-f]+) '
                 r'PARAM=0x([0-9a-f]+) DATA=0x([0-9a-f]+)')
OOL = re.compile(r'^# ool [\d.]+ seq=(\d+) EP=0x13 dir=([<>]) buf=([AB])')

steps = []          # liste ordonnée : ('recv', tag, typ) ou ('send', tag, typ, param, data, a_path|None)
ool_dir = os.path.join(SNEW, "sep.log.ool")
with open(os.path.join(SNEW, "sep.log")) as f:
    lines = f.readlines()
for i, ln in enumerate(lines):
    m = MSG.match(ln)
    if not m:
        continue
    _, d, tag, typ, param, data = m.groups()
    tag, typ, param, data = int(tag,16), int(typ,16), int(param,16), int(data,16)
    if d == '<':
        steps.append(('recv', tag, typ))
    else:
        a_path = None
        # la (les) ligne(s) '# ool' de ce message suivent immédiatement
        for j in range(i+1, min(i+4, len(lines))):
            o = OOL.match(lines[j])
            if not o:
                if lines[j].startswith('#'):
                    continue
                break
            seq, od, buf = int(o.group(1)), o.group(2), o.group(3)
            if od == '>' and buf == 'A':
                cand = os.path.join(ool_dir, f"{seq:06d}_13_A.bin")
                if os.path.exists(cand):
                    a_path = cand
        steps.append(('send', tag, typ, param, data, a_path))

n_send = sum(1 for s in steps if s[0] == 'send')
n_awrite = sum(1 for s in steps if s[0] == 'send' and s[5])
print(f"S_new: {len(steps)} étapes EP 0x13, {n_send} réponses AP, {n_awrite} écritures tampon A", flush=True)
if n_awrite == 0:
    print("ERREUR: aucune écriture de tampon A trouvée (capture sans OOL ?). Abandon.", flush=True)
    sys.exit(1)

# ---------------------------------------------------------------------------
# 2. MODE SELFTEST : on n'ouvre PAS le Mac. On vérifie juste que la séquence se
#    relit correctement et on l'affiche. Aucune écriture nulle part.
# ---------------------------------------------------------------------------
if SELFTEST:
    print("--- SELFTEST (hors-ligne, le Mac n'est pas touché) ---", flush=True)
    for s in steps:
        if s[0] == 'recv':
            print(f"  attendre <  TAG=0x{s[1]:02x} TYPE=0x{s[2]:02x}", flush=True)
        else:
            tag, typ, param, data, a = s[1], s[2], s[3], s[4], s[5]
            sz = os.path.getsize(a) if a else 0
            extra = f"  [écrit A: {os.path.basename(a)} {sz}o]" if a else ""
            print(f"  envoyer  >  TAG=0x{tag:02x} TYPE=0x{typ:02x} PARAM=0x{param:02x} "
                  f"DATA=0x{data:08x}{extra}", flush=True)
    print("SELFTEST OK : séquence relue. (Rien envoyé au SEP.)", flush=True)
    sys.exit(0)

# ---------------------------------------------------------------------------
# 3. LANCEMENT RÉEL : construire le SEP (comme pending/sep_boot.sh), le démarrer,
#    apprendre les tampons A/B, puis rejouer.
# ---------------------------------------------------------------------------
from m1n1.proxy import UartInterface, M1N1Proxy
from m1n1.proxyutils import ProxyUtils, bootstrap_port
from m1n1.hw.sep import SEP, SEPMessage
from m1n1.trace.asc import ASCRegs
from collections import defaultdict, deque

iface = UartInterface(); p = M1N1Proxy(iface, debug=False); bootstrap_port(iface, p)
u = ProxyUtils(p)

# DART : constantes de disposition publique (cf. hv/trace_sep_filtered.py, lui-même d'après
# m1n1 hw/dart8020.py). On traduit IOVA->PA par parcours de table (lectures), puis writemem.
DART_TCR, DART_TTBR, DART_PAGE = 0x100, 0x200, 0x4000
TCR_TRANSLATE_ENABLE, TCR_BYPASS_DART = 1 << 7, 1 << 8
TTBR_VALID, TTBR_ADDR_MASK = 1 << 31, (1 << 31) - 1
PTE_OFFSET = {"dart,t8020": (14, 39), "dart,t6000": (10, 39)}
OOL_CNTL_TYPES = {0x02: ("A", "iova"), 0x04: ("A", "size"), 0x03: ("B", "iova"), 0x05: ("B", "size")}
CNTL_EP = 0

ram_lo = u.adt["/chosen"].dram_base
ram_hi = ram_lo + u.adt["/chosen"].dram_size
dart_node = u.adt["/arm-io/dart-sep"]
dart_base = dart_node.get_reg(0)[0]
compat = dart_node.compatible[0]
pte_lo, pte_hi = PTE_OFFSET[compat]
pte_mask = (1 << (pte_hi - pte_lo + 1)) - 1

def _check(pa, size):
    if not (ram_lo <= pa and pa + size <= ram_hi):
        raise RuntimeError(f"PA 0x{pa:x}+0x{size:x} hors RAM")

def _pte(table_pa, idx):
    pa = table_pa + 8 * idx; _check(pa, 8)
    return struct.unpack("<Q", iface.readmem(pa, 8))[0]

def translate_page(sid, iova):
    tcr = p.read32(dart_base + DART_TCR + 4 * sid)
    if tcr & TCR_BYPASS_DART or not tcr & TCR_TRANSLATE_ENABLE:
        return None
    if (iova >> 36) >= 4:
        return None
    ttbr = p.read32(dart_base + DART_TTBR + 16 * sid + 4 * (iova >> 36))
    if not ttbr & TTBR_VALID:
        return None
    l1 = _pte((ttbr & TTBR_ADDR_MASK) << 12, (iova >> 25) & 0x7FF)
    if not l1 & 1:
        return None
    l2 = _pte(((l1 >> pte_lo) & pte_mask) << 14, (iova >> 14) & 0x7FF)
    if not l2 & 1:
        return None
    return ((l2 >> pte_lo) & pte_mask) << 14

def find_sid(iova):
    for sid in range(16):
        try:
            pa = translate_page(sid, iova & ~(DART_PAGE - 1))
        except RuntimeError:
            continue
        if pa is not None:
            return sid
    raise RuntimeError(f"IOVA 0x{iova:x} non mappée dans aucun stream")

def dart_read(sid, iova, size):
    out = []; cur, end = iova, iova + size
    while cur < end:
        page = cur & ~(DART_PAGE - 1); n = min(end, page + DART_PAGE) - cur
        pa = translate_page(sid, page)
        if pa is None:
            raise RuntimeError(f"page IOVA 0x{page:x} non mappée")
        pa += cur - page; _check(pa, n); out.append(iface.readmem(pa, n)); cur += n
    return b"".join(out)

def dart_write(sid, iova, data):
    """ÉCRITURE dans le tampon du SEP : traduction IOVA->PA puis writemem, page par page.
    Seule différence avec la lecture du traceur : writemem au lieu de readmem."""
    cur, end = iova, iova + len(data); off = 0
    while cur < end:
        page = cur & ~(DART_PAGE - 1); n = min(end, page + DART_PAGE) - cur
        pa = translate_page(sid, page)
        if pa is None:
            raise RuntimeError(f"page IOVA 0x{page:x} non mappée (écriture refusée)")
        pa += cur - page; _check(pa, n)
        iface.writemem(pa, data[off:off + n]); off += n; cur += n

# --- construction manuelle du SEP (dart_init signature correcte, cf. sep_boot.sh) ---
sep = SEP.__new__(SEP)
sep.i, sep.p, sep.u = iface, p, u
sep.sep_base = u.adt["/arm-io/sep"].get_reg(0)[0]
sep.dart_base = dart_base
sep.asc = ASCRegs(u, sep.sep_base)
sep.dart_handle = p.request(p.P_DART_INIT, sep.dart_base, 0, 0, 2)  # T6000
sep.epnum2name, sep.epname2num, sep.msgs = {}, {}, defaultdict(deque)

# --- rôle AP (v2) : amorçage EP 0 (CNTL) + ALLOCATION/ANNONCE des tampons OOL de l'EP 0x13 ---
# Protocole : docs/kext_sepmanager.md §3/§5 (source: kext). tag = slot+1 (pool de 8) ;
# acquittement = < EP0 TYPE 0x01 de même tag ; ordre A(taille 0x04, adresse 0x02) puis
# B(taille 0x05, adresse 0x03), param = endpoint cible (0x13). C'est l'AP qui ALLOUE A et B
# dans sa mémoire et les DONNE au SEP (le SEP ne les choisit pas).
cntl_acks = set()
cntl_tag = [0]

def pump_ep0():
    """Draine l'EP 0 sans bloquer : mémorise les acquittements (TYPE 0x01), répond au NAP
    (0x11 -> NAP_OK 0x12), ignore les notifications (OS-actif 0x0d/0x15, 0x10...)."""
    sep._try_recv_msgs()
    while sep.msgs[CNTL_EP]:
        m = sep.msgs[CNTL_EP].popleft()
        if m.TYPE == 0x01:
            cntl_acks.add(m.TAG)
        elif m.TYPE == 0x11:
            sep.send_msg(SEPMessage(EP=0, TAG=m.TAG, TYPE=0x12))

def cntl_send(typ, data, param, label, timeout_s=5):
    cntl_tag[0] = cntl_tag[0] % 8 + 1
    tag = cntl_tag[0]
    sep.send_msg(SEPMessage(EP=0, TAG=tag, TYPE=typ, PARAM=param, DATA=data))
    t = time.time()
    while time.time() - t < timeout_s:
        pump_ep0()
        if tag in cntl_acks:
            cntl_acks.discard(tag); return True
        time.sleep(0.01)
    return False

print("démarrage du SEP par m1n1 (séquence publique)...", flush=True)
sep.boot()
print("BOOT OK", flush=True)

# attendre que le SEP annonce ses endpoints (0xFD) ; on veut xarm = 0x13
t0 = time.time()
while time.time() - t0 < 8:
    pump_ep0()
    if 0x13 in sep.epnum2name:
        break
    time.sleep(0.02)
if 0x13 not in sep.epnum2name:
    print(f"ERREUR: le SEP n'a pas annoncé l'EP 0x13 (xarm). Endpoints={sep.epnum2name}. "
          f"Abandon, rien de plus envoyé.", flush=True)
    sys.exit(2)
print("xarm (0x13) annoncé. Endpoints : "
      + ", ".join(f"0x{n:02x}:{nm}" for n, nm in sorted(sep.epnum2name.items())), flush=True)

# Amorçage : SECMODE_REQUEST (CNTL TYPE 0x14, param=0). VALIDÉ sur la capture cntl-study3 :
# le SEP poste OS-actif (0x0d), puis l'AP envoie > EP0 TYPE 0x14, le SEP répond < TYPE 0x01
# DATA=mode (3). Le SEP fait ça AVANT d'accepter la mise en place des tampons.
if not cntl_send(0x14, 0, 0x00, "SECMODE"):
    print("ERREUR: pas d'acquittement SECMODE (CNTL 0x14) en 5 s. Abandon, rien de plus envoyé.", flush=True)
    sys.exit(3)
print("  SECMODE acquitté", flush=True)

# Allouer A (envoi AP->SEP) et B (réception SEP->AP), 0x8000 chacun (c24), init à zéro,
# et les mapper dans le DART du SEP. IOVA = celles de macOS (c24) ; à ajuster si xarm ne lit
# pas A (inconnu de fond, cf. docs/voie_c_design.md « Correctif voie C »).
SIZE = 0x8000
IOVA_A, IOVA_B = 0x2c000, 0x38000
phys_A = u.heap.memalign(0x4000, SIZE)
phys_B = u.heap.memalign(0x4000, SIZE)
iface.writemem(phys_A, b"\x00" * SIZE)
iface.writemem(phys_B, b"\x00" * SIZE)
p.dart_map(sep.dart_handle, IOVA_A, phys_A, SIZE)
p.dart_map(sep.dart_handle, IOVA_B, phys_B, SIZE)
print(f"tampons mappés : A iova=0x{IOVA_A:x}<-phys=0x{phys_A:x} | "
      f"B iova=0x{IOVA_B:x}<-phys=0x{phys_B:x}", flush=True)

# Annoncer au SEP : A taille puis adresse, B taille puis adresse — chacun acquitté.
for label, typ, data in [("A taille", 0x04, SIZE), ("A adresse", 0x02, IOVA_A >> 12),
                         ("B taille", 0x05, SIZE), ("B adresse", 0x03, IOVA_B >> 12)]:
    if not cntl_send(typ, data, 0x13, label):
        print(f"ERREUR: pas d'acquittement du CNTL {label} (TYPE 0x{typ:02x}) en 5 s. "
              f"Le SEP n'a pas accepté la mise en place des tampons. Abandon.", flush=True)
        sys.exit(3)
    print(f"  CNTL {label} : acquitté", flush=True)

bufs = {"A": {"iova": IOVA_A, "size": SIZE, "sid": find_sid(IOVA_A)},
        "B": {"iova": IOVA_B, "size": SIZE, "sid": find_sid(IOVA_B)}}
print(f"tampons prêts : A sid={bufs['A']['sid']} | B sid={bufs['B']['sid']}", flush=True)

def write_A(path):
    data = open(path, "rb").read()
    data = data[:bufs["A"]["size"]]
    dart_write(bufs["A"]["sid"], bufs["A"]["iova"], data)

def next_sep_13(timeout_s=10):
    t = time.time()
    while time.time() - t < timeout_s:
        pump_ep0()
        if sep.msgs[0x13]:
            return sep.msgs[0x13].popleft()
        time.sleep(0.01)
    return None

import hashlib
def read_B(n=0x400):
    """LECTURE SEULE du tampon B (SEP->AP). On lit directement phys_B (qu'on a alloué et mappé
    en IOVA_B) : aucun message envoyé, strictement équivalent au readmem du traceur. Renvoie
    (nbytes_non_nuls_sur_n, sha8, 32_premiers_octets_hex)."""
    try:
        data = iface.readmem(phys_B, n)
    except Exception as e:
        return (-1, "????????", f"<lecture B impossible: {e}>")
    nz = sum(1 for b in data if b)
    sha = hashlib.sha256(data).hexdigest()[:8]
    return (nz, sha, data[:32].hex())

def observe_loop(seconds=20):
    """ESSAI A : après la divergence, on N'ENVOIE RIEN sur 0x13 (surtout pas d'acquittement de
    SAVE, qui pourrait avancer le compteur anti-rejeu et périmer le S_new). On draine passivement
    les messages 0x13 du SEP et, pour chacun, on LIT B (read-only). pump_ep0 ne touche que l'EP 0
    (NAP keepalive), jamais 0x13. But : identifier ce que le SEP demande après les 4 lockers."""
    print(f"--- OBSERVATION {seconds}s (lecture seule, RIEN envoyé sur 0x13) ---", flush=True)
    seen = []
    t0 = time.time()
    while time.time() - t0 < seconds:
        pump_ep0()
        while sep.msgs[0x13]:
            m = sep.msgs[0x13].popleft()
            nz, sha, head = read_B()
            kind = {0x05: "FETCH", 0x01: "SAVE", 0x06: "SAVE2", 0x07: "?07"}.get(m.TYPE, "?")
            print(f"  SEP> TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} "
                  f"DATA=0x{m.DATA:08x} [{kind}]  B: nz={nz} sha={sha} head={head}", flush=True)
            seen.append((m.TYPE, nz))
        time.sleep(0.02)
    if seen:
        saves = sum(1 for t, _ in seen if t in (0x01, 0x06))
        fetches = sum(1 for t, _ in seen if t == 0x05)
        big = [nz for t, nz in seen if nz > 100]
        print(f"--- bilan observation : {len(seen)} messages SEP (FETCH={fetches}, SAVE={saves}). "
              f"B gros (>100 o non nuls) : {big} ---", flush=True)
        print("  Lecture : B~16 o = FETCH (UUID demandé) ; B~800+ o = SAVE (blob frais à sceller). "
              "SAVE juste après 4 FETCH = le SEP sous Linux ne réclame que 4 lockers (voie C vivante).",
              flush=True)
    else:
        print("--- bilan observation : AUCUN message 0x13 reçu pendant l'écoute "
              "(le SEP attend peut-être une réponse qu'on ne donne pas, ou s'est arrêté) ---", flush=True)

# ---------------------------------------------------------------------------
# 4. REJEU : on suit la séquence enregistrée. Pour chaque 'recv' on attend une
#    requête du SEP ; pour chaque 'send' on écrit le locker dans A (si la capture
#    l'a fait à ce pas) puis on renvoie le message exact.
# ---------------------------------------------------------------------------
print("--- début du rejeu EP 0x13 ---", flush=True)
replay_done = 0        # nb de réponses 'send' réellement renvoyées au SEP
replay_total = sum(1 for s in steps if s[0] == 'send')
diverged = False       # le SEP a-t-il divergé de la capture ?
for idx, s in enumerate(steps):
    if s[0] == 'recv':
        m = next_sep_13()
        if m is None:
            print(f"[{idx}] timeout en attente d'une requête SEP (attendu TAG=0x{s[1]:02x}). Arrêt.", flush=True)
            diverged = True
            break
        if m.TAG != s[1] or m.TYPE != s[2]:
            # Échec FERMÉ : si le SEP sous m1n1 diverge de la capture, on NE continue PAS à
            # pousser des réponses enregistrées (ça mettrait le SEP dans un état non maîtrisé).
            extra = ""
            if OBSERVE:
                nz, sha, head = read_B()
                extra = f"  [message complet : PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x} ; B: nz={nz} sha={sha} head={head}]"
            print(f"[{idx}] DIVERGENCE après {replay_done} lockers rejoués : reçu TAG=0x{m.TAG:02x} "
                  f"TYPE=0x{m.TYPE:02x}, attendu TAG=0x{s[1]:02x} TYPE=0x{s[2]:02x}. "
                  f"Rien de plus envoyé au SEP.{extra}", flush=True)
            diverged = True
            break
    else:
        tag, typ, param, data, a_path = s[1], s[2], s[3], s[4], s[5]
        if a_path:
            write_A(a_path)
        sep.send_msg(SEPMessage(EP=0x13, TAG=tag, TYPE=typ, PARAM=param, DATA=data))
        replay_done += 1

print(f"--- rejeu terminé ({replay_done}/{replay_total} réponses rejouées"
      f"{', DIVERGENCE' if diverged else ''}) ---", flush=True)

# ESSAI A : après le rejeu (divergé ou complet), on observe passivement ce que le SEP demande,
# SANS rien lui renvoyer sur 0x13. Sinon, simple écoute des annonces d'endpoints (EP 0).
if OBSERVE:
    observe_loop(20)
else:
    print("--- écoute 10 s des endpoints ---", flush=True)
    t0 = time.time()
    while time.time() - t0 < 10:
        pump_ep0(); time.sleep(0.03)

print("Endpoints annoncés par le SEP :", flush=True)
for num, name in sorted(sep.epnum2name.items()):
    star = "  <-- BIOMÉTRIE !" if name == "sbio" else ""
    print(f"  0x{num:02x} {name}{star}", flush=True)
# ATTENTION : la présence de sbio NE prouve PAS à elle seule que le rejeu est accepté.
# On ne peut parler de "rejeu accepté" que si le rejeu s'est déroulé SANS divergence.
# (Essai 1, 2026-11-11 : 4 lockers rejoués — dont SEP-xART et USER-xART — puis le SEP a
#  divergé à la 5e transaction (TAG=0x05 TYPE=0x01=SAVE au lieu de TYPE=0x05=FETCH). sbio
#  a été annoncé pendant cet échange partiel, au point normal, PAS depuis les seuls tampons.
#  "annoncé" != "fonctionnel" ; sks (0x12) restait absent.)
sbio_la = "sbio" in sep.epname2num
if sbio_la and not diverged and replay_done == replay_total:
    print(">>> sbio PRÉSENT après un rejeu COMPLET sans divergence : rejeu plausiblement accepté.", flush=True)
elif sbio_la and (diverged or replay_done < replay_total):
    print(f">>> sbio PRÉSENT MAIS le rejeu a divergé/avorté ({replay_done}/{replay_total}). "
          f"sbio ne vient donc PAS du contenu rejoué : réveil obtenu par le boot SEP + mise en "
          f"place des tampons seuls. À interpréter avec le sceptique, NE PAS conclure 'voie C gagnée'.", flush=True)
else:
    print(">>> sbio ABSENT. Le réveil de la biométrie n'a pas eu lieu ici.", flush=True)
PY

# Logs d'une écriture SEP en lecture seule (policy « traces/ en lecture seule après capture »).
if [ "$SELFTEST" != 1 ] && [ -n "${OUT:-}" ]; then
  chmod a-w "$OUT"/*.log 2>/dev/null || true
fi
echo "Terminé. Quel que soit le résultat : ne rien renvoyer, couper, redémarrer le Mac."
