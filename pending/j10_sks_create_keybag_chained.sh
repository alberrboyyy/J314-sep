#!/usr/bin/env bash
# BUT : J10 = J9b (boot chaîné natif, lockers sans UUID = sepd par défaut, skdl/sks/scrd ouverts par le CNTL, UN
#       get_capabilities ACCEPTÉ — J9a vérifié matériel : état 0, theirs 2 → v2 — puis UN set_env ACCEPTÉ, J9b)
#       + la VOIE IDENTITÉ d'appareil : en SAUTANT perform_operation (TAG 0x22) ET null_d_key (TAG 0x0a), DEUX
#       transactions SKS enchaînées :
#         1. `load_keybag`        (TAG 0x03) : importe un blob de 16 o (uuid) et REND un handle de keybag.
#            `> EP 0x12 TAG 0x03 TYPE 0x03 PARAM 0 DATA 0x00740000`, OOL A12 = 0x74 o.
#         2. `make_system_keybag` (TAG 0x0d) : marque ce keybag « system » (statut seul, pas de handle).
#            `> EP 0x12 TAG 0x0d TYPE 0x04 PARAM 0 DATA 0x00740000`, OOL A12 = 0x74 o.
#       Gabarits VU AU BINAIRE (kernelcache 27.2.1, `com.apple.driver.AppleSEPKeyStore`, docs/keybag_native_path.md
#       § J10) : en-tête IPC v2 (négociée) + condensé SHA-256/16 v2 recalculé + cdhash neutre ; load_keybag = état 0 +
#       handle_y(u64) + blob{0x10, uuid} ; make_system_keybag = état 1 (const) + handle_y(u64) + handle chargé(u32) +
#       type(u32) + blob VIDE + flag 0. Le noyau LIT le handle rendu par load_keybag (OOL B +0x6c, offset DÉDUIT) et
#       le place lui-même dans le champ +0x60 de make_system_keybag puis RECALCULE le condensé — il n'invente jamais
#       de handle. Le make_system_keybag n'est envoyé qu'APRÈS un load_keybag RÉPONDU (PARAM 0, handle obtenu). Écoute
#       des réponses 0x83 / 0x8d, RIEN d'autre envoyé à 0x12 / 0x17 / 0x0a, aucune réponse du pilote à un mot reçu.
#       Puis le 0x73 sbio comme J9b. docs/sks_native_plan.md (section J10).
#
#       *** SQUELETTE — NON LANÇABLE SANS TROIS VALEURS USERLAND ***
#       uuid (16 o), handle_y (u64), type (i32, contrainte VU <= -10) sont INCONNUS (reversés sur le PC). Ils ne sont
#       PAS dérivables du binaire (politique userland coreauthd/keystored, absente du kernelcache). Ce script EXIGE les
#       trois (variables d'env ou arguments) et REFUSE de tourner si une manque. On branchera les vraies valeurs quand
#       le PC les aura (voir docs/sks_userland_values.md du PC).
#       TRANCHE (question centrale) : un uuid candidat sur load_keybag 0x03 rend-il un handle, ou le SEP exige-t-il une
#       identité DÉJÀ enregistrée (« keybag not found ») ? Et make_system_keybag l'accepte-t-il (PARAM 0) ? Réponse
#       appariée + handle = la voie identité est ouverte ; REFUS/SILENCE/figé = elle ne l'est pas (ou l'uuid ne convient
#       pas, ou l'ordre compte).
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13, 0x08, 0x17, 0x12, 0x0a, comme J9b),
#       0x13 (xART : store servi par sepd, lockers SANS UUID, SAVE acquittés si demandés), **0x12 : QUATRE mots** (portes
#       noyau `sks_ipc::GetcapGate`, `sks_setenv::SetenvGate`, puis `sks_keybag::LoadkeybagGate` et `MskbGate` : ces
#       quatre mots exacts, une fois chacun ; A12 contrôlé à chaque fois : constantes, condensé v2, forme du cdhash ;
#       les valeurs userland — uuid, handle_y, type — ne sont PAS contrôlées, elles sont libres), 0x08 (UN mot 0x73).
#       AUCUN mot à 0x17/0x0a. AUCUN perform_operation (TAG 0x22) NI null_d_key (TAG 0x0a) jamais. Pas de relais.
#       Paramètre : allow_sks=5.
# RISQUE : écriture SEP vers SKS (EP 0x12) — load_keybag ET make_system_keybag sont des CLASSES DE MESSAGE JAMAIS
#       TESTÉES sur matériel (4e/5e types 0x12, après get_capabilities/set_env) → 1er run = « go » d'Albert. La voie
#       identité ne transmet AUCUN secret AP (blob make_system_keybag VIDE ; load_keybag ne porte qu'un uuid de 16 o,
#       un identifiant, pas une clé) : le matériel de clé du keybag d'appareil est INTERNE au SEP. load_keybag importe
#       un keybag (« charger ») : un uuid inattendu peut être refusé (« keybag not found »), bénin ; mais la portée
#       exacte côté SEP (crée-t-il à la volée ? persiste-t-il ? re-scelle-t-il en xART ?) est INCONNUE. Au pire :
#       PARAM/état inattendu, silence, SEP figé/panique jusqu'au reboot (SEPOS relancé par un `reboot` Linux normal,
#       VU n=7 ; power-cycle = Albert). Effet sur l'état scellé : non attendu de ces deux ops, mais un SAVE (xART) peut
#       quand même survenir pendant le run : copie du store faite AVANT (STORE.avant-j10-<date>) et comparaison APRÈS.
#       macOS déjà déclaré sacrifiable (Albert 2026-11-22) ; filet : alarm_p5.img + backup perso + DFU.
#       ⚠️ SERVICE : le service sep-touchid tient le SEP à chaque boot. AVANT ce run : `touch /etc/sep-touchid/disabled`
#       puis `reboot` (le service ne démarre pas : ConditionPathExists=!/etc/sep-touchid/disabled). APRÈS : vérifier que
#       le store du service n'a pas divergé (voir la fin du script), `rm /etc/sep-touchid/disabled`, puis `reboot`.
#       Ce script REFUSE de tourner si le service est actif, si sepd tourne, ou si STORE = /var/lib/sepd (store du
#       service, jamais servi ici).
# RÉSULTAT ATTENDU : sepd.log = J9a/J9b (4 lockers sans UUID ×2, op 0x07, 0 SAVE) ; dmesg « 'sks' ouvert », getcap
#       « VERDICT sks getcap : RÉPONDU (… theirs 2 → négociée v2 …) », set_env « VERDICT sks setenv : ACCEPTÉ (PARAM 0,
#       état 0 …) », puis « sks load_keybag : requête acceptée », « sks load_keybag > EP 0x12 TAG 0x03 … », puis soit
#       « VERDICT sks loadkeybag : handle=0x… (PARAM 0 …) » (handle obtenu → make_system_keybag enchaîné) soit
#       « VERDICT sks loadkeybag : REFUS (PARAM …) / REFUS/SILENCE / NON ENVOYÉ » (voie fermée ou valeurs manquantes) ;
#       si handle obtenu : « sks make_system_keybag > EP 0x12 TAG 0x0d … handle chargé 0x… » puis « VERDICT sks
#       make_system_keybag : marqué system (PARAM 0) » ou « REFUS (PARAM …) ». sks_keybag_outcome.bin = les QUATRE
#       verdicts décodés (getcap, setenv, load_keybag, make_system_keybag) + instantanés B12 (0x80 o). Puis
#       « VERDICT sbio : VIVANT » attendu comme J9b (si MUET : à analyser).
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-23. JAMAIS LANCÉ. SQUELETTE : non lançable tant que les trois
#       valeurs userland (uuid, handle_y, type) ne sont pas fournies. 1er run = « go » d'Albert (classes de message
#       neuves : load_keybag + make_system_keybag, ET ordre neuf : perform_operation ET null_d_key sautés).
#
# Usage (root, boot normal SANS le service : /etc/sep-touchid/disabled présent, puis reboot) :
#   UUID=<32 hex, 16 o> HANDLE=<u64> TYPE=<i32 <= -10> pending/j10_sks_create_keybag_chained.sh [STORE]
#   (ou en arguments : pending/j10_sks_create_keybag_chained.sh [STORE] --uuid <hex> --handle <u64> --type <i32>)
#   STORE = store chaîné d'un seal frais réussi (défaut /var/lib/sepd-run-20261122-230441 : J7b/J8/J9a/J9b, 0 SAVE).
# Binaires attendus ($J12 = /home/albert/kbuild/j12) :
#   sep_native.ko     a2d9e2eed2f8decfb995f3cf3f93688f9fac033e53384612c76397aff860f5b8 (allow_sks=5)
#   sks_setenv        e162e0289f9ca6ea448840a0b46d985f924cb9e556dcbdcaecca109fd2d33831
#   sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a (= j5/j9/j10/j11, défaut sans UUID)
#   sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd (= j5/j9/j10/j11)
#   sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 (= j5/j9/j10/j11)
set -euo pipefail
J12=${J12:-/home/albert/kbuild/j12}
SERVICE_STORE=/var/lib/sepd

