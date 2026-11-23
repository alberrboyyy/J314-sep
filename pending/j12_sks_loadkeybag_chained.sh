#!/usr/bin/env bash
# BUT : J12 = J9b (boot chaîné natif, lockers sans UUID = sepd par défaut, skdl/sks/scrd ouverts par le CNTL, UN
#       get_capabilities ACCEPTÉ — J9a vérifié matériel : état 0, theirs 2 → v2 — puis UN set_env ACCEPTÉ, J9b)
#       + `load_keybag` (TAG fil 0x03) PUIS `make_system_keybag` CHAÎNÉ (TAG fil 0x0d, TYPE 0x04), en SAUTANT
#       perform_operation (TAG 0x22), null_d_key (TAG 0x0a) ET create_keybag (TAG 0x01) :
#         1) `load_keybag` (TYPE 0x03) : `> EP 0x12 TAG 0x03 TYPE 0x03 PARAM 0 DATA 0x00740000`, OOL A12 = 0x74 o
#            (état 0 + handle_y(u64, 0x58) + blob{len 0x10, uuid @0x64}, condensé v2) ;
#         2) si la réponse est TAG 0x83 PARAM 0 : le noyau lit le handle rendu à OOL B +0x6c (DÉDUIT) et le pose dans
#            `make_system_keybag` CHAÎNÉ (TYPE 0x04, 0x84 o, finalize_mskb + recalcul du condensé), comme allow_sks=5.
#       POURQUOI J12 (journal 2026-11-23, docs/applekeystored_identity.md §6/§8/§9) : create_keybag (0x01) exige des
#       DONNÉES (refus -0xb si corps vide = import-AVEC-données, PAS création à neuf) ; make_system_keybag STANDALONE
#       (J11, 0x0d sans create avant) exige un HANDLE (refus -0xb). CERCLE. L'op JAMAIS TESTÉE qui le brise =
#       `load_keybag` (TAG fil 0x03) : prend un uuid 16 o et DOIT rendre un handle (réponse TAG 0x83, PARAM 0 = OK) —
#       c'est le chaînon uuid → handle → make_system. docs/sks_native_plan.md §11.
#       Gabarit VU AU BINAIRE (kernelcache 27.2.1, `com.apple.driver.AppleSEPKeyStore`, docs/applekeystored_identity.md
#       §6, `__ipc_load_keybag` @0xcdb934 / `_code_ipc_load_keybag` @0xcde92c) ; récupéré du squelette J10 (git a9aadd0),
#       NON vérifié matériel ; aucun code Apple copié.
#
#       *** LES DEUX ISSUES (ce que ce run tranche) ***
#       - load_keybag REND un handle (PARAM 0) : le cercle est brisé, le make_system chaîné part avec ce handle →
#         « marqué system » possible = identité d'appareil native sans macOS.
#       - load_keybag REFUSE (PARAM != 0, p.ex. not found / -0xb) : une identité PRÉ-EXISTANTE (postée par macOS)
#         est requise → prochaine étape = capture macOS pour voir la séquence exacte. make_system n'est alors PAS émis.
#
#       *** SQUELETTE — NON LANÇABLE SANS LES VALEURS USERLAND REQUISES ***
#       uuid (16 o) et type (i32, contrainte VU <= -10) sont INCONNUS (reversés sur le PC), PAS dérivables du binaire.
#       Ce script EXIGE les deux (variables d'env ou arguments) et REFUSE de tourner si l'une manque. HANDLE_Y (u64,
#       0x58) a un défaut 0. PAS de --class (pas de create_keybag). On branchera les vraies valeurs quand le PC les aura
#       (voir docs/sks_userland_values.md du PC).
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13, 0x08, 0x17, 0x12, 0x0a, comme J9b),
#       0x13 (xART : store servi par sepd, lockers SANS UUID, SAVE acquittés si demandés), **0x12 : jusqu'à QUATRE mots**
#       (portes noyau `sks_ipc::GetcapGate`, `sks_setenv::SetenvGate`, `sks_keybag::LoadkeybagGate`, puis — seulement si
#       load_keybag a répondu PARAM 0 — `sks_keybag::MskbGate` : ces mots exacts, une fois chacun ; A12 contrôlé à chaque
#       fois : constantes, condensé v2, forme du cdhash ; les valeurs userland — uuid, type, handle_y — ne sont PAS
#       contrôlées, elles sont libres ; le handle chargé du make_system est posé par le noyau depuis la réponse
#       load_keybag), 0x08 (UN mot 0x73). AUCUN mot à 0x17/0x0a. AUCUN perform_operation (TAG 0x22), null_d_key (TAG
#       0x0a) NI create_keybag (TAG 0x01) jamais. Pas de relais. Paramètre : allow_sks=7.
# RISQUE : écriture SEP vers SKS (EP 0x12) — `load_keybag` est une CLASSE JAMAIS TESTÉE sur matériel → 1er run = « go »
#       d'Albert. Aucun secret AP transmis (uuid de 16 o = identifiant, pas une clé ; le matériel de clé du keybag
#       d'appareil est INTERNE au SEP). load_keybag peut charger/instancier un keybag : portée exacte côté SEP
#       (persiste-t-il ? re-scelle-t-il en xART ? via le make_system chaîné qui suit ?) INCONNUE. Au pire : PARAM/état
#       inattendu, silence, SEP figé/panique jusqu'au reboot (SEPOS relancé par un `reboot` Linux normal, VU n=7 ;
#       power-cycle = Albert). Effet sur l'état scellé : non attendu de load_keybag seul, mais un SAVE (xART) peut
#       survenir pendant le run (surtout si make_system est émis) : copie du store faite AVANT (STORE.avant-j12-<date>)
#       et comparaison APRÈS. macOS déjà déclaré sacrifiable (Albert 2026-11-22) ; filet : alarm_p5.img + backup perso +
#       DFU.
#       ⚠️ SERVICE : le service sep-touchid tient le SEP à chaque boot. AVANT ce run : `touch /etc/sep-touchid/disabled`
#       puis `reboot` (le service ne démarre pas : ConditionPathExists=!/etc/sep-touchid/disabled). APRÈS : vérifier que
#       le store du service n'a pas divergé (voir la fin du script), `rm /etc/sep-touchid/disabled`, puis `reboot`.
#       Ce script REFUSE de tourner si le service est actif, si sepd tourne, ou si STORE = /var/lib/sepd (store du
#       service, jamais servi ici).
# RÉSULTAT ATTENDU : sepd.log = J9a/J9b (4 lockers sans UUID ×2, op 0x07, 0 SAVE) ; dmesg « 'sks' ouvert », getcap
#       « VERDICT sks getcap : RÉPONDU (… theirs 2 → négociée v2 …) », set_env « VERDICT sks setenv : ACCEPTÉ (PARAM 0,
#       état 0 …) », puis « sks load_keybag : requête acceptée », « sks load_keybag > EP 0x12 TAG 0x03 TYPE 0x03 … »,
#       puis soit « VERDICT sks load_keybag : handle=0x… (PARAM 0 … cercle brisé → make_system_keybag chaîné) » suivi de
#       « sks make_system_keybag > … TYPE 0x04 … » et « VERDICT sks make_system_keybag : marqué system / REFUS », soit
#       « VERDICT sks load_keybag : REFUS (PARAM …) » (et make_system NON ENVOYÉ). sks_loadkeybag_outcome.bin = les
#       QUATRE verdicts décodés (getcap, setenv, load_keybag, make_system) + instantanés B12 (0x80 o). Puis
#       « VERDICT sbio : VIVANT » attendu comme J9b (si MUET : à analyser).
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-23 (J12). JAMAIS LANCÉ.
#       SQUELETTE : non lançable tant que les valeurs userland requises (uuid, type) ne sont pas fournies.
#       1er run = « go » d'Albert (classe neuve : load_keybag jamais émis sur matériel).
#
# Usage (root, boot normal SANS le service : /etc/sep-touchid/disabled présent, puis reboot) :
#   UUID=<32 hex, 16 o> TYPE=<i32 <= -10> [HANDLE_Y=<u64>] pending/j12_sks_loadkeybag_chained.sh [STORE]
#   (ou en arguments : pending/j12_sks_loadkeybag_chained.sh [STORE] --uuid <hex> --type <i32> [--handle-y <u64>])
#   HANDLE_Y (0x58) a un défaut 0. PAS de --class (pas de create_keybag).
#   STORE = store chaîné d'un seal frais réussi (défaut /var/lib/sepd-run-20261122-230441 : J7b/J8/J9a/J9b, 0 SAVE).
# Binaires attendus ($J16 = /home/albert/kbuild/j16) :
#   sep_native.ko     145d3ee150018f517958221d91f03d7ba01e32ef8684d24d3a3bc19e69c07e62 (allow_sks=7, load_keybag chaîné)
#   sks_setenv        842b89d6c3cd11ec6cf4ee0896de02ea23ab97fdb1643895a1078cd8d606463b
#   sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a (= j5..j15, défaut sans UUID)
#   sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd (= j5..j15)
#   sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 (= j5..j15)
set -euo pipefail
J16=${J16:-/home/albert/kbuild/j16}
SERVICE_STORE=/var/lib/sepd

