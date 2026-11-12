# Pourquoi le boot Apple a cassé après l'essai « voie C » — analyse

2026-11-12 — Claude (Opus 4.8). Analyse hors hardware, sources repo + publiques autorisées (Asahi, m1n1,
linux-asahi, Apple support public). Aucune action matérielle, aucune écriture SEP.

But : donner le **mécanisme le plus probable** de la casse du boot Apple (macOS + recovery + Startup Options +
1TR morts, seul m1n1 permissif démarre) survenue après l'essai voie C (rejeu xART au SEP), en séparant
strictement ce qui est **FAIT/VU** de ce qui est **HYPOTHÈSE**.

Statut global : la casse touche de l'**interne SEP/SEPOS/ROM non observable** ; aucune des conclusions sur la
cause profonde n'est `vérifié`. Tout le mécanisme proposé est `hypothèse`, appuyé sur des faits de trace + des
sources publiques et par élimination.

---

## 1. Ce qui est FAIT / VU (appuyé sur traces, logs, sources)

### 1.1 Ce que l'essai a réellement envoyé au SEP
- **Séquence de boot permissive** (EP 0xFF/0xFE) : GET_STATUS, BOOT_TZ0, BOOT_IMG4, SET_SHMEM — identique à
  `pending/sep_boot.sh`. Puis amorçage EP 0 (SECMODE 0x14) et mise en place des tampons OOL A/B de l'EP 0x13
  (4 CNTL acquittés, A iova=0x2c000 / B iova=0x38000).
  Source : `pending/sep_xart_replay.sh` (corps, l.310-361) ; `pending/sep_boot.sh` ; `docs/journal.md`
  (« ESSAI VOIE C n°1 », 2026-11-11).
