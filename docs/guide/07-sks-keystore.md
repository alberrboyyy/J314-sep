# 7. SKS / keystore

L'endpoint `sks` (0x12, Secure Key Store) gère le keybag de l'utilisateur : l'état de
verrouillage qui conditionne l'accès aux clés (et donc, en bout de chaîne, le déverrouillage
par biométrie). Il fait partie des cinq endpoints annoncés **après** l'échange xART, donc absent
sous m1n1 seul ([chapitre 3](03-boot-sep.md)). Référence : `docs/messages.md` § SBIO (TAG 0x01)
et `docs/verification_status.md` (K-E1).

## Notifications d'état (TAG 0x01)

`source: kext` : les messages SEP → AP de **TAG 0x01** sur `sbio` sont acheminés par le kext
vers `IOBiometricFamily` (`sksQueueEnqueue` → `sksQueueProcess`), qui journalise
« userID = …, lockState = … ». Donc, dans un message TAG 0x01 :

- **DATA = userID** ;
- **le champ (type + param·0x100) = état de verrouillage du keybag (lockState)**.

Conséquence importante : les valeurs de TYPE observées sur ces notifications (0x08, 0x09, 0x11,
0x15, 0x28, …) sont des **états de keybag**, pas des verdicts biométriques. Cela **contredit**
une lecture antérieure qui voyait `<01/08` comme un « résultat de correspondance ».

## Observations (K-E1)

**Vérifié (macOS, une session)** : corrélation entre événements système et messages SKS —
`0x209` au verrouillage, `0x228` à la saisie du mot de passe, `0x208` au doigt reconnu ; aucune
notification TAG 0x01 pendant les invites en session déjà ouverte. **Réserves** (décision du
sceptique) : une seule session, pas de répétition ; un deuxième `0x209` apparaît après chaque
verrouillage, non expliqué. Le statut global reste donc proche de l'**Hypothèse** pour
l'interprétation fine ; voir `docs/verification_status.md` (K-E1) pour le détail et les manques.

## Question ouverte (SKS-1)

Le keybag démarre dans un état de blocage biométrique (`lockState` = 0x0015) jusqu'à validation
du code. **Inconnu** : le SEP **refuse-t-il** une demande de correspondance tant que ce blocage
dure, ou macOS **s'abstient-il** seulement de la faire ? La distinction ne se tranche que par une
**écriture** vers le SEP (envoyer la demande et observer le refus ou non) — donc hors de ce que
fait un agent, et conditionnée aux lignes rouges ([chapitre 10](10-regles-et-risques.md)). Aucune
observation positive à ce jour.

## Portée

SKS confirme que, même avec `sbio` actif, le déverrouillage dépend de l'état du keybag géré par
le SEP. C'est une dépendance supplémentaire au-delà de la seule disponibilité de `sbio`, mais
elle n'est pertinente que si l'échange xART aboutit d'abord ([chapitre 5](05-xart.md)).
