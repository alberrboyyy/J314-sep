#!/usr/bin/env bash
# BUT : J11 PIVOT = J9b (boot chaîné natif, lockers sans UUID = sepd par défaut, skdl/sks/scrd ouverts par le CNTL, UN
#       get_capabilities ACCEPTÉ — J9a vérifié matériel : état 0, theirs 2 → v2 — puis UN set_env ACCEPTÉ, J9b)
#       + UN SEUL `make_system_keybag` STANDALONE, en SAUTANT perform_operation (TAG 0x22), null_d_key (TAG 0x0a) ET
#       create_keybag (TAG 0x01) :
#         `make_system_keybag` (TAG fil 0x0d, TYPE 0x03) : `> EP 0x12 TAG 0x0d TYPE 0x03 PARAM 0 DATA 0x00840000`,
#         OOL A12 = 0x84 o (MÊME corps que la version chaînée J10, condensé v2 inclus).
#       POURQUOI LE PIVOT (journal 2026-11-23, docs/applekeystored_identity.md §8/§9) : J10b a montré que create_keybag
#       0x01 = import-AVEC-données (refus -0xb « argument requis nul » quand les blobs sont vides) — PAS la création
#       d'un keybag vide. La VRAIE création à neuf (le SEP fabrique avec sa clé d'appareil, blob VIDE) =
#       make_system_keybag (TAG fil 0x0d) via identity_load (selector 0x78). J11 l'émet SEUL (sans create_keybag avant)
#       pour voir ce que le SEP répond. docs/sks_native_plan.md §10.
#       CONSÉQUENCE DU STANDALONE : dans la version chaînée (J10, allow_sks=5), le handle chargé (OOL 0x60) venait de la
#       réponse create_keybag (posé par le noyau via finalize_mskb). ICI il n'y a PAS de create avant : le handle chargé
#       (0x60) ET le handle_y (0x58) deviennent des ENTRÉES userland. Le noyau n'insère RIEN et NE recalcule PAS le
#       condensé — il envoie la requête telle que sks_setenv l'a construite (condensé déjà contrôlé par la porte).
#       Gabarit VU AU BINAIRE (kernelcache 27.2.1, `com.apple.driver.AppleSEPKeyStore`, docs/applekeystored_identity.md
#       §6/§8) : en-tête IPC v2 (négociée) + condensé SHA-256/16 v2 recalculé + cdhash neutre ; make_system_keybag =
#       état 1 (const) + handle_y(u64, 0x58) + handle chargé(u32, 0x60) + type(u32, 0x64) + blob{0x10, uuid} + flag 0.
#       Écoute de la réponse 0x8d (TYPE 0x03), RIEN d'autre envoyé à 0x12 / 0x17 / 0x0a, aucune réponse du pilote à un
#       mot reçu. Puis le 0x73 sbio comme J9b.
#
#       *** INCONNUE DU HANDLE (à documenter — ce n'est PAS une hypothèse résolue) ***
#       Un make_system_keybag STANDALONE porte normalement un handle de keybag rendu par une op PRÉALABLE (create ou
#       load). Ici il n'y en a pas : on teste avec handle chargé = 0 (défaut). Si le SEP exige un handle VALIDE d'abord,
#       il REFUSERA le standalone — et ce refus CONFIRMERA qu'une op préalable est obligatoire (→ mur, ou capture macOS
#       pour voir la séquence exacte). Un « marqué system » (PARAM 0) dirait au contraire que le SEP fabrique le keybag
#       système à partir de rien (sa clé d'appareil) sans handle préalable.
#
#       *** SQUELETTE — NON LANÇABLE SANS LES VALEURS USERLAND REQUISES ***
#       uuid (16 o) et type (i32, contrainte VU <= -10) sont INCONNUS (reversés sur le PC), PAS dérivables du binaire.
#       Ce script EXIGE les deux (variables d'env ou arguments) et REFUSE de tourner si l'une manque. Deux valeurs ont
#       un défaut 0 : MSKB_HANDLE (handle chargé, u32, 0x60 — INCONNU, testé à 0) et HANDLE_Y (u64, 0x58). On branchera
#       les vraies valeurs quand le PC les aura (voir docs/sks_userland_values.md du PC).
#       TRANCHE (question centrale) : un make_system_keybag émis SEUL (sans create/load avant) est-il « marqué system »
#       (PARAM 0 : le SEP crée le keybag système à neuf) ou REFUSÉ (il faut un handle/une op préalable) ?
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13, 0x08, 0x17, 0x12, 0x0a, comme J9b),
#       0x13 (xART : store servi par sepd, lockers SANS UUID, SAVE acquittés si demandés), **0x12 : TROIS mots** (portes
#       noyau `sks_ipc::GetcapGate`, `sks_setenv::SetenvGate`, puis `sks_keybag::MskbStandaloneGate` : ces trois mots
#       exacts, une fois chacun ; A12 contrôlé à chaque fois : constantes, condensé v2, forme du cdhash ; les valeurs
#       userland — uuid, type, handle chargé, handle_y — ne sont PAS contrôlées, elles sont libres), 0x08 (UN mot 0x73).
#       AUCUN mot à 0x17/0x0a. AUCUN perform_operation (TAG 0x22), null_d_key (TAG 0x0a) NI create_keybag (TAG 0x01)
#       jamais. Pas de relais. Paramètre : allow_sks=6.
# RISQUE : écriture SEP vers SKS (EP 0x12) — make_system_keybag STANDALONE est une CLASSE/ORDRE JAMAIS TESTÉ sur
#       matériel (3e transaction 0x12 émise SEULE, create_keybag sauté) → 1er run = « go » d'Albert. Aucun secret AP
#       transmis (uuid de 16 o = identifiant, pas une clé ; le matériel de clé du keybag d'appareil est INTERNE au SEP).
#       make_system_keybag peut lier/créer un keybag système : portée exacte côté SEP (persiste-t-il ? re-scelle-t-il en
#       xART ?) INCONNUE. Au pire : PARAM/état inattendu, silence, SEP figé/panique jusqu'au reboot (SEPOS relancé par un
#       `reboot` Linux normal, VU n=7 ; power-cycle = Albert). Effet sur l'état scellé : non attendu de cette op, mais un
#       SAVE (xART) peut survenir pendant le run : copie du store faite AVANT (STORE.avant-j11-<date>) et comparaison
#       APRÈS. macOS déjà déclaré sacrifiable (Albert 2026-11-22) ; filet : alarm_p5.img + backup perso + DFU.
#       ⚠️ SERVICE : le service sep-touchid tient le SEP à chaque boot. AVANT ce run : `touch /etc/sep-touchid/disabled`
#       puis `reboot` (le service ne démarre pas : ConditionPathExists=!/etc/sep-touchid/disabled). APRÈS : vérifier que
#       le store du service n'a pas divergé (voir la fin du script), `rm /etc/sep-touchid/disabled`, puis `reboot`.
#       Ce script REFUSE de tourner si le service est actif, si sepd tourne, ou si STORE = /var/lib/sepd (store du
#       service, jamais servi ici).
# RÉSULTAT ATTENDU : sepd.log = J9a/J9b (4 lockers sans UUID ×2, op 0x07, 0 SAVE) ; dmesg « 'sks' ouvert », getcap
#       « VERDICT sks getcap : RÉPONDU (… theirs 2 → négociée v2 …) », set_env « VERDICT sks setenv : ACCEPTÉ (PARAM 0,
#       état 0 …) », puis « sks make_system_keybag (standalone) : requête acceptée », « sks make_system_keybag STANDALONE
#       > EP 0x12 TAG 0x0d TYPE 0x03 … », puis soit « VERDICT sks make_system_keybag (standalone) : marqué system
#       (PARAM 0 ; handle=0x… si rendu) » soit « REFUS (PARAM …) / SILENCE / NON ENVOYÉ ». sks_mskb_standalone_outcome.bin
#       = les TROIS verdicts décodés (getcap, setenv, make_system standalone) + instantanés B12 (0x80 o). Puis
#       « VERDICT sbio : VIVANT » attendu comme J9b (si MUET : à analyser).
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-23 (J11 PIVOT). JAMAIS LANCÉ.
#       SQUELETTE : non lançable tant que les valeurs userland requises (uuid, type) ne sont pas fournies.
#       1er run = « go » d'Albert (classe/ordre neufs : make_system_keybag émis SEUL, create_keybag sauté).
#
# Usage (root, boot normal SANS le service : /etc/sep-touchid/disabled présent, puis reboot) :
#   UUID=<32 hex, 16 o> TYPE=<i32 <= -10> [MSKB_HANDLE=<u32>] [HANDLE_Y=<u64>] pending/j11_sks_make_system_chained.sh [STORE]
#   (ou en arguments : pending/j11_sks_make_system_chained.sh [STORE] --uuid <hex> --type <i32>
#    [--mskb-handle <u32>] [--handle-y <u64>])
#   MSKB_HANDLE (handle chargé, 0x60) et HANDLE_Y (0x58) ont un défaut 0 (handle INCONNU, testé à 0).
#   STORE = store chaîné d'un seal frais réussi (défaut /var/lib/sepd-run-20261122-230441 : J7b/J8/J9a/J9b, 0 SAVE).
# Binaires attendus ($J15 = /home/albert/kbuild/j15) :
#   sep_native.ko     8a395911a83d0e7faf8c452fa08b6bdd3cfe14f4327a049e6111c9e1c400bfe6 (allow_sks=6, make_system STANDALONE)
#   sks_setenv        c7b722ddcb5d8550cb72a16fd5cc629f4991c1ab97118bb412ebb751648f18f0
#   sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a (= j5..j14, défaut sans UUID)
#   sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd (= j5..j14)
#   sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 (= j5..j14)
set -euo pipefail
J15=${J15:-/home/albert/kbuild/j15}
SERVICE_STORE=/var/lib/sepd

