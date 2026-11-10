# 1. Le projet

## Objet

Rétro-ingénierie du Secure Enclave Processor (SEP) d'un MacBook Pro 14" M1 Max, en vue de
faire fonctionner Touch ID sous Linux. Le travail procède par **observation** du dialogue
entre le processeur d'application (AP) et le SEP, sans documentation constructeur, puis par
reconstitution du protocole et du matériel nécessaires côté Linux.

Projet privé. Rien n'est publié ni remonté au projet Asahi (voir [chapitre 10](10-regles-et-risques.md)).

## Matériel

- **Machine** : MacBook Pro 14", Apple M1 Max, désignation interne `j314c`, SoC `t6001`.
- **AP** : les cœurs applicatifs, où tourne le système (macOS 13.5 pour l'observation, ou Linux).
- **SEP** : coprocesseur de sécurité isolé, sans stockage persistant propre. Il détient les
  secrets (clés de volume, gabarits biométriques) et ne les expose jamais à l'AP. L'AP ne peut
  que lui adresser des messages et lire les réponses.
- **Capteur Mesa** : le lecteur d'empreinte, périphérique SPI de l'AP (famille `SandDollar`,
  compatible ADT `biosensor,mesa`). Détail au [chapitre 6](06-capteur-mesa.md).

## Principe de Touch ID (cadre)

Touch ID ne se réduit pas à « le capteur lit l'empreinte et renvoie un verdict ». Le capteur
et le SEP établissent une **session chiffrée de bout en bout** ; l'image du doigt transite
chiffrée, l'AP ne faisant que la relayer. La comparaison a lieu **dans le SEP**, qui n'émet
que le résultat. Conséquence directe pour le projet : l'AP (donc Linux) ne voit jamais l'image
en clair et ne peut pas effectuer la comparaison lui-même. **Vérifié** (voir [chapitre 6](06-capteur-mesa.md)
et `docs/verification_status.md` SPI-1).

## Objectif et paliers

- **Cible** : déverrouillage par empreinte sous Linux, équivalent à macOS.
- **Acquis** : Linux pilote le capteur (alimentation, transport en clair, lecture d'identité
  et d'état). **Vérifié** ([chapitre 6](06-capteur-mesa.md)).
- **Blocage** : le service biométrique du SEP (`sbio`) n'est pas disponible tant que l'échange
  xART n'a pas eu lieu au boot ([chapitre 5](05-xart.md)). La faisabilité de la cible dépend
  d'**une question** précise (rejeu de l'état xART), non encore tranchée.

## Phases

- **Phase 1** — observation seule : traces, documentation publique Asahi, code public m1n1 et
  linux-asahi, sources Apple open source. Pas de désassemblage de binaire Apple.
- **Phase 2** (en cours) — désassemblage des kexts macOS **autorisé uniquement** pour extraire
  le protocole AP ↔ SEP (format, séquences, constantes), sans extraction de clé ni de secret.
  Toute information issue d'un kext est marquée `source: kext` dans l'annexe.

Les contraintes et lignes rouges qui encadrent tout le travail sont au [chapitre 10](10-regles-et-risques.md).
