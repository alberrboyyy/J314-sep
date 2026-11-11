# xART (le « coffre ») : ce qu'on sait et les voies possibles

But de ce document : rassembler ce qui est **public** et ce que **nos traces** montrent sur l'échange xART (EP 0x13),
puis lister les voies pour débloquer la biométrie (`sbio`, EP 0x08) sous Linux, en marquant pour chacune si elle
franchit une ligne rouge, son risque, et ce qu'elle exige. **Aucune action ici** : document d'analyse seulement.

Statut des faits : `vérifié` = confirmé par une expérience ou par 19/19 boots concordants ; `hypothèse` = interprétation.
Sources : `docs/messages.md` (« xART au boot — traces »), `docs/journal.md` (entrées analyste du 2026-11-10), doc Asahi
et code public m1n1/linux-asahi déjà cités dans `messages.md`. Rien ne vient d'un firmware Apple déchiffré ni d'une source interne.

---

## 1. Le problème, en une phrase

Le SEP n'annonce les services biométrie et clés (`sbio` 0x08, `sks` 0x12, `scrd` 0x0a, `sse` 0x0c, `skdl` 0x17)
**qu'après** que l'AP (le système qui tourne sur les cœurs principaux) a mené à bien un dialogue xART sur l'EP 0x13.
Sous m1n1/Linux, personne ne tient ce dialogue → le SEP reste à **7 endpoints sur 12**, et Touch ID n'existe pas encore
côté SEP (`vérifié` : SEP-BOOT 2026-11-09 = 7/12 ; 19/19 boots macOS = les 5 autres arrivent après le 1er échange 0x13).

## 2. Ce qu'est xART

- **Rôle (public, doc Asahi)** : xART = *anti-replay / anti-rollback*. Le SEP n'a pas de stockage persistant à lui ; il confie
  des blobs chiffrés (« lockers ») à l'AP, qui les écrit sur le disque, et les lui rend au boot suivant. xART garantit que
  le SEP reçoit bien la **dernière** version sauvée, pas une ancienne rejouée. EP 0x10 `xars` = mise en place, EP 0x13 `xarm`
  = le manager qui fait les fetch/save (noyau macOS : « AppleSEPXART (EP: 19) »).
- **Où c'est stocké (vu dans les logs noyau)** : un volume `xART` est monté, puis un fichier « Gigalocker »
  `/System/Volumes/xarts/<UUID>.gl`. Le contenu est lié à l'état chiffré du disque macOS (FileVault, trousseau).
- **Le dialogue au boot (vérifié, structure identique 19/19)** — détail complet dans `messages.md` :
  1. `xarm` s'annonce, envoie un 1er message (`< 0x13 TAG2 TYPE0x0e`), puis **attend l'AP 2,8 à 3,8 s** ;
  2. l'AP répond (`> TAG2`), le SEP demande, l'AP **fetch** « SEP-xART » puis « USER-xART » (réponses à en-tête **constant**
     `0x64/0x103` et `0xad/0x07`, dont le **contenu CRC change à chaque boot**) ;
  3. **0,122 s après** la dernière réponse de ce bloc, le SEP annonce `sbio`, puis `skdl`, `sse`, `sks`, `scrd` ;
  4. puis une série de « fetch locker » (4 lockers constants + des lockers variables), et des « Saving » dont l'AP **recopie le CRC**.
- **Enchaînement boot→boot (vérifié, 15/15 paires)** : le CRC « Fetched » d'un boot = le dernier CRC « Saving » du boot précédent.
  C'est exactement un coffre : l'AP rend ce que le SEP lui a fait sauver la fois d'avant.

## 3. Pourquoi c'est un mur pour Linux

- **Répondre sur 0x13, c'est écrire vers le SEP** → ligne rouge (script `pending/` + lancement par Albert, jamais par un agent).
- **Le contenu n'est pas rejouable à l'aveugle** : les en-têtes de réponse sont constants et connus, mais le **corps** des
  réponses fetch (le blob du locker) n'a **jamais été capturé** — il passe en mémoire partagée (OOL), et le tracer n'a pas
  d'OOL sur 0x13. Les requêtes SEP ne contiennent **aucun identifiant** du locker : l'identité est ailleurs (shmem), non tracée.
