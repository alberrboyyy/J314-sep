# driver/kernel : base du noyau custom (linux-asahi d'ALARM)

- `config-7.2.12-3-1-ARCH` : `.config` du noyau ALARM qui tourne (paquet `linux-asahi 7.2.12.asahi3-1`,
  copié depuis `/lib/modules/7.2.12-3-1-ARCH/build/.config`, identique à `/proc/config.gz`).
- `localversion.10-pkgrel` : donne le suffixe `-3-1-ARCH`, donc `kernelrelease` = `7.2.12-3-1-ARCH`.
- Sources : archive du tag `asahi-7.2.12-3` de github.com/AsahiLinux/linux
  (`https://github.com/AsahiLinux/linux/archive/refs/tags/asahi-7.2.12-3.tar.gz`, sha256 dans
  `asahi-7.2.12-3.tar.gz.sha256`).
- Compilateurs du noyau stock : gcc 16.1.1, binutils 2.46.0, rustc 1.99.1, bindgen 0.73.2.
- Correctif local requis avec des en-têtes système récents : ajouter à `tools/include/linux/types.h`
  `typedef unsigned __int128 __u128 __attribute__((aligned(16)));` (+ `__s128`). Sans lui, `resolve_btfids` ne
  compile pas.

Installer ou démarrer un noyau construit ici = action d'Albert. Le noyau stock reste au menu comme secours.
