# Hypothèses et expériences

Format :
```
## H<n> — <énoncé court>
- Statut : ouverte | confirmée | réfutée
- Fondée sur : traces/<dossier> (lignes / horodatages)
- Autres explications possibles :
- Expérience : … (AUTO via tools/ | EXPÉRIENCE HUMAINE)
- Si vraie : … / Si fausse : …
```

---

## H1 — Le SEP refuse Touch ID en mode de sécurité Permissive
- Statut : **réfutée** (2026-11-07, Albert)
- Fondée sur : `bputil -d` → « Security Mode: Permissive » (coih absent), après `bputil -nkcas` + `csrutil disable`
  sur macos13.5 ; le déverrouillage Touch ID fonctionne (boot **natif** de macOS, pas sous m1n1).
- Limite : ça ne dit rien de Touch ID quand macOS tourne sous l'hyperviseur m1n1 → H2.

## H2 — Touch ID marche encore quand macOS 13.5 démarre sous l'hyperviseur m1n1 (kernel chargé par m1n1)
- Statut : **confirmée (2 essais, 2026-11-07, observation d'Albert)**.
  Essai 2 : traces/20261107_h2-notrace-2/ — après démarrage à froid ; client `run_guest.py` resté connecté
  (aucune déconnexion USB après 03:23:24) ; lock / unlock Touch ID OK. Le 1er essai est gardé ci-dessous pour mémoire.
  Essai 1 : traces/20261107_h2-notrace/ — macOS 13.5 a démarré sous HV (lent), Touch ID fonctionne.
  Réserves : (a) le client Python `run_guest.py` avait perdu la connexion USB (02:53:24) : macOS tournait sous m1n1
  SANS client hôte, ce qui n'est pas la condition d'une capture tracée ; (b) détails (Albert) : déverrouillage depuis
  l'écran verrouillé, 3 essais bon doigt réussis ; essais avec un doigt non enrôlé faits (nombre et résultat non précisés).
  Prochaine étape : rejouer H2 avec le client qui reste connecté jusqu'au bout (puis avec le tracer, SEP_EPS=0x08).
- Statut initial : ouverte. **Toute première expérience, SANS tracer.**
- Pourquoi c'est préalable : si Touch ID casse sous hyperviseur même sans trace, aucune capture de
  déverrouillage n'est possible, et il faut comprendre pourquoi avant tout le reste.
- Autres explications à garder en tête si ça échoue : périphérique SPI/biométrique non passé à l'invité,
  état dérivé de la boot policy du kernel chargé par m1n1, timeouts dus à l'hyperviseur lui-même,
  ou macOS qui n'arrive pas jusqu'à l'écran de connexion.
- Expérience : **EXPÉRIENCE HUMAINE.**
  1. Chainload d'un m1n1 frais, puis démarrage de macOS 13.5 sous `run_guest.py` **sans `-m`** (pas de tracer).
     `tools/boot_and_trace.sh` ne convient pas : il impose un script de trace. Commande manuelle (Albert) :
     ```
     # prérequis une fois : python -m venv --system-site-packages ~/.venvs/m1n1 && ~/.venvs/m1n1/bin/pip install asn1==3.3.0
     cd ~/Desktop/sep-touchid && export M1N1DEVICE=/dev/ttyACM0 && mkdir -p traces/20261107_h2-notrace
     ~/.venvs/m1n1/bin/python m1n1/proxyclient/tools/chainload.py -r m1n1/build/m1n1.bin
     # attendre que /dev/ttyACM0 réapparaisse, puis :
     ~/.venvs/m1n1/bin/python m1n1/proxyclient/tools/run_guest.py macos/kernel.macho -- \
       "debug=0x14e serial=3 apcie=0xfffffffe -enable-kprintf-spam wdt=-1 clpc=0" 2>&1 | tee traces/20261107_h2-notrace/console.log
     # dans un autre pane tmux : stty -F /dev/ttyACM1 raw -echo; cat /dev/ttyACM1 > traces/20261107_h2-notrace/hv_uart.log
     ```
     Bootargs = ceux de la doc Asahi (m1n1-hypervisor), identiques à `MACOS_BOOTARGS` de `tools/env.sh`.
     Ne PAS passer `-n` à chainload.py : par défaut il préserve le SEPFW (sinon le SEP ne peut pas démarrer).
  2. À l'écran de connexion : mot de passe (session ouverte ?), verrouillage, puis tentative Touch ID,
     5 fois avec le doigt enrôlé et 2 fois avec un doigt non enrôlé.
  3. Noter : macOS a-t-il atteint le login ? l'option Touch ID est-elle proposée ? résultat de chaque essai ;
     gels, panics ; sortie de la console proxy et de `/dev/ttyACM1` sauvegardée dans un dossier `traces/`.
- Si vraie : on passe aux captures ci-dessous. Si fausse : pas de trace de déverrouillage possible ;
  documenter le mode d'échec et trancher (périphérique, policy, hyperviseur) avant de tracer.

## Captures prévues après H2 (dans cet ordre)
1. **C1 — Boot complet, filtre large** (AUTO, après décision m1n1 et écriture du tracer filtré) :
   SEP_EPS = tous sauf les plus bavards identifiés au premier essai. But : liste réelle des endpoints (0xFD), init 0x13/0x12.
2. **C2 — Deux boots identiques** (AUTO) : ce qui varie entre les deux = non déterministe (nonces, tags, horodatages).
3. **C3 — Déverrouillage Touch ID réussi**, SEP_EPS=0x08,0x12,0x13 (EXPÉRIENCE HUMAINE).
4. **C4 — Doigt non enrôlé**, même filtre (EXPÉRIENCE HUMAINE).
5. **C5 — Déverrouillage par mot de passe**, même filtre (EXPÉRIENCE HUMAINE).
   > Mise à jour sceptique 2026-11-07 : C3, C4 et C5 sont regroupées en **une seule session** avec marqueurs,
   > tous endpoints (le filtre 0x08,0x12,0x13 ferait perdre 0x0a, 0x17, 0x15, actifs au même moment dans C1).
   > Protocole : section « C3 — Touch ID » en bas de ce fichier.
6. **C6 — Single-user mode** : SKS moins bavard, pour isoler l'init (doc Asahi).
Comparaisons : `analysis/diff_traces.py` C3 vs C5, C3 vs C4, C2a vs C2b.

## Q0 — Question de sortie du jalon 1
- Statut : ouverte
- L'enrôlement et la vérification Touch ID dépendent-ils d'un état que seul macOS peut créer
  (keybags utilisateur, xART, credentials SCRD) ?
- Expériences prévues :
  1. Trace d'un boot complet (AUTO) → séquence d'init 0xFD / 0x13 / 0x12.
  2. Trace d'un déverrouillage Touch ID réussi (EXPÉRIENCE HUMAINE).
  3. Même chose avec un doigt non enrôlé (EXPÉRIENCE HUMAINE).
  4. Déverrouillage par mot de passe pour comparaison (EXPÉRIENCE HUMAINE).
  5. Single-user mode : SKS beaucoup moins bavard, utile pour isoler l'init (doc Asahi).
- Sous-hypothèse concrète : HD ci-dessous.

---

# Revue sceptique de C1 (2026-11-07, agent sceptique)

Source unique pour tout ce qui suit : `traces/20261107-033436_c1-boot/sep.log` (1865 messages, mode ASYNC,
horodatage = heure du PC, `seen=1865 logged=1865`). **Une seule trace, un seul boot, aucun marqueur horaire.**
Aucune des hypothèses HA..HD ne peut donc dépasser le statut `ouverte`. Les numéros de ligne renvoient à `sep.log`.

Réserves communes à HA..HD :
- `seen=logged` dit seulement que le tracer n'a rien jeté de ce qu'il a vu ; il ne prouve pas que l'hyperviseur a
  piégé tous les accès (ordre INBOX0/INBOX1, accès 32 bits : non vérifiés, voir journal « tracer »).
- Horodatage côté PC en ASYNC : l'ordre relatif est probablement fiable, les écarts de quelques ms ne le sont pas.
- Le contenu des buffers partagés (OOL) est invisible. Tout ce qui « transporte des données » est une inférence.
- Les noms de champs Asahi (TAG/TYPE/PARAM/DATA) sont un découpage de bits, **pas une sémantique** : C1 montre
  qu'ils ne veulent pas dire la même chose d'un endpoint à l'autre (voir HA, point 1).

## HA — Sur EP 0x08 (sbio), TYPE = n° de commande ; TAG 0xfc = requête/réponse simple ; TAG 0xfe/0xfd + DATA=0x000N0000 = transfert fragmenté
- Statut : ouverte
- Fondée sur : C1 l.320-449 (init), 1109-1145, 1224-1247. Pour : chaque `> TAG=0xfc TYPE=X` reçoit `< TAG=0xfc TYPE=X` ;
  la sous-séquence 0x17,0x15,0x16,0x42,0x18,0x5f apparaît deux fois à l'identique (l.323-336 et l.367-380) ;
  TYPE n'est pas monotone et se répète (0x2b, 0x6b, 0x79 reviennent souvent) → ce n'est pas un compteur.
- Autres explications possibles :
  1. **Sur EP 0x12, le même champ TYPE est un compteur** : il s'incrémente de 1 à chaque requête et reboucle
     (l.1020-1035 : 0xfd, 0xfe, 0xff, 0x00, 0x01…), et c'est TAG qui porte la commande, avec le bit 0x80 dans la
     réponse (0x19→0x99, 0x48→0xc8, 0x45→0xc5). Donc « TYPE = commande » n'est pas une propriété du format SEP ;
     sur 0x08 ce peut être un sélecteur, un identifiant d'objet/handle, ou un index de méthode dont la vraie
     commande est dans l'OOL.
  2. TAG 0xfc pourrait être un identifiant de canal/client (le client AP principal), et 0x01..0x04 / 0x26 d'autres
     canaux (notifications), plutôt qu'une « classe de message ».
  3. 0xfe/0xfd : le sens n'est **pas fixe**. SEP envoie 0xfe et l'AP répond 0xfd pour 0x5b (l.355-362), 0x6d
     (l.423-431), 0x65 (l.1113-1116) ; l'AP envoie 0xfe et le SEP répond 0xfd pour 0x5f (l.335-336, l.379-380) et 0x6c
     (l.1230-1233). Pour 0x5f et 0x6c l'échange 0xfe/0xfd vient **après** la réponse 0xfc finale, et 0x6c se termine
     sur un 0xfd sans 0xfc derrière. Ça colle aussi à : poignée de main de propriété d'un buffer partagé (doorbell
     « buffer prêt » / « buffer rendu »), avec N = numéro de génération ou de slot, sans aucune fragmentation.
  4. DATA=0x000N0000 : sur 0x12 les mêmes bits 48-63 portent des valeurs qui ressemblent à des tailles (0x6c, 0x1dc,
     0x678) et les bits 32-47 un statut 0/1. N=1,2,3 sur 0x08 peut donc être un compteur de morceaux, une taille dans une
     unité inconnue, ou un index de buffer.
