#!/usr/bin/env bash
# =============================================================================
# sep_native_sbio3.sh — ROUTE NATIVE + sbio : FRANCHIR le 1er mur post-0x73 (0x17 prepareSession)
#   en lisant le n° de série du capteur SUR SPI (live) et en le donnant au SEP, puis S'ARRÊTER
#   au MUR SUIVANT en dumpant ce que le SEP présente.
#
# ─────────────────────────────────────────────────────────────────────────────
# EN LANGAGE CLAIR (décision go / no-go — Albert)
#   BUT : on a prouvé (n=3, vérifié) que par la route native, sbio répond au « bonjour » 0x73 comme macOS,
#   puis que le TOUT PREMIER mur est la commande 0x17 « prepareSession » (classe [SPI]). On a VU cette nuit
#   que la charge de ce 0x17 = le NUMÉRO DE SÉRIE / identité du capteur (16 octets
#   0219c05c0fd2aa349a81c76e030200d8) — EXACTEMENT ceux que l'AP lit du capteur par SPI (mesa_hello /
#   mesa_spi_proxy.read_id ont sorti cette même identité sur CE Mac). Donc on peut FRANCHIR 0x17
#   NATIVEMENT : lire l'identité capteur maintenant, par SPI, et la servir au SEP dans la commande 0x17.
#   Ce script refait toute la route native (persist → sbio → 0x73 VIVANT), FRANCHIT 0x17 avec la série LUE
#   EN DIRECT, puis S'ARRÊTE et PHOTOGRAPHIE le MUR SUIVANT (d'après la carte c12 : 0x15 performKeyExchange,
#   lui aussi [SPI] = le vrai lockstep chiffré SEP↔capteur, pas encore traité).
#
#   CE QUI EST ÉCRIT (⚠️ même classe de risque que sep_native_sbio2.sh / persist — récupérable) :
#     - Booter le firmware SEP (IMG4) : écriture SEP, routine depuis des semaines.
#     - Acquitter les SAVE (0x01/0x06) fait AVANCER le compteur anti-rejeu scellé du SEP : irréversible au
#       sens « on ne revient pas en arrière sur le compteur ». MÊME chose que persist / sbio2.
#     - ALIMENTER le capteur (gpio0 196) + configurer spi2 en mode scruté, lire son identité : EXACTEMENT
#       comme tools/mesa_hello.sh (brique mesa_spi_proxy, selftest OK). TOUT est REMIS dans l'état d'iBoot
#       en fin de run (power_off + restore dans un finally, MÊME en cas d'erreur). AUCUN DOIGT.
#     - La commande sbio 0x17 est BÉNIGNE : elle ne fait que DONNER au SEP le n° de série que le capteur
#       annonce à l'instant (on sert ce que le capteur DIT MAINTENANT, pas un octet fabriqué). PAS de match,
#       PAS d'enrôlement, PAS d'image. On lit la réponse et on dumpe ; on n'acquitte RIEN après.
#     - On S'ARRÊTE AVANT le MUR SUIVANT (0x15, [SPI] = dialogue chiffré SEP↔capteur). On N'ENVOIE PAS 0x15.
#     - Récupération : through-SEP = quasi toujours réparable par DFU (voie C), PAS garanti à 100 %
#       (Stockholm / inconnus). Backup + IPSW prêts. macOS sera désynchronisé — on s'en fiche (ne boote déjà
#       plus). Linux : aucun risque.
#     - Budget de SAVE BORNÉ (MAX_SAVES, défaut 48). Fail-closed PARTOUT : op EP 0x13 inconnue, CNTL non
#       acquitté, 0x73 sans réponse, capteur muet / identité inattendue, série capteur ≠ gabarit c12, 0x17
#       non acquitté, mur suivant → on N'ENVOIE RIEN de plus et on s'arrête (en dumpant au mur) ET on remet
#       le capteur comme iBoot.
#
#   CE QUE ÇA N'EST PAS : pas du rejeu de coffre macOS (store VIDE xart_store_sbio3, À PART ; le SEP crée
#     SON état frais). Le gabarit 0x17 relu de la capture c12 (000303_08_A.bin) sert de FORME EXACTE du
#     gt_packet ; mais la charge (la série) est RE-LUE SUR LE CAPTEUR À L'INSTANT et doit être identique —
#     c'est une sécurité. « 0x17 franchi » ≠ « Touch ID marche » : reste le lockstep chiffré 0x15/0x16…, les
#     blobs, puis un vrai match + l'enrôlement.
#
#   ENDPOINTS TOUCHÉS : 0x00 (CNTL, amorçage), 0x13 (xART/gigalocker, comme persist), 0x08 (sbio : 0x73 + 0x17),
#     + le CAPTEUR SPI (spi2 + gpio0 196, LECTURE d'identité uniquement, comme mesa_hello).
#   RISQUE : identique à sep_native_sbio2.sh (boot IMG4 + ACK SAVE = compteur avance) + alim/SPI capteur
#     restaurée (mesa_hello est éprouvé). L'ajout 0x17 n'envoie au SEP qu'une commande bénigne (la série).
#   RÉSULTAT ATTENDU : le script FRANCHIT 0x17 (le SEP acquitte la série lue en direct), puis dumpe dans $OUT/
#     l'état au MUR SUIVANT (= 0x15 [SPI] d'après c12) : messages EP 0x08 spontanés + tampons A8/B8 + réf.
#     capture du 0x15 (000305_08_A.bin). Message clair « PROCHAIN MUR = [SPI] 0x15 performKeyExchange ».
#     Au script suivant : coder le relais SPI chiffré en lockstep (docs/sensor_hw.md §Trames 0x72/0x73…).
#   PRÉPARÉ PAR : Claude (Opus 4.8), 2026-11-22 — à relire et lancer par Albert, backup + DFU prêts.
#                 L'agent ne lance JAMAIS ce script en réel (uniquement SELFTEST=1 hors-ligne).
# ─────────────────────────────────────────────────────────────────────────────
#
# TECHNIQUE
#   PHASE 1 — NATIF (IDENTIQUE à sep_native_sbio2.sh) : ack recon, SERVIR/ABSENT les FETCH, STOCKER+ACK les
#     SAVE, boucle jusqu'à idle, budget MAX_SAVES, fail-closed sur op inconnue.
#   PHASE 2 — SONDE sbio (IDENTIQUE à sep_native_sbio2.sh) : ouvrir l'EP 0x08 (A8/B8), écrire le 0x73 exact
#     (SBIO_A), l'envoyer, lire B8 + messages, verdict VIVANT/MUET. Renvoie le contexte (tampons) à la Phase 3.
#   PHASE 3 — FRANCHIR 0x17 (NOUVEAU) : dans la MÊME session proxy, construire MesaSPI (analysis/mesa_spi_proxy),
#     power_on(), read_id() → identité capteur ; extraire la série [9:25] ; VÉRIFIER qu'elle == la charge du 0x17
#     de la capture c12 (gabarit 000303_08_A.bin, +0x1c, 0x10 o). Écrire dans A8 le gabarit avec la série LUE À
#     L'INSTANT, envoyer EP 0x08 TAG=0xfc TYPE=0x17, lire/dumper B8 + faute DART. Si 0x17 acquitté : continuer le
#     déroulé post-0x17 (rejouer [AP]/[SEP] en ordre c12) et STOP+dump au 1er [SPI]/[BLOB]/[FINGER] (= 0x15 d'après
#     c12). Teardown capteur (power_off + restore) dans un finally, MÊME en cas d'erreur. Fail-closed partout.
#
# RED LINES : aucune op disque sur le Mac, pas de dd/nvram/sudo/partition. Le store est un fichier sur CE PC.
#   m1n1 : lu, jamais modifié/poussé. Le SEP-write (boot IMG4 + SAVE-ack) = lancé par Albert (ce script, pending/).
#   On N'ENVOIE JAMAIS un SAVE vers sbio, ni le 0x15/0x16 chiffré, ni une commande blob/doigt : STOP au mur.
#   Capteur : alim + lecture d'identité uniquement (mesa_hello), remis en état d'iBoot dans un finally.
#
# USAGE
#   SELFTEST=1 ./pending/sep_native_sbio3.sh   # hors-ligne : politique + vérifs 0x17/identité/import. Ne touche pas le Mac.
#   ./tools/catch_proxy.sh                      # D'ABORD (Claude) : attrape le Mac en proxy (tu power-cycles)
#   ./pending/sep_native_sbio3.sh               # PUIS run RÉEL (Albert lance)
#   Vars : MAX_SAVES=48 | IDLE=25 | XART_STORE=<dir> | OS_UUID_MODE=fixed|none | SBIO_A=<0x73.bin> |
#          SBIO_0X17_TMPL=<gabarit 0x17> | SBIO_STREAM15=0|1 | C12_OOL=<dir ool c12> |
#          PHASE3_MAX_STEPS=16 | WALL_LISTEN=4
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
# Store SÉPARÉ, DISTINCT de sbio/sbio2 ET de l'état précieux (xart_store_linux).
export XART_STORE="${XART_STORE:-$REPO_ROOT/xart_store_sbio3}"
# Poignée 0x73 rejouée OCTET POUR OCTET depuis la capture (pas de gt_packet construit à la main).
export SBIO_A="${SBIO_A:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000300_08_A.bin}"
# Gabarit 0x17 (gt_packet EXACT de macOS, DONNÉES) : forme du prepareSession ; la charge = n° série capteur.
export SBIO_0X17_TMPL="${SBIO_0X17_TMPL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000303_08_A.bin}"
# Dossier des OOL EP 0x08 de la capture c12 (source des octets EXACTS rejoués / référence du mur = DONNÉES).
export C12_OOL="${C12_OOL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool}"
# Racine du repo, pour importer analysis.mesa_spi_proxy (brique SPI capteur réutilisable).
export ANALYSIS_PARENT="${ANALYSIS_PARENT:-$REPO_ROOT}"
# Option diagnostic (défaut 0) : programmer AUSSI le stream 15 du dart-sep côté AP (aucune écriture SEP).
export SBIO_STREAM15="${SBIO_STREAM15:-0}"
# Budgets Phase 3 : nb max de commandes sbio rejouées, et durée d'écoute au mur.
export PHASE3_MAX_STEPS="${PHASE3_MAX_STEPS:-16}"
export WALL_LISTEN="${WALL_LISTEN:-4}"
export M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
mkdir -p "$XART_STORE"

