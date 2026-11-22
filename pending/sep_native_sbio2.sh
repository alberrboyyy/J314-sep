#!/usr/bin/env bash
# =============================================================================
# sep_native_sbio2.sh — ROUTE NATIVE + sbio AU-DELÀ DU 0x73 : rejouer, DANS L'ORDRE de c12,
#   les commandes sbio (EP 0x08) qui NE touchent NI le capteur NI un blob NI un doigt,
#   puis S'ARRÊTER au 1er mur (relais capteur / blob / doigt) en DUMPANT ce que le SEP présente.
#
# ─────────────────────────────────────────────────────────────────────────────
# EN LANGAGE CLAIR (décision go / no-go — Albert)
#   BUT : on a prouvé cette nuit (n=3, vérifié) que, par la route native, sbio répond au « bonjour »
#   0x73 EXACTEMENT comme macOS. Ce script-ci va UN cran plus loin, SANS DOIGT : il refait toute la
#   route native (comme sep_native_sbio.sh), redit le 0x73, PUIS tente de rejouer les commandes
#   suivantes que macOS envoie à sbio — MAIS seulement celles qui n'ont besoin NI du capteur Touch ID,
#   NI d'un gros fichier (blob) de macOS, NI d'un doigt. Dès que la prochaine commande attendue est
#   une de ces trois (capteur / blob / doigt), le script S'ARRÊTE et PHOTOGRAPHIE ce que le SEP
#   demande à cet instant (le message + le contenu des tampons A8/B8), pour qu'on sache la FORME
#   EXACTE de la 1re requête « parle au capteur » et qu'on code le relais SPI au script SUIVANT.
#
#   HONNÊTETÉ (réduction de portée imposée par la capture) : dans la trace de référence c12, la TOUTE
#   PREMIÈRE commande que macOS envoie à sbio APRÈS le 0x73 est déjà une commande capteur (0x17
#   prepareSession = « lis le n° de série du capteur sur SPI » = classe [SPI], docs/sbio_sequence.md §1.1).
#   Il n'y a DONC, dans l'ordre de c12, AUCUNE commande « sans capteur » à rejouer entre le 0x73 et ce
#   1er mur. En pratique ce script ne rejoue donc RIEN de plus que le 0x73, puis s'arrête IMMÉDIATEMENT
#   au mur 0x17 et le dumpe. C'est voulu : mieux vaut court et sûr que deviné. La valeur du run = voir,
#   SUR MATÉRIEL et en route native, ce que le SEP présente à ce point précis (demande-t-il quelque chose
#   spontanément ? que contiennent les tampons ?), + joindre la forme exacte du 0x17 lue dans la capture.
#
#   CE QUI EST ÉCRIT (⚠️ identique à sep_native_sbio.sh / persist — MÊME classe de risque, récupérable) :
#     - Booter le firmware SEP (IMG4) : écriture SEP, routine depuis des semaines.
#     - Acquitter les SAVE (0x01/0x06) fait AVANCER le compteur anti-rejeu scellé du SEP : irréversible
#       au sens « on ne revient pas en arrière sur le compteur ». MÊME chose que persist.
#     - Le 0x73 et toute commande REJOUÉE sont des commandes sbio BÉNIGNES (classe [AP]/[SEP] : init,
#       cache, politique) SANS capteur, SANS blob, SANS doigt, SANS enrôlement, SANS match. On lit la
#       réponse et on dumpe ; on n'acquitte RIEN après la lecture.
#     - AUCUN DOIGT, AUCUN enrôlement, AUCUN match. On S'ARRÊTE AVANT la 1re commande capteur/blob/doigt.
#     - Récupération : through-SEP = quasi toujours réparable par DFU (voie C), PAS garanti à 100 %
#       (Stockholm / inconnus). Backup + IPSW prêts. macOS sera désynchronisé — on s'en fiche (ne boote
#       déjà plus). Linux : aucun risque.
#     - Budget de SAVE BORNÉ (MAX_SAVES, défaut 48) + budget d'étapes sbio BORNÉ (PHASE3_MAX_STEPS).
#     - Fail-closed PARTOUT : SAVE au-delà du budget, op EP 0x13 inconnue, CNTL d'ouverture sbio non
#       acquitté, 0x73 sans réponse, OOL manquant, réponse sbio inattendue, 1re commande [SPI]/[BLOB]/
#       [FINGER] → on N'ENVOIE RIEN de plus et on s'arrête (en dumpant au mur).
#
#   CE QUE ÇA N'EST PAS : pas du rejeu de coffre macOS. On part d'un store VIDE (xart_store_sbio2, À PART),
#     le SEP crée SON propre état frais et on le garde. Les OOL rejoués sont relus OCTET POUR OCTET depuis
#     la capture c12 = DONNÉES, pas du code Apple, pas de payload fabriqué à la main. « sbio accepte l'init »
#     ≠ « Touch ID marche » : il restera le relais capteur SPI, les blobs, puis un vrai match + l'enrôlement.
#
#   ENDPOINTS TOUCHÉS : 0x00 (CNTL, amorçage), 0x13 (xART/gigalocker, comme persist), 0x08 (sbio, sonde + déroulé).
#   RISQUE : identique à sep_native_sbio.sh (boot IMG4 + ACK SAVE = compteur avance). Rien de neuf côté écriture :
#     le « au-delà du 0x73 » n'ajoute que des commandes sbio bénignes en LECTURE de réponse, jamais un SAVE sbio.
#   RÉSULTAT ATTENDU : le script dumpe, dans $OUT/, l'état du SEP au 1er mur (= 0x17 [SPI], d'après c12) :
#     messages EP 0x08 spontanés éventuels + tampons A8/B8 + réf. capture du 0x17 (000303_08_A.bin). Message
#     clair « PROCHAIN MUR = [SPI] 0x17 prepareSession ». Au script suivant : coder le relais SPI (sensor_hw.md).
#   PRÉPARÉ PAR : Claude (Opus 4.8), 2026-11-22 — à relire et lancer par Albert, backup + DFU prêts.
#                 L'agent ne lance JAMAIS ce script en réel (uniquement SELFTEST=1 hors-ligne).
# ─────────────────────────────────────────────────────────────────────────────
#
# TECHNIQUE
#   PHASE 1 — NATIF (IDENTIQUE à sep_native_sbio.sh / sep_native_persist.sh) : ack recon, SERVIR/ABSENT
#     les FETCH, STOCKER+ACK les SAVE, boucle jusqu'à idle, budget MAX_SAVES, fail-closed sur op inconnue.
#   PHASE 2 — SONDE sbio (IDENTIQUE à sep_native_sbio.sh) : ouvrir l'EP 0x08 (A8/B8), écrire le 0x73 exact
#     (SBIO_A), l'envoyer, lire B8 + messages, verdict VIVANT/MUET. Renvoie le contexte (tampons) à la Phase 3.
#   PHASE 3 — DÉROULÉ post-0x73 (NOUVEAU) : parcourir la liste ordonnée des commandes sbio de c12 APRÈS le
#     0x73 (docs/sbio_sequence.md §1). Pour chaque étape de classe [AP]/[SEP] : écrire son OOL EXACT (relu de
#     la capture) dans A8, envoyer EP 0x08 TAG=0xfc/TYPE=opcode, lire la réponse, dumper. Au 1er [SPI]/[BLOB]/
#     [FINGER], ou à toute réponse inattendue : STOP + DUMP complet (messages + A8/B8 + réf. capture) + message
#     « PROCHAIN MUR = <classe> <opcode> ». Budget PHASE3_MAX_STEPS. fail-closed partout.
#     (D'après c12 : le 1er mur est l'étape 0 = 0x17 [SPI] ; le déroulé rejoue donc 0 commande et dumpe le mur.)
#
# RED LINES : aucune op disque sur le Mac, pas de dd/nvram/sudo/partition. Le store est un fichier sur CE PC.
#   m1n1 : lu, jamais modifié/poussé. Le SEP-write (boot IMG4 + SAVE-ack) = lancé par Albert (ce script, pending/).
#   On N'ENVOIE JAMAIS un SAVE vers sbio, ni une commande capteur/blob/doigt : STOP au mur.
#
# USAGE
#   SELFTEST=1 ./pending/sep_native_sbio2.sh   # hors-ligne : politique + liste ordonnée + où ça s'arrête. Ne touche pas le Mac.
#   ./tools/catch_proxy.sh                      # D'ABORD (Claude) : attrape le Mac en proxy (tu power-cycles)
#   ./pending/sep_native_sbio2.sh               # PUIS run RÉEL d'ÉCRITURE + déroulé (Albert lance)
#   Vars : MAX_SAVES=48 | IDLE=25 | XART_STORE=<dir> | OS_UUID_MODE=fixed|none | SBIO_A=<0x73.bin> |
#          SBIO_STREAM15=0|1 | C12_OOL=<dir ool c12> | PHASE3_MAX_STEPS=16 | WALL_LISTEN=4
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
# Store SÉPARÉ, DISTINCT de sep_native_sbio.sh (xart_store_sbio) ET de l'état précieux (xart_store_linux).
export XART_STORE="${XART_STORE:-$REPO_ROOT/xart_store_sbio2}"
# Poignée 0x73 rejouée OCTET POUR OCTET depuis la capture (pas de gt_packet construit à la main).
export SBIO_A="${SBIO_A:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000300_08_A.bin}"
# Dossier des OOL EP 0x08 de la capture c12 (source des octets EXACTS rejoués en Phase 3 = DONNÉES).
export C12_OOL="${C12_OOL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool}"
# Option diagnostic (défaut 0) : programmer AUSSI le stream 15 du dart-sep côté AP (aucune écriture SEP).
export SBIO_STREAM15="${SBIO_STREAM15:-0}"
# Budgets Phase 3 : nb max de commandes sbio rejouées, et durée d'écoute au mur.
export PHASE3_MAX_STEPS="${PHASE3_MAX_STEPS:-16}"
export WALL_LISTEN="${WALL_LISTEN:-4}"
export M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
mkdir -p "$XART_STORE"

