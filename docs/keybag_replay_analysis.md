# Rejouabilité de la séquence keybag-load de macOS (EP 0x12) depuis la capture

Rédigé le 2026-11-24 (agent analyste). **But** : répondre, sur la base des seules traces, à la question du pivot —
« la suite `load_keybag / make_system_keybag / device_state_transition` que macOS joue au login est-elle **rejouable**
depuis nos captures pour amener le SEP à `keybag chargé/déverrouillé` ? ».

Sources : `traces/20261108-032454_c12-boot-ho/sep.log` (boot **sans login** — timeout, 812 lignes SEP) et
`traces/20261108-025802_c11-doigt-tranchant/sep.log` (session interactive complète : login mot de passe, verrou/déverrou,
matchs doigt, lockout, auth applicative). Outil ajouté : `analysis/ep12_sequence.py` (séquence 0x12 appariée + comparaison
longueurs fil entre deux traces). Convention : **VU** = lu dans la trace (chiffres) ; **VU-kext** = lu au désassemblage
(cf. `sks_protocol.md`, `sks_keybag_unlock.md`) ; **INTERPRÉTÉ** = déduit ; **INCONNU** = non tranché. Rien n'est `vérifié`
(aucune expérience). Aucune écriture SEP.

---

## 0. LIMITE CAPITALE — l'OOL de l'EP 0x12 n'est PAS dans ces captures (VU)

La prémisse de la mission (« on a les OCTETS byte-exacts de tout ça dans les OOL capturés ») est **fausse pour l'EP 0x12**.
Vérifié :

- Tous les fichiers `.bin` des deux `sep.log.ool/` sont nommés `NNNNNN_08_*.bin` : le jeton central est l'**endpoint**,
  et il vaut **0x08** (sbio capteur) pour **100 %** des dumps (c12 : 139 fichiers, c11 : 911 fichiers, **0** fichier `_12_`).
- Dans les `sep.log`, toutes les lignes `# ool … EP=0x…` portent **`EP=0x08`** (c12 : 155/155, c11 : 998/998). **Aucune**
  ligne OOL `EP=0x12`.

⇒ Pour l'EP 0x12 on ne dispose **que du mot mailbox** de chaque message : `TAG` (opération), `TYPE` (compteur de txn),
`PARAM` (statut en réponse) et `DATA>>16` (**longueur fil** du corps OOL, en octets). **Le contenu DER / le corps IPC
(en-tête + données) n'est nulle part dans ces traces.** C'est cohérent avec ce que disaient déjà `sks_protocol.md` §1.2
et `sks_sequence_c12.md` (« OOL 0x12 jamais capturé »). Conséquence immédiate pour la mission : on **ne peut pas** décoder
les octets des `0x22` / `0x03` / `0x0d` / `0x18`, ni comparer leurs **octets** entre c11 et c12. Le test empirique
« champ qui diffère entre deux boots = fraîcheur » ne peut porter que sur la **longueur fil**, pas sur le contenu.

---

## 1. Cartographie de la séquence EP 0x12

### 1.1 Préfixe de bring-up (pré-login) — IDENTIQUE c11 et c12 (VU)

Les **17 premières requêtes** 0x12 sont identiques en `(TAG, longueur fil)` entre c12 et c11, position par position
(`analysis/ep12_sequence.py … --cmp`). C'est le bring-up keystore déjà décrit dans `sks_sequence_c12.md`. Extrait c12
(`traces/20261108-032454_c12-boot-ho/sep.log` L178…247) ; les noms d'op viennent de la table VU-kext `sks_protocol.md` §1.3 :

