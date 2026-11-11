# Annexe — setups et sources

Cette annexe est le seul endroit du guide où apparaissent les noms réels des dossiers de
traces et les anciennes étiquettes de travail. Les chapitres y renvoient par `S1`, `S2`…
pour les setups et par `[T-xx]` pour les traces. Elle dit, pour chaque source, dans quelles conditions elle a
été produite et ce qu'elle permet d'affirmer.

## Matériel commun à tous les setups

- **Machine étudiée** : MacBook Pro 14" à puce Apple M1 Max. Désignation interne `j314c`,
  puce `t6001`. Une empreinte y est enrôlée dans macOS 13.5.
- **PC hôte** : un PC sous Arch Linux, relié au Mac par un câble USB-C de données. Tout le
  travail d'analyse s'y fait ; le Mac n'est que le banc d'essai.
- **m1n1** : commit public `70757dc7`, non modifié. Une copie fraîche est rechargée sur le
  Mac avant chaque capture.
- **macOS** : version 13.5, installée sur un volume dédié. C'est la seule version que
  l'hyperviseur de m1n1 sait faire tourner.

## Setups

<a id="s1"></a>
### S1 — macOS 13.5 observé par l'hyperviseur m1n1

Le noyau de macOS 13.5 est lancé comme **invité** de l'hyperviseur m1n1. Un script de trace,
exécuté sur le PC hôte, intercepte les accès du noyau aux registres de la mailbox du SEP et
les consigne. Lancé par `tools/boot_and_trace.sh`.

| | |
|---|---|
| Sur le Mac | m1n1 en hyperviseur, macOS 13.5 invité, en session normale : login, verrouillage, Touch ID |
| Sur le PC | client m1n1 + script de trace : `hv/trace_sep_filtered.py`, ou ses variantes `hv/trace_sep_spi.py` et `hv/trace_sep_spi_dma.py` qui écoutent aussi le bus du capteur |
| Fichiers produits | `sep.log` : un message AP ↔ SEP par ligne. `hv_uart.log` : journal du noyau macOS. `marks.txt` et `notes.txt` : repères horaires et résultats notés pendant les sessions avec doigt. `sep.log.ool/` : contenu des buffers partagés. `spi2.log`, `sio.log`, `sio.bufs/` : bus du capteur |
| Ce que ça permet | Voir tous les messages échangés entre macOS et le SEP ; lire le contenu des buffers partagés ; écouter le dialogue entre macOS et le capteur ; faire correspondre un geste humain, doigt ou mot de passe, à des messages |
| Ce que ça ne permet pas | Envoyer quoi que ce soit au SEP : l'observation est en lecture seule. Savoir ce que le SEP *exige* : on ne voit que ce que macOS fait. Lire le contenu chiffré |
| Limites connues | Horodatage = horloge du PC, pas celle du Mac. Le Mac est ralenti : le délai entre requête et réponse sur l'endpoint biométrique passe d'environ 2,4 ms à 7,4 ms quand on lit tous les buffers. Demande le câble USB et, pour les essais avec doigt, quelqu'un devant le Mac |

