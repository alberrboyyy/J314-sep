# J6 — enrôlement puis match Touch ID : protocole, octet-près, et les murs (source: trace + kext)

2026-11-22 — agent driver (session ALARM). But : établir, AVANT de coder la réponse (règle CLAUDE.md « protocole
avant de répondre »), la séquence EXACTE de l'enrôlement et du match qui suit le repos final de la 2e passe (J5c
pass2), pour une session humaine. **Portée protocole/séquence/format uniquement. Aucune donnée biométrique.**

Marquage : **VU** = lu dans une capture (fichier:ligne) ou un désassemblage (adresse) ; **hypothèse** = interprété.
Rien ici n'est `vérifié` au sens natif (aucun enroll/match n'a jamais tourné hors macOS). Sources :
- **trace** : `traces/20261110-003201_c20-doigt-spi` (C20 : SEP `sep.log` + OOL `sep.log.ool/*_08_*.bin` + SPI
  `sio.log`/`sio.bufs` ; 7 matchs doigt, TOUS des succès uid 0x1f5), recoupé C8 (`…004657_c8-doigt-ool`),
  C11 (`…025802_c11-doigt-tranchant`), C6 (`…043828_c6-doigt-ool`). Outils : `analysis/sio_dialog.py --sep`,
  `analysis/sbio_transactions.py`, `analysis/sbio_gt_packet.py`.
- **kext** : `docs/sbio_enroll.md`, `docs/sbio_match.md`, `docs/kext_sepmanager.md` §6/§7/§12c/§12d, `docs/messages.md`
  §SBIO. `docs/verification_status.md` : verdict 0x09 (`match_info_t`) et image 0x65 (0x7200, CRC16/ARC) = **vérifié**.

> **AUCUNE trace d'enrôlement n'existe dans le repo.** Toutes les captures doigt sont des MATCHS. La séquence
> d'enrôlement ci-dessous est donc **entièrement `source: kext`** (sbio_enroll.md) ; seule la séquence de match est VU
> en trace.

---

## 0. Ce qui précède : repos final de J5c pass2 (VU C20)

