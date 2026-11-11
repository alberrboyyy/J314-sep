#!/usr/bin/env bash
# Tethered boot d'ALARM (récupération du Mac) via m1n1 proxy.
# Envoie le noyau + DTB + initramfs extraits du backup restic (~/alarm-recovery/boot)
# dans la RAM du Mac et démarre Linux. N'ÉCRIT RIEN sur le disque du Mac : le noyau
# part en RAM par USB. Reversible : un reboot du Mac revient à m1n1.
#
# Usage :
#   tools/tethered_boot.sh shell   # s'arrête dans l'initramfs (rien monté) — vérif lecture seule
#   tools/tethered_boot.sh alarm   # boot complet d'ALARM (monte la racine en écriture)
#
# En mode 'shell' : à l'invite de l'initramfs, taper 'exit' continue le boot normal d'ALARM.
set -euo pipefail
source "$(dirname "$0")/env.sh"

MODE="${1:-shell}"

BOOTDIR="${BOOTDIR:-$HOME/alarm-recovery/boot}"
KERNEL="${KERNEL:-$BOOTDIR/vmlinuz-linux-asahi}"
DTB="${DTB:-$BOOTDIR/t6001-j314c-full.dtb}"   # DTB complet du noyau (clavier/trackpad/écran) + espace libre ; cpu@0 en tête, pas de smbios
INITRAMFS="${INITRAMFS:-$BOOTDIR/initramfs-linux-asahi.img}"

# Déverrouillage LUKS d'ALARM par la clé embarquée dans l'initramfs (pas de passphrase).
# UUID lus depuis le grub.cfg du backup.
LUKS_UUID="123dfd25-0a64-4837-87fe-ec02441992da"
LUKS_ARGS="rd.luks.name=${LUKS_UUID}=cryptroot rd.luks.key=${LUKS_UUID}=/cryptkey.bin root=/dev/mapper/cryptroot rootflags=subvol=@ rw"

case "$MODE" in
  shell) BOOTARGS="earlycon ${LUKS_ARGS} break=premount loglevel=4" ;;
  alarm) BOOTARGS="earlycon ${LUKS_ARGS} systemd.wants=sshd.service appledrm.show_notch=1 loglevel=4" ;;
  *) die "mode inconnu : $MODE (attendu : shell | alarm)" ;;
esac

for f in "$KERNEL" "$DTB" "$INITRAMFS"; do
  [ -f "$f" ] || die "fichier absent : $f"
done
require_mac

echo "Mode     : $MODE"
echo "Noyau    : $KERNEL"
echo "DTB      : $DTB"
echo "Initramfs: $INITRAMFS"
echo "Bootargs : $BOOTARGS"
echo "Device   : $M1N1DEVICE"
echo
[ "${YES:-}" = 1 ] || { read -r -p "Lancer le tethered boot ? [oui/N] " ok; [ "$ok" = oui ] || die "annulé."; }

# Le m1n1 déjà sur le Mac est la même version que notre build -> chainload inutile par défaut.
# Mettre CHAIN=1 pour forcer un chainload si besoin.
if [ "${CHAIN:-0}" = 1 ]; then
  echo "==> chainload m1n1 frais…"
  "$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin"
  sleep 2
fi
# vmlinuz-linux-asahi est une Image ARM64 brute (non compressée) -> compression none
COMPRESSION="${COMPRESSION:-none}"
echo "==> envoi du noyau Linux… (compression=$COMPRESSION)"
exec "$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/linux.py" \
  "$KERNEL" "$DTB" "$INITRAMFS" --compression "$COMPRESSION" -b "$BOOTARGS"
