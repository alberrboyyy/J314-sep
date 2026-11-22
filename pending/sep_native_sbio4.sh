#!/usr/bin/env bash
# =============================================================================
# sep_native_sbio4.sh — ROUTE NATIVE + sbio : FRANCHIR 0x17 (prepareSession) PUIS RELAYER le
#   key exchange 0x15/0x16 (performKeyExchange) = 1er dialogue en LOCKSTEP chiffré SEP↔capteur,
#   l'AP n'étant qu'un PUR RELAIS D'OCTETS. On S'ARRÊTE juste après ce 1er échange de clés.
#
# ─────────────────────────────────────────────────────────────────────────────
# EN LANGAGE CLAIR (décision go / no-go — Albert)
#   BUT : sbio3 a FRANCHI nativement le mur 0x17 (on sert au SEP le n° de série que le capteur annonce,
#   lu en direct). Le MUR SUIVANT est 0x15/0x16 « performKeyExchange ». On a VU cette nuit (docs/
#   sbio_keyexchange.md, désassemblage kext) que pour cet échange de clés, l'AP est un PUR RELAIS
#   D'OCTETS : AUCUNE crypto, AUCUN secret côté AP. Le mécanisme est du simple transport en lockstep :
#     {sbio 0x15 → le SEP rend un blob OPAQUE de 40 o} → {SPI : on envoie ces 40 o au capteur dans une
#      trame 0x72 (en-tête 80 72 00 2f 00 00 00 + 40 o = 47 o ; longueur = TAILLE TOTALE 0x2f) ; le capteur rend 40 o} → {sbio 0x16 :
#      on renvoie au SEP les 40 o de réponse du capteur}.
#   Les 40 o ne sont JAMAIS lus, interprétés ni modifiés par l'AP : on les transporte, point.
#   Ce script refait toute la route native (persist → sbio → 0x73 VIVANT → 0x17 FRANCHI), PUIS relaie
#   ce 1er key exchange 0x15/0x16, et S'ARRÊTE (on valide d'abord ce 1er relais lockstep).
#
#   CE QUI EST ÉCRIT (⚠️ même classe de risque que sep_native_sbio3.sh / persist — récupérable) :
#     - Booter le firmware SEP (IMG4) : écriture SEP, routine depuis des semaines.
#     - Acquitter les SAVE (0x01/0x06) fait AVANCER le compteur anti-rejeu scellé du SEP : irréversible au
#       sens « on ne revient pas en arrière sur le compteur ». MÊME chose que persist / sbio3.
#     - ALIMENTER le capteur (gpio0 196) + spi2 en mode scruté, lire identité (0x17) PUIS relayer le key
#       exchange : EXACTEMENT le transport de tools/mesa_hello.sh (brique mesa_spi_proxy). Le capteur reste
#       ALIMENTÉ entre 0x17 et le key exchange (une seule session). TOUT est REMIS dans l'état d'iBoot en
#       FIN de run (power_off + restore dans le finally EXTERNE, MÊME en cas d'erreur). AUCUN DOIGT.
#     - Le key exchange 0x15/0x16 relaie des OCTETS OPAQUES : le SEP rend 40 o, on les passe au capteur, le
#       capteur rend 40 o, on les rend au SEP. AUCUN SECRET connu/extrait côté AP, AUCUNE image, AUCUN match,
#       AUCUN enrôlement. On lit/dumpe tout et on S'ARRÊTE après ce 1er échange.
#     - On N'ENVOIE PAS la suite (0x42/0x18, patch 0x5f, params 0x55…) ce run : STOP après le key exchange.
#     - Récupération : through-SEP = quasi toujours réparable par DFU (voie C), PAS garanti à 100 %
#       (Stockholm / inconnus). Backup + IPSW prêts. macOS sera désynchronisé — on s'en fiche (ne boote déjà
#       plus). Linux : aucun risque.
#     - Budget de SAVE BORNÉ (MAX_SAVES, défaut 48). Fail-closed PARTOUT : op EP 0x13 inconnue, CNTL non
#       acquitté, 0x73 sans réponse, capteur muet / identité inattendue, série ≠ gabarit c12, 0x17 non
#       acquitté, réponse 0x15 ≠ 40 o, réponse SPI trop courte, 0x16 non acquitté → on N'ENVOIE RIEN de plus,
#       on dumpe, on s'arrête, ET on remet le capteur comme iBoot.
#
#   CE QUE ÇA N'EST PAS : pas du rejeu de coffre macOS (store VIDE xart_store_sbio4, À PART ; le SEP crée
#     SON état frais). Les gabarits 0x15/0x16 relus de la capture c12 (000305/000307_08_A.bin) servent de
#     FORME EXACTE du gt_packet ; la CHARGE du 0x16 est REMPLACÉE par les 40 o que le CAPTEUR rend À
#     L'INSTANT (le key exchange est frais à chaque allumage, non rejouable). « 0x15/0x16 franchi » ≠
#     « Touch ID marche » : restent 0x42/0x18, le patch capteur, les params chiffrés, le match, l'enrôlement.
#
#   ENDPOINTS TOUCHÉS : 0x00 (CNTL), 0x13 (xART/gigalocker, comme persist), 0x08 (sbio : 0x73 + 0x17 + 0x15/0x16),
#     + le CAPTEUR SPI (spi2 + gpio0 196 : identité 0x17 + relais 0x72 du key exchange, comme mesa_hello).
#   RISQUE : identique à sep_native_sbio3.sh (boot IMG4 + ACK SAVE = compteur avance ; alim/SPI capteur
#     restaurée). L'ajout 0x15/0x16 ne transporte que des octets opaques (aucun secret, aucun doigt).
#   RÉSULTAT ATTENDU : le script FRANCHIT 0x17, puis relaie le key exchange. VERDICT auto-vérifiant : si le
#     SEP ACQUITTE 0x16 (message « < EP=0x08 TYPE=0x16 ») → le relais lockstep a MARCHÉ (grand pas : 1er
#     dialogue chiffré SEP↔capteur relayé nativement). Sinon → le parsing de la réponse SPI est probablement
#     faux → STOP+dump complet dans $OUT/ pour inspection. Dans TOUS les cas, dump complet (B8 du 0x15, réponse
#     SPI brute, B8 du 0x16). Au script suivant : enchaîner 0x42/0x18 (0x73 SPI) etc.
#   PRÉPARÉ PAR : Claude (Opus 4.8), 2026-11-22 — à relire et lancer par Albert, backup + DFU prêts.
#                 L'agent ne lance JAMAIS ce script en réel (uniquement SELFTEST=1 hors-ligne).
# ─────────────────────────────────────────────────────────────────────────────
#
# TECHNIQUE
#   PHASE 1 — NATIF (IDENTIQUE à sbio3) : ack recon, SERVIR/ABSENT les FETCH, STOCKER+ACK les SAVE, boucle
#     jusqu'à idle, budget MAX_SAVES, fail-closed sur op inconnue.
#   PHASE 2 — SONDE sbio (IDENTIQUE à sbio3) : ouvrir l'EP 0x08 (A8/B8), 0x73 exact, verdict VIVANT/MUET.
#   PHASE 3 — FRANCHIR 0x17 (IDENTIQUE à sbio3 à une exception près) : MesaSPI power_on + read_id → série lue
#     en direct, VÉRIFIER == gabarit c12, envoyer 0x17. EXCEPTION sbio4 : le capteur reste ALIMENTÉ (PAS de
#     power_off entre 0x17 et le key exchange), l'instance MesaSPI VIT jusqu'à la fin, et le TEARDOWN (power_off
#     + restore) va dans le finally EXTERNE (après la Phase 4), MÊME en cas d'erreur.
#   PHASE 4 — RELAIS key exchange 0x15/0x16 (NOUVEAU) :
#     (1) sbio 0x15 : gabarit 000305_08_A.bin (sessionType=1), envoyer EP 0x08 TYPE=0x15, lire B8 ;
#         EXTRAIRE le blob du SEP = 40 o à +0x1c (offset CONFIRMÉ par la capture 000306_08_B.bin :
#         +0x14=0x15, +0x18=0x28). VÉRIFIER taille == 0x28, sinon STOP+dump (fail-closed).
#     (2) SPI : trame 0x72 = 80 72 00 2f 00 00 00 + 40 o → mesa.xfer ; poll état 0x10 (long. en attente) ;
#         demande 0x13 ; lecture. EXTRAIRE 40 o de réponse capteur (offset SPI_RESP_OFF, défaut 9 =
#         en-tête 80 d4 00 LL 00000000 <type>, comme l'identité). DUMPE toute la réponse SPI brute.
#     (3) sbio 0x16 : gabarit 000307_08_A.bin, INJECTER les 40 o du capteur à la place de la charge,
#         envoyer EP 0x08 TYPE=0x16, lire B8.
#     (4) VERDICT : le SEP ACQUITTE 0x16 (« < EP=0x08 TYPE=0x16 ») → relais MARCHÉ ; sinon STOP+dump.
#     (5) S'ARRÊTER après le key exchange (on valide d'abord ce 1er relais lockstep).
#     Teardown capteur dans le finally EXTERNE, MÊME en cas d'erreur. Fail-closed partout.
#
# RED LINES : aucune op disque sur le Mac, pas de dd/nvram/sudo/partition. Le store est un fichier sur CE PC.
#   m1n1 : lu, jamais modifié/poussé. Le SEP-write (boot IMG4 + SAVE-ack) = lancé par Albert (ce script, pending/).
#   On N'ENVOIE JAMAIS un SAVE vers sbio. Le key exchange 0x15/0x16 = transport d'octets opaques (aucun secret).
#   On N'ENVOIE PAS la suite après le key exchange, ni commande blob/doigt. Capteur remis en état d'iBoot (finally).
#
# USAGE
#   SELFTEST=1 ./pending/sep_native_sbio4.sh   # hors-ligne : politique + vérifs 0x17 + gabarits 0x15/0x16 + trame 0x72. Ne touche pas le Mac.
#   ./tools/catch_proxy.sh                      # D'ABORD (Claude) : attrape le Mac en proxy (tu power-cycles)
#   ./pending/sep_native_sbio4.sh               # PUIS run RÉEL (Albert lance)
#   Vars : MAX_SAVES=48 | IDLE=25 | XART_STORE=<dir> | OS_UUID_MODE=fixed|none | SBIO_A=<0x73.bin> |
#          SBIO_0X17_TMPL=<gabarit 0x17> | SBIO_0X15_TMPL=<gabarit 0x15> | SBIO_0X16_TMPL=<gabarit 0x16> |
#          SBIO_STREAM15=0|1 | C12_OOL=<dir ool c12> | SPI_RESP_OFF=9 | WALL_LISTEN=4
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
# Store SÉPARÉ, DISTINCT de sbio/sbio2/sbio3 ET de l'état précieux (xart_store_linux).
export XART_STORE="${XART_STORE:-$REPO_ROOT/xart_store_sbio4}"
# Poignée 0x73 rejouée OCTET POUR OCTET depuis la capture (pas de gt_packet construit à la main).
export SBIO_A="${SBIO_A:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000300_08_A.bin}"
# Gabarit 0x17 (gt_packet EXACT de macOS, DONNÉES) : forme du prepareSession ; la charge = n° série capteur.
export SBIO_0X17_TMPL="${SBIO_0X17_TMPL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000303_08_A.bin}"
# Gabarits 0x15 / 0x16 (gt_packet EXACTS de macOS, DONNÉES = FORME uniquement) pour le key exchange.
#   0x15 : la charge = sessionType (01000000). 0x16 : la charge (40 o) est REMPLACÉE par la réponse LIVE du capteur.
export SBIO_0X15_TMPL="${SBIO_0X15_TMPL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000305_08_A.bin}"
export SBIO_0X16_TMPL="${SBIO_0X16_TMPL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool/000307_08_A.bin}"
# Dossier des OOL EP 0x08 de la capture c12 (source des octets EXACTS rejoués / référence du mur = DONNÉES).
export C12_OOL="${C12_OOL:-$REPO_ROOT/traces/20261108-032454_c12-boot-ho/sep.log.ool}"
# Racine du repo, pour importer analysis.mesa_spi_proxy (brique SPI capteur réutilisable).
export ANALYSIS_PARENT="${ANALYSIS_PARENT:-$REPO_ROOT}"
# Option diagnostic (défaut 0) : programmer AUSSI le stream 15 du dart-sep côté AP (aucune écriture SEP).
export SBIO_STREAM15="${SBIO_STREAM15:-0}"
# Offset de la charge (40 o) dans la réponse SPI 0x72 : best-effort (9 = en-tête 80 d4 00 LL 00000000 <type>,
#   comme l'identité). Le parsing d'enveloppe SPI n'est pas 100% reversé (sbio_keyexchange.md §8) : l'ACK 0x16 tranche.
export SPI_RESP_OFF="${SPI_RESP_OFF:-9}"
# Durée d'écoute au mur (dump).
export WALL_LISTEN="${WALL_LISTEN:-4}"
export M1N1_PROXYCLIENT="$M1N1_DIR/proxyclient"
mkdir -p "$XART_STORE"