- **Le contenu est lié au disque macOS chiffré** : fournir au SEP un vieux blob, ou un mauvais, c'est précisément ce que
  l'anti-replay est censé détecter ; côté macOS cela touche FileVault et le trousseau. Risque réel pour les données.
- **Incident ouvert** : après l'unique boot SEP par m1n1 (SEP-BOOT), Albert a dû se reconnecter à son compte Apple. Cause
  **non établie** (≥ 6 causes possibles, 1 seul cas). Tant qu'elle n'est pas écartée, pas de nouveau boot SEP.

## 4. Les voies possibles

Classées de la plus sûre (rien vers le SEP) à la plus risquée (écriture, Albert seul). « LR » = franchit une ligne rouge.

### Voie A — Rester côté capteur, sans SEP (en cours, sûr)
- **Idée** : continuer à faire parler Linux au capteur mesa directement (déjà `vérifié` : identité, état, broche d'interruption).
- **Limite dure** : tout le dialogue utile (image du doigt, matching) est **chiffré entre le SEP et le capteur** ; l'AP ne fait
  que relayer. Sans le SEP qui configure le capteur, pas de détection de doigt (`vérifié` 2026-11-10 : doigt posé, aucun changement).
- **LR ?** Non. **Risque** : nul. **Donne Touch ID ?** Non, jamais seul. Sert de base matérielle, pas plus.

### Voie B — Observer plus finement l'échange xART existant, sans y répondre (sûr, recommandé, PRÊT)
- **Idée** : capturer le **corps** (OOL) des réponses fetch/save 0x13 **pendant un boot macOS normal** sous hyperviseur, pour
  enfin voir ce que contient un locker et comment l'AP le construit. Aujourd'hui on n'a que les en-têtes.
- **Prêt, aucun code à écrire** (vérifié dans `hv/trace_sep_filtered.py` le 2026-11-10) : le tracer lit déjà l'OOL de
  **n'importe quel** endpoint via `SEP_OOL_EPS`. L'apprentissage du buffer passe par le CNTL (EP 0x00 TYPE 2/3/4/5), qui
  tourne **même quand l'affichage est filtré sur 0x13** (ligne 495, hors du filtre `self.eps`). Le CNTL de l'EP 0x13 fournit
  bien les deux buffers (0x8000 / 0x8000, `messages.md` L91-98). Lecture seule (traduction DART vérifiée, aucune écriture).
- **Commande prête à lancer** (Albert, Mac en mode câble, après backup) :
  ```
  SEP_EPS=0x13 SEP_OOL_EPS=0x13 SEP_OOL_BYTES=0x8000 LIVE_EPS=0x13 \
    ./tools/boot_and_trace.sh c21-xart-ool
  ```
  Donne `traces/<...>_c21-xart-ool/sep.log` (en-têtes 0x13 filtrés) + des `.bin` d'OOL : buffer A sur les `>` (réponse fetch
  de l'AP = le locker rendu), buffer B sur les `<` (save du SEP = le blob confié). Le blob attendu est sur TYPE 0 (`>`, fetch)
  et TYPE 1/6 (`<`, save) ; à confirmer sur la capture. Rien n'est envoyé au SEP (c'est macOS qui dialogue, on écoute).
- **LR ?** Non (lecture seule, même classe que les captures C1-C20, ~20 déjà faites sans souci de données). **Risque** : celui
  d'une capture ordinaire sous hyperviseur (l'incident iCloud venait du **boot SEP par m1n1**, pas d'une écoute de boot macOS).
- **Ce que ça apporte** : voir le contenu réel des lockers et, surtout, préparer la voie C (**rejouer** ces blobs, pas les
  forger). On cherche notamment s'il y a un compteur / nonce par boot dans l'échange, qui déciderait si un rejeu passe.
  **C'est le prochain pas le plus utile et le moins risqué.**
- **Ne peut pas se faire à distance** : demande le câble USB rebranché et un reboot en mode câble → Albert devant le Mac.

