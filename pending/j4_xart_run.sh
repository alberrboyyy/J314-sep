#!/usr/bin/env bash
# BUT : J4 étape 7, servir xART 0x13 (scellement frais). ENDPOINTS : 0xFF/0xFE (boot), 0x00 (CNTL), 0x13 (xART, SAVE acquittés).
# RISQUE : écriture SEP, compteur scellé avancé, enrôlement Touch ID macOS invalidé (accepté). RÉSULTAT ATTENDU : sbio (0x08) annoncé.
# PRÉPARÉ PAR : Claude (session ALARM), 2026-11-22. Go d'Albert : 2026-11-22, dans la session ALARM.
# J4 étape 7 : boot SEPOS + service xART (go d'Albert 2026-11-22). Lancer en root après un reboot normal.
set -euo pipefail
J=/home/albert/kbuild/j2
mkdir -p /etc/sepd /var/lib/sepd
[ -s /etc/sepd/os_uuid ] || echo 4c494e55580000000000000000000000 > /etc/sepd/os_uuid
[ -z "$(ls -A /var/lib/sepd)" ] || { echo "store /var/lib/sepd non vide : arrêt (1er run = store neuf)"; exit 1; }
cp $J/sep-native.dtbo /lib/firmware/
insmod $J/sep_native_ovl.ko
insmod $J/sep_native.ko allow_boot=1 allow_xart=1 allow_xart_save_ack=1 &
for i in $(seq 1 300); do [ -e /dev/sep_native ] && break; sleep 0.1; done
[ -e /dev/sep_native ] || { echo "/dev/sep_native absent après 30 s"; journalctl -k -b --no-pager | grep sep_native | tail -20; exit 1; }
# insmod reste en arrière-plan : sepd doit répondre au 0x0e sans attendre la fin du probe
exec $J/sepd --store /var/lib/sepd --os-uuid-file /etc/sepd/os_uuid --dev /dev/sep_native
