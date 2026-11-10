# 10. Règles et risques

Ces règles priment sur toute autre considération. Source : `CLAUDE.md` (faisant foi).

## Priorités de risque (ordre strict)

1. **Ne jamais rendre le Mac inutilisable (brick).**
2. **Ne jamais perdre la partition Linux de test.**

Le backup d'Albert ne couvre que Linux ; **la perte de macOS est acceptable**. Donc le risque
pour des données macOS (FileVault, trousseau) est toléré, mais tout risque de brick ou
d'atteinte à la partition Linux ne l'est pas.

## Lignes rouges (toutes phases)

- **Aucune écriture vers le SEP par un agent** : endpoints xART/pnon/sks/xars (0x13, 0x15, 0x12,
  0x10), gigalockers, envoi d'IMG4. Toute écriture jugée nécessaire est écrite dans `pending/`
  avec un en-tête (but, risque, résultat attendu), puis **relue et lancée par Albert**.
- **Le matériel passe uniquement par `tools/*.sh`.** Pas d'appel direct à `m1n1/proxyclient`, pas
  de script ad hoc ouvrant `/dev/ttyACM*`.
- **Jamais** : `bputil`, `kmutil`, `csrutil`, `nvram`, partitionnement, `dd`, `sudo`. La boot
  policy et l'installation de m1n1 sont faites à la main par Albert.
- **Rien ne sort du dépôt vers Asahi** (issues, PR, doc, IRC/Matrix). Projet privé. On ne modifie
  rien dans `m1n1/` (les mainteneurs interdisent l'usage d'IA sur leur projet).
- **`traces/` est en lecture seule** après capture ; les analyses vont dans `docs/`.
- **Aucune copie de code Apple** (même réécrit) dans `driver/`. Le pilote s'écrit à partir de la
  doc du protocole.
- **Phase 2** : désassemblage de kext **uniquement** pour le protocole (format, séquences,
  constantes), aucune clé ni secret extrait ; information issue d'un kext marquée `source: kext`.

## Qui décide quoi

- L'agent décide seul : lecture, analyse, documentation, outillage sur le PC, captures en lecture
  seule, et les validations techniques (ce qui reste incertain est noté, pas renvoyé à Albert).
- L'agent sollicite Albert **uniquement** si l'action peut abîmer le Mac ou écrit vers le SEP, en
  une phrase simple (ce qu'on fait, ce qui peut rater, oui/non).

## Exception : Linux de test

Sur la partition Asahi de test (`root@10.0.200.4`, jetable) **uniquement**, via
`tools/linux_ssh.sh`, l'agent peut agir en root pour compiler et charger les modules de
`driver/linux/`. Interdit même là : partitionner, toucher à m1n1 / à la boot policy / à macOS,
et envoyer quoi que ce soit au SEP.

## Rigueur

- Une hypothèse n'est **Vérifiée** que si une expérience dédiée l'a confirmée (reproductible).
  Une interprétation de log, même convaincante, reste une **Hypothèse**.
- Chaque observation est consignée dans `docs/journal.md` (date, trace, ce qui a été vu, comment).
- En cas de doute, le dire : « je ne sais pas » vaut mieux qu'un motif inventé.

## Filtre de sécurité du modèle

Un filtre de sécurité (`[cyber]`) peut interrompre le travail sur ce sujet selon le modèle qui
exécute la session. Observé : coupures sous Fable 5.2, Sonnet 5.5, Opus 5.5 ; **Opus 4.8 passe**.
Pour déléguer sans se faire couper, utiliser un `fork` de la session (il tourne sur le modèle du
parent). Le programme « Cyber Verification » d'Anthropic (niveau Defense Access, ouvert aux
particuliers) réduit ces coupures — décision et compte d'Albert.