### Voie C — RELAYER (pas forger) les blobs xART : Linux joue le rôle de stockage que macOS tient (écriture SEP — LR, Albert seul)
- **Idée (précisée avec Albert le 2026-11-10)** : le SEP n'a **pas de disque** ; il confie ses blobs à l'AP qui les stocke et les
  lui rend au boot. macOS tient ce rôle. **Rien n'oblige à comprendre les blobs** (ils restent chiffrés par une clé interne du
  SEP) : il suffirait que **Linux les stocke et les rende** comme macOS. On ne **forge** rien (ça, c'est impossible, voie D) ; on
  **relaie** l'état que le SEP a lui-même fait sauver. Si le SEP valide, il annonce `sbio` → et c'est **lui** qui fait ensuite la
  comparaison d'empreinte (on n'a jamais besoin de sa clé). Donc le Touch ID n'est **pas** mort par conception : il est derrière cette question.
- **Mesuré par la voie B (c21 vs c23, 2 boots, lecture seule, 2026-11-11, analysis/diff_xart_ool.py)** :
  - Le coffre rendu au SEP = 10 blobs ; **8/10 identiques octet pour octet** d'un boot à l'autre (statiques, rejouables trivialement) ;
    seuls **2 blobs** changent (un de ~848 o, un de ~3 Ko ; hypothèse : SEP-xART + USER-xART). Ce que le SEP **sauve** change à 100 %.
  - Donc la fraîcheur anti-rejeu est **isolée à 2 petits blobs** (et au contenu chiffré, invisible). Pas de nonce en clair dans l'échange.
- **La vraie inconnue qui reste (seulement tranchable par un test en ÉCRITURE)** : quand Linux rendra la **dernière** version sauvée de
  ces 2 blobs, le **compteur scellé** interne au SEP l'acceptera-t-il ? Impossible à lire (chiffré dans le blob). Contrainte : ces 2 blobs
  **périment dès que macOS reboote** (il réécrit) → un essai doit utiliser des blobs capturés juste avant, sans boot macOS entre-temps.
- **Ce qu'il faut, concrètement** : (1) les **vrais fichiers de lockers** (gigalockers `/System/Volumes/xarts/<UUID>.gl` + le
  contenu shmem non tracé), pas seulement les en-têtes ; les lire sur le disque macOS (lecture seule). (2) Un composant Linux qui
  réponde sur l'EP 0x13 avec ces blobs. (3) Un SEP démarré par m1n1 (on sait le faire : SEP-BOOT).