- Combien de traces : 1. Insuffisant.
- Expérience :
  - (AUTO, C2) Les deux boots identiques doivent donner la même séquence de TYPE à l'init sbio et le même nombre
    d'allers-retours 0xfe/0xfd pour 0x5b/0x6d/0x5f. Un TYPE qui varie entre boots pour la même étape = pas un n° de commande.
  - (EXPÉRIENCE HUMAINE, C3) Trois déverrouillages bon doigt identiques (étapes `fp_good_1..3`) : la séquence de TYPE
    doit être identique trois fois, à l'exception éventuelle d'une branche succès/échec.
  - (AUTO, outillage tracer, observation pure) Tracer en plus `/arm-io/dart-sep` (`hv/trace_dart.py` existe dans m1n1)
    ou les adresses touchées dans la mémoire partagée au moment des 0xfe/0xfd : s'il s'agit de fragments, chaque 0xfe
    correspond à un morceau différent (offset ou mapping différent) ; si c'est un doorbell, c'est le même buffer à chaque fois.
- Si vraie : séquences TYPE reproductibles entre boots et entre actions identiques ; nombre de 0xfe/0xfd lié à la quantité
  de données (ex. plus de morceaux quand il y a plus de doigts enrôlés). Si fausse : TYPE varie pour une même action,
  ou le nombre de 0xfe/0xfd est constant quelle que soit la donnée (→ doorbell / handshake, pas fragmentation).

