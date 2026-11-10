# 9. État et suite

Synthèse de l'état au 2026-11-10. Détail et chronologie : `docs/journal.md` et `docs/handoff.md`.

## Acquis (Vérifié)

- **Transport mailbox AP ↔ SEP** compris et tracé en lecture seule (format, DART, buffers OOL,
  CNTL). [Chapitre 2](02-architecture.md).
- **Boot du SEP sous m1n1 seul** : « BOOT OK », 7/12 endpoints. GETRAND répond sans macOS.
  [Chapitre 3](03-boot-sep.md).
- **Capteur piloté par Linux** : alimentation, transport en clair, identité identique à macOS,
  état, broche « donnée prête » caractérisée, transport réactif. [Chapitre 6](06-capteur-mesa.md).
- **Relais de l'image** capteur → SEP **octet pour octet** (type 0x65, en-tête 0x1c) ;
  chiffrement de bout en bout confirmé ; 27 images lues / 7 transmises sur une session.
- **Outillage** complet et réutilisable : traceur OOL générique, capture, boot SEP, accès Linux
  de test, pilote capteur, rejeu hors ligne. [Chapitre 8](08-outillage.md).

## Blocages et incertitudes

- **`sbio` absent sans xART** : blocage central. La suite dépend d'**une** question — l'anti-rejeu
  xART accepte-t-il un rejeu fidèle de l'état courant, ou impose-t-il un compteur/nonce par boot ?
  [Chapitre 5](05-xart.md). **Non tranché.**
- **SKS-1** : le SEP refuse-t-il une correspondance sous blocage de keybag ? Ne se tranche que par
  une écriture. [Chapitre 7](07-sks-keystore.md). **Non tranché.**
- **Incident iCloud** après le boot du SEP par m1n1 : cause non établie (un cas). [Chapitre 3](03-boot-sep.md).
- Points mineurs ouverts : second `0x209` après verrouillage, groupe de broches 116-118.

## Prochaines étapes

1. **Voie B (lecture seule, sans risque)** : capturer le contenu de l'échange xART pendant un
   boot macOS, y chercher le compteur/nonce, lire les lockers du disque. Prête côté outil ;
   demande le câble USB et la présence d'Albert. [Chapitre 5](05-xart.md), [chapitre 8](08-outillage.md).
2. **Analyse** de cette capture → verdict sur la faisabilité du rejeu (voie C).
3. **Selon le verdict** : soit préparer un essai de rejeu (écriture SEP, `pending/`, lancé par
   Albert, sous garanties) ; soit acter que Touch ID s'arrête là, honnêtement.

## Décisions qui appartiennent à Albert

- Tenter ou non la voie C (écriture xART) une fois la voie B analysée.
- S'inscrire ou non au programme de vérification d'Anthropic pour réduire les coupures du filtre
  de sécurité sur ce sujet (voir [chapitre 10](10-regles-et-risques.md)).
- Jusqu'où aller : s'arrêter à « Linux parle au capteur », ou viser Touch ID complet.

## Pistes connexes

- **Hibernation / veille** : la batterie qui se vide en veille relève du sommeil profond (gestion
  d'alimentation du noyau Asahi), **pas du SEP**. L'endpoint `hibe` n'est pas derrière xART mais
  n'a montré **aucune** activité dans nos captures. Analyse : `docs/power_sep_options.md`.
