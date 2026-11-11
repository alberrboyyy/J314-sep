# Guide de style — `docs/guide/`

Ce fichier s'impose à toute personne et à tout agent qui écrit dans `docs/guide/`. Il ne
fait pas partie du guide lui-même : c'est la règle du jeu.

## 1. Le lecteur

On écrit pour **un développeur Linux compétent, qui connaît un peu l'ARM, mais qui ne
connaît ni le SEP, ni m1n1, ni rien de ce projet**. Il n'était pas là pendant les
expériences, n'a pas lu le journal et ne le lira pas.

Le guide est une documentation communautaire **privée**. On vise le sérieux et la clarté de
la documentation Asahi Linux, sans jamais se présenter comme venant d'Asahi ni laisser
entendre que le projet y est lié.

Test à appliquer à chaque phrase : *ce lecteur peut-il la comprendre avec les seuls fichiers
de `docs/guide/` ?* Si non, il manque une définition, une référence ou un « pourquoi ».

## 2. La voix

- Neutre, ou « on ». Présent de l'indicatif.
- Aucune mention d'Albert, de l'agent, de Claude, d'un rôle interne comme analyste, sceptique
  ou traceur, ni du modèle utilisé.
- Pas d'historique de travail. « On a d'abord cru que… » n'a sa place que si l'erreur aide à
  comprendre le sujet : un piège dans lequel le lecteur tomberait aussi.
- Pas de consigne. Le guide décrit ce qui est et ce qui est risqué ; il ne dit pas qui a le
  droit de lancer quoi. Les règles de fonctionnement du projet vivent dans `CLAUDE.md`.
- Phrases complètes. Pas de style télégraphique, pas de flèche `→` en guise de verbe.
- **Pas de parenthèses.** Ni pour définir un terme, ni pour citer une trace, ni pour glisser
  une précision. Une définition se met en apposition ou dans sa propre phrase ; une
  référence s'intègre à la phrase ; une précision qui compte mérite une phrase, et celle qui
  ne compte pas s'enlève. Une parenthèse isolée de loin en loin est tolérée, pas plus. Les
  parenthèses des liens Markdown ne sont évidemment pas concernées.
- Gras réservé au terme qu'on définit et à l'idée centrale d'un paragraphe : pas plus d'un
  ou deux par paragraphe.

## 3. Les termes

**Tout terme ou sigle est défini à sa première utilisation dans le chapitre ET figure dans
[glossaire.md](glossaire.md).**

- La définition dans le chapitre tient en une incise ou une phrase ; le glossaire donne la
  version de référence.
- Chaque chapitre se lit seul : un terme défini au chapitre 2 est redéfini brièvement au
  chapitre 5.
- On n'emploie qu'un seul mot par chose. Les mots retenus sont ceux du glossaire : par
  exemple « traceur » et non « tracer », « démarrage » ou « boot » mais pas les deux dans la
  même page pour la même chose.
- Un nouveau terme s'ajoute au glossaire **dans le même commit** que le chapitre qui
  l'introduit.

## 4. Ce qu'on sait, ce qu'on suppose, ce qu'on ignore

Par défaut, **tout ce qui est écrit dans le guide est vérifié** : confirmé par une expérience
dédiée et reproductible, ou par un invariant observé sans exception. On ne colle donc pas
d'étiquette « Vérifié » : c'est le régime normal.

Ce qui sort de ce régime est isolé visuellement :

- **Une hypothèse**, c'est-à-dire une interprétation cohérente mais sans expérience qui la
  tranche, va dans un encadré :

  ```markdown
  > **Hypothèse** — Les cinq endpoints absents ne sont annoncés qu'après l'échange xART.
  > Ce qui la soutient : … Ce qui la trancherait : …
  ```

- **Ce qui n'est pas compris** va dans la section « Questions ouvertes » en fin de chapitre,
  pas au fil du texte.