if [ "$SELFTEST" != 1 ]; then
  [ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
  STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_native_sbio2"; mkdir -p "$OUT"; export OUT
  # Le Mac doit DÉJÀ être en proxy : lancer ./tools/catch_proxy.sh AVANT (Claude le fait + power-cycle).
  require_mac
fi

timeout 420 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "${OUT:-/tmp}/native_sbio2.log"
import os, sys, time, struct, glob
SELFTEST = os.environ["SELFTEST"] == "1"
OS_UUID_MODE = os.environ.get("OS_UUID_MODE", "fixed")
LINUX_OS_UUID = bytes.fromhex(os.environ["LINUX_OS_UUID"])
MAX_SAVES = int(os.environ.get("MAX_SAVES", "48"))
IDLE = int(os.environ.get("IDLE", "25"))
XART_STORE = os.environ["XART_STORE"]
SBIO_A = os.environ.get("SBIO_A", "")
C12_OOL = os.environ.get("C12_OOL", "")
SBIO_STREAM15 = os.environ.get("SBIO_STREAM15", "0") == "1"
PHASE3_MAX_STEPS = int(os.environ.get("PHASE3_MAX_STEPS", "16"))
WALL_LISTEN = int(os.environ.get("WALL_LISTEN", "4"))

OP_FWBOOT, OP_OSUUID, OP_FETCH_MASTER, OP_FETCH_GL = 0x0e, 0x13, 0x00, 0x05
OP_ABSENT, OP_ANNOUNCE, OP_SAVE_XART, OP_SAVE_LOCKER = 0x07, 0x1d, 0x01, 0x06
RESP_DONE, RESP_ANNOUNCE = 0x00, 0x16
ACK_MASK = 0xFFFFFF00
OPNAME = {OP_FWBOOT:"fw-boot", OP_OSUUID:"os-uuid", OP_FETCH_MASTER:"FETCH-maître",
          OP_FETCH_GL:"FETCH-locker", OP_ABSENT:"absent(SEP)", OP_ANNOUNCE:"annonce-EP",
          OP_SAVE_XART:"SAVE-xART", OP_SAVE_LOCKER:"SAVE-locker"}

def declen(param, data): return (param & 0xFF) | ((data & 0xFF) << 8)

# ---------------------------------------------------------------------------
# LISTE ORDONNÉE des commandes sbio APRÈS le 0x73, telle que lue dans docs/sbio_sequence.md §1.1
# (1re passe d'init) + VU dans la trace c12 (seq 303+). Chaque entrée :
#   (opcode, classe, nom, ool_A, ool_B)  — classe interprétée (sbio_sequence.md), noms source: kext.
#   ool_A/ool_B = fichiers OOL EXACTS de la capture (DONNÉES) quand résolus depuis la trace, sinon None.
# CLASSES : "AP"/"SEP" = rejouables ici (sans capteur/blob/doigt) ; "SPI"/"BLOB"/"FINGER" = MUR (STOP+dump).
# NOTE D'HONNÊTETÉ : la 1re entrée (0x17) est [SPI]. Donc, dans l'ordre de c12, le MUR tombe à l'étape 0 :
#   aucune commande [AP]/[SEP] n'est rejouable entre le 0x73 et ce 1er mur. La suite de la carte (§1.2 2e
#   passe capteur [SPI], §1.3 catacomb [BLOB] + requêtes clients [SEP]) est TOUTE postérieure à ce mur et
#   n'est donc pas atteignable en ordre c12 sans franchir le [SPI] ; on la liste ici pour transparence.
POST_0X73_STEPS = [
    # --- §1.1 : init + 1re passe capteur (seq trace vérifiés pour le bloc d'init) ---
    (0x17, "SPI", "prepareSession — n° serie capteur lu sur SPI", "000303_08_A.bin", "000304_08_B.bin"),
    (0x15, "SPI", "performKeyExchange (sessionType=1)",            "000305_08_A.bin", "000306_08_B.bin"),
    (0x16, "SPI", "performKeyExchange (2) — reponse capteur",      "000307_08_A.bin", "000308_08_B.bin"),
    (0x42, "SPI", "initializeSequenceCounter",                     "000309_08_A.bin", "000310_08_B.bin"),
    (0x18, "SPI", "compteur (reponse capteur)",                    "000311_08_A.bin", "000312_08_B.bin"),
    (0x5f, "SPI", "LoadPatch (patch capteur, OOL ~16Ko)",          "000313_08_A.bin", None),
    (0x5d, "SPI", "applySensorParams",                             None, None),
    (0x5c, "SPI", "applySensorParams (suite)",                     None, None),
    (0x6a, "SPI", "applySensorParams (suite)",                     None, None),
    (0x31, "SPI", "n0 serie module",                               None, None),
    (0x32, "SPI", "n0 serie module (2)",                           None, None),
    (0x01, "SPI", "fin loadPatch (etat capteur=3)",                None, None),
    (0x1f, "SEP", "cacheMatchPolicy",                              None, None),
    (0x31, "SPI", "n0 serie module (repete)",                      None, None),
    (0x32, "SPI", "n0 serie module (2, repete)",                   None, None),
    (0x5b, "BLOB","setCalibrationData (~64Ko)",                    None, None),
    # --- §1.2/§1.3 : TOUT ce qui suit est APRÈS le 1er mur (non atteignable en ordre c12). Résumé : ---
    #   §1.2 2e passe capteur : 0x63[SEP] 0x19[SPI] 0x17 0x15 0x16 0x42 0x18 0x5f 0x5d 0x5c 0x6a 0x6f 0x31
    #        0x32 0x01 [SPI] 0x1f[SEP]
    #   §1.3 catacomb + clients : 0x63[SEP] 0x7c[SEP] 0x6b/0x79[SEP] 0x6d[BLOB] 0x39/0x2b/0x54/0x33/0x36/
    #        0x6e/0x7a/0x28/0x7c/0x63/0x7d/0x0b[SEP] 0x71[BLOB]
]

# --- store xART sbio2 sur CE PC : maîtres par type (1/2), gigalockers par UUID + dump brut ---
store_masters = {}
store_gls = {}
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
    print("--- SELFTEST (hors-ligne, le Mac n'est pas touche) ---", flush=True)
    print(f"store xART sbio2 : {XART_STORE}  (maitres={len(glob.glob(os.path.join(XART_STORE,'master_*.bin')))}, "
          f"gl={len(glob.glob(os.path.join(XART_STORE,'gl_*.bin')))})  [SEPARE de xart_store_linux et xart_store_sbio]", flush=True)
    print("PHASE 1 — politique native PERSIST (identique a sep_native_sbio.sh) :", flush=True)
    print("  fw-boot/os-uuid/annonce/absent-SEP : ack ; FETCH : SERVIR si store sinon ABSENT ;", flush=True)
    print(f"  SAVE 0x01/0x06 : lire B, STOCKER, ACK (DATA&0xffffff00)  !! ECRITURE  (budget {MAX_SAVES})", flush=True)
    print(f"  boucle jusqu'a idle ({IDLE}s de silence) ; fail-closed sur op inconnue", flush=True)
    assert OS_UUID_MODE in ("fixed", "none") and len(LINUX_OS_UUID) == 16
    print("PHASE 2 — sonde sbio 0x73 (identique a sep_native_sbio.sh, seulement si idle ET 0x08 annonce) :", flush=True)
    if SBIO_A and os.path.exists(SBIO_A):
        b = open(SBIO_A, "rb").read()
        assert len(b) > 0x14, f"SBIO_A trop court ({len(b)} o)"
        assert b[0x00] == 1, f"SBIO_A +0x00={b[0x00]} (attendu 1)"
        assert b[0x14] == 0x73, f"SBIO_A +0x14={b[0x14]:#x} (attendu 0x73)"
        print(f"  SBIO_A verifie : {os.path.basename(SBIO_A)} = gt_packet 0x73 valide (+0x00=1, +0x14=0x73).", flush=True)
    else:
        print(f"  ERREUR — fichier SBIO_A introuvable : {SBIO_A!r}.", flush=True); raise SystemExit(1)
    print("PHASE 3 — deroule post-0x73 (NOUVEAU) : rejoue [AP]/[SEP] en ordre c12, STOP au 1er [SPI]/[BLOB]/[FINGER].", flush=True)
    print(f"  dossier OOL c12 : {C12_OOL}  (existe={os.path.isdir(C12_OOL)})", flush=True)
    print("  LISTE ORDONNEE des etapes post-0x73 (source: sbio_sequence.md §1 + trace c12) :", flush=True)
    wall_idx = None
    for i, (op, cls, name, oa, ob) in enumerate(POST_0X73_STEPS):
        mark = ""
        if cls in ("SPI", "BLOB", "FINGER") and wall_idx is None:
            wall_idx = i; mark = "   <<<<< STOP ICI (1er mur, on N'ENVOIE PAS)"
        act = "REJOUE" if cls in ("AP", "SEP") else "MUR"
        ref = ""
        if oa:
            exists = os.path.exists(os.path.join(C12_OOL, oa)) if C12_OOL else False
            ref = f"  [ref A={oa}{' OK' if exists else ' ABSENT'}]"
        print(f"    #{i:2d}  op=0x{op:02x}  [{cls:6s}]  {act:6s}  {name}{ref}{mark}", flush=True)
    print(f"  budget etapes = {PHASE3_MAX_STEPS} ; ecoute au mur = {WALL_LISTEN}s.", flush=True)
    if wall_idx == 0:
        op0 = POST_0X73_STEPS[0]
        print(f"  >>> VERDICT PLAN : d'apres c12, la 1re commande post-0x73 est deja un MUR "
              f"([{op0[1]}] op 0x{op0[0]:02x} {op0[2]}). Le deroule rejoue 0 commande [AP]/[SEP] et "
              f"DUMPE directement ce mur. (Reduction de portee HONNETE : aucune commande sans capteur "
              f"entre le 0x73 et la 1re commande capteur dans la trace de reference.)", flush=True)
        # Le dump du mur joindra la ref capture de l'etape 0 si presente :
        if op0[3]:
            pth = os.path.join(C12_OOL, op0[3])
            if os.path.exists(pth):
                rb = open(pth, "rb").read()
                oplen = rb[0x18] if len(rb) > 0x18 else None
                print(f"  >>> forme EXACTE du mur (ref capture {op0[3]}, {len(rb)}o) : gt_packet +0x00={rb[0] if rb else '?'} "
                      f"+0x14=0x{rb[0x14]:02x} (opcode) +0x18=0x{oplen:02x} (len charge) ; charge a +0x1c.", flush=True)
    else:
        print(f"  >>> VERDICT PLAN : 1er mur a l'etape #{wall_idx}.", flush=True)
    print("SELFTEST OK (rien envoye au SEP).", flush=True)
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
    raise RuntimeError("IOVA non mappee")
def dart_rw(sid, iova, data=None, size=0):
    read = data is None; end = iova + (size if read else len(data)); cur, off, out = iova, 0, []
    while cur < end:
        page = cur & ~(DART_PAGE-1); n = min(end, page+DART_PAGE) - cur
        pa = translate_page(sid, page)
        if pa is None: raise RuntimeError("page non mappee")
        pa += cur - page; _check(pa, n)
        if read: out.append(iface.readmem(pa, n))
        else: iface.writemem(pa, data[off:off+n]); off += n
        cur += n
    return b"".join(out) if read else None

# LECTURE SEULE de l'etat de faute du dart-sep (porte de sep_native_sbio.sh). read32 only, aucune ecriture.
DART_ERROR, DART_ERROR_ADDR_LO, DART_ERROR_ADDR_HI = 0x40, 0x50, 0x54
_DART_ERR_BITS = (("NO_DAPF_MATCH", 11), ("WRITE", 10), ("SUBPAGE_PROT", 7), ("PTE_READ_FAULT", 6),
                  ("READ_FAULT", 4), ("WRITE_FAULT", 3), ("NO_PTE", 2), ("NO_PMD", 1), ("NO_TTBR", 0))
def read_dart_fault():
    raw = p.read32(dart_base + DART_ERROR)
    addr = (p.read32(dart_base + DART_ERROR_ADDR_HI) << 32) | p.read32(dart_base + DART_ERROR_ADDR_LO)
    bits = [nm for nm, b in _DART_ERR_BITS if raw & (1 << b)]
    return {"raw": raw, "flag": (raw >> 31) & 1, "sid": (raw >> 24) & 0xf, "bits": bits, "addr": addr}
def print_dart_fault(label):
    f = read_dart_fault()
    print(f"  [DART-faute {label}] ERROR=0x{f['raw']:08x} FLAG={f['flag']} sid={f['sid']} "
          f"causes={','.join(f['bits']) or '-'} ADDR=0x{f['addr']:x}", flush=True)
    return f

print("demarrage du SEP par m1n1 (sequence publique, routine)...", flush=True)
sep.boot(); print("BOOT OK", flush=True)
t0 = time.time()
while time.time() - t0 < 8:
    pump_ep0()
    if 0x13 in sep.epnum2name: break
    time.sleep(0.02)
if 0x13 not in sep.epnum2name:
    print(f"ERREUR: EP 0x13 non annonce. {sep.epnum2name}. Abandon.", flush=True); sys.exit(2)
print("xarm (0x13) annonce : " + ", ".join(f"0x{n:02x}:{nm}" for n, nm in sorted(sep.epnum2name.items())), flush=True)
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
print(f"tampons prets (A sid={sid_A}, B sid={sid_B}). store: maitres={sorted(store_masters)}, gl={len(store_gls)}.", flush=True)

def write_A(data):
    iface.writemem(phys_A, b"\x00"*SIZE); dart_rw(sid_A, IOVA_A, data=data[:SIZE])

def send(m, typ, param, data): sep.send_msg(SEPMessage(EP=0x13, TAG=m.TAG, TYPE=typ, PARAM=param, DATA=data))

def serve_master(m):
    sel = (m.DATA >> 8) & 0xFF; mtype = 2 if (sel & 1) else 1
    pay = store_masters.get(mtype)
    if pay is None:
        write_A(b"\x00" * 0x11); send(m, RESP_DONE, 0x11, sel << 8); return f"ABSENT maitre t{mtype}"
    A = b"\x00" * 0x11 + pay; ln = len(A); write_A(A)
    send(m, RESP_DONE, ln & 0xFF, ((ln >> 8) & 0xFF) | (sel << 8)); return f"SERVI maitre t{mtype} ({ln}o)"

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
        mtype = 2 if (sel & 1) else 1; store_put_master(mtype, blob); tag = f"maitre t{mtype}"
    else:
        idx = len(gl_raw); gl_raw.append(blob)
        open(os.path.join(XART_STORE, f"glsave_{idx}.bin"), "wb").write(blob)
        tag = f"gigalocker brut #{idx}"
    send(m, RESP_DONE, 0x00, m.DATA & ACK_MASK)      # !! ACK : le compteur scelle avance
    return tag, ln

# ===========================================================================
# PHASE 2 — sonde sbio (0x73). IDENTIQUE a sep_native_sbio.sh, mais RENVOIE le contexte (tampons)
# a la Phase 3. A n'appeler qu'apres idle ET 0x08 annonce.
# Retour : dict {alive, phys_A8, phys_B8, IOVA_A8, IOVA_B8, sid_A8, SZ8} ou None.
# ===========================================================================
def probe_sbio():
    print("=== PHASE 2 — SONDE sbio (0x73, sans doigt, une seule commande) ===", flush=True)
    if 0x08 not in sep.epnum2name:
        print("  sbio (0x08) n'est PAS annonce : rien a sonder.", flush=True); return None
    if not (SBIO_A and os.path.exists(SBIO_A)):
        print(f"  ERREUR: fichier SBIO_A introuvable ({SBIO_A!r}). On n'envoie RIEN.", flush=True); return None
    a_bytes = open(SBIO_A, "rb").read()
    if len(a_bytes) <= 0x14 or a_bytes[0x14] != 0x73 or a_bytes[0] != 1:
        print(f"  ERREUR: SBIO_A n'est pas un gt_packet 0x73. On n'envoie RIEN.", flush=True); return None

    SZ8 = 0x4000
    IOVA_A8, IOVA_B8 = 0x54000, 0x5c000
    try:
        phys_A8 = u.heap.memalign(0x4000, SZ8)
        phys_B8 = u.heap.memalign(0x4000, SZ8)
        iface.writemem(phys_A8, b"\x00" * SZ8)
        iface.writemem(phys_B8, b"\x00" * SZ8)
        p.dart_map(sep.dart_handle, IOVA_A8, phys_A8, SZ8)
        p.dart_map(sep.dart_handle, IOVA_B8, phys_B8, SZ8)
        if SBIO_STREAM15:
            dart_handle_15 = p.request(p.P_DART_INIT, sep.dart_base, 15, 0, 2)
            p.dart_map(dart_handle_15, IOVA_A8, phys_A8, SZ8)
            p.dart_map(dart_handle_15, IOVA_B8, phys_B8, SZ8)
            print("  E1 : stream 15 du dart-sep PROGRAMME ; A8/B8 mappes en sid 0 ET sid 15 "
                  "(ecriture DART cote AP seulement, aucune ecriture SEP).", flush=True)
    except Exception as e:
        print(f"  ERREUR a l'allocation/mapping des tampons sbio : {e}. On n'envoie RIEN.", flush=True); return None
    for label, typ, data in [("A8 taille", 0x04, SZ8), ("A8 adresse", 0x02, IOVA_A8 >> 12),
                             ("B8 taille", 0x05, SZ8), ("B8 adresse", 0x03, IOVA_B8 >> 12)]:
        if not cntl_send(typ, data, 0x08, label):
            print(f"  le SEP n'a PAS acquitte le CNTL {label} (ouverture sbio) en 5 s. On s'arrete, RIEN envoye.", flush=True)
            return {"alive": False}
        print(f"  CNTL {label} (ouverture sbio) : acquitte", flush=True)

    def _maps(sid):
        try: return translate_page(sid, IOVA_A8) is not None
        except RuntimeError: return False
    sids_A8 = [s for s in range(16) if _maps(s)]
    print(f"  A8 (IOVA 0x{IOVA_A8:x}) mappe dans les streams : {sids_A8}", flush=True)

    try:
        sid_A8 = find_sid(IOVA_A8)
        dart_rw(sid_A8, IOVA_A8, data=a_bytes[:SZ8])
    except Exception as e:
        print(f"  ERREUR a l'ecriture du 0x73 dans A8 : {e}. RIEN envoye.", flush=True); return {"alive": False}
    print(f"  0x73 ecrit dans A8 (depuis {os.path.basename(SBIO_A)}). Envoi...", flush=True)
    pump_ep0(); sep.msgs[0x08].clear()
    fault_before = print_dart_fault("avant 0x73 (baseline)")
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x73, PARAM=0x00, DATA=0x00000000))

    got = []
    t0 = time.time()
    while time.time() - t0 < 6:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft()
            got.append((m.TAG, m.TYPE))
            print(f"  SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} "
                  f"DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    fault_after = print_dart_fault("apres 0x73")
    changed = (fault_after["raw"] != fault_before["raw"]) or (fault_after["addr"] != fault_before["addr"])
    if fault_after["flag"] and (fault_before["flag"] == 0 or changed):
        print(f"  >>> FAUTE DART NEUVE apres le 0x73 : sid={fault_after['sid']} "
              f"causes={','.join(fault_after['bits']) or '-'} adresse=0x{fault_after['addr']:x}.", flush=True)
    try:
        b8 = iface.readmem(phys_B8, SZ8)
    except Exception as e:
        b8 = b""; print(f"  (lecture de B8 impossible : {e})", flush=True)
    nz = sum(1 for x in b8 if x)
    if b8 and os.environ.get("OUT"):
        try:
            with open(os.path.join(os.environ["OUT"], "sbio_probe_B.bin"), "wb") as f: f.write(b8)
        except Exception: pass
    b_ok = len(b8) > 0x14 and b8[0] == 1 and b8[0x14] == 0x73
    msg_ok = any(typ == 0x73 for _, typ in got) or any(tag == 0x04 for tag, _ in got)
    print(f"  B8 : {nz} octets non nuls ; tete={b8[:0x20].hex() if b8 else '-'}", flush=True)
    alive = bool(b_ok or msg_ok)
    if alive:
        print(">>> SONDE sbio : sbio a REPONDU au 0x73 (VIVANT sous m1n1). Comparer a c12 (B +0x00=1, +0x14=0x73). "
              "NE PAS conclure 'Touch ID marche' : reste init capteur, blobs, match, enrolement.", flush=True)
    else:
        print(">>> SONDE sbio : AUCUNE reponse au 0x73 (B8 nul, aucun message EP 0x08). sbio ANNONCE mais muet ici.", flush=True)
    return {"alive": alive, "phys_A8": phys_A8, "phys_B8": phys_B8,
            "IOVA_A8": IOVA_A8, "IOVA_B8": IOVA_B8, "sid_A8": (sid_A8 if 'sid_A8' in dir() else None), "SZ8": SZ8}

# ===========================================================================
# PHASE 3 — deroule post-0x73 : rejoue [AP]/[SEP] en ordre c12, STOP au 1er [SPI]/[BLOB]/[FINGER].
# ===========================================================================
def _hexhead(b, n=0x40): return b[:n].hex() if b else "-"

def read_c12_ool(fn):
    if not (fn and C12_OOL): return None
    pth = os.path.join(C12_OOL, fn)
    return open(pth, "rb").read() if os.path.exists(pth) else None

def dump_wall(ctx, step, idx):
    op, cls, name, oa, ob = step
    outdir = os.environ.get("OUT")
    print(f"  --- DUMP du mur (etape #{idx}, op=0x{op:02x} [{cls}] {name}) ---", flush=True)
    # 1. ce que le SEP demande spontanement sur EP 0x08 (route native : le SEP peut piloter, cf. EP 0x13)
    pump_ep0()
    spont = []
    t0 = time.time()
    while time.time() - t0 < WALL_LISTEN:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft()
            spont.append((m.TAG, m.TYPE, m.PARAM, m.DATA))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    if not spont:
        print("    (aucun message EP 0x08 spontane apres le 0x73 : le SEP ATTEND que l'AP pilote la commande "
              "suivante, comme macOS. La commande suivante attendue = ce mur.)", flush=True)
    # 2. etat LIVE des tampons A8/B8 (ce que le SEP a laisse)
    try:
        a8 = iface.readmem(ctx["phys_A8"], ctx["SZ8"])
        b8 = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
    except Exception as e:
        a8 = b8 = b""; print(f"    (lecture A8/B8 impossible : {e})", flush=True)
    print(f"    A8 (notre dernier envoi, 0x73) tete={_hexhead(a8)}", flush=True)
    print(f"    B8 (derniere sortie SEP)       tete={_hexhead(b8)}", flush=True)
    # 3. faute DART (lecture seule)
    print_dart_fault("au mur")
    # 4. reference capture c12 = DONNEES : forme EXACTE de la commande du mur cote macOS
    ref_a = read_c12_ool(oa); ref_b = read_c12_ool(ob)
    if ref_a is not None:
        oplen = ref_a[0x18] if len(ref_a) > 0x18 else None
        print(f"    ref capture c12 ({oa}, {len(ref_a)}o) = commande du mur cote macOS : gt_packet "
              f"+0x14=0x{ref_a[0x14]:02x} +0x18=0x{(oplen if oplen is not None else 0):02x} (len charge) ; "
              f"charge a +0x1c tete={_hexhead(ref_a[0x1c:0x1c+0x20])}", flush=True)
    # 5. ecrire les dumps
    if outdir:
        try:
            if a8: open(os.path.join(outdir, "wall_A8.bin"), "wb").write(a8)
            if b8: open(os.path.join(outdir, "wall_B8.bin"), "wb").write(b8)
            if ref_a is not None: open(os.path.join(outdir, f"wall_ref_{op:02x}_A.bin"), "wb").write(ref_a)
            if ref_b is not None: open(os.path.join(outdir, f"wall_ref_{op:02x}_B.bin"), "wb").write(ref_b)
            with open(os.path.join(outdir, "wall_summary.txt"), "w") as f:
                f.write(f"MUR post-0x73 (route native)\n")
                f.write(f"etape #{idx} op=0x{op:02x} classe=[{cls}] {name}\n")
                f.write(f"messages EP 0x08 spontanes du SEP : {spont}\n")
                f.write(f"A8_head={_hexhead(a8)}\nB8_head={_hexhead(b8)}\n")
                f.write(f"ref_capture_A={oa} ref_capture_B={ob}\n")
            print(f"    dumps ecrits dans {outdir}/ : wall_A8.bin wall_B8.bin "
                  f"{'wall_ref_%02x_A.bin ' % op if ref_a is not None else ''}wall_summary.txt", flush=True)
        except Exception as e:
            print(f"    (ecriture des dumps impossible : {e})", flush=True)

def replay_step(ctx, step, idx):
    """Rejoue une commande sbio [AP]/[SEP] avec son OOL EXACT. Renvoie True si reponse attendue, sinon STOP."""
    op, cls, name, oa, ob = step
    if not oa:
        print(f"  etape #{idx} op=0x{op:02x} [{cls}] : OOL A non resolu dans la table -> STOP "
              f"(fail-closed : on n'invente pas de payload).", flush=True); return False
    a_bytes = read_c12_ool(oa)
    if a_bytes is None:
        print(f"  etape #{idx} op=0x{op:02x} : OOL {oa} introuvable dans {C12_OOL} -> STOP (fail-closed).", flush=True); return False
    if len(a_bytes) <= 0x14 or a_bytes[0x14] != op:
        got = a_bytes[0x14] if len(a_bytes) > 0x14 else -1
        print(f"  etape #{idx}: OOL {oa} +0x14=0x{got:02x} != op 0x{op:02x} -> STOP (fail-closed).", flush=True); return False
    try:
        iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
        dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=a_bytes[:ctx["SZ8"]])
    except Exception as e:
        print(f"  etape #{idx}: ecriture A8 impossible : {e} -> STOP.", flush=True); return False
    pump_ep0(); sep.msgs[0x08].clear()
    print(f"  etape #{idx}: op=0x{op:02x} [{cls}] ({name}) : OOL {oa} ecrit dans A8, envoi EP 0x08...", flush=True)
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=op, PARAM=0x00, DATA=0x00000000))
    got = []; t0 = time.time()
    while time.time() - t0 < 4:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft(); got.append((m.TAG, m.TYPE))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    try:
        b8 = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
    except Exception:
        b8 = b""
    if b8 and os.environ.get("OUT"):
        try: open(os.path.join(os.environ["OUT"], f"step_{idx:02d}_{op:02x}_B.bin"), "wb").write(b8)
        except Exception: pass
    # macOS : chaque commande recoit une reponse '<' de meme TYPE. Sinon = inattendu -> STOP + dump.
    ok = any(typ == op for _, typ in got)
    print(f"    B8 tete={_hexhead(b8)} ; reponse de meme type 0x{op:02x} : {'OUI' if ok else 'NON'}", flush=True)
    if not ok:
        print(f"  etape #{idx}: reponse INATTENDUE (pas de '< 0x{op:02x}') -> STOP (fail-closed). Dump de l'etat :", flush=True)
        dump_wall(ctx, step, idx)
        return False
    return True

