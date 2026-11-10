# 2. Architecture AP ↔ SEP

L'AP et le SEP communiquent par une **mailbox** matérielle (contrôleur de type ASC : deux
boîtes INBOX pour AP → SEP, deux boîtes OUTBOX pour SEP → AP). Chaque message est un mot de
64 bits ; les charges volumineuses passent par des buffers en mémoire (OOL), dont l'adresse
est traduite par une IOMMU (DART). Source : doc Asahi, code public m1n1 (`hw/sep.py`), et nos traces.

## Format d'un message (mot mailbox)

Découpage du mot de 64 bits (**Hypothèse cohérente**, contrôlée sans exception, voir
`docs/messages.md` § « Contrôles de cohérence ») :

| Bits | Champ | Rôle |
|------|-------|------|
| 0–7   | endpoint | service destinataire/émetteur (voir [chapitre 4](04-endpoints.md)) |
| 8–15  | tag | corrélation requête/réponse (ou index de pool) |
| 16–23 | type | opération |
| 24–31 | param | paramètre d'opération |
| 32–63 | data | valeur 32 bits (souvent une taille, un compteur, ou une IOVA ≫ 12) |

Notation employée partout : `> EP=0x.. TAG=.. TYPE=.. PARAM=.. DATA=..` pour AP → SEP, et
`<` pour SEP → AP. Le noyau macOS numérote les endpoints en décimal (ex. « EP: 19 » = 0x13).

## Mailbox et modes de trace

L'observation se fait sous l'hyperviseur m1n1 : les accès aux registres INBOX/OUTBOX sont
interceptés et journalisés. Le traceur peut fonctionner en mode asynchrone (défaut) ou
synchrone ; la lecture du contenu des buffers OOL impose le mode synchrone ([chapitre 8](08-outillage.md)).

## DART (IOMMU du SEP)

Les buffers partagés sont désignés par des adresses virtuelles d'E/S (IOVA), traduites en
adresses physiques par le DART `/arm-io/dart-sep`. Le traceur refait cette traduction en
**lecture seule** (registres TCR/TTBR, descripteurs L1/L2), avec vérification que chaque
adresse physique tombe dans la RAM avant lecture. Compatibles gérés : `dart,t8020` et
`dart,t6000`. **Vérifié (lecture)** : traductions contrôlées contre la RAM, aucune écriture
(ni SEP, ni DART, ni mémoire invité). Détail : `docs/messages.md`, en-tête de `hv/trace_sep_filtered.py`.

## Buffers hors-ligne (OOL) et configuration CNTL

Chaque endpoint dispose de **deux buffers OOL** (notés A et B). Ils sont configurés au boot
par l'endpoint de contrôle `cntl` (0x00), via quatre messages `>` par endpoint :

- `TYPE 0x04 PARAM=ep DATA=taille` — taille du buffer A.
- `TYPE 0x02 PARAM=ep DATA=IOVA≫12` — adresse du buffer A.
- `TYPE 0x05` / `TYPE 0x03` — taille et adresse du buffer B.
- Chaque message est acquitté par `< TYPE 0x01` renvoyant la DATA reçue.

**Vérifié (invariant)** : les buffers sont alloués consécutivement en pages de 4 Kio avec un
écart constant, sur les neuf endpoints concernés et sans exception (formule dans
`docs/messages.md` § CNTL). **Hypothèse** : A = sens AP → SEP, B = sens SEP → AP (cohérent
avec les traces, non vérifié sur les adresses ; voir `docs/verification_status.md` ligne A/B).

## En-tête OOL (`gt_packet`, 0x1c octets)

Les transferts applicatifs (ex. endpoint `sbio`) sont encadrés par un en-tête de 0x1c octets
en tête de buffer, puis la charge. Champs (`source: kext`, confirmés sur nos captures ;
**Vérifié (lecture)**, voir `docs/messages.md` § SBIO et `docs/verification_status.md`) :

| Offset | Champ |
|--------|-------|
| +0x00 | version = 1 |
| +0x04 | taille totale du transfert |
| +0x08 | offset du morceau courant |
| +0x0c | champ recopié du contexte (probable « flags », lecture incertaine) |
| +0x10 | 0 |
| +0x14 | commande (= type) |
| +0x18 | taille du morceau = min(reste, taille buffer − 0x1c) |
| +0x1c | charge |

Un transfert plus grand qu'un buffer est fragmenté en plusieurs morceaux, chacun précédé de
cet en-tête. Ce mécanisme explique la reconstitution de l'image capteur ([chapitre 6](06-capteur-mesa.md)).