# --- Valeurs userland (env ou arguments). REQUISES : UUID, TYPE. Avec défaut 0 : MSKB_HANDLE, HANDLE_Y ---
UUID=${UUID:-}
TYPE=${TYPE:-}
MSKB_HANDLE=${MSKB_HANDLE:-0}
HANDLE_Y=${HANDLE_Y:-0}
STORE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --uuid)        UUID=$2; shift 2 ;;
    --type)        TYPE=$2; shift 2 ;;
    --mskb-handle) MSKB_HANDLE=$2; shift 2 ;;
    --handle-y)    HANDLE_Y=$2; shift 2 ;;
    --*)           echo "argument inconnu : $1"; exit 2 ;;
    *)             [ -z "$STORE" ] && { STORE=$1; shift; } || { echo "argument en trop : $1"; exit 2; } ;;
  esac
done
STORE=${STORE:-/var/lib/sepd-run-20261122-230441}
HINT="valeurs userland à fournir — voir docs/sks_userland_values.md du PC"
[ -n "$UUID" ] || { echo "UUID (uuid 16 o) manquant : $HINT"; exit 2; }
[ -n "$TYPE" ] || { echo "TYPE (type i32 <= -10) manquant : $HINT"; exit 2; }

[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
want() {  # want FICHIER SHA256
  [ "$(sha256sum "$J15/$1" | cut -d' ' -f1)" = "$2" ] || { echo "$J15/$1 n'est pas le binaire relu (sha256)"; exit 1; }
}
want sep_native.ko     8a395911a83d0e7faf8c452fa08b6bdd3cfe14f4327a049e6111c9e1c400bfe6
want sks_setenv        c7b722ddcb5d8550cb72a16fd5cc629f4991c1ab97118bb412ebb751648f18f0
want sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
want sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd
want sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771
modinfo -F parm "$J15/sep_native.ko" | grep -q "6 (J11" || { echo "$J15/sep_native.ko sans allow_sks=6 (J11)"; exit 1; }
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

LOG=/home/albert/Desktop/sep-touchid/logs/$(date +%Y%m%d-%H%M%S)_j11-sks-make-system-standalone
mkdir -p "$LOG"
echo "valeurs userland : UUID=$UUID TYPE=$TYPE MSKB_HANDLE=$MSKB_HANDLE HANDLE_Y=$HANDLE_Y" | tee "$LOG/userland.txt"
echo "STORE = $STORE (servi tel quel) :" | tee "$LOG/store.txt"; ls -l "$STORE" | tee -a "$LOG/store.txt"
sha256sum "$STORE"/*.bin >> "$LOG/store.txt"
BAK="${STORE%/}.avant-j11-$(date +%Y%m%d-%H%M%S)"; cp -a "$STORE" "$BAK"; echo "copie du store avant run : $BAK" | tee -a "$LOG/store.txt"
(cd "$J15" && sha256sum sep_native.ko sks_setenv sepd sep_native_ovl.ko sep-native.dtbo) > "$LOG/binaires.sha256"
cp "$J15/sep-native.dtbo" /lib/firmware/sep-native.dtbo
[ "$(sha256sum /lib/firmware/sep-native.dtbo | cut -d' ' -f1)" = 8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 ] \
  || { echo "/lib/firmware/sep-native.dtbo ≠ binaire relu"; exit 1; }
insmod "$J15/sep_native_ovl.ko"
insmod "$J15/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=0 \
    sbio_open=1 allow_sks=6 &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
if [ ! -e /dev/sep_native ]; then
    echo "/dev/sep_native absent après 30 s"
    journalctl -k -b --no-pager | grep sep_native > "$LOG/kernel.log" || true
    exit 1
fi
"$J15/sepd" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native 2> "$LOG/sepd.log" &
SEPD=$!
# sks_setenv run --mskb : attend /dev/sep_sks, écrit le get_capabilities, puis (v2 négociée) le set_env, puis
# (set_env ACCEPTÉ) le make_system_keybag STANDALONE (handle chargé = --mskb-handle, envoyé tel quel, pas de finalize),
# lit les TROIS verdicts. cpx-encryption-mode forcé à 2 (valeur de notre ADT). Les valeurs requises (uuid, type) sont
# OBLIGATOIRES : si l'une manque, sks_setenv refuse AVANT d'ouvrir /dev/sep_sks (rien envoyé au SEP).
set +e
"$J15/sks_setenv" run --mskb --uuid "$UUID" --type "$TYPE" --mskb-handle "$MSKB_HANDLE" --handle-y "$HANDLE_Y" \
    --dev /dev/sep_sks --wait-s 300 --cpx 2 --out-dir "$LOG" > "$LOG/sks_mskb.out" 2> "$LOG/sks_mskb.log"
SE=$?
set -e
echo "sks_setenv rc=$SE (0 = make_system_keybag marqué system, 1 = autre verdict final, 2 = rien écrit / erreur)" | tee -a "$LOG/sks_mskb.log"
# Fin du probe (insmod rendu : ligne « table de découverte »), puis journaux.
for i in $(seq 1 1800); do
    journalctl -k -b --no-pager | grep -q "sep_native.*table de découverte" && break
    sleep 0.1
done
sleep 2
journalctl -k -b --no-pager | grep -E "sep_native" > "$LOG/kernel.log" || true
echo "journaux : $LOG (sepd reste lancé, pid $SEPD : le SEP peut encore demander du xART ; reboot pour finir)"
grep -E "sks getcap|sks setenv|sks make_system_keybag|keystore|VERDICT|HALTED|annonce 0x1d|découverte : EP 0x12" "$LOG/kernel.log" || true
cat "$LOG/sks_mskb.out" || true
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
