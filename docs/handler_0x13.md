# Handler EP 0x13 (xART) — design du driver natif

2026-11-19 — Claude. Hors-hardware. Design du handler 0x13 pour la route native (`route_native.md` §3, étape 2).
Sources : `gigalocker.md` (protocole FETCH/SAVE décodé), `messages.md` §xART, `pending/sep_xart_replay.sh`
(SERVE_GL = handler 0x13 déjà écrit en script), captures `snew-reel`/c1/c8. Rien d'écrit vers le SEP.

## 0. L'idée clé : le handler natif est l'OPPOSÉ de SERVE_GL
- **SERVE_GL (rejeu, échoue)** : on **rend à la puce le coffre capturé de macOS**. Elle le juge non-courant →
  veut re-sceller (SAVE) → on s'arrête → mur. On essaie de *falsifier* un état scellé : impossible (`route_native.md` §2).
- **Handler natif (le bon)** : Linux **n'a pas encore d'état xART**. Donc au boot, quand la puce FETCH ses lockers,
  on répond **« absent »** → la puce **crée un état frais** et le **SAVE** → le driver **stocke** ce blob dans le
  **stockage xART de Linux**. Au boot suivant, on le lui **rend**. On ne falsifie rien : **le SEP scelle son propre
  état frais pour Linux**, exactement comme pour macOS. C'est ça qui donne l'état scellé légitime qui **arme sbio**.

## 1. La machine à états (requêtes SEP `<` → réponse AP `>`, même TAG)
Toutes VU dans les captures (`gigalocker.md §Protocole`, `messages.md`). La **logique** de réponse en mode natif
est notée ci-dessous ; ce qui change vs SERVE_GL est en **gras**.

| le SEP demande (`<`) | op | réponse du handler NATIF | statut |
|---|---|---|---|
| TAG 0x02 TYPE 0x0e | état fw-boot | acquitter (A vide, `DATA=0x100`) | VU (ack) |
| TAG 0x01 TYPE 0x13 | UUID d'OS | écrire 16 o d'UUID de l'« OS courant » (**= un UUID propre à Linux**, cf. §3) | VU (format) / UUID Linux = **ouvert** |
| TYPE 0x00 | FETCH maître (sel 0/1) | **si maître Linux en stock → le rendre ; sinon → réponse ABSENT** | VU (présent) / absent = **hypothèse** |
| TYPE 0x05 | FETCH gigalocker (UUID en B) | **chercher l'UUID dans le store Linux ; présent → rendre ; absent → ABSENT** | VU (présent) / absent = **hypothèse** |
| TAG .. TYPE 0x07 | locker-absent (réponse) | c'est NOTRE réponse quand rien en stock (macOS l'émet aussi : snew-reel TAG=0x0b) | VU (existe) |
| TYPE 0x1d | annonce d'endpoint | acquitter `> TYPE=0x16 DATA=(DATA & 0xFFFFFF00)`, continuer | VU |
| TYPE 0x01 / 0x06 | **SAVE** (xART maître / locker) | **ACK + STOCKER le blob (B) dans le store Linux** ⚠️ écriture SEP | ACK = **PORTE Albert** |

**Format réponse FETCH** (VU, `gigalocker.md`) : longueur écrite en A = `PARAM | (DATA[0]<<8)` → le driver
**recalcule** PARAM/DATA0 depuis la taille du blob rendu (ne pas rejouer la valeur capturée). `DATA[1]` =
drapeau ré-émis tel quel depuis la requête (sélecteur maître / 0x00-0x01 gigalocker). CRC = **dans** le blob (+0x16),
pas dans le message.

## 2. Ce qui change DE FOND vs SERVE_GL (à coder)
1. **Branche « ABSENT »** : SERVE_GL sert toujours un blob (depuis le `.gl` macOS). Le handler natif doit, pour un
   locker **non présent dans le store Linux**, répondre **locker-absent (TYPE 0x07)** au lieu de servir du macOS.
   → c'est ce qui autorise la puce à **créer du frais**.
