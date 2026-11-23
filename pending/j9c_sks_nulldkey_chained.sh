#!/usr/bin/env bash
# BUT : J9c = J9b (boot chaîné natif, lockers sans UUID = sepd par défaut, skdl/sks/scrd ouverts par le CNTL, UN
#       get_capabilities ACCEPTÉ par le SEP — J9a vérifié matériel : état 0, theirs 2 → v2 — puis UN set_env, J9b)
#       + UNE TROISIÈME transaction SKS : `null_d_key` (TAG 0x0a), en SAUTANT les deux perform_operation (TAG 0x22,
#       txn3/txn5 du bring-up macOS). `> EP 0x12 TAG 0x0a TYPE 0x03 PARAM 0 DATA 0x00600000`, OOL A12 = 0x60 o. Le
#       format du corps 0x60 o est ÉTABLI AU BINAIRE (VU, PAS une hypothèse) : kernelcache 27.2.1,
#       `__ipc_null_d_key` @0xfffffe0009cdbbd0 + `_code_ipc_null_d_key` @0xfffffe0009cdfc38 — le codec écrit en-tête
#       IPC (0x54) + état u32 (0) + u64 (= arg2 de __ipc_null_d_key, que l'unique appelant effaceable_init passe à 1),
#       SANS mot de longueur de blob et SANS blob → total 0x60 (recoupe la trace c12 L186). En-tête v2 (négociée),
#       condensé SHA-256/16 v2 recalculé, cdhash neutre. Le noyau n'envoie le null_d_key qu'APRÈS que le set_env a été
#       ACCEPTÉ (état 0) ; il n'envoie JAMAIS de perform_operation. Écoute de la réponse 0x8a, RIEN d'autre envoyé à
#       0x12 / 0x17 / 0x0a, aucune réponse du pilote à un mot reçu. Puis le 0x73 sbio comme J9b.
#       docs/sks_native_plan.md (section J9c).
#       TRANCHE (question centrale) : peut-on SAUTER les deux perform_operation ? Si le SEP répond au null_d_key appairé
#       (TAG bit 7, TYPE 0x03) — en particulier PARAM 0xff comme macOS (« pas de d-key à annuler », bénin) — alors
#       txn3/txn5 N'ÉTAIENT PAS un prérequis et on peut avancer. Si ERREUR appariée d'un autre type, SILENCE, ou le SEP
#       se fige/Halted → ils le sont (ou l'ordre compte).
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13, 0x08, 0x17, 0x12, 0x0a, comme J9b),
#       0x13 (xART : store servi par sepd, lockers SANS UUID, SAVE acquittés si demandés), **0x12 : TROIS mots** (portes
#       noyau `sks_ipc::GetcapGate`, `sks_setenv::SetenvGate`, puis `sks_nulldkey::NulldkeyGate` : ces trois mots exacts,
#       une fois chacun ; A12 contrôlé à chaque fois : constantes, condensé v2, forme du cdhash), 0x08 (UN mot 0x73).
#       AUCUN mot à 0x17/0x0a. AUCUN perform_operation (TAG 0x22) jamais. Pas de relais (allow_sbio_relay=0).
#       Paramètre : allow_sks=4.
# RISQUE : écriture SEP vers SKS (EP 0x12) — null_d_key est une CLASSE DE MESSAGE JAMAIS TESTÉE sur matériel (3e type
#       0x12, après get_capabilities et set_env) → 1er run = « go » d'Albert. null_d_key = « annuler la d-key » : aucune
#       clé, aucun keybag, aucun mot de passe, aucune donnée de stockage n'est transmis (le corps = en-tête + un état à 0
#       + l'entier 1) ; sous macOS le SEP y répond PARAM 0xff (il n'y a pas de d-key à annuler) et le kext ne décode
#       aucun corps de réponse. On SAUTE sciemment les deux perform_operation du bring-up : c'est précisément ce qu'on
#       teste, et c'est un ordre que macOS n'émet pas (le SEP pourrait réagir autrement). Au pire : PARAM/état inattendu,
#       silence, ou un SEP qui se fige / panique jusqu'au reboot (SEPOS est relancé par un `reboot` Linux normal, VU n=7 ;
#       power-cycle = Albert). Effet sur l'état scellé : non attendu (null_d_key n'est pas une opération de stockage) ;
#       le store servi peut quand même être modifié par un SAVE (xART) : copie faite AVANT (STORE.avant-j9c-<date>).
#       macOS déjà déclaré sacrifiable (Albert 2026-11-22) ; filet : alarm_p5.img + backup perso + DFU.
#       ⚠️ SERVICE : le service sep-touchid tient le SEP à chaque boot. AVANT ce run : `touch /etc/sep-touchid/disabled`
#       puis `reboot` (le service ne démarre pas : ConditionPathExists=!/etc/sep-touchid/disabled). APRÈS : vérifier que
#       le store du service n'a pas divergé (voir la fin du script), `rm /etc/sep-touchid/disabled`, puis `reboot`.
#       Ce script REFUSE de tourner si le service est actif, si sepd tourne, ou si STORE = /var/lib/sepd (store du
#       service, jamais servi ici).
# RÉSULTAT ATTENDU : sepd.log = J9a/J9b (4 lockers sans UUID ×2, op 0x07, 0 SAVE) ; dmesg « 'sks' ouvert », getcap
#       « VERDICT sks getcap : RÉPONDU (… theirs 2 → négociée v2 …) », set_env « VERDICT sks setenv : ACCEPTÉ (PARAM 0,
#       état 0 …) », puis « sks null_d_key : requête acceptée », « sks null_d_key > EP 0x12 TAG 0x0a … perform_operation
#       SAUTÉS », puis soit « sks null_d_key < réponse appariée : TAG 0x8a … PARAM -1 … » et « VERDICT sks null_d_key :
#       RÉPONDU (PARAM -1 …) ; PARAM 0xff = comme macOS » (⇒ perform_operation NON prérequis, on avance), soit « VERDICT
#       sks null_d_key : RÉPONDU (PARAM … ≠ 0xff) » / « SILENCE » / « NON ENVOYÉ » (set_env non ACCEPTÉ), à interpréter.
#       sks_nulldkey_outcome.bin = les TROIS verdicts décodés (getcap, setenv, null_d_key) + instantané B12 (0x80 o) du
#       null_d_key. Puis « VERDICT sbio : VIVANT » attendu comme J9b (si MUET : à analyser).
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-23. JAMAIS LANCÉ. 1er run = « go » d'Albert (classe de message
#       neuve : null_d_key, ET ordre neuf : perform_operation sautés).
#
# Usage (root, boot normal SANS le service : /etc/sep-touchid/disabled présent, puis reboot) :
#   pending/j9c_sks_nulldkey_chained.sh STORE
#   STORE = store chaîné d'un seal frais réussi, ex. /var/lib/sepd-run-20261122-230441 (J7b/J8/J9a/J9b : 0 SAVE).
# Binaires attendus ($J11 = /home/albert/kbuild/j11) :
#   sep_native.ko     4a5858a317274922adfa10b4293969c2c555a2981f9ea90c8db027f177182b49 (allow_sks=4)
#   sks_setenv        c81a45473926be0b03cb6a69f50a40baccbb87a90dafcbf5623b5dae373658e9
#   sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a (= j5/j9/j10, défaut sans UUID)
#   sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd (= j5/j9/j10)
#   sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 (= j5/j9/j10)
set -euo pipefail
J11=${J11:-/home/albert/kbuild/j11}
SERVICE_STORE=/var/lib/sepd
STORE=${1:-/var/lib/sepd-run-20261122-230441}
[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
want() {  # want FICHIER SHA256
  [ "$(sha256sum "$J11/$1" | cut -d' ' -f1)" = "$2" ] || { echo "$J11/$1 n'est pas le binaire relu (sha256)"; exit 1; }
}
want sep_native.ko     4a5858a317274922adfa10b4293969c2c555a2981f9ea90c8db027f177182b49
want sks_setenv        c81a45473926be0b03cb6a69f50a40baccbb87a90dafcbf5623b5dae373658e9
want sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
want sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd
want sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771
modinfo -F parm "$J11/sep_native.ko" | grep -q "^allow_sks:.*4 (J9c)" || { echo "$J11/sep_native.ko sans allow_sks=4 (J9c)"; exit 1; }
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

LOG=/home/albert/Desktop/sep-touchid/logs/$(date +%Y%m%d-%H%M%S)_j9c-sks-nulldkey-chained
mkdir -p "$LOG"
echo "STORE = $STORE (servi tel quel) :" | tee "$LOG/store.txt"; ls -l "$STORE" | tee -a "$LOG/store.txt"
sha256sum "$STORE"/*.bin >> "$LOG/store.txt"
BAK="${STORE%/}.avant-j9c-$(date +%Y%m%d-%H%M%S)"; cp -a "$STORE" "$BAK"; echo "copie du store avant run : $BAK" | tee -a "$LOG/store.txt"
(cd "$J11" && sha256sum sep_native.ko sks_setenv sepd sep_native_ovl.ko sep-native.dtbo) > "$LOG/binaires.sha256"
cp "$J11/sep-native.dtbo" /lib/firmware/sep-native.dtbo
[ "$(sha256sum /lib/firmware/sep-native.dtbo | cut -d' ' -f1)" = 8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 ] \
  || { echo "/lib/firmware/sep-native.dtbo ≠ binaire relu"; exit 1; }
insmod "$J11/sep_native_ovl.ko"
insmod "$J11/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=0 \
    sbio_open=1 allow_sks=4 &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
if [ ! -e /dev/sep_native ]; then
    echo "/dev/sep_native absent après 30 s"
    journalctl -k -b --no-pager | grep sep_native > "$LOG/kernel.log" || true
    exit 1
fi
"$J11/sepd" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native 2> "$LOG/sepd.log" &
SEPD=$!
# sks_setenv --nulldkey : attend /dev/sep_sks, écrit le get_capabilities, puis (v2 négociée) le set_env, puis (set_env
# ACCEPTÉ) le null_d_key, lit les TROIS verdicts. cpx-encryption-mode forcé à 2 (valeur de notre ADT).
set +e
"$J11/sks_setenv" run --nulldkey --dev /dev/sep_sks --wait-s 300 --cpx 2 --out-dir "$LOG" > "$LOG/sks_nulldkey.out" 2> "$LOG/sks_nulldkey.log"
SE=$?
set -e
echo "sks_setenv rc=$SE (0 = null_d_key RÉPONDU, 1 = autre verdict final, 2 = rien écrit / erreur)" | tee -a "$LOG/sks_nulldkey.log"
# Fin du probe (insmod rendu : ligne « table de découverte »), puis journaux.
for i in $(seq 1 1800); do
    journalctl -k -b --no-pager | grep -q "sep_native.*table de découverte" && break
    sleep 0.1
done
sleep 2
journalctl -k -b --no-pager | grep -E "sep_native" > "$LOG/kernel.log" || true
echo "journaux : $LOG (sepd reste lancé, pid $SEPD : le SEP peut encore demander du xART ; reboot pour finir)"
grep -E "sks getcap|sks setenv|sks null_d_key|keystore|VERDICT|HALTED|annonce 0x1d|découverte : EP 0x12" "$LOG/kernel.log" || true
cat "$LOG/sks_nulldkey.out" || true
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
