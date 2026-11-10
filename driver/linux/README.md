# driver/linux : « bonjour » au capteur Touch ID depuis Linux

État : **préparé hors ligne, jamais lancé sur le Mac sous Linux.** La même séquence a été vérifiée 2 fois depuis m1n1
(`tools/mesa_hello.sh`, `docs/verification_status.md` SPI-3). Rien ici ne parle au SEP.

## Fichiers
- `mesa_transport.h` : **couche transport réutilisable, base du futur pilote.** Primitives sans logique de test :
  `mesa_acquire`/`mesa_release` (prendre/relâcher le capteur : mode SPI vérifié, broche d'alimentation, contrôleur
  maintenu allumé), `mesa_power_on`/`mesa_power_off` (allumer/éteindre avec les délais vérifiés), `mesa_send` (émettre
  une commande), `mesa_read` (lire une réponse en attente), `mesa_status` (lire l'état, rend le nombre d'octets en
  attente). Le vrai pilote inclura ce fichier au lieu de recopier la séquence.
- `mesa_probe.c` : petit module = premier client du transport. Sans `enable=1` il ne fait rien du tout. Avec `enable=1`
  il refait la séquence vérifiée (« bonjour »), rien d'autre :
  1. broche d'alimentation du capteur à 0, 40 ms, puis à 1, 60 ms ;
  2. réveil `80 78 00 07 00 00 00` ;
  3. état : `80 10 00 07 00 00 00` + 16 zéros, en lisant 0x17 octets (réponse `80 20 00 10 …` à partir de l'octet 7) ;
  4. identité `80 70 00 07 00 00 00`, puis état ;
  5. seulement si l'état annonce 0x1b octets en attente : `80 13 00 0b 00 00 00 1b 00 00 00`, puis lecture de 0x1b octets
     (en émettant des zéros), puis état ;
  6. alimentation à 0.
  Chaque échange est un message SPI séparé. Chaque émission et chaque réponse sont affichées dans le journal du noyau
  (`dmesg`), avec une ligne `RÉSULTAT :` qui dit si l'identité est celle lue sous macOS
  (`80d4001b00000000700219c05c0fd2aa349a81c76e030200d87576`). Le module ne reste pas chargé « lié » au capteur :
  pour recommencer, le décharger et le recharger.
- `mesa_statloop.c` : 2e client du transport. Avec `enable=1` il allume le capteur, le réveille, lit l'état toutes les
  secondes pendant `duree` secondes (défaut 30) sans doigt, puis l'éteint — pour voir si l'état est stable au repos.
  Ne pas charger en même temps que `mesa_probe` (même capteur). Montre que `mesa_transport.h` se réutilise tel quel.
- `mesa_irqwatch.c` : 3e client du transport. Avec `enable=1` il allume le capteur et surveille sa broche d'interruption
  (gpio0 195, lue seulement, toutes les 20 ms) pendant `duree` secondes, en lisant l'état toutes les `etat_ms` ms (0 = jamais).
  Résultat du 2026-11-10 : la broche monte à l'allumage, retombe après la 1re lecture d'état, ne réagit pas au doigt.
- `t6001-j314c-mesa.dtsi` : description du bus spi2 et du capteur. Chaque ligne est marquée VÉRIFIÉ, LU, CALQUÉ ou INCONNU.
- `t6001-j314c-mesa-test.dts` : device tree de test = j314c public + le fragment ci-dessus, activé.
- `Makefile` : module hors arbre.

## Vérifié hors ligne (2026-11-10)
- `mesa_probe.c` (+ `mesa_transport.h`) compile sans avertissement (`W=1`) contre les en-têtes du noyau 7.2 du PC
  (x86 : contrôle de l'API seulement). `mesa_ovl.c` ne compile pas sur ce PC (fonction `of_find_all_nodes` absente des
  en-têtes x86), mais compile sur le Linux de test Asahi ; sans rapport avec le capteur.
- `t6001-j314c-mesa-test.dts` compile avec `cpp` + `dtc` contre les fichiers publics `arch/arm64/boot/dts/apple/` de Linux
  (branche master du 2026-11-10) : les étiquettes `aic`, `clkref`, `ps_spi2`, `pinctrl_ap` existent et le nœud spi2 produit
  a la même forme que spi3.
- Les octets des trames ont été relus contre `tools/mesa_hello.sh`.

## Chip-select (incertitude notée)
Le bus spi2 n'a pas de broche chip-select (ADT), et l'essai depuis m1n1 n'en a manipulé aucune (registre PIN = 0).
Sous Linux :
- `SPI_NO_CS` n'est **pas utilisable** : `spi-apple.c` n'annonce que CPHA, CPOL et LSB_FIRST, donc `spi_setup()` refuserait
  ce mode ; et il n'existe pas de propriété de device tree pour le demander. De plus, pour un chip-select « natif », le cœur
  SPI appelle `set_cs()` du contrôleur même avec `SPI_NO_CS`.
- Conséquence : `spi-apple` fera bouger son bit de chip-select interne (registre PIN, bit 1) autour de chaque message, et
  règle au démarrage PIN, PINCFG et SHIFTCFG. Aucune broche n'est reliée à ce signal (hypothèse : broche 51 non configurée),
  donc cela ne devrait rien changer sur le fil. **Non vérifié** : c'est la principale différence avec l'essai m1n1.
- Si le capteur ne répond pas sous Linux, c'est le premier suspect ; le correctif serait dans `spi-apple` (ne pas toucher
  PIN), pas dans ce module.