- **Une limite de portée** se dit en clair dans la phrase. Presque tout ce qui concerne le
  SEP a été observé sur macOS : cela établit *ce que macOS fait*, pas *ce que le SEP exige*.
  Écrire « macOS envoie toujours ces 57 commandes dans cet ordre », pas « le SEP exige ces
  57 commandes ».

Le statut d'une affirmation se prend dans `docs/verification_status.md`. Un point qui y est
marqué `hypothèse` ne devient pas un fait parce qu'il est bien écrit.

**Fidélité.** Réécrire n'est pas inventer. Aucun fait, aucun chiffre, aucune explication,
aucun « pourquoi » qui ne soit appuyé par les sources du dépôt. Quand il manque quelque
chose, on laisse un marqueur à l'endroit précis, et on continue :

```markdown
<!-- QUESTION ALBERT : pourquoi ce délai de 2,8 à 3,8 s compte-t-il pour un pilote ? -->
```

## 5. Les références

Le texte ne contient **jamais d'identifiant brut** : ni nom de dossier de trace comme
`20261109-212150_sep_getrand`, ni étiquette de travail comme `C1`, `K-E1`, `SPI-3` ou
`SEP-BOOT`, ni numéro de ligne de log.

- **Setups** : `S1`, `S2`… toujours liés, et nommés en clair à leur première occurrence dans
  le chapitre : « sous macOS observé par l'hyperviseur, montage décrit en [S1](annexe-sources.md#s1) ».
  La référence fait partie de la phrase : jamais « (S1) » ni « ([T-30]) » entre parenthèses.
- **Traces** : `[T-xx]`, toujours liées : `[T-30](annexe-sources.md#t-30)`.
- **Séries de traces** : `[T-G1]`… définies dans l'annexe, pour « les 19 démarrages » et
  autres ensembles cités souvent.
- **Autres chapitres** : par leur titre, `[Le coffre xART](05-xart.md)`, pas « chapitre 5 » :
  les numéros bougent.
- **Fichiers du dépôt**, outils et scripts : chemin en `code`, uniquement quand le lecteur peut
  vouloir l'ouvrir ou le lancer.
- **Notes de travail**, soit `docs/journal.md`, `docs/messages.md`, `docs/hypotheses.md` et
  les autres fichiers de `docs/` hors du guide : on
  n'y renvoie pas depuis le texte. C'est `annexe-sources.md` qui fait le lien entre le guide
  et les preuves brutes.

Toute trace ou tout setup cité doit exister dans [annexe-sources.md](annexe-sources.md). S'il
manque, on l'ajoute à l'annexe avant de le citer.

## 6. La structure d'un chapitre

```markdown
# Titre du chapitre

Introduction : deux ou trois phrases. De quoi on parle, et pourquoi ça compte pour faire
fonctionner Touch ID sous Asahi Linux.

## Sections de contenu
…

## À retenir
- trois à cinq puces : ce que le lecteur doit emporter.

## Questions ouvertes
- ce qu'on ne comprend pas, ce qui reste à trancher ; à défaut, « Aucune à ce jour. »
```

- Le titre de premier niveau **ne porte pas de numéro** : l'ordre est donné par le nom du
  fichier et par le plan de `README.md`.
- Chaque section commence par dire à quoi sert ce qu'elle décrit avant de le détailler. Un
  fait sans conséquence pour l'objectif n'a pas sa place dans le corps du chapitre.
- Un chapitre = un sujet. Si un contenu est traité ailleurs, on y renvoie en une phrase au
  lieu de le répéter.

## 7. Les formats

- **Tableaux** pour les messages, registres, endpoints, champs de structure, à la manière de
  la documentation Asahi. Une colonne « Rôle » ou « À quoi ça sert » est obligatoire.
- **Diagrammes de séquence Mermaid** pour tout échange de plus de deux messages :

  ````markdown
  ```mermaid
  sequenceDiagram
      participant AP
      participant SEP
      AP->>SEP: GET_STATUS, type 0x02 sur l'endpoint 0xFF
      SEP-->>AP: statut OK, type 0x66
  ```
  ````

