#!/usr/bin/env bash
# BUT : J3 sur boot CHAÎNÉ : servir un store xART existant (master + lockers sauvegardés par un run précédent) et
#       ouvrir sbio de façon PRÉCOCE (sbio_open=1), comme macOS : les 4 CNTL PARAM 0x08 partent dès que l'annonce
#       0x1d 'sbio' est acquittée (TYPE 0x16), pendant que le xART continue ; puis le 0x73 quand le xART est calme.
#       Décide si l'enrôlement peut persister d'un boot à l'autre (ouverture tardive jamais acquittée en chaîné, n=2).
# ENDPOINTS TOUCHÉS : 0xFF/0xFE (boot), 0x00 (CNTL : SECMODE + tampons 0x13 et 0x08), 0x13 (xART, store servi, SAVE
#       acquittés), 0x08 (sbio : UN seul mot, TAG 0xfc TYPE 0x73). Pas de relais (allow_sbio_relay=0). Jamais 0x12.
# RISQUE : écriture SEP (comme J3/J4 : compteur scellé avancé). NOUVEAU : ouverture précoce de sbio entrelacée avec le
#       xART (1er run de ce chemin). Ack CNTL absent → HALTED propre (plus aucun envoi), power-cycle (Albert).
# RÉSULTAT ATTENDU : dmesg « sbio : ouverture PRÉCOCE », 4 « CNTL ack », « 0x08 ouvert », puis « VERDICT sbio : VIVANT ».
#       « pas d'ack CNTL à l'ouverture de 0x08 » (HALTED) = l'ouverture précoce ne suffit pas non plus.
# PRÉPARÉ PAR : Claude (agent driver, session ALARM), 2026-11-22. Go d'Albert donné ; lancé le 2026-11-22 19:57 (CNTL acké, 0x73 muet).
#
# Usage (root, après un reboot normal avec alias sep) : pending/j3_chained_run.sh STORE   (STORE obligatoire, non vide)
set -euo pipefail
J5=${J5:-/home/albert/kbuild/j5}
STORE=${1:?usage: $0 STORE (store xART d un run precedent, non vide)}
[ -d "$STORE" ] && [ -n "$(ls -A "$STORE")" ] || { echo "STORE $STORE absent ou vide : ce test exige un store CHAÎNÉ"; exit 1; }
ls "$STORE"/master_*.bin >/dev/null 2>&1 || { echo "STORE $STORE sans master_*.bin : pas un boot chaîné"; exit 1; }
lsmod | grep -q "^sep_native " && { echo "sep_native déjà chargé : redémarrer d'abord"; exit 1; }
modinfo -F parm "$J5/sep_native.ko" | grep -q "^sbio_open:" || { echo "$J5/sep_native.ko sans sbio_open"; exit 1; }
echo "STORE = $STORE (servi tel quel) :"; ls -l "$STORE"
mkdir -p /etc/sepd
[ -s /etc/sepd/os_uuid ] || { echo "/etc/sepd/os_uuid absent : un store chaîné exige l'UUID du run qui l'a scellé"; exit 1; }
cp "$J5/sep-native.dtbo" /lib/firmware/
insmod "$J5/sep_native_ovl.ko"
insmod "$J5/sep_native.ko" allow_boot=1 allow_xart=1 allow_xart_save_ack=1 allow_sbio=1 allow_sbio_relay=0 sbio_open=1 &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
[ -e /dev/sep_native ] || { echo "/dev/sep_native absent après 30 s"; journalctl -k -b --no-pager | grep sep_native | tail -20; exit 1; }
echo "verdict : journalctl -k -b | grep -E 'ouverture|CNTL ack|0x08 ouvert|sbio|VERDICT|HALTED'"
exec "$J5/sepd" --store "$STORE" --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native
