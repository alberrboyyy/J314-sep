# driver/rust : pilote Touch ID en Rust

## `sep-proto/` — protocole AP↔SEP (J1 de `docs/linux_roadmap.md`)

Portage Rust de `driver/sepreplay/` (la référence Python). **Calcul pur : aucune mailbox, aucun périphérique, aucune
écriture vers le SEP.** Le cœur est `no_std` + `alloc` : le futur module noyau (Rust for Linux) le reprendra tel quel.
Seul le lecteur de traces (`trace`, feature `std`, active par défaut) a besoin de la bibliothèque standard.

Modules (les statuts vérifié / hypothèse sont ceux de `docs/verification_status.md`, rappelés dans chaque fichier) :
- `word` : mot mailbox 64 bits (EP/TAG/TYPE/PARAM/DATA), `Msg` avec sa direction.
- `discovery` : table 0xFD (nom → EP, tailles OOL), ouvertures CNTL. Toujours chercher un EP par son nom.
- `gt` : règle de compteur GT (`CounterChecker`, utilisable en ligne), en-tête OOL, réassemblage, CRC des tranches
  0x65, et `fragment()` (découpage côté émetteur, calcul seulement).
- `sensor` : trames capteur, statut, commandes et identité vérifiées sur matériel (`mesa_probe`, 2026-11-22).
- `xart` : codec EP 0x13 et coffre gigalocker (.gl). `xart_responder` : réponses de macOS reproduites ; la politique
  native (ABSENT, persistance des SAVE) est isolée et marquée HYPOTHÈSE.
- `daemon` : séquence d'init sbio (57 commandes) et stockage des blobs 0x6c → 0x6d.
- `crc` : CRC-16/ARC et CRC-32, écrits depuis les définitions standard.

Aucune entrée ne provoque de panique : chaque décodeur renvoie un `Result` (fail-closed, `Error::Unexpected`).

### Lancer
```
cd driver/rust/sep-proto
cargo test --offline                        # 21 tests unitaires + 17 tests de rejeu sur traces/
cargo test --offline -- --nocapture         # affiche les comptes [stepN]
cargo build --offline --no-default-features # vérifie que le cœur compile sans std
```
Les tests de rejeu reprennent les mêmes références que `driver/tests/*.py` et retrouvent les mêmes comptes
(2026-11-22) : 6122 mots GT sur 23 traces sans exception, init de 57 commandes 23/23, 39 images / 468 tranches CRC,
30 paires 0x13 reproduites mot pour mot, coffre 12/12 (CRC et réécriture à l'octet près).

## Modules noyau Rust hors arbre (`kmod/`, `build.sh`)
Le paquet d'en-têtes d'ALARM ne contient pas les artefacts Rust du noyau (`libkernel.rmeta`…), et le noyau exige
exactement son rustc. Mise en place (faite le 2026-11-22, `~/kbuild/`, rien d'installé dans le système) :
1. sources du tag AsahiLinux `asahi-7.2.12-3` (archive GitHub) dans `~/kbuild/src/linux-asahi-7.2.12-3` ;
2. `.config`, `localversion.10-pkgrel`, `Module.symvers` et `vmlinux` copiés depuis `/lib/modules/$(uname -r)/build`
   (config identique après `olddefconfig`, `kernelrelease` = `7.2.12-3-1-ARCH`) ;
3. `rustup toolchain install 1.99.1 --component rust-src` et `cargo install bindgen-cli --version 0.73.2
   --root ~/kbuild/tools` ;
4. correctif local de l'arbre : `tools/include/linux/types.h` ne définit pas `__u128`, alors que les en-têtes
   système (`asm/sigcontext.h`) s'en servent, ce qui casse `resolve_btfids`. On ajoute la même typedef que
   `/usr/include/linux/types.h` ;
5. `make modules_prepare` (15 s), puis `./build.sh`.
`kmod/sep_hello.rs` = module de contrôle de la chaîne : il n'accède à aucun matériel. vermagic identique au noyau,
tous ses symboles présents. **Chargé et déchargé sur ALARM le 2026-11-22 : OK** (`dmesg` : « chaîne Rust OK », puis
« déchargé »). Gros acquis : l'arbre fournit `kernel::soc::apple::{mailbox, rtkit}` en Rust (ce que
`drivers/soc/apple/sep.rs` utilise). En revanche, il n'y a pas de liaison Rust SPI : le capteur restera en C ou
passera par une petite couche de liaison. `CONFIG_APPLE_SEP=y` (intégré au noyau) : un pilote SEP étendu
remplacera `sep.rs` dans un noyau custom, ou se liera via un nœud DT distinct. Tout module qui parle au SEP :
premier chargement = go d'Albert (CLAUDE.md).
