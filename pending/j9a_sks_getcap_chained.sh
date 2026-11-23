#!/usr/bin/env bash
# BUT : J9a = J7b (boot chaîné natif, lockers servis sans UUID = sepd par défaut, skdl/sks/scrd ouverts par le CNTL,
#       vérifié n=2) + UN SEUL message vers SKS : `get_capabilities`, la 1re transaction de chaque boot macOS (6/6),
#       `> EP 0x12 TAG 0x4d TYPE 0x01 PARAM 0 DATA 0x00640000`, OOL A12 = 0x64 o construits d'après
#       docs/sks_protocol.md §1.6 (source: kext 13.5, NON vérifié matériel) par `sks_getcap run` (valeurs neutres :
#       horodatage CLOCK_MONOTONIC µs, uniqueid 0, uid 0, cdhash = SHA-1 des 8 o de l'uniqueid, condensé SHA-256/16
#       recalculé). Écoute 10 s de la réponse, RIEN d'autre envoyé à 0x12 / 0x17 / 0x0a, aucune réponse du pilote à un
#       mot reçu. Puis le 0x73 sbio comme J7b (voir si quelque chose change). docs/sks_native_plan.md §6.
#       Tranche : (a) le SEP répond-il à un get_capabilities construit sous Linux (champs processus neutres) ?
#       (b) avec quoi : PARAM (statut), état, « theirs » (version d'en-tête IPC du SEP, jamais capturée), disposition
#       de la réponse 0x5c (L = 0x48 seulement DÉDUIT) ; (c) la suite (0x73 sbio) change-t-elle ?
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13, 0x08, 0x17, 0x12, 0x0a, comme J7b),
#       0x13 (xART : store servi par sepd, lockers SANS UUID, SAVE acquittés si demandés), **0x12 : UN mot** (porte
#       noyau `sks_ipc::GetcapGate` : ce mot exact, une fois ; A12 contrôlé : constantes, condensé, forme du cdhash),
#       0x08 (UN mot 0x73). AUCUN mot à 0x17/0x0a. Pas de relais (allow_sbio_relay=0). Paramètre : allow_sks=2.
# RISQUE : écriture SEP vers SKS (EP 0x12) = CLASSE JAMAIS TESTÉE sur matériel → 1er run = « go » d'Albert.
#       get_capabilities est une négociation de version d'en-tête : aucune clé, aucun keybag, aucun mot de passe ; le kext
#       macOS continue même en échec (« defaulting to v1 »). Au pire : PARAM ≠ 0 (refus), silence, ou un SEP qui se
#       fige / panique jusqu'au reboot (SEPOS est relancé par un `reboot` Linux normal, VU n=7 ; power-cycle = Albert).
#       Effet sur l'état scellé : inconnu mais non attendu (get_capabilities n'est pas une opération de stockage) ;
#       le store servi peut quand même être modifié par un SAVE (xART) : copie faite AVANT (STORE.avant-j9a-<date>).
#       macOS déjà déclaré sacrifiable (Albert 2026-11-22) ; filet : alarm_p5.img + backup perso + DFU.
#       ⚠️ SERVICE : le service sep-touchid tient le SEP à chaque boot. AVANT ce run : `touch /etc/sep-touchid/disabled`
#       puis `reboot` (le service ne démarre pas : ConditionPathExists=!/etc/sep-touchid/disabled). APRÈS : vérifier que
#       le store du service n'a pas divergé (voir la fin du script), `rm /etc/sep-touchid/disabled`, puis `reboot`.
#       Ce script REFUSE de tourner si le service est actif, si sepd tourne, ou si STORE = /var/lib/sepd (store du
#       service, jamais servi ici).
# RÉSULTAT ATTENDU : sepd.log = J7b (4 lockers sans UUID ×2, op 0x07, 0 SAVE) ; dmesg « 'sks' ouvert », « sks getcap :
#       requête acceptée », « sks getcap > EP 0x12 TAG 0x4d … », puis soit « sks getcap < réponse appariée : TAG 0xcd …
#       DATA 0x005c0001 » et « VERDICT sks getcap : RÉPONDU (PARAM 0, état 0, theirs N → négociée vM ; L 0x48 …) »
#       (macOS : réponse 1,25 ms après la requête, c12 L178-179), soit « VERDICT sks getcap : ERREUR (PARAM … ) » (le SEP
#       refuse nos champs neutres), soit « SILENCE ». sks_getcap.log = le même verdict décodé + instantané B12 (0x80 o).
#       Puis « VERDICT sbio : VIVANT » attendu comme J7b (si MUET : à analyser, le get_capabilities a changé quelque chose).
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-23. JAMAIS LANCÉ. 1er run = « go » d'Albert.
#
# Usage (root, boot normal SANS le service : /etc/sep-touchid/disabled présent, puis reboot) :
#   pending/j9a_sks_getcap_chained.sh STORE
#   STORE = store chaîné d'un seal frais réussi, ex. /var/lib/sepd-run-20261122-230441 (identique octet pour octet à
#           /var/lib/sepd le 2026-11-23 10:00, cmp des 5 .bin ; J7b/J8 n'y ont fait 0 SAVE).
# Binaires attendus ($J9 = /home/albert/kbuild/j9) :
#   sep_native.ko     145804d0b31871b0d5c6b266dce464770bb8467d9631384ed362ef5cb796f334 (allow_sks=2)
#   sks_getcap        c25a6193938b308dfafdde6e2f74382d1a7d1336aed83e68b247cc39ad0715c9
#   sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a (= j5, défaut sans UUID)
#   sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd (= j5)
#   sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 (= j5)
set -euo pipefail
J9=${J9:-/home/albert/kbuild/j9}
SERVICE_STORE=/var/lib/sepd
STORE=${1:?usage: $0 STORE (store xART d un seal frais reussi, non vide, PAS /var/lib/sepd)}
[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
want() {  # want FICHIER SHA256
  [ "$(sha256sum "$J9/$1" | cut -d' ' -f1)" = "$2" ] || { echo "$J9/$1 n'est pas le binaire relu (sha256)"; exit 1; }
}
want sep_native.ko     145804d0b31871b0d5c6b266dce464770bb8467d9631384ed362ef5cb796f334
want sks_getcap        c25a6193938b308dfafdde6e2f74382d1a7d1336aed83e68b247cc39ad0715c9
want sepd              6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
want sep_native_ovl.ko 02c1fcc2fb9b19363a89a8ad818422411eb968110720d039d3b822029ad517cd
want sep-native.dtbo   8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771
modinfo -F parm "$J9/sep_native.ko" | grep -q "^allow_sks:.*2 (J9a)" || { echo "$J9/sep_native.ko sans allow_sks=2 (J9a)"; exit 1; }
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

LOG=/home/albert/Desktop/sep-touchid/logs/$(date +%Y%m%d-%H%M%S)_j9a-sks-getcap-chained
mkdir -p "$LOG"
echo "STORE = $STORE (servi tel quel) :" | tee "$LOG/store.txt"; ls -l "$STORE" | tee -a "$LOG/store.txt"
sha256sum "$STORE"/*.bin >> "$LOG/store.txt"
BAK="${STORE%/}.avant-j9a-$(date +%Y%m%d-%H%M%S)"; cp -a "$STORE" "$BAK"; echo "copie du store avant run : $BAK" | tee -a "$LOG/store.txt"
(cd "$J9" && sha256sum sep_native.ko sks_getcap sepd sep_native_ovl.ko sep-native.dtbo) > "$LOG/binaires.sha256"
cp "$J9/sep-native.dtbo" /lib/firmware/sep-native.dtbo
[ "$(sha256sum /lib/firmware/sep-native.dtbo | cut -d' ' -f1)" = 8adbcb089a430fa63718c90a43dd5423afe0d52c8bfd0dc7eab0d60c51119771 ] \
  || { echo "/lib/firmware/sep-native.dtbo ≠ binaire relu"; exit 1; }
insmod "$J9/sep_native_ovl.ko"
insmod "$J9/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=0 \
    sbio_open=1 allow_sks=2 &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
if [ ! -e /dev/sep_native ]; then
    echo "/dev/sep_native absent après 30 s"
    journalctl -k -b --no-pager | grep sep_native > "$LOG/kernel.log" || true
    exit 1
fi
"$J9/sepd" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native 2> "$LOG/sepd.log" &
SEPD=$!
# sks_getcap : attend /dev/sep_sks, n'écrit la requête que quand le noyau la demande (skdl/sks/scrd ouverts), lit le verdict.
set +e
"$J9/sks_getcap" run --dev /dev/sep_sks --wait-s 300 --out-dir "$LOG" > "$LOG/sks_getcap.out" 2> "$LOG/sks_getcap.log"
GC=$?
set -e
echo "sks_getcap rc=$GC (0 = RÉPONDU, 1 = autre verdict, 2 = rien écrit / erreur)" | tee -a "$LOG/sks_getcap.log"
# Fin du probe (insmod rendu : ligne « table de découverte »), puis journaux.
for i in $(seq 1 1800); do
    journalctl -k -b --no-pager | grep -q "sep_native.*table de découverte" && break
    sleep 0.1
done
sleep 2
journalctl -k -b --no-pager | grep -E "sep_native" > "$LOG/kernel.log" || true
echo "journaux : $LOG (sepd reste lancé, pid $SEPD : le SEP peut encore demander du xART ; reboot pour finir)"
grep -E "sks getcap|keystore|VERDICT|HALTED|annonce 0x1d|découverte : EP 0x12" "$LOG/kernel.log" || true
cat "$LOG/sks_getcap.out" || true
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