if [ "$SELFTEST" != 1 ]; then
  [ -f "$M1N1_DIR/build/m1n1.bin" ] || die "m1n1 non compilé : ./tools/build_m1n1.sh"
  STAMP="$(date +%Y%m%d-%H%M%S)"; OUT="$TRACES_DIR/${STAMP}_native_sbio4"; mkdir -p "$OUT"; export OUT
  # Le Mac doit DÉJÀ être en proxy : lancer ./tools/catch_proxy.sh AVANT (Claude le fait + power-cycle).
  require_mac
fi

timeout 420 "$M1N1_PYTHON" - <<'PY' 2>&1 | tee "${OUT:-/tmp}/native_sbio4.log"
import os, sys, time, struct, glob
SELFTEST = os.environ["SELFTEST"] == "1"
OS_UUID_MODE = os.environ.get("OS_UUID_MODE", "fixed")
LINUX_OS_UUID = bytes.fromhex(os.environ["LINUX_OS_UUID"])
MAX_SAVES = int(os.environ.get("MAX_SAVES", "48"))
IDLE = int(os.environ.get("IDLE", "25"))
XART_STORE = os.environ["XART_STORE"]
SBIO_A = os.environ.get("SBIO_A", "")
SBIO_0X17_TMPL = os.environ.get("SBIO_0X17_TMPL", "")
SBIO_0X15_TMPL = os.environ.get("SBIO_0X15_TMPL", "")
SBIO_0X16_TMPL = os.environ.get("SBIO_0X16_TMPL", "")
C12_OOL = os.environ.get("C12_OOL", "")
SBIO_STREAM15 = os.environ.get("SBIO_STREAM15", "0") == "1"
SPI_RESP_OFF = int(os.environ.get("SPI_RESP_OFF", "9"))
WALL_LISTEN = int(os.environ.get("WALL_LISTEN", "4"))
KX_BLOB_LEN = 0x28           # longueur du blob key-exchange (40 o) : SEP 0x15/0x16 ET charge SPI 0x72 (VU c12)

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
    print(f"store xART sbio4 : {XART_STORE}  (maitres={len(glob.glob(os.path.join(XART_STORE,'master_*.bin')))}, "
          f"gl={len(glob.glob(os.path.join(XART_STORE,'gl_*.bin')))})  [SEPARE de xart_store_linux/sbio/sbio2/sbio3]", flush=True)
    print("PHASE 1 — politique native PERSIST (identique a sep_native_sbio3.sh) :", flush=True)
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
    print("    ecrire gabarit+serie-live dans A8 ; envoyer EP 0x08 TAG=0xfc TYPE=0x17 ; lire/dumper B8 + faute DART.", flush=True)
    print("    EXCEPTION sbio4 : capteur reste ALIMENTE (pas de power_off) ; teardown dans le finally EXTERNE (apres Phase 4).", flush=True)

    print("PHASE 4 — RELAIS key exchange 0x15/0x16 (NOUVEAU) : l'AP = PUR RELAIS d'octets (docs/sbio_keyexchange.md).", flush=True)
    # (1) gabarit 0x15 : sessionType=1 ; sa reponse SEP = blob opaque 40 o.
    t15 = _read_file(SBIO_0X15_TMPL)
    if t15 is None:
        print(f"  ERREUR — gabarit 0x15 introuvable : {SBIO_0X15_TMPL!r}.", flush=True); raise SystemExit(1)
    assert len(t15) >= GT_PAYLOAD + 4, f"gabarit 0x15 trop court ({len(t15)} o)"
    assert t15[GT_OP] == 0x15, f"gabarit 0x15 +0x14=0x{t15[GT_OP]:02x} (attendu 0x15)"
    assert t15[GT_LEN] == 0x04, f"gabarit 0x15 +0x18=0x{t15[GT_LEN]:02x} (attendu 0x04)"
    st15 = t15[GT_PAYLOAD:GT_PAYLOAD + 4]
    assert st15 == bytes.fromhex("01000000"), f"gabarit 0x15 sessionType={st15.hex()} (attendu 01000000)"
    print(f"  gabarit 0x15 verifie : {os.path.basename(SBIO_0X15_TMPL)} ({len(t15)}o) +0x14=0x15 +0x18=0x04 "
          f"sessionType={st15.hex()}", flush=True)
    # (2) gabarit 0x16 : la charge (40 o) sera REMPLACEE par la reponse LIVE du capteur.
    t16 = _read_file(SBIO_0X16_TMPL)
    if t16 is None:
        print(f"  ERREUR — gabarit 0x16 introuvable : {SBIO_0X16_TMPL!r}.", flush=True); raise SystemExit(1)
    assert len(t16) >= GT_PAYLOAD + KX_BLOB_LEN, f"gabarit 0x16 trop court ({len(t16)} o)"
    assert t16[GT_OP] == 0x16, f"gabarit 0x16 +0x14=0x{t16[GT_OP]:02x} (attendu 0x16)"
    assert t16[GT_LEN] == KX_BLOB_LEN, f"gabarit 0x16 +0x18=0x{t16[GT_LEN]:02x} (attendu 0x{KX_BLOB_LEN:02x})"
    print(f"  gabarit 0x16 verifie : {os.path.basename(SBIO_0X16_TMPL)} ({len(t16)}o) +0x14=0x16 "
          f"+0x18=0x{KX_BLOB_LEN:02x} (charge 40 o remplacee a l'execution)", flush=True)
    # (3) reference : la reponse SEP 0x15 capturee confirme offset+taille du blob (pas une supposition).
    rb15 = _read_file(os.path.join(C12_OOL, "000306_08_B.bin"))
    if rb15 is not None and len(rb15) > GT_LEN:
        assert rb15[GT_OP] == 0x15 and rb15[GT_LEN] == KX_BLOB_LEN, (
            f"ref 000306_08_B.bin inattendue (+0x14=0x{rb15[GT_OP]:02x} +0x18=0x{rb15[GT_LEN]:02x})")
        print(f"  reference 000306_08_B.bin : reponse SEP 0x15 = +0x14=0x15 +0x18=0x{KX_BLOB_LEN:02x} ; "
              f"blob 40 o @ +0x1c = {rb15[GT_PAYLOAD:GT_PAYLOAD+KX_BLOB_LEN].hex()} (offset CONFIRME par capture).", flush=True)
    # (4) construction de la trame SPI 0x72 = en-tete 7 o + 40 o = 47 o (0x2f), sans toucher au capteur.
    kx_frame = bytes.fromhex("8072002f000000") + bytes(KX_BLOB_LEN)   # longueur d'en-tete = TOTALE (0x2f=47), pas la charge
    assert len(kx_frame) == 0x2f, f"trame 0x72 = {len(kx_frame)} o (attendu 0x2f=47)"
    assert kx_frame[:7].hex() == "8072002f000000", "en-tete 0x72 incorrect (longueur TOTALE 0x2f, VU macOS C19)"
    print(f"  trame 0x72 construite (a blanc) : en-tete {kx_frame[:7].hex()} + 40 o = {len(kx_frame)} o (0x2f). OK.", flush=True)
    print(f"  offset d'extraction de la charge SPI (SPI_RESP_OFF) = {SPI_RESP_OFF} (best-effort ; l'ACK 0x16 tranche).", flush=True)
    print("  Plan Phase 4 : 0x15 -> B8 (blob 40 o @ +0x1c) -> SPI 0x72 (poll etat, 0x13, lecture) -> 40 o capteur ", flush=True)
    print("    -> 0x16 (charge=40 o capteur) -> VERDICT : ACK 0x16 = relais MARCHE ; sinon STOP+dump. STOP apres KX.", flush=True)

    print("  LISTE ORDONNEE post-0x73 (source: sbio_sequence.md §1 + trace c12) :", flush=True)
    for i, (op, cls, name, oa, ob) in enumerate(POST_0X73_STEPS):
        if i == 0:
            act = "FRANCHI (P3)"
        elif op in (0x15, 0x16):
            act = "RELAIS (P4)"
        elif cls in ("SPI", "BLOB", "FINGER"):
            act = "MUR (apres)"
        else:
            act = "n/a"
        ref = ""
        if oa:
            exists = os.path.exists(os.path.join(C12_OOL, oa)) if C12_OOL else False
            ref = f"  [ref A={oa}{' OK' if exists else ' ABSENT'}]"
        print(f"    #{i:2d}  op=0x{op:02x}  [{cls:6s}]  {act:12s}  {name}{ref}", flush=True)
    print(f"  ecoute au mur = {WALL_LISTEN}s. Apres le key exchange (0x16), on S'ARRETE (prochain mur = 0x42/0x18, SPI 0x73).", flush=True)
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