Variante **sans traceur** : même montage, mais aucun script de trace. Elle n'a servi qu'à
confirmer que Touch ID fonctionne encore quand macOS tourne sous l'hyperviseur : ce sont les essais
[T-01](#t-01) et [T-02](#t-02).

<a id="s2"></a>
### S2 — m1n1 seul, sans système invité

m1n1 est en **mode proxy** : il attend les ordres du PC hôte et aucun système d'exploitation
ne tourne sur le Mac. Le matériel est dans l'état où iBoot, le chargeur de démarrage d'Apple,
l'a laissé.

| | |
|---|---|
| Sur le Mac | m1n1 seul |
| Sur le PC | scripts de `tools/` pour lire l'ADT et des registres et dialoguer avec le capteur ; scripts de `pending/` pour ce qui envoie un message au SEP |
| Fichiers produits | selon l'essai : `adt.bin` / `adt.txt`, `peek.log`, `getrand.log`, `boot.log`, `hello.log`, `dialog.txt` |
| Ce que ça permet | Lire l'ADT, la description matérielle, et des registres ; piloter directement une broche ou le bus du capteur ; parler à la ROM du SEP et tenter de démarrer SEPOS |
| Ce que ça ne permet pas | Observer macOS. Reproduire ce que macOS fait après le démarrage du SEP : personne ne tient le rôle de l'AP, notamment pour xART |
| Limites connues | Un échec se solde par un redémarrage du Mac. Le seul démarrage de SEPOS fait dans ce setup a été suivi d'une demande de reconnexion au compte Apple sous macOS, de cause non établie |

<a id="s3"></a>
### S3 — Linux de test sur le Mac

Une installation Fedora Asahi Remix sur le même Mac, avec le noyau `7.2.12-402.asahi.fc45` à pages de
16 Kio. Elle est considérée comme jetable et pilotée à distance par SSH, avec `tools/linux_ssh.sh`. Pas de
câble USB, pas de m1n1 en mode proxy.

| | |
|---|---|
| Sur le Mac | Linux, avec les modules de `driver/linux/` compilés et chargés sur place ; le bus du capteur est ajouté à chaud au device tree : rien n'est installé, un redémarrage enlève tout |
| Sur le PC | SSH seulement |
| Fichiers produits | aucun dossier dans `traces/`. Les commandes passées sont dans `logs/linux_ssh.log` ; les sorties de `dmesg` sont recopiées dans `docs/journal.md` à la date de l'essai |
| Ce que ça permet | Dialoguer en clair avec le capteur depuis Linux ; développer la couche transport du pilote |
| Ce que ça ne permet pas | Parler au SEP : rien ne lui est envoyé depuis ce setup |
| Limites connues | Les numéros internes utilisés pour l'ajout à chaud ne valent que pour ce noyau. Essais avec doigt : le moment où le doigt est posé est déclaré, pas mesuré |

<a id="s4"></a>
### S4 — macOS 13.5 démarré normalement

macOS démarre seul, sans m1n1. Aucune capture : seules des observations humaines en
proviennent : Touch ID fonctionne avec la sécurité de démarrage abaissée ; deux redémarrages
se sont faits sans nouvelle demande de reconnexion au compte Apple après l'incident de [S2](#s2).

### Sources sans matériel

- **Documentation et code publics** : documentation Asahi Linux, code public de m1n1 et de
  linux-asahi, code source ouvert publié par Apple. Les noms des messages de démarrage,
  GET_STATUS, BOOT_TZ0, BOOT_IMG4, SET_SHMEM et GETRAND, et les rôles des endpoints en
  viennent.
- **Lecture des extensions noyau de macOS 13.5**, notée « source : kext » dans les notes de
  travail : lecture statique, limitée au protocole entre l'AP et le SEP, c'est-à-dire format,
  séquences et constantes. Elle donne des
  noms et des structures ; à elle seule elle ne rend pas un point « vérifié ».
- **Rejeu hors ligne**, dans `driver/sepreplay`, 29 tests : du code écrit à partir de la
  description du protocole relit les captures et doit retrouver exactement ce que macOS a
  envoyé. Rien n'est émis vers le Mac.

## Catalogue des traces

Tous les dossiers sont dans `traces/`. « Ancien nom » est l'étiquette utilisée dans les notes
de travail.

### Setup S1 — macOS sous hyperviseur

| ID | Dossier | Date | Ancien nom | Ce que la trace montre |
|---|---|---|---|---|
| <a id="t-01"></a>T-01 | `20261107_h2-notrace` | 07/11/2026 | H2, essai 1 | Sans traceur. macOS démarre sous l'hyperviseur et Touch ID fonctionne, d'après une observation humaine ; le client du PC a perdu la liaison USB en cours de route, début du journal noyau perdu |
| <a id="t-02"></a>T-02 | `20261107_h2-notrace-2` | 07/11/2026 | H2, essai 2 | Sans traceur. Même essai, liaison conservée jusqu'au bout ; verrouillage et déverrouillage par Touch ID réussis |
| <a id="t-03"></a>T-03 | `20261107-033436_c1-boot` | 07/11/2026 | C1 | Première capture complète : démarrage du SEP, annonce des 12 endpoints, login par mot de passe, un verrouillage, un déverrouillage au doigt. Sert de référence pour la séquence de démarrage |
| <a id="t-04"></a>T-04 | `20261107-034313_c2a-boot` | 07/11/2026 | C2a | Démarrage sans intervention prévue, premier d'une paire destinée à repérer ce qui varie d'un démarrage à l'autre |
| <a id="t-05"></a>T-05 | `20261107-034841_c2b-boot` | 07/11/2026 | C2b | Second démarrage de la paire |
| <a id="t-06"></a>T-06 | `20261107-035422_c3-touchid` | 07/11/2026 | C3, avortée | Session Touch ID interrompue, protocole non respecté ; non analysée |
| <a id="t-07"></a>T-07 | `20261107-035930_c3-touchid` | 07/11/2026 | C3 | Session Touch ID : verrouillages, mot de passe, bons et mauvais doigts. Repères horaires peu fiables |
| <a id="t-08"></a>T-08 | `20261107-042414_c4-shmem` | 07/11/2026 | C4 | Démarrage avec lecture unique de l'en-tête de la mémoire partagée du SEP, à travers le DART du SEP |
| <a id="t-09"></a>T-09 | `20261107-043309_c5-ool-boot` | 07/11/2026 | C5 | Démarrage avec lecture du contenu des buffers partagés de l'endpoint biométrique |
| <a id="t-10"></a>T-10 | `20261107-043828_c6-doigt-ool` | 07/11/2026 | C6 | Session avec doigt et lecture complète des buffers ; le seul essai avec le bon doigt a échoué ; un lien avec le ralentissement dû à la lecture est possible, non établi |
| <a id="t-11"></a>T-11 | `20261107-045400_c7-ool-light` | 07/11/2026 | C7 | Démarrage avec lecture allégée des buffers |
| <a id="t-12"></a>T-12 | `20261108-004657_c8-doigt-ool` | 08/11/2026 | C8 | Session avec doigt : 3 bons doigts acceptés, mauvais doigts refusés ; contenu des réponses de comparaison |
| <a id="t-13"></a>T-13 | `20261108-010915_c9-boot-ool-persist` | 08/11/2026 | C9 | Démarrage sans intervention après T-12 : ce que macOS renvoie au SEP au démarrage après des succès |
| <a id="t-14"></a>T-14 | `20261108-011515_c10-boot-ool-stable` | 08/11/2026 | C10 | Démarrage de macOS bloqué ou très ralenti avant l'initialisation biométrique, cause inconnue |
| <a id="t-15"></a>T-15 | `20261108-012015_c10b-boot-ool-stable` | 08/11/2026 | C10b | Reprise de T-14 : démarrage complet, sans intervention ni succès Touch ID depuis T-13 |
| <a id="t-16"></a>T-16 | `20261108-025802_c11-doigt-tranchant` | 08/11/2026 | C11 | Longue session avec doigt : 24 tentatives entre correspondances, refus et abandons, série de mauvais doigts, invite dans une session déjà ouverte |
| <a id="t-17"></a>T-17 | `20261108-032454_c12-boot-ho` | 08/11/2026 | C12 | Démarrage sans intervention après T-16 : macOS renvoie au SEP, à l'identique, le dernier bloc de gabarits exporté pendant T-16 |
| <a id="t-19"></a>T-19 | `20261108-163401_c13-ke1` | 08/11/2026 | C13 | Session inutilisable : macOS s'est mis en veille à l'écran de connexion |
| <a id="t-20"></a>T-20 | `20261108-171039_c14-ke1` | 08/11/2026 | C14 | Nouvelle tentative de la même session ; un seul repère posé, pas d'analyse consignée |
| <a id="t-21"></a>T-21 | `20261108-181424_c15-ke1` | 08/11/2026 | C15 : K-E1, 1re moitié | Quatre invites Touch ID dans une session ouverte, 3 bons doigts et 1 mauvais, puis un verrouillage et un mot de passe |
| <a id="t-22"></a>T-22 | `20261108-183948_c16-ke1` | 08/11/2026 | C16 : K-E1, 2e moitié | Verrouillage puis mot de passe ; verrouillage puis doigt ; verrouillage, attente, doigt |
| <a id="t-32"></a>T-32 | `20261110-001859_c17-spi-boot` | 10/11/2026 | C17 | Démarrage avec relevé des registres du bus du capteur et de ses broches, sans le contenu des échanges |
| <a id="t-33"></a>T-33 | `20261110-002417_c18-spi-dma-boot` | 10/11/2026 | C18 | Démarrage avec lecture du contenu des échanges entre macOS et le capteur ; lecture incomplète |
| <a id="t-34"></a>T-34 | `20261110-002829_c19-spi-dma-boot` | 10/11/2026 | C19 | Même chose, lecture complète : trames en clair et trames chiffrées |
| <a id="t-35"></a>T-35 | `20261110-003201_c20-doigt-spi` | 10/11/2026 | C20 | Session avec doigt en écoutant à la fois le capteur et le SEP : 27 images lues sur le bus, 7 transmises au SEP, identiques octet pour octet |

### Setup S2 — m1n1 seul

| ID | Dossier | Date | Ancien nom | Ce que la trace montre |
|---|---|---|---|---|
| <a id="t-18"></a>T-18 | `20261108-162919_adt` | 08/11/2026 | ADT-1 | Copie de l'ADT, la description matérielle : emplacement du capteur, bus, broches, fréquence |
| <a id="t-23"></a>T-23 | `20261109-210517_sep_peek` | 09/11/2026 | SEP-PEEK | Lecture de trois registres d'état du SEP, sans rien lui envoyer : boîtes vides, compteurs de lecture et d'écriture non nuls |
| <a id="t-24"></a>T-24 | `20261109-211028_sep_getrand` | 09/11/2026 | SEP-GETRAND, essai 1 | Essai invalide : mauvaise adresse d'appel dans m1n1, le message n'est très probablement jamais parti. Ne dit rien sur le SEP |
| <a id="t-25"></a>T-25 | `20261109-211050_sep_peek_apres_getrand` | 09/11/2026 | — | Dossier incomplet, sans relevé |
| <a id="t-26"></a>T-26 | `20261109-211835_check_sym` | 09/11/2026 | — | Contrôle de l'adresse d'une fonction de m1n1, cause de l'échec de T-24 |
| <a id="t-27"></a>T-27 | `20261109-211849_check_sym` | 09/11/2026 | — | Même contrôle, adresse corrigée |
| <a id="t-28"></a>T-28 | `20261109-212150_sep_getrand` | 09/11/2026 | SEP-GETRAND | La ROM du SEP répond à GETRAND sans macOS : quatre octets aléatoires reçus |
| <a id="t-29"></a>T-29 | `20261109-220855_sep_boot` | 09/11/2026 | SEP-BOOT, essai 1 | Échec côté m1n1 avant tout message au SEP, mauvais type de DART ; le Mac a redémarré |
| <a id="t-30"></a>T-30 | `20261109-221029_sep_boot` | 09/11/2026 | SEP-BOOT | Démarrage de SEPOS depuis m1n1 : séquence acceptée, 7 endpoints annoncés sur 12 ; 4 messages du SEP restés non lus, contenu perdu |
| <a id="t-31"></a>T-31 | `20261110-001208_gpio_peek` | 10/11/2026 | — | Lecture de la configuration des broches et de l'alimentation des bus SPI, telles qu'iBoot les laisse |
| <a id="t-36"></a>T-36 | `20261110-005244_mesa_hello` | 10/11/2026 | MESA-HELLO | Le capteur, alimenté et interrogé depuis m1n1, renvoie la même identité que sous macOS |
| <a id="t-37"></a>T-37 | `20261110-005318_mesa_hello2` | 10/11/2026 | MESA-HELLO, 2e essai | Répétition de T-36 : résultat identique |

### Setup S3 — Linux de test, essais sans dossier de trace

Ces essais n'ont pas de dossier dans `traces/`. Leur seule trace écrite est l'entrée de
`docs/journal.md` à la date indiquée, plus les commandes dans `logs/linux_ssh.log`.

| ID | Date | Ancien nom | Ce que l'essai montre |
|---|---|---|---|
| <a id="t-38"></a>T-38 | 10/11/2026 | LINUX-HELLO | Depuis Linux, avec le pilote SPI public, le capteur renvoie la même identité que sous macOS et sous m1n1 |
| <a id="t-39"></a>T-39 | 10/11/2026 | LINUX-HELLO, 2e essai | Même résultat après réorganisation du module en couche transport séparée |
| <a id="t-40"></a>T-40 | 10/11/2026 | boucle d'état ; DOIGT-LINUX, 1re passe | État du capteur lu chaque seconde : stable 30 s au repos. Passe avec doigt non confirmée |
| <a id="t-41"></a>T-41 | 10/11/2026 | DOIGT-LINUX, 2e passe | Doigt déclaré posé pendant environ 17 s : l'état lu ne change pas |
| <a id="t-42"></a>T-42 | 10/11/2026 | DOIGT-LINUX-IRQ | La broche « donnée prête » fonctionne sous Linux mais ne réagit pas au doigt |
| <a id="t-43"></a>T-43 | 10/11/2026 | broche pendant le « bonjour » | La broche remonte à chaque nouvelle réponse en attente et retombe à la lecture de l'état |
| <a id="t-44"></a>T-44 | 10/11/2026 | transport réactif | Le dialogue donne le même résultat en attendant la broche plutôt qu'un délai fixe |

### Séries de traces

| ID | Composition | Usage |
|---|---|---|
| <a id="t-g1"></a>T-G1 | Les 19 captures S1 qui contiennent un `sep.log`, de T-03 à T-22, sauf T-18 qui relève du setup S2 | « Les 19 démarrages de macOS observés » : échange xART au démarrage, ordre d'apparition des endpoints |
| <a id="t-g2"></a>T-G2 | T-09, T-10, T-11, T-12, T-13, T-15, T-16, T-17 | « Huit démarrages complets avec lecture des buffers » : ordre d'annonce des endpoints, séquence d'initialisation biométrique |
| <a id="t-g3"></a>T-G3 | T-32, T-33, T-34, T-35 | Écoute du bus du capteur sous macOS |

## Anciennes étiquettes

Ces étiquettes viennent des notes de travail. Elles ne doivent plus apparaître dans les
chapitres ; cette table sert à faire le lien quand on remonte aux preuves.

| Étiquette | Signification |
|---|---|
| `C1` … `C20` | Captures faites dans le setup S1, numérotées dans l'ordre. `C1` = T-03, `C20` = T-35 ; voir la colonne « Ancien nom » |
| `H1`, `H2` | Deux hypothèses préalables : « Touch ID est refusé quand la sécurité de démarrage est abaissée », réfutée dans le setup S4 ; « Touch ID fonctionne encore sous l'hyperviseur », confirmée par T-01 et T-02 |
| `HA` … `HO` | Hypothèses issues des captures, lettre attribuée dans l'ordre d'apparition |
| `K1` … `K7` | Points lus dans les extensions noyau puis confrontés aux captures |
| `K-E1` | Expérience avec doigt destinée à savoir si certaines notifications suivent l'état du keybag ou le verdict biométrique : T-21 et T-22 |
| `ADT-1` | Lecture de l'ADT : T-18 |
| `SEP-PEEK`, `SEP-GETRAND`, `SEP-BOOT` | Essais sur le SEP dans le setup S2 : T-23, T-28, T-30 |
| `MESA-HELLO` | Premier dialogue avec le capteur sans macOS : T-36, T-37 |
| `LINUX-HELLO` | Même dialogue depuis Linux : T-38, T-39 |
| `DOIGT-LINUX`, `DOIGT-LINUX-IRQ` | Doigt posé alors que le capteur n'est piloté que par Linux : T-40 à T-42 |
| `SPI-1` … `SPI-4` | Résultats sur le bus du capteur : image relayée telle quelle dans T-35, transport observé dans T-G3, dialogue sans macOS dans T-36 et T-37, dialogue depuis Linux dans T-38 |
| `SKS-1` | Question ouverte : le SEP refuse-t-il une comparaison tant que le mot de passe n'a pas été saisi ? Aucune trace ne la tranche |
| Voies `A` … `E` | Pistes envisagées pour obtenir l'endpoint biométrique sous Linux : A, rester côté capteur ; B, observer le contenu de l'échange xART ; C, rejouer ce contenu ; D, le fabriquer ; E, démarrer un SEP sans état |
| `connu-doc` | Statut « vient de la documentation ou du code publics » |
| `source: kext` | Information issue de la lecture des extensions noyau de macOS |

<!-- QUESTION ALBERT : T-04 et T-05 (C2a, C2b) et T-20 (C14) n'ont pas d'entrée d'analyse dans le journal. Les descriptions ci-dessus viennent du plan d'expérience et de meta.txt. Sais-tu ce qui s'est passé pendant ces trois captures ? -->
<!-- QUESTION ALBERT : le journal dit que le premier essai de démarrage du SEP n'a « pas de dossier de trace », mais traces/20261109-220855_sep_boot existe et contient l'erreur. Je l'ai catalogué comme T-29 = cet essai. Correct ? -->