- **Encadrés ⚠️** pour les risques sur le matériel, les données ou l'état de macOS :

  ```markdown
  > ⚠️ **Titre court à l'impératif ou à l'infinitif.** Ce qui s'est passé ou peut se
  > passer, ce qu'on sait de la cause, ce qu'on en conclut.
  ```

- **Notation des messages** : expliquée une fois dans
  [Architecture AP ↔ SEP](02-architecture.md) ; ailleurs, on écrit le message en mots,
  « l'AP envoie BOOT_TZ0, type 0x05, sur l'endpoint 0xFF », ou dans un tableau, pas en
  notation de log comme `> 0xFF TYPE 5`.
- **Nombres** : hexadécimal préfixé `0x` pour adresses, types, tailles de buffers ; décimal
  pour les comptages et les durées. Unités écrites : « 0x7200 octets », « 2,8 à 3,8 s ».
- **Comptages** : toujours avec leur dénominateur et ce qu'on compte : « dans les
  19 démarrages observés », pas « 19/19 ».

## 8. À ne jamais faire

Tous les exemples viennent de l'ancienne version du guide.

| À ne jamais faire | Exemple réel | Pourquoi |
|---|---|---|
| Parenthèses, quelles qu'elles soient | « Le SEP (Secure Enclave Processor, le coprocesseur de sécurité de la puce) ne rend… » ; « ([T-28]) » ; « (source : kext) » | Voir § 2 et § 11. |
| Citer une chose jamais définie | « observée sous macOS (C1) » ; « DART `t6000` » ; « IOVA ≫ 12 » ; « charge OOL » ; « SEP accepted Tz0 » | Le lecteur n'a ni la liste des captures ni le vocabulaire. |
| Identifiant brut de trace | « (trace `20261109-212150_sep_getrand`, 4 octets obtenus) » | Illisible ; on écrit `[T-28]` lié à l'annexe. |
| Étiquette de travail | « essai MESA-HELLO », « K-E1 », « SKS-1 », « SPI-1 », « voie B » sans la décrire | Ce sont des noms de carnet, pas des noms de choses. |
| Historique de travail | « Correction vérifiée : l'ordre n'est pas fixe » ; « trois ordres observés sur huit boots » donné comme une péripétie ; « Cela contredit une lecture antérieure » | Le lecteur veut l'état des connaissances, pas le chemin. |
| Consigne destinée à l'agent | « pas de nouveau boot du SEP par m1n1 sans décision explicite d'Albert » ; « lancé par Albert, pas par un agent » | Le guide décrit un risque ; il ne distribue pas des permissions. |
| Mention d'une personne ou d'un rôle interne | « 2 essais déclarés par Albert » ; « décision du sceptique » | Voir § 2. |
| Étiquette de statut sur chaque phrase | « **Vérifié (fait)** : … **Hypothèse** : … **Inexpliqué** » | Voir § 4 : vérifié par défaut, encadré pour l'hypothèse, section pour l'inconnu. |
| Fait sans « pourquoi » | « `GETRAND` renvoie 4 octets aléatoires de la ROM. » | En quoi cela rapproche-t-il de Touch ID ? Si on ne sait pas le dire, le fait n'a pas sa place, ou il manque une `QUESTION ALBERT`. |
| Mélanger les setups | « Observée sous macOS et reproduite sous m1n1 seul » sans avoir présenté ni l'un ni l'autre | On nomme le setup `S1`, `S2`… et on le lie. |
| Renvoi vers les notes de travail | « voir `docs/messages.md` § Boot ROM » ; « `docs/verification_status.md` ligne A/B » | Le guide doit se suffire ; les preuves passent par l'annexe. |
| Notation de log dans la prose | « `> 0xFF TYPE 5` **BOOT_TZ0** → `< 0x69` » | Voir § 7. |
| Numéro dans le titre ou dans un renvoi | « # 3. Séquence de boot du SEP » ; « voir chapitre 5 » | Les numéros se désynchronisent. |
| Comptage sans objet | « 19/19 », « 15/15 paires », « 7/12 » | Dire de quoi : « 7 des 12 endpoints ». |
| Inventer une explication plausible | — | Voir § 4, Fidélité. |
| Copier un binaire ou un extrait de binaire Apple | — | Aucun octet de kernelcache, firmware ou dump dans `docs/guide/`. Les courtes trames observées sur un bus, quelques octets d'en-tête, se décrivent en tableau de champs. |

