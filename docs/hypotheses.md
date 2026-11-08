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

# Hypothèses issues de C8 (2026-11-08, analyste)

C8 = `traces/20261108-004657_c8-doigt-ool` ; détail et lignes citées : `docs/messages.md` section C8,
`analysis/out/c8_ool_attempts.txt`, `analysis/out/c8_attempts.txt`. C6 = `traces/20261107-043828_c6-doigt-ool`.
> Revue sceptique 2026-11-08 : section « Revue sceptique de C8 » plus bas (artefact `ool_index.py`, HK-HO, protocole C10).
> HI a une alternative concurrente (HO) qui change la lecture de C9.

## HE — Le résultat de la comparaison doigt est dans la réponse OOL de 0x09 (`< B`), pas dans le mot mailbox
- Statut : ouverte
- Fondée sur : C8 `< B 0x09` L1731, L2428, L2999 (succès : `+0x00`=0x1f5, 16 octets `fe6003d8…371b`, `+0x1c`=1,
  `+0x2c..+0xc1f` = réponse 0x54 de l'init L556) vs L3647, L3711, L4247 (échecs : 0xffffffff, zéros) ; C6 5/5 refus
  identiques aux échecs C8. Mot mailbox 0x09 identique (PARAM=0, DATA=0) dans tous les cas.
- Autres explications possibles : le SEP écrit le même contenu pour une autre raison (ex. compte-rendu à destination
  d'un démon, le vrai verdict passant par SKS 0x12 — la notif `TAG=0 DATA=0xfffffe0b` n'apparaît que dans les succès) ;
  l'association A/B ↔ sens reste une hypothèse du tracer.
- Expérience (AUTO, sans humain) : relire chaque future capture doigt avec `analysis/ool_attempts.py` et tester la
  règle « `+0x00`==0x1f5 ⇔ 2× `<01/08` ⇔ UNLOCKED » sur toutes les tentatives (prédiction : 0 exception).
- Expérience (EXPÉRIENCE HUMAINE, décision d'Albert) : enrôler un **second doigt** dans macOS, puis session C8 avec doigt 1,
  doigt 2, mauvais doigt. Si les 16 octets changent avec le doigt → identifiant de gabarit ; s'ils restent égaux →
  identifiant d'utilisateur/de base. Prédiction HE : `+0x00`=0x1f5 pour doigt 1 et doigt 2, -1 pour le mauvais.
- Si vraie : un driver Linux lirait le verdict dans B après `< 0xfc 0x09`. Si fausse : chercher dans SKS (0x12).

## HF — `+0xc24` (u32) de la réponse 0x09 est un code de raison ou un score, pas un booléen
- Statut : ouverte
- Fondée sur : succès 2, 2, 1 (C8) ; mauvais doigt 0x2e ×3 (C8 L3647, L3711, L4247) ; bon doigt refusé 5, 5, 0x1b, 6, 0x1b (C6).
- Autres explications possibles : compteur interne ; valeur qui dépend du temps d'acquisition (C6 = tracer lent).
- Expérience (EXPÉRIENCE HUMAINE) : 3 essais de chaque : bon doigt à plat, bon doigt seulement le bout, bon doigt
  glissé, mauvais doigt, objet non-doigt (gomme). Prédiction « code » : une valeur stable par type d'échec ;
  « score » : valeurs dispersées et ordonnées selon la qualité.

## HG — La réponse 0x07 décide abandon (`22`) ou comparaison (`09`) ; `+0x06..+0x07` = `01 01` si on compare
- Statut : ouverte
- Fondée sur : `01 01` dans 11/11 tentatives suivies de 0x09 (C8 6, C6 5), `00 00` dans 4/4 abandons (C8 L1692, L2369,
  L2393 ; C6 L1791). `+0x02` = 2 dans 4/4 abandons mais aussi 3 dans un cas continué (L2417) : moins net.
- Autres explications possibles : l'AP abandonne pour une autre raison (timeout, doigt retiré) et 0x07 ne fait que
  le refléter. 4 abandons seulement.
- Expérience (EXPÉRIENCE HUMAINE) : toucher le capteur très brièvement (< 0.3 s) 5 fois pour provoquer des abandons ;
  prédiction : `00 00` à chaque `23 06 65 07 22`. AUTO : vérifier sur toutes les captures futures.

## HH — TYPE 0x65 (`> A`, 0x7200 octets) = 12 trames capteur chiffrées ou compressées
- Statut : ouverte (le contenu n'est PAS interprétable ; seule la structure est testée)
- Fondée sur : 12 blocs de 0x980 o, en-tête de 0x17 o constant sauf index de bloc NN et compteur SSSS ; corps 7.99 bits/o,
  ratio zlib 1.001 ; NN continue après un abandon, repart à 0 après une tentative complète ; SSSS saute de +0xd (C8, 6/6)
  ou +0x18 (C6, 4/4) après une tentative complète.
- Autres explications possibles : le corps est du bruit ou des données déjà compressées ; les sauts SSSS viennent de trames
  envoyées ailleurs (autre TYPE, autre buffer) ou consommées par le SEP lui-même.
- Expérience (AUTO, analyse) : chercher dans C8 tout message entre la fin d'une tentative complète et la suivante dont
  le contenu porte des blocs `80 52 .. 80 09 00 00 3a` (expliquerait les sauts). Ne pas tenter de déchiffrer (hors périmètre).

## HI — L'enregistrement 0xbf4 renvoyé par 0x54 à l'init est un état persistant mis à jour après un succès
- Statut : ouverte
- Fondée sur : réponse 0x54 identique dans C5, C6, C7, C8 (aucun succès Touch ID entre C5 et C8 ; C6 = 5 refus) ;
  dans C8, la copie dans la réponse 0x09 est identique pour fp_good_1 et diffère de 20 octets (offsets 0x3a-0x42, 0x8a-0x90,
  0xe4-0xea, 0xbea-0xbef de l'enregistrement) pour fp_good_2 et fp_good_3, après les rafales post-unlock `6b 79 6c 37…`.
- Autres explications possibles : ces 20 octets sont des compteurs/horodatages recalculés à chaque réponse, sans persistance.
- Expérience (AUTO via `tools/boot_and_trace.sh`, sans humain, boot seul comme C7) : prochain boot avec SEP_OOL_EPS=0x08 et
  0x54 dans les types complets ; comparer la réponse 0x54 de l'init à `analysis/out/c8_payloads/L02968_good_outB_09.bin`
  [0x2c:0xc20]. Égale à fp_good_3 → état persistant mis à jour ; égale à C5 → pas de persistance (ou non écrite).
  Ne demande aucune écriture vers le SEP.

## HJ — Les champs `+0x44` et `+0x48` de la requête 0x06 sont fixés par l'AP avant la comparaison
- Statut : ouverte
- Fondée sur : `+0x44` = 4 (6 tentatives lock_g*), 5 (3 tentatives lock_b*), 1 (C6, 6/6) ; `+0x48` = nombre d'abandons
  depuis la dernière tentative complète (15/15) ; `+0x97..+0xa6` (16 o) fixes par verrouillage. Ces valeurs précèdent 0x09 :
  elles ne peuvent pas être le résultat de la tentative en cours.
- Point de vigilance : `+0x44` sépare parfaitement bon et mauvais doigt dans C8 **par coïncidence de calendrier**
  (bons doigts d'abord, mauvais ensuite). Ne pas en faire un indice de succès.
- Expérience (EXPÉRIENCE HUMAINE) : session alternée bon / mauvais / bon / mauvais (un essai par verrouillage) ; si `+0x44`
  suit le temps ou le nombre de déverrouillages et non le doigt, la coïncidence est confirmée.

---

# Revue sceptique de C8 (2026-11-08, agent sceptique)

Sources relues : `traces/20261108-004657_c8-doigt-ool/sep.log` (L1674-1789, L3618-3687, L3826-3871), `marks.txt` ;
`traces/20261107-043828_c6-doigt-ool/sep.log` (lectures A et B à chaque message, L323-357, L1000-2339, L1803-1814) ;
`analysis/out/c8_ool_attempts.txt`, `c8_ool_index.txt`, `c8_uart_align.md` ; `analysis/ool_index.py` ;
`hv/trace_sep_filtered.py` (`_ool_dump`, docstring). Aucune action hardware, aucun binaire Apple lu.
Correspondance avec la demande : 1 = HE + HF, 2 = HK, 3 = HG, 4 = HH, 5 = HL, 6 = HM. Nouvelles : HN, HO.

## Réserves communes à toutes les hypothèses C8
- **Une seule session, un seul ordre** : 3 bons doigts d'abord, puis 2 mauvais (dont 1 après un mot de passe). Tout ce qui
  sépare « bon » de « mauvais » dans C8 sépare aussi « début » de « fin » de session, `+0x44`=4 de `+0x44`=5, « avant » et
  « après » pw_unlock_1, et « attente lock→doigt ~10-25 s » de « ~21-30 s » (marks.txt : lock_b1→fp_bad_1 = 30.4 s).
  Seul C6 (5 refus bon doigt, autre tracer, plus lent) casse en partie cette confusion.
- **Petits effectifs** : 3 succès, 3 échecs mauvais doigt, 4 abandons (C8 3 + C6 1). Une règle « 3/3 » a une chance non
  négligeable d'être une coïncidence si le champ a peu de valeurs possibles (octet 0/1 : 1 chance sur 8 par sens).
- **Instantanés** : `>` lit A avant que m1n1 ne rejoue l'écriture INBOX (le SEP n'a pas encore le message) ; `<` lit B
  **après** le dépilement (le SEP tourne pendant la lecture, docstring du tracer). Une lecture B sur une notification ou sur
  un `<fe` peut tomber en pleine écriture : fp_good_1 L1730 (`<01/08`) voit B **entièrement nul**, fp_good_2/3 voient déjà
  le début de la réponse 0x09. Ne jamais interpréter le contenu B d'un message sans charge propre.
- **Artefact d'outil trouvé (à corriger avant toute nouvelle conclusion)** — `analysis/ool_index.py` L37-61 :
  `last_file` est indexé par buffer seulement, alors que le tracer compare les lectures **par (EP, buffer, longueur)**
  (`key = (ep, name, len(blob))`, tracer L580). Pour une ligne `changed=none`, l'outil rattache donc parfois le .bin d'une
  lecture d'une **autre longueur** et affiche un contenu faux. Deux cas vérifiés dans le log brut :
  - L1684/L1685 `<fe 0x65` : log `sha=4fe7b59a nz=0` (= 0x4000 zéros), l'index affiche `end=0x15 (=001483_08_B.bin)`
    (en-tête 0x06, lecture 0x400). Les « 5× `< B 0xfe/0x65` avec l'en-tête 0x06 précédent » de `docs/messages.md` sont
    cet artefact : B est **vide** (tout à zéro) à ces `<fe`.
  - L3836/L3837 et L3866/L3867 `> 0x70` (pw_unlock_1) : log `sha=fc765c2e`, le **même** sha que L1749 (`> A 0x70` d'un
    essai doigt, `changed=0x14+0x1` depuis l'en-tête 0x0b) : A contient l'en-tête **0x70**, pas 0x21.
  Conséquence : les 7 « exceptions » de l'en-tête (HK) ne sont pas des exceptions ; toute affirmation « B identique au B
  précédent » sur des lignes `changed=none` est à refaire. Test rapide : pour chaque ligne `none`, comparer le `nz` du
  log au `nz` du fichier rattaché ; une différence = rattachement faux. Les charges des tentatives (`c8_payloads/`) ont
  toutes un `file=` propre dans le log (vérifié pour 0x06/0x07/0x09/0x21/0x65 de L1674-1785 et L3621-3686), donc HE..HJ
  ne sont pas touchées sur le fond — à reconfirmer après correction.

## HE (+ HF) — Revue : la réponse 0x09 code le résultat
- Ce qui tient (vérifié dans le log brut) :
  - le contenu est **frais** : la lecture B 0x4000 précédente (`<fc 0x65`, L1713 et L3636) est nulle sauf 2 octets d'en-tête ;
    l'enregistrement 0xbf4 des succès n'est donc pas un reste de la réponse 0x54 de l'init resté dans B ;
  - la lecture `<fc 0x09` est fiable : le SEP poste la réponse après l'avoir écrite, et le B suivant ne change qu'au `> 0x1f` ;
  - la règle tient sur **11/11** tentatives complètes (C8 6, C6 5), dans deux captures, avec deux réglages du tracer.
- Autres explications :
  1. **Conséquence du déverrouillage du keybag, pas du match** : dans les 3 succès, `< EP=0x12 TAG=0 DATA=0xfffffe0b`
     (L1728) arrive **avant** `<fc 0x09` (L1731) dans la même file OUTBOX (ordre fiable). Le SEP pourrait ne remplir
     l'enregistrement que parce que le keybag 501 vient d'être déverrouillé. Pour un driver Linux (pas de SKS), ça change
     tout. C8 ne peut pas séparer les deux : match et déverrouillage vont toujours ensemble.
  2. **« -1 » = « pas de succès », pas « pas de correspondance »** : C6 (bon doigt refusé, tracer lent) donne aussi -1 mais
     `+0xc24` = 5/5/0x1b/6/0x1b, alors que le mauvais doigt donne 0x2e ×3. Le -1 marque l'issue, la cause est ailleurs.
  3. `+0xc24` (HF) : 0x2e **identique 3/3** pour le mauvais doigt plaide pour un **code** (un score de distance varierait
     d'un essai à l'autre) ; succès 1/2 et C6 5/6/0x1b restent compatibles avec code ou score. Confusion à lever : pour les
     succès, 2, 2, 1 suit « au moins un abandon avant dans ce verrouillage » (`+0x48` de 0x06 = 1, 2, 0) — compte de lots de
     trames ou de tentatives plutôt que qualité ? 3 points, non tranchable.
- Combien de traces : C8 + C6 pour la règle -1/0x1f5 ; une seule capture avec des succès OOL.
- Expériences (ordre de coût) :
  - (SANS HARDWARE) tabuler `+0xc24` contre `+0x48`/`+0x07` de 0x06, `+0x02`/`+0x06..07`/`+0x28` de 0x07 et la durée 0x09,
    sur C6 + C8. Si `+0xc24` (succès) = f(`+0x48`) exactement → compteur, pas qualité.
  - (EXPÉRIENCE HUMAINE, C10 étapes `fp_app_good` / `fp_app_bad`) Touch ID **session ouverte** (invite d'authentification,
    keybag déjà déverrouillé). Si vraie (verdict) : B 0x09 = 0x1f5 + identifiant pour `fp_app_good`, -1 pour `fp_app_bad`,
    **sans** `< EP=0x12 TAG=0 DATA=0xfffffe0b`. Si alternative 1 : B = -1 (ou différent) alors que macOS accepte, ou la notif
    -501 réapparaît à chaque succès (→ c'est un « événement d'authentification », pas un changement d'état du keybag).
  - (EXPÉRIENCE HUMAINE, C10 étape `fp_tip_*`) bout du doigt seulement : refus attendus avec des codes ≠ 0x2e si `+0xc24`
    est un code de raison ; un éventail de valeurs ordonnées si c'est un score.

## HK — En-tête OOL commun de 0x1c octets (1, total, offset, 0, 0, TYPE, longueur du morceau)
- Ce qui tient : 480 lectures C8 + C5/C6/C7 ; offsets k·0x3fe4 (= 0x4000 − 0x1c) dans les `0xfd` des deux sens (0x65 A,
  0x5f B, 0x5b/0x6d A, 0x6c B) ; fin du contenu = 0x1c + longueur sans exception. Avec l'artefact corrigé ci-dessus, les
  « exceptions » disparaissent : `<fe` = B **entièrement nul** (pas d'en-tête du tout), `> 0x70` = en-tête 0x70.
  C'est l'hypothèse la mieux soutenue structurellement, et elle réfute l'alternative « doorbell sans fragmentation » de HA
  (point 3) pour 0x65/0x5b/0x6d/0x5f/0x6c : les morceaux successifs ont des contenus différents et un champ offset.
- Ce qui reste fragile : la **sémantique** de `+0x00` (version ? drapeau « contenu présent » ? : il vaut 0 exactement quand
  le buffer a été remis à zéro, ce qui colle mieux à un drapeau) ; `+0x0c`/`+0x10` toujours 0 (statut ? identifiant de
  transaction ? inconnu) ; qui remet les buffers à zéro (AP après lecture ? SEP ?) — C6 montre B nul à **chaque** `>` et A
  remis à zéro seulement autour de 6 notifications (L1000, L1022, L1667, L1880, L2199, L2339).
- Expérience (SANS HARDWARE) : script d'invariants sur C5..C9 : TYPE en-tête = TYPE mot mailbox ; Σ longueurs des morceaux =
  total ; longueur morceau = min(0x3fe4, total − offset) ; `+0x0c`, `+0x10` ≠ 0 au moins une fois ? ; `+0x00` = 0 ⇔ buffer
  tout nul ? Si une seule violation hors `<fe`/notifications → réviser HK. (BOOT SANS HUMAIN) rien de plus à attendre de
  C9/C10 que des effectifs.

## HG — Revue : 0x07 `+0x06..07` = `01 01` → 0x09, `00 00` → abandon
- Confusions écartées (vérifié sur les valeurs publiées) : le drapeau fourni par l'AP `+0x07` de 0x06 (1 si `+0x48`=0) ne
  prédit pas l'abandon (L1674 abandon avec `+0x48`=0, L2375 abandon avec `+0x48`=1, L2968 continué avec `+0x48`=0).
- Autres explications : l'AP abandonne pour une raison qu'il connaît par ailleurs (doigt retiré, signal capteur via AOP) et
  le SEP ne fait que constater ; dans les deux cas l'octet **prédit** l'abandon, mais la causalité n'est pas observable sans
  écrire vers le SEP. Pour un driver, la prédiction suffit si elle tient. 4 abandons, dont 3 « premier essai après lock ».
  `+0x28` = 1 pour le mauvais doigt est confondu avec `+0x44`=5 (fourni par l'AP, recopié dans 0x07 à `+0x48`) : il peut
  dépendre du paramètre de session et non du doigt.
- Expériences : (SANS HARDWARE) C6 + C8, tabuler `+0x02`, `+0x06..07`, flottants `+0x18..` pour abandon vs continué.
  (EXPÉRIENCE HUMAINE, C10 `fp_tap_1..3`) effleurements < 0.3 s : prédiction `00 00` dans chaque `23 06 65 07 22`, `01 01`
  dans chaque tentative qui va jusqu'à 0x09. Une seule exception réfute « `+0x06..07` décide ». C10 cycle 1 (mauvais puis
  bon doigt dans le **même** verrouillage, donc même `+0x44`) : si `+0x28` vaut 1 puis 0 → lié au doigt ; 1 et 1 ou 0 et 0
  → lié au verrouillage.

## HH — Revue : 0x65 = relais AP→SEP de trames capteur chiffrées
- Ce qui tient (C6, lecture des deux buffers) : L1806-1811, au `<fe 0x65` A est **inchangé** (morceau 1) et B nul ; au
  `> 0xfd` suivant A contient le morceau 2. Le morceau 2 apparaît donc entre le dépilement du `<fe` par l'AP et l'écriture
  `> 0xfd` : écrit par l'AP (le SEP n'écrit A dans aucun des 156/162 `< A` de C6). Le sens AP→SEP est bien soutenu.
- Ce qui n'est pas soutenu : « données capteur ». Rien ne relie le contenu au capteur sinon la corrélation temporelle avec
  le doigt et la taille fixe. L'AP pourrait produire lui-même ce contenu (traitement côté noyau, ou paquet chiffré par le
  capteur et seulement relayé : indiscernable ici). Taille 0x7200 **identique** pour abandon et tentative complète : la
  quantité ne dépend pas de la qualité du contact.
- Sur les compteurs : le saut SSSS est **constant** (+0xd, 6/6) alors que la durée de 0x09 varie de 235 à 303 ms et que la
  fin de tentative varie (`<03` à 0-166 ms) → ce n'est pas un compteur de temps à cadence fixe ; plutôt un nombre fixe de
  trames/paquets consommés ailleurs. C6 (+0x18, 4/4) diffère : réglage du tracer, ou paramètre `+0x44` (1 dans C6) ?
- Expériences : (SANS HARDWARE) celle de l'analyste (chercher des blocs `80 52 .. 80 09 00 00 3a` hors 0x65) + vérifier si le
  saut SSSS de C8 dépend de `+0x44` (4 vs 5 : +0xd dans les deux → non) et si celui de C6 dépend de `+0x44`=1.
  Pour relier au capteur il faudrait observer le chemin capteur→AP (AOP/SPI) : outillage à concevoir par le tracer, en
  lecture seule ; hors de portée immédiate. Ne pas tenter d'interpréter le corps (chiffré : hors périmètre).

## HL — « Sending lock change X for handle H value V » ↔ `< EP=0x12 TAG=X TYPE=V DATA=H` ; notif -501 seulement en succès
- Ce qui tient : la concordance **des valeurs** est indépendante de l'horloge : handles 32 bits non triviaux (0xce5f3e75 =
  -832618891 recalculé, 0xfffffffa = -6, 0xfffffe0b = -501) dans C8 29/29, C3 34/34, C1 6/6. C'est l'hypothèse la plus solide.
- Ce qui est en partie **circulaire** : les 29 « lock change » de C8 sont **eux-mêmes** des ancrages de l'alignement
  (`c8_uart_align.md` §1). L'accord d'**ordre** ne prouve donc que la cohérence avec les 69 ancrages xART indépendants
  (0 rejet), ce qui reste un bon signe, pas une preuve. `TYPE = value` repose sur **une** occurrence V=1 par capture (3 au
  total, toutes au login) ; `PARAM=1 = volume` est déduit du type de handle.
- « -501 seulement en succès » : vrai 3/3 vs 0/3, mais la notif apparaît aussi au mot de passe : c'est un marqueur de
  déverrouillage de session, pas du match (voir HE alternative 1). Point important pour Linux : en succès doigt, aucune
  requête `> EP=0x12` propre au succès ne la précède (`> 0x12 TAG=0x48` existe aussi en échec, L3645) → le SEP semble
  déverrouiller de lui-même pendant 0x09. « Non sollicité » ne vaut que pour les EP tracés et les mots mailbox (pas l'OOL
  de 0x12, non lu).
- Expérience (SANS HARDWARE, BOOT SANS HUMAIN C9) : **prédiction préenregistrée** : avant d'ouvrir `hv_uart.log` de C9, écrire
  depuis `sep.log` seul la liste des lignes « Sending lock change X for handle H value V » attendues, puis comparer.
  Si vraie : 100 % ; une seule ligne manquante ou en trop → réviser. (EXPÉRIENCE HUMAINE C10 `fp_app_*`) : présence ou
  absence de la notif -501 quand le keybag est déjà déverrouillé (prédiction HL : **absente**).

## HM — A = AP→SEP, B = SEP→AP (biais de mesure du tracer ?)
- Le biais existe dans C7/C8 (`split_dir=1` : `>` ne lit que A, `<` que B) : un contenu écrit par le SEP dans A, ou par l'AP
  dans B, serait invisible. Mais **C5 et C6 lisaient les deux buffers à chaque message** (journal 2026-11-07 tracer) : `> B`
  nul 71/73 et 141/143, `< A` inchangé 78/78 et 156/162 (les 6 autres = remise à zéro de A, toutes sur des notifications
  SEP, liste ci-dessus). C6 couvre des tentatives doigt complètes (0x65 en morceaux, 0x07, 0x09). L'association tient donc
  pour tout ce que C6 contient.
- Ce qui n'est **pas** couvert : le chemin succès (C6 n'a aucun succès) : 0x6c (B, 3 morceaux après chaque succès), 0x37,
  0x0b ; et la question « qui remet à zéro ». La nomenclature A = CNTL TYPE 2/4, B = 3/5 reste une hypothèse (C4).
- Expérience (BOOT SANS HUMAIN, C10-boot) : `SEP_OOL_SPLIT_DIR=0` sur un boot seul (init 0x5b/0x6d/0x54/0x5f) : coût ~0.2 ms
  par message en plus. Si `> B` est nul et `< A` inchangé partout → HM tient aussi à l'init. Pour le chemin succès : à faire
  plus tard, **pas** dans la session humaine C10 (ne pas changer deux réglages à la fois ; C6 lent = bon doigt refusé).

## HN — Les 16 octets `fe6003d8…371b` sont un UUID v4 (identifiant d'utilisateur macOS ?) et non un identifiant de gabarit
- Statut : ouverte (nouvelle, sceptique)
- Fondée sur : C8 L554 (`> A 0x54` : l'**AP** envoie `f5010000` + ces 16 octets **avant** toute tentative : l'AP les connaît,
  ils ne sortent pas d'un match) ; lus comme UUID : `fe6003d8-cea5-414f-b48a-0338dc7c371b` → quartet de version = 4 et
  variante `b` (10xx), le format d'un UUID aléatoire RFC 4122. Probabilité d'avoir les deux par hasard : 1/64. Indice, pas preuve.
- Autres explications : UUID d'un objet biométrique (jeu de gabarits, « identité » LocalAuthentication) ou du keybag.
- Expérience (EXPÉRIENCE HUMAINE, 30 s, aucune écriture) : dans Terminal sous macOS, `id -u` et
  `dscl . -read /Users/$(id -un) GeneratedUID`. Si l'UUID affiché = `FE6003D8-CEA5-414F-B48A-0338DC7C371B` → identifiant
  d'utilisateur (et `+0x00`=0x1f5 = uid, renforce HB) ; sinon → objet SEP/biométrique (le 2e doigt de HE trancherait alors).

## HO — Alternative à HI : la base de gabarits est stockée par macOS et poussée au SEP à chaque boot
- Statut : ouverte (nouvelle, sceptique)
- Fondée sur : C8 index : à l'init, gros transferts **AP→SEP** `> A 0x5b` (4 morceaux) et `> A 0x6d` (3 morceaux) ;
  après chaque succès, transfert **SEP→AP** `< B 0x6c` (3 morceaux, L1906-1917, L2637-2648, L3224-3235 ; lu tronqué à
  0x400, `trunc=1`) puis `0x37` pendant lequel le noyau écrit 2 « Saving USER-xART » (anti-rejeu). Les 20 octets qui changent
  dans l'enregistrement (HI) n'apparaissent qu'**après** la première rafale `6b 79 6c 37`. Paire de TYPE voisins 0x6c/0x6d.
- Lecture : le SEP exporte une base mise à jour (chiffrée) via 0x6c, macOS la sauve, puis la renvoie au boot via 0x6d/0x5b,
  l'xART empêchant le rejeu d'une vieille version. Si c'est ça, un driver Linux devra **stocker et renvoyer** ce blob.
- Pièges pour C9 : (a) C8 s'est terminé par un `reboot()` de l'hyperviseur (arrêt non propre) ~165 s après le dernier succès :
  une sauvegarde non vidée sur disque donnerait un faux négatif ; (b) tout usage de Touch ID en boot natif entre C8 et C9
  fausserait la comparaison → **demander à Albert** s'il y en a eu.
- Expériences : (SANS HARDWARE, dès maintenant) dans C8, comparer `+0x04` (longueur totale, lisible dans l'en-tête même
  tronqué) des `< B 0x6c` post-succès avec celle de `> A 0x6d` et `> A 0x5b` à l'init. Longueurs égales → fort indice HO.
  (C9, en cours) comparer les `> A 0x5b`/`0x6d` de l'init C9 à ceux de C5/C6/C7/C8 (sha des .bin) en plus de la 0x54 de HI.
  Tableau de décision :
  | 0x54 C9 | 0x5b/0x6d C9 vs C8 init | Conclusion |
  |---|---|---|
  | = fp_good_3 | différents | HO : état stocké par macOS, renvoyé au boot (et mis à jour) |
  | = fp_good_3 | identiques | état persistant côté SEP (xART/stockage SEP), HI sans HO |
  | = C5..C8 | identiques | pas de persistance, ou sauvegarde perdue (piège a) : refaire après un arrêt propre |
  | = C5..C8 | différents | incohérent avec les deux : relire l'outillage avant d'interpréter |
  (C10, réglage) ajouter 0x6c à `SEP_OOL_FULL_TYPES` pour lire le blob exporté en entier et le retrouver (ou non) octet pour
  octet dans le `> A 0x6d`/`0x5b` du boot suivant (C11-boot sans humain).
- **Résultat C9 (analyste, 2026-11-08) : ligne 1 du tableau → HO soutenue, HI à reformuler.** 0x54 C9 = copie 0x21 de
  fp_good_3 (0 octet différent hors 0x06-0x2d) ; `> A 0x5b` C9 = C5..C8 (inchangé) ; `> A 0x6d` C9 **changé** : petit blob
  (0xf4) = export `< B 0x6c` C8 L3250 (même sha 5965c621), gros blob de 0x9317 o = longueur de l'export L3226, 0x3e4 premiers
  octets identiques (seuls lus). Statut : hypothèse (1 boot, export lu tronqué) ; la persistance passe par le stockage côté
  macOS, rien n'indique un stockage propre au SEP. Reste à faire : lecture complète de 0x6c (réglage ci-dessus) et C10/C11.
  Détail : `docs/messages.md`, section « 0x6c / 0x6d / 0x5b / 0x5f ».

## HJ — Revue
- Rien à ajouter sur le fond : la confusion `+0x44` / ordre de session est réelle. Elle contamine aussi `+0x28` et `+0x48`
  de la réponse 0x07 (recopies). C10 cycle 1 (mauvais puis bon doigt dans le même verrouillage) la tranche à moindre coût
  qu'une session entièrement alternée : `+0x44` identique pour les deux doigts → paramètre de verrouillage, pas de doigt.

## Ordre des expériences (du moins cher au plus cher)
1. **SANS HARDWARE (analyste, maintenant)** :
   a. corriger `analysis/ool_index.py` (`last_file` indexé par (buffer, longueur)), régénérer `c8_ool_index.txt`, reconfirmer
      les lignes de `docs/messages.md` qui s'appuient sur des lectures `changed=none` (en-tête « 7 exceptions », notifications) ;
   b. invariants d'en-tête HK sur C5..C8 ;
   c. HO : `+0x04` de `< B 0x6c` vs `> A 0x6d`/`0x5b` (C8) ;
   d. HF/HG : tableau `+0xc24` / 0x07 / 0x06 sur C6 + C8 ;
   e. HL : préparer la liste prédite des « lock change » de C9 depuis `sep.log` avant de lire `hv_uart.log`.
2. **BOOT SANS HUMAIN** : C9 (en cours) → HI + HO (tableau ci-dessus) + HL (prédiction) ; puis C10-boot avec
   `SEP_OOL_SPLIT_DIR=0` (HM à l'init). Avant d'interpréter C9 : Albert confirme l'absence d'usage Touch ID natif depuis C8.
3. **EXPÉRIENCE HUMAINE C10** (une session, ≤ 10 min après l'écran de connexion) — protocole ci-dessous.
4. **Décisions d'Albert (modifient l'état du Mac)** : enrôler un 2e doigt (HE/HN) ; 2e compte (HB). Seulement si HN ne tranche pas.

## C10 — Session doigt « tranchante » (EXPÉRIENCE HUMAINE, ≤ 10 min)
- Réglages capture (tracer) : comme C8 (`SEP_OOL_EPS=0x08`, `SEP_OOL_BYTES=0x400`, `SEP_OOL_SPLIT_DIR=1`), types complets
  = ceux de C8 **+ 0x6c** (lu seulement après un succès, hors chemin requête→réponse). Ne rien changer d'autre.
- Règles C3/C8 inchangées : verrouiller **uniquement** par Ctrl+Cmd+Q ; doigt à plat ~2 s sans appuyer ; jamais d'appui
  sur la touche Touch ID. Au plus 3 refus d'affilée (éviter le passage forcé au mot de passe) ; si macOS exige le mot de passe,
  `./tools/mark.sh anomalie`, taper le mot de passe, continuer.
- Script (même forme que `tools/guide_doigt.sh` : `go <étiquette> "<consigne>"`, `wait_s`, `res`) ; à écrire par le tracer,
  par exemple `tools/guide_doigt_c10.sh` :
  ```
  mark loginwin
  go pw_login        "tape ton MOT DE PASSE + Entrée"                       ; wait_s 25
  # cycle 1 : mauvais PUIS bon doigt dans le même verrouillage (HJ, HG +0x28, ordre inversé vs C8)
  go lock_m1         "Ctrl+Cmd+Q (verrouiller)"                              ; wait_s 15
  go fp_bad_1        "MAUVAIS doigt (non enrôlé)"   ; wait_s 5 ; res fp_bad_1
  go fp_good_1       "BON doigt"                    ; wait_s 5 ; res fp_good_1 ; wait_s 20
  # cycle 2 : effleurements (HG : provoquer des abandons), puis bon doigt
  go lock_m2         "Ctrl+Cmd+Q (verrouiller)"                              ; wait_s 15
  go fp_tap_1        "EFFLEURE le capteur (< 0,3 s) avec le BON doigt" ; wait_s 4
  go fp_tap_2        "EFFLEURE encore (< 0,3 s)"                        ; wait_s 4
  go fp_tap_3        "EFFLEURE encore (< 0,3 s)"                        ; wait_s 4 ; res fp_tap
  go fp_good_2       "BON doigt à plat"             ; wait_s 5 ; res fp_good_2 ; wait_s 20
  # cycle 3 : bout du doigt (HF : codes de refus), puis bon doigt
  go lock_m3         "Ctrl+Cmd+Q (verrouiller)"                              ; wait_s 15
  go fp_tip_1        "BON doigt, SEULEMENT LE BOUT"  ; wait_s 5 ; res fp_tip_1
  go fp_good_3       "BON doigt à plat"             ; wait_s 5 ; res fp_good_3 ; wait_s 20
  # session ouverte (HE alternative 1, HL) : invite Touch ID sans verrouillage
  go fp_app_prompt   "Safari > Réglages > Mots de passe (attends l'invite Touch ID, NE POSE PAS le doigt)" ; wait_s 5
  go fp_app_good     "BON doigt sur l'invite"       ; wait_s 5 ; res fp_app_good   # puis fermer la fenêtre
  go fp_app_prompt2  "rouvre Safari > Réglages > Mots de passe (invite Touch ID)"            ; wait_s 5
  go fp_app_bad      "MAUVAIS doigt sur l'invite, puis Annuler" ; wait_s 5 ; res fp_app_bad
  # HN / HB : lecture seule
  go uid_check       "Terminal : id -u ; dscl . -read /Users/\$(id -un) GeneratedUID  (recopie la sortie)" ; res uid_check
  mark end
  ```
  Si l'invite Safari ne propose pas Touch ID (option « Remplissage automatique » désactivée), utiliser toute autre invite
  qui affiche l'icône Touch ID sans rien modifier, ou sauter ces étapes (`./tools/mark.sh anomalie`). Ne **pas** passer par
  `sudo` ni par un réglage système qui change l'état du Mac.
- Durée estimée : ~1 min login, ~1 min par cycle (×3), ~1,5 min invites, ~0,5 min Terminal → **~6 min** + marge.
- Ce que chaque étape tranche (prédictions des hypothèses actuelles) :
  | Étapes | Hypothèse | Si vraie | Si fausse |
  |---|---|---|---|
  | fp_bad_1 → fp_good_1 (même lock) | HJ, HG `+0x28` | `+0x44` identique aux deux ; `+0x28` 1 puis 0 (doigt) ou égal (verrouillage) | `+0x44` change entre les deux → lié au doigt/à l'essai |
  | fp_bad_1 avant tout succès | HE, réserve « ordre » | B 0x09 = -1, `+0xc24`=0x2e, même en début de session | 0x2e absent / autre valeur → 0x2e lié au moment de session |
  | fp_tap_1..3 | HG | `00 00` dans chaque `23 06 65 07 22` ; `01 01` si 0x09 suit | une exception → `+0x06..07` ne décide pas |
  | fp_tip_1 | HF | refus avec code ≠ 0x2e (ou succès avec 1/2) | 0x2e pour tout refus → booléen « pas de correspondance » |
  | fp_good_1..3 | HE, HO | 0x1f5 + identifiant ; 0x6c lu en entier (pour C11-boot) | — |
  | fp_app_good / fp_app_bad | HE alt. 1, HL | 0x1f5 / -1 dans B **sans** notif `<12 TAG=0 DATA=0xfffffe0b` | B = -1 malgré l'acceptation, ou notif -501 présente → verdict lié au keybag / notif = « événement d'auth » |
  | uid_check | HN, HB | 501 et GeneratedUID = `FE6003D8-CEA5-414F-B48A-0338DC7C371B` | UUID différent → objet biométrique |
- Après C10 : C11-boot sans humain (arrêt **propre** de macOS avant, par Albert, menu Pomme > Éteindre si possible sous HV)
  pour retrouver le blob 0x6c de C10 dans les `> A 0x5b/0x6d` de l'init (HO).

# Verdicts après C11 (2026-11-08, analyste) — une ligne par hypothèse

C11 = `traces/20261108-025802_c11-doigt-tranchant` ; détail : `docs/messages.md` section C11, `analysis/out/c11_attempt_fields.txt`.
« Candidat `vérifié` » = prédiction écrite avant la capture et confirmée par une trace dédiée, sans exception ; la décision
revient au sceptique / à Albert (CLAUDE.md), pas à l'analyste.
- **HE** — tient : 0x09 `+0x00`=0x1f5 + identifiant ⇔ correspondance, 18/18 dans C11 (29/29 avec C6+C8), y compris en session
  ouverte sans notif -501 → alternative 1 (conséquence du déverrouillage keybag) réfutée sur 2 cas. **Candidat `vérifié`.**
- **HF** — « code par type d'échec » réfuté (mauvais doigt = 0x29, 0x2d, 0x2e) ; « score » soutenu (succès 1-4, refus ≥ 5,
  bout 0x1e, mauvais doigt 0x29-0x2e). Reste hypothèse (seuil 4/5 jamais testé de près).
- **HG** — forme forte réfutée : `00 00` suivi 4× de `1e 09` (correspondances). Reste vrai : tout abandon a `00 00` (10/10).
- **HH** — inchangée (structure seulement ; aucun test du contenu).
- **HI** — reformulée par HO : chaîne 0x21(N) = 0x09(N+1) 12/12 + 2/2 (C8), mise à jour à chaque correspondance y compris en
  session ouverte ; 0x54 d'init = dernier état connu (C9 = C10b = C11). Candidat `vérifié` pour la chaîne intra-session.
- **HJ** — soutenue : `+0x44` identique pour mauvais puis bon doigt du même verrouillage (C11 L1903/L1991) ; compteur de session ;
  `+0x28` de 0x07 = 0 dans les 6 refus de C11 → le `+0x28`=1 de C8 n'était pas lié au doigt.
- **HK** — tient : C11 994 lectures, 0 violation I1-I5 (35 restes de morceau précédent, comme C5-C9) ; contrôle sha 0 faux.
- **HL** — valeurs 33/33 dans C11 (ordre 30/33 : un triplet de verrouillage dans un autre ordre que le log noyau) ; prédiction
  « -501 absente en session ouverte » confirmée (L6871). Correspondance des valeurs : candidat `vérifié` ; l'ordre, non.
- **HM** — non testée dans C11 (split_dir=1).
- **HN** — « identifiant = GeneratedUID » **réfuté** (FF7F7F3C-… ≠ FE6003D8-…, notes.txt) ; « 0x1f5 = uid 501 » confirmé par
  `id -u`. Nature de l'identifiant : ouverte (gabarit / jeu de gabarits / objet SEP).
- **HO** — soutenue : `> A 0x6d` inchangé tant qu'il n'y a pas de succès (C9 = C10b = C11), changé après les succès de C8.
  Prédiction préenregistrée pour le prochain boot (C12) : `> A 0x6d` = exports C11 L6959 (0x9245 o, sha 83613e39) et L6983
  (0xf4 o, sha 5e58a78d). Si confirmée en octets complets → candidat `vérifié`.

# Confrontation kext ↔ traces (2026-11-08, sceptique)

Objet : les affirmations `source: kext` de `docs/messages.md` (« SBIO (0x08) — lecture du kext » et « Capteur (Mesa) → 0x65 »)
qui font une prédiction testable sur les traces **déjà capturées**. Aucun hardware, aucun désassemblage, lecture seule de
`traces/` (sep.log, marks.txt, notes.txt) et de `analysis/out/` (c3/c8/c11_lock_cycles, c11_attempt_fields, c8_ool_attempts,
c8_ool_index, c11_transfers). Comptages faits par recherche regex sur les `sep.log` (lignes `^<ts> [<>] EP=0x08 …`).

**Réserve de méthode (circularité).** Les motifs de trace (ordre d'init, `<03`→`>21`, fragments `DATA=k·0x10000`…) étaient
connus de l'analyste **avant** sa lecture du kext ; le kext n'est donc pas une prédiction aveugle pour ces points, c'est une
deuxième source indépendante qui explique un motif déjà vu. Seules les prédictions de la consigne (points 1, 3-7) et les
miennes ci-dessous ont été écrites avant les comptages. Je note honnêtement que j'avais parcouru `c11_lock_cycles.txt` et
C11 L1855-L2079 avant de rédiger les prédictions des points 2-6 ; les comptages globaux (toutes traces) sont postérieurs.

Le présent texte ne change aucun statut dans `docs/messages.md` : il **propose** ; la décision revient à Albert (CLAUDE.md).

## K1 — TAG 0x01 (SEP→AP) = état de verrouillage du keybag (DATA = uid, TYPE + PARAM·0x100 = lockState), pas un verdict biométrique
- Prédictions (avant comptage) : (a) `<01/08` aussi au déverrouillage par mot de passe ; (b) aucun `<01/08` après une
  correspondance en session déjà ouverte (C11 fp_app_good) ; (c) `<01/09` lié à chaque verrouillage.
- Comptages (C3 = `20261107-035930_c3-touchid`, C8, C11 ; tableaux `analysis/out/c{3,8,11}_lock_cycles.txt`) :
  - (c) **24/24** transitions LOCKED hors boot (uart) ont un `<01/09 p2` (0x209) à ±2 s : C3 10/10 (L1362, 2024, 2292, 2510,
    2760, 3176, 3918, 4362, 4608, 5173), C8 5/5 (L1526, 2070, 2675, 3280, 3932), C11 9/9 (L1498, 2401, 2956, 3370, 3668, 3936,
    4348, 5087, 5814). Les 11 `<01/09` restants sont tous un **2e `<01/09` identique 10,6-14,5 s après** un verrouillage resté
    verrouillé (C3 L1464, 3462, 4714 ; C8 L2209, 2840, 3493, 4089 ; C11 L1647, 2552, 4519, 5244) ; absents quand on
    déverrouille avant ce délai (C11 fp_tap, C3 idle_f1). **0 `<01/09` orphelin.**
  - (b) **2/2** correspondances en session ouverte sans aucune notif TAG 0x01 : C11 L6261 (fp_app_prompt, 0x09 = 0x1f5, score 2)
    et L6871 (fp_app_good, 0x1f5, score 1). À l'inverse, **toutes** les correspondances sur écran verrouillé ont ≥ 1 `<01/08`
    (C11 10/10, C8 3/3, C3 8/9 ; exception C3 L5418 : `<01/45` ×3 à la place, après la rafale d'échecs de fp_bad_2).
  - (a) **réfutée telle qu'énoncée** : les 8 déverrouillages par mot de passe ont `<01/28 p2` (0x228) — C3 pw_login L701/707,
    pw_unlock L1677/1690, pw_after_bad L5723/5730 ; C8 pw_login L853/864, pw_unlock_1 L3833/3842, pw_unlock_2 L4383/4392 ;
    C11 pw_login L851/860, pw_unlock_4 L5980 — et `<01/08` n'apparaît que **2/8** fois (C8 L855, C3 L5724, glissé entre deux
    0x228). Aucune correspondance doigt ne produit 0x228. **La phrase de messages.md (§ lecture du kext, « `<01/08` aux succès et
    au déverrouillage mot de passe ») est inexacte et doit être corrigée** : mot de passe → 0x228 (8/8), 0x208 occasionnel.
  - DATA = 0x1f5 dans 100 % des TAG 0x01 (un seul compte : la partie « DATA = uid » n'est pas testée au-delà de 501, cf. HB).
- Autres explications : (i) TAG 0x01 = « événement d'authentification » vu par SKS — réfutée par (b) et par les 0x209 sans
  aucune activité biométrique ; (ii) 0x208/0x228 = mode de déverrouillage (bio / code) — **compatible** avec la lecture
  keybag (un champ de bits d'état : 0x01 verrouillé ?, 0x20 code saisi ?, 0x200 premier déverrouillage depuis le boot ? —
  pure spéculation, `PARAM=0` avant le 1er login : 0x11/0x15/0x55, `PARAM=2` après). (iii) Le 2e 0x209 différé =
  verrouillage effectif des clés de classe après un délai de grâce — plausible, non testé.
- Verdict : **lecture kext confirmée** (pas un verdict biométrique ; suit les transitions de verrouillage) ; sous-prédiction (a)
  fausse dans sa forme, ce qui ne contredit pas le kext mais corrige la doc.
- Proposition : **`vérifié`** pour « `<01/09 p2` accompagne chaque verrouillage » (kext + 3 traces, 24/24, 0 orphelin).
  **Reste `hypothèse`** pour « TAG 0x01 n'est jamais émis par une correspondance en session ouverte » : le cas décisif tient sur
  2 tentatives d'**une seule** trace → expérience K-E1.
- **EXPÉRIENCE HUMAINE K-E1** (≤ 4 min, peut se greffer sur la prochaine session doigt) : session ouverte, 3 invites Touch ID
  bon doigt + 1 mauvais doigt ; puis lock → mot de passe ; lock → bon doigt ; lock → attendre 20 s → bon doigt.
  Si vraie : 0 TAG 0x01 pendant les 4 invites ; 0x209 à chaque lock (+ 2e 0x209 seulement dans le cas « attendre 20 s ») ;
  0x228 au mot de passe ; 0x208 au doigt. Si fausse : un `<01/xx` pendant une invite en session ouverte → TAG 0x01 dépend
  aussi du verdict biométrique.

## K2 — Mot mailbox fabriqué par GT : TAG ∈ {0xfc, 0xfd, 0xfe}, bits 16-47 = commande (TYPE, PARAM = 0), bits 48-63 = compteur
- Prédiction (avant comptage) : sur tout message EP 0x08 à TAG ≥ 0xfc : PARAM = 0, DATA & 0xffff = 0 ; DATA >> 16 = 0 sur
  chaque 0xfc ; compteur croissant 1, 2, 3… sur les fragments d'un même transfert ; aucun TAG 0xff.
- Comptages : **4006/4006** messages TAG 0xfc/0xfd/0xfe des 14 traces ont PARAM = 0 et DATA & 0xffff = 0 ; **0** TAG 0xff
  dans les 7317 lignes EP 0x08. Tous les 0xfc ont DATA = 0. Fragments C11 (55 lignes fd/fe) et C8 (44) :
  - envoi AP fragmenté (0x5b, 0x6d, 0x65) : `>fc`(0) `<fe`(0) `>fd`(1) `<fe`(1) `>fd`(2) `<fe`(2) `>fd`(3) puis `<fc`(0) (C11 L418-432) ;
  - réponse SEP fragmentée (0x5f, 0x6c) : `>fc`(0) requête, `<fc`(0) 1er morceau, `>fe`(**0**) `<fd`(1) `>fe`(1) `<fd`(2)
    (C11 L2363-2373, 10/10 transactions 0x6c de C8+C11, 4/4 0x5f).
- **Exception à la lecture littérale du kext** (« compteur incrémenté à chaque message envoyé dans la transaction, remis à zéro
  au début de chaque transaction ») : l'AP a déjà envoyé `>fc`(0) quand son premier `>fe` vaut encore 0 (10/10), et la réponse
  `<fc` du SEP vaut 0 après ses `<fe`(0..2). Le compteur est donc remis à zéro **à chaque transfert (chaque 0xfc, chaque
  sens)**, pas une fois par couple requête/réponse ; il vaut l'indice du morceau (fd k = morceau k ; fe k = accusé du morceau k).
  Soit la paraphrase du kext est imprécise (« transaction » = un transfert dans un sens), soit l'analyste a mal lu le point de
  remise à zéro. Pour un pilote, la règle observée suffit et ne dépend pas de l'interprétation.
- Verdict : **confirmé sans exception** pour l'encodage (TAG, TYPE = commande, PARAM = 0, DATA = compteur << 16) ;
  **règle du compteur corrigée** (par transfert et par sens), 0 exception à la règle corrigée.
- Proposition : **`vérifié`** pour l'encodage et la règle corrigée — deux sources indépendantes (kext, 14 traces / 4006 messages,
  fragments dans les deux sens) et comportement reproductible d'un boot à l'autre. Réserve : seule une écriture vers le SEP
  (hors de portée, `pending/`) prouverait que le SEP **exige** ce format ; « vérifié » porte ici sur ce que macOS émet.

## K3 — 0x09 : `+0x14` u32 ≠ 0 ⇒ le kext relance (`retryMatchAfterHomeButtonPress` : 0x65/0x06/0x07/0x75/0x09 sans 0x23)
- Prédiction : si un `+0x14` ≠ 0 existe, on voit une séquence de capture sans `> 0x23` en tête, ou un 0x3e / 0x75.
- Comptages : `> 0xfc 0x23` = `> 0xfc 0x65` dans **chaque** trace (C1 1/1, C3 22/22, C6 6/6, C8 9/9, C11 24/24 = 62/62),
  toutes les séquences de `c*_lock_cycles` commencent par `23 06 65` ; **0** message TYPE 0x3e, 0x75, 0x74, 0x0a.
  50 transactions 0x09 (C1 1, C3 20, C6 5, C8 6, C11 18) : **aucune relance**.
- Conséquence si le kext est bien lu : `+0x14` = 0 dans les 50 réponses. Je n'ai pas lu la valeur (fichiers binaires) ;
  `c8_ool_attempts.txt` dit seulement que `+0x14..+0x1b` est **constant** sur les 6 réponses C8 (valeur non imprimée).
- Verdict : **non testable** dans le sens « ≠ 0 ⇒ relance » (jamais déclenché). Test faisable **sans hardware** (analyste) :
  imprimer `+0x14` u32 des 29 réponses 0x09 OOL (C6 5, C8 6, C11 18). Attendu si le kext est bien lu : 0 partout. Une seule
  valeur ≠ 0 sans relance ⇒ lecture du kext fausse sur ce champ.
- Provoquer une relance (« home button » = clic sur la touche Touch ID pendant la capture) : **déconseillé** sous HV (risque de
  veille / extinction, gel). Pas d'EXPÉRIENCE HUMAINE proposée tant que Linux n'en a pas besoin.

## K4 — Toute charge `> 0x65` fait 0x7200 o (12 tranches `sensor96112_slice16_t` de 0x980)
- Prédiction : 62/62 transferts 0x65 en exactement 2 morceaux (tampon 0x4000 : 0x3fe4 + 0x321c) ; total d'en-tête = 0x7200.
- Comptages : **62/62** transferts `> 0x65` des 5 traces ont exactement un `>fd` (compteur 1) et jamais de compteur 2
  (#lignes fc|fd 0x65 = 3 × #transferts dans chaque trace) → total ∈ ]0x3fe4, 0x7fc8], compatible. Octets exacts : **15/62**
  (C6 6 + C8 9, `analysis/slice_crc.py` : 180/180 tranches, CRC-16/ARC). C3 et C1 : pas d'OOL → total illisible.
  C11 (24) : OOL complète (`full=1`, len 0x4000) mais 0x65 absent de `c11_transfers.txt`.
- Verdict : **compatible sans exception, confirmé octet pour octet sur 15/62**. Test sans hardware : `ool_transfers.py --types
  0x65` + `slice_crc.py` sur C11 → attendu 24 × 0x7200 et 288/288 tranches CRC exactes. Après ce test, avec C6 + C8 + C11
  (3 traces, 39 images, trois sessions doigt différentes) : proposition **`vérifié`** pour « taille 0x7200, 12 tranches à
  CRC-16/ARC ». Le contenu chiffré reste `hypothèse` (HH).

## K5 — Notification `< TAG=0x03` ⇒ l'AP envoie `> 0xfc 0x21` (`checkBgOpsResult`)
- Prédiction : autant de `>21` que de `<03`, chacun juste après son `<03` ; jamais de `>21` sans `<03` préalable.
- Comptages : `<03` = `>21` dans chaque trace (C1 1/1, C3 20/20, C6 5/5, C8 6/6, C11 18/18 = **50/50**), et `<03` = nombre
  de 0x09 (50/50 : une notif par comparaison, succès comme échec). **49/50** : le `>21` est le message EP 0x08 suivant de l'AP
  (≤ 15 ms). **Exception** : C3 `<03` L5362 (…102.717) → `>21` L5381 (…103.086, +370 ms), après que l'AP a déjà lancé la
  tentative suivante (L5363 `>23`, L5373 `>09`, L5379 `>22`). Cohérent avec le kext (drapeau `_bgOpsResultReady` + réveil d'un
  fil : le `>21` attend que la tentative en cours libère le verrou), pas avec une réponse synchrone.
- Verdict : **confirmé** (1:1 en nombre, 0 `>21` orphelin) ; « immédiatement » faux une fois sur 50, explication kext cohérente.
- Proposition : **`vérifié`** comme **comportement de macOS** (kext + 5 traces, 50/50). Non testé : que le SEP exige le 0x21
  (ou bloque sinon) — nécessite une omission volontaire = écriture → hors agent.

## K6 — Ordre d'init identique d'un boot à l'autre (C5..C12)
- Prédiction : même suite de TYPE `>fc` à l'init dans tous les boots complets ; ordre des fonctions du kext
  (prepareSession 17 → performKeyExchange 15/16 → initializeSequenceCounter 42/18 → loadPatch 5f…01 → applySensorParams
  5d/5c/6a/6f → getSensorModuleSerialNumberRaw 31/32 → setCalibrationData 61/5b/63).
- Comptages (C5, C6, C7, C8, C9, C10b, C11, C12 = 8 boots complets ; C10 `011515` exclu : 5 lignes EP 0x08) : les **57
  premières commandes sont identiques 8/8** :
  `73 | 17 15 16 42 18 5f 5d 5c 6a 31 32 01 1f 31 32 5b 63 | 19 | 17 15 16 42 18 5f 5d 5c 6a 6f 31 32 01 1f 63 63 |
  7c 6b 79 6d 39 6b 79 6b 79 6d 2b 6b 79 54 2b 33 36 6e 7a 71 28 7c`, puis une queue de 6 commandes de **même multiensemble**
  {2b ×3, 7c, 63 ×2} dans un **ordre variable** (8 ordres différents, ex. C5 `7c 63 2b 2b 2b 63`, C8 `63 7c 63 2b 2b 2b`,
  C11 `2b 7c 2b 63 2b 63`), puis `7d 0b` 8/8. La partie variable est celle des commandes user-client (plusieurs démons
  concurrents) — attendu ; la partie pilotée par le kext est figée.
- **Exceptions à la lecture des séquences du kext** (à relire par l'analyste, rien de bloquant) :
  1. `loadPatch` = « 5f → capteur Patch → GetStatus → 01 » : dans **16/16** passes, 5f et 01 sont séparés par
     `5d 5c 6a [6f] 31 32`. Ou 0x01 n'appartient pas à `loadPatch`, ou `loadPatch` appelle applySensorParams et le numéro de série
     entre le patch et 0x01.
  2. `applySensorParams` (5d 5c 6a 6f) : 0x6f **absent de la 1re passe 8/8, présent dans la 2e 8/8** → branche conditionnelle
     non décrite.
  3. `setCalibrationData` (61, 5b, 63) : **0x61 jamais envoyé** (0/7317) ; 5b uniquement en 1re passe.
  4. 0x19 (`HandleReset`) sépare 8/8 deux passes complètes : la 2e passe refait clé, compteur, patch (2e 0x5f, réponse
     différente : 0x568e puis 0x70ce o en C11) → un reset capteur fait partie de l'init normale.
  5. Jamais vus non plus : 0x48 (`sendDeviceSerialNumberToSbio`), 0x1b, 0x43/0x44, 0x04, 0x67.
- Verdict : **confirmé sans exception** pour « ordre identique » (préfixe de 57, 8/8) ; la correspondance fine
  fonction-kext → sous-séquence a 3 écarts (1-3).
- Proposition : **`vérifié`** pour la suite d'init observée (8 boots, reproductible, noms kext en appui). Les attributions
  `loadPatch`/0x01 et la condition de 0x6f restent `hypothèse` (source: kext) tant que les écarts 1-2 ne sont pas expliqués.

## K7 — 0x27 / 0x25 (`commandStartMatch`) présents quelque part ?
- Prédiction (consigne) : à chercher. La mienne : absents (aucun motif inconnu n'a été signalé dans les séquences).
- Comptage : **0** message EP 0x08 de TYPE 0x27 ou 0x25 (toutes TAG) dans les 15 `sep.log` (7317 lignes EP 0x08), y compris
  les 50 comparaisons (écran verrouillé, session ouverte, mauvais doigt, bout du doigt). Pas de 0x03 (`commandStartEnroll`).
- Verdict : **confirmé : absents**. Conséquence : sur 13.5, le déverrouillage et les invites passent par
  `asyncCaptureHandler`/`handleMatch` (23 06 65 07 [1e] 09) sans `commandStartMatch`. Usage de 0x27/0x25 inconnu (autre mode :
  Apple Pay ? accessoire ? ancienne voie ?) — ne pas l'implémenter sans nouvelle observation.
- Statut proposé : observation `vérifiée` (absence sur 5 traces doigt) ; le rôle de 0x27/0x25 : ouvert.

## EXPÉRIENCE ADT-1 — dump ADT en lecture seule pour localiser le capteur (agent tracer à écrire ; non exécutée)
- But : lire dans l'ADT du j314c le nœud `compatible = biosensor,mesa` et son parent `spi-1,spimc` : nom (`spiN`), `reg`,
  `interrupts`, `function-mesa_pwr`, `function-mesa_pwr1v8`, `function-mesa_reset`, `mesa-spi-freq`, délais d'alim, et
  le nœud gpio cible des phandles. Détail dans `docs/sensor_hw.md`.
- Moyen : un script `tools/dump_adt.sh` (à écrire par **tracer**) qui chainloade m1n1 frais comme `boot_and_trace.sh` et
  écrit l'ADT (`adt.txt` via la lecture proxy de l'arbre, sans HV, sans écriture MMIO, sans SEP) dans un dossier traces/.
  Rien d'autre sur le Mac. Pas d'écriture vers le SEP ; le hardware passe uniquement par tools/*.sh.
- Résultat attendu : tableau contrôleur/IRQ/GPIO fiable. Un seul dump suffit (pas de doigt, pas d'humain).
- Statut : proposée, non lancée. Sans ça, `docs/sensor_hw.md` reste en `hypothèse`.

## Ce qui reste à faire (du moins cher au plus cher)
1. **Analyste, sans hardware** : (a) `+0x14` u32 des 29 réponses 0x09 OOL (K3) ; (b) totaux + CRC des 24 `> 0x65` de C11 (K4) ;
   (c) corriger dans `docs/messages.md` la phrase sur `<01/08` au mot de passe (K1) et la règle du compteur (K2).
2. **Analyste, kext** : expliquer les écarts K6-1 (place de 0x01), K6-2 (condition de 0x6f), K6-3 (0x61 jamais envoyé) et
   relire le point exact de remise à zéro du compteur dans GT (K2).
3. **EXPÉRIENCE HUMAINE K-E1** (≤ 4 min) : invites Touch ID en session ouverte + trois types de déverrouillage (K1).

## SKS-1 — Le SEP refuse-t-il 0x09 tant que le trousseau n'est pas validé ? (2026-11-08, Claude, source: kext = noms de symboles seulement)
Aucun désassemblage fait : lecture de `analysis/out/sks_symbols.txt` (396 noms) recoupée avec messages.md §SKS et kext_sepmanager.md §6.
- VU (traces) : chemin doigt = **aucune requête AP→0x12** avant le succès ; le SEP émet seul `< 0x12 TAG=0x00 DATA=-501` pendant le 0x09 puis macOS publie UNLOCKED. Chemin mot de passe = `> 0x12 TAG 0x41` puis `0x18`. lockState (0x0015 au boot, 0x0228 après code) est une notification **SEP→AP** (`<01`).
- Noms (source: kext) : `AppleKeyStore::sep_deliver_msg`, `change_lock_state`, `unlock_the_device`, `verify_password`, `device_state_transition`, `get_device_state`, `notify_change_device_state`, `ep_check_policy`, `IOSEPBiometricService::finalizeSKSStateHandling`. Côté AP, le keystore ne fait que relayer/mettre en cache l'état annoncé par le SEP ; aucun nom ne suggère un « jeton bio » envoyé par l'AP pour autoriser un match.
- HYPOTHÈSE (non vérifiée) : l'état « blocage bio » (0x0015) vient du SEP, donc le SEP l'applique très probablement lui-même ; macOS s'abstient en plus d'offrir Touch ID. Le déverrouillage du trousseau après match est fait par le SEP seul (pas de message AP) → pour Linux, `0x09` suffirait une fois le mot de passe validé via 0x12, mais le mot de passe doit passer par SKS.
- NON TRANCHÉ : « refuse » vs « macOS s'abstient ». Seule expérience qui tranche : envoyer 0x09 (écriture SBIO) à l'état 0x0015 → script dans `pending/`, à lancer par Albert. Expérience passive possible (K-E1 bis) : doigt posé sur l'écran de login juste après boot, vérifier que macOS n'envoie pas 0x09 (confirme l'abstention de macOS, pas le refus du SEP).
- Filtre [cyber] : pas déclenché cette fois (pas de désassemblage). Étude plus profonde du protocole 0x12 (format des TAG 0x18/0x41/0x2f) non faite.