## HB — DATA=0x1f5 dans les messages sbio SEP→AP spontanés = uid 501 de l'utilisateur
- Statut : ouverte
- Fondée sur : C1 l.428-430, 467, 510, 693, 699, 705, 1042, 1125, 1127 (SEP→AP, TAG 0x01/0x02) ; **et l.509 : c'est
  l'AP qui envoie 0x1f5** (`> TAG=0x26 TYPE=0x00 DATA=0x1f5`), suivi immédiatement d'une notification 0x01/0x11 0x1f5.
- Indice supplémentaire (à ne pas sur-interpréter) : EP 0x12 envoie spontanément `DATA=0xfffffe0b` (l.697, l.1124),
  et 0xfffffe0b = −501 en 32 bits signé. Ces deux messages tombent à moins de 1 ms d'une notification sbio 0x1f5
  (l.699, l.1125). Coïncidence possible ; mais si c'est l'uid, il apparaît sur deux endpoints.
- Autres explications possibles :
  1. Identifiant d'un objet SEP (session, handle de client, identifiant de jeu de gabarits) qui vaut 0x1f5 par hasard
     ou par construction ; un masque de bits (0b1_1111_0101).
  2. C'est bien 501, mais ce n'est pas « l'utilisateur connecté » : c'est le propriétaire des gabarits enrôlés,
     connu dès le boot. **Argument fort** : 0x1f5 apparaît déjà à l.428 (t=922, ~36 s après le début de trace),
     vraisemblablement **avant** le login mot de passe (que je place, sans preuve, vers t=974, voir HD).
  3. Les messages TAG 0x01..0x04 ne portent pas tous 0x1f5 : TAG 0x04 (l.321) et TAG 0x03 (l.1143) ont DATA=0.
     DATA pourrait donc être un argument d'événement qui vaut souvent 501 sans que ce soit sa définition.