## 9. Avant / après

### Exemple 1 — un risque, pas une consigne

**Avant**

> Après l'unique boot du SEP par m1n1, macOS a exigé une reconnexion au compte Apple au
> redémarrage suivant. **Cause non établie** (un seul cas ; ~20 captures sous hyperviseur
> antérieures n'avaient rien provoqué). Décision en vigueur : pas de nouveau boot du SEP par
> m1n1 sans décision explicite d'Albert.

**Après**

> ⚠️ **Éviter de démarrer le SEP depuis m1n1.** Lors du seul essai, le 9 novembre 2026, macOS
> a exigé une reconnexion au compte Apple au redémarrage suivant. La cause n'est pas
> établie : les quelque vingt captures faites sous hyperviseur n'avaient jamais provoqué ça.
> Tant qu'on ne sait pas, on considère ce boot comme risqué pour l'état de macOS. Voir
> [Règles et risques](10-regles-et-risques.md).

Ce qui change : encadré de risque, date au lieu de « l'unique », plus de consigne ni de nom.

### Exemple 2 — un résultat, pas une péripétie

**Avant**, dans `03-boot-sep.md`

> **Correction vérifiée** : l'ordre d'annonce n'est **pas** fixe (trois ordres observés sur
> huit boots) ; tout code doit chercher les endpoints par nom, pas par rang.

**Après**

