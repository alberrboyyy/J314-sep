# Route native — le vrai chemin vers Touch ID sous Linux

2026-11-19 — Claude. Synthèse hors-hardware à partir de nos docs (`driver_plan.md`, `public_linux_state.md` §1,
`voie_sbio.md`, `sources.md`). Aucune action matérielle. But : après le palier « c'est faisable » (James
Calligeros, board Asahi, cf. `sources.md`), fixer **où ça bloque** et **le premier pas concret**.

## 1. Acquis (fait et solide)
- **Capteur (C-A) : fait, vérifié sur matériel.** Linux allume le capteur Mesa (spi2, gpio), lit identité/état
  (`driver/linux/`, journal 10/11). Le lien SPI n'est pas le blocage.
- **Protocole sbio extrait et vérifié.** Format fil `gt_packet_t` (opcode `+0x14`), carte opcode↔opération,
  séquence d'init — `vérifié (macOS)` / `kext` (`messages.md`, `driver_plan.md` §1).
- **Rejeu hors-ligne codé** (module `sepreplay`, 29 tests) : décodage mailbox, découverte 0xFD, réassemblage GT.

## 2. Le mur, et pourquoi le rejeu était condamné
- **sbio ne s'arme pas tant que le SEP n'a pas un état xART *scellé et légitime*** (prouvé ce soir, E1 + contrôle :
  silence = l'**état**, pas le canal DART — `voie_sbio.md` §7).
- **Le rejeu (voie C, sondes sbio sous m1n1) essayait de *court-circuiter* ça** : servir au SEP un coffre xART
  **capturé sous macOS**. La puce le **rejette** (la fraîcheur est ancrée dans le matériel) et demande à
  **re-sceller** (SAVE) — qu'on n'acquitte pas (risque brick). → **on ne peut pas *falsifier* un état scellé**.
- Conclusion : la bonne voie n'est pas de **rejouer** l'état scellé de macOS, mais de laisser le SEP **sceller
  SON PROPRE état frais pour les volumes de Linux** — exactement ce que fait macOS pour les siens.

## 3. Ce que la route native demande vraiment
Un **driver Linux qui construit l'environnement SEP**, dans l'ordre :
1. **Booter SEPOS sous Linux — DÉJÀ FAIT (porte déjà franchie, en routine, sans incident).** Via le harnais
   proxyclient (`sep.boot()` = GET_STATUS / BOOT_TZ0 / **BOOT_IMG4** / SET_SHMEM), on démarre SEPOS depuis
   des semaines (ouverture de **chaque** run voie C ; `pending/sep_xart_replay.sh` l.17-20/520, `sep_boot.sh`).
   L'IMG4 envoyé = le firmware SEP **propre à la machine** (préchargé en RAM par iBoot, ADT `/chosen/memory-map`
   SEPFW), pas un blob leaké. C'est une écriture SEP qu'**Albert** lance (`pending/`), déjà éprouvée. ⚠️ Ne PAS
   confondre avec le **driver noyau** Linux (`drivers/soc/apple/sep.rs`, `status="disabled"` sur j314c,
   `public_linux_state.md` §1.3) : ça, c'est le chemin « SEP | WIP » d'Asahi — PAS le nôtre.
2. **Gérer l'EP 0x13 (xART/gigalocker)** pour que le SEP **scelle un état frais** pour les volumes Linux (la doc
   Asahi dit « 0x13 is needed for SKS to start »). C'est **le cœur manquant** : c'est ce qui donne l'état scellé
   légitime qui **arme sbio**.
3. **EP 0x12 (SKS / keybag)** — probablement requis : les notifs sbio passent par `sksQueueProcess` (kext), et le
   match 0x09 peut être bloqué tant que le keybag est verrouillé (`driver_plan.md` §2, D2).
4. **EP 0x08 (sbio)** : ouverture, 0x73, init capteur, puis match — protocole déjà extrait.

