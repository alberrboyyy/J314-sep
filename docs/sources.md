# sources.md — faits publics utiles (un fait = un énoncé + source exacte + date de lecture)

> Séparé de nos traces. Ici **seulement** ce qui est établi par une source publique autorisée.
> Nos observations (traces/kext) vont dans `docs/journal.md`, `docs/messages.md`, `docs/public_linux_state.md` (§trace/kext).

## Guide « Apple Platform Security » (support.apple.com) — page « Secure Enclave »
URL : `https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web` — lu le **2026-11-18**.
Source autorisée par Albert le 2026-11-18 (document de conception public, ni leak ni firmware).

- Le Secure Enclave (A12/S4 et +) est **apparié à un « Secure Storage Component »** matériel pour le stockage
  d'entropie. (Verbatim : « the Secure Enclave is paired with a Secure Storage Component for entropy storage. »)
- SEP ↔ Secure Storage Component : **protocole chiffré+authentifié à accès exclusif**, sur un **bus I2C dédié**
  accessible uniquement par le SEP.
- **Toutes les clés de chiffrement des données utilisateur sont enracinées dans l'entropie du stockage NV du Secure
  Enclave** (« rooted in entropy stored in the Secure Enclave nonvolatile storage »).
- Services **anti-rejeu** du stockage NV = **révocation aux « anti-replay boundaries »** : changement de code,
  on/off/reset de Face/Touch/Optic ID, ajout/retrait biométrie, ajout/retrait carte Apple Pay, EACS. **Le boot n'y
  figure pas.**
- Counter lockbox = salt 128 bits + verifier 128 bits + **compteur 8 bits** + max tentatives → **anti-brute-force de
  code**, pas un compteur de version xART.
- Memory Protection Engine (RAM volatile) : **clé de protection mémoire éphémère régénérée au démarrage** +
  « anti-replay value » par bloc, arbre d'intégrité en SRAM dédiée. (Concerne la RAM, pas le xART persistant.)
- Le guide **n'emploie pas** « xART », « boot nonce », « monotonic counter », et **ne dit pas** que l'état NV périme
  à chaque boot → **ne tranche pas explicitement** compteur-de-version vs nonce-par-boot pour le stockage persistant.

Exploité en détail dans `docs/public_linux_state.md` §H–L (2026-11-18 après-midi).

## Chat communauté Asahi (#asahi-dev, OFTC/Matrix) — TÉMOIGNAGES, non vérifiés par nous
> Logs publics. Ce sont des dires de membres, PAS de la doc officielle : à traiter comme **hypothèse crédible**
> (personnes qui connaissent le hardware), jamais `vérifié`. Cohérents entre eux et avec notre empirique.

### Brick SEP : récupérable vs définitif (2026-11-19, réponse à une question générique d'Albert)
- **« Michael Reeves »** : il existe un Secure Element **séparé du SEP**, nom **« Stockholm »** (comparé à une
  carte à puce Java), qui stocke **une partie de l'état anti-rejeu du SEP**. Le toucher **DIRECTEMENT** → même
  un DFU peut ne pas réparer (**brick définitif possible**). En passant **seulement par le SEP** → « should be
  fine but still risky ». [témoignage] → c'est la voie irréversible que les docs publiques ne nommaient pas ;
  on n'a aucun accès direct au Stockholm, on ne parle qu'au SEP. Voir mémoire `stockholm-se-brick-definitif`.
  > Verbatim (texte exact, fautes incluses) : « If you mess with the "Stockholm"SE (not to be confused with SEP,
  > it's a seperate chip like those in a Java card) which stores some of SEP's anti-replay state, it's possible
  > even DFU can't help fix it. So don't mess with it directly, if you only talk to it through SEP it should be
  > fine but still risky »
- **« chaos_princess »** : casse **volontairement** le gigalocker de façon « réaliste » sur une machine
  sacrificielle (mac mini) ; ça tue une install macOS ou **toutes** (recoveryOS + boot picker comptent comme
  « install macOS »), selon l'action. **« my mac mini is still alive »** après ces essais → la classe
  « gigalocker cassé » (= notre activité SERVE_GL/voie C) est **récupérable** par DFU. [témoignage]
  Question posée (« toujours DFU-récupérable, ou déjà un brick définitif ? ») : réponse en attente au 2026-11-19.
  > Verbatim (texte exact, fautes incluses) : « i have deliberately broke gigalocker in "realistic" ways on a
  > sacrificial machine and it either kills one macos install, or all macos installs depending on what exactly
  > you do. (recoveryos and boot picker count as "macos install") » ; « my mac mini is still alive :P » ;
  > « what'cha trying to do? » ; « right »

### Faisabilité de Touch ID sous Linux (2026-11-19)
Témoins = **membres du board Asahi** (gouvernance, page asahilinux.org/community « Governance ») : chaos_princess
= Sasha Finkelstein ; **James Calligeros** (dev SEP/Apple Silicon). Haute autorité, mais toujours « témoignage ».
- **James Calligeros** : « It's been looked at and is **definitely possible**, it's just not high on anyone's
  priority list and is **extremely involved**. Tracing SEP is excruciatingly slow which makes it a **massive
  time sink**, and as mentioned if you **break gigalocker you earn yourself a dfu restore**. » [témoignage]
  → Retenu : (1) Touch ID sous Linux est **faisable** (confirmé par un expert SEP du board) ; (2) **regardé mais
  pas priorisé** → terrain largement ouvert, pas de duplication d'un effort fini ; (3) **tracer le SEP est LE
  time-sink** (valide la priorité « filtrer le tracer par endpoint » du CLAUDE.md) ; (4) **casser le gigalocker
  = DFU restore** (recoupe chaos_princess + Michael : classe through-SEP = récupérable, pas de brick définitif).