2. **Brancher le SAVE au lieu de s'arrêter** : SERVE_GL fait fail-closed sur SAVE (anti-brick, voulu). Le handler
   natif, lui, doit **acquitter le SAVE et persister le blob** (tampon B) dans le store Linux, indexé par type
   (maître 0x01/0x02) ou par UUID (gigalocker 0x03/0x04). ⚠️ **C'est l'écriture SEP** = porte Albert + récupérable
   (casser gigalocker = DFU, `stockholm-se-brick-definitif`).
3. **Store xART Linux** : un fichier/zone qui joue le rôle du `.gl` de macOS (format VU `gigalocker.md §Structure` :
   slots 0x9000, en-tête type/UUID/longueur/CRC à +0x01/+0x02/+0x12/+0x16, charge à +0x22). Vierge au 1er boot.

## 3. Questions ouvertes (à ne pas masquer)
- **UUID d'OS (op 0x13)** : macOS renvoie `apfs-preboot-uuid`. Les volumes Linux ne sont pas APFS. **Quel UUID
  renvoyer** pour que la puce associe l'état scellé à « l'OS Linux courant » ? Candidats : UUID du volume racine,
  ou un UUID fixe propre au driver. **Ouvert** — à vérifier sur le 1er boot réel.
- **« Absent → frais » marche-t-il vraiment ?** On sait **émettre** le locker-absent (0x07, VU). Que la puce
  réponde en **créant un état frais qui arme sbio** = **jamais testé** — c'est **LE** pari de la route native
  (`route_native.md` §6). Hypothèse, à trancher par l'expérience.
- **Octet-près de l'en-tête A** (préfixe maître 0x11 vs gigalocker à l'offset 0) : non tranché sur captures
  (`gigalocker.md §Point ENCORE ouvert`). Peu grave en natif (nos propres SAVE/FETCH seront cohérents entre eux),
  mais à fixer au 1er boot.
- **Enrôlement** : un état xART frais côté Linux n'a **aucune empreinte** (les gabarits macOS sont scellés à macOS).
  → Linux aura besoin de son **propre enrôlement** (`driver_plan.md` C-D, « autre chantier »).