- **Rejeu de 4 transactions xART**, puis arrêt : op 0x0e (état fw-boot), op 0x13 (UUID d'OS = apfs-preboot-uuid),
  op 0x00 FETCH **SEP-xART** maître, op 0x00 FETCH **USER-xART** maître. Soit **2 blobs xART maîtres + l'UUID +
  le drapeau fw**, pas « 4 gigalockers ».
  Source : `docs/kext_sepmanager.md` §8 (table des op xART, source: kext) ; `docs/journal.md` 2026-11-11.
- **Bifurcation reproductible** (n=2) : à la 5e requête le SEP émet `TAG=0x05 TYPE=0x01` (= **SAVE** xART maître)
  là où macOS émet `TYPE=0x05` (= FETCH gigalocker). `TAG=0x05 TYPE=0x01` n'existe **nulle part** dans la capture
  macOS (grep du sep.log). Le SEP veut **ré-écrire** son xART, pas continuer à restaurer.
  Source : `docs/journal.md` (« ESSAI VOIE C n°1 » et « essai 1 REPRODUIT (n=2) ») ;
  `docs/voie_c_design.md` « Résultats — essai 1 ».
- **Le SAVE n'a PAS été acquitté.** Le script s'arrête à la divergence (échec fermé) : « Rien de plus envoyé au
  SEP. » Donc **aucun nouveau gigalocker n'a été écrit sur le disque** et le stockage côté AP **n'a pas avancé**.
  Source : `pending/sep_xart_replay.sh` l.437-448 (branche DIVERGENCE) et en-tête « ÉTAT v2.1 ».

### 1.2 Symptômes après l'essai
- macOS boucle (bootloop) ; **recovery, Startup Options (le menu de démarrage) et 1TR = morts** (bootloop /
  retombe sur m1n1) ; **seul m1n1 permissif démarre** (« Running proxy… »).
- **DFU Revive fait → n'a PAS réparé.**
- ALARM (Linux quotidien) récupérable uniquement par **tethered boot** (noyau en RAM via m1n1).
  Source : `docs/journal.md` (« INCIDENT … menu Apple cassé », soir ; « RÉCUPÉRATION : ALARM bootable », nuit) ;
  `docs/RECUPERATION_MAC.md`.
- **Confond partiel à garder en tête (FAIT) :** m1n1 avait été mis **par défaut volontairement** par Albert pour
  faciliter les reboots du projet ; le Linux est « plus sélectionnable car le menu est cassé ». Donc « ça boote
  m1n1 » est **en partie voulu** — mais cela n'explique PAS que **Startup Options et 1TR eux-mêmes** bouclent
  (un simple objet de boot par défaut laisserait le menu s'ouvrir).
  Source : `docs/RECUPERATION_MAC.md` l.24-25 ; `docs/journal.md` l.141.

### 1.3 Discriminant essentiel : un boot SEP permissif SEUL n'avait PAS cassé le menu
- Le **premier** boot SEP par m1n1 (SEP-BOOT, 2026-11-09) a démarré le SEPOS permissif, atteint 7/12 endpoints,
  puis **est resté au repos sans engager l'échange xART**. Suite : une simple **reconnexion au compte Apple**
  (cause non établie), **pas** de menu cassé ; et Albert a ensuite **redémarré macOS normalement 2×, sans
  problème de login**.
  Source : `docs/journal.md` (rapport d'Albert, l.472 « deux redémarrages normaux sous macOS ») ;
  `docs/xart_options.md` §3 (incident iCloud) ; `docs/messages.md` / journal SEP-BOOT 2026-11-09.
- **Conclusion de fait :** le boot permissif *nu* est **récupérable par un boot macOS normal** (macOS re-scelle).
  Ce qui diffère dans la voie C, c'est **l'engagement de l'échange xART** (2 blobs maîtres + UUID) **et la
  tentative de re-scellement** (SAVE). La casse corrèle avec **cela**, pas avec le simple boot permissif.

### 1.4 Ce que les sources publiques établissent
- **xART = anti-rejeu, lié aux clés de volume.** Asahi : « the SEP generates a Volume Encryption Key (VEK) and
  eXtended Anti-Replay Token (xART) for each APFS volume » ; « The xART prevents replay attacks from capturing
  the VEK » ; avec FileVault « the VEK and xART are wrapped with a Key Encryption Key (KEK) ».
  Source : https://asahilinux.org/docs/platform/security/ (cité dans `docs/public_linux_state.md` §A).
- **Le SEP détient une « Boot Policy ».** Asahi, même page : pour chaque kernelcache, « its hash is recorded in
  the SEP's Boot Policy ». → **le succès du boot sécurisé d'un OS passe par un état détenu DANS le SEP.**
  Source : https://asahilinux.org/docs/platform/security/ (`docs/public_linux_state.md` §A).
- **Le SEP a vraisemblablement une notion d'identité de l'OS courant.** Asahi, guide de boot (« The magic ESP
  stuff ») : ils soupçonnent que les features sécurité « (e.g. SEP) … might have a concept of "currently booted
  OS identity" ». (Spéculatif côté Asahi, mais convergent avec le kext.)
  Source : https://asahilinux.org/docs/alt/boot-process-guide/ (lu le 2026-11-12).
- **La fraîcheur vient d'un nonce que le SEP produit lui-même, pas l'AP.** Le kext expose
  `nonce_generate/read/invalidate`, `erase_session_seeds_for_UUID`, `setup_OS_UUID`, et un nonce ROM
  (`AppleSEPBooter::generateROMNonce`, opcode `BootOpcode::ReportNonceWord`). L'AP ne **choisit pas** la valeur
  du nonce. op 0x13 = `_determineOsUuidGated` rend l'`apfs-preboot-uuid` de `/chosen`.
  Source : `docs/kext_sepmanager.md` §8-§9 (source: kext).
- **Le mécanisme de fraîcheur n'est documenté nulle part publiquement** (ni compteur monotone, ni nonce par
  boot, ni ancrage). `pnon` (0x15) est seulement « boot policy related / Machine owner credentials handoff »,
  pas décrit comme un nonce anti-rejeu. Le stockage AP (gigalocker) est **trivialement rejouable**
  (m1n1 `get_gigalocker`). → publiquement **indéterminé** si un rejeu du dernier état passe.
  Source : `docs/public_linux_state.md` §C/§D/§E ; https://asahilinux.org/docs/hw/soc/sep/.
- **Revive ≠ Restore (Apple, public).** Revive « doesn't erase your Mac » (plus rapide, ne touche pas les
  données) ; Restore = « erase it and restore it to factory settings » (bouton « Restore and Update »).
  La page Apple **ne précise pas** ce qui est réinitialisé exactement (ni disque, ni partitions, ni état scellé).
  Source : https://support.apple.com/en-us/108900 (lu le 2026-11-12).

---

## 2. Départage des pistes (ce que les faits permettent de dire)

### Piste 1 — Le boot SEP permissif a-t-il, à lui seul, désynchronisé l'état scellé ?
**Plutôt NON pour le *simple* boot ; OUI pour l'*engagement xART*.** Le discriminant §1.3 est net : un boot SEP
permissif nu (SEP-BOOT 2026-11-09) n'a pas cassé le menu et s'est récupéré par un boot macOS normal. Ce qui a
cassé le boot est spécifique à la voie C : avoir mené le SEP **dans l'échange xART** sous un contexte de
fraîcheur (nonce/graine de session) **qui n'est pas** celui sous lequel les blobs rejoués ont été scellés, au
point que le SEP a jugé l'état non courant et a basculé en **re-scellement** (SAVE). Ce que relie le public :
le SEP détient la **Boot Policy** (hash des kernelcaches) et vraisemblablement l'**identité de l'OS courant** ;
donc un état SEP incohérent peut casser le boot sécurisé de **tout** OS signé Apple.
`hypothèse` sur le « comment » interne.

### Piste 2 — Rejeu partiel (op 0x00 ×2) / rotation de nonce au boot a-t-il invalidé l'ancre, SANS acquitter le SAVE ?
**Partiellement tranché, le reste indéterminé.** FAIT : le SAVE **n'a pas été acquitté**, donc **le stockage AP
n'a pas avancé** (pas de nouveau gigalocker écrit). La casse n'est donc **pas** « un SAVE committé a fait avancer
le compteur sur disque ». Reste la question, **non observable** : le SEPOS a-t-il muté son **état interne** par
le simple fait de booter + fetcher 2 blobs maîtres + juger l'état non courant (rotation/invalidate de nonce ou
de `session_seeds`, cf. kext §9) ? Le fait qu'il **demande** un SAVE prouve qu'il a déjà, en interne, un contexte
différent de celui des lockers rejoués — mais pas que ce contexte a été **rendu irréversible** par l'essai.
`hypothèse` ; **indéterminé** si réversible en principe.