def phase3_replay(ctx):
    print("=== PHASE 3 — deroule post-0x73 (rejoue [AP]/[SEP] en ordre c12, STOP au 1er [SPI]/[BLOB]/[FINGER]) ===", flush=True)
    if not ctx or not ctx.get("alive"):
        print("  sbio pas VIVANT (0x73 sans reponse) : PHASE 3 non lancee (fail-closed).", flush=True); return
    if ctx.get("sid_A8") is None:
        print("  sid A8 inconnu : PHASE 3 non lancee (fail-closed).", flush=True); return
    sent = 0
    for idx, step in enumerate(POST_0X73_STEPS):
        op, cls, name, oa, ob = step
        if cls in ("SPI", "BLOB", "FINGER"):
            print(f"  etape #{idx}: op=0x{op:02x} classe=[{cls}] ({name}) = MUR. On N'ENVOIE PAS cette commande.", flush=True)
            dump_wall(ctx, step, idx)
            klass = {"SPI": "relais capteur SPI (sensor_hw.md)", "BLOB": "blob espace-utilisateur (capture)",
                     "FINGER": "doigt pose (session humaine)"}[cls]
            print(f"  >>> PROCHAIN MUR = [{cls}] op 0x{op:02x} ({name}). STOP fail-closed. "
                  f"Le script SUIVANT devra traiter : {klass}.", flush=True)
            return
        # [AP] / [SEP] : rejouable ici
        if sent >= PHASE3_MAX_STEPS:
            print(f"  budget d'etapes atteint ({PHASE3_MAX_STEPS}) -> STOP.", flush=True); return
        if not replay_step(ctx, step, idx):
            return
        sent += 1
    print(f"  fin de la table post-0x73 atteinte ({sent} etapes rejouees) sans mur -> STOP "
          f"(inattendu vu la carte sbio_sequence.md).", flush=True)

