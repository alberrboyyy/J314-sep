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

## Alimentation et broches de spi2 (2026-11-10)
Sources : `analysis/adt_pmgr_ps.py` sur `traces/20261108-162919_adt/adt.bin` (hors ligne) ; `traces/20261110-001208_gpio_peek`
(`tools/gpio_peek.sh`, lecture seule sous m1n1 seul) ; fichiers publics Linux `t600x-pmgr.dtsi`, `t600x-gpio-pins.dtsi`.

| Élément | Valeur | Statut |
|---|---|---|
| Domaine d'alimentation de spi2 | pmgr `SPI2` (id 144), registre CPU 0x28e580200 = `ps_spi2` (`power-controller@200`, parent `ps_spi_p`) du DT public | lu (ADT) + concordant avec le DT public ; allumé (0xff) sous m1n1 seul |
| Broches SPI de spi2 | gpio0 48 (MISO, tirage bas), 49, 50, fonction périphérique 1 ; rôle horloge/MOSI de 49 et 50 non distingué | **hypothèse** (même motif que spi1/spi3/spi4, numérotation 48-51 / 52-55 / 56-59) |
| Chip-select | aucun (`function-spi_cs0 = 1:null()`, broche 51 non configurée) | hypothèse |
| IRQ capteur (gpio0 195) | entrée, tirage bas ; active haute : 0 capteur éteint, 1 après allumage, 0 après la 1re lecture d'état (Linux, 2026-11-10) | vérifié (Linux, 3 passes) |
| mesa_pwr (gpio0 196) | non configurée sous m1n1 (ni sortie ni entrée) → capteur probablement éteint | lu / hypothèse |

Réserve : un 5e groupe au même motif (116, 117, 118) n'a pas de contrôleur SPI connu dans l'ADT ; tant qu'il n'est pas
expliqué, « spi2 = 48-50 » reste une hypothèse. Pour un DT Linux : `pinmux = <APPLE_PINMUX(48, 1)>, <APPLE_PINMUX(49, 1)>,
<APPLE_PINMUX(50, 1)>` (iBoot les a déjà réglées ainsi : ne rien changer d'autre).

## Dialogue SPI AP ↔ capteur sous macOS (C17, C18, C19 — 2026-11-10)
Sources : `traces/20261110-001859_c17-spi-boot` (registres), `…002417_c18-spi-dma-boot` (contenu partiel),
`…002829_c19-spi-dma-boot` (contenu complet : 147 buffers, 0 erreur de lecture). Outils : `hv/trace_sep_spi_dma.py`
(écoute seule), `analysis/spi2_transfers.py`, `analysis/sio_dialog.py <dossier> [--sep] [--full]`.
Statut général : **vu** (boots macOS sans doigt) ; les noms et rôles sont des **hypothèses**. Rien n'a été envoyé.

### Transport (vu)
- Les données ne passent pas par les registres FIFO de spi2 : transferts DMA par le coprocesseur SIO, canaux 0x18
  (émission) et 0x19 (réception). Descripteur dans le bloc de contrôle SIO : `+0x40 + DATA*0xc`, pointeur à +8, taille à +0x10.
- Réglages spi2 constants : CLKDIV 3, CFG 0x40042, SHIFTCFG 0x80c07, PIN 0. Les broches 48-51 ne sont jamais réécrites.
- Alimentation : gpio0 196 en sortie, 0 puis 1 ; elle est coupée/remise deux fois (~11 ms) et toute l'initialisation est rejouée.

### Trames (vu ; noms = hypothèses)
En-tête d'émission : `80 <cmd> <longueur totale, 16 bits gros-boutiste> 00 00 00`, puis la charge.

| cmd | Taille | Vu | Rôle supposé |
|---|---|---|---|
| 0x10 | 7 | 47 fois ; lecture simultanée de 0x17 octets dont les 16 derniers = `80 20 00 10 00000000` + 8 octets | demande d'état ; réponse 0x20 |
| 0x13 | 0x0b, charge = longueur (32 bits petit-boutiste) | avant chaque lecture de réponse ; suivi d'une émission d'1 octet `00` puis d'une réception de cette longueur | « donne-moi la réponse de N octets » |
| 0x78, 0x70 | 7 | au début de chaque allumage ; 0x70 → réponse 0x1b octets identique dans C18 et C19 (`80 d4 00 1b 00000000 70 02 19c0…`) | réveil ; identité du capteur |
| 0x72 | 0x2f | après SEP `0x15` ; réponse 0x33 (type 0x72) puis SEP `0x16` | échange de clés (charge différente à chaque fois) |
| 0x73 | 0x47 | après SEP `0x42` ; réponse 0x4b (type 0x73) puis SEP `0x18` | 1er message chiffré |
| 0x60 + bloc | 7 puis 0x568e ou 0x70ce octets | après SEP `0x5f` (transfert OOL venant du SEP) | envoi du correctif du capteur |
| 0x55 | 0x40, 0x49, 0x4d, 0x56 | après SEP `0x5d`, `0x5c`, `0x6a`, `0x6f`, `0x31` ; certaines ont une réponse 0x4b (type 0x75) suivie de SEP `0x32` | commandes chiffrées |
| 0x30, 0x40 | 7 | une fois chacune en fin d'init / pendant l'attente | inconnu |

Réponses : `80 d4 <longueur> 00000000 <type>` + charge. Dans l'état (réponse 0x20), l'avant-dernier groupe porte la longueur
de la réponse en attente (0x1b, 0x33, 0x4b vus) : c'est elle que l'AP redemande avec 0x13.

Enveloppe des messages 0x73 / 0x55 / 0x75 et des gros blocs : `3a 00…00`, un compteur de 8 octets (base différente à chaque
allumage, +1 par message), puis une longueur et un contenu d'aspect aléatoire, différent d'un allumage à l'autre.

### Interprété (hypothèses)
- L'AP est un simple relais : chaque bloc envoyé au capteur suit une commande SEP de l'EP 0x08, chaque réponse du capteur
  est suivie d'une commande SEP. Le contenu est chiffré entre le SEP et le capteur (cohérent avec la note publique de
  `trace_mesa.py`). Un pilote Linux n'aurait donc à connaître que le transport ci-dessus ; le contenu vient du SEP.
