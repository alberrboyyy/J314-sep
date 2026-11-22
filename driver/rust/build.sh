#!/usr/bin/env bash
# Compile les modules Rust de driver/rust/kmod contre l'arbre linux-asahi préparé (même version, même .config,
# même rustc que le noyau qui tourne). N'installe rien, ne charge rien.
# Préparation (une fois) : sources du tag asahi-<ver> dans $KDIR, .config + localversion.* copiés depuis
# /lib/modules/$(uname -r)/build, rustc exact via rustup, bindgen exact dans ~/kbuild/tools, puis
# `make modules_prepare`.
set -euo pipefail
KDIR=${KDIR:-$HOME/kbuild/src/linux-asahi-7.2.12-3}
RUSTVER=$(sed -n 's/^CONFIG_RUSTC_VERSION_TEXT="rustc \([0-9.]*\).*/\1/p' "$KDIR/.config")
export PATH="$(dirname "$(rustup +"$RUSTVER" which rustc)"):$HOME/kbuild/tools/bin:$PATH"
[ "$(make -s -C "$KDIR" kernelrelease)" = "$(uname -r)" ] || { echo "arbre $KDIR != noyau $(uname -r)" >&2; exit 1; }
make -C "$KDIR" M="$(cd "$(dirname "$0")/kmod" && pwd)" modules "$@"