def phase3(ctx):
    """FRANCHIR 0x17. Renvoie (mesa, crossed). sbio4 : le capteur reste ALIMENTE (pas de teardown ici) ;
    l'instance MesaSPI est rendue a l'appelant qui la passe a la Phase 4 puis la detruit dans son finally."""
    print("=== PHASE 3 — FRANCHIR 0x17 prepareSession (n° serie capteur lu SUR SPI, en direct) ===", flush=True)
    if not ctx or not ctx.get("alive"):
        print("  sbio pas VIVANT (0x73 sans reponse) : PHASE 3 non lancee (fail-closed).", flush=True); return None, False
    if ctx.get("sid_A8") is None:
        print("  sid A8 inconnu : PHASE 3 non lancee (fail-closed).", flush=True); return None, False
    # 1. gabarit 0x17 (c12) = forme EXACTE du gt_packet (DONNEES) ; sa charge = serie attendue.
    if not (SBIO_0X17_TMPL and os.path.exists(SBIO_0X17_TMPL)):
        print(f"  gabarit 0x17 introuvable ({SBIO_0X17_TMPL!r}) -> STOP (fail-closed).", flush=True); return None, False
    tmpl = open(SBIO_0X17_TMPL, "rb").read()
    if len(tmpl) < GT_PAYLOAD + X17_PAYLEN or tmpl[GT_OP] != 0x17 or tmpl[GT_LEN] != X17_PAYLEN:
        o = tmpl[GT_OP] if len(tmpl) > GT_OP else -1; l = tmpl[GT_LEN] if len(tmpl) > GT_LEN else -1
        print(f"  gabarit 0x17 malforme (+0x14=0x{o:02x} +0x18=0x{l:02x}, len {len(tmpl)}) -> STOP (fail-closed).", flush=True); return None, False
    expected_serial = tmpl[GT_PAYLOAD:GT_PAYLOAD + X17_PAYLEN]
    print(f"  gabarit 0x17 : {os.path.basename(SBIO_0X17_TMPL)} ({len(tmpl)}o), serie attendue (c12) = {expected_serial.hex()}", flush=True)
    # 2. brique SPI capteur, DANS LA MEME session proxy.
    try:
        from analysis.mesa_spi_proxy import MesaSPI, MesaError
    except Exception as e:
        print(f"  import de analysis.mesa_spi_proxy impossible : {e} -> STOP (fail-closed).", flush=True); return None, False
    mesa = None
    try:
        mesa = MesaSPI(iface, p, u)              # verifie l'etat iBoot (lecture seule) ; peut lever MesaError
        print("  MesaSPI construit (capteur mesa sur spi2, etat iBoot verifie, lecture seule).", flush=True)
        mesa.power_on()                          # alim gpio0 196 + spi2 mode scrute (comme mesa_hello)
        print("  capteur ALIMENTE (gpio0 196) + spi2 en mode scrute (reste alimente jusqu'a la fin du run).", flush=True)
        ident = mesa.read_id()                   # bonjour -> identite ; verif interne vs ID_EXPECTED
        serial = ident[SERIAL_SLICE]
        print(f"  identite capteur LUE ({len(ident)}o) : {ident.hex()}", flush=True)
        print(f"  n° de serie extrait [9:25] : {serial.hex()}", flush=True)
        if serial != expected_serial:
            print(f"  >>> MUR : serie capteur != gabarit c12 ({serial.hex()} != {expected_serial.hex()}) "
                  f"-> STOP (fail-closed). On N'ENVOIE PAS 0x17.", flush=True)
            dump_wall(ctx, POST_0X73_STEPS[0], 0); return mesa, False
        # 3. construire la commande 0x17 depuis le gabarit, en INJECTANT la serie LUE A L'INSTANT.
        #    (securite : on sert ce que le capteur DIT MAINTENANT ; doit etre identique au gabarit.)
        cmd = bytearray(tmpl); cmd[GT_PAYLOAD:GT_PAYLOAD + X17_PAYLEN] = serial
        try:
            iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
            dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=bytes(cmd)[:ctx["SZ8"]])
        except Exception as e:
            print(f"  ecriture de la commande 0x17 dans A8 impossible : {e} -> STOP (fail-closed).", flush=True); return mesa, False
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
            dump_wall(ctx, POST_0X73_STEPS[0], 0); return mesa, False
        print(">>> 0x17 FRANCHI NATIVEMENT : le SEP a accepte le n° de serie capteur lu en direct. "
              "NE PAS conclure 'Touch ID marche' : reste le lockstep chiffre 0x15/0x16, les blobs, le match.", flush=True)
        return mesa, True
    except MesaError as e:
        print(f"  >>> capteur (MesaSPI) : {e} -> STOP (fail-closed).", flush=True)
        return mesa, False
    except Exception as e:
        print(f"  >>> erreur PHASE 3 : {e} -> STOP (fail-closed).", flush=True)
        return mesa, False

