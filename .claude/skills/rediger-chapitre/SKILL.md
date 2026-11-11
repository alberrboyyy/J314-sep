---
name: rediger-chapitre
description: Réécrire ou modifier un chapitre de docs/guide/ selon STYLE.md, puis le faire relire par les agents lecteur-naif et verificateur jusqu'à « RAS » des deux. À utiliser pour toute rédaction ou correction d'un chapitre du guide.
---

# Rédiger un chapitre du guide

Argument : le fichier du chapitre (ex. `docs/guide/03-boot-sep.md`). Un seul chapitre à la
fois ; on ne touche à aucun autre chapitre.

## Ce qui est interdit pendant ce travail

- Toute action sur le matériel, tout démarrage du SEP, tout script dans `pending/`.
- Lire en détail ou modifier le code de `m1n1/`.
- Modifier ou déplacer les notes de travail (`docs/*.md` hors `docs/guide/`) et `traces/`.
- Copier dans `docs/guide/` un binaire ou un extrait de binaire Apple.
- Inventer : un fait, un chiffre ou un « pourquoi » absent des sources devient
  `<!-- QUESTION ALBERT : ... -->` à l'endroit précis où il manque.

## 1. Lire

1. `docs/guide/STYLE.md` en entier, y compris « Règles ajoutées après correction ».
2. `docs/guide/glossaire.md` et `docs/guide/annexe-sources.md`.
3. Le chapitre actuel, et le plan dans `docs/guide/README.md` pour savoir ce que les
   chapitres voisins couvrent déjà.
4. Les sources du sujet : `docs/verification_status.md` (fait foi pour les statuts),
   `docs/hypotheses.md`, `docs/messages.md`. Le journal (`docs/journal.md`) sert à vérifier
   un détail ou une date, pas à être recopié.

## 2. Préparer

Avant d'écrire, dresser la liste des affirmations du chapitre, chacune avec :
sa source (fichier + ligne), son statut (vérifié / hypothèse / inconnu), son setup et sa
trace (`S…`, `[T-xx]`), et en une ligne pourquoi elle compte pour Touch ID sous Linux.

- Pas de source : l'affirmation sort du chapitre, ou devient une `QUESTION ALBERT`.
- Pas de « pourquoi » dans les sources : `QUESTION ALBERT`.
- Trace ou setup absent de l'annexe, terme absent du glossaire : les y ajouter d'abord.
- Contenu qui recouvre un autre chapitre : ne rien déplacer ; proposer la solution à Albert
  et attendre sa réponse.

## 3. Réécrire

Suivre la structure de STYLE.md : introduction, contenu, « À retenir », « Questions
ouvertes ». Vérifié par défaut, hypothèses en encadré, inconnu en fin de chapitre. Passer
la liste « Avant de rendre un chapitre » de STYLE.md.

## 4. Boucle de relecture (4 tours au maximum)

À chaque tour :

1. Lancer l'agent `lecteur-naif` sur le chapitre.
2. Corriger chaque point signalé. Si la correction demande une information absente des
   sources, ne pas l'inventer : `QUESTION ALBERT`.
3. Lancer l'agent `verificateur` sur le chapitre corrigé.
4. Corriger chaque point signalé, en revenant à la source citée.
5. Si l'un des deux a signalé quelque chose à ce tour, refaire un tour complet (une
   correction pour l'un peut casser quelque chose pour l'autre).

La boucle s'arrête quand les deux répondent « RAS » dans le même tour, ou après le
4e tour. Un point signalé qu'on estime infondé n'est pas ignoré en silence : il est gardé
pour le résumé, avec la raison.

Une `QUESTION ALBERT` n'empêche pas le « RAS » : c'est un manque déclaré, pas une erreur.

## 5. Résumé pour Albert

En français simple, sans jargon :

- le chapitre réécrit (chemin du fichier) ;
- le nombre de tours, et les derniers rapports des deux agents (tels quels) ;
- les points restés signalés après le 4e tour, ou écartés, avec la raison ;
- la liste de toutes les `QUESTION ALBERT` du chapitre, chacune avec la phrase concernée ;
- ce qui a été ajouté au glossaire et à l'annexe ;
- les recouvrements avec d'autres chapitres, s'il y en a, et la solution proposée.

Ne pas commiter sans qu'Albert le demande. Quand il corrige quelque chose, ajouter la règle
correspondante, avec la phrase fautive et sa correction, dans « Règles ajoutées après
correction » de STYLE.md.