> Nuance honnête (chicken-and-egg). Après SEP-BOOT 2026-11-09, la guérison a été « reboote macOS, il re-scelle ».
> Après la voie C, macOS **ne peut plus booter** — donc ce même auto-correctif est **impossible**. Il se peut
> que l'état soit réparable *en principe* par un boot macOS, mais que la désynchronisation soit précisément ce
> qui **empêche** macOS de booter pour se réparer. On ne peut pas trancher réversible / irréversible depuis
> l'extérieur. `indéterminé`.

### Piste 3 — Pourquoi Revive ne répare pas mais Restore (destructif) le ferait ?
**Cohérent avec « la casse est dans l'état scellé SEP ↔ état sur disque », pas dans le firmware.** Revive
rafraîchit le firmware **sans effacer le disque** (Apple : « doesn't erase your Mac ») : il ne réécrit **ni** la
LocalPolicy, **ni** le volume/les gigalockers xART, **ni** ne force le SEP à re-sceller un état neuf. Donc si la
casse est une **incohérence entre l'état scellé interne du SEP et l'état de boot-policy/xART sur disque**, Revive
**ne peut pas** y toucher → échec constaté (FAIT). Restore « erase it and restore it to factory settings » :
réinitialise le disque (LocalPolicy + xART + boot policy recréés depuis zéro) et ré-établit un état scellé frais
→ répare *a priori*. Limite : la page Apple **ne détaille pas** ce que Restore réinitialise ; l'attribution
« Restore recrée l'état scellé » est une **interprétation** cohérente, pas une citation.
Sources : https://support.apple.com/en-us/108900 ; `docs/RECUPERATION_MAC.md` ; `docs/journal.md` (nuit).

### Piste 4 — Le menu / 1TR dépendent-ils du SEP au point qu'un SEP désynchronisé casse MÊME la récupération ?
**C'est l'élément clé qui explique que *même* recovery/Startup Options/1TR soient morts.** FAIT (public) : le SEP
détient la **Boot Policy** (hash des kernelcaches enregistré dans le SEP). Startup Options et 1TR tournent depuis
le **recoveryOS**, lui-même booté sous une LocalPolicy que le SEP doit évaluer. Si l'état scellé du SEP
(boot policy / nonce / identité d'OS) n'est plus cohérent, l'attestation de **n'importe quel** OS Apple (macOS,
recoveryOS, le menu, 1TR) échoue → bootloop généralisé, pendant que le chemin **permissif** de m1n1 (qui ne
vérifie **rien** de tout ça) passe encore. Cela explique le motif observé « tout Apple meurt, seul m1n1 vit ».
`hypothèse` (le public établit que le SEP détient la Boot Policy ; il ne décrit pas la mécanique de l'échec).

---

## 3. Mécanisme le plus probable (conclusion)

**Hypothèse de travail, la mieux étayée (statut `hypothèse`, non `vérifié`) :**

1. L'essai voie C a démarré le SEPOS en mode **permissif** (sans la LocalPolicy signée d'Apple, sans
   l'attestation normale) et l'a conduit **dans l'échange xART** sous un **contexte de fraîcheur (nonce / graine
   de session) propre à ce boot**, différent de celui sous lequel les blobs SEP-xART / USER-xART rejoués avaient
   été scellés par macOS. *(FAIT : boot permissif + 4 transactions rejouées ; HYPOTHÈSE : le contexte de
   fraîcheur diffère — nonce produit par le SEP, kext §9.)*
2. Jugeant l'état restauré **non courant**, le SEP a basculé en **re-scellement** (op 0x01 SAVE) au lieu de
   poursuivre les FETCH — bifurcation **reproductible** (FAIT, n=2). Le simple fait d'avoir booté SEPOS +
   fetché les blobs maîtres + tenté un re-scellement a **avancé ou invalidé l'ancre de fraîcheur interne** du SEP
   (rotation/`invalidate` de nonce ou de `session_seeds`, kext §9). *(HYPOTHÈSE : interne, non observable ; le
   SAVE n'a pas été acquitté, donc ce n'est pas le stockage disque qui a avancé — FAIT.)*
3. Comme **cette même ancre scellée** gouverne la **Boot Policy** détenue par le SEP (hash des kernelcaches) et
   l'**identité de l'OS courant**, le boot sécurisé Apple de **tout** OS signé — macOS, recoveryOS, Startup
   Options, 1TR — ne retrouve plus un état cohérent → **bootloop généralisé**. Le chemin permissif de m1n1 ne
   vérifie aucun de ces éléments → il reste le seul à démarrer. *(HYPOTHÈSE appuyée sur Asahi platform/security
   « hash recorded in the SEP's Boot Policy » + boot-process-guide « currently booted OS identity ».)*
4. **Revive** rafraîchit le firmware sans toucher ni le disque ni l'état scellé → ne répare pas (FAIT constaté,
   cohérent). **Restore** efface le disque et recrée LocalPolicy + xART + boot policy → ré-établit un état scellé
   frais → réparerait (HYPOTHÈSE cohérente avec la distinction Apple Revive/Restore et l'échec de Revive).

**En une phrase :** la voie C a probablement **désynchronisé l'état scellé interne du SEP** (nonce/graine
d'ancre de fraîcheur) en l'amenant à re-sceller sous un contexte permissif ; comme cet état scellé est aussi ce
qui autorise le boot sécurisé Apple (Boot Policy + identité d'OS détenues par le SEP), **toutes** les voies de
boot Apple — y compris la récupération — se retrouvent sans état cohérent et bouclent, tandis que le boot
permissif m1n1, qui ne vérifie rien, passe encore.

**Ce qui reste franchement INDÉTERMINÉ :**
- Le « comment » exact de la mutation (rotation de nonce ? invalidation de graines ? marquage « à re-sceller » ?)
  est **interne à SEPOS/ROM**, hors de portée du kext (qui ne montre que le côté AP). Non tranché.
- **Réversible vs irréversible** : impossible de dire si un boot macOS aurait guéri l'état (empêché seulement
  parce que macOS ne peut plus booter), ou si la mutation est définitive. Non tranché.
- **Attribution causale voie-C → menu cassé** : la bifurcation est reproductible (n=2), mais la **casse du menu**
  est un **événement unique** (n=1), avec un confond (m1n1 par défaut volontaire, plusieurs runs, Revive
  intercalé). Le lien « voie C a cassé le menu » reste une **HYPOTHÈSE forte par corrélation temporelle et par
  élimination** (§1.3), pas un FAIT reproduit.

---

## 4. Ce qui resterait à vérifier SANS risque (lecture / doc seulement)

Aucune de ces étapes n'écrit vers le SEP ni sur un disque ; toutes respectent les lignes rouges.

1. **Comparer le gigalocker sur disque avant/après l'incident** (lecture seule, m1n1 `get_gigalocker` /
   `rust_read_gigalocker`, cf. `docs/public_linux_state.md` §D). S'il est **inchangé** par rapport au S_new
   capturé, cela **confirme** que le SAVE n'a jamais été committé côté AP → la casse est **purement interne au
   SEP** (ou en NVRAM), pas dans le stockage xART du disque. Discrimine piste 2.
2. **Lire (read-only) les valeurs de nonce / boot-policy côté NVRAM et ADT** quand le Mac est en m1n1 proxy
   (lecture MMIO/NVRAM seulement — **aucune écriture `nvram`**, ligne rouge). Sans référence pré-incident on ne
   pourra pas tout trancher, mais on peut vérifier la **cohérence interne** (présence/format d'un boot-nonce).
3. **Étude documentaire publique du lien SEP ↔ LocalPolicy / boot-nonce** : lire le guide *Apple Platform
   Security* public (support.apple.com/guide/security — doc publique, **pas** un firmware déchiffré) sur
   LocalPolicy, Owner Identity Key (OIK), « sealed key protection » et le *boot nonce* (`lpnch`), et la page
   Asahi « Open OS Ecosystem on Apple Silicon » (https://asahilinux.org/platform/open-os-interop/, non encore
   lue) pour formaliser comment la Boot Policy détenue par le SEP gate le boot de recoveryOS / Startup Options.
   Objectif : confirmer ou infirmer l'étape 3 du mécanisme (SEP désynchro → recovery cassée) par source publique.
4. **Désassemblage (phase 2, lecture) du sous-système nonce/boot-policy** côté kext (`AppleSEPManager`,
   `generateROMNonce`, `_nonce_action`, `erase_session_seeds_for_UUID`) pour voir **quand** l'AP déclenche une
   rotation/invalidation — et donc si la séquence de l'essai a pu, indirectement, en provoquer une. Protocole
   uniquement, aucune clé.
5. **Non sans risque, donc exclu ici :** le test qui trancherait vraiment réversible/irréversible est un boot
   macOS réussi (impossible, c'est la panne) ou un DFU **Restore** (destructif) — à ne faire qu'après image
   disque, par Albert.

---

## Sources

- `pending/sep_xart_replay.sh` (corps l.310-488, en-tête « ÉTAT v2.1 ») — ce que l'essai a envoyé, échec fermé
  sur divergence, SAVE non acquitté.
- `pending/sep_boot.sh` — séquence de boot permissive.
- `docs/journal.md` — « ESSAI VOIE C n°1 » (2026-11-11), « essai 1 REPRODUIT (n=2) », « INCIDENT … menu Apple
  cassé », « RÉCUPÉRATION : ALARM bootable », rapport d'Albert l.472 (2 reboots macOS OK après SEP-BOOT).
- `docs/kext_sepmanager.md` §2 (boot ROM / SET_SHMEM), §8 (dispatch xART : op 0x00/0x01/0x05/0x13), §9 (nonce :
  `generateROMNonce` / `ReportNonceWord`, `nonce_*`, `apfs-preboot-uuid`, l'AP ne choisit pas le nonce).
- `docs/voie_c_design.md` « Résultats — essai 1 » ; `docs/xart_options.md` §2-§3 ; `docs/RECUPERATION_MAC.md`.
- `docs/public_linux_state.md` §A-§E (sources publiques xART/VEK/KEK/Boot Policy, get_gigalocker, mécanisme non
  documenté) ; §1.1-1.2 (boot SEP côté m1n1 / linux-asahi, lpol/ibot, stub permissif).
- https://asahilinux.org/docs/platform/security/ — VEK/xART/KEK ; « its hash is recorded in the SEP's Boot
  Policy ».
- https://asahilinux.org/docs/alt/boot-process-guide/ — SEP « might have a concept of "currently booted OS
  identity" ».
- https://asahilinux.org/docs/hw/soc/sep/ — table des endpoints (0x10 xars, 0x13 xarm, 0x15 pnon).
- https://support.apple.com/en-us/108900 — Revive « doesn't erase your Mac » vs Restore « erase it and restore
  it to factory settings » (lu le 2026-11-12).
