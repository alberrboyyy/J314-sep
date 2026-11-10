# sep-touchid — documentation du projet

Documentation de référence du projet : rétro-ingénierie du Secure Enclave Processor (SEP)
d'un MacBook Pro 14" M1 Max (modèle `j314c`, SoC `t6001`), en vue de faire fonctionner
l'authentification biométrique (Touch ID) sous Linux.

Ce guide documente **ce qui a été établi** : architecture, protocole, matériel, outillage,
et l'état de chaque résultat. Il est rédigé pour un lecteur à l'aise avec l'informatique
système ; la terminologie technique est employée directement, chaque terme étant défini à
sa première occurrence.

## Conventions

- **Vérifié** — confirmé par une expérience dédiée et reproductible (ou par un invariant
  observé sans exception sur un échantillon significatif de captures). Niveau de confiance élevé.
- **Hypothèse** — interprétation cohérente d'observations, non confirmée par une expérience
  discriminante. À ne pas traiter comme acquis.
- Ces libellés sont alignés sur `docs/verification_status.md`.
- Chaque affirmation technique renvoie à l'**annexe** pour la preuve et le détail brut.

## Annexe (preuves et détail)

Ce guide explique et synthétise ; il ne remplace pas les documents de travail, qui restent
la source faisant foi et ne sont pas réécrits :

- `docs/messages.md` — table des messages, carte des endpoints, format mailbox, CNTL/OOL.
- `docs/verification_status.md` — statut Vérifié/Hypothèse de chaque point, avec preuve et manques.
- `docs/sensor_hw.md` — matériel et dialogue du capteur Mesa.
- `docs/xart_options.md` — analyse du coffre xART et des voies vers `sbio`.
- `docs/driver_plan.md` — plan d'architecture du pilote Linux.
- `docs/journal.md` — journal chronologique des captures et observations.
- `docs/handoff.md` — état de fin de session et liste de tâches.

## Plan

1. [Le projet](01-le-projet.md) — périmètre, matériel, objectif, phases.
2. [Architecture AP ↔ SEP](02-architecture.md) — mailbox, format des messages, DART, buffers OOL.
3. [Séquence de boot du SEP](03-boot-sep.md) — ROM, mémoire partagée, annonce des endpoints.
4. [Carte des endpoints](04-endpoints.md) — les douze services du SEP et leur rôle.
5. [Le coffre xART](05-xart.md) — anti-rejeu, échange au boot, rejeu contre forge.
6. [Le capteur Mesa](06-capteur-mesa.md) — matériel, transport, session chiffrée, image.
7. [SKS / keystore](07-sks-keystore.md) — EP 0x12, keybag, notifications d'état.
8. [Outillage](08-outillage.md) — traceur, captures, boot du SEP, pilote Linux, rejeu.
9. [État et suite](09-etat-et-suite.md) — acquis, blocages, décisions ouvertes.
10. [Règles et risques](10-regles-et-risques.md) — lignes rouges, priorités, workflow.
