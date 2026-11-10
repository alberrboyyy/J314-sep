# 5. Le coffre xART

xART (eXtended Anti-Replay Token) est le mécanisme d'anti-rejeu du SEP. Le SEP n'ayant pas de
stockage persistant, il confie des **lockers** (blobs chiffrés et authentifiés par une clé
interne) à l'AP, qui les écrit sur le disque et les lui rend au boot suivant. xART garantit que
le SEP reçoit la **dernière** version sauvée et non une ancienne rejouée. L'endpoint `xars`
(0x10) met en place, `xarm` (0x13) assure les opérations ; le noyau macOS le nomme
« AppleSEPXART (EP: 19) ». Analyse complète : `docs/xart_options.md` ; traces : `docs/messages.md`
§ « xART au boot ».

## Échange au boot (observé, structure identique sur 19 boots)

**Vérifié (invariant, 19/19)** pour la structure ; les valeurs de contenu (CRC) varient (voir ci-dessous).

1. `xarm` s'annonce, émet un premier message, puis **attend l'AP de 2,8 à 3,8 s**.
2. L'AP répond ; le SEP demande, l'AP **restitue** (fetch) « SEP-xART » puis « USER-xART ».
   Les en-têtes de réponse sont **constants** d'un boot à l'autre ; le **contenu change à
   chaque boot**.
3. **0,122 s après** ce bloc, le SEP annonce `sbio`, puis `skdl`, `sse`, `sks`, `scrd`.
4. Suivent des restitutions de lockers (quatre au contenu constant, d'autres variables) et des
   sauvegardes, dont l'AP **recopie le CRC**.

**Vérifié (chaîne boot → boot, 15/15 paires)** : le CRC « restitué » d'un boot est égal au
dernier CRC « sauvé » du boot précédent. C'est le comportement attendu d'un coffre : l'AP rend
ce que le SEP lui a fait sauver la fois d'avant.

## Le blocage

`sbio` (et donc Touch ID) n'est annoncé qu'**après** cet échange. Sous m1n1/Linux, aucun
composant ne tient le rôle de l'AP pour xART ; le SEP reste à 7/12 endpoints, sans `sbio`
([chapitre 3](03-boot-sep.md)). **Vérifié** : SEP-BOOT = 7/12 ; **Hypothèse** (causalité) :
c'est bien l'absence d'échange xART qui prive des cinq endpoints.

## Rejouer n'est pas forger

Deux approches, à ne pas confondre :

- **Forger** un locker (fabriquer un état inventé) exige la clé interne du SEP, qu'on s'interdit
  de chercher (ligne rouge « aucune clé extraite »). **Impossible.**
- **Rejouer** les lockers que le SEP a lui-même fait sauver ne demande **pas** de les
  comprendre : il suffit de les stocker et de les rendre, comme le fait l'AP macOS. Le SEP n'a
  pas de disque et **dépend** de ce service ; rien n'interdit en principe que Linux le tienne.

Si le rejeu aboutit, le SEP annonce `sbio` et **effectue lui-même** la comparaison d'empreinte :
le projet n'a jamais besoin de sa clé. **Le Touch ID n'est donc pas exclu par conception** ; il
dépend de la question ci-dessous.

## La question qui tranche

L'anti-rejeu accepte-t-il un **rejeu fidèle de l'état courant** (dernier état sauvé, inchangé),
ou vérifie-t-il un **compteur / nonce incrémenté à chaque boot** qui ferait échouer un rejeu
passif ? **Inconnu.** C'est le point décisif, et il se tranche **en lecture seule** par la
capture du contenu des lockers (voie B ci-dessous), avant toute écriture.

## Voies (synthèse de `docs/xart_options.md`)

- **Voie B — observer (sans risque, prête)** : capturer le contenu (OOL) de l'échange `xarm`
  pendant un boot macOS, en lecture seule, pour y chercher le compteur/nonce et lire les blobs.
  L'outil le permet déjà ([chapitre 8](08-outillage.md)) ; il manque la capture physique (câble USB).
- **Voie C — rejouer (écriture SEP, décision d'Albert)** : faire tenir le rôle de stockage xART
  par Linux. Nécessite les vrais fichiers de lockers du disque macOS (`/System/Volumes/xarts/`),
  n'est tentée qu'après la voie B, passe par un script `pending/` lancé par Albert, et sous
  garantie absolue de non-brick et de non-atteinte à la partition Linux ([chapitre 10](10-regles-et-risques.md)).
- **Voie D — forger** : impossible (clé interne), documentée pour être écartée.