| # | L (c12) | `>` TAG | op (nom VU-kext) | req o | resp o | PARAM resp | remarque |
|---|---|---|---|---|---|---|---|
| 0 | 178 | 0x4d | get_capabilities | 0x64 | 0x5c | 0 | négociation en-tête IPC |
| 1 | 180 | 0x2a | set_env | 0x470 | 0x58 | 0 | |
| 2 | 182 | 0x22 | perform_operation | 0x8c | 0x14c | 0 | famille identité/system_key (§2.3) |
| 3 | 184 | 0x22 | perform_operation | 0x90 | 0xb8 | 0 | idem |
| 4 | 186 | 0x0a | null_d_key | 0x60 | — | 0xff | « rien à annuler » (bénin) |
| 5 | 188 | 0x32 | unwrap_media_key | 0x94 | 0xb4 | 0 | FileVault volume |
| 6 | 191 | 0x48 | fv_get_blob_state | 0x1dc | 0x110 | 0 | |
| 7 | 195 | 0x48 | fv_get_blob_state | 0x230 | 0x110 | 0 | |
| 8 | 198 | 0x41 | fv_unwrap_vek | 0x240 | 0xa0 | 0 | déverrou volume (passcode pré-boot) |
| 9 | 204 | 0x48 | fv_get_blob_state | 0x230 | 0x110 | 0 | |
| 10 | 206 | 0x47 | fv_set_protection | 0x244 | 0x60 | 0 | |
| 11-12 | 208/210 | 0x10 | new_pfk_data | 0xb8 | 0x0/0xec | 0xfe/0 | |
| 13 | 235 | 0x32 | unwrap_media_key | 0x94 | 0xb4 | 0 | |
| 14-16 | 237/244/246 | 0x48 | fv_get_blob_state | 0x1dc/0x230/0x1dc | 0x110 | 0 | |

Au-delà de la position 16, c11 et c12 **divergent** (ordre/nombre des polls, pas de login en c12) — divergence
**attendue** (activité de boot différente), pas une divergence de protocole.

### 1.2 Fenêtre « keybag au login » — c11 uniquement (VU)

Dans c12 (jamais loggé) la séquence keybag n'apparaît **pas**. Dans c11 elle survient **immédiatement après `pw_login`**
(mark `pw_login` @1794103203 ; keybag @1794103207), `traces/20261108-025802_c11-doigt-tranchant/sep.log` L836…850 :

| L | ts | `>`/`<` | TAG | op (nom VU-kext) | req o | resp o / PARAM | VU |
|---|---|---|---|---|---|---|---|
| 836 | …207.19 | > | 0x04 | get_device_state (poll) | 0x6c | —/0xfd | |
| 838 | …207.21 | > | **0x03** | **load_keybag** | **0x678** | — | req de **1656 o** |
| 839 | …207.25 | < | 0x83 | ↳ réponse | — | 0x5c / 0 | **OK** ; handle rendu dans l'OOL (non capturé) |
| 840 | …207.26 | > | **0x0d** | **make_system_keybag** | 0x6c | — | |
| 841 | …207.32 | < | 0x8d | ↳ réponse | — | 0x58 / 0 | **OK**, DATA bit0=1 (invalide cache) |
| 844 | …207.33 | > | 0x05 | (op non nommée dans §1.3) | 0x64 | — | |
| 845 | …207.33 | < | 0x85 | ↳ réponse | — | 0x58 / 0 | OK |
| 846 | …207.35 | > | 0x04 | get_device_state | 0x6c | — | |
| 847 | …207.35 | < | 0x84 | ↳ réponse | — | 0x64 / 0 | rend des données (0x64) |
| 848 | …207.35 | > | **0x18** | **device_state_transition** | 0x7c | — | |
| 849 | …207.38 | < | **0x00** | **NOTIF unlock** | — | DATA=**0xfffffe0b (-501)** | déverrou keybag **utilisateur -501** |
| 850 | …207.38 | < | 0x98 | ↳ réponse du 0x18 | — | 0x68 / 0 | DATA bit0=1 |

