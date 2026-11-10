# 6. Le capteur Mesa

Le capteur d'empreinte (famille `SandDollar`, compatible ADT `biosensor,mesa`) est un
périphérique **SPI de l'AP**, pas un service du SEP ni de l'AOP. Il se rattache par
`IONameMatch = biosensor,mesa` à un contrôleur SPI de l'AP (`source: kext`, personnalités
IOKit). Référence détaillée : `docs/sensor_hw.md`.

## Matériel (bus `spi2`)

**Vérifié** (lecture ADT, puis essais matériels ; `docs/verification_status.md` ADT-1, SPI-3, SPI-4) :

- Contrôleur `spi2` à l'adresse MMIO `0x39b108000`, interruption AIC 1108.
- Mode SPI : CPHA = 1, CPOL = 0, 8 bits, **pas de chip-select câblé** ; diviseur d'horloge 3
  (horloge de 24 MHz, fréquence demandée 8 MHz).
- Alimentation du capteur : GPIO `gpio0` broche 196, **active haute**.
- Broche « donnée prête » : `gpio0` broche 195 (voir plus bas).
- Domaine d'alimentation du contrôleur : `ps_spi2` (pmgr), géré par le noyau.
- Transferts assurés par le coprocesseur **SIO** (canaux DMA 0x18/0x19) sous macOS.
- Les broches SPI sont laissées en l'état par iBoot : aucune configuration `pinctrl` à ajouter.

## Transport en clair

Quatre trames circulent **en clair** sur le bus (le reste est chiffré, voir plus bas). Format
`80 <commande> <longueur 16 bits gros-boutiste> 00 00 00`, réponses préfixées `80 ..` :

- `0x78` réveil ;
- `0x10` demande d'état → réponse d'état `80 20 00 10 …` (indique notamment le nombre d'octets
  en attente) ;
- `0x70` demande d'identité ;
- `0x13` lecture d'une réponse en attente.

**Vérifié** : depuis m1n1 seul (essai MESA-HELLO, 2 fois) et depuis Linux (LINUX-HELLO), ces
trames obtiennent du capteur une **identité identique** à celle lue sous macOS
(`80 d4 00 1b … d8 75 76`). Le pilote public `spi-apple` suffit au transport ; son chip-select
interne ne gêne pas. Linux peut donc allumer le capteur et dialoguer en clair, sans SEP.

## Broche « donnée prête » (gpio0 195)

**Vérifié** (essais `mesa_irqwatch`, 2026-11-10) : ligne active haute signalant qu'une réponse
est en attente.

- Capteur éteint : 0 ; après allumage et après réveil : 1.
- Après une lecture d'état (`0x10`) : retombe à 0 (la lecture acquitte).
- Remonte à 1 **à chaque nouvelle réponse en attente** (par exemple après une demande
  d'identité `0x70`), pas seulement au démarrage.
- Si l'état n'est pas lu, elle reste à 1.

Conséquence : le transport peut être rendu **réactif** (attendre la montée plutôt qu'une pause
fixe). C'est implémenté par scrutation bornée dans le pilote ([chapitre 8](08-outillage.md)).
Un pilotage par interruption matérielle est possible mais reporté (risque de rafale bloquante
à distance).

## Session chiffrée et rôle de l'AP

Après l'identité, le capteur et le SEP établissent une **session chiffrée de bout en bout**.
Les commandes `sbio` qui la préparent sont connues par lecture de kext (`source: kext`,
`docs/messages.md` § SBIO) : échange de clé (`performKeyExchange`), compteur de séquence,
chargement d'un correctif (`loadPatch`), paramètres capteur, numéro de série. Chaque commande
`sbio` déclenche sur le bus une trame chiffrée correspondante (ex. `0x72`, `0x73`, `0x60` + bloc,
`0x55`). **L'AP ne fait que relayer** ces trames ; il ne peut pas les fabriquer ni les
interpréter (**Hypothèse** pour tout sauf l'image, voir ci-dessous). Sans la session établie
par le SEP, le logiciel interne du capteur n'est pas chargé : **Vérifié** qu'un doigt posé ne
change alors ni l'état ni la broche 195 (essai DOIGT-LINUX, 2 essais déclarés par Albert).

## L'image du doigt : relayée au SEP, octet pour octet

Lors d'une pose, le capteur produit une image de **0x7200 octets**, lue par l'AP sur le bus
(chiffrée). L'AP la transmet au SEP via l'endpoint `sbio` (0x08), en charge OOL de **type 0x65**.

**Vérifié (octet pour octet, C20, `analysis/cmp_sensor_sep_image.py`)** : sept images complètes
lues sur le bus sont **identiques** à la concaténation de deux buffers OOL (chacun un morceau de
0x4000 précédé de l'en-tête `gt_packet` de 0x1c octets, [chapitre 2](02-architecture.md)). L'en-tête
décode proprement : taille totale 0x7200, offset du morceau (0, puis 0x3fe4), type 0x65,
taille du morceau (0x3fe4 puis 0x321c ; somme = 0x7200). L'AP relaie donc l'image **sans la
transformer**.

**Vérifié (chiffrement de bout en bout)** : deux images d'un même doigt ne partagent **aucune**
séquence de 32 octets. Le contenu est chiffré entre capteur et SEP ; l'AP ne voit que du chiffré.

**Vérifié (comptage, C20, `analysis/count_sensor_vs_sep_images.py`)** : sur une session,
**27 images** sont lues sur le bus mais **7 seulement** sont transmises au SEP (14 morceaux de
type 0x65), alignées sur les poses de doigt. **Hypothèse** sur les 20 autres : trames de
prévisualisation/qualité non retenues pour la comparaison.

## Portée pour Linux

Linux peut piloter le capteur en clair (identité, état, broche prête) — **acquis**. Mais la
comparaison d'empreinte exige la session chiffrée établie par le SEP, et l'image ne sort jamais
en clair. Une comparaison « côté hôte » est donc exclue ; la seule voie vers Touch ID passe par
l'activation de `sbio` dans le SEP ([chapitre 5](05-xart.md)).