- **⚠️ COEXISTENCE macOS/Linux (question clé, soulevée par Albert 2026-11-19).** Le stockage du SEP a deux niveaux
  (`gigalocker.md`) : les **gigalockers** (indexés par UUID, par volume → **namespaçables**, Linux peut avoir les
  siens sans toucher macOS) ET le **MASTER xART** (SEP-xART/USER-xART, **sans UUID**, un seul au niveau **appareil**,
  dans le volume xART de l'iBootSystemContainer → **partagé**, c'est la racine anti-rejeu de la puce).
  - **Fait gênant (forte inférence, n=1)** : le brick voie C = un **SAVE du MASTER** (premier SAVE, 127 o, sans UUID,
    `gigalocker.md §Structure du blob RE-SCELLÉ`) → et c'est ce qui a **tué macOS**. Donc re-sceller le master sous
    boot permissif **désynchronise macOS**.
  - **La question qui décide du dual-boot** : la route native peut-elle établir l'état xART de Linux **en ne touchant
    QUE ses propres gigalockers** (namespacés), ou doit-elle faire **re-sceller le MASTER partagé** ? Si c'est le
    master : (a) ça clobbe macOS (tolérable, macOS sacrifiable + DFU), MAIS (b) risque de **thrash dual-boot**
    (chaque OS réinvalide le SEP de l'autre à chaque bascule) → Touch ID Linux **fragile**. Apple gère le multi-OS
    via **LocalPolicy / « OS identity » par OS** + un master monotone géré proprement par le SEP ; notre boot
    **permissif** ne suit pas ce protocole → d'où le risque de désync. **Non tranché** — à regarder dès les 1ers
    boots natifs : le handler natif doit-il répondre « absent » aussi pour les **maîtres** (laisser la puce créer un
    master Linux distinct), et le SEP maintient-il un master **par OS** ou **un seul partagé** ? (le blob master est
    opaque → à observer, pas à supposer.)

## 4. Ce qui est codable/testable MAINTENANT (hors-hardware) vs la porte
- **Hors-hardware, tout de suite** : (a) le **parseur/encodeur** des messages 0x13 (déjà en Python dans
  `sep_xart_replay.sh` ; à porter proprement dans `driver/`) ; (b) la **machine à états** FETCH/SAVE/absent et le
  **store** (lire/écrire le format `.gl`), **testés en rejeu** contre une capture (`snew-reel`, c1, c8) : on vérifie
  que pour une requête donnée, le handler produit la bonne forme de réponse (longueur recalculée, drapeau ré-émis,
  branche absent correcte). Aucune émission vers le SEP.
- **Porte matérielle (Albert)** : le **boot SEPOS est déjà fait** en routine via le harnais proxyclient
  (`sep.boot()`, ouverture de chaque run voie C — PAS une porte à rouvrir). La porte, c'est que le handler natif
  **acquitte le SAVE** (écriture : avance le compteur scellé). Donc le 1er run réel est **100 % décision Albert**,
  après backup, en sachant qu'un DFU peut suivre.

## 4bis. État au 2026-11-20 (hors-hardware fait)
- **Codec 0x13 + parseur du coffre** (`driver/sepreplay/xart.py`, step6) : FAIT, 7 tests verts.
- **Modèle de la réponse AP, VU** (`driver/sepreplay/xart_responder.py`, step7) : FAIT, 8 tests verts,
  **validé en reproduisant snew-reel ligne à ligne** (les 30 échanges : ack fw-boot, UUID, FETCH
  longueur+sélecteur, ack locker-absent, **ack SAVE** `DATA & 0xFFFFFF00`, ack annonce 0x16). C'est le
  côté AP observé — la base commune du handler natif.
- **Divergences natives** (`native_fetch_decision` / `native_on_save` dans le même module) : écrites mais
  marquées HYPOTHÈSE, **non testées contre une capture** (aucune n'existe). Ce sont les 2 seuls points où
  Linux s'écarte de macOS (branche ABSENT ; persist-on-SAVE).
- **Store xART : lecture ET écriture faites (VU).** `xart.parse_coffre` (lecture) + `serialize_locker`/
  `build_header` (écriture), CRC du slot **VÉRIFIÉ** (`slot_crc` = `zlib.crc32` de la charge, 12/12 ;
  round-trip d'un slot à l'octet près, testé step6). → persist-on-SAVE a où ranger le blob.
  **Restes non-VU** : (a) le **u16 à +0x1a** de l'en-tête (rôle inconnu, mis à 0, ⚠️ à confirmer avant un
  vrai SAVE natif) ; (b) la **POLITIQUE** (quand répondre absent / quand persister) = hypothèse, porte Albert.
- **Reste à coder hors-hardware** : brancher la machine à états native (observer `xart_responder` +
  store) bout à bout et la tester en rejeu — sans jamais émettre. Puis la porte matérielle (Albert).

## 5. Prochain pas concret proposé
1. (hors-hardware) Extraire de `sep_xart_replay.sh` la logique 0x13 en un module **`driver/`** propre, avec la
   **branche ABSENT** et un **store** lisible/écrivable au format `.gl`, + **tests de rejeu** sur une capture.
2. (hors-hardware) Préparer le script `pending/` du **boot SEPOS natif** (DT alias+okay + IMG4), en-tête
   but/risque/résultat, pour qu'Albert puisse l'armer quand il décide d'ouvrir la porte.
3. (porte Albert) 1er boot SEPOS + handler natif en mode « absent → laisse sceller → stocke le SAVE » → observer
   si la puce va jusqu'à **annoncer + armer sbio**. C'est l'expérience qui transforme « faisable » en « ça marche ».
