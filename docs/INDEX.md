# INDEX — carte de la documentation

Ce fichier est la **carte** de `docs/` : il dit **où trouver quoi**, pas ce qui est vrai.
Il ne contient **aucun fait original** ; chaque fait fait foi dans le document pointé, pas ici.
Dernière mise à jour **2026-11-18**. Source : lecture des docs eux-mêmes (aucune expérience, aucune écriture).

> Contexte et règles d'abord : lire `CLAUDE.md` (phase, lignes rouges, « Qui décide quoi ») et `README.md`
> à la racine du repo. Ils ne sont pas dans `docs/` et ne sont pas réécrits par cette carte.

## Par où commencer (reprise en session neuve)

Ordre conseillé, du plus utile au contexte :

1. **`docs/handoff.md`** — état de fin de session + liste de tâches. Le point de reprise : « où on en est ».
2. **`docs/journal.md`** (entrées du haut) — chronologie, plus récent en premier. L'entrée du 2026-11-18 résume l'état actuel (voie C fermée, confiance élevée).
3. **`docs/verification_status.md`** — la référence de ce qui est `vérifié` vs `hypothèse`.
4. **`docs/messages.md`** — la table de référence du protocole (messages, endpoints, format mailbox).
5. **`docs/guide/README.md`** — la même matière, expliquée de façon pédagogique (voir « Guide humain »).

## Référence canonique

| Fichier | Rôle (1 ligne) | Statut | Voir aussi |
|---|---|---|---|
| `messages.md` | Table des messages SEP, carte des endpoints, format mailbox, CNTL/OOL. | canonique (quasi tout `hypothèse` ; 2 lignes `vérifié`) | verification_status.md, kext_sepmanager.md |
| `verification_status.md` | Statut `vérifié`/`hypothèse` de chaque message/champ, avec preuve et ce qui manque. | canonique | messages.md, hypotheses.md |
| `kext_sepmanager.md` | Protocole AP↔SEP extrait des kexts macOS 13.5 (sbio, xART, SKS) — `source: kext`. | canonique (tout `hypothèse (kext)`, 2 sous-points `vérifié` §13b/§13c) | messages.md, driver_plan.md |
| `driver_plan.md` | Plan d'architecture du futur pilote Linux Touch ID (phase 2, aucun code). | canonique (planification) | kext_sepmanager.md §7, verification_status.md |
| `sensor_hw.md` | Matériel du capteur Mesa (contrôleur SPI, broches, ADT). | canonique (plusieurs points `inconnu`/`hypothèse`) | public_linux_state.md §2 |
| `sources.md` | Faits **publics** autorisés (1 fait = énoncé + source exacte + date). Aujourd'hui : guide « Apple Platform Security ». | canonique (faits publics) | public_linux_state.md §H–L |
| `public_linux_state.md` | État **public** côté Linux (SEP, SPI, AOP, capteur) d'après m1n1/linux-asahi/doc Asahi. | canonique (public, `[public]`/`[déduit]`/`[trace]`) | sources.md, voie_nonce.md |

## Exploration (voies)

