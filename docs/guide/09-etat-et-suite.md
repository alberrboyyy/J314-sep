# État et suite

Ce chapitre résume où en est le projet et ce qui reste pour faire fonctionner Touch ID sous Linux. Chaque point est détaillé dans son chapitre, vers lequel on renvoie. Deux acteurs reviennent partout : l'AP, le processeur principal qui exécute macOS ou Linux, et le SEP, le coprocesseur de sécurité, qui dialoguent par une boîte aux lettres matérielle.

## Ce qui est acquis

- Le dialogue entre l'AP et le SEP est compris et observé en lecture seule : format des messages, traduction d'adresses, zones de mémoire partagée. Voir [Architecture AP ↔ SEP](02-architecture.md).
- Le SEP démarre depuis m1n1 seul, sans macOS, et annonce sept de ses douze endpoints, les services qu'il expose ; sa mémoire morte répond aux premiers messages. Voir [Démarrage du SEP](03-boot-sep.md).
- Le capteur d'empreinte est piloté depuis Linux : on l'alimente, on dialogue avec lui en clair, on lit son identité qui est la même que sous macOS, on lit son état, et on attend sa broche « donnée prête » au lieu d'une pause fixe. Voir [Le capteur Mesa](06-capteur-mesa.md).
- L'image du doigt est relayée au SEP octet pour octet et reste chiffrée de bout en bout entre le capteur et le SEP ; pendant une session, 27 images ont été lues sur le bus du capteur et 7 seulement transmises au SEP. Voir [Le capteur Mesa](06-capteur-mesa.md).
- Le coffre xART est compris. xART est le mécanisme d'anti-rejeu par lequel le SEP, qui n'a pas de stockage, confie des lockers, des blocs chiffrés, à l'AP ; le coffre est l'ensemble de ces lockers. Son contenu a été capturé sur trois démarrages : dix des douze lockers rendus au SEP sont identiques d'un démarrage à l'autre, les deux qui changent sont identifiés, et le fait que le SEP se fait rendre ce qu'il a sauvé la fois précédente est confirmé octet pour octet. Voir [Le coffre xART](05-xart.md).
- L'outillage est complet et réutilisable : traceur, capture, démarrage du SEP, dialogue avec le capteur depuis Linux, rejeu hors ligne des captures. Voir [Outillage](08-outillage.md).

## Le blocage, réduit à une question

L'endpoint biométrique `sbio`, celui de Touch ID, n'apparaît qu'au cours de l'échange xART ; démarré par m1n1 seul, sans cet échange, le SEP ne l'annonce pas. Ce coffre est en grande partie figé d'un démarrage à l'autre, ce qui rend plausible de le rejouer à l'identique pour obtenir le même résultat. Reste une seule question : l'anti-rejeu du SEP accepte-t-il un rejeu fidèle du dernier état, ou vérifie-t-il un secret que la lecture ne montre pas ? Elle ne se tranche que par un essai qui écrit vers le SEP. Voir [Le coffre xART](05-xart.md).

## Prochaines étapes

1. L'essai de rejeu : rendre au SEP, démarré par m1n1, ses derniers lockers sauvés, et observer s'il annonce alors `sbio`. C'est une écriture vers le SEP, donc une opération risquée, à mener avec les précautions réunies dans [Règles et risques](10-regles-et-risques.md).
2. Selon le résultat : soit `sbio` apparaît et le Touch ID devient atteignable sous Linux, le SEP faisant lui-même la comparaison d'empreinte ; soit le coffre refuse le rejeu, et cette voie est close.

## Une piste voisine, hors SEP

On attend parfois d'un portable qu'il se vide peu en veille. Cette autonomie dépend du sommeil profond, une affaire de gestion d'alimentation du noyau, et non du SEP. L'endpoint `hibe`, dédié à l'hibernation, n'est pas derrière le coffre xART, mais n'a montré aucune activité dans les captures : son protocole est inconnu.

## À retenir

- « Linux parle au capteur » est un résultat atteint ; le Touch ID complet, lui, dépend encore d'un seul essai.
- Le coffre xART est compris et en grande partie figé, ce qui rend le rejeu plausible.
- Le pas décisif est une écriture vers le SEP, risquée, qui donnera une réponse nette : oui ou non.

## Questions ouvertes

- L'anti-rejeu xART cache-t-il un secret qui ferait échouer un rejeu fidèle ? Seul l'essai en écriture le dira.
- Le SEP refuse-t-il une comparaison d'empreinte tant que le mot de passe de l'utilisateur n'a pas été saisi ? Voir [SKS / keystore](07-sks-keystore.md).
- Le démarrage du SEP par m1n1 a été suivi une fois d'une reconnexion au compte Apple, de cause non établie. Voir [Démarrage du SEP](03-boot-sep.md).
- Quelques points de détail du protocole et du matériel du capteur restent inexpliqués. Voir [SKS / keystore](07-sks-keystore.md) et [Le capteur Mesa](06-capteur-mesa.md).