> Le SEP n'annonce pas ses endpoints dans un ordre fixe. Huit démarrages de macOS ont été
> comparés, ceux de la série [T-G2](annexe-sources.md#t-g2) : les douze mêmes noms sont
> toujours annoncés, mais dans trois ordres différents. Un pilote doit donc retrouver chaque
> endpoint **par son nom**, jamais par son rang d'arrivée.

Ce qui change : plus de « correction », puisque le lecteur ignore qu'on a cru le contraire ; le
comptage dit ce qu'il compte et renvoie à l'annexe, la conséquence pour le pilote est
la conclusion de la phrase et non une incise.

### Exemple 3 — une hypothèse, dite comme telle

**Avant**, dans `07-sks-keystore.md`

> **Vérifié (macOS, une session)** : corrélation entre événements système et messages SKS —
> `0x209` au verrouillage, `0x228` à la saisie du mot de passe, `0x208` au doigt reconnu ;
> aucune notification TAG 0x01 pendant les invites en session déjà ouverte. **Réserves**
> (décision du sceptique) : une seule session, pas de répétition ; un deuxième `0x209`
> apparaît après chaque verrouillage, non expliqué. Le statut global reste donc proche de
> l'**Hypothèse** pour l'interprétation fine ; voir `docs/verification_status.md` (K-E1) pour
> le détail et les manques.

**Après**

> Pendant une session d'essai sous macOS observé par l'hyperviseur, enregistrée dans les
> captures [T-21](annexe-sources.md#t-21) et [T-22](annexe-sources.md#t-22), chaque
> événement a été suivi d'une notification d'état distincte :
>
> | Événement | État de verrouillage notifié |
> |---|---|
> | verrouillage de la session | `0x0209` |
> | mot de passe saisi | `0x0228` |
> | doigt reconnu sur l'écran verrouillé | `0x0208` |
> | doigt présenté dans une session déjà ouverte | aucune notification |
>
> > **Hypothèse** — Ces notifications suivent l'état du keybag, verrouillé ou
> > déverrouillé, pas le verdict de la comparaison d'empreinte. Ce qui la soutient : le tableau ci-dessus.
> > Ce qui manque : une seule session, un seul essai par cas, et l'un des verrouillages a
> > été suivi de `0x0208` au lieu de `0x0209` ; il faudrait une deuxième session identique.
>
> Puis, dans « Questions ouvertes » : *un second `0x0209` suit chaque verrouillage de dix à
> vingt secondes ; son rôle est inconnu.*

Ce qui change : « vérifié… mais proche de l'hypothèse » devient un fait observé, le tableau,
plus une hypothèse encadrée ; l'inexpliqué part en fin de chapitre ; plus d'étiquette de
carnet, plus de rôle interne, plus de renvoi vers les notes de travail.

### Exemple 4 — un fait avec son setup et son « pourquoi »

**Avant**, dans `03-boot-sep.md`

> `GETRAND` (`> 0xFF TYPE 16`) renvoie 4 octets aléatoires de la ROM : **Vérifié** sans macOS
> (trace `20261109-212150_sep_getrand`, 4 octets obtenus, aucun plantage).

**Après**

> Le SEP répond à m1n1 même quand aucun macOS ne tourne, dans le montage décrit en
> [S2](annexe-sources.md#s2). Le message le plus simple pour s'en assurer est GETRAND, de
> type 0x10 sur l'endpoint 0xFF, par lequel la ROM du SEP renvoie quatre octets aléatoires.
> Dans l'essai [T-28](annexe-sources.md#t-28), la réponse arrive normalement. Cela montre que la mailbox fonctionne sans macOS ; cela
> ne dit pas si SEPOS, le système complet du SEP, tourne.

Ce qui change : le setup est nommé et lié, la trace est une référence, le message est écrit
en mots, et la phrase dit ce que le résultat prouve et ne prouve pas.

## 10. Avant de rendre un chapitre

1. Chaque terme est défini dans le chapitre et présent dans le glossaire.
2. Chaque `S…` et `[T-…]` est lié et existe dans l'annexe.
3. Aucune entrée de la table « À ne jamais faire ».
4. Chaque affirmation se retrouve dans les sources ; sinon `QUESTION ALBERT`.
5. Les sections « À retenir » et « Questions ouvertes » existent.
6. Les agents `lecteur-naif` puis `verificateur` répondent « RAS ».

## 11. Règles ajoutées après correction

Quand une correction est demandée sur un chapitre, la règle correspondante s'ajoute ici, avec
la phrase fautive et sa version corrigée.

### Pas de parenthèses

Demandé deux fois. Les parenthèses hachent la lecture et servent à glisser ce qu'on n'a pas
pris la peine d'expliquer.

**Fautif**

> Le SEP (Secure Enclave Processor, le coprocesseur de sécurité de la puce) ne rend aucun
> service tant que le système principal ne l'a pas démarré. […] Au message GETRAND (type 16
> sur l'endpoint 0xFF, par lequel m1n1 demande des octets aléatoires), le SEP renvoie quatre
> octets ([T-28]).

**Corrigé**

> Le SEP, ou Secure Enclave Processor, est le coprocesseur de sécurité de la puce. Il ne
> rend aucun service tant que le système principal ne l'a pas démarré. […] m1n1 sait demander
> des octets aléatoires au SEP par le message GETRAND, de type 0x10 sur l'endpoint 0xFF. Dans
> l'essai [T-28], le SEP renvoie quatre octets.

Comment faire : une définition va en apposition, entre virgules, ou dans sa propre phrase ;
une référence de trace ou de setup devient un complément de la phrase, « dans l'essai
[T-28] » ; une précision passe après deux-points ou dans une phrase à part ; « source :
kext » s'écrit « d'après la lecture des extensions noyau de macOS ».