# --- Les TROIS valeurs userland (env ou arguments) : OBLIGATOIRES, aucune valeur par défaut ---
UUID=${UUID:-}
HANDLE=${HANDLE:-}
TYPE=${TYPE:-}
STORE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --uuid)   UUID=$2; shift 2 ;;
    --handle) HANDLE=$2; shift 2 ;;
    --type)   TYPE=$2; shift 2 ;;
    --*)      echo "argument inconnu : $1"; exit 2 ;;
    *)        [ -z "$STORE" ] && { STORE=$1; shift; } || { echo "argument en trop : $1"; exit 2; } ;;
  esac
done
STORE=${STORE:-/var/lib/sepd-run-20261122-230441}
HINT="valeurs userland à fournir — voir docs/sks_userland_values.md du PC"
[ -n "$UUID" ]   || { echo "UUID (uuid 16 o) manquant : $HINT"; exit 2; }
[ -n "$HANDLE" ] || { echo "HANDLE (handle_y u64) manquant : $HINT"; exit 2; }
[ -n "$TYPE" ]   || { echo "TYPE (type i32 <= -10) manquant : $HINT"; exit 2; }

[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
want() {  # want FICHIER SHA256
  [ "$(sha256sum "$J12/$1" | cut -d' ' -f1)" = "$2" ] || { echo "$J12/$1 n'est pas le binaire relu (sha256)"; exit 1; }
}
want sep_native.ko     a2d9e2eed2f8decfb995f3cf3f93688f9fac033e53384612c76397aff860f5b8
want sks_setenv        e162e0289f9ca6ea448840a0b46d985f924cb9e556dcbdcaecca109fd2d33831
want sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
want sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd
want sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771
modinfo -F parm "$J12/sep_native.ko" | grep -q "^allow_sks:.*5 (J10" || { echo "$J12/sep_native.ko sans allow_sks=5 (J10)"; exit 1; }
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

LOG=/home/albert/Desktop/sep-touchid/logs/$(date +%Y%m%d-%H%M%S)_j10-sks-keybag-chained
mkdir -p "$LOG"
echo "valeurs userland : UUID=$UUID HANDLE=$HANDLE TYPE=$TYPE" | tee "$LOG/userland.txt"
echo "STORE = $STORE (servi tel quel) :" | tee "$LOG/store.txt"; ls -l "$STORE" | tee -a "$LOG/store.txt"
sha256sum "$STORE"/*.bin >> "$LOG/store.txt"
BAK="${STORE%/}.avant-j10-$(date +%Y%m%d-%H%M%S)"; cp -a "$STORE" "$BAK"; echo "copie du store avant run : $BAK" | tee -a "$LOG/store.txt"
(cd "$J12" && sha256sum sep_native.ko sks_setenv sepd sep_native_ovl.ko sep-native.dtbo) > "$LOG/binaires.sha256"
cp "$J12/sep-native.dtbo" /lib/firmware/sep-native.dtbo
[ "$(sha256sum /lib/firmware/sep-native.dtbo | cut -d' ' -f1)" = 8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 ] \
  || { echo "/lib/firmware/sep-native.dtbo ≠ binaire relu"; exit 1; }
insmod "$J12/sep_native_ovl.ko"
insmod "$J12/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=0 \
    sbio_open=1 allow_sks=5 &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
if [ ! -e /dev/sep_native ]; then
    echo "/dev/sep_native absent après 30 s"
    journalctl -k -b --no-pager | grep sep_native > "$LOG/kernel.log" || true
    exit 1
fi
"$J12/sepd" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native 2> "$LOG/sepd.log" &
SEPD=$!
# sks_setenv run --keybag : attend /dev/sep_sks, écrit le get_capabilities, puis (v2 négociée) le set_env, puis
# (set_env ACCEPTÉ) le load_keybag, puis le make_system_keybag (le noyau y place le handle rendu), lit les QUATRE
# verdicts. cpx-encryption-mode forcé à 2 (valeur de notre ADT). Les trois valeurs userland sont OBLIGATOIRES : si
# l'une manque, sks_setenv refuse AVANT d'ouvrir /dev/sep_sks (rien envoyé au SEP).
set +e
"$J12/sks_setenv" run --keybag --uuid "$UUID" --handle "$HANDLE" --type "$TYPE" \
    --dev /dev/sep_sks --wait-s 300 --cpx 2 --out-dir "$LOG" > "$LOG/sks_keybag.out" 2> "$LOG/sks_keybag.log"
SE=$?
set -e
echo "sks_setenv rc=$SE (0 = make_system_keybag marqué system, 1 = autre verdict final, 2 = rien écrit / erreur)" | tee -a "$LOG/sks_keybag.log"
# Fin du probe (insmod rendu : ligne « table de découverte »), puis journaux.
for i in $(seq 1 1800); do
    journalctl -k -b --no-pager | grep -q "sep_native.*table de découverte" && break
    sleep 0.1
done
sleep 2
journalctl -k -b --no-pager | grep -E "sep_native" > "$LOG/kernel.log" || true
echo "journaux : $LOG (sepd reste lancé, pid $SEPD : le SEP peut encore demander du xART ; reboot pour finir)"
grep -E "sks getcap|sks setenv|sks load_keybag|sks make_system_keybag|loadkeybag|keystore|VERDICT|HALTED|annonce 0x1d|découverte : EP 0x12" "$LOG/kernel.log" || true
cat "$LOG/sks_keybag.out" || true
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
