#!/usr/bin/env bash
# BUT : J7a = expérience 1 de docs/sks_native_plan.md §4 : sur un boot CHAÎNÉ (store xART d'un seal frais réussi servi),
#       refaire J3d (ouverture PRÉCOCE de sbio 0x08) PUIS ouvrir par le CNTL SEUL, dans l'ordre de macOS (c12) :
#       skdl 0x17 (A=B=0x4000), sks 0x12 (A=B=0x8000), scrd 0x0a (A=B=0x4000) — chacun seulement s'il est annoncé
#       en 0xFD au bon numéro avec les tailles attendues ET son annonce 0x1d acquittée (30 s max chacun) ; écoute
#       passive 10 s de 0x17/0x12/0x0a (mots journalisés, dumps de B) ; puis le 0x73 → VIVANT ou MUET.
#       Tranche : (a) sks s'annonce-t-il en 0xFD sur un boot chaîné natif (jamais vu en J3/J3b/J3d, n=3 ; toujours vu
#       après un seal frais, n=7) ? (b) l'ouverture seule de skdl/sks/scrd (sans aucun contenu) suffit-elle à ce que
#       sbio réponde au 0x73 ? (c) le SEP parle-t-il seul sur ces EP une fois ouverts ?
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13, 0x08, puis 0x17, 0x12, 0x0a), 0x13 (xART,
#       store servi, SAVE acquittés si le SEP en demande), 0x08 (UN seul mot : TAG 0xfc TYPE 0x73).
#       AUCUN mot envoyé AUX EP 0x17, 0x12, 0x0a (porte d'envoi du noyau) : ni ping skdl (> 0x17 TAG 0xfc TYPE 0x01/0x06
#       de c12 : OOL jamais capturé), ni RPC sks (DER jamais capturé). Pas de relais (allow_sbio_relay=0).
# RISQUE : écriture SEP, CLASSE NEUVE : ouverture CNTL des EP 0x17/0x12/0x0a (jamais faite hors macOS). Effet attendu
#       nul côté keybag (aucune requête), mais l'état SEP de ces EP n'est pas connu. Ack CNTL absent en 5 s → HALTED
#       propre (plus aucun envoi), power-cycle (Albert). Comme J3d : store chaîné servi ; si le SEP demandait des SAVE,
#       ils seraient acquittés (compteur scellé avancé ; jamais vu en chaîné). macOS déjà sacrifiable.
# RÉSULTAT ATTENDU : dmesg « keystore : ouverture de 'skdl' », 4 « CNTL ack », « 'skdl' ouvert », puis soit
#       « VERDICT sks : NON PRÊT … annonce 0xFD : NON » (blocage EN AMONT de SKS : xART/lockers ou skdl), soit
#       « 'sks' ouvert », « 'scrd' ouvert » ; « VERDICT keystore : … », lignes « keystore < … » éventuelles, puis
#       « VERDICT sbio : VIVANT » (l'ouverture suffit) ou « MUET » (il faut le contenu : expériences 2+ du plan).
# PRÉPARÉ PAR : Claude (agent driver, session ALARM), 2026-11-22. JAMAIS LANCÉ. 1er run = « go » d'Albert.
#
# Usage (root, après un power-cycle + boot normal avec alias sep) :
#   pending/j7a_sks_open_chained.sh STORE
#   STORE obligatoire, non vide = un store chaîné existant, ex. le plus récent /var/lib/sepd-run-* d'un seal frais
#   réussi (/var/lib/sepd-run-20261122-230441 au 2026-11-22 23:04 : master_2.bin + 4 locker_save_*).
#   Le store est servi tel quel ; il n'est pas modifié sauf SAVE demandé par le SEP.
# Binaire attendu : $J5/sep_native.ko sha256 ff799c113945ee18bc511dfd567e6b40ced12f36400a75249702b15f13dcfe55
set -euo pipefail
J5=${J5:-/home/albert/kbuild/j5}
WANT_SHA=ff799c113945ee18bc511dfd567e6b40ced12f36400a75249702b15f13dcfe55
STORE=${1:?usage: $0 STORE (store xART d un seal frais reussi, non vide)}
[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
[ -d "$STORE" ] && [ -n "$(ls -A "$STORE")" ] || { echo "STORE $STORE absent ou vide : ce test exige un store CHAÎNÉ"; exit 1; }
ls "$STORE"/master_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans master_*.bin : pas un boot chaîné"; exit 1; }
ls "$STORE"/locker_save_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans locker_save_*.bin : pas le store d'un seal complet"; exit 1; }
lsmod | grep -q "^sep_native " && { echo "sep_native déjà chargé : power-cycle d'abord"; exit 1; }
[ "$(sha256sum "$J5/sep_native.ko" | cut -d' ' -f1)" = "$WANT_SHA" ] || { echo "$J5/sep_native.ko n'est pas le binaire relu (sha256)"; exit 1; }
modinfo -F parm "$J5/sep_native.ko" | grep -q "^allow_sks:J7a" || { echo "$J5/sep_native.ko sans allow_sks J7a"; exit 1; }
[ -s /etc/sepd/os_uuid ] || { echo "/etc/sepd/os_uuid absent : un store chaîné exige l'UUID du run qui l'a scellé"; exit 1; }
LOG=/home/albert/Desktop/sep-touchid/logs/$(date +%Y%m%d-%H%M%S)_j7a-sks-open-chained
mkdir -p "$LOG"
echo "STORE = $STORE (servi tel quel) :" | tee "$LOG/store.txt"; ls -l "$STORE" | tee -a "$LOG/store.txt"
sha256sum "$STORE"/*.bin >> "$LOG/store.txt"
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
"$J5/sepd" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native 2> "$LOG/sepd.log" &
SEPD=$!
for i in $(seq 1 1800); do
    journalctl -k -b --no-pager | grep -q "sep_native.*table de découverte" && break
    sleep 0.1
done
sleep 2
journalctl -k -b --no-pager | grep -E "sep_native" > "$LOG/kernel.log" || true
echo "journaux : $LOG (sepd reste lancé, pid $SEPD : le SEP peut encore demander du xART ; power-cycle pour finir)"
grep -E "keystore|VERDICT|HALTED|annonce 0x1d|découverte : EP 0x12" "$LOG/kernel.log" || true