- Sans le service sbio du SEP (bloqué par xART, voir driver_plan), Linux peut au mieux allumer le capteur, lire son identité
  (0x70) et son état (0x10) : ce sont les seules trames en clair.
- Doigt posé (C20, traces/20261110-003201_c20-doigt-spi, **vérifié (macOS)** 7/7) : l'état annonce 0x7200 octets en attente,
  l'AP les lit (0x13 puis réception de 0x7200 : `80 52 <n> 80 09 00 00 3a …`, 12 tranches de 0x980) et envoie la 1re image de
  la pose telle quelle au SEP dans `> 0x65`. 27 images lues pour 7 envoyées : les suivantes ne vont pas au SEP (rôle inconnu).
  En attente : demande d'état toutes les ~0,5 s. Trames 0x30 après le résultat et 0x40 avant la pose suivante (rôle supposé :
  arrêt / reprise du balayage).

### Essai sans macOS (MESA-HELLO, 2026-11-10) — vérifié
`tools/mesa_hello.sh` (m1n1 seul) : alimentation gpio0 196, spi2 en mode scruté (CLKDIV 3, CFG 0x40002), trames 0x78, 0x10, 0x70,
0x13 → le capteur rend la même identité que sous macOS. Conséquences : les broches SPI n'ont pas besoin d'être réglées (état
d'iBoot suffisant), pas de chip-select, CPHA = 1. Tout le reste du dialogue est chiffré et vient du SEP : non essayé.

### Réponse d'état (trame 0x20) : valeurs vues dans C20 (analyse hors ligne, 2026-11-10)
Les 9 octets qui suivent `80 20 00 10 00 00 00`. Comptes sur toute la capture C20 (login, 3 bons doigts, 2 mauvais).
Colonne « sens » = **hypothèses** tirées du moment où la valeur apparaît ; rien n'a été testé.

| Octets | Vu | Moment | Sens supposé |
|---|---|---|---|
| `00 60 00 00 00 52 33 00 00` (variantes `…18…`, `…08…`) | 13 | juste après l'allumage, avant l'envoi du gros bloc | repos, capteur sans correctif (octet 2 = `60`) |
| `09 60 00 00 08 00 00 00 00` | 1 | après la trame 0x78 | vient d'être réveillé |
| `07 60 00 00 88 LL 00 00 00` / `07 00 21 00 8c LL …` / `07 00 21 00 8e 00 72 00 00` | 37 | avant chaque lecture de réponse | réponse prête ; longueur = octets 5-6 (petit-boutiste) : 0x1b, 0x33, 0x4b, 0x7200 |
| `00 29 01 00 7c 52 33 00 16`, `00 00 21 00 0c 52 33 00 16`, `00 00 01 00 5c 52 33 00 16` | 17 | après l'envoi du gros bloc ; après chaque résultat | repos avec correctif chargé (dernier octet `16`) |
| `11 06 21 00 0c 00 00 00 00` | 9 | après la trame 0x40 | balayage qui démarre |
| `11 02 21 80 04 80 80 80 80` | 218 | toutes les ~0,5 s en attente | armé, attend un doigt |
| `13 00 21 00 0e 00 00 00 00` | 8 | ~80 ms avant « réponse prête 0x7200 » | doigt détecté, image en cours |
| `11 05 21 XX 0c aa bb cc dd` | 3 | entre deux images d'une même pose | mesures du doigt (4 derniers octets variables) |
| `10 02 21 00 06 00 00 00 00` | 14 | après un mauvais doigt, ~3 s | attend que le doigt se lève ? |

À retenir pour un pilote : le premier octet sert d'état (`00` repos, `07` réponse prête, `11` balayage, `13` doigt), l'octet 2
vaut `60` avant le correctif et `21`/`01` après. Sans le correctif (qui vient du SEP, chiffré), on ne voit que les lignes `60`.

## Broche d'interruption et repos, capteur piloté par Linux seul (2026-11-10)
Source : journal 06:07, 06:08 et 06:15 (modules `driver/linux/mesa_statloop.c` et `mesa_irqwatch.c`). Rien ne vient d'un kext.

| Moment | Broche gpio0 195 | Réponse d'état (0x10) | Statut |
|---|---|---|---|
| capteur éteint | 0 | — | vérifié (3 passes) |
| après allumage, après réveil 0x78 | 1 | — | vérifié (3 passes) |
| 1re lecture d'état | retombe à 0 en moins de ~11 ms | `80 20 00 10 000000 09 60 00 00 18 00 00 00 00` | vérifié (macOS-indépendant, 4 passes pour l'état) |
| demande d'identité 0x70, puis nouvelle réponse en attente | **remonte à 1** | 2e état annonce 0x1b (27) octets | vérifié (1 passe, hello=1) |
| lectures suivantes, au repos, 30 à 45 s | 0 | `… 09 60 00 00 00 00 00 00 00`, identique à chaque fois | vérifié |
| aucune lecture d'état pendant 10 s | reste à 1 | — | vérifié (1 passe) |
| doigt posé (sans appuyer) | 0, inchangée | inchangée | 2 essais, doigt déclaré par Albert |

- La broche est une ligne « donnée prête / attention » : elle passe à 1 dès que le capteur a une réponse en attente (démarrage, puis après chaque demande comme 0x70) et retombe à 0 quand l'AP lit l'état (0x10). Active haute. Mesuré sur toute la séquence « bonjour » (mesa_irqwatch.ko hello=1, 2026-11-10). => un pilote piloté par interruption est possible (attendre la montée au lieu de pauses fixes).
- Hypothèse : l'octet 0x18 de la 1re réponse est la raison de la demande (« je viens de démarrer ») ; lire l'état l'acquitte.
- Hypothèse : sous macOS le doigt est signalé parce que le SEP a configuré le capteur par le dialogue chiffré ; non testable sans le SEP.
- Limites : état lu à 1 Hz, broche scrutée à 20 ms.
