# Le coffre xART

Le SEP, le coprocesseur de sécurité de la puce, n'a pas de stockage persistant à lui. Il confie des lockers, des blocs de données chiffrés, à l'AP, le côté qui exécute le système d'exploitation, macOS ou Linux ; l'AP les range sur le disque et les lui rend au démarrage suivant. Ce mécanisme s'appelle xART. L'ensemble de ces lockers forme ce qu'on appellera ici le coffre. Il compte pour Touch ID sous Linux parce que l'endpoint biométrique `sbio` n'est annoncé qu'au cours de cet échange.

## Pourquoi xART bloque la biométrie

xART est un mécanisme d'anti-rejeu : il garantit que le SEP reçoit au démarrage la **dernière** version sauvée de ses lockers, et non une version plus ancienne qu'on lui rejouerait. L'endpoint `xars`, numéro 0x10, met le mécanisme en place ; l'endpoint `xarm`, numéro 0x13, assure les restitutions et les sauvegardes.

Le SEP n'annonce `sbio` qu'une fois cet échange engagé. Démarré depuis m1n1 seul, dans le montage [S2](annexe-sources.md#s2) où aucun système ne tient le rôle de l'AP, le SEP s'arrête à sept des douze endpoints et `sbio` est absent. Le détail de cette vague d'endpoints est dans [Démarrage du SEP](03-boot-sep.md).

> **Hypothèse** — C'est bien l'absence d'échange xART qui prive le SEP des cinq endpoints restants. Ce qui la soutient : sur les 19 démarrages de macOS observés, série [T-G1](annexe-sources.md#t-g1), ces cinq endpoints apparaissent toujours au cours de l'échange xART, jamais avant. Ce qui la trancherait : tenir le rôle de l'AP depuis Linux et voir `sbio` apparaître.

## L'échange au démarrage

Sur les 19 démarrages de macOS observés dans le montage [S1](annexe-sources.md#s1), macOS tournant comme invité de l'hyperviseur, l'échange a la même forme. L'endpoint `xarm` s'annonce, émet un premier message, puis attend l'AP de 2,8 à 3,8 s. L'AP répond, le SEP demande, et l'AP restitue d'abord le locker que le journal du noyau de macOS nomme SEP-xART, puis celui qu'il nomme USER-xART, puis une série d'autres lockers. Au fil de l'échange, le SEP fait aussi sauver de nouveaux lockers, dont l'AP accuse réception. C'est au cours de cet échange que les endpoints encore absents, dont `sbio`, sont annoncés, dans un ordre et à un moment décrits dans [Démarrage du SEP](03-boot-sep.md).

```mermaid
sequenceDiagram
    participant AP
    participant SEP
    SEP->>AP: xarm s'annonce, puis émet un premier message
    Note over AP,SEP: le SEP attend de 2,8 à 3,8 s
    AP->>SEP: réponse
    SEP->>AP: demande le locker SEP-xART
    AP->>SEP: restitue le locker SEP-xART
    SEP->>AP: demande le locker USER-xART
    AP->>SEP: restitue le locker USER-xART
    Note over AP,SEP: d'autres lockers sont ensuite restitués, et de nouveaux sauvés
```

Que l'AP rende bien au SEP ce qu'il lui a fait sauver se vérifie d'un démarrage au suivant, pour les deux lockers nommés SEP-xART et USER-xART. Le journal du noyau consigne pour chacun une somme de contrôle, un nombre court qui résume son contenu. Dans la série [T-G1](annexe-sources.md#t-g1), chaque fois que deux démarrages se suivent et que le locker est présent dans les deux, la somme de contrôle du locker restitué au second est celle du dernier locker de même nom sauvé au premier. Cela se vérifie sans exception sur les 15 paires de démarrages consécutifs où SEP-xART est présent et sur les 16 où USER-xART l'est. C'est le comportement attendu d'un stockage délégué. Cette correspondance porte sur la somme de contrôle, pas sur le contenu lui-même, qui n'a été lu que lors des démarrages décrits plus bas.

## Ce que contient le coffre

Le contenu des lockers a été lu lors de trois démarrages où les buffers OOL de `xarm` ont été capturés, [T-45](annexe-sources.md#t-45), [T-46](annexe-sources.md#t-46) et [T-47](annexe-sources.md#t-47). Un buffer OOL est une zone de mémoire partagée par laquelle passent les données trop grandes pour un message de la mailbox. Chaque locker voyage dans un buffer OOL de 0x8000 octets et n'en occupe qu'une partie. La plupart des lockers sont accompagnés d'une étiquette de 16 octets, transmise à part et en clair, qui dit lequel le SEP réclame ; SEP-xART fait exception, c'est un bloc nommé sans étiquette. Le corps d'un locker est chiffré : on n'y lit aucune information. On peut en revanche comparer ses octets d'un démarrage à l'autre, et c'est ce qui suit ; tout compteur d'anti-rejeu reste scellé dans ce corps chiffré, illisible.

En comparant les trois démarrages, on voit quelle part du coffre est figée et quelle part change :

| Lockers | Rôle | Observé sur les trois démarrages comparés |
|---|---|---|
| restitués au SEP | ce que l'AP rend au SEP au démarrage | 12 lockers, dont 10 identiques octet pour octet sur les trois démarrages et 2 différents |
| sauvés par le SEP | ce que le SEP confie à l'AP pour la fois suivante | 5 lockers, tous différents |

La plus grande part de ce que l'AP rend au SEP est donc **statique** : l'AP la stocke et la restitue telle quelle. Ce qui change d'un démarrage à l'autre se limite à deux lockers restitués, et à tout ce que le SEP fait sauver, qu'il régénère à chaque session.

Les deux lockers qui changent sont SEP-xART et un second locker que les journaux de macOS rattachent à la gestion des identifiants. Le locker USER-xART, lui, ne change pas sur les trois démarrages. Chaque locker garde son identité d'un démarrage à l'autre, par son étiquette quand il en a une ou par sa place dans l'échange : c'est bien le même locker dont le corps est renouvelé, non un locker différent. Et sur ces trois démarrages, ce que le SEP a fait sauver à un démarrage est, octet pour octet, ce que l'AP lui rend au démarrage suivant, au préfixe d'étiquette près : ce lien d'un démarrage au suivant est donc confirmé sur le contenu, et plus seulement sur la somme de contrôle.

> **Hypothèse** — Ce qui empêche de rejouer un vieil état est de nature cryptographique, porté par les octets chiffrés qui changent d'une sauvegarde à l'autre, et non par un compteur en clair. Ce qui la soutient : dans les parties qui changent, aucun octet ne s'incrémente ni ne se répète de façon lisible. Ce qui la trancherait : ces octets sont chiffrés, donc seul un essai qui rend ces lockers au SEP montrerait ce qu'il vérifie.

## Rejouer n'est pas forger

Deux approches sont possibles pour tenir le rôle de l'AP depuis Linux, à ne pas confondre.

- **Forger** un locker, c'est fabriquer un état inventé. Cela exige la clé interne du SEP, que le projet s'interdit de chercher. C'est impossible.
- **Rejouer** les lockers, c'est rendre au SEP ceux qu'il a lui-même fait sauver. Cela ne demande pas de les comprendre : il suffit de les stocker et de les rendre, comme le fait l'AP de macOS. Le SEP n'a pas de disque et dépend de ce service ; rien n'interdit en principe que Linux le tienne.

Si un rejeu aboutit, le SEP annonce `sbio` et effectue lui-même la comparaison d'empreinte ; le projet n'a jamais besoin de sa clé. Le Touch ID sous Linux n'est donc pas exclu par conception. Il dépend de la question suivante.

## La question qui tranche

L'anti-rejeu accepte-t-il un rejeu fidèle de l'état courant, c'est-à-dire le dernier état sauvé rendu inchangé, ou vérifie-t-il un compteur renouvelé à chaque démarrage qu'un rejeu fidèle ne saurait satisfaire ? Le compteur, s'il existe, est scellé dans le locker chiffré et ne se lit pas ; l'échange ne montre aucun compteur en clair. Seule une tentative qui rend réellement les lockers au SEP peut trancher, et une telle tentative écrit vers le SEP.

> **Hypothèse** — Un rejeu fidèle a des chances d'aboutir. Ce qui la soutient : sur les trois démarrages comparés, la plus grande part du coffre est identique, et ce qui change d'un démarrage à l'autre se limite à deux lockers restitués. Ce qui la trancherait : rendre à un SEP démarré depuis m1n1 les dernières versions sauvées de ces deux lockers et observer si `sbio` apparaît.

> ⚠️ **Rendre des lockers au SEP modifie son état et celui de macOS.** Cet essai écrit vers le SEP, ce qui sort de l'observation en lecture seule de tous les autres résultats du projet. De plus, les deux lockers qui changent deviennent périmés dès que macOS redémarre et les réécrit, si bien qu'un essai doit utiliser des lockers capturés juste avant, sans démarrage de macOS entre-temps. Les risques et les précautions sont réunis dans [Règles et risques](10-regles-et-risques.md).

## À retenir

- Le SEP n'annonce la biométrie qu'au cours de l'échange où l'AP lui rend ses lockers ; sans ce service, pas de `sbio`, donc pas de Touch ID sous Linux.
- Le contenu des lockers est chiffré ; le projet n'a pas besoin de le lire, seulement de le stocker et de le rendre.
- Sur les trois démarrages comparés, 10 des 12 lockers rendus au SEP sont identiques : la plus grande part du coffre est statique et rejouable.
- Forger un locker est impossible sans la clé interne du SEP ; rejouer les lockers sauvés ne demande pas cette clé.
- Reste une seule inconnue décisive : l'anti-rejeu accepte-t-il un rejeu fidèle de l'état courant ? Elle ne se tranche que par un essai qui écrit vers le SEP.

## Questions ouvertes

- Y a-t-il un compteur d'anti-rejeu renouvelé à chaque démarrage ? Le début de chaque sauvegarde en est le candidat, mais il est chiffré et illisible ; seul un essai en écriture dirait ce que le SEP vérifie.
- Le second locker qui change relève de la gestion des identifiants de macOS. Son rôle dans un déverrouillage biométrique sous Linux, et s'il faut le rejouer au même titre que SEP-xART, ne sont pas établis.