# ===========================================================================
# PHASE 1 — boucle native PERSIST (identique a sep_native_sbio.sh) : ACK + STOCKE les SAVE.
# ===========================================================================
counts = defaultdict(int); nsave = 0; last = time.time(); verdict = "idle"
print(f"=== PHASE 1 — PERSIST : on ACQUITTE + STOCKE les SAVE (ecriture), budget {MAX_SAVES}, idle {IDLE}s ===", flush=True)
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
        print(f"  {name} TAG=0x{m.TAG:02x} -> ACK + STOCKE {tag} ({ln}o) [SAVE #{nsave}/{MAX_SAVES}]", flush=True)
        if nsave >= MAX_SAVES:
            verdict = "budget_atteint"; print(f"  >>> {MAX_SAVES} SAVE sans stabilisation = MEME MUR QUE VOIE C. STOP.", flush=True); break
    else:
        verdict = "op_inconnue"; print(f"  op INCONNUE 0x{op:02x} TAG=0x{m.TAG:02x} -> STOP (fail-closed).", flush=True); break

print("--- bilan : " + ", ".join(f"{OPNAME.get(o,hex(o))}x{c}" for o, c in sorted(counts.items())), flush=True)
print(f"--- verdict flux : {verdict} (idle = le SEP s'est stabilise apres les SAVE)", flush=True)
print("endpoints finaux : " + ", ".join(f"0x{n:02x}:{nm}" for n, nm in sorted(sep.epnum2name.items())), flush=True)
print(f"store apres run : maitres={sorted(store_masters)}, gl={len(store_gls)}, gl_bruts={len(gl_raw)} (dans {XART_STORE})", flush=True)

# ---------------------------------------------------------------------------
# PHASE 2 + 3 : seulement si le SEP s'est STABILISE (idle) ET a annonce sbio (0x08).
# ---------------------------------------------------------------------------
if verdict != "idle":
    print(f">>> Flux non stabilise (verdict={verdict}) : sonde + deroule NON lances (fail-closed).", flush=True)
elif 0x08 not in sep.epnum2name:
    print(">>> SEP stabilise mais sbio (0x08) non annonce : rien a sonder.", flush=True)
else:
    ctx = probe_sbio()
    phase3_replay(ctx)
PY
