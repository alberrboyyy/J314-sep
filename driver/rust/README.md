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

## Module noyau Rust : pas encore possible sur ALARM (relevé 2026-11-22)
Le noyau `7.2.12-3-1-ARCH` a `CONFIG_RUST=y`, mais :
1. le paquet d'en-têtes (`/lib/modules/$(uname -r)/build/rust/`) ne contient **pas** les artefacts Rust du noyau
   (`libkernel.rmeta`, etc.) : un module Rust hors arbre ne peut pas être compilé contre lui ;
2. le noyau est compilé avec `rustc 1.99.1` et `bindgen 0.73.2` ; le système a `rustc 1.98.1`. Il faut exactement la
   même version.
Pour y arriver : récupérer les sources linux-asahi de cette version avec la même `.config`, installer rustc 1.99.1
(rustup), compiler la cible `rust/`, puis le module contre cet arbre. Ce module touchera au SEP : son premier
chargement = go d'Albert (CLAUDE.md).