# --- Valeurs userland (env ou arguments). REQUISES : UUID, TYPE. Avec défaut 0 : HANDLE_Y ---
UUID=${UUID:-}
TYPE=${TYPE:-}
HANDLE_Y=${HANDLE_Y:-0}
STORE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --uuid)     UUID=$2; shift 2 ;;
    --type)     TYPE=$2; shift 2 ;;
    --handle-y) HANDLE_Y=$2; shift 2 ;;
    --*)        echo "argument inconnu : $1"; exit 2 ;;
    *)          [ -z "$STORE" ] && { STORE=$1; shift; } || { echo "argument en trop : $1"; exit 2; } ;;
  esac
done
STORE=${STORE:-/var/lib/sepd-run-20261122-230441}
HINT="valeurs userland à fournir — voir docs/sks_userland_values.md du PC"
[ -n "$UUID" ] || { echo "UUID (uuid 16 o) manquant : $HINT"; exit 2; }
[ -n "$TYPE" ] || { echo "TYPE (type i32 <= -10) manquant : $HINT"; exit 2; }

[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
want() {  # want FICHIER SHA256
  [ "$(sha256sum "$J16/$1" | cut -d' ' -f1)" = "$2" ] || { echo "$J16/$1 n'est pas le binaire relu (sha256)"; exit 1; }
}
want sep_native.ko     145d3ee150018f517958221d91f03d7ba01e32ef8684d24d3a3bc19e69c07e62
want sks_setenv        842b89d6c3cd11ec6cf4ee0896de02ea23ab97fdb1643895a1078cd8d606463b
want sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
want sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd
want sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771
modinfo -F parm "$J16/sep_native.ko" | grep -q "7 (J12" || { echo "$J16/sep_native.ko sans allow_sks=7 (J12)"; exit 1; }
# Le service ne doit PAS tenir le SEP pendant ce boot.
[ -e /etc/sep-touchid/disabled ] || { echo "/etc/sep-touchid/disabled absent : désactiver le service (touch) puis reboot d'abord"; exit 1; }
if systemctl is-active --quiet sep-touchid 2>/dev/null; then echo "service sep-touchid actif : refus"; exit 1; fi
pgrep -x sepd >/dev/null && { echo "un sepd tourne déjà : refus"; exit 1; }
lsmod | grep -q "^sep_native " && { echo "sep_native déjà chargé (SEP déjà touché depuis ce boot) : reboot d'abord"; exit 1; }
[ -e /dev/sep_native ] && { echo "/dev/sep_native existe déjà : refus"; exit 1; }
# STORE : chaîné, complet, et jamais celui du service.
[ "$(readlink -f "$STORE")" != "$(readlink -f "$SERVICE_STORE")" ] || { echo "STORE = store du service ($SERVICE_STORE) : refus (utiliser une copie, ex. /var/lib/sepd-run-20261122-230441)"; exit 1; }
[ -d "$STORE" ] && [ -n "$(ls -A "$STORE")" ] || { echo "STORE $STORE absent ou vide : ce test exige un store CHAÎNÉ"; exit 1; }
ls "$STORE"/master_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans master_*.bin : pas un boot chaîné"; exit 1; }
ls "$STORE"/locker_save_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans locker_save_*.bin : pas le store d'un seal complet"; exit 1; }
[ -s /etc/sepd/os_uuid ] || { echo "/etc/sepd/os_uuid absent : un store chaîné exige l'UUID du run qui l'a scellé"; exit 1; }
# Même contenu servi que le service (sinon un SAVE ici ou là ferait diverger les deux) : avertissement seulement.
same=1
for f in "$STORE"/master_*.bin "$STORE"/locker_save_*.bin; do
  cmp -s "$f" "$SERVICE_STORE/$(basename "$f")" || same=0
done
[ "$same" = 1 ] || echo "ATTENTION : $STORE diffère de $SERVICE_STORE (master/locker) ; continuer = servir un autre état que le service"
# Mailbox et DART du SEP liées avant l'insmod (sinon probe différé, hors de ce script), comme le service.
bound() { basename "$(readlink -f "$1/driver" 2>/dev/null)" 2>/dev/null || true; }
for i in $(seq 1 600); do
  [ "$(bound /sys/bus/platform/devices/396408000.mbox)" = apple-mailbox ] \
    && [ "$(bound /sys/bus/platform/devices/3952c0000.iommu)" = apple-dart ] && break
  sleep 0.1
done
[ "$(bound /sys/bus/platform/devices/396408000.mbox)" = apple-mailbox ] || { echo "mailbox SEP non liée : refus"; exit 1; }
[ "$(bound /sys/bus/platform/devices/3952c0000.iommu)" = apple-dart ] || { echo "DART SEP non liée : refus"; exit 1; }

LOG=/home/albert/Desktop/sep-touchid/logs/$(date +%Y%m%d-%H%M%S)_j12-sks-loadkeybag-chained
mkdir -p "$LOG"
echo "valeurs userland : UUID=$UUID TYPE=$TYPE HANDLE_Y=$HANDLE_Y" | tee "$LOG/userland.txt"
echo "STORE = $STORE (servi tel quel) :" | tee "$LOG/store.txt"; ls -l "$STORE" | tee -a "$LOG/store.txt"
sha256sum "$STORE"/*.bin >> "$LOG/store.txt"
BAK="${STORE%/}.avant-j12-$(date +%Y%m%d-%H%M%S)"; cp -a "$STORE" "$BAK"; echo "copie du store avant run : $BAK" | tee -a "$LOG/store.txt"
(cd "$J16" && sha256sum sep_native.ko sks_setenv sepd sep_native_ovl.ko sep-native.dtbo) > "$LOG/binaires.sha256"
cp "$J16/sep-native.dtbo" /lib/firmware/sep-native.dtbo
[ "$(sha256sum /lib/firmware/sep-native.dtbo | cut -d' ' -f1)" = 8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 ] \
  || { echo "/lib/firmware/sep-native.dtbo ≠ binaire relu"; exit 1; }
insmod "$J16/sep_native_ovl.ko"
insmod "$J16/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=0 \
    sbio_open=1 allow_sks=7 &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
if [ ! -e /dev/sep_native ]; then
    echo "/dev/sep_native absent après 30 s"
    journalctl -k -b --no-pager | grep sep_native > "$LOG/kernel.log" || true
    exit 1
fi
"$J16/sepd" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native 2> "$LOG/sepd.log" &
SEPD=$!
# sks_setenv run --loadkeybag : attend /dev/sep_sks, écrit le get_capabilities, puis (v2 négociée) le set_env, puis
# (set_env ACCEPTÉ) le load_keybag, puis — seulement si load_keybag répond PARAM 0 — le make_system_keybag CHAÎNÉ
# (handle chargé posé par le noyau depuis la réponse load_keybag, condensé recalculé), lit les QUATRE verdicts.
# cpx-encryption-mode forcé à 2 (valeur de notre ADT). Les valeurs requises (uuid, type) sont OBLIGATOIRES : si l'une
# manque, sks_setenv refuse AVANT d'ouvrir /dev/sep_sks (rien envoyé au SEP).
set +e
"$J16/sks_setenv" run --loadkeybag --uuid "$UUID" --type "$TYPE" --handle-y "$HANDLE_Y" \
    --dev /dev/sep_sks --wait-s 300 --cpx 2 --out-dir "$LOG" > "$LOG/sks_loadkeybag.out" 2> "$LOG/sks_loadkeybag.log"
SE=$?
set -e
echo "sks_setenv rc=$SE (0 = make_system_keybag marqué system, 1 = autre verdict final, 2 = rien écrit / erreur)" | tee -a "$LOG/sks_loadkeybag.log"
# Fin du probe (insmod rendu : ligne « table de découverte »), puis journaux.
for i in $(seq 1 1800); do
    journalctl -k -b --no-pager | grep -q "sep_native.*table de découverte" && break
    sleep 0.1
done
sleep 2
journalctl -k -b --no-pager | grep -E "sep_native" > "$LOG/kernel.log" || true
echo "journaux : $LOG (sepd reste lancé, pid $SEPD : le SEP peut encore demander du xART ; reboot pour finir)"
grep -E "sks getcap|sks setenv|sks load_keybag|sks make_system_keybag|keystore|VERDICT|HALTED|annonce 0x1d|découverte : EP 0x12" "$LOG/kernel.log" || true
cat "$LOG/sks_loadkeybag.out" || true
grep -E "locker|SAVE|STOP" "$LOG/sepd.log" | cut -c15- || true
# Divergence éventuelle avec le store du service (un SAVE pendant ce run) : à régler AVANT de réactiver le service.
diverged=0
for f in "$STORE"/master_*.bin "$STORE"/locker_save_*.bin; do
  cmp -s "$f" "$BAK/$(basename "$f")" || diverged=1
done
if [ "$diverged" = 1 ]; then
  echo "ATTENTION : $STORE a CHANGÉ pendant ce run (SAVE) ; le store du service ($SERVICE_STORE) est désormais PÉRIMÉ pour ce SEP."
  echo "            NE PAS réactiver le service avant décision d'Albert (copier le nouvel état dans le store du service ?)."
else
  echo "store inchangé (0 SAVE) : service réactivable (rm /etc/sep-touchid/disabled ; reboot)."
fi