# ===========================================================================
# PHASE 4 — RELAIS key exchange 0x15/0x16 (performKeyExchange). L'AP = PUR RELAIS d'octets (aucune crypto,
#   aucun secret) : voir docs/sbio_keyexchange.md. On s'ARRETE juste apres ce 1er echange de cles.
# ===========================================================================
def spi_relay_0x72(mesa, blob40, label="kx"):
    """Relaie blob40 (40 o, opaque) au capteur via la trame 0x72, lit la reponse et la rend BRUTE.
    Sequence = transport documente (sensor_hw.md / mesa_hello) : emettre la commande, poll etat 0x10 pour
    la longueur en attente, demander 0x13, lire. DUMPE la reponse brute. Ne modifie JAMAIS les octets."""
    from analysis.mesa_spi_proxy import MesaError
    # en-tete 7 o + 40 o = 47 o (0x2f). La LONGUEUR de l'en-tete (octets 2-3, BE) = TAILLE TOTALE de la trame
    # (47 = 0x2f), PAS la taille de la charge. Corrige 2026-11-22 (reverseur) : etait 0x28 (=40, charge) a tort,
    # d'ou l'erreur capteur (ack 11 o, status=2) au run sbio4. macOS envoie 8072002f000000 (VU : C19, 28.672).
    frame = bytes.fromhex("8072002f000000") + bytes(blob40)      # en-tete 80 72 002f 000000 + 40 o = 47 o (0x2f)
    if len(frame) != 0x2f:
        raise MesaError(f"trame 0x72 mal formee ({len(frame)} o, attendu 0x2f)")
    print(f"  SPI> trame 0x72 ({len(frame)} o) : en-tete {frame[:7].hex()} + 40 o opaques du SEP.", flush=True)
    mesa.xfer(frame, 0); time.sleep(0.01)                        # emettre la commande (rx_len=0, comme mesa_hello)
    # poll etat 0x10 : la longueur de la reponse en attente est dans st[12]|st[13]<<8 (cf. mesa_spi_proxy.hello)
    pending = 0; st = None
    for _ in range(50):
        st = mesa.status()
        pending = st[12] | (st[13] << 8)
        if pending:
            break
        time.sleep(0.01)
    print(f"  SPI< etat 0x10 : longueur en attente = 0x{pending:02x} (attendu 0x33 d'apres sensor_hw.md)", flush=True)
    resp = b""
    if pending:
        req = bytes.fromhex("8013000b000000") + struct.pack("<I", pending)   # demande 0x13 de `pending` octets
        mesa.xfer(req, 0); time.sleep(0.01)
        resp = mesa.xfer(bytes(pending), pending)                # lecture full-duplex de `pending` octets
    outdir = os.environ.get("OUT")
    if outdir:
        try:
            if st is not None: open(os.path.join(outdir, f"spi_{label}_status.bin"), "wb").write(bytes(st))
            if resp: open(os.path.join(outdir, f"spi_{label}_resp_raw.bin"), "wb").write(resp)
        except Exception as e:
            print(f"    (ecriture dump SPI impossible : {e})", flush=True)
    print(f"  SPI< reponse 0x72 BRUTE ({len(resp)} o) tete={_hexhead(resp)}", flush=True)
    return resp, pending

