#!/usr/bin/env bash
# env_probe.sh — sonde LECTURE SEULE de l'environnement Linux-sur-Mac (j314c), pour la tâche T1 de
# MISSION_AGENT_MAC.md. AUCUN envoi au SEP, aucun accès disque, aucune écriture. À lancer sur le Linux de
# test (root@10.0.200.4), p.ex. :  ./tools/linux_ssh.sh run "bash -s" < driver/linux/env_probe.sh
#
# But : établir si l'environnement Linux offre ce qu'il faut pour le pilote natif — spi-apple sur spi2,
# et SURTOUT apple-sio / dart-sio (le coprocesseur DMA, absent de m1n1 ; cf. docs/linux_roadmap.md §2).
set -uo pipefail
sec() { printf '\n===== %s =====\n' "$1"; }

sec "NOYAU"
uname -a
[ -r /proc/version ] && cat /proc/version
cat /sys/firmware/devicetree/base/model 2>/dev/null | tr -d '\0'; echo

sec "SPI (spi-apple / spi2 = capteur Mesa)"
dmesg 2>/dev/null | grep -iE "apple.*spi|spi.*apple" | tail -n 20
echo "-- /sys/bus/spi/devices --"; ls -l /sys/bus/spi/devices/ 2>/dev/null
echo "-- nœuds DT spi --"; ls /proc/device-tree/soc/ 2>/dev/null | grep -i spi
for n in /proc/device-tree/soc/spi@39b108000 /proc/device-tree/soc/spi*; do
  [ -e "$n/status" ] && { printf '%s status=' "$n"; tr -d '\0' < "$n/status"; echo; }
done

sec "SIO + DART-SIO (le DMA — point décisif)"
dmesg 2>/dev/null | grep -iE "\bsio\b|apple-sio|dart-sio|dmaengine" | tail -n 30
echo "-- modules --"; lsmod 2>/dev/null | grep -iE "sio|dma" || echo "(aucun module sio/dma listé)"
echo "-- nœuds DT sio/dart --"; ls /proc/device-tree/soc/ 2>/dev/null | grep -iE "sio|dart"
for n in /proc/device-tree/soc/sio* /proc/device-tree/soc/dart-sio*; do
  [ -e "$n/status" ] && { printf '%s status=' "$n"; tr -d '\0' < "$n/status"; echo; }
done
echo "-- canaux dmaengine --"; ls /sys/class/dma/ 2>/dev/null || echo "(pas de /sys/class/dma)"

sec "SEP (présence seulement — AUCUN message envoyé)"
ls /proc/device-tree/soc/ 2>/dev/null | grep -i sep || echo "(pas de nœud sep listé)"
for n in /proc/device-tree/soc/sep*; do
  [ -e "$n/status" ] && { printf '%s status=' "$n"; tr -d '\0' < "$n/status"; echo; }
done
dmesg 2>/dev/null | grep -iE "apple.*sep|sep.*boot|SEPOS" | tail -n 15

sec "GPIO (alim capteur 196, IRQ 195)"
dmesg 2>/dev/null | grep -iE "gpio" | tail -n 8
ls /sys/class/gpio/ 2>/dev/null

sec "FIN"
echo "Sonde terminée (lecture seule). Renvoyer toute la sortie à l'orchestrateur."
