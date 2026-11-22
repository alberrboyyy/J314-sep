#!/usr/bin/env bash
# BUT : J7b = J7a (docs/sks_native_plan.md §4 exp. 1) à UNE différence près : sepd sert chaque locker FETCH (op 0x05)
#       SANS ses 16 premiers octets (l'UUID), c.-à-d. A = B[16..] du SAVE, au lieu du B entier (J3b/J3d/J7a).
#       Pourquoi : sur 4 boots chaînés natifs (J3 ABSENT, J3b/J3d/J7a verbatim), le SEP réagit pareil — 2 FETCH du
#       locker 407e94c4…, puis silence, ni SAVE ni locker suivant, sks jamais annoncé en 0xFD ⇒ le locker servi a le
#       même effet qu'un locker absent. macOS (c12) enchaîne, lui, 7 opérations locker puis FD sks. Indices (hypothèse) :
#       un A FETCH gigalocker macOS commence par la charge, pas par l'UUID (gigalocker.md, snew-reel seq133) ; le slot .gl
#       de 9133c5d5… fait 0x28 = 40 o = son SAVE B (56 o) − 16. Kext op 0x05/0x06 NON relu (binaire sur le PC c9).
#       Tranche : (a) le SEP accepte-t-il le locker sans UUID (il demande alors le locker suivant 9133c5d5…, puis
#       e01e3b5e…, 2438821b…) ? (b) sks s'annonce-t-il alors en 0xFD (puis ouverture CNTL skdl/sks/scrd comme J7a) ?
#       (c) sbio répond-il au 0x73 ?
# ENDPOINTS TOUCHÉS : identiques à J7a — 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13, 0x08, puis 0x17, 0x12,
#       0x0a si annoncés), 0x13 (xART : store servi, lockers SANS UUID, SAVE acquittés si demandés), 0x08 (UN mot 0x73).
#       AUCUN mot aux EP 0x17/0x12/0x0a. Pas de relais (allow_sbio_relay=0). Même sep_native.ko que J7a (ff799c11…).
# RISQUE : écriture SEP, SCRIPT NEUF (seul changement vs J7a éprouvé : le contenu du A de réponse au FETCH locker,
#       16 o de moins ; longueur PARAM/DATA recalculée, porte noyau inchangée). Si le SEP juge le locker invalide : au pire
#       même silence que J7a (n=4), ou il re-scelle (SAVE, acquittés et persistés dans STORE → compteur scellé avancé,
#       état neuf comme un seal frais ; macOS déjà sacrifiable). Un blob du store qui ne commence pas par son UUID =
#       sepd s'arrête sans répondre (fail-closed). Halted propre si ack CNTL absent ; power-cycle = Albert.
#       ⚠️ Le STORE peut être modifié (SAVE) : on en fait d'abord une copie (STORE.avant-j7b-<date>, hors repo).
# RÉSULTAT ATTENDU : sepd.log « locker 407e… SERVED WITHOUT UUID (90 o of 106) » ×1-2, puis SOIT de nouveaux FETCH
#       (9133c5d5… 40 o, e01e3b5e… 597 o, 2438821b… 369 o, op 0x07) → succès de l'emballage, et dmesg « découverte :
#       EP 0x12 = 'sks' » puis « 'sks' ouvert » / « 'scrd' ouvert », VERDICT sbio VIVANT ou MUET ; SOIT le même silence
#       que J7a (« VERDICT sks : NON PRÊT ») → l'emballage n'était pas la cause (reste : anti-rejeu, ping skdl, DATA).
# PRÉPARÉ PAR : Claude (session ALARM), 2026-11-22. JAMAIS LANCÉ. 1er run = « go » d'Albert.
#
# Usage (root, après un power-cycle + boot normal avec alias sep) :
#   pending/j7b_sks_open_chained_nouuid.sh STORE
#   STORE = store chaîné d'un seal frais réussi, ex. /var/lib/sepd-run-20261122-230441 (inchangé par J7a : 0 SAVE).
# Binaires attendus : $J5/sep_native.ko sha256 ff799c113945ee18bc511dfd567e6b40ced12f36400a75249702b15f13dcfe55
#                     $J5/sepd.j7b       sha256 94f334db796903e68a86661dc2b93232bcbd647997c886264056e9419bdc6428
set -euo pipefail
J5=${J5:-/home/albert/kbuild/j5}
WANT_SHA=ff799c113945ee18bc511dfd567e6b40ced12f36400a75249702b15f13dcfe55
WANT_SEPD=94f334db796903e68a86661dc2b93232bcbd647997c886264056e9419bdc6428
STORE=${1:?usage: $0 STORE (store xART d un seal frais reussi, non vide)}
[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
[ -d "$STORE" ] && [ -n "$(ls -A "$STORE")" ] || { echo "STORE $STORE absent ou vide : ce test exige un store CHAÎNÉ"; exit 1; }
ls "$STORE"/master_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans master_*.bin : pas un boot chaîné"; exit 1; }
ls "$STORE"/locker_save_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans locker_save_*.bin : pas le store d'un seal complet"; exit 1; }
lsmod | grep -q "^sep_native " && { echo "sep_native déjà chargé : power-cycle d'abord"; exit 1; }
[ "$(sha256sum "$J5/sep_native.ko" | cut -d' ' -f1)" = "$WANT_SHA" ] || { echo "$J5/sep_native.ko n'est pas le binaire relu (sha256)"; exit 1; }
modinfo -F parm "$J5/sep_native.ko" | grep -q "^allow_sks:J7a" || { echo "$J5/sep_native.ko sans allow_sks J7a"; exit 1; }
[ "$(sha256sum "$J5/sepd.j7b" | cut -d' ' -f1)" = "$WANT_SEPD" ] || { echo "$J5/sepd.j7b n'est pas le binaire relu (sha256)"; exit 1; }
[ -s /etc/sepd/os_uuid ] || { echo "/etc/sepd/os_uuid absent : un store chaîné exige l'UUID du run qui l'a scellé"; exit 1; }
LOG=/home/albert/Desktop/sep-touchid/logs/$(date +%Y%m%d-%H%M%S)_j7b-sks-open-chained-nouuid
mkdir -p "$LOG"
echo "STORE = $STORE (servi tel quel) :" | tee "$LOG/store.txt"; ls -l "$STORE" | tee -a "$LOG/store.txt"
sha256sum "$STORE"/*.bin >> "$LOG/store.txt"
BAK="${STORE%/}.avant-j7b-$(date +%Y%m%d-%H%M%S)"; cp -a "$STORE" "$BAK"; echo "copie du store avant run : $BAK" | tee -a "$LOG/store.txt"
cp "$J5/sep-native.dtbo" /lib/firmware/
insmod "$J5/sep_native_ovl.ko"
insmod "$J5/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=0 \
    sbio_open=1 allow_sks=1 &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
if [ ! -e /dev/sep_native ]; then
    echo "/dev/sep_native absent après 30 s"
    journalctl -k -b --no-pager | grep sep_native > "$LOG/kernel.log" || true
    exit 1
fi
# sepd en fond ; on attend la fin du probe (insmod rendu : ligne « table de découverte ») puis on garde les journaux.
"$J5/sepd.j7b" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native --locker-strip-uuid 2> "$LOG/sepd.log" &
SEPD=$!
for i in $(seq 1 1800); do
    journalctl -k -b --no-pager | grep -q "sep_native.*table de découverte" && break
    sleep 0.1
done
sleep 2
journalctl -k -b --no-pager | grep -E "sep_native" > "$LOG/kernel.log" || true
echo "journaux : $LOG (sepd reste lancé, pid $SEPD : le SEP peut encore demander du xART ; power-cycle pour finir)"
grep -E "keystore|VERDICT|HALTED|annonce 0x1d|découverte : EP 0x12" "$LOG/kernel.log" || true
grep -E "locker|SAVE|STOP" "$LOG/sepd.log" | cut -c15- || true