| Fichier | Rôle (1 ligne) | Statut | Voir aussi |
|---|---|---|---|
| `xart_options.md` | Vue d'ensemble xART + les voies A–E pour débloquer `sbio` sous Linux. | exploration (A/B faites ; C = la piste crédible, aujourd'hui fermée ; D/E écartées) | voie_c_design.md, gigalocker.md |
| `voie_c_design.md` | Plan + analyse de sûreté de la voie C (rejouer les lockers xART au SEP). | exploration-fermée (voie C conclue fermée, confiance élevée — journal 2026-11-18) | xart_options.md, gigalocker.md |
| `gigalocker.md` | Format décodé du fichier coffre `<UUID>.gl` lu sur disque (support de la voie C). | exploration-fermée (décode = VU factuel ; la voie C qu'il servait est fermée) | voie_c_design.md, messages.md §xART |
| `voie_nonce.md` | Piste « établir/reproduire le nonce de fraîcheur xART côté AP ». | exploration-fermée (bloquée côté AP, `hypothèse` ; 1 capture OOL 0x15 resterait à faire) | kext_sepmanager.md §9, public_linux_state.md |
| `voie_sbio.md` | Piste « piloter `sbio` (0x08) directement sous m1n1 » — pourquoi le 0x73 est muet. | exploration-ouverte (plausible, non prouvée bloquée ; E1 proposée) | kext_sepmanager.md §13, messages.md §SBIO |
| `power_sep_options.md` | Question annexe : le SEP peut-il régler la décharge en veille ? (hors ligne principale) | exploration-fermée (conclut : SEP pas le bon levier) | — |

## Historique / process

| Fichier | Rôle (1 ligne) | Statut | Voir aussi |
|---|---|---|---|
| `journal.md` | Journal chronologique de toutes les observations/captures/décisions (plus récent en haut). | historique (chronologie faisant foi) | hypotheses.md, handoff.md |
| `hypotheses.md` | Hypothèses ouvertes + revues du sceptique + expérience qui tranche chacune. | process (mélange `ouverte`/`confirmée`/`réfutée`) | verification_status.md, journal.md |
| `handoff.md` | Snapshot d'état de fin de session + liste de tâches cochées. | process (point de reprise ; bandeau daté 2026-11-17) | journal.md |
| `RECUPERATION_MAC.md` | Procédure de récupération du Mac après la casse du boot. | historique (marqué « RÉSOLU / historique » en tête) | incident_voie_c_boot_casse.md, handoff.md |
| `incident_voie_c_boot_casse.md` | Analyse : pourquoi le boot Apple a cassé après l'essai voie C. | historique (cause, tout `hypothèse`) | RECUPERATION_MAC.md |
| `agent-macos.md` | Consignes pour l'agent « macos » tournant dans macOS 13.5 sous l'hyperviseur. | périmé? (plus de macOS 13.5 ni de tracing sous hyperviseur — à confirmer, voir « incertain ») | README.md |

## Guide humain

| Fichier | Rôle (1 ligne) | Statut | Voir aussi |
|---|---|---|---|
| `guide/` | Documentation pédagogique en 10 chapitres + glossaire + annexe des sources. A son propre `README.md` (sommaire) et `STYLE.md`. | — (synthèse ; renvoie aux docs de travail pour la preuve) | guide/README.md, guide/annexe-sources.md |

## Recouvrements / doublons repérés

Observations seulement — rien n'est corrigé ici ; la décision revient à Albert.

- **`handoff.md` vs `journal.md`** : le bandeau et le « point de reprise » de `handoff.md` reprennent les dernières entrées du journal (état 2026-11-17/18). Recouvrement sur l'**état courant** ; `handoff.md` ajoute une liste de tâches que le journal n'a pas. Le **journal fait autorité** pour la chronologie, `handoff.md` pour « où on en est + à faire » — et son bandeau (17/11) est plus ancien que l'entrée de tête du journal (18/11), donc susceptible de retard.
- **`sources.md` vs `guide/annexe-sources.md`** : noms proches mais **contenus différents** — `sources.md` = faits **publics externes** (guide Apple) ; `annexe-sources.md` = annexe du guide qui mappe nos **dossiers de traces et setups** (S1/S2, [T-xx]). Peu de recouvrement réel ; chacun fait autorité dans son domaine. Le voisinage de noms peut prêter à confusion, sans plus.
- **`RECUPERATION_MAC.md` vs `incident_voie_c_boot_casse.md`** : même événement (boot cassé après voie C) sous deux angles — l'un la **procédure de récup** (résolue), l'autre l'**analyse de cause**. Complémentaires ; `RECUPERATION_MAC.md` fait autorité pour le « comment on a réparé », l'autre pour le « pourquoi ça a cassé ».
- **`RECUPERATION_MAC.md` / `incident_voie_c_boot_casse.md` vs `handoff.md` / `journal.md`** : le statut de récupération du Mac est aussi raconté dans le bandeau de `handoff.md` et le journal. Les deux premiers sont marqués **historique** ; `handoff.md`/`journal.md` portent l'état vivant.
- **xART éparpillé** : `xart_options.md`, `voie_c_design.md`, `gigalocker.md`, `voie_nonce.md`, les sections xART de `messages.md`, `kext_sepmanager.md` §8-9 et `public_linux_state.md` touchent tous au même sujet. La **conclusion « rejouer le coffre ne marche pas »** est redite dans plusieurs ; `verification_status.md` + l'entrée journal du 2026-11-18 font la synthèse qui fait foi.
- **`sources.md` §Apple vs `public_linux_state.md` §H–L** : même guide Apple. Recouvrement **assumé** — `sources.md` cite explicitement « exploité en détail dans public_linux_state.md §H–L ». Renvoi volontaire, pas un vrai doublon.
