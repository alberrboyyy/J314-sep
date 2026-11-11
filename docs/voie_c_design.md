# Essai de rejeu xART (voie C) — plan et analyse de sûreté

État : **plan seulement**. Aucun script exécutable n'est écrit. Toute écriture vers le SEP reste un script `pending/`
relu et lancé par Albert, jamais par un agent, et seulement après validation de ce plan. Ce document existe pour décider
en connaissance de cause.

## But

Déterminer si un SEP démarré par m1n1, et non par macOS, accepte qu'on lui **rejoue** ses derniers lockers xART et, en
conséquence, annonce l'endpoint biométrique `sbio` et les quatre autres endpoints absents. C'est le seul pas qui tranche la
question ouverte du chapitre « Le coffre xART » : l'anti-rejeu accepte-t-il un rejeu fidèle de l'état courant ?

Si oui : le SEP passe de 7 à 12 endpoints sous Linux, et `sbio` devient adressable — prérequis de tout Touch ID sous Linux,
le SEP faisant lui-même la comparaison d'empreinte. Si non : on aura la réponse, et la voie C est close.

## Ce qu'on a déjà

- **Le démarrage du SEP par m1n1** (`pending/sep_boot.sh`, déjà lancé une fois = SEP-BOOT) : atteint 7/12 endpoints, avec
  un message resté en attente sur l'EP 0x13 = la demande xART du SEP.
- **Le contenu complet de l'échange xART** capturé sur 3 boots macOS (c21/c23/c24) : les lockers rendus par l'AP et ceux que
  le SEP fait sauver, avec le chaînage prouvé octet pour octet `save(N) = fetch(N+1)`.
- **La structure du dialogue** sur l'EP 0x13 : séquence des fetch et des save, étiquettes de 16 octets des lockers.

## L'idée, et pourquoi elle pourrait marcher

Le SEP est le **même composant physique** quel que soit le système qui le démarre ; son état secret interne persiste d'un
démarrage à l'autre et n'avance que lorsqu'il fait sauver de nouveaux lockers. Donc :

1. On capture un démarrage macOS. On en retient les **derniers lockers que le SEP a fait sauver** pendant ce démarrage,
   soit `S_new`. À ce moment, le compteur interne du SEP correspond à `S_new`.
2. **Sans redémarrer macOS**, on démarre le SEP par m1n1. Son état interne est toujours à `S_new`.
3. Quand le SEP réclame ses lockers sur l'EP 0x13, Linux lui rend `S_new` : exactement ce qu'il attend au démarrage suivant,
   puisque `save(N) = fetch(N+1)`. S'il n'y a pas d'autre vérification que celle-là, il accepte et annonce `sbio`.

La condition clé est l'étape 2 : **aucun démarrage de macOS entre la capture et l'essai**, sinon macOS fait sauver de
nouveaux lockers, le compteur avance, et `S_new` devient périmé.

## Étapes de l'essai

1. Capture macOS en lecture seule, comme c21/c24, pour obtenir `S_new` : les lockers sauvés et les lockers statiques.
   Reconstituer l'ensemble exact que l'AP devrait rendre au démarrage suivant.
2. Préparer un composant côté PC qui, pendant un démarrage du SEP par m1n1, répond sur l'EP 0x13 : il place le bon locker
   dans le buffer OOL et renvoie le message attendu, pour chaque fetch, dans l'ordre observé.
3. Lancer le démarrage du SEP par m1n1 avec ce composant actif. Observer, en lecture, si le SEP passe de 7 à 12 endpoints
   et annonce `sbio`.
4. Quel que soit le résultat, ne rien envoyer de plus ; couper, redémarrer le Mac.

Il manque, à préciser avant d'écrire le script : la **liste exacte et l'ordre** des lockers à rendre, l'**origine des
étiquettes** que le SEP passe en mémoire partagée, et la façon de placer les buffers OOL aux bonnes adresses côté m1n1.

## Analyse de sûreté

Les deux règles d'Albert : ne pas bricker, ne pas toucher la partition Linux. macOS est sacrifiable.

- **Partition Linux : aucun contact.** L'essai ne parle qu'au SEP par la mailbox, via m1n1. Il n'ouvre, ne monte, n'écrit
  aucun disque. Le script devra être relu pour garantir qu'il ne contient aucune opération disque.
- **Brick : risque faible mais non nul, à énoncer franchement.** Les messages envoyés sont de la même nature que ceux de
  SEP-BOOT, qui a démarré le SEP sans incident matériel, plus des réponses sur un endpoint déjà prévu par le SEP. Un SEP mis
  dans un état incohérent est réinitialisé au redémarrage ; m1n1 garde la main. Rien dans ce qu'on sait ne peut rendre le Mac
  non démarrable de façon permanente, mais on n'a pas de preuve formelle, donc on classe l'essai comme risqué par prudence.
- **macOS : effet de bord possible, accepté.** Le seul démarrage du SEP par m1n1 a déjà été suivi d'une reconnexion au
  compte Apple, de cause non établie. Un rejeu qui touche à l'état xART peut désynchroniser FileVault ou le trousseau. Albert
  accepte de perdre macOS ; la seule exigence est que cela ne déborde ni sur Linux ni sur la capacité à démarrer la machine.

## Inconnues et risques ouverts

- On ne sait pas si le SEP vérifie **plus** que la correspondance `save(N) = fetch(N+1)` : une attestation liée au système
  qui le démarre, un état de politique de boot, un secret que seul macOS présente. Si oui, le rejeu échoue même fidèle.
- On ne sait pas si les lockers passés en mémoire partagée suffisent, ni si des échanges sur d'autres endpoints 0x10 ou
  0x15 sont requis avant que `sbio` apparaisse.
- L'effet de bord macOS n'est pas compris ; on ne peut pas le borner à l'avance.

## Décision

Ce plan ne s'exécute pas tant que : Albert l'a relu et validé ; un script `pending/` a été écrit avec son en-tête but,
risque, résultat attendu, et relu pour la garantie « aucune opération disque » ; et Albert le lance lui-même. L'étape 1,
la capture en lecture seule de `S_new`, est sans risque et peut se faire quand le Mac est en mode câble.