**VU** : `load_keybag` (0x03) puis `make_system_keybag` (0x0d) sont **acceptés** (PARAM 0), et c'est le
`device_state_transition` (0x18) qui **déclenche la notification de déverrouillage** `TAG 0x00 / handle -501` (le keybag
utilisateur). **INTERPRÉTÉ** : la chaîne de déverrouillage du keybag utilisateur au login mot de passe est
`load_keybag(0x03) → make_system_keybag(0x0d) → 0x05 → device_state_transition(0x18) → notif unlock -501`. (Le
déverrouillage du **volume** FileVault, lui, a eu lieu plus tôt, au bring-up — 0x41/0x32, §1.1.)

### 1.3 `0x22` (perform_operation) — ce qu'on peut en dire sans l'OOL

Trois `0x22` au bring-up (positions 2, 3, 19) + d'autres après login. Longueurs fil VU :
- bring-up : req 0x8c (resp 0x14c), req 0x90 (resp 0xb8), req 0x90 (resp 0xa0) — **mêmes longueurs en c11 et c12**.
- c11 ajoute au login des `0x22` plus gros : req **0x20c** (×1) et **0x258** (×2) — absents de c12.

Le sélecteur `o` (osc/oska/oskc2/oskgp…), les champs `skt/skg/skcs`, et l'éventuel OCTET STRING ~16-20 o (seed/nonce)
évoqués dans la mission sont dans l'**OOL** → **INCONNU ici** (jamais capturé). Le reverse (`sks_protocol.md` §2.3) pose
que ces `0x22` de tout début de boot sont vraisemblablement la **famille identité/system_key** (handle keybag = -1, ni
`rk` ni `acmh`), et que la paire supplémentaire de 16-20 o **pourrait** être `skcs` (client_seed) — **un seed de session
serait de la fraîcheur** ; mais c'est **non tranché** (ni capturé, ni confirmé matériel).

---

## 2. create_keybag / make_system_keybag / load_keybag : présents ou non ? (VU)

Recherche exhaustive sur **toutes** les traces (`> EP=0x12 TAG=0x01|0x03|0x0d`) :

| op (TAG req) | présence | détail |
|---|---|---|
| **create_keybag (0x01)** | **ABSENT de TOUTES les traces** | aucune requête `> 0x12 TAG=0x01` nulle part. macOS **ne crée jamais** de keybag sur cet appareil. **VU.** |
| **load_keybag (0x03)** | **PRÉSENT** | c11 (L838, req 0x678), et aussi c1, c3, c6, c15, c18 — **à chaque login**. Absent de c12 (jamais loggé). **VU.** |
| **make_system_keybag (0x0d)** | **PRÉSENT** | mêmes traces que 0x03, systématiquement juste après (c11 L840, req 0x6c). **VU.** |

> ⚠️ Correction à la prémisse de la mission. Il est **exact** que macOS ne fait **jamais** `create_keybag` (0x01). Mais il
> est **faux** de dire qu'il ne fait que « load/unlock d'un keybag existant » : il fait **aussi `make_system_keybag`
> (0x0d)** à chaque login. Ce sont précisément les trois ops (0x01 écarté, 0x03, 0x0d) que l'équipe native a tenté de
> rejouer et qui ont **toutes renvoyé -0xb** (journal : « load_keybag aussi refusé -11 … 3 ops/3 butent **sans les vraies
> valeurs** »). Le présent travail explique **pourquoi** (§3-4) : les « vraies valeurs » (le blob de 0x678 o) sont dans
> l'OOL, qui n'est ni dans la capture ni reproductible hors-ligne.

---

## 3. Tableau de rejouabilité (par message)

« Rejouable » = ré-émettre les **octets capturés** amènerait le SEP au même état. Deux obstacles indépendants :
**(O1)** les octets ne sont pas dans la capture (§0) ; **(O2)** même si on les avait, le message porte-t-il de la
fraîcheur par session/boot ? Faute d'OOL, O2 est jugé sur la **longueur fil** (VU, c11 vs c12) + le **modèle de corps
reversé** (VU-kext). Longueur identique = nécessaire mais **PAS suffisant** (un nonce de taille fixe ne change pas la
longueur).