## Autres différences avec l'essai depuis m1n1 (non vérifiées)
- `spi-apple` travaille par interruption (AIC 1108, jamais vue) et non en mode scruté ; registre CFG = 0x22 au lieu de 0x40002.
- Le diviseur d'horloge vaut 3 (comme vérifié) seulement si l'horloge de spi2 est bien de 24 MHz et la fréquence demandée 8 MHz.
- Le noyau coupe et rallume l'alimentation du contrôleur spi2 (`ps_spi2`) quand il ne sert pas ; l'essai m1n1 n'y touchait pas.
  Le module garde spi2 allumé pendant toute la séquence.
- Broche d'alimentation : Linux écrit 0x76802 / 0x76803 (macOS : 0x76a02 / 0x76a03, un bit « entrée active » en plus) et la
  laisse en sortie à 0 à la fin (l'essai m1n1 remettait la valeur d'origine 0x7680e).
- Le simple fait de démarrer avec ce device tree initialise le contrôleur spi2 (écritures de registres par `spi-apple`),
  même sans charger le module. Le capteur, lui, reste éteint.

## Comment faire démarrer Linux avec ce device tree
Trois voies, de la plus sûre à la moins sûre. **Aucune n'a été essayée.**

**Voie 1 (recommandée) : envoyer le device tree par le câble, démarrer le Linux de test habituel.**
Le PC envoie au Mac (en mode câble) un m1n1 suivi du device tree modifié et du chargeur U-Boot ; le Linux de test démarre
ensuite depuis le disque comme d'habitude, avec son propre noyau. Rien n'est écrit dans la chaîne de démarrage du Mac ;
au redémarrage suivant tout est comme avant. Avantage : le Linux de test a déjà le réseau, ssh et de quoi compiler le module.
Ce qui manque, précisément :
1. un script `tools/` qui fait l'envoi (assemblage `m1n1.bin` + device tree + U-Boot, puis chainload) : il n'existe pas ;
   c'est une action matérielle, donc soumise à l'accord d'Albert comme `tools/boot_test_kernel.sh` ;
2. le fichier U-Boot du Linux de test (paquet Fedora ; chemin à relever sur place, Linux allumé) ;
3. le device tree **de ce Linux-là** (celui du noyau Fedora Asahi, pas le fichier public) avec spi2 ajouté : le récupérer sur
   le Linux de test, le décompiler avec `dtc`, y ajouter le nœud de `t6001-j314c-mesa.dtsi` avec des numéros à la place des
   étiquettes (ce device tree n'a pas d'étiquettes, journal du 2026-11-10), le recompiler. Le device tree public compilé ici
   ne convient pas tel quel à ce noyau (il décrit moins de matériel) ;
