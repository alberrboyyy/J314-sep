#!/usr/bin/env bash
# Compile m1n1 (dev, sans RELEASE) pour le chainload.
set -euo pipefail
source "$(dirname "$0")/env.sh"

[ -d "$M1N1_DIR" ] || die "m1n1/ absent. Clone : git clone --recursive https://github.com/AsahiLinux/m1n1.git m1n1"

make -C "$M1N1_DIR" -j"$(nproc)" ARCH=aarch64-linux-gnu-
ls -l "$M1N1_DIR/build/m1n1.bin"