## 4. Réalité : « extremely involved » (James), confirmé par le code public
- Le pilote public `drivers/soc/apple/sep.rs` **n'est qu'un amorceur** : TZ0/IMG4/shmem/découverte. **Aucun code
  0x13 (xART), 0x12 (SKS) ni 0x08 (sbio)** nulle part (ni m1n1, ni linux-asahi) — `public_linux_state.md` §1.2/§1.3.
  Feature-support Asahi : « SEP | WIP | WIP ».
- Donc la route native = **construire l'environnement SEP qu'Asahi n'a pas encore construit** (xART → SKS → sbio).
  C'est exactement le « extremely involved / not prioritized » de James. On n'est pas en retard : on serait en
  **avance** sur une pièce qu'ils n'ont pas faite.

## 5. Les portes (écritures SEP) — gatées Albert, mais récupérables
- Chaque marche (IMG4, 0x13, 0x12) **écrit vers le SEP** → script `pending/`, lancé par Albert.
- **Le risque est réduit, PAS nul ni prouvé sûr.** Ce qu'on sait :
  - **Récupérable (empirique)** : casser le gigalocker = **DFU restore** (voie C, chaos_princess, James, 19/11).
    ⚠️ ça couvre **les manips essayées**, pas « toute écriture SEP possible ».
  - **Définitif connu** : toucher le **Stockholm SE en direct** (Michael) — **un** chemin irréversible, qu'on ne
    fait jamais. Michael a dit through-SEP « should be fine but **still risky** » : il n'a **pas** dit que c'est le
    seul chemin définitif.
  - **Inconnu** : les sources publiques ne peuvent **pas exclure** d'autres voies irréversibles (« non documenté ≠
    prouvé impossible », documentaliste 19/11).
  → Pour notre classe (through-SEP), le brick permanent est **peu probable mais non nul**. On ne traite **jamais**
  « through-SEP » comme « garanti sûr ». Chaque écriture : **après backup disque** (on l'a), yeux ouverts,
  DFU + ré-enrôlement possible. (`stockholm-se-brick-definitif`, `sources.md`.)

## 6. Le premier pas concret, et la question qui tranche
- **Question décisive** (celle qui transforme « faisable » en « ça marche ») : *si un driver Linux gère
  correctement l'EP 0x13 au boot SEPOS, le SEP scelle-t-il un état frais qui **arme sbio** ?* Personne ne l'a
  testé (terrain ouvert).
- **Le boot SEPOS n'est PAS la porte** (déjà franchi en routine, §3.1). La **vraie porte matérielle**, c'est la
  **politique 0x13 native** : répondre *absent* aux FETCH (laisser la puce créer du frais) puis **acquitter +
  persister le SAVE**. Le **SAVE-ack** est l'écriture supplémentaire (fait avancer le compteur scellé) = décision
  **Albert**, `pending/`, backup + DFU en filet. Tout le reste est **hors-hardware** : handler 0x13 côté driver à
  partir du VU (`xart.py`/`xart_responder.py`, faits + testés), testé en rejeu, puis le script `pending/` du run
  natif avec en-tête but/risque/résultat (fail-closed, budget de SAVE borné).
- **Inconnus en aval** (à ne pas masquer) : l'**enrôlement sous Linux** (les gabarits macOS sont scellés à l'état
  macOS, ne se transfèrent pas → Linux aura besoin de son propre enrôlement — `driver_plan.md` C-D, « autre
  chantier ») ; et le gating keybag du match 0x09 (D2).

## En une phrase
Touch ID sous Linux ne passe **pas** par rejouer l'état de macOS (mur prouvé), mais par **écrire le driver qui
fait sceller au SEP son propre état frais pour Linux** (0x13 → 0x12 → 0x08) — gros chantier, non commencé
publiquement, faisable, à risque **borné** (DFU), dont la 1re porte matérielle (boot SEPOS/IMG4) est une décision
d'Albert.