4. vérifier que le m1n1 du repo accepte une charge collée derrière lui quand il est envoyé par le câble (prévu par m1n1,
   jamais fait ici).

**Voie 2 : `tools/boot_test_kernel.sh` tel quel (noyau + device tree envoyés par le câble).**
Rien d'écrit sur le disque non plus, mais il manque beaucoup : le dossier `linux/` (sources à cloner sur le PC), une
configuration de noyau (`tools/build_kernel.sh` n'en crée pas), `t6001-j314c-mesa-test.dts` et le `.dtsi` copiés dans
`linux/arch/arm64/boot/dts/apple/` (+ une ligne dans le Makefile de ce dossier, puis `DTB=…/t6001-j314c-mesa-test.dtb`),
un petit système de démarrage en mémoire (initramfs) contenant le module compilé pour ce noyau, et un moyen de lire le
résultat (sans réseau, il ne s'affiche que sur l'écran du Mac).

**Voie 3 (déconseillée) : installer le device tree modifié dans le démarrage du Linux de test.**
Modifie la chaîne de démarrage du Linux d'Albert : interdit aux agents, et inutile si la voie 1 marche.

## Ce qu'Albert doit faire à la main
Aujourd'hui : **rien, ce n'est pas encore prêt** (il manque les 4 points de la voie 1). Quand ce sera prêt, ce sera ceci :

1. Démarrer le Mac sur le Linux de test, normalement, et me dire « Linux allumé ».
   Je récupère alors deux fichiers dessus et je prépare l'envoi. Rien n'est modifié sur le Mac.
2. Éteindre le Mac, le rallumer en « mode câble » (comme pour les captures), câble USB-C branché sur le PC.
3. Coller la commande que je donnerai (une seule ligne commençant par `! ./tools/`), répondre `oui`.
4. Le Mac démarre le Linux de test comme d'habitude. Attendre l'écran de connexion, me dire « c'est démarré ».
   Je lance l'essai du capteur à distance et je lis le résultat. Pas besoin de poser le doigt.
5. Pour revenir en arrière : redémarrer le Mac normalement. Rien n'a été installé.

Ce qui peut rater : le Linux ne démarre pas (écran noir ou figé). Dans ce cas, appuyer longtemps sur le bouton
d'alimentation pour éteindre, puis rallumer normalement : rien n'est perdu, rien n'a été écrit sur le disque par cet essai.

## Hors périmètre
Trames chiffrées (0x72, 0x73, 0x55, 0x60…), interruption du capteur, images, SEP, SKS, xART : rien de tout cela ici.

## Essai réel du 2026-11-10 (LINUX-HELLO) : ça marche, sans câble et sans rien installer
Sur le Linux de test, plus besoin de changer le démarrage : `mesa_ovl.ko` ajoute le bus spi2 et le capteur à chaud
(fichiers `mesa_ovl.c`, `mesa-spi2-overlay.dts`). Un redémarrage enlève tout.
```
cd /root/mesa
make -C /lib/modules/$(uname -r)/build M=$PWD modules
dtc -I dts -O dtb -o mesa-spi2.dtbo mesa-spi2-overlay.dts && cp mesa-spi2.dtbo /lib/firmware/
insmod mesa_ovl.ko                 # décrit le matériel, n'envoie rien au capteur
insmod mesa_probe.ko enable=1      # allume le capteur, lit son identité, l'éteint
dmesg | tail -20                   # doit finir par « IDENTITÉ IDENTIQUE »
```
Les numéros (phandles) du fichier overlay viennent du device tree de CE noyau (7.2.12-402.asahi.fc45) : après une mise à
jour du noyau, les revérifier dans le DT vivant avant de charger. La section « Ce qu'Albert doit faire à la main » plus haut
(envoi par câble) n'est plus nécessaire.