Après le 2e `< 0x63` de la 2e passe (J5c pass2, repos où notre code s'arrête, capteur éteint par sbiod), macOS
**n'éteint pas** le capteur et enchaîne (VU C20 `sep.log` ~34.72 s) : `0x7c` GetBioDeviceList → `0x6b 0x79`
(GetCatacombState/GroupState) → **`0x6d` LoadCatacomb** (le gabarit scellé, fragmenté AP→SEP, = dernier export `0x6c`)
→ `0x39` → `0x2b` → `0x54` RequestTopologyOfTemplate → requêtes clients → `0x71` LoadBioLockoutRecord → `0x28` →
`0x7d` updateOperationDeviceList → polling. **C'est l'état « prêt pour un doigt ».** Le `0x6d` charge **les gabarits
existants** ; sans gabarit chargé, `checkAutoMatchConditions` (kext) bloque (`isAtLeastOneWithTemplates` faux, §3).

Conséquence pour Linux (hypothèse) : pour un **match**, il faut d'abord **des gabarits chargés** (0x6d). Pour en
avoir, il faut avoir **enrôlé**. Les gabarits macOS sont scellés à l'état macOS (xART macOS) et **ne se chargent pas**
sur notre xART frais Linux → **un enrôlement natif est le préalable obligatoire au premier match natif.**

---

## 1. MATCH — séquence fil, VU C20 (octet-près)

Déclencheur : **doigt posé**. Côté capteur SPI (VU C20 `sio.log`, `spi2.log`) :
1. En veille, l'AP interroge l'état (`80 10`, corps `11 02 21 80 04 80808080` = pas de doigt) toutes ~0,5 s ; la
   broche **IRQ gpio195** est armée « niveau haut ».
2. Doigt → IRQ 195 monte → l'AP lit l'état : corps `13 00 21 00 0e …` puis `07 00 21 00 8e 00 72 00 00` =
   **octet d'état 0x07 (réponse prête) + longueur en attente 0x7200** (12×0x980).
3. L'AP lit l'image : `> 80 13 00 0b 00000000 72 0000` (demande 0x7200), puis lecture full-duplex de **0x7200 o**
   (`RX 0x7200`, en-tête de tranche `80 52 NN 80 09 …`). **Image = VU, structure vérifiée** (CRC16/ARC, 12 tranches,
   `verification_status.md`). Chiffrée capteur↔SEP (l'AP relaie des octets).

Côté SEP (VU C20, une transaction `0xfc` par opcode), **recoupe la séquence `vérifiée` de `messages.md`** :

| ordre | op | A (AP→SEP) | B (SEP→AP) | rôle (kext) | classe |
|---|---|---|---|---|---|
| 1 | 0x23 | 0 | 0 | asyncCapture : début de tentative | [SEP] |
| 2 | 0x06 | **0xa7** | 0 | `_lastImageProcessingParams` (**D6**, origine non lue — voir §4) | [BLOB-INCONNU] |
| 3 | 0x65 | **0x7200** (2 frags fe/fd) | 0 | l'**image** lue en (3) ci-dessus, recopiée au SEP | [FINGER] |
| 4 | 0x07 | 0 | **0xc0** | résultat d'image : `+0x06/07`=`01 01` → exploitable, `00 00` → relance | [FINGER] |
| 4b | 0x22 | 0 | 0 | (si image inexploitable : abandon, retour à 1 ; VU C20 659 s) | [SEP] |
| 5 | 0x1e | 0 | 0 | handleMatch : étape (présente quand 0x07 dit exploitable mais `+0x00`=2) | [SEP] |
| 6 | **0x09** | **0** | **0xca2** | **le VERDICT** `match_info_t` (voir §2) | [FINGER] **vérifié** |
| 7 | 0x1f | 0 | 2 (`05 05`) | cacheMatchPolicy | [SEP] |
| 8 | 0x22 | 0 | 0 | kEnableBgOpsUpdate (fin de tentative) | [SEP] |
| 9 | 0x0b | 0 | 0 | commandCancel (fin) | [SEP] |
| — | `< 03` | — | — | notif SEP « template list » → déclenche 0x21 | [notif] |
| 10 | 0x21 | 0 | 0xc8e | checkBgOpsResult (récap) | [SEP] |
| 11 | 0x70 | 0 | 0x69 | SaveBioLockoutRecord (`HRLB`, sortie à stocker par l'AP) | [BLOB-SORTIE] |

**Plusieurs images par pose** (VU C20 712 s) : le SEP redemande des captures (`0x23 06 65 07` répétés, 6× dans une
pose) jusqu'à décider ; **une seule `0x09` par pose** émise quand il tranche. Entre deux `0x65` : lecture SPI d'une
nouvelle image (0x7200). Le compteur `+0x40` de 0x06 croît par capture (VU), `+0x48` = n° d'abandons depuis la
dernière capture complète (VU 46/46), `+0x44` u32 = compteur qui croît lentement (pas un indice de doigt, HJ).

**Après un match réussi** (VU C20 634 s) : le gabarit **s'adapte** → le SEP ré-exporte le catacomb :
`0x6b 0x79 → 0x6c (PrepareSaveCatacomb, frag SEP→AP) → 0x37 (ConfirmSaveCatacomb) → 0x33 → 0x6c → 0x37`. L'AP doit
**stocker le blob `0x6c`** et le re-servir en `0x6d` au boot suivant (HO `vérifié` : macOS réimporte le dernier
export). → le driver Linux devra persister ce blob (fichier AP), comme macOS.

### 1.1 commandStartMatch 0x27/0x25 — ABSENT (VU négatif, `vérifié`)
`messages.md`/K7 : **0 occurrence** de 0x27/0x25/0x03 sur 15 traces. Le match macOS observé est le chemin
**auto-match** : `checkAutoMatchConditions` arme sans `commandStartMatch`, donc **sans acmContext sur le fil**. Le
driver Linux peut suivre ce chemin (pas d'acmContext à fabriquer) — **à la seule condition** que le SEP n'exige pas
l'armement (non tranché, §3).

---

## 2. Le verdict 0x09 — `match_info_t`, 0xca2 o (VÉRIFIÉ, le driver le lira)

`verification_status.md` + `messages.md` §0x09, reconfirmé C20 (`001721_08_B.bin`…) :
- `+0x00` u32 : **0x1f5** = uid 501 (correspondance) ; **0xffffffff** = refus.
- `+0x04` 16 o : identifiant du gabarit (`fe6003d8…371b` sous macOS) ; zéros au refus.
- `+0xc24` u32 : score/raison (succès 1-4, refus ≥ 5) — hypothèse.
C'est le signal « doigt reconnu ». Le parseur existe déjà (`analysis/sbio_gt_packet.py`, `sbiod` tests).

---

## 3. D2 — faut-il SKS / keybag (EP 0x12) pour enrôler/matcher ? (le mur)

**Ce que montrent les traces (VU) :**
- EP 0x12 (SKS) est **ouvert et actif** dans tous les boots macOS (C1 : 579 requêtes). Le match C20 a lieu **session
  déverrouillée** (uid connecté). Le lockState au boot = 0x0015 (verrouillé + **blocage bio**), passe à 0x0208
  (déverrouillé bio) après le code (`messages.md` §6).
- Les notifs `< 0x08 TAG 0x01 TYPE 0x08` (lockState 0x0208) accompagnent chaque 0x09 (VU C20).

**Ce que dit le kext (VU, sbio_match.md §3) :** le **gating de match est fait CÔTÉ AP** : `checkAutoMatchConditions`
exige `isEnabledForUnlock` **et** `isAtLeastOneWithTemplates` **et** pas de lockout, AVANT tout envoi. Le kext ne
contient **aucun** chemin où 0x09 part sous blocage bio. Donc l'absence de 0x09 en session verrouillée est
**entièrement explicable côté AP** : macOS s'abstient.

**Non déterminé (honnête) :** on **ne peut pas** savoir depuis le binaire si le **SEP lui-même** refuserait un 0x09
(ou l'enroll 0x03) sous keybag verrouillé / sans keybag. **Indice protocolaire** : l'armement 0x27/0x25 transporte un
acmContext (jeton d'autorisation issu du keystore) — **mais il n'est pas émis** sur le chemin auto-match observé. Si
le SEP valide un acmContext, il faudrait l'EP 0x12. Hypothèse, non tranchée.

**Notre état natif Linux :** EP 0x12 (SKS) **n'a JAMAIS été ouvert** (route native = seal xART frais, pas de keybag
utilisateur). Donc :
1. **Pas de gabarit** (jamais enrôlé nativement ; les gabarits macOS ne se chargent pas sur notre xART frais) →
   `isAtLeastOneWithTemplates` serait faux → **rien à matcher**.
2. **Pas de keybag** → si le SEP exige un keybag déverrouillé (ou un acmContext) pour enrôler/sceller un gabarit ou
   pour 0x09, l'opération est bloquée.

→ **D2 est bloquant pour J6** : le premier match natif suppose un gabarit, qui suppose un enrôlement, qui suppose
(peut-être) le keybag. **EP 0x12 jamais ouvert chez nous = l'étape bloquante possible.**

---

## 4. ENROLL — séquence fil (source: kext uniquement, sbio_enroll.md) et le 2e mur

Aucune trace. D'après `sbio_enroll.md` (désassemblage AppleMesaSEPDriver) :
```
START  → 0x03 commandStartEnroll, A = enroll_indata_v2_t (0x44 = 68 o)   [contenu INCONNU, §4.1]
         met _commandMode = kCommandModeEnroll (3)
BOUCLE de poses (N décidé par le SEP, pas un compteur AP) :
   doigt posé → capture (asyncCaptureHandler : 0x23 0x06 0x65 0x07, = §1 étapes 1-4)   [FINGER]
   0x1e  (A 0)                                                                         [SEP]
   0x08  (A 0, B = enrollment_info_t 0xc98 = 3224 o)  « plie l'image dans le gabarit »
         parse : +0x02 u16 = erreur (0=OK) ; +0x04 = progression ; +0xbfe u32 = COMPLETE
   doigt retiré → 0x08 (sans image, postFingerOff)
   jusqu'à +0xbfe ≠ 0 (COMPLETE)
FIN    → enregistre l'identité (+0xc02 16 o) ; pas d'opcode fil dédié ; puis export catacomb
         0x6c (= §1 post-succès) à stocker par l'AP, re-servi en 0x6d au boot suivant
STOP/annulation → commandStopEnroll : _commandMode=1, pas d'opcode fil
```
Le match d'enrôlement émet **0x08** (pas 0x09). Nombre de poses **non fixé** (le SEP décide via `+0xbfe`). Le gabarit
**reste dans le SEP** ; l'AP ne reçoit que progression + code d'erreur + un identifiant. L'export final (0x6c) est le
blob « catacomb » à persister côté AP.

### 4.1 Le mur n°2 : `enroll_indata_v2_t` (68 o) INCONNU
`commandStartEnroll` envoie 68 o au SEP, **tel quel**, fournis par biometrickitd (userspace). **Contenu non lu**
(sbio_enroll.md §8.1). On ne peut donc **pas** émettre un `0x03` correct nativement sans le reverser (côté
biometrickitd / IOBiometricFamily) ou le capturer (aucune trace d'enroll). Le seul bit connu : `w8 & 1` du 1er u32 =
un flag de mode (hypothèse). → **bloqueur dur et distinct de D2.**

### 4.2 D6 : le 0x06 (0xa7 o) de la capture — INCONNU
VU (46/46 captures) : `+0x00`=0x89, `+0x44` u32 (compteur lent), `+0x48` u32 (n° d'abandons), `+0x40` u32 (compteur
par capture, croît), `+0x64` = uid 0x1f5, `+0x93`=0x10, **`+0x97..0xa6` 16 o = nonce par verrouillage** (identique
dans un même lock, change au lock suivant). Origine `_lastImageProcessingParams` **non lue** ; le nonce est lié aux
événements keybag (lockState). → **sur notre état sans keybag, on ne sait pas construire un 0x06 valide.** Le SEP le
valide-t-il ? inconnu. **Bloqueur, lié à D2.**

---

## 5. Liste EXHAUSTIVE des opcodes connus (règle FOLLOW) et des inconnus

Pour une porte fail-closed (CLAUDE.md « liste des connus exhaustive »). « connu » = place + rôle identifiés.

- **Match, connus (VU trace + verrou de verdict vérifié) :** 0x23, 0x06, 0x65, 0x07, 0x1e, 0x09, 0x1f, 0x22, 0x0b,
  0x21, 0x70 ; notifs `< 01` (lockState), `< 03` (template list). Pré-match : 0x7c, 0x6b, 0x79, 0x6d, 0x39, 0x2b,
  0x54, 0x33, 0x36, 0x6e, 0x7a, 0x28, 0x7d, 0x40. Post-succès : 0x6c, 0x37.
- **Enroll, connus (source: kext seulement) :** 0x03, 0x1e, 0x08 ; capture partagée 0x23/0x06/0x65/0x07.
- **Payloads INCONNUS (ne peuvent PAS être fabriqués) :** 0x03 (68 o, §4.1), 0x06 (0xa7 o nonce, §4.2). → toute
  tentative de les émettre = valeur devinée = **probe**, pas un relais fidèle.
- **Opcodes jamais vus / non requis :** 0x27/0x25 (commandStartMatch, absents = vérifié), 0x0c/0x8001/0x0d-0x12/0x14
  (sous-résultats internes de handleMatch, §12d, non émis en `mov w1,#imm` fil — répertoire kext, non observés isolément
  en trace) → **inconnus côté fil** : s'ils apparaissaient, STOP.

---

## 6. Conclusion : J6 est BLOQUÉ (deux murs), et l'expérience la moins chère qui tranche

**Le protocole est établi** (séquence match VU, verdict vérifié ; séquence enroll = kext). Mais J6 (enrôlement réel
puis match) bute sur **trois choses imbriquées, non résolubles en lecture seule :**
1. **D2 / EP 0x12** : notre état natif n'a **ni keybag ni gabarit**. Le premier match suppose un gabarit (enroll) ;
   l'enroll et/ou le 0x09 peuvent exiger le keybag (SEP-refus = non tranché). EP 0x12 jamais ouvert chez nous.
2. **enroll_indata_v2_t (0x03, 68 o)** : contenu inconnu → pas d'enroll correct possible sans le reverser/capturer.
3. **0x06 (0xa7 o, nonce par lock)** : origine inconnue, liée au keybag → pas de capture/match fidèle possible.

**On ne code donc PAS un enroll/match « établi »** : il n'y a pas de payload établi pour 0x03 ni 0x06. Coder des
niveaux « enroll/match » qui envoient des octets devinés violerait « protocole avant de répondre » et « fail-closed ».

**Expérience la moins chère qui tranche D2 (proposée, à valider avec l'orchestrateur/sceptique) — SANS doigt
d'abord :**
- **E-enroll-start** : après J5c pass2 (sans éteindre le capteur), charger le catacomb vide / absent, puis **émettre
  un seul `0x03` avec un `enroll_indata_v2_t` minimal** (68 o : u32[0]=1 = flag mode, reste 0 — best-effort documenté)
  et **observer la réponse exacte du SEP** (ack ? code d'erreur `0xe00000..` ? refus keybag ? silence ?). **Aucune
  pose de doigt**, aucun gabarit créé, une seule écriture, fail-closed immédiat. Ça tranche : (a) le SEP accepte-t-il
  d'entrer en mode enroll sans keybag ? (b) quel refus exact s'il le faut ? → dit si EP 0x12 est **indispensable**
  avant d'investir dans le reverse de biometrickitd. Classe neuve → **go d'Albert** (1er run).
- Si E-enroll-start passe (SEP en mode enroll) : alors seulement une **session humaine** de poses a du sens (§4).

Tant que E-enroll-start n'a pas tranché, **pas de session humaine J6** : elle coûterait un run pour buter sur un mur
qu'un probe sans doigt révèle à moindre coût.

---

## 7. Ce qui est préparé côté code (honnête sur le périmètre)

- `sep-proto::bio` : la **carte** des deux séquences (opcodes, longueurs connues, payloads marqués INCONNU) et le
  **parseur de verdict 0x09** (déjà vérifié), avec tests de rejeu sur C20/C11 (séquence de match reconnue octet-près,
  verdict lu). **Aucune fabrication de 0x03/0x06.**
- `sbiod --upto match` : **lecture seule / rejeu** — rejoue la séquence match d'une capture et vérifie
  reconnaissance + verdict (test), **ne pilote pas** le SEP (pas de payload 0x06/0x65 à fabriquer sans doigt + D6).
- Noyau : **pas** de niveau `allow_sbio_bio` actif. Un paramètre `allow_sbio_bio` est ajouté **en butoir refusé**
  (comme `allow_sks`) : toute valeur ≠ 0 fait échouer le probe, avec le motif (D2 + payloads inconnus). Le seul
  envoi neuf envisagé (E-enroll-start, 0x03) est laissé en `pending/` **non exécutable** tant qu'Albert/orchestrateur
  n'a pas validé l'expérience.
</content>
</invoke>

### 7.1 Mise à jour 2026-11-22 : E-ENROLL-START codée (J6a), variante « avec doigt »
Décision d'Albert : tenter quand même. `allow_sbio_bio=1` (exige `allow_sbio_params=3`) admet UN `0x03` à charge fixe
**68 octets à zéro** (`sbio_gate::ENROLL_INDATA_MIN` : longueur VU kext ; u32 +0x00 lu par le kext, bit 0 = drapeau de
sens inconnu → laissé à 0 ; +0x04..+0x43 jamais lus par le kext, aucune valeur par défaut connue → 0 ; acceptation par
le SEP = hypothèse), puis écoute 90 s sans aucune réponse (aucune requête SEP→AP n'a de réponse établie ici ; 0x65 est
une commande AP). Script : `pending/j6a_enroll_start.sh`. Jamais lancé.