if [ "$SELFTEST" != 1 ]; then
  [ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
  STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_native_sbio3"; mkdir -p "$OUT"; export OUT
  # Le Mac doit DÉJÀ être en proxy : lancer ./tools/catch_proxy.sh AVANT (Claude le fait + power-cycle).
  require_mac
fi

timeout 420 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "${OUT:-/tmp}/native_sbio3.log"
import os, sys, time, struct, glob
SELFTEST = os.environ["SELFTEST"] == "1"
OS_UUID_MODE = os.environ.get("OS_UUID_MODE", "fixed")
LINUX_OS_UUID = bytes.fromhex(os.environ["LINUX_OS_UUID"])
MAX_SAVES = int(os.environ.get("MAX_SAVES", "48"))
IDLE = int(os.environ.get("IDLE", "25"))
XART_STORE = os.environ["XART_STORE"]
SBIO_A = os.environ.get("SBIO_A", "")
SBIO_0X17_TMPL = os.environ.get("SBIO_0X17_TMPL", "")
C12_OOL = os.environ.get("C12_OOL", "")
SBIO_STREAM15 = os.environ.get("SBIO_STREAM15", "0") == "1"
PHASE3_MAX_STEPS = int(os.environ.get("PHASE3_MAX_STEPS", "16"))
WALL_LISTEN = int(os.environ.get("WALL_LISTEN", "4"))

# Racine du repo sur sys.path pour importer la brique SPI capteur (import OFFLINE-safe : m1n1/time y sont
# importés paresseusement, dans les méthodes ; l'import du module n'ouvre aucun matériel).
sys.path.insert(0, os.environ.get("ANALYSIS_PARENT", "."))

OP_FWBOOT, OP_OSUUID, OP_FETCH_MASTER, OP_FETCH_GL = 0x0e, 0x13, 0x00, 0x05
OP_ABSENT, OP_ANNOUNCE, OP_SAVE_XART, OP_SAVE_LOCKER = 0x07, 0x1d, 0x01, 0x06
RESP_DONE, RESP_ANNOUNCE = 0x00, 0x16
ACK_MASK = 0xFFFFFF00
OPNAME = {OP_FWBOOT:"fw-boot", OP_OSUUID:"os-uuid", OP_FETCH_MASTER:"FETCH-maître",
          OP_FETCH_GL:"FETCH-locker", OP_ABSENT:"absent(SEP)", OP_ANNOUNCE:"annonce-EP",
          OP_SAVE_XART:"SAVE-xART", OP_SAVE_LOCKER:"SAVE-locker"}

# Offsets gt_packet_t (vérifié, docs/messages.md §SBIO) : +0x14 = opcode, +0x18 = longueur de charge, +0x1c = charge.
GT_OP, GT_LEN, GT_PAYLOAD = 0x14, 0x18, 0x1c
X17_PAYLEN = 0x10            # longueur de la charge du 0x17 = 16 octets (n° de série capteur), VU c12
SERIAL_SLICE = slice(9, 25)  # dans la trame d'identité capteur (80 d4 00 1b 0000 0000 70 <16o série> 75 76)

def declen(param, data): return (param & 0xFF) | ((data & 0xFF) << 8)

# ---------------------------------------------------------------------------
# LISTE ORDONNÉE des commandes sbio APRÈS le 0x73 (docs/sbio_sequence.md §1.1 + trace c12, seq 303+).
#   (opcode, classe, nom, ool_A, ool_B). CLASSES : "AP"/"SEP" = rejouables ; "SPI"/"BLOB"/"FINGER" = MUR.
# L'index 0 (0x17) est FRANCHI SPÉCIALEMENT par la Phase 3 (série capteur lue en direct). Le déroulé
# post-0x17 reprend à l'index 1 : la carte c12 y place 0x15 [SPI] = le MUR SUIVANT (lockstep chiffré).
POST_0X73_STEPS = [
    # --- §1.1 : init + 1re passe capteur ---
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
    # --- §1.2/§1.3 : tout ce qui suit est APRÈS d'autres murs [SPI]/[BLOB] (cf. sbio_sequence.md). ---
]

# --- store xART sbio3 sur CE PC : maîtres par type (1/2), gigalockers par UUID + dump brut ---
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

def _read_file(pth):
    return open(pth, "rb").read() if (pth and os.path.exists(pth)) else None

if SELFTEST:
    print("--- SELFTEST (hors-ligne, le Mac et le capteur ne sont PAS touches) ---", flush=True)
    print(f"store xART sbio3 : {XART_STORE}  (maitres={len(glob.glob(os.path.join(XART_STORE,'master_*.bin')))}, "
          f"gl={len(glob.glob(os.path.join(XART_STORE,'gl_*.bin')))})  [SEPARE de xart_store_linux/sbio/sbio2]", flush=True)
    print("PHASE 1 — politique native PERSIST (identique a sep_native_sbio2.sh) :", flush=True)
    print("  fw-boot/os-uuid/annonce/absent-SEP : ack ; FETCH : SERVIR si store sinon ABSENT ;", flush=True)
    print(f"  SAVE 0x01/0x06 : lire B, STOCKER, ACK (DATA&0xffffff00)  !! ECRITURE  (budget {MAX_SAVES})", flush=True)
    print(f"  boucle jusqu'a idle ({IDLE}s de silence) ; fail-closed sur op inconnue", flush=True)
    assert OS_UUID_MODE in ("fixed", "none") and len(LINUX_OS_UUID) == 16

    print("PHASE 2 — sonde sbio 0x73 (identique a sep_native_sbio2.sh, seulement si idle ET 0x08 annonce) :", flush=True)
    b = _read_file(SBIO_A)
    if b is None:
        print(f"  ERREUR — fichier SBIO_A introuvable : {SBIO_A!r}.", flush=True); raise SystemExit(1)
    assert len(b) > GT_OP, f"SBIO_A trop court ({len(b)} o)"
    assert b[0x00] == 1, f"SBIO_A +0x00={b[0x00]} (attendu 1)"
    assert b[GT_OP] == 0x73, f"SBIO_A +0x14={b[GT_OP]:#x} (attendu 0x73)"
    print(f"  SBIO_A verifie : {os.path.basename(SBIO_A)} = gt_packet 0x73 valide (+0x00=1, +0x14=0x73).", flush=True)

    print("PHASE 3 — FRANCHIR 0x17 (NOUVEAU) : lire l'identite capteur SUR SPI (live) et la servir au SEP.", flush=True)
    # (a) le gabarit 0x17 de la capture c12 : forme EXACTE + charge = n° serie capteur.
    tmpl = _read_file(SBIO_0X17_TMPL)
    if tmpl is None:
        print(f"  ERREUR — gabarit 0x17 introuvable : {SBIO_0X17_TMPL!r}.", flush=True); raise SystemExit(1)
    assert len(tmpl) >= GT_PAYLOAD + X17_PAYLEN, f"gabarit 0x17 trop court ({len(tmpl)} o)"
    assert tmpl[GT_OP] == 0x17, f"gabarit +0x14=0x{tmpl[GT_OP]:02x} (attendu 0x17)"
    assert tmpl[GT_LEN] == X17_PAYLEN, f"gabarit +0x18=0x{tmpl[GT_LEN]:02x} (attendu 0x{X17_PAYLEN:02x})"
    charge = tmpl[GT_PAYLOAD:GT_PAYLOAD + X17_PAYLEN]
    print(f"  gabarit 0x17 verifie : {os.path.basename(SBIO_0X17_TMPL)} ({len(tmpl)}o) "
          f"+0x14=0x17 +0x18=0x{X17_PAYLEN:02x} ; charge (serie, 16o) = {charge.hex()}", flush=True)
    # (b) import de la brique SPI capteur + coherence charge == identite attendue.
    try:
        from analysis.mesa_spi_proxy import MesaSPI, ID_EXPECTED, MesaError
    except Exception as e:
        print(f"  ERREUR — import de analysis.mesa_spi_proxy impossible : {e}", flush=True); raise SystemExit(1)
    expected_serial = ID_EXPECTED[SERIAL_SLICE]
    print(f"  import MesaSPI OK ; identite connue ID_EXPECTED ({len(ID_EXPECTED)}o) = {ID_EXPECTED.hex()}", flush=True)
    print(f"  serie attendue (ID_EXPECTED[9:25]) = {expected_serial.hex()}", flush=True)
    assert charge == expected_serial, (f"charge du gabarit 0x17 ({charge.hex()}) != serie capteur connue "
                                       f"({expected_serial.hex()})")
    print("  >>> COHERENCE OK : la charge du 0x17 (c12) == le n° de serie que le capteur annonce "
          "(mesa_spi_proxy.read_id). Le run LIRA cette serie EN DIRECT et la servira telle quelle.", flush=True)
    print("  Plan Phase 3 : MesaSPI(iface,p,u) -> power_on() -> read_id() -> serie[9:25] ; VERIFIER == gabarit ;", flush=True)
    print("    ecrire gabarit+serie-live dans A8 ; envoyer EP 0x08 TAG=0xfc TYPE=0x17 ; lire/dumper B8 + faute DART ;", flush=True)
    print("    si 0x17 acquitte -> continuer en ordre c12 ; STOP+dump au 1er [SPI]/[BLOB]/[FINGER] ; teardown capteur (finally).", flush=True)

    print("  LISTE ORDONNEE post-0x73 (source: sbio_sequence.md §1 + trace c12) :", flush=True)
    wall_idx = None
    for i, (op, cls, name, oa, ob) in enumerate(POST_0X73_STEPS):
        mark = ""
        if i == 0:
            act = "FRANCHI"; mark = "   <<< FRANCHI via lecture capteur live (Phase 3)"
        elif cls in ("SPI", "BLOB", "FINGER"):
            act = "MUR"
            if wall_idx is None:
                wall_idx = i; mark = "   <<<<< MUR SUIVANT (STOP ICI apres 0x17, on N'ENVOIE PAS)"
        else:
            act = "REJOUE"
        ref = ""
        if oa:
            exists = os.path.exists(os.path.join(C12_OOL, oa)) if C12_OOL else False
            ref = f"  [ref A={oa}{' OK' if exists else ' ABSENT'}]"
        print(f"    #{i:2d}  op=0x{op:02x}  [{cls:6s}]  {act:7s}  {name}{ref}{mark}", flush=True)
    print(f"  budget etapes = {PHASE3_MAX_STEPS} ; ecoute au mur = {WALL_LISTEN}s.", flush=True)
    if wall_idx is not None:
        ws = POST_0X73_STEPS[wall_idx]
        print(f"  >>> VERDICT PLAN : 0x17 FRANCHI ; le MUR SUIVANT tombe a l'etape #{wall_idx} "
              f"([{ws[1]}] op 0x{ws[0]:02x} {ws[2]}). Entre 0x17 et ce mur, AUCUNE commande [AP]/[SEP] a rejouer "
              f"dans l'ordre c12 : on dumpe directement ce mur. (Reduction de portee HONNETE : le 0x15 est le "
              f"lockstep chiffre SEP<->capteur, non traite ici.)", flush=True)
        if ws[3]:
            pth = os.path.join(C12_OOL, ws[3])
            rb = _read_file(pth)
            if rb is not None:
                oplen = rb[GT_LEN] if len(rb) > GT_LEN else None
                print(f"  >>> forme du mur suivant (ref capture {ws[3]}, {len(rb)}o) : gt_packet "
                      f"+0x14=0x{rb[GT_OP]:02x} +0x18=0x{(oplen if oplen is not None else 0):02x} (len charge).", flush=True)
    print("SELFTEST OK (rien envoye au SEP, capteur non touche).", flush=True)
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

# LECTURE SEULE de l'etat de faute du dart-sep. read32 only, aucune ecriture.
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
# PHASE 2 — sonde sbio (0x73). IDENTIQUE a sep_native_sbio2.sh, renvoie le contexte (tampons) a la Phase 3.
# ===========================================================================
def probe_sbio():
    print("=== PHASE 2 — SONDE sbio (0x73, sans doigt, une seule commande) ===", flush=True)
    if 0x08 not in sep.epnum2name:
        print("  sbio (0x08) n'est PAS annonce : rien a sonder.", flush=True); return None
    if not (SBIO_A and os.path.exists(SBIO_A)):
        print(f"  ERREUR: fichier SBIO_A introuvable ({SBIO_A!r}). On n'envoie RIEN.", flush=True); return None
    a_bytes = open(SBIO_A, "rb").read()
    if len(a_bytes) <= GT_OP or a_bytes[GT_OP] != 0x73 or a_bytes[0] != 1:
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
    b_ok = len(b8) > GT_OP and b8[0] == 1 and b8[GT_OP] == 0x73
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
# PHASE 3 — FRANCHIR 0x17 (lecture capteur SPI live) puis deroule post-0x17, STOP au 1er [SPI]/[BLOB]/[FINGER].
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
    # 1. ce que le SEP demande spontanement sur EP 0x08
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
        print("    (aucun message EP 0x08 spontane : le SEP ATTEND que l'AP pilote la commande suivante, "
              "comme macOS. La commande suivante attendue = ce mur.)", flush=True)
    # 2. etat LIVE des tampons A8/B8
    try:
        a8 = iface.readmem(ctx["phys_A8"], ctx["SZ8"])
        b8 = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
    except Exception as e:
        a8 = b8 = b""; print(f"    (lecture A8/B8 impossible : {e})", flush=True)
    print(f"    A8 (notre dernier envoi)  tete={_hexhead(a8)}", flush=True)
    print(f"    B8 (derniere sortie SEP)  tete={_hexhead(b8)}", flush=True)
    # 3. faute DART (lecture seule)
    print_dart_fault("au mur")
    # 4. reference capture c12 = DONNEES : forme EXACTE de la commande du mur cote macOS
    ref_a = read_c12_ool(oa); ref_b = read_c12_ool(ob)
    if ref_a is not None:
        oplen = ref_a[GT_LEN] if len(ref_a) > GT_LEN else None
        print(f"    ref capture c12 ({oa}, {len(ref_a)}o) = commande du mur cote macOS : gt_packet "
              f"+0x14=0x{ref_a[GT_OP]:02x} +0x18=0x{(oplen if oplen is not None else 0):02x} (len charge) ; "
              f"charge a +0x1c tete={_hexhead(ref_a[GT_PAYLOAD:GT_PAYLOAD+0x20])}", flush=True)
    # 5. ecrire les dumps
    if outdir:
        try:
            if a8: open(os.path.join(outdir, "wall_A8.bin"), "wb").write(a8)
            if b8: open(os.path.join(outdir, "wall_B8.bin"), "wb").write(b8)
            if ref_a is not None: open(os.path.join(outdir, f"wall_ref_{op:02x}_A.bin"), "wb").write(ref_a)
            if ref_b is not None: open(os.path.join(outdir, f"wall_ref_{op:02x}_B.bin"), "wb").write(ref_b)
            with open(os.path.join(outdir, "wall_summary.txt"), "w") as f:
                f.write(f"MUR post-0x17 (route native)\n")
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
    if len(a_bytes) <= GT_OP or a_bytes[GT_OP] != op:
        got = a_bytes[GT_OP] if len(a_bytes) > GT_OP else -1
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
    ok = any(typ == op for _, typ in got)
    print(f"    B8 tete={_hexhead(b8)} ; reponse de meme type 0x{op:02x} : {'OUI' if ok else 'NON'}", flush=True)
    if not ok:
        print(f"  etape #{idx}: reponse INATTENDUE (pas de '< 0x{op:02x}') -> STOP (fail-closed). Dump de l'etat :", flush=True)
        dump_wall(ctx, step, idx)
        return False
    return True

def replay_post_0x17(ctx, start_idx):
    """Deroule la carte c12 a partir de start_idx : rejoue [AP]/[SEP], STOP+dump au 1er [SPI]/[BLOB]/[FINGER]."""
    print("=== deroule post-0x17 (rejoue [AP]/[SEP] en ordre c12, STOP au 1er [SPI]/[BLOB]/[FINGER]) ===", flush=True)
    sent = 0
    for idx in range(start_idx, len(POST_0X73_STEPS)):
        step = POST_0X73_STEPS[idx]
        op, cls, name, oa, ob = step
        if cls in ("SPI", "BLOB", "FINGER"):
            print(f"  etape #{idx}: op=0x{op:02x} classe=[{cls}] ({name}) = MUR. On N'ENVOIE PAS cette commande.", flush=True)
            dump_wall(ctx, step, idx)
            klass = {"SPI": "lockstep chiffre SEP<->capteur SPI (sensor_hw.md : 0x72/0x73/0x55…)",
                     "BLOB": "blob espace-utilisateur (capture)", "FINGER": "doigt pose (session humaine)"}[cls]
            print(f"  >>> PROCHAIN MUR = [{cls}] op 0x{op:02x} ({name}). STOP fail-closed. "
                  f"Le script SUIVANT devra traiter : {klass}.", flush=True)
            return
        if sent >= PHASE3_MAX_STEPS:
            print(f"  budget d'etapes atteint ({PHASE3_MAX_STEPS}) -> STOP.", flush=True); return
        if not replay_step(ctx, step, idx):
            return
        sent += 1
    print(f"  fin de la table post-0x73 atteinte ({sent} etapes rejouees) sans mur -> STOP "
          f"(inattendu vu la carte sbio_sequence.md).", flush=True)

def phase3(ctx):
    print("=== PHASE 3 — FRANCHIR 0x17 prepareSession (n° serie capteur lu SUR SPI, en direct) ===", flush=True)
    if not ctx or not ctx.get("alive"):
        print("  sbio pas VIVANT (0x73 sans reponse) : PHASE 3 non lancee (fail-closed).", flush=True); return
    if ctx.get("sid_A8") is None:
        print("  sid A8 inconnu : PHASE 3 non lancee (fail-closed).", flush=True); return
    # 1. gabarit 0x17 (c12) = forme EXACTE du gt_packet (DONNEES) ; sa charge = serie attendue.
    if not (SBIO_0X17_TMPL and os.path.exists(SBIO_0X17_TMPL)):
        print(f"  gabarit 0x17 introuvable ({SBIO_0X17_TMPL!r}) -> STOP (fail-closed).", flush=True); return
    tmpl = open(SBIO_0X17_TMPL, "rb").read()
    if len(tmpl) < GT_PAYLOAD + X17_PAYLEN or tmpl[GT_OP] != 0x17 or tmpl[GT_LEN] != X17_PAYLEN:
        o = tmpl[GT_OP] if len(tmpl) > GT_OP else -1; l = tmpl[GT_LEN] if len(tmpl) > GT_LEN else -1
        print(f"  gabarit 0x17 malforme (+0x14=0x{o:02x} +0x18=0x{l:02x}, len {len(tmpl)}) -> STOP (fail-closed).", flush=True); return
    expected_serial = tmpl[GT_PAYLOAD:GT_PAYLOAD + X17_PAYLEN]
    print(f"  gabarit 0x17 : {os.path.basename(SBIO_0X17_TMPL)} ({len(tmpl)}o), serie attendue (c12) = {expected_serial.hex()}", flush=True)
    # 2. brique SPI capteur, DANS LA MEME session proxy.
    try:
        from analysis.mesa_spi_proxy import MesaSPI, MesaError
    except Exception as e:
        print(f"  import de analysis.mesa_spi_proxy impossible : {e} -> STOP (fail-closed).", flush=True); return
    mesa = None
    try:
        mesa = MesaSPI(iface, p, u)              # verifie l'etat iBoot (lecture seule) ; peut lever MesaError
        print("  MesaSPI construit (capteur mesa sur spi2, etat iBoot verifie, lecture seule).", flush=True)
        mesa.power_on()                          # alim gpio0 196 + spi2 mode scrute (comme mesa_hello)
        print("  capteur ALIMENTE (gpio0 196) + spi2 en mode scrute.", flush=True)
        ident = mesa.read_id()                   # bonjour -> identite ; verif interne vs ID_EXPECTED
        serial = ident[SERIAL_SLICE]
        print(f"  identite capteur LUE ({len(ident)}o) : {ident.hex()}", flush=True)
        print(f"  n° de serie extrait [9:25] : {serial.hex()}", flush=True)
        if serial != expected_serial:
            print(f"  >>> MUR : serie capteur != gabarit c12 ({serial.hex()} != {expected_serial.hex()}) "
                  f"-> STOP (fail-closed). On N'ENVOIE PAS 0x17.", flush=True)
            dump_wall(ctx, POST_0X73_STEPS[0], 0); return
        # 3. construire la commande 0x17 depuis le gabarit, en INJECTANT la serie LUE A L'INSTANT.
        #    (securite : on sert ce que le capteur DIT MAINTENANT ; doit etre identique au gabarit.)
        cmd = bytearray(tmpl); cmd[GT_PAYLOAD:GT_PAYLOAD + X17_PAYLEN] = serial
        try:
            iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
            dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=bytes(cmd)[:ctx["SZ8"]])
        except Exception as e:
            print(f"  ecriture de la commande 0x17 dans A8 impossible : {e} -> STOP (fail-closed).", flush=True); return
        pump_ep0(); sep.msgs[0x08].clear()
        print_dart_fault("avant 0x17 (baseline)")
        print("  envoi EP 0x08 TAG=0xfc TYPE=0x17 (prepareSession ; charge = serie capteur lue en direct)...", flush=True)
        sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x17, PARAM=0x00, DATA=0x00000000))
        got = []; t0 = time.time()
        while time.time() - t0 < 6:
            pump_ep0()
            while sep.msgs[0x08]:
                m = sep.msgs[0x08].popleft(); got.append((m.TAG, m.TYPE))
                print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
            time.sleep(0.02)
        print_dart_fault("apres 0x17")
        try: b8 = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
        except Exception: b8 = b""
        nz = sum(1 for x in b8 if x)
        if b8 and os.environ.get("OUT"):
            try: open(os.path.join(os.environ["OUT"], "cross_0x17_B.bin"), "wb").write(b8)
            except Exception: pass
        print(f"  B8 apres 0x17 : {nz} octets non nuls ; tete={_hexhead(b8)}", flush=True)
        ok = any(typ == 0x17 for _, typ in got)
        print(f"  reponse SEP de meme type 0x17 : {'OUI' if ok else 'NON'}", flush=True)
        if not ok:
            print("  >>> 0x17 NON acquitte par le SEP (pas de '< 0x17') -> STOP (fail-closed). Dump de l'etat :", flush=True)
            dump_wall(ctx, POST_0X73_STEPS[0], 0); return
        print(">>> 0x17 FRANCHI NATIVEMENT : le SEP a accepte le n° de serie capteur lu en direct. "
              "NE PAS conclure 'Touch ID marche' : reste le lockstep chiffre 0x15/0x16, les blobs, le match.", flush=True)
        # 4. continuer en ordre c12 a partir de l'index 1 ; STOP au 1er [SPI]/[BLOB]/[FINGER] (= 0x15 d'apres c12).
        replay_post_0x17(ctx, start_idx=1)
    except MesaError as e:
        print(f"  >>> capteur (MesaSPI) : {e} -> STOP (fail-closed).", flush=True)
    except Exception as e:
        print(f"  >>> erreur PHASE 3 : {e} -> STOP (fail-closed).", flush=True)
    finally:
        # TEARDOWN capteur : remettre spi2 + broche 196 dans l'etat d'iBoot, MEME en cas d'erreur.
        if mesa is not None:
            try: mesa.power_off(); print("  capteur ETEINT (power_off).", flush=True)
            except Exception as e: print(f"  (power_off a echoue : {e})", flush=True)
            try: mesa.restore(); print("  spi2 + broche 196 REMIS dans l'etat d'iBoot (restore).", flush=True)
            except Exception as e: print(f"  (restore a echoue : {e})", flush=True)

# ===========================================================================
# PHASE 1 — boucle native PERSIST (identique a sep_native_sbio2.sh) : ACK + STOCKE les SAVE.
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
    print(f">>> Flux non stabilise (verdict={verdict}) : sonde + franchissement NON lances (fail-closed).", flush=True)
elif 0x08 not in sep.epnum2name:
    print(">>> SEP stabilise mais sbio (0x08) non annonce : rien a sonder.", flush=True)
else:
    ctx = probe_sbio()
    phase3(ctx)
PY
