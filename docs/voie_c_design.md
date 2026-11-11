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

## Annexe technique — séquence de rejeu et buffers (lecture seule, c24)

Extrait du `sep.log` de T-47 (c24). Donne les morceaux qui manquaient au plan : les adresses des buffers OOL de
`xarm` et la suite exacte des réponses que l'AP doit renvoyer. Rien n'est envoyé ; c'est une lecture de trace.

**Buffers OOL de l'EP 0x13, appris par le CNTL au boot** :
- buffer A, sens AP→SEP = là où l'AP écrit le locker rendu : IOVA `0x2c000`, taille `0x8000`.
- buffer B, sens SEP→AP = là où le SEP écrit ce qu'il fait sauver : IOVA `0x38000`, taille `0x8000`.
- Ces IOVA sont ceux d'une session macOS. Sous un démarrage du SEP par m1n1, le SEP refait ses propres CNTL ; le script
  doit apprendre les IOVA à la volée, exactement comme le traceur le fait avec `SEP_OOL_EPS`, et non les coder en dur.

**Suite des réponses de l'AP à rejouer** (chaque `>` est une réponse à la requête `<` du SEP qui la précède) :
- TAG 0x02, TYPE 0x00, PARAM 0x00, DATA 0x00000100 — réponse à la première requête.
- TAG 0x01, TYPE 0x00, PARAM 0x00, DATA 0x00000000.
- TAG 0x03, TYPE 0x00, PARAM 0x64, DATA 0x00000103 — **fetch SEP-xART** : placer le locker SEP-xART dans le buffer A.
- TAG 0x04, TYPE 0x00, PARAM 0x14, DATA 0x00000008 — **fetch USER-xART** : placer le locker USER-xART dans le buffer A.
- Puis les acquittements TAG 0x00 TYPE 0x16 des cinq annonces d'endpoints `0x1d`, et la série de fetch TAG 0x05 à 0x0f et
  au-delà, chacun plaçant le locker demandé dans le buffer A avec le PARAM/DATA de réponse observé.

**Ce que le script doit faire, à chaque requête du SEP** : reconnaître le TAG, écrire dans le buffer A les octets du locker
correspondant capturé juste avant, puis renvoyer le mot de réponse `>` observé. L'identité du locker demandé est l'étiquette
de 16 octets que le SEP passe dans le buffer B avant un fetch ; le script l'y lit pour choisir le bon locker.

**Reste à établir avant d'écrire le script** : l'ordre complet au-delà de TAG 0x0f, et la correspondance exacte étiquette →
locker pour chaque fetch. Tout cela se lit dans les captures, sans rien envoyer.

## Table de rejeu de la phase de boot (lecture seule, c24)

Les dix lockers que l'AP rend au SEP pendant la phase de boot, dans l'ordre, avec le TAG de la requête, l'en-tête de
réponse à renvoyer, la taille utile et l'étiquette de 16 octets que le SEP passe dans le buffer B juste avant le fetch.
Les deux premiers sont des blocs nommés sans étiquette ; les suivants sont désignés par étiquette.

| Ordre | TAG | réponse PARAM / DATA | taille utile | étiquette de 16 octets réclamée | locker |
|---|---|---|---|---|---|
| 1 | 0x03 | 0x64 / 0x00000103 | 843  | aucune | SEP-xART |
| 2 | 0x04 | 0x14 / 0x00000008 | 2043 | aucune | USER-xART |
| 3 | 0x05 | 0x0c / 0x0000010c | 3073 | 407e94c4f60495b3f2fbf5a8a31ae719 | |
| 4 | 0x07 | 0xb6 / 0x00000100 | 3075 | e01e3b5e2c38f5960968a4d52ae2b22b | |
| 5 | 0x0a | 0x01 / 0x00000102 | 3072 | 2438821b3dc0faf876d7aad6ca4dc668 | |
| 6 | 0x0c | 0x28 / 0x00000100 | 3072 | 9133c5d52d8f276460f2ff4851d26065 | |
| 7 | 0x0e | 0x7c / 0x00000000 | 3074 | f86488fdcf52da496934d4ec1d6b35dd | |
| 8 | 0x10 | 0x53 / 0x00000101 | 3074 | 8624497a8c2ff2582625a036fab3b8e3 | Credential Manager |
| 9 | 0x16 | 0x14 / 0x00000120 | 8182 | 8624497a8c2ff2582625a036fab3b8e3 | Credential Manager |
| 10 | 0x18 | 0xb2 / 0x00000000 | 8183 | 8624497a8c2ff2582625a036fab3b8e3 | Credential Manager |

Entre les lockers 2 et 3, le SEP annonce `sbio` puis `skdl`, `sse`, `sks`, `scrd` (requêtes TYPE 0x1d) que l'AP acquitte par
une réponse TYPE 0x16 reprenant les deux premiers caractères du nom. L'étiquette `8624497a…` est réclamée trois fois : c'est
le locker Credential Manager, lu sous trois tailles. Les lockers 1, 2 et 8 sont les trois qui changent d'un boot à l'autre ;
les sept autres sont figés (voir le chapitre « Le coffre xART » du guide).

**Ce que le script de rejeu fait, par locker** : à la requête du SEP, lire l'étiquette dans le buffer B, choisir le locker
capturé correspondant, écrire ses octets dans le buffer A, renvoyer le mot de réponse de la colonne PARAM/DATA. Pour les
lockers 1 et 2, sans étiquette, se repérer par l'ordre et le TAG. Les IOVA des buffers A et B sont relus à la volée au
démarrage du SEP par m1n1, jamais codés en dur. Reste la seule inconnue de fond : l'anti-rejeu accepte-t-il ce rejeu fidèle.

## Faisabilité technique confirmée (lecture de code public, rien lancé)

Les primitives nécessaires au script de rejeu existent déjà dans l'outillage, donc le script est implémentable :

- Écrire un locker dans le buffer A du SEP : on traduit l'IOVA du buffer en adresse physique par le DART, exactement
  comme le traceur le fait en lecture, puis on écrit les octets avec la commande d'écriture mémoire du proxy m1n1. La
  traduction lecture seule est déjà codée et vérifiée dans le traceur ; l'écriture mémoire est une primitive du proxy.
- Démarrer le SEP et lui envoyer des messages sur la mailbox : `pending/sep_boot.sh` le fait déjà pour la séquence de boot.
- Lire l'étiquette dans le buffer B avant chaque fetch : même traduction lecture seule que ci-dessus.

Le traceur, lui, s'interdit toute écriture mémoire par principe ; le script de rejeu fait l'inverse, et c'est précisément
pour cela qu'il est une écriture vers le SEP, à mettre dans `pending/` et à lancer par Albert, jamais par un agent.

Il ne reste donc, avant un essai, que : écrire ce script avec soin et le faire relire ; capturer l'état `S_new` juste avant
sans redémarrer macOS entre-temps. La seule inconnue de fond demeure : l'anti-rejeu du SEP accepte-t-il ce rejeu fidèle.