| message | longueur fil c11 vs c12 | corps (VU-kext) | fraîcheur ? | rejouable depuis la capture ? |
|---|---|---|---|---|
| **En-tête IPC (TOUS les 0x12)** | n/a | en-tête 0x54 o : horodatage µs monotone + condensé SHA-256/16 (`sks_protocol.md` §1.6) | **OUI, par message** (horodatage + digest changent à chaque message et chaque boot) | **NON tel quel** ; mais **reconstructible** sans secret (base du condensé connue) |
| get_capabilities (0x4d) | IDENTIQUE (0x64) | en-tête v1 + état + u64=1 | header seul | NON tel quel ; reconstructible (§1.6) |
| set_env (0x2a) | IDENTIQUE (0x470) | blob env (version, mode, `cpx-encryption-mode`) | header seul ; corps quasi-constant | NON tel quel ; reconstructible (§1.7) |
| perform_operation (0x22) bring-up | IDENTIQUE (0x8c/0x90) | SET DER identité/system_key ; possible `skcs` seed 16-20 o | header + **seed possible = INCONNU** | **INCONNU** (OOL jamais capturé) |
| unwrap_media_key (0x32) | IDENTIQUE (0x94) | clé média **enveloppée** (blob disque APFS) | blob **scellé au volume macOS** | **NON** (blob disque, secret, absent) |
| fv_get_blob_state (0x48) | IDENTIQUE (jeu de longueurs) | sonde l'état d'un VEK/keybag de **volume macOS** | — | NON (pas d'objet hors macOS) |
| fv_unwrap_vek (0x41) | req 0x240 présent des 2 côtés | VEK+KEK enveloppés + **credential/passcode** (blob OOL) | blob scellé + **secret utilisateur** | **NON** (secret + blob disque, absents) |
| **load_keybag (0x03)** | c11 seul ; req **0x678** | **blob de keybag utilisateur** (depuis le disque APFS) | blob **propre au volume/à l'utilisateur** | **NON** (blob disque de 1656 o, absent et non reproductible hors-ligne) |
| **make_system_keybag (0x0d)** | c11 seul ; req 0x6c | scalaires (type/génération/flags), **pas de blob secret visible** côté AP | header + scalaires ; **INCONNU** si un scalaire porte une génération de session | **INCONNU** (corps non capturé ; chemin identité d'appareil, effet et persistance non tracés) |
| **device_state_transition (0x18)** | c11 seul ; req 0x7c | **handle de keybag** + scalaires d'état | dépend du **handle** rendu par load_keybag (étape précédente) | **NON tel quel** (challenge/réponse : handle dynamique issu de l'étape d'avant) |

Note VU utile pour O2 : sur les ops **constantes par nature** (get_capabilities, set_env) la longueur fil est **identique**
c11↔c12, ce qui est cohérent avec un bring-up déterministe. Mais cela **ne prouve pas** l'égalité des octets : l'en-tête
IPC (horodatage + digest) garantit au contraire qu'ils **diffèrent** à chaque message (VU-kext). On ne peut pas trancher
plus finement sans capturer l'OOL 0x12.

---

## 4. Séquence minimale « keybag chargé/déverrouillé » et verdict

Suite minimale observée (c11, login mot de passe) :
`load_keybag(0x03) → make_system_keybag(0x0d) → [0x05] → device_state_transition(0x18) → notif unlock -501`.

- **load_keybag (0x03)** : exige le **blob de keybag de 0x678 o**. Ce blob est lu **du disque APFS macOS** (keybag
  utilisateur), **propre au volume/à l'utilisateur**, **absent de la capture** et **non fabricable hors-ligne**. **MUR.**
- **make_system_keybag (0x0d)** : pas de blob secret visible côté AP (VU-kext), mais corps non capturé ; effet sur le
  gating bio et persistance xART **INCONNU** (hors bundle AppleSEPKeyStore).
- **device_state_transition (0x18)** : porte un **handle** ; dans la capture la notif rend le handle fixe **-501**
  (keybag utilisateur), mais l'étape dépend de l'état posé par load_keybag → **challenge/réponse** : non statiquement
  rejouable (il faut la réponse dynamique du SEP à l'étape précédente).

### VERDICT

**La séquence keybag-load de macOS N'EST PAS rejouable depuis ces captures. NON.** Ce qui bloque, par ordre de dureté :

1. **O1 — les octets n'y sont pas.** L'OOL de l'EP 0x12 n'a jamais été tracé (§0). On n'a aucun corps à rejouer pour
   `0x22/0x03/0x0d/0x18/0x41/0x32`. C'est l'obstacle **immédiat** et il est total.
2. **O2a — le byte porteur est un secret disque.** `load_keybag` a besoin d'un **blob de keybag de 1656 o** scellé au
   volume/utilisateur macOS ; `fv_unwrap_vek` d'un VEK enveloppé + du passcode. Même avec l'OOL capturé, ces octets
   seraient des **secrets propres à l'appareil/au volume** — hors périmètre (non extraits), et **inexistants sur un OS
   Linux**. C'est exactement le -0xb « sans les vraies valeurs » qu'a rencontré l'équipe native.
3. **O2b — fraîcheur par message.** Tout message 0x12 porte un en-tête IPC avec horodatage µs monotone + condensé
   SHA-256/16 (VU-kext) → **aucun** message n'est rejouable **octet pour octet** ; l'en-tête doit être **reconstruit**
   (faisable sans secret). Et `device_state_transition` dépend d'un **handle dynamique** (challenge/réponse).

### Ce que ça implique pour les deux pistes « SANS DFU » du handoff

- **Piste B (rejouer le keybag macOS depuis le disque via apfs-fuse)** est **la seule cohérente** avec ce qu'on voit :
  le mur de `load_keybag` est précisément le **blob de 0x678 o**, qui **vit sur le disque APFS**. Le récupérer **tel qu'il
  est sur le disque** (pas depuis la capture, qui ne l'a pas) est la condition nécessaire. **Attention** : ce blob seul ne
  suffit pas — il faut aussi (a) reconstruire l'en-tête IPC par message (VU-kext, faisable), et (b) gérer `0x18` en
  **live** (handle rendu par le SEP), donc ce n'est **pas** un pur rejoué, mais un dialogue.
- **Piste A (pré-séquence system_key/identité avant keybag)** touche aux `0x22` du bring-up : leur contenu (seed `skcs` ?)
  est **INCONNU** faute d'OOL — on ne peut ni la confirmer ni la rejouer depuis la capture.
- Capturer l'**OOL de l'EP 0x12** (re-tracer avec le filtre OOL élargi à 0x12, cf. `sks_sequence_c12.md` §4) lèverait O1
  et permettrait enfin le test octet-à-octet c11↔c12 demandé — mais pas O2a (le blob resterait un secret disque).

### Points ouverts (honnêtes)
- Contenu octet de tout message 0x12 : **jamais capturé**. Tout « byte-exact » annoncé sur 0x12 est une erreur de prémisse.
- `skcs`/seed dans les `0x22` de bring-up = nonce de session ou constante : **INCONNU**.
- `make_system_keybag` (0x0d) rejouable (corps = scalaires sans blob) ? corps non capturé → **INCONNU** ; et son effet +
  persistance xART : hors trace.
- Handle de `device_state_transition` : la notif montre -501 (constante connue), mais le lien exact avec la réponse OOL de
  `load_keybag` n'est pas observable (OOL absent).
- Rien de ceci n'est `vérifié` : aucune expérience ; tout verdict de rejouabilité repose sur longueurs fil (VU) + reverse
  (VU-kext), pas sur un rejoué matériel.
