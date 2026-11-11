# Statut de vérification des messages et champs (2026-11-08, sceptique)

Règle (CLAUDE.md) : `vérifié` = expérience dédiée + prédiction écrite AVANT + reproductible. Lecture de kext seule, ou
recoupement d'un motif déjà connu avant la lecture, = `hypothèse`. `vérifié` porte sur **ce que macOS émet / ce que le SEP
renvoie à macOS** : aucune écriture vers le SEP n'a jamais été faite, donc « le SEP exige X » n'est vérifié nulle part.
Seules les lignes marquées `vérifié` sont utilisables par le driver. Depuis 2026-11-09 (CLAUDE.md « Qui décide quoi »), le
sceptique tranche lui-même : plus de « vérifié (proposé) ».
**Sens de `vérifié`** : « macOS fait / reçoit exactement cela, de façon reproductible sur des captures distinctes ». Cela
ne veut PAS dire « le SEP l'exige » ni « le SEP acceptera un autre hôte » : aucune écriture n'a jamais été faite, donc l'exigence
n'est testée nulle part. Le contenu chiffré/opaque reste hors de portée de toute vérification.
Traces : C1 boot, C3 touchid, C5-C9 OOL, C11 doigt tranchant, C12 boot-ho. Source : T = trace, K = kext, P = public (Asahi/m1n1).

