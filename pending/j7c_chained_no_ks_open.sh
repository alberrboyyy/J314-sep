#!/usr/bin/env bash
# BUT : J7c = J7b (VÉRIFIÉ n=2 : boot chaîné, lockers servis sans UUID → sks annoncé, sbio VIVANT) MOINS l'ouverture CNTL
#       de skdl 0x17 / sks 0x12 / scrd 0x0a (pas d'allow_sks). Seul sbio est ouvert (tôt, comme J3d/J7b), puis le 0x73.
#       Tranche : ces 3 ouvertures sont-elles NÉCESSAIRES pour que sbio réponde sur un boot chaîné ? Important pour la
#       suite : le noyau n'accepte pas allow_sks avec le relais capteur (allow_sbio_relay=1) ; si J7c donne VIVANT, l'init
#       capteur complète sur boot chaîné (J8) marche sans toucher au module.
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13 et 0x08), 0x13 (xART : store servi, lockers
#       SANS UUID = défaut du nouveau sepd, SAVE acquittés si demandés), 0x08 (UN mot 0x73). Rien vers 0x17/0x12/0x0a.
# RISQUE : écriture SEP, SCRIPT NEUF mais SOUS-ENSEMBLE strict de J7b éprouvé (mêmes mots, moins les 3 ouvertures CNTL ;
#       insmod = celui de J3d, éprouvé). Nouveau binaire sepd (défaut « sans UUID », même réponses que sepd.j7b pour un
#       store de SAVE — tests snew). Au pire : sbio MUET (comme J3d) ou SAVE (acquittés, store copié avant). Power-cycle = Albert.
# RÉSULTAT ATTENDU : sepd.log identique à J7b (4 lockers SANS UUID ×2, op 0x07, 0 SAVE), dmesg « découverte : EP 0x12 =
#       'sks' » (annonce seule, pas d'ouverture), puis « VERDICT sbio : VIVANT » (ouvertures inutiles) ou « MUET »
#       (il faut ouvrir skdl/sks/scrd → étendre allow_sks au chemin relais pour J8).
# PRÉPARÉ PAR : Claude (session ALARM), 2026-11-23. JAMAIS LANCÉ. 1er run = « go » d'Albert.
#
# Usage (root, après un power-cycle + boot normal avec alias sep) :
#   pending/j7c_chained_no_ks_open.sh STORE      (ex. /var/lib/sepd-run-20261122-230441)
# Binaires attendus : $J5/sep_native.ko sha256 ff799c113945ee18bc511dfd567e6b40ced12f36400a75249702b15f13dcfe55
#                     $J5/sepd          sha256 6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
set -euo pipefail
J5=${J5:-/home/albert/kbuild/j5}
WANT_SHA=ff799c113945ee18bc511dfd567e6b40ced12f36400a75249702b15f13dcfe55
WANT_SEPD=6ad1992f12b0d300b37b6b20ba2e9e3c0cc44d4e02bd7b74ce031cc958e37f4a
STORE=${1:?usage: $0 STORE (store xART d un seal frais reussi, non vide)}
[ "$(id -u)" = 0 ] || { echo "à lancer en root"; exit 1; }
[ -d "$STORE" ] && [ -n "$(ls -A "$STORE")" ] || { echo "STORE $STORE absent ou vide : ce test exige un store CHAÎNÉ"; exit 1; }
ls "$STORE"/master_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans master_*.bin : pas un boot chaîné"; exit 1; }
ls "$STORE"/locker_save_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans locker_save_*.bin : pas le store d'un seal complet"; exit 1; }
lsmod | grep -q "^sep_native " && { echo "sep_native déjà chargé : power-cycle d'abord"; exit 1; }
[ "$(sha256sum "$J5/sep_native.ko" | cut -d' ' -f1)" = "$WANT_SHA" ] || { echo "$J5/sep_native.ko n'est pas le binaire relu (sha256)"; exit 1; }
[ "$(sha256sum "$J5/sepd" | cut -d' ' -f1)" = "$WANT_SEPD" ] || { echo "$J5/sepd n'est pas le binaire relu (sha256)"; exit 1; }
[ -s /etc/sepd/os_uuid ] || { echo "/etc/sepd/os_uuid absent : un store chaîné exige l'UUID du run qui l'a scellé"; exit 1; }
LOG=/home/albert/Desktop/sep-touchid/logs/$(date +%Y%m%d-%H%M%S)_j7c-chained-no-ks-open
mkdir -p "$LOG"
echo "STORE = $STORE (servi tel quel) :" | tee "$LOG/store.txt"; ls -l "$STORE" | tee -a "$LOG/store.txt"
sha256sum "$STORE"/*.bin >> "$LOG/store.txt"
BAK="${STORE%/}.avant-j7c-$(date +%Y%m%d-%H%M%S)"; cp -a "$STORE" "$BAK"; echo "copie du store avant run : $BAK" | tee -a "$LOG/store.txt"
cp "$J5/sep-native.dtbo" /lib/firmware/
insmod "$J5/sep_native_ovl.ko"
insmod "$J5/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=0 \
    sbio_open=1 &
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
grep -E "locker|SAVE|STOP" "$LOG/sepd.log" | cut -c15- || true
