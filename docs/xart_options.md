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

### Voie B — Observer plus finement l'échange xART existant, sans y répondre (sûr, recommandé)
- **Idée** : capturer le **corps** (OOL/shmem) des réponses fetch 0x13 **pendant un boot macOS normal** sous hyperviseur, pour
  enfin voir ce que contient un locker et comment l'AP le construit. Aujourd'hui on n'a que les en-têtes.
- **Ce qu'il faut** : étendre le tracer pour suivre l'OOL de l'EP 0x13 (comme on l'a fait pour l'EP 0x08 du capteur, C19→C20).
  Capture en **lecture seule** d'un boot macOS : l'AP, c'est macOS, c'est lui qui répond ; nous on écoute.
- **LR ?** Non (lecture seule, c'est macOS qui dialogue avec le SEP, pas nous). **Risque** : celui d'une capture ordinaire.
- **Ce que ça apporte** : savoir si une réponse xART est *fabriquable* hors macOS (probable **non** : blob chiffré par une clé
  du SEP/du disque), et au minimum documenter précisément le coffre. **C'est le prochain pas le plus utile et le moins risqué.**
- **Note** : cette capture touche des zones liées au disque chiffré ; à faire quand Albert a son backup complet du Mac.

### Voie C — Fournir au SEP, sous Linux, les blobs xART capturés sous macOS (écriture SEP — LR, Albert seul)
- **Idée** : rejouer vers le SEP, depuis Linux, les réponses xART qu'on aurait capturées (voie B), pour le pousser à annoncer `sbio`.
- **Problèmes** : (1) **écriture vers 0x13** = ligne rouge absolue → script `pending/`, lancé par Albert, jamais par un agent.
  (2) L'anti-replay est fait pour **refuser** un blob qui n'est pas le dernier sauvé ; un blob capturé lors d'un boot macOS
  sera *périmé* dès que macOS reboote et sauve une nouvelle version. (3) Risque direct FileVault/trousseau si le SEP accepte
  puis se désynchronise. **Probabilité de succès : faible**, risque élevé. À ne pas viser tant que B n'a pas montré que c'est jouable.

### Voie D — Faire tenir le dialogue xART par un composant de confiance (très lourd, hypothétique)
- **Idée** : réimplémenter côté Linux un « stockage xART » qui se comporte comme l'AP macOS (fetch/save cohérents, monotones),
  avec son propre fichier de lockers, pour amener le SEP à un état où `sbio` est annoncé **sans dépendre du disque macOS**.
- **Problèmes** : il faut que le SEP accepte des lockers **qu'on génère** ; or ils sont chiffrés/authentifiés par une clé
  interne au SEP. Sans cette clé (qu'on ne cherche pas : ligne rouge « aucune clé extraite »), on ne peut pas forger un locker
  valide. **Donc cette voie bute sur la même impossibilité que C**, en plus compliqué. Documentée pour être écartée, pas suivie.

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
   relu et lancé par lui, **et** un backup complet du Mac existant, **et** la cause de la reconnexion iCloud écartée.
3. **Honnête** : avec ce qu'on sait, Touch ID complet sous Linux est **probablement hors de portée sans forger un locker xART**,
   ce qui demanderait une clé interne au SEP qu'on s'interdit de chercher. Le but réaliste à court terme reste « Linux parle au
   capteur », pas « Touch ID déverrouille ». La Voie B dira si cette conclusion doit changer.

## 6. Ce qui manque pour avancer (sans franchir de ligne rouge)
- [ ] Étendre le tracer à l'OOL de l'EP 0x13 (réutiliser la méthode OOL de l'EP 0x08, C19→C20).
- [ ] Une capture macOS en lecture seule avec cet OOL, après backup complet du Mac (décision/fenêtre d'Albert).
- [ ] Documenter le format d'un locker observé (taille, en-tête, ce qui est chiffré) dans `messages.md`.
