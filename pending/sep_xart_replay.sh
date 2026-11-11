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
# ÉTAT : v1, NON LANÇABLE EN L'ÉTAT — BLOCAGE identifié par le sceptique (2026-11-11) :
#   >>> Le script croit APPRENDRE du SEP les adresses (IOVA) des tampons A/B. FAUX : dans la
#       capture, ces IOVA sont annoncées AP->SEP (c'est macOS qui ALLOUE les tampons dans SA
#       mémoire mappée DART et les DONNE au SEP via 4 messages CNTL). Donc en l'état,
#       buffers_ready() reste faux -> sortie propre « tampons A/B non appris », SANS rien
#       écrire au SEP (donc sûr), mais SANS tester voie C.
#   >>> CORRECTIF À FAIRE (refonte, pas retouche) : ajouter le rôle AP = allouer A (0x8000) et
#       B (0x8000) sur le heap m1n1, les dart_map à des IOVA qu'on choisit, puis ÉMETTRE les 4
#       CNTL (EP 0, PARAM=0x13) : TYPE 0x04 DATA=taille_A ; TYPE 0x02 DATA=iova_A>>12 ;
#       TYPE 0x05 DATA=taille_B ; TYPE 0x03 DATA=iova_B>>12. Puis seulement le rejeu des lockers.
#   >>> INCONNU à lever d'abord (capture non filtrée sur USB, ou désassemblage AppleSEPManager
#       en phase 2) : le TAG de ces CNTL et l'éventuel échange d'amorçage (le SEP demande-t-il
#       les tampons, ou l'AP les pousse-t-il ?). Voir docs/voie_c_design.md « Correctif voie C ».
#
#   À faire AVANT lancement : (a) écrire le correctif ci-dessus ; (b) relecture sceptique + Albert ;
#   (c) SELFTEST ; (d) Albert lance lui-même (jamais un agent).
#
# PRÉCONDITION capture S_new : SEP_OOL_BYTES >= taille du tampon A (0x8000), sinon les .bin
#   sont tronqués et A serait rejoué incomplet. (c24/c21 utilisaient bien 0x8000.)
#
# Usage :
#   ./pending/sep_xart_replay.sh <dossier_capture_S_new>      # lancement réel (Albert)
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

bufs = {"A": {"iova": None, "size": None, "sid": None},
        "B": {"iova": None, "size": None, "sid": None}}

def learn_cntl():
    """Apprend les IOVA/tailles des tampons A/B de l'EP 0x13 depuis les messages CNTL
    reçus (TYPE 2/3/4/5, PARAM=0x13). iova = DATA<<12 ; size = DATA. Comme le traceur."""
    for msg in list(sep.msgs[CNTL_EP]):
        if msg.TYPE in OOL_CNTL_TYPES and msg.PARAM == 0x13:
            buf, field = OOL_CNTL_TYPES[msg.TYPE]
            val = (msg.DATA << 12) if field == "iova" else msg.DATA
            if bufs[buf][field] != val:
                bufs[buf][field] = val; bufs[buf]["sid"] = None
    sep.msgs[CNTL_EP].clear()

def buffers_ready():
    return all(bufs[b]["iova"] is not None and bufs[b]["size"] for b in ("A", "B"))

print("démarrage du SEP par m1n1 (séquence publique)...", flush=True)
sep.boot()
print("BOOT OK", flush=True)

# laisser arriver les annonces d'endpoints + les CNTL d'init des tampons
t0 = time.time()
while time.time() - t0 < 5:
    sep._try_recv_msgs(); learn_cntl()
    if buffers_ready():
        break
    time.sleep(0.02)
if not buffers_ready():
    print(f"ERREUR: tampons A/B non appris (A={bufs['A']}, B={bufs['B']}). "
          f"Le SEP n'a pas annoncé l'EP 0x13 ? Abandon, rien de plus envoyé.", flush=True)
    sys.exit(2)
for b in ("A", "B"):
    bufs[b]["sid"] = find_sid(bufs[b]["iova"])
print(f"tampons appris : A iova=0x{bufs['A']['iova']:x} size=0x{bufs['A']['size']:x} "
      f"sid={bufs['A']['sid']} | B iova=0x{bufs['B']['iova']:x} sid={bufs['B']['sid']}", flush=True)

def write_A(path):
    data = open(path, "rb").read()
    data = data[:bufs["A"]["size"]]
    dart_write(bufs["A"]["sid"], bufs["A"]["iova"], data)

def next_sep_13(timeout_s=10):
    t = time.time()
    while time.time() - t < timeout_s:
        sep._try_recv_msgs(); learn_cntl()
        if sep.msgs[0x13]:
            return sep.msgs[0x13].popleft()
        time.sleep(0.01)
    return None

# ---------------------------------------------------------------------------
# 4. REJEU : on suit la séquence enregistrée. Pour chaque 'recv' on attend une
#    requête du SEP ; pour chaque 'send' on écrit le locker dans A (si la capture
#    l'a fait à ce pas) puis on renvoie le message exact.
# ---------------------------------------------------------------------------
print("--- début du rejeu EP 0x13 ---", flush=True)
for idx, s in enumerate(steps):
    if s[0] == 'recv':
        m = next_sep_13()
        if m is None:
            print(f"[{idx}] timeout en attente d'une requête SEP (attendu TAG=0x{s[1]:02x}). Arrêt.", flush=True)
            break
        if m.TAG != s[1] or m.TYPE != s[2]:
            # Échec FERMÉ : si le SEP sous m1n1 diverge de la capture, on NE continue PAS à
            # pousser des réponses enregistrées (ça mettrait le SEP dans un état non maîtrisé).
            print(f"[{idx}] DIVERGENCE: reçu TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x}, "
                  f"attendu TAG=0x{s[1]:02x} TYPE=0x{s[2]:02x}. Arrêt immédiat, rien de plus "
                  f"envoyé au SEP.", flush=True)
            break
    else:
        tag, typ, param, data, a_path = s[1], s[2], s[3], s[4], s[5]
        if a_path:
            write_A(a_path)
        sep.send_msg(SEPMessage(EP=0x13, TAG=tag, TYPE=typ, PARAM=param, DATA=data))

print("--- rejeu terminé, écoute 10 s des endpoints ---", flush=True)
t0 = time.time()
while time.time() - t0 < 10:
    sep._try_recv_msgs(); learn_cntl(); time.sleep(0.03)

print("Endpoints annoncés par le SEP :", flush=True)
for num, name in sorted(sep.epnum2name.items()):
    star = "  <-- BIOMÉTRIE !" if name == "sbio" else ""
    print(f"  0x{num:02x} {name}{star}", flush=True)
if "sbio" in sep.epname2num:
    print(">>> sbio PRÉSENT : le rejeu est accepté, Touch ID atteignable sous Linux.", flush=True)
else:
    print(">>> sbio ABSENT : le SEP a refusé le rejeu (ou vérifie plus). Voie C close.", flush=True)
PY

# Logs d'une écriture SEP en lecture seule (policy « traces/ en lecture seule après capture »).
if [ "$SELFTEST" != 1 ] && [ -n "${OUT:-}" ]; then
  chmod a-w "$OUT"/*.log 2>/dev/null || true
fi
echo "Terminé. Quel que soit le résultat : ne rien renvoyer, couper, redémarrer le Mac."