Prédictions écrites avant : K1c/K2/K4/K5/K6/K7 (hypotheses.md « Confrontation », avant comptage, mais motifs connus de
l'analyste ; le sceptique le note lui-même), HO (journal C12 : prédiction sha avant capture, exacte), HE (table C10).

| Message ou champ | Sens / EP | Description | Source | Statut | Preuve | Manque pour `vérifié` |
|---|---|---|---|---|---|---|
| Découpage mot (EP 0-7, tag 8-15, type 16-23, param 24-31, data 32-63) | tous | format mailbox | P+T+K | hypothèse (cohérent) | messages.md « Contrôles de cohérence » : uart L776 ↔ C1 L35 ; 36 xART ↔ uart ; ≥ 8 « EP n enabled » | prédiction écrite + test sur un mot jamais vu (aucune écriture possible) ; en lecture, très solide |
| Annonces EP 0xFD TYPE 0 (nom 4 car.) | < FD | table nom→numéro, 12 EP | P+T+K | hypothèse | C1 L16-38,108-124,161 ; 12/12 = doc Asahi | 2e boot comparé (C6..C12 ont le même ordre) : simple relecture sans hardware |
| FD TYPE 1 : 4 octets min/max pages envoi/réception (page 0x4000) | < FD | tailles OOL | K | hypothèse | 3 cas (0x15, 0x12, 0x08) | prédiction sur les 9 autres EP avant relecture (sans hw) |
| Boot ROM FF : 0x02/0x66, 0x05/0x69, 0x06/0x6a, 0xd2 | FF | GET_STATUS, TZ0, IMG4 | P+K+T | hypothèse (types connu-doc) | C1 L3-14, C11 L5-13 | écriture SEP (Albert) |
| `> FF 0x1b` / `< FF 0x7f` | FF | inconnu | T | hypothèse (rôle inconnu) | C1 L3-4, C11 L3-4 | origine introuvable dans le kext |
| `> FE` taille shmem (octets 2-3) | FE | pages 4 Kio de mémoire partagée | K+T | hypothèse | uart « slave addr 0x580000, size 0x1c000 » 1 boot décodé | autres boots (uart C5-C12) : sans hw ; et écriture |
| CNTL `> 0x04/0x02/0x05/0x03` (taille/adresse IN/OUT) | 0x00 | config buffers OOL, A=envoi AP, B=réception | T+K | hypothèse (A/B : K seul + cohérence) | 36 séquences, formule d'adresses sans exception ; « EP n enabled » | A/B non vérifié sur adresses ; confirmer par IOVA (dump d'adresses) |
| CNTL `<07/01` ack = écho DATA | < 0x00 | acquittement | T+K | hypothèse (36/36 écho) | C1 | écriture |
| CNTL `> 0x14` SECMODE / réponse DATA=3 | 0x00 | mode de sécurité | K+T | hypothèse | C1 L39-40, C11, C12 (1 valeur) | comparer avec un autre mode (Albert) |
| CNTL `<0x0d`, `<0x29`, `<0x10` | < 0x00 | OS actif, unsolicited, wrapping | K+T | hypothèse | C1, C11 (uart L765-766 pour 0x29) | rien de testable en lecture |
| CNTL tag = index pool + 1 | > 0x00 | tag sans sens | K+T | hypothèse | C1/C11/C12 | — |
| Mot sbio GT : request ∈ {0xfc,0xfd,0xfe}, TYPE = commande, PARAM = 0, DATA = compteur<<16 (compteur par transfert et par sens) | 0x08 | encodage | K+T | **vérifié (côté macOS)** | 4006/4006 messages de 14 traces ; 0 TAG 0xff ; règle du compteur corrigée sans exception | « le SEP exige ce format » : écriture |
| Paires 0xfc `>X`/`<X` PARAM=DATA=0 | 0x08 | requête/réponse | T | hypothèse → vérifié de fait | C1 224 msg, C11, 0 exception | — (déjà couvert par la ligne ci-dessus) |
| Fragments 0xfe/0xfd (« pendant »/« après ») | 0x08 | transfert multi-morceaux | K+T | **vérifié (côté macOS)** (idem encodage) | C11 L418-432, L2363-2373 ; 10/10 0x6c | — |
| En-tête OOL 0x1c o (1,total,offset,0,0,TYPE,len) | A/B | paquet GT | K+T | **vérifié (lecture)** | 1695 lectures C5-C9, 994 C11, 0 violation ; mais l'invariant a été vu avant la lecture kext | prédiction a priori sur une capture neuve (C12 déjà dispo : sans hw) |
| A=AP→SEP, B=SEP→AP | OOL | direction des buffers | K+T (HM) | hypothèse | cohérent C8 ; HM non testée (split_dir=1) | dump avec split_dir inversé (boot sans humain) |
| TYPE 0x73 (init sbio, `<TAG 0x04` pendant) | 0x08 | ouverture | K+T | **vérifié (ordre)** via K6 ; sémantique hypothèse | 8/8 boots, 1re commande | — |
| Init : 17 15 16 42 18 5f 5d 5c 6a 31 32 01 1f … (57 premières commandes) | 0x08 | séquence d'init | K+T | **vérifié (2026-11-09, comportement macOS)** pour la liste ordonnée des 57 TYPE ; attributions fines hypothèse ; la coupure à 57 est choisie après coup (là où les boots divergent) | K6 : 8/8 boots, préfixe 57 identique ; rejeu hors ligne 18/18 captures avec sbio, dont C13-C16 postérieures à K6 (hors échantillon) | « le SEP exige cet ordre / ce préfixe » : écriture. Écarts K6-1 (0x01 loin de 0x5f), K6-2 (0x6f 2e passe seulement), K6-3 (0x61 jamais envoyé) non expliqués |
| 0x15/0x16 (40 o hostKeyWrapped), 0x42/0x18, 0x17 (série capteur) | 0x08 | clé de session SEP↔capteur, AP relais | K | hypothèse | ordre observé seulement ; contenu jamais comparé octet à octet ; « AP n'a pas de clé » = K | tailles 40/0x40/0x10 lues dans les OOL de C5-C12 (sans hw) ; test réel = relais Linux (écriture) |
| 0x5b calibration (0xfc99 o, sha d5a6117d, « comb ») | > 0x08 | blob fixe | T | hypothèse | identique C5-C9 (5 boots) | origine (fichier macOS) non vue ; sans hw : retrouver dans le disque (hors périmètre) |
| 0x5f réponses (0x568e, 0x70ce o), 0x01 | < 0x08 | patch capteur du SEP | K+T | hypothèse | longueurs stables, contenu différent à chaque boot (5 boots) | rôle « patch » = K seul ; test : le capteur le reçoit (SPI, SEP-écriture côté Linux) |
| 0x6c export / 0x6d import `LTFC` (uid 501 gros, -1 petit 0xf4) | 0x08 | catacomb (gabarits scellés), conservé par macOS | T+K | **vérifié (HO, 2026-11-09, comportement macOS)** : macOS réimporte au boot le dernier blob exporté ; import C12 = dernier export C11, sha complet, 2/2 blobs ; C9 → C11 idem (2/2) ; C8 → C9 : petit blob identique, gros PARTIEL (tracer tronqué) | prédiction écrite avant (C12), exacte ; rejeu hors ligne | contenu = chiffré (opaque) ; que le SEP refuse un blob absent/ancien = écriture ; ordre « petit puis gros » = hypothèse (5 boots) |
| 0x54 (req uid+16 o ; rép 0xbf4) | 0x08 | enregistrement associé au gabarit | T | hypothèse | identique C5-C8 ; changée en C9/C11/C12 selon les succès (HI/HO) | prédiction a priori du contenu 0x54 de C12 = 0x21 final C11 (sans hw : jamais écrite) |
| Chaîne 0x21(N) = 0x09(N+1) (hors 0x06-0x2d) | < 0x08 | enregistrement mis à jour à chaque correspondance | T | hypothèse (candidat) | 12/12 C11 + 2/2 C8 | prédiction explicite écrite avant une capture neuve (C12 : calculable sans hw) |
| 16 o `fe6003d8…371b` | 0x08 | identifiant (≠ GeneratedUID) | T | hypothèse (nature inconnue) | HN réfutée pour GeneratedUID (notes C11) | enrôler un 2e doigt/utilisateur et voir si ça change (EXPÉRIENCE HUMAINE) |
| DATA=0x1f5 = uid 501 | 0x08/0x12 | uid | T+K | **vérifié** pour « 501 » (`id -u`) ; « = uid général » non testé | C11 notes | 2e utilisateur (HUMAINE) pour confirmer le rôle de DATA |
| `<01/xx` : DATA=uid, u16 TYPE+PARAM·0x100 = lockState SKS | < 0x08 | état du keybag | K+T | hypothèse ; sous-point `<01/09 p2` à chaque verrouillage = **vérifié** | 24/24 verrous, 0 orphelin (C3, C8, C11) | K-E1 pour « jamais de `<01` en session ouverte » (2 cas d'une trace) |
| `<01/28 p2` (0x228) | < 0x08 | mot de passe validé | T+K | hypothèse | 8/8 mots de passe, jamais au doigt | idem K-E1 ; `<01/08` au mot de passe 2/8 : inexpliqué |
| `<01/08` (0x208) | < 0x08 | déverrouillé avec bio | T+K | hypothèse | présent 10/10 C11, 3/3 C8, 8/9 C3 (en écran verrouillé) | K-E1 |
| `<01/45`, 0x15, 0x55, 0x11 | < 0x08 | blocage bio/état avant login | T+K | hypothèse | 0x45 : 1 cycle de C3 seulement ; non reproduit en C11 (3 échecs) | 5 échecs consécutifs (HUMAINE) |
| Bits du lockState (bit 0 verrouillé, 1 blocage code, 2 blocage bio, 3, 5 code validé, 9) | < 0x08 | sémantique des bits | K (noms de fonctions) | hypothèse | spéculation compatible | K-E1 + blocage |
| `<02/01` (u16 = gabarits ?) | < 0x08 | | K+T | hypothèse | 1 occurrence (C11 L562) | autres boots (sans hw : grep) |
| `<03` ⇒ `>21` (checkBgOpsResult) | 0x08 | notif de fin de comparaison | K+T | **vérifié (comportement macOS)** | 50/50, exception +370 ms expliquée | « SEP exige 0x21 » : écriture |
| `<04/00` | < 0x08 | signal prêt | K+T | hypothèse | 1× par boot, pendant 0x73 | — |
| `> TAG 0x26 DATA=uid` (dropUnlockToken) | > 0x08 | | K+T | hypothèse | 1× par boot, DATA=0x1f5 | écriture |
| Séquence match `23 06 65 07 [1e] 09 1f 22 70 [2b] <03 21` | 0x08 | tentative de déverrouillage | T+K | **vérifié (réponse du SEP / séquence macOS)** : 18 tentatives C11 sans exception, prédit en C10 | C3, C8, C11 | — |
| 0x65 charge 0x7200 = 12 × 0x980, CRC-16/ARC | > 0x08 | image capteur chiffrée | K+T | **vérifié (2026-11-09, comportement macOS)** pour la structure et le CRC (24/24 C11, 288/288 ; C6+C8+C11 : 39 images, 468/468 tranches, 3 sessions ; rejeu par code écrit depuis la définition standard CRC-16/ARC, une tranche corrompue est détectée) ; contenu hypothèse (HH) | commit 5313351 ; driver/tests | contenu chiffré = non testable ; « le capteur/SEP rejette une mauvaise tranche » = écriture |
| 0x06 charge 0xa7 (`+0x40` compteur, `+0x44`, `+0x48`, `+0x97..0xa6` nonce par verrouillage) | > 0x08 | params de capture (HJ) | T+K | hypothèse | 9/9 C8 + 15/15 C6/C8 ; C11 | origine `_lastImageProcessingParams` non lue ; nonce par verrouillage : 5 verrous |
| 0x07 réponse 0xc0 : `+0x00 err`, `+0x02 assessment`, `+0x06/07`, `+0x85`=0x37 | < 0x08 | résultat image | K+T | hypothèse (champs nommés K) ; `+0x85`=0x37 15/15 fait | C6/C8/C11 | HG forte réfutée ; `+0x28` ≠ doigt |
| 0x1e entre 0x07 et 0x09 | > 0x08 | relance après 0x07 défavorable | T | hypothèse | 4/4 (C11) | déclencheur exact (C11 seul) |
| 0x09 réponse 0xca2 : `+0x00`=0x1f5 + id = correspondance, 0xffffffff = refus | < 0x08 | verdict | T (+K : le kext teste −1) | **vérifié (HE)** : prédiction C10, 29/29 sur C6+C8+C11, y compris session ouverte | C11 18/18 | autre utilisateur / autre doigt enrôlé (HUMAINE) pour « uid général » |
| 0x09 `+0xc24` | < 0x08 | score/distance (succès 1-4, bout 0x1e, refus ≥ 5) | T | hypothèse | 29 tentatives ; seuil 4/5 | test à la limite (HUMAINE : doigt partiel, graduer) |
| 0x09 `+0x14` u32 ≠ 0 ⇒ relance (retry) | < 0x08 | | K | hypothèse (non testée) | 0 relance sur 50 | imprimer `+0x14` des 29 OOL (sans hw) ; ≠ 0 sans relance = faux |
| 0x21 réponse 0xc8e | < 0x08 | récap fin de tentative | T | hypothèse | 6/6 C8 + chaîne | — |
| 0x70 `HRLB` 0x69 o / 0x71 | < / > 0x08 | BioLockoutRecord | K+T | hypothèse (nom `HRLB`) | 12/12 C8 | rejeu = écriture |
| 0x1f (`05 05`), 0x22, 0x0b, 0x23, 0x2b, 0x33, 0x36, 0x7c, 0x7d, 0x28, 0x39, 0x6e, 0x7a, 0x6b, 0x79, 0x63, 0x19, 0x40 | 0x08 | commandes diverses (noms K) | K+T | hypothèse | place seule dans l'ordre | rôle requis ou non pour un match : **inconnu** (écriture) |
| Absence de 0x27/0x25/0x03/0x3e/0x75 | 0x08 | pas de `commandStartMatch` | T | **vérifié (négatif)** | 0 sur 15 traces (K7) | — |
| Latence 0xfc ~1.6 ms ; 0x09 = 240-250 ms succès / 296-366 ms refus | 0x08 | timing | T | hypothèse (3 traces concordantes) | C3, C8, C11 | — |
| SKS `> t / < t\|0x80`, TYPE = compteur, DATA 0xLLLL0000 | 0x12 | protocole SKS (579 req) | T | hypothèse | C1 579/579 appariées, réponses 0x84/0x86 PARAM 0xfd avant login, 0x00 après (C1, C2a, C3) | format des commandes inconnu ; pas d'écriture |
| `<0x12 TAG X TYPE V DATA=handle` « lock change » | < 0x12 | notif keybag (TAG 0=déverr., 1=verr.) | T+uart | **vérifié (valeurs)** : 33+34+29+6 ; ordre 30/33 | HL | — |
| Notif -501 pendant 0x09 | < 0x12 | keybag déverrouillé par le SEP | T | hypothèse | 3/3 C8, absente en session ouverte (prédiction C10, 2/2 C11) | K-E1 (plus de cas) |
| `> 0x12 TAG 0x2f/0x41/0x18` | > 0x12 | verrou différé / mot de passe 1re et 2e étape | T | hypothèse | 6/6, 3/3, 6/6 | écriture / format ; EP 0x12 = ligne rouge |
| xART `< 0x13` TYPE 0x01 PARAM 0x9c, CRC<<16 | < 0x13 | « Saving USER-xART » | T+uart | **vérifié (CRC = log noyau)** ; rôle « marqueur de comparaison » hypothèse | C8 18/18, C3 52/52, C1 4/4 | rôle |
| xART `< 0x1d` (nom EP ASCII), TYPE 0x06, 0x01/0x53 | < 0x13 | | T+uart | hypothèse | 5/5 uart « op 29 » | — |
| SBIO sur SPI : trame `80 op idx len`, lecture `80 13`, statut `80 20` | capteur | protocole capteur | K+T (uart) | hypothèse ; trame d'image = voir 0x65 | statut 16/16 traces ; `_checkImageCRC` OK | statut complet (CRC non ARC) inconnu |
| Chemin ADT/SPI du capteur sur t6001 | — | | P (M1) + K | hypothèse | non vérifié sur M1 Max | dump ADT (tracer) |

## (1) Messages minimaux de docs/driver_plan.md
`docs/driver_plan.md` n'existe pas encore (autre agent). À relire quand il paraît. Provisoire, d'après kext_sepmanager.md §7 :
l'init (A) est écriture SEP/Albert ; B (init SBIO) = `vérifié` pour l'**ordre** seulement ; C (match) séquence `vérifié`,
**verdict** `vérifié` ; D2 (keybag/SKS 0x12 + lockState) = non vérifié et bloquant probable ; D3/D4/D5 (0x5b, 0x6d, 0x71)
rejouables : 0x6d `vérifié` (HO), 0x5b fixe mais hypothèse, 0x71 hypothèse ; 0x06 (params 0xa7) hypothèse. Aucun élément ne
prouve qu'un hôte non macOS soit accepté par le SEP : ce n'est vérifiable que par une écriture (pending/).

## (2) Les 3 expériences les plus rentables
1. **Sans hardware (coût ~0)** : script d'analyse sur traces existantes, avec prédictions écrites avant : (a) `+0x14` des 29 0x09 (= 0 attendu) ;
   (b) 0x54 d'init de C12 = 0x21 du dernier succès C11 (hors 0x06-0x2d) ; (c) tailles 40/0x40/0x10 des charges 0x15/0x16/0x42/0x18/0x17
   sur C5-C12 ; (d) FD TYPE 1 → T4/T5 sur les 12 EP de C6..C12. Fait passer ~5 lignes (HI/chaîne 0x21, FD, +0x14, 0x15/0x16).
2. **Boot sans humain** : deux boots consécutifs avec `split_dir` inversé (teste A/B, HM) et sans succès entre eux (nonces/clés
   0x5f, 0x15/0x16 qui varient = non déterministe ; le reste identique) ; ajoute lecture ADT du capteur. Fait passer A/B, FD tailles,
   0x5b fixe, 0x73, `<02`, chemin SPI.
3. **EXPÉRIENCE HUMAINE** : K-E1 (session ouverte : 3 bon doigt + 1 mauvais ; lock → mot de passe ; lock → doigt ; lock → 20 s → doigt),
   ≤ 4 min, **prédictions écrites avant** (0 `<01` en session ouverte ; 0x209 par lock ; 0x228 mot de passe ; 0x208 doigt). Fait passer
   les 5 lignes `<01/xx` + notif -501. Variante : 2e doigt enrôlé pour le rôle de l'identifiant 16 o et de `+0xc24` (graduer).


## Mise à jour 2026-11-08 soir (Claude)
- K-E1 partielle (C15) : 0 `<08 TAG=0x01` pendant 4 invites en session ouverte (3 bon doigt, 1 mauvais), 0 requête AP→0x12 : soutient « TAG 0x01 = état keybag, pas verdict » ; reste `hypothèse` (n=4, une trace). Lock : `<01/08 p2` (0x208) vu, pas 0x209 : à revoir. Manque : lock→doigt, lock→20 s→doigt.
- ADT-1 : capteur = enfant de spi2 (8 MHz), mesa_pwr = gpio0 0xc4/0x101, IRQ gpio0 195 (trace 20261108-162919_adt) : `vérifié` en tant que lecture de l'ADT ; rôle des broches = hypothèse.
- SKS-1 : voir hypotheses.md ; non tranché sans écriture.
- K-E1 complète (C15+C16) : prédictions 0x209@lock, 0x228@mot de passe, 0x208@doigt, 0 TAG 0x01 en invite : confirmées (n=1 par cas, une session) → décision sceptique 2026-11-09 : reste `hypothèse` pour « `<01` suit le keybag, pas le verdict » (une seule session, pas de répétition, et la prédiction 0x209@lock était fausse sur un point) ; manque : une 2e session identique. Écart : 2e 0x209 présent dans tous les cas, pas seulement après 20 s.
- Correction (driver, rejeu 8 boots) : l'ordre d'annonce 0xFD n'est **pas fixe** (3 ordres sur 8 boots, C7 et C9 diffèrent) : la ligne « C6..C12 ont le même ordre » est inexacte ; le pilote cherche les EP par nom.
- Rejeu hors ligne (driver/, 29 tests) : init 57 commandes 18/18 captures ; 0x65 : 24/24 transferts, 288/288 CRC (C11), 39/39 images et 468/468 tranches sur C6+C8+C11 ; 0x6d C12 = 0x6c C11 octet pour octet (2/2).

- SPI-1 (2026-11-10, C20) : la charge de `> 0x65` est l'image lue par l'AP sur le bus SPI du capteur, non transformée :
  `vérifié (macOS)` (prédiction écrite avant, 7/7 poses, 113/114 blocs de 256 o ; réserve : pas de sha du transfert réassemblé).
  **Réserve levée (2026-11-10, analysis/cmp_sensor_sep_image.py) :** image réassemblée comparée octet pour octet. 7 images
  complètes de 0x7200 o lues sur le bus (sio.bufs/*_done_data.bin) sont **identiques octet pour octet** à la concaténation de
  deux buffers OOL de l'EP 0x08 côté SEP (sep.log.ool/*_08_A.bin), chacun après un entête de 0x1c o ; les 22 autres images ne
  sont pas comparables (leur buffer SEP n'a pas été dumpé, hors fenêtre). Entête de tranche décodé (champs 32 bits LE) :
  `[0]=1 [1]=0x7200 (longueur totale) [2]=offset de la tranche [3]=0 [4]=0 [5]=0x65 (type image) [6]=longueur de la tranche`
  (tranche 1 : offset 0, len 0x3fe4 ; tranche 2 : offset 0x3fe4, len 0x321c ; somme = 0x7200). Confirme l'entête OOL de la ligne
  « En-tête OOL 0x1c o » sur le chemin de l'image. Contrôle : 2 images différentes ne partagent **aucun** run de 32 o (chiffrement
  bout en bout capteur↔SEP, l'AP ne voit que du chiffré). Reste hypothèse : sens des champs [0], [3], [4] ; généralisation aux autres boots.
- SPI-2 (C17-C20) : transport SPI AP ↔ capteur (trames `80 <cmd> <len>`, état 0x10/0x20, lecture 0x13, DMA SIO 0x18/0x19) : `vu`
  dans 4 captures, noms des commandes = hypothèses ; jamais rejoué par nous. Broches spi2 = 48/49/50 : hypothèse.
- SPI-3 (2026-11-10, MESA-HELLO, traces/20261110-005244_mesa_hello) : sans macOS, alimentation par gpio0 196 + trames 0x78, 0x10,
  0x70, 0x13 sur spi2 (CLKDIV 3, CPHA 1, pas de CS, broches laissées par iBoot) → identité du capteur identique à celle lue sous
  macOS : `vérifié` (2 essais identiques, 2e : traces/20261110-005318_mesa_hello2). Rend SPI-2 `vérifié` pour ces 4 trames seulement.
- SPI-4 (2026-11-10, LINUX-HELLO) : sous Linux (Fedora Asahi de test), spi2 ajouté à chaud (driver/linux/mesa_ovl.c + mesa-spi2-overlay.dts)
  et mesa_probe enable=1 → même identité du capteur : `vérifié` (1 essai). Le pilote public spi-apple suffit pour le transport.

- xART-CHAIN (2026-11-11, T-45/T-46/T-47, lecture seule) : le contenu OOL de l'EP 0x13 a été capturé et comparé sur 3 boots.
  `vérifié (octet pour octet)` : sur 10 lockers rendus au SEP, 8 sont identiques sur les 3 boots ; les 2 variables sont SEP-xART (TAG 0x03)
  et un locker Credential Manager (TAG 0x10, UUID 8624497a…) ; USER-xART (TAG 0x04) est stable. `save(N)=fetch(N+1)` confirmé sur le contenu
  (A094(cN+1)=B231(cN), A222(cN+1)=B229(cN)). Pas de compteur en clair. Mécanisme anti-rejeu (préfixe 16 o = nonce/MAC) = `hypothèse`.
  Que le SEP accepte un rejeu de la dernière sauvegarde quand Linux le boote = non testé (écriture SEP, pending/ + Albert).