- **Lignes rouges et risque** : répondre sur 0x13 = **écriture SEP** → script `pending/` relu et lancé par **Albert**, jamais un agent.
  Risque de désynchroniser macOS (acceptable pour Albert : il n'a pas besoin de macOS) **MAIS** il faut garantir **aucun brick** et
  **aucune atteinte à la partition Linux** (ses deux seules règles). L'effet de bord iCloud du boot SEP précédent reste inexpliqué :
  prudence. À ne tenter qu'après la voie B et avec le feu vert d'Albert.
- **Verdict** : voie **réaliste** (pas une impasse), mais risquée et conditionnée à la voie B. C'est la seule piste crédible vers un Touch ID complet.

### Voie D — Faire tenir le dialogue xART par un composant de confiance (très lourd, hypothétique)
- **Idée** : réimplémenter côté Linux un « stockage xART » qui se comporte comme l'AP macOS (fetch/save cohérents, monotones),
  avec son propre fichier de lockers, pour amener le SEP à un état où `sbio` est annoncé **sans dépendre du disque macOS**.
- **Différence avec C** : ici on **génère/forge** des lockers (état inventé), là où la voie C se contente de **rejouer** l'état
  réel que le SEP a fait sauver. Forger exige que le SEP accepte des lockers **qu'on fabrique** ; or ils sont chiffrés/authentifiés
  par une clé **interne au SEP**, qu'on s'interdit de chercher (ligne rouge « aucune clé extraite »). **Impossible.** C'est bien la
  voie C (rejeu), pas D (forge), qui est la piste crédible. D documentée seulement pour être écartée.

### Voie E — Contourner xART : démarrer un SEP « neuf » sans état (à creuser, prudence)
- **Idée** : existe-t-il un mode où le SEP démarre sans réclamer de coffre (première initialisation, « SEP vierge ») et annonce
  quand même `sbio` ? Sous SEP-BOOT, le SEP tourne et attend ; on ne sait pas s'il annoncerait `sbio` après un xART **vide**
  (réponses « rien à te rendre ») plutôt qu'après un xART **rempli**.
- **Ce qu'il faut pour trancher, sans écrire** : d'abord la voie B (comprendre le fetch), ensuite seulement une éventuelle
  réponse *minimale* « locker introuvable » — mais **toute réponse sur 0x13 reste une écriture SEP** (LR, Albert). On a déjà vu
  le SEP gérer un « not found » (TAG 9, USER_XART_LOCKER « not found », 19/19) : il ne plante pas dessus. Piste à garder, pas à exécuter.

## 5. Recommandation

1. **Maintenant, sans risque** : finir la Voie A (base capteur propre, en cours) et préparer la **Voie B** (tracer l'OOL de
   l'EP 0x13) pour une future capture macOS en lecture seule. C'est le seul pas qui augmente vraiment ce qu'on sait du coffre
   sans rien écrire ni risquer les données.
2. **Décision d'Albert, pas d'un agent** : toute Voie C/D/E implique une écriture vers le SEP (0x13), donc un script `pending/`
   relu et lancé par lui. Backup : Albert n'a qu'un backup Linux et accepte de perdre macOS ; ses deux règles sont **ne pas
   bricker** et **ne pas toucher la partition Linux** (voir CLAUDE.md et mémoire). La cause de la reconnexion iCloud reste à garder en tête.
3. **Honnête (corrigé le 2026-11-10 avec Albert)** : le Touch ID complet n'est **pas mort par conception**. On ne peut pas **forger**
   les lockers (chiffrés, voie D impossible), mais on peut peut-être les **rejouer** (voie C) : le SEP n'a pas de disque, il compte
   sur l'AP pour lui rendre ses blobs ; Linux pourrait tenir ce rôle sans jamais les comprendre. Le Touch ID est donc **derrière une
   seule question** : l'anti-rejeu accepte-t-il un rejeu fidèle de l'état courant, ou y a-t-il un compteur/nonce par boot ? La voie B
   (lecture seule) doit trancher cela avant tout essai en écriture. But court terme garanti : « Linux parle au capteur » (atteint).

## 6. Ce qui manque pour avancer (sans franchir de ligne rouge)
- [x] Tracer l'OOL de l'EP 0x13 : déjà supporté par `hv/trace_sep_filtered.py` (`SEP_OOL_EPS=0x13`), vérifié le 2026-11-10. Rien à coder.
- [ ] Lancer la capture (commande voie B ci-dessus) : Mac en mode câble, Albert devant la machine, après backup complet. Pas faisable à distance.
- [ ] Documenter le format d'un locker observé (taille, en-tête, ce qui est chiffré) dans `messages.md`, une fois la capture faite.
- [ ] Voie C (après B) : chercher un **compteur/nonce par boot** dans l'échange 0x13 (le point qui décide si un rejeu passe).
- [ ] Voie C : lire les **gigalockers** du disque macOS (`/System/Volumes/xarts/<UUID>.gl`) en lecture seule, pour avoir les vrais blobs.
- [ ] Voie C (écriture, Albert) : seulement si B dit que c'est jouable → script `pending/` qui répond sur 0x13 avec les blobs rejoués ;
      garanties obligatoires : aucun risque de brick, aucune écriture vers la partition Linux. Lancé par Albert.

## 7. État du 2026-11-10 (contexte)
Backup : Albert a **un** backup (2026-11-10) — à préciser : couvre-t-il macOS/FileVault, ou seulement sa partition Linux ?
La voie B écoute un boot macOS (zones liées au disque chiffré), donc le point à clarifier avant de lancer est : backup macOS inclus.
Accès : Albert est à distance (école), Mac joignable seulement par la **partition Linux de test** via WireGuard (capteur, pas de SEP).
Câble USB débranché → ni m1n1 ni capture macOS tant qu'il n'est pas rebranché. La voie B attend donc qu'Albert soit devant le Mac.
