#!/usr/bin/env bash
# Phase 2+ : démarre le kernel de test sur le Mac via m1n1 (rien d'installé sur le disque).
# SOUMIS À CONFIRMATION dans .claude/settings.json : un agent ne le lance pas seul.
set -euo pipefail
source "$(dirname "$0")/env.sh"

grep -q "PHASE ACTUELLE : 1" "$REPO_ROOT/CLAUDE.md" && die "Phase 1 : pas de test kernel."
require_mac

INITRAMFS="${1:-}"
DTB="${DTB:-$LINUX_DIR/arch/arm64/boot/dts/apple/t6001-j314c.dtb}"  # MBP 14" M1 Max — à vérifier
BOOTARGS="${BOOTARGS:-earlycon debug}"

echo "Kernel : $LINUX_DIR/arch/arm64/boot/Image.gz"
echo "DTB    : $DTB"
read -r -p "Confirmer le boot du kernel de test ? [oui/N] " ok
[ "$ok" = "oui" ] || die "annulé."

"$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/chainload.py" -r "$M1N1_DIR/build/m1n1.bin"
sleep 2
"$M1N1_PYTHON" "$M1N1_DIR/proxyclient/tools/linux.py" \
  "$LINUX_DIR/arch/arm64/boot/Image.gz" "$DTB" ${INITRAMFS:+"$INITRAMFS"} -b "$BOOTARGS"