def phase4(ctx, mesa):
    print("=== PHASE 4 — RELAIS key exchange 0x15/0x16 (performKeyExchange ; AP = pur relais d'octets) ===", flush=True)
    if mesa is None:
        print("  capteur non disponible : PHASE 4 non lancee (fail-closed).", flush=True); return
    from analysis.mesa_spi_proxy import MesaError
    # --- gabarits 0x15 / 0x16 (FORME du gt_packet ; DONNEES ; la charge du 0x16 sera remplacee live) ---
    t15 = _read_file(SBIO_0X15_TMPL)
    t16 = _read_file(SBIO_0X16_TMPL)
    if t15 is None or len(t15) < GT_PAYLOAD + 4 or t15[GT_OP] != 0x15 or t15[GT_LEN] != 0x04:
        print(f"  gabarit 0x15 absent/malforme ({SBIO_0X15_TMPL!r}) -> STOP (fail-closed).", flush=True); return
    if t16 is None or len(t16) < GT_PAYLOAD + KX_BLOB_LEN or t16[GT_OP] != 0x16 or t16[GT_LEN] != KX_BLOB_LEN:
        print(f"  gabarit 0x16 absent/malforme ({SBIO_0X16_TMPL!r}) -> STOP (fail-closed).", flush=True); return
    print(f"  gabarits OK : 0x15 ({os.path.basename(SBIO_0X15_TMPL)}, sessionType={t15[GT_PAYLOAD:GT_PAYLOAD+4].hex()}) "
          f"; 0x16 ({os.path.basename(SBIO_0X16_TMPL)}, charge 40 o a remplacer).", flush=True)

    # --- (1) sbio 0x15 : le SEP rend un blob opaque de 40 o ---
    try:
        iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
        dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=t15[:ctx["SZ8"]])
    except Exception as e:
        print(f"  ecriture 0x15 dans A8 impossible : {e} -> STOP (fail-closed).", flush=True); return
    pump_ep0(); sep.msgs[0x08].clear()
    print_dart_fault("avant 0x15 (baseline)")
    print("  envoi EP 0x08 TAG=0xfc TYPE=0x15 (performKeyExchange, sessionType=1)...", flush=True)
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x15, PARAM=0x00, DATA=0x00000000))
    got = []; t0 = time.time()
    while time.time() - t0 < 6:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft(); got.append((m.TAG, m.TYPE))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    print_dart_fault("apres 0x15")
    try: b8 = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
    except Exception: b8 = b""
    if b8 and os.environ.get("OUT"):
        try: open(os.path.join(os.environ["OUT"], "kx_0x15_B.bin"), "wb").write(b8)
        except Exception: pass
    blob_op  = b8[GT_OP]  if len(b8) > GT_OP  else -1
    blob_len = b8[GT_LEN] if len(b8) > GT_LEN else -1
    print(f"  B8 apres 0x15 : tete={_hexhead(b8)} ; +0x14=0x{blob_op:02x} +0x18=0x{blob_len:02x} (attendu 0x15 / 0x{KX_BLOB_LEN:02x})", flush=True)
    # FAIL-CLOSED : la taille du blob SEP DOIT etre 0x28 (offset +0x1c CONFIRME par la capture 000306_08_B.bin).
    if not (len(b8) >= GT_PAYLOAD + KX_BLOB_LEN and blob_op == 0x15 and blob_len == KX_BLOB_LEN):
        print(f"  >>> reponse 0x15 INATTENDUE (type != 0x15 ou taille != 0x{KX_BLOB_LEN:02x}) -> STOP+dump (fail-closed, on ne devine pas).", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[1], 1); return
    sep_blob = bytes(b8[GT_PAYLOAD:GT_PAYLOAD + KX_BLOB_LEN])
    print(f"  blob KX du SEP (40 o, +0x1c, OPAQUE) = {sep_blob.hex()}", flush=True)

    # --- (2) relais SPI : 40 o -> capteur (trame 0x72) -> 40 o ---
    try:
        resp, pending = spi_relay_0x72(mesa, sep_blob, label="0x72")
    except MesaError as e:
        print(f"  >>> relais SPI 0x72 : {e} -> STOP+dump (fail-closed).", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[1], 1); return
    # extraction best-effort : charge a SPI_RESP_OFF (defaut 9 ; parsing d'enveloppe SPI non 100% reverse, sbio_keyexchange.md §8).
    if len(resp) < SPI_RESP_OFF + KX_BLOB_LEN:
        print(f"  >>> reponse SPI trop courte ({len(resp)} o) pour extraire 40 o a l'offset {SPI_RESP_OFF} "
              f"-> STOP+dump (fail-closed, on ne devine pas). Reponse brute dans $OUT/spi_0x72_resp_raw.bin.", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[1], 1); return
    sensor_resp = bytes(resp[SPI_RESP_OFF:SPI_RESP_OFF + KX_BLOB_LEN])
    print(f"  reponse capteur extraite (40 o @ offset {SPI_RESP_OFF}, OPAQUE) = {sensor_resp.hex()}", flush=True)

    # --- (3) sbio 0x16 : renvoyer au SEP les 40 o du capteur (charge remplacee dans le gabarit) ---
    cmd16 = bytearray(t16); cmd16[GT_PAYLOAD:GT_PAYLOAD + KX_BLOB_LEN] = sensor_resp
    try:
        iface.writemem(ctx["phys_A8"], b"\x00" * ctx["SZ8"])
        dart_rw(ctx["sid_A8"], ctx["IOVA_A8"], data=bytes(cmd16)[:ctx["SZ8"]])
    except Exception as e:
        print(f"  ecriture 0x16 dans A8 impossible : {e} -> STOP (fail-closed).", flush=True); return
    pump_ep0(); sep.msgs[0x08].clear()
    print("  envoi EP 0x08 TAG=0xfc TYPE=0x16 (reponse capteur relayee au SEP)...", flush=True)
    sep.send_msg(SEPMessage(EP=0x08, TAG=0xfc, TYPE=0x16, PARAM=0x00, DATA=0x00000000))
    got16 = []; t0 = time.time()
    while time.time() - t0 < 6:
        pump_ep0()
        while sep.msgs[0x08]:
            m = sep.msgs[0x08].popleft(); got16.append((m.TAG, m.TYPE))
            print(f"    SEP> EP=0x08 TAG=0x{m.TAG:02x} TYPE=0x{m.TYPE:02x} PARAM=0x{m.PARAM:02x} DATA=0x{m.DATA:08x}", flush=True)
        time.sleep(0.02)
    print_dart_fault("apres 0x16")
    try: b8b = iface.readmem(ctx["phys_B8"], ctx["SZ8"])
    except Exception: b8b = b""
    if b8b and os.environ.get("OUT"):
        try: open(os.path.join(os.environ["OUT"], "kx_0x16_B.bin"), "wb").write(b8b)
        except Exception: pass
    print(f"  B8 apres 0x16 : tete={_hexhead(b8b)}", flush=True)

    # --- (4) VERDICT auto-verifiant ---
    ok16 = any(typ == 0x16 for _, typ in got16)
    if ok16:
        print(">>> KEY EXCHANGE RELAYE : le SEP a ACQUITTE 0x16 (< EP=0x08 TYPE=0x16). Le 1er dialogue chiffre "
              "SEP<->capteur a ete relaye NATIVEMENT en lockstep (grand pas). NE PAS conclure 'Touch ID marche' : "
              "restent 0x42/0x18, le patch capteur, les params chiffres, le match, l'enrolement.", flush=True)
    else:
        print(">>> 0x16 NON acquitte par le SEP : le parsing de la reponse SPI est PROBABLEMENT faux "
              f"(offset {SPI_RESP_OFF} ?) -> STOP+dump pour inspection (reponse SPI brute dans $OUT/spi_0x72_resp_raw.bin ; "
              "re-essayer avec un autre SPI_RESP_OFF). Fail-closed.", flush=True)
        dump_wall(ctx, POST_0X73_STEPS[2], 2)

    # --- (5) STOP apres le key exchange (on valide d'abord ce 1er relais lockstep) ---
    print("=== PHASE 4 terminee : on S'ARRETE apres le key exchange (on N'ENCHAINE PAS la suite ce run). ===", flush=True)

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
# PHASE 2 + 3 + 4 : seulement si le SEP s'est STABILISE (idle) ET a annonce sbio (0x08).
#   Le capteur (MesaSPI) est alimente en Phase 3 et VIT jusqu'a la Phase 4 ; le TEARDOWN (power_off +
#   restore) est ICI, dans le finally EXTERNE, et s'execute MEME en cas d'erreur de la Phase 3 ou 4.
# ---------------------------------------------------------------------------
if verdict != "idle":
    print(f">>> Flux non stabilise (verdict={verdict}) : sonde + franchissement NON lances (fail-closed).", flush=True)
elif 0x08 not in sep.epnum2name:
    print(">>> SEP stabilise mais sbio (0x08) non annonce : rien a sonder.", flush=True)
else:
    ctx = probe_sbio()
    mesa = None
    try:
        mesa, crossed = phase3(ctx)
        if crossed and mesa is not None:
            phase4(ctx, mesa)
        else:
            print(">>> 0x17 non franchi : Phase 4 (key exchange 0x15/0x16) non lancee (fail-closed).", flush=True)
    finally:
        # TEARDOWN capteur EXTERNE : remettre spi2 + broche 196 dans l'etat d'iBoot, MEME en cas d'erreur.
        if mesa is not None:
            try: mesa.power_off(); print("  capteur ETEINT (power_off).", flush=True)
            except Exception as e: print(f"  (power_off a echoue : {e})", flush=True)
            try: mesa.restore(); print("  spi2 + broche 196 REMIS dans l'etat d'iBoot (restore).", flush=True)
            except Exception as e: print(f"  (restore a echoue : {e})", flush=True)
PY