- Combien de traces : 1, un seul compte utilisateur. Insuffisant.
- Expérience :
  - (EXPÉRIENCE HUMAINE, simple) Albert lance `id -u` dans Terminal sous macOS (pas de sudo) : 501 attendu.
  - (AUTO, C2) Boots sans login : si 0x1f5 apparaît quand même → pas lié à une session ouverte (alternative 2).
    Si 0xfffffe0b apparaît aussi sans login → idem pour EP 0x12.
  - (EXPÉRIENCE HUMAINE, lourde, plus tard) Second compte macOS (uid 502) avec un doigt enrôlé, login et unlock sur ce
    compte : attendu 0x1f6 et 0xfffffe0a. Modifie l'état du Mac (nouveau compte) : à décider par Albert.
- Si vraie : 0x1f6/0xfffffe0a avec le compte 502 ; 0x1f5 absent des messages liés au compte 502.
  Si fausse : 0x1f5 reste le même avec un autre compte, ou apparaît identique dans des contextes sans utilisateur.

## HC — Les rafales sbio de 03:36:58–03:37:00 et 03:37:15–03:37:16 correspondent au lock et à l'unlock doigt
- Statut : ouverte
- Fondée sur : C1 l.1042-1145 (t=1794019018.3–1020.4) et l.1224-1247 (t=1035.4–1036.3) ; signal d'Albert à
  t≈1040.97 (heure de son message, pas de l'action).
- Ce que les données montrent vraiment : **trois** zones d'activité sbio après l'init, pour **trois** actions humaines
  (login, lock, unlock) : t=973.8–974.8 (l.681-710), t=1018.3–1020.4, t=1035.4–1036.3. Aucun message sbio entre
  t=974.84 et t=1018.3.
- Autres alignements qui collent aussi :
  - A (celui de HC) : 974 = login, 1018–1020 = lock, 1035 = unlock doigt.
  - B : 974 = login ; le lock ne produit **aucun** message sbio ; 1018–1020 = unlock doigt (la commande 0x09 dure 240 ms
    et encadre une notification SEP 0x01/0x08, puis 0x70 dure 190 ms suivi d'un `TAG=0x03` spontané : profil d'une
    capture/comparaison qui attend le capteur) ; 1035 = travail après unlock (ex. mise à jour de gabarit, transfert
    0x6c en 0xfe/0xfd) ou tâche de fond.
  - C : une partie des rafales est de l'activité de fond périodique, sans lien avec l'humain.
  - Observation qui complique : les notifications sbio l.699 et l.1042 suivent chacune **une commande SKS TAG 0x18**
    (l.696-698, l.1040-1041), et l.1124 suit un message SKS spontané. Les « événements » sbio pourraient être déclenchés
    par un changement d'état SKS (keybag), pas par le doigt. De plus, les deux messages SKS 0xfffffe0b ont TYPE=0x01
    (l.697, t=974) puis TYPE=0x00 (l.1124, t=1020) : si TYPE=état (1 = déverrouillé, 0 = verrouillé ?), t=1020 serait le
    **lock** et non l'unlock — mais c'est une interprétation d'un seul bit sur deux messages.
- Combien de traces : 1, sans marqueur. Insuffisant ; l'attribution A/B/C est indécidable sur C1.
- Expérience : C3 avec marqueurs (protocole ci-dessous). Points décisifs : `lock1` suivi de 30 s sans rien toucher
  (sépare lock et unlock), `pw_unlock` (unlock sans doigt), `fp_good_1..3` (répétabilité), `fp_noprompt` (doigt sans demande).
  C2 (AUTO) donne le bruit de fond.
- Si vraie (A) : après chaque `lock_*`, rafale contenant 0x23/0x06/0x65/0x07/0x09/0x70 dans les ~2 s, **avant** que le doigt
  soit posé ; après chaque `fp_good_*`, rafale de type 0x6b/0x79/0x6c/0x37. Si B : après `lock_*` rien (ou presque) sur sbio,
  et la séquence 0x09/0x70 n'apparaît qu'après la pose du doigt. Si C : des rafales du même type apparaissent dans les
  fenêtres `idle*` et dans C2.

## HD (Q0) — Touch ID dépend d'un état créé par le login mot de passe via SKS (0x12)
- Statut : ouverte
- Fondée sur : C1. Avant t≈974, beaucoup de réponses SKS ont PARAM=0xfd et DATA=0 (ex. l.593-633) ; à partir de
  t≈974.6 (l.685-719) elles ont PARAM=0x00 et DATA non nul, avec deux messages SKS spontanés (l.639-641, l.697) et
  des échanges xART 0x13. Les premiers événements sbio « post-login » (l.693, 699, 705) sont collés à ces messages SKS.
  Lecture plausible : keybag verrouillé (0xfd = refus ?) → déverrouillé par le mot de passe. Non prouvé.
- Autres explications possibles :
  1. Dépendance **côté macOS** (politique logicielle : macOS exige le mot de passe après un redémarrage avant
     d'autoriser la biométrie) ; le SEP ferait la comparaison sans aucun état SKS. Pour Linux, ce serait la bonne nouvelle.
  2. Dépendance côté SEP, mais via xART (0x13) ou SCRD (0x0a), pas SKS ; SKS et sbio bougeraient ensemble parce que le
     login touche tout en même temps (corrélation, pas causalité).
  3. Dépendance côté SEP via un contenu OOL que le tracer ne voit pas : on verrait la même séquence mailbox avec un
     résultat différent.
  4. Pas de dépendance du tout : les messages sbio près des messages SKS sont des notifications de changement d'état
     de session diffusées à tous les clients.
- Combien de traces : 1, et un seul ordre d'actions (login → lock → unlock). On n'a jamais tenté le doigt **avant**
  le login. Insuffisant.
- Expérience :
  - (EXPÉRIENCE HUMAINE, C3 étape `fp_prelogin`) Bon doigt à l'écran de connexion, avant tout mot de passe.
    Trois issues : (i) aucun message sbio → macOS n'arme pas le capteur, on ne peut rien conclure sur le SEP ;
    (ii) séquence sbio de comparaison (0x09/0x70 ou ce que C3 montrera pour `fp_good_*`) **identique** à celle d'un bon
    doigt post-login, mais macOS refuse → dépendance côté AP (alternative 1) ; (iii) séquence présente mais **différente**
    (réponse ou notification différente, ou arrêt plus tôt) → dépendance côté SEP.
  - (AUTO, C6 single-user mode) sbio s'initialise-t-il (séquence l.320-449) sans aucune session utilisateur ni SKS bavard ?
  - Le test définitif (envoyer des commandes sbio sans avoir fait le login SKS) est une **écriture vers le SEP** :
    interdit aux agents. À rédiger plus tard dans `pending/` (phase 2+) si les observations ne suffisent pas.
- Si vraie : issue (iii) ; dans C2, sbio ne passe jamais à l'état observé après t≈974 ; l'init sbio ne se termine pas
  pareil en single-user. Si fausse : issue (ii), ou sbio identique avec et sans login.

## Ce que C2 (deux boots identiques sans action humaine) permettra d'éliminer
C2 = C2a et C2b, même m1n1, même kernel, mêmes bootargs, personne ne touche le Mac, arrêt à l'écran de connexion.
- **Champs non déterministes** : toute valeur qui diffère entre C2a et C2b à la même position de séquence est un nonce,
  un compteur, un handle ou un horodatage ; elle ne doit pas être utilisée pour aligner C3 sur C1 (`diff_traces.py` ignore déjà
  TAG/DATA ; vérifier si c'est justifié pour 0x08, où TAG semble constant). Exemples à surveiller : le point de départ du
  compteur TYPE de 0x12, les DATA des messages 0x13 `TYPE=0x01 PARAM=0x9c` (l.1122, 1140, 1243, 1245 : 0x0c5e, 0xb835,
  0x9d10, 0x1f75 — l'AP renvoie la même valeur, ce qui ressemble à un identifiant de requête ou un nonce), les
  `0xce5f3e75`/`0xfffffffa` de 0x12 (l.639-641).
- **HA** : si l'init sbio (l.320-449) est identique dans C2a et C2b (mêmes TYPE, même nombre de 0xfe/0xfd), le
  « TYPE = commande » survit à un premier test ; s'il varie, il tombe.
- **HB** : si 0x1f5 (sbio) ou 0xfffffe0b (SKS) apparaissent sans login, « uid de l'utilisateur connecté » tombe
  (reste possible : uid du propriétaire des gabarits, ou constante).
- **HC, alignement C** : si des rafales sbio du type t=1018–1020 ou t=1035 apparaissent dans C2 sans humain, ce sont
  des tâches de fond ; elles devront être retirées de toute interprétation de C1/C3.
- **HD** : C2 donne l'état SKS « jamais de login » (PARAM=0xfd persistant ?) et l'état sbio correspondant : référence
  pour l'étape `fp_prelogin` de C3.
- **Bruit de fond** : débit par endpoint quand personne ne fait rien (0x0a et 0x12 sont réguliers dans C1) → seuil
  pour dire qu'une rafale de C3 est « causée » par une action.
- C2 n'élimine **rien** sur le login, le lock, l'unlock ou le doigt : il ne contient aucune de ces actions.

## C3 — Touch ID (EXPÉRIENCE HUMAINE)
- Statut : prête, à lancer par Albert. Dépend de `tools/mark.sh` (en cours d'écriture par le tracer) : `./tools/mark.sh <étiquette>`
  écrit `<epoch> <étiquette>` dans `marks.txt` du dossier de capture en cours. Même horloge (PC) que `sep.log` → alignement direct.
- But : départager HA..HD en une seule session de boot, tous endpoints.
- Lancement : `./tools/boot_and_trace.sh c3-touchid --interactive` (SEP_EPS non défini = tous les endpoints).
  `--interactive` évite une coupure au milieu : la séquence dure ~10 min **après** l'écran de connexion, et le boot sous HV
  en prend déjà ~1,5 min. Si on reste en mode AUTO : `TRACE_TIMEOUT=1200`.
- Règles pour toute la session :
  - Le marqueur se pose sur le PC **juste avant** l'action (≤ 2 s avant). Une marque `*_ok` se pose dès que le résultat est visible.
  - Verrouiller **uniquement** au clavier par **Ctrl+Cmd+Q**. Ne jamais *appuyer* sur la touche Touch ID (c'est aussi le
    bouton marche/veille : l'appui verrouille/met en veille et touche le capteur en même temps).
  - Poser le doigt = poser à plat, sans appuyer, ~2 s, puis retirer.
  - Pendant les fenêtres `idle*` : ne toucher **ni** le Mac **ni** son trackpad pendant 30 s. Le PC peut servir (marques).
  - Bon doigt = doigt enrôlé. Mauvais doigt = doigt jamais enrôlé (le même aux deux essais).
  - Noter sur papier, pour chaque étape : ce que macOS affiche, succès/échec, toute anomalie (gel, lenteur, panic).
  - Si macOS passe en « mot de passe requis » plus tôt que prévu, ou si l'écran s'éteint : poser `./tools/mark.sh anomalie`,
    le noter, et continuer à l'étape suivante.
- Étapes :
  1. `./tools/mark.sh loginwin` — dès que l'écran de connexion est affiché. Ne rien toucher. Attendu : rien de spécial.
  2. `./tools/mark.sh idle0` — 30 s sans rien toucher. Attendu : bruit de fond seul (référence, avec C2).
  3. `./tools/mark.sh fp_prelogin` — poser le **bon doigt** à l'écran de connexion, avant le mot de passe ; noter ce que
     macOS affiche. Attendu : test HD (issues i/ii/iii). Probablement « mot de passe requis ».
  4. `./tools/mark.sh idle1` — 30 s sans rien toucher.
  5. `./tools/mark.sh pw_login` — taper le mot de passe + Entrée. `./tools/mark.sh pw_login_ok` dès que le bureau est là.
     Attendu : rafale SKS/xART + notifications sbio comme t≈974 dans C1 (passage PARAM 0xfd → 0x00 sur 0x12).
  6. `./tools/mark.sh idle2` — 30 s sans rien toucher (laisser le login « retomber »).
  7. `./tools/mark.sh lock1` — Ctrl+Cmd+Q. Attendu : signature du lock seul (HC : A = rafale 0x09/0x70 ; B = rien).
  8. `./tools/mark.sh idle3` — 30 s, écran verrouillé, sans rien toucher. Attendu : rien de neuf sur sbio, sinon c'est de l'attente capteur.
  9. `./tools/mark.sh pw_unlock` — mot de passe + Entrée. `./tools/mark.sh pw_unlock_ok` au bureau.
     Attendu : unlock **sans doigt** ; la différence avec les étapes 11-13 = ce qui est propre à Touch ID.
  10. `./tools/mark.sh idle4` — 30 s sans rien toucher.
  11. `./tools/mark.sh lock_f1` — Ctrl+Cmd+Q ; `./tools/mark.sh idle_f1` — 30 s sans rien toucher ;
      `./tools/mark.sh fp_good_1` — bon doigt ; `./tools/mark.sh fp_good_1_ok` au bureau ; `./tools/mark.sh idle_f1b` — 30 s.
  12. Idem avec `lock_f2`, `idle_f2`, `fp_good_2`, `fp_good_2_ok`, `idle_f2b`.
  13. Idem avec `lock_f3`, `idle_f3`, `fp_good_3`, `fp_good_3_ok`, `idle_f3b`.
      Attendu (11-13) : la même séquence sbio trois fois (test HA) ; position du 0x09/0x70 par rapport à `lock_f*` et
      `fp_good_*` (test HC A/B).
  14. `./tools/mark.sh lock_bad` — Ctrl+Cmd+Q ; `./tools/mark.sh idle_bad` — 30 s sans rien toucher.
  15. `./tools/mark.sh fp_bad_1` — **mauvais doigt**, ~2 s, retirer ; attendre 10 s ;
      `./tools/mark.sh fp_bad_2` — mauvais doigt, ~2 s, retirer ; attendre 10 s.
      Attendu : même début de séquence que `fp_good_*`, puis divergence. Si **aucune** différence dans les mots mailbox entre
      bon et mauvais doigt, le résultat de la comparaison passe par l'OOL → limite du tracer actuel, à noter.
  16. `./tools/mark.sh pw_after_bad` — mot de passe + Entrée ; `./tools/mark.sh pw_after_bad_ok` au bureau ;
      `./tools/mark.sh idle5` — 30 s. Attendu : comme l'étape 9, éventuellement + remise à zéro du compteur d'échecs.
  17. `./tools/mark.sh fp_noprompt` — session ouverte, aucune demande d'authentification à l'écran : bon doigt ~2 s, retirer.
      Attendu : si rien sur sbio, le capteur n'est armé que quand macOS le demande ; si une notification sbio arrive, le SEP
      détecte le doigt de lui-même.
  18. `./tools/mark.sh idle6` — 30 s sans rien toucher.
  19. `./tools/mark.sh end` — puis arrêter la capture (Ctrl-C → shell HV → `reboot()` en mode interactif).
- Après la capture : Albert reporte ses notes papier (résultats, messages macOS, anomalies) dans `docs/journal.md` ou les
  dicte à un agent ; `traces/<dossier C3>/` devient en lecture seule.
- Comparaisons prévues (analyste) : fenêtres `fp_good_*` entre elles (répétabilité), `fp_good_*` vs `pw_unlock`,
  `fp_good_*` vs `fp_bad_*`, `lock1` vs `lock_f*`, `fp_prelogin` vs `fp_good_*`, toutes les `idle*` vs C2.
- Ce que C3 ne tranche pas : le contenu OOL ; HB (un seul compte) ; la cause (et non la simple corrélation) de HD.
