# Glossaire

Tous les termes et sigles employés dans le guide. Chaque entrée ne dit que ce qui est établi
par les sources du projet, décrites dans [annexe-sources.md](annexe-sources.md) ; quand un point n'est
pas établi, l'entrée le dit.

Les noms d'endpoints du SEP, comme `sbio` ou `xarm`, sont regroupés à l'entrée
[Endpoints du SEP](#endpoints-du-sep).

## A

**ADT**, Apple Device Tree — Description du matériel que le chargeur de démarrage d'Apple
transmet au système : liste des périphériques, adresses, interruptions, broches. C'est
l'équivalent Apple du device tree de Linux. Le projet en a une copie lue sur la machine
étudiée : c'est la trace [T-18](annexe-sources.md#t-18).

**AIC** — Contrôleur d'interruptions de l'AP. Le bus du capteur d'empreinte y a
l'interruption numéro 1108.

**AOP** — Autre coprocesseur de la puce, distinct du SEP. D'après la lecture des extensions
noyau de macOS, il n'intervient pour le capteur d'empreinte que pour sa réinitialisation ;
ce point n'a pas été vérifié par expérience.

**AP**, Application Processor — Les cœurs principaux de la puce, ceux qui exécutent le
système d'exploitation, macOS ou Linux. Dans le guide, « l'AP » désigne le côté du dialogue
que Linux devra tenir face au SEP.

**ASC** — Type de contrôleur de mailbox qu'Apple utilise pour parler à ses coprocesseurs. La
mailbox du SEP en est un.

**Asahi Linux** — Projet communautaire qui porte Linux sur les Mac à puce Apple. Sa
documentation et son code publics sont des sources de ce projet. Le présent travail est
privé et n'en fait pas partie.

## B

**Boot policy** — Réglages de sécurité du démarrage d'un Mac à puce Apple. L'endpoint `pnon`
du SEP y est associé d'après la documentation publique.

**Buffer A, buffer B** — Les deux buffers OOL d'un endpoint. Le buffer A est configuré par
les messages de contrôle de type 0x04 et 0x02, le B par 0x05 et 0x03. Que A serve au sens
AP → SEP et B au sens SEP → AP est une hypothèse, cohérente avec les traces mais non testée
séparément.

## C

**Capture** — Un enregistrement fait dans le setup [S1](annexe-sources.md#s1) : un démarrage
de macOS sous l'hyperviseur, avec les fichiers produits par le traceur. Chaque capture est
une trace `[T-xx]` de l'annexe.

**Catacomb** — Nom que les extensions noyau de macOS donnent au bloc de données qui contient
les gabarits d'empreintes. Le SEP l'exporte chiffré, macOS le conserve et le lui renvoie à
l'identique au démarrage suivant. Son contenu est opaque.

**Chainload** — Chargement d'une copie fraîche de m1n1 par le m1n1 déjà installé sur le Mac.
Fait avant chaque capture, parce que l'interface entre m1n1 et ses outils côté PC change
d'une version à l'autre.

**Chip-select**, CS — Ligne d'un bus SPI qui désigne le périphérique auquel on parle. Le bus
du capteur d'empreinte n'en a pas.

**CNTL** — Voir `cntl` à l'entrée [Endpoints du SEP](#endpoints-du-sep).

**CPHA, CPOL** — Les deux réglages, phase et polarité de l'horloge, qui définissent le mode
d'un bus SPI. Le capteur d'empreinte fonctionne avec CPHA = 1 et CPOL = 0.

**CRC** — Somme de contrôle. Deux usages dans le guide : le CRC-16/ARC qui protège chaque
tranche d'image envoyée par le capteur, et les CRC que le noyau macOS affiche pour les blocs
xART.

## D

**DART** — IOMMU des puces Apple : elle traduit les adresses vues par un périphérique, les IOVA,
en adresses physiques. Le SEP a la sienne, nommée `dart-sep` dans l'ADT ; sur la machine étudiée
elle est du modèle que le code public appelle `t6000`.

**Découverte** — Phase où le SEP annonce ses endpoints à l'AP, sur l'endpoint 0xFD : pour
chacun, son numéro et un nom de quatre caractères.

**Device tree**, DT — Description du matériel utilisée par le noyau Linux. Le device tree
public pour cette machine ne décrit pas le bus du capteur d'empreinte ; le projet l'ajoute à
chaud par un **overlay**, un fragment appliqué au device tree en cours d'utilisation.

**DMA** — Transfert de données entre un périphérique et la mémoire sans passer octet par
octet par le processeur. Sous macOS, les données du bus du capteur passent par DMA, via le
coprocesseur SIO.

**Donnée prête**, broche — Broche 195 du contrôleur `gpio0`, pilotée par le capteur
d'empreinte. Elle passe à 1 quand le capteur a une réponse en attente et retombe à 0 quand
l'AP lit l'état du capteur.

## E

**Endpoint**, EP — Numéro sur 8 bits, présent dans chaque message, qui désigne le service du
SEP auquel le message s'adresse ou dont il provient.

<a id="endpoints-du-sep"></a>
**Endpoints du SEP** — Douze endpoints applicatifs sont annoncés sur la machine étudiée, les
mêmes que dans la documentation Asahi, d'où viennent les rôles ci-dessous.

| Numéro | Nom | Rôle |
|---|---|---|
| 0x00 | `cntl` | contrôle : activation des endpoints, configuration de leurs buffers OOL |
| 0x08 | `sbio` | authentification biométrique : Touch ID |
| 0x0a | `scrd` | identifiants de l'utilisateur ; rôle donné comme probable |
| 0x0c | `sse` | NFC / Apple Pay |
| 0x0e | `hdcp` | protection de contenu vidéo |
| 0x10 | `xars` | mise en place de xART |
| 0x12 | `sks` | Secure Key Store : gestion des clés et du keybag |
| 0x13 | `xarm` | gestionnaire xART : restitution et sauvegarde des lockers |
| 0x14 | `hibe` | hibernation |
| 0x15 | `pnon` | boot policy |
| 0x17 | `skdl` | liste d'extensions noyau interdites |
| 0x18 | `stac` | accessoires de confiance |
| 0xFD | — | découverte : annonce des endpoints |
| 0xFE | — | démarrage : mémoire partagée |
| 0xFF | — | ROM de démarrage du SEP |

## F

**FileVault** — Chiffrement du disque de macOS. Les stockages xART et SKS du SEP lui servent
aussi, d'où le risque pour les données macOS de toute écriture vers ces services.

**Firmware du SEP** — Le programme de SEPOS. iBoot le dépose en mémoire avant de passer la
main ; l'AP le désigne ensuite au SEP par le message BOOT_IMG4.

**Forger** — Fabriquer un locker xART au lieu de rendre celui que le SEP a fait sauver.
Demanderait la clé interne du SEP ; exclu. S'oppose à **rejouer**.

## G

**Gabarit** — Représentation d'une empreinte enrôlée, à laquelle le SEP compare l'image d'un
doigt. Les gabarits ne sortent du SEP que chiffrés : voir **catacomb**.

**Gigalocker** — Fichier du disque macOS où sont rangés les lockers xART : un fichier `.gl`
sur un volume dédié nommé `xART`.

**GPIO** — Broche d'entrée-sortie pilotable par logiciel. `gpio0` est le contrôleur de broches
auquel sont reliées l'alimentation du capteur, broche 196, et sa ligne « donnée prête »,
broche 195.

**`gt_packet`, transfert générique** — Format que macOS utilise pour faire passer des données
volumineuses par un buffer OOL : un en-tête de 0x1c octets, qui donne la version, la taille totale, la
position du morceau, le type de commande et la taille du morceau, suivi des données. Un transfert plus grand
que le buffer est découpé en plusieurs morceaux.

## H

**HDCP** — Protection anticopie des sorties vidéo. Sans rapport avec Touch ID ; cité parce
que le SEP a un endpoint de ce nom.

**Hyperviseur** — Ici, le mode de m1n1 dans lequel il fait tourner un système, ici macOS 13.5,
comme invité et peut intercepter ses accès au matériel. C'est ce qui permet d'observer le
dialogue entre macOS et le SEP sans modifier macOS.

## I

**iBoot** — Chargeur de démarrage d'Apple. Il s'exécute avant m1n1 et avant tout système ;
il laisse notamment les broches du bus du capteur déjà configurées.

**IMG4** — Format de conteneur des images de démarrage d'Apple. Dans le guide : le firmware
du SEP, que l'AP lui remet au démarrage par le message BOOT_IMG4.

**Invité** — Système d'exploitation qui tourne sous un hyperviseur.

**IOMMU** — Unité de traduction d'adresses placée entre un périphérique et la mémoire. Voir
**DART**.

**IOVA** — Adresse telle que la voit un périphérique placé derrière une IOMMU. Les messages
du SEP désignent les buffers partagés par leur IOVA exprimée en pages de 4 Kio, c'est-à-dire
l'adresse divisée par 0x1000.

## J

**`j314c`** — Désignation interne du MacBook Pro 14" M1 Max étudié.

## K

**Kernelcache** — Fichier de macOS qui regroupe le noyau et ses extensions. Le noyau lancé
sous l'hyperviseur en est extrait.

**Kext** — Extension du noyau de macOS, l'équivalent d'un module noyau Linux. « Source :
kext » signale une information tirée de la lecture de ces extensions, limitée au protocole
entre l'AP et le SEP.

**Keybag** — Ensemble de clés d'un utilisateur, détenu par le SEP et géré par l'endpoint
`sks`. Il est verrouillé ou déverrouillé ; son état conditionne l'accès aux clés.

## L

**linux-asahi** — Arbre du noyau Linux maintenu par le projet Asahi Linux.

**Locker** — Bloc de données chiffré que le SEP confie à l'AP pour qu'il le conserve sur
disque et le lui rende plus tard. Voir **xART**.

**`lockState`** — Valeur sur 16 bits qui décrit l'état de verrouillage d'un keybag. Le nom et
la signification des bits viennent de la lecture des extensions noyau ; leur interprétation
reste une hypothèse.

## M

**m1n1** — Chargeur de démarrage du projet Asahi Linux pour les Mac à puce Apple. Il sert ici
de trois façons : en mode proxy, en hyperviseur, et comme source publique sur le démarrage
du SEP.

**Mailbox** — Mécanisme matériel par lequel l'AP et le SEP s'échangent des messages : une
boîte par sens, dans laquelle on dépose un mot de 64 bits.

**Marque**, repère — Ligne horodatée posée à la main pendant une capture pour noter un geste,
par exemple « doigt posé » ou « mot de passe saisi ».

**Mémoire partagée**, shmem — Zone de mémoire que l'AP met à disposition du SEP pendant son
démarrage, par un message sur l'endpoint 0xFE.

**Mesa** — Nom du capteur d'empreinte dans macOS et dans l'ADT, où il s'appelle `biosensor,mesa`. C'est un
périphérique SPI de l'AP, pas du SEP.

**Messages de démarrage** — Messages que l'AP envoie à la ROM du SEP pour le démarrer. Leurs
noms viennent du code public de m1n1 : GET_STATUS, type 0x02, demande son état à la ROM ;
BOOT_TZ0, type 0x05, lance la seconde phase ; BOOT_IMG4, type 0x06, désigne le firmware. Ces
trois messages vont sur l'endpoint 0xFF. SET_SHMEM, sur l'endpoint 0xFE, concerne la mémoire
partagée. GETRAND, type 0x10 sur l'endpoint 0xFF, demande des octets aléatoires et ne fait pas
partie de la séquence. Voir [Démarrage du SEP](03-boot-sep.md).

**MMIO** — Registres d'un périphérique accessibles comme de la mémoire.

**Mot**, de mailbox — Les 64 bits d'un message : endpoint sur les bits 0 à 7, tag sur 8 à 15, type sur
16 à 23, param sur 24 à 31, data sur 32 à 63. Ce découpage vient de la documentation Asahi ;
il s'est révélé cohérent avec toutes les captures sans exception.

## O

**OOL**, *out of line*, « hors ligne » — Se dit des données trop volumineuses pour un mot de
mailbox : elles sont déposées dans un buffer en mémoire dont l'adresse a été convenue à
l'avance, et le message ne fait que signaler qu'elles y sont.

## P

**PC hôte** — Le PC sous Linux relié au Mac par USB, sur lequel tournent les outils.

**`pending/`** — Dossier du dépôt qui regroupe les scripts envoyant quelque chose au SEP. Ils
sont séparés du reste parce qu'ils ne sont jamais lancés automatiquement.

**pmgr** — Gestionnaire d'alimentation de la puce. Chaque contrôleur y a un domaine
d'alimentation ; celui du bus du capteur s'appelle `ps_spi2` dans le device tree public.

**Proxy**, mode — Mode de m1n1 où il n'exécute rien de lui-même et attend, par USB, les
ordres d'un programme sur le PC hôte : lire un registre, écrire en mémoire, appeler une
fonction.

## R

**Rejouer** — Rendre au SEP, tels quels, les lockers xART qu'il a lui-même fait sauver. Ne
demande pas d'en comprendre le contenu. S'oppose à **forger**. On ne sait pas encore si le
SEP accepterait un rejeu venant d'un autre système que macOS.

**Rejeu hors ligne** — Relecture des captures par du code écrit à partir de la description du
protocole, pour contrôler cette description. Rien n'est envoyé au Mac.

**ROM du SEP**, **SEPROM** — Premier programme qu'exécute le SEP. Elle répond sur l'endpoint
0xFF, et c'est elle qui reçoit les messages de démarrage. Le code public de m1n1 l'appelle
SEPROM.

## S

**SandDollar** — Nom de la famille de capteurs à laquelle macOS rattache le capteur
d'empreinte de cette machine.

**SEP**, Secure Enclave Processor — Coprocesseur de sécurité de la puce, isolé de l'AP. Il
détient les secrets, clés et gabarits d'empreintes, et ne les expose jamais ; l'AP ne peut que
lui envoyer des messages et lire ses réponses. Il n'a pas de stockage persistant propre.

**SEPOS** — Le système complet du SEP, celui qui fournit les services : biométrie, clés,
xART. Il n'est en fonction qu'une fois que l'AP a remis son firmware à la ROM.

**Session chiffrée** — Canal chiffré établi entre le SEP et le capteur d'empreinte. L'AP en
transporte les messages sans pouvoir les lire ni les fabriquer.

**Setup** — Montage matériel et logiciel dans lequel une observation a été faite. Les setups
sont décrits dans [annexe-sources.md](annexe-sources.md) et cités `S1`, `S2`…

**SIO** — Coprocesseur de la puce qui prend en charge, sous macOS, les transferts DMA de
certains bus, dont celui du capteur.

**SKS**, Secure Key Store — Service du SEP qui gère les clés et le keybag. Son endpoint est `sks`,
numéro 0x12.

**SPI** — Bus série synchrone. Le capteur d'empreinte est relié au contrôleur `spi2` de l'AP.

**`spi-apple`** — Pilote Linux public des contrôleurs SPI des puces Apple. Il suffit, tel
quel, pour dialoguer avec le capteur.

**Synchrone, asynchrone**, modes du traceur — En mode synchrone, l'invité est mis en pause à
chaque accès tracé, ce qui permet de lire la mémoire à cet instant précis mais ralentit le
Mac ; en mode asynchrone il continue de tourner. Lire le contenu des buffers OOL impose le
mode synchrone.

## T

**`t6001`** — Désignation interne de la puce Apple M1 Max.

**Tag, type, param, data** — Les champs d'un mot de mailbox autres que l'endpoint. Le type
désigne l'opération ; le tag sert en général à associer une réponse à sa requête.

**Touch ID** — Déverrouillage par empreinte digitale. Objectif du projet : le faire
fonctionner sous Linux.

**Trace** — Ensemble des fichiers enregistrés lors d'un essai, cité `[T-xx]` et décrit dans
[annexe-sources.md](annexe-sources.md).

**Traceur** — Script exécuté côté PC hôte pendant que macOS tourne sous l'hyperviseur ; il
consigne les messages échangés avec le SEP. Il n'écrit jamais rien vers le SEP.

**Trame** — Un message sur le bus du capteur : un court en-tête, commande et longueur, suivi
éventuellement de données.

**Trousseau** — Stockage des mots de passe et clés de l'utilisateur dans macOS. Cité parce
que le contenu conservé par xART y est lié, comme à FileVault.

**TZ0** — Nom d'une étape du démarrage du SEP, déclenchée par le message BOOT_TZ0, de type 0x05
sur l'endpoint 0xFF. La documentation Asahi décrit ce message comme faisant passer le SEP
en seconde phase de démarrage, une portion de mémoire lui étant réservée. Nos sources n'en
disent pas plus.

## U

**UART de l'hyperviseur** — Port série virtuel par lequel m1n1 transmet au PC hôte le journal
du noyau macOS invité.

**uid** — Identifiant numérique d'un utilisateur. Vaut 501 pour l'utilisateur de la machine
étudiée.

## X

**xART** — Mécanisme anti-rejeu du SEP. Le SEP n'ayant pas de stockage, il confie des lockers
à l'AP, qui les écrit sur disque et les lui rend au démarrage suivant ; xART garantit que le
SEP reçoit la dernière version sauvée et non une plus ancienne.
<!-- QUESTION ALBERT : le chapitre 5 actuel développe le sigle en « eXtended Anti-Replay Token ». Je ne trouve cette expansion dans aucune source du dépôt (xart_options.md dit seulement « anti-replay / anti-rollback »). D'où vient-elle ? Sans source, je ne la reprends pas. -->

**XNU** — Le noyau de macOS.
