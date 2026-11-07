#!/usr/bin/env bash
# Phase 2+ : cross-compile linux-asahi + driver, produit Image.gz et dtbs.
set -euo pipefail
source "$(dirname "$0")/env.sh"

grep -q "PHASE ACTUELLE : 1" "$REPO_ROOT/CLAUDE.md" && die "Phase 1 : pas de build kernel."
[ -d "$LINUX_DIR" ] || die "linux/ absent. Clone : git clone https://github.com/AsahiLinux/linux.git linux"

make -C "$LINUX_DIR" ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j"$(nproc)" Image dtbs modules
gzip -kf "$LINUX_DIR/arch/arm64/boot/Image"
ls -l "$LINUX_DIR/arch/arm64/boot/Image.gz"
