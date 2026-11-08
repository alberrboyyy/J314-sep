# Matériel du capteur Touch ID (j314c / t6001) : contrôleur SPI, broches

Statut global : **l'ADT de notre machine n'est dans aucune trace ni aucun fichier du repo.** Le contrôleur et les
broches exacts sont donc **inconnus** ; ci-dessous, ce qui est vu, déduit, et la demande d'expérience.
Recherche faite : `grep -ril biosensor traces macos m1n1 docs analysis` ne trouve que `trace_mesa.py` et nos docs ;
`traces/*/{trace,chainload}.log` ne contiennent ni `spi`, ni `gpio0`, ni `mesa`.

## Vu (faits)
- `traces/20261107-033436_c1-boot/hv_uart.log:176,182-184` : le noyau démarre 4 contrôleurs `AppleSPIMCController` :
  spi4 (CCLK 24 MHz), spi1 (200 MHz), spi3 (24 MHz), spi2 (24 MHz). Aucune ligne ne dit lequel porte le capteur.
- `hv_uart.log:910,912` : « AppleBiometricSensor: Found SandDollarFamily » ; `:2078` : « Mesa biometric driver detected ».
- `macos/kernel.macho` (plist prelink, `strings`, l.301353 et 301414 du flux strings) : AppleMesa et AppleSandDollar
  (bundle AppleBiometricSensor) ont `IONameMatch = biosensor,mesa`, `IOProviderClass = AppleARMSPIDevice`. Donc le
  capteur est un **nœud enfant `biosensor,mesa` d'un contrôleur SPI de l'AP**, pas un périphérique du SEP.
- Noms de propriétés ADT présents dans le kernel (noms seulement ; **leur appartenance à Mesa/SandDollar n'est pas
  attribuée ligne à ligne**) : `function-mesa_pwr`, `function-mesa_pwr1v8`, `function-mesa_reset`,
  `function-mesa-reset-ntfy`, `mesa-spi-freq`, `mesa-spi-clock-phase`, `mesa-power-on-delay`,
  `mesa-power-on-1v8-3v0-delay`, `mesa-power-off-delay`, `mesa-power-off-3v0-1v8-delay`, `mesa-drive-1v8`,
  `mesa-sensor-id`, `mesa-pm-assertion`, `mesa-patch-directly`, `mesa-dispatch-hid`, `mesa-esd-*`, etc.
- Code public m1n1 `proxyclient/hv/trace_mesa.py` (M1, 2022) : l.25-39 cherche `spi-1,spimc` parent d'un enfant
  `biosensor,mesa` ; l.41-51 IRQ du contrôleur et du capteur lues de l'ADT (`interrupts` / `interrupt-parent` =
  AIC) ; l.53-56 `mesa_pins = {0xc4: "mesa_pwr"}` sur `/arm-io/gpio0` ; l.208-212 `/arm-io/spi2` + DMA via SIO.

## Déduit (hypothèses)
- Alim : propriété `function-mesa_pwr` (et `function-mesa_pwr1v8` pour le 1,8 V) = phandle d'un contrôleur GPIO + n° de
  broche + flags (format `function-*` Apple habituel ; non vérifié ici). Reset : `function-mesa_reset` côté AOP
  (cf. journal 2026-11-08 « d'où vient l'image 0x65 »), pas côté GPIO de l'AP : à confirmer dans l'ADT.
- Interruption : propriété `interrupts` du nœud enfant `biosensor,mesa` (m1n1 la lit) ; numéro inconnu.
- Contrôleur : sur M1 (machine de l'auteur de trace_mesa.py) c'est `spi2` ; **rien n'autorise à transposer à t6001**.
  Le DT Linux t600x ne décrit que spi1 (NVRAM) et spi3 (HID) (`docs/public_linux_state.md` §2.2), donc candidats
  restants spi2 et spi4, sans preuve. Mêmes réserves : `0xc4` (mesa_pwr) est la valeur M1, pas t6001.
- Les 4 CCLK (24 MHz pour spi2/3/4) ne départagent pas ; `mesa-spi-freq` fixe la fréquence réelle.

## Inconnu
Contrôleur SPI (spi2 ou spi4 ?), adresse MMIO, n° d'IRQ, GPIO pwr/pwr1v8, broche CS, mode/fréquence SPI, canaux
DMA SIO, rôle de la broche reset. Tout est dans l'ADT, que nous n'avons pas.

## Expérience demandée (lecture seule, non exécutée)
Voir `docs/hypotheses.md`, « EXPÉRIENCE ADT-1 ».
