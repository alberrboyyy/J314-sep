# SKS — chaîne « keystore → keybag déverrouillé » pour un OS sans keybag macOS (Linux natif)

Rédigé le 2026-11-23 (agent reverseur, ALARM, Opus 4.8, capstone, hors-ligne). **Cible** : les transactions de
bring-up qui, sur macOS chaîné, mènent au déverrouillage — `unwrap_media_key` (0x32), `fv_get_blob_state` (0x48),
`fv_unwrap_vek` (0x41), `device_state_transition` (0x18) — plus la création d'un keybag neuf
(`create_keybag` / `make_system_keybag`). **But** : savoir si un OS Linux SANS keybag/volume macOS peut atteindre un
keybag déverrouillé. **Aucun octet de clé, de secret, de passcode ou de dérivation extrait** (protocole uniquement).

**Source binaire** : kernelcache `macos/kc/26B131__MacBookPro18,4/kernelcache.release.*` (27.2.1 = version installée),
bundle `com.apple.driver.AppleSEPKeyStore`. **`source: kext` (27.2.1)**. Convention : **VU** = lu au désassemblage
(adresse/symbole/immédiat) ; **DÉDUIT** = interprété d'après noms/flot ; **INCONNU** = non tranché par ce binaire.
Rien de `vérifié` (aucun matériel). Tous les symboles C++ `AppleKeyStore::*` sont présents en 27.2.1 (contrairement à
13.5), ce qui a permis d'aller plus loin que `sks_protocol.md` §3.

---

## 0. Correction de prémisse — 0x32 / 0x48 / 0x41 / 0x18 ne sont PAS des `perform_operation` DER — VU

Ces quatre TAG **ne portent AUCUN champ `o` ni dictionnaire DER `aks_params`** (le SET 0x31 / paires SEQUENCE de
`sks_protocol.md` §2 est réservé à `perform_operation`, TAG **0x22**, seul). Chacun est une **opération IPC dédiée**
avec son propre codeur `_code_ipc_<op>` qui sérialise une **structure C plate** via les **mêmes primitives** que
`get_capabilities`/`set_env` (en-tête IPC 0x54 o puis champs `__word`/`__lword`/`__blob`). VU :

| TAG fil (VU trace) | op IPC (symbole VU) | codeur `_code_ipc_*` | sélecteur passé au submit (VU `mov w1,#…`) | builder noyau `__ipc_*` |
|---|---|---|---|---|
| 0x32 | `unwrap_media_key` | 0xce5640 | `w1=#0x32` @0xcfc6d4 | `__ipc_unwrap_media_key` 0xcfc5ec |
| 0x48 | `fv_get_blob_state` | 0xce87b0 | `w1=#0x48` @0xcfde24/0xcfde44 | `__ipc_fv_get_blob_state` 0xcfdda4 |
| 0x41 | `fv_unwrap_vek` | 0xce7848 | `w1=#0x41` @0xcfd6a0 | `__ipc_fv_unwrap_vek[_v1]` 0xcfd478/0xcfd5cc |
| 0x18 | `device_state_transition` | 0xce1da0 | `w1=#0x18` @0xcfb108 | `__ipc_device_state_transition` 0xcfb078 |

Le sélecteur `w1` est passé à l'appel indirect authentifié `blraa x<obj>, x17` (x17=`#0x392e`), c.-à-d. la vmethod de
soumission de l'instance endpoint. **Le sélecteur numérique = le TAG fil** (VU, recoupe la trace c12). → Pour ces
opérations il n'y a **ni `o`, ni paires DER, ni `rk`, ni `acmh`** : les arguments sont des **scalaires + blobs OOL
positionnels** dans la structure. (Corrige la question posée en termes de « opération `o` et paires DER ».)

---

## 1. `unwrap_media_key` (TAG 0x32) — VU / DÉDUIT

- **Builder** `__ipc_unwrap_media_key` (0xcfc5ec, VU) : construit une structure sur la pile et y copie, depuis les
  arguments, **deux couples {blob, longueur}** (une **clé média enveloppée** en entrée + un contexte) et un petit mot ;
  puis `blraa` sélecteur **0x32**. En retour il recopie des champs de sortie (la clé brute résultante) vers les
  tampons de l'appelant. → `unwrap_media_key` **DÉSENVELOPPE un blob fourni** : il **porte des données** (une clé média
  *wrapped*), il **n'est pas** une requête d'état vide. (VU structure ; DÉDUIT = « unwrap d'un blob disque ».)
- **Qui l'appelle** (VU, symboles) : `AppleKeyStore::unwrap_media_key` (0xcf6640) et la famille
  `fs_unwrap_media_key_from_uid` (0xcf1354) / `fs_unwrap_media_key_from_class` (0xcf1414) /
  `fs_migrate_media_key_to_class` / `fv_unwrap_media_key` (0xcf2c0c). Ces fonctions reçoivent un `aks_wrapped_key_s`
  (la clé média enveloppée) et rendent un `aks_raw_key_s`. **La source du blob est la couche fichiers/volume**
  (`fs_*`/`fv_*` = FileSystem / FileVault), c.-à-d. **du disque APFS macOS** (cf. §2, callers communs). VU noms,
  DÉDUIT source.
- **`rk`/`acmh` ?** Non (ce n'est pas un `perform_operation`). Il porte un **blob de clé média enveloppée**, pas un
  `rk` DER. Pour l'*opération d'identité* au tout début de boot, cf. `sks_protocol.md` §2.3 (famille 0x22).
- **Reproductible à froid depuis Linux ?** **NON tel quel** : l'entrée est une clé média **scellée par le SEP** pour
  ce volume (blob disque macOS). Un OS Linux n'en a pas. Le **corps (DER req 0x30 = 48 o au bring-up)** n'est pas
  « décodable en DER » : ce n'est pas du DER, c'est en-tête IPC + struct ; les 48 o utiles portent le blob wrapped,
  dont le **contenu est INCONNU** (OOL 0x12 jamais capturé) et serait de toute façon un secret (non extrait).

## 2. `fv_get_blob_state` (TAG 0x48) — VU / DÉDUIT

- **Ce qu'il fait** (VU, `AppleKeyStore::fv_get_blob_state` 0xcf569c → `fv_get_blob_state_der` 0xcf5ea8 → codeur
  0xce87b0) : met à zéro une structure `aks_fv_blob_state_s`, puis **interroge le SEP** et **remplit un état** —
  champs sérialisés aux offsets 0x50 (mot d'état, testé `cbz`), 0x58, 0x60/0x68, 0x70, puis 0x80/0x88 (couples
  `__blob`). La réponse fil fait **0x110 o** (trace c12). C'est une **requête de LECTURE d'état** du blob FileVault
  détenu par le SEP (présence/version/paramètres d'un VEK/keybag de volume). (VU disposition ; DÉDUIT sémantique.)
- **D'où vient le blob FileVault** (VU, callers hors bundle) : la famille `fv_*`/`pf_fv_*` est une **KPI** appelée par
  la couche stockage :
  - `AppleAPFSContainer::volumeCacheKey` (0xb8816a0), `AppleAPFSContainer::volumeUnlockRecord` (0xb8930c4),
  - `CoreStorageFamily::unlockVEKs` (0xa361808),
  - `get_vek_from_placeholder_data` (0xb8848fc), `apfs_keybag_unlock_with_placeholder_data`, `_CreateVEK`,
    `_media_keybag_operation` (0xb866e3c).
  → Le blob est l'**enregistrement de déverrouillage / le VEK enveloppé du volume APFS macOS**, lu **du disque** par
  APFS/CoreStorage et passé au SEP. **`source: kext`**, VU par les signatures (`aks_fv_param_s`, `aks_fv_data_s`,
  `crypto_state`).
- **OS sans ce blob (Linux)** : il n'y a **pas de volume APFS FileVault**, donc rien à passer. En protocole,
  `fv_get_blob_state` zéroie sa sortie et branche « rien » quand les tampons/handles sont nuls (VU : plusieurs `cbz`
  en entrée de `fv_get_blob_state_der` sautent au remplissage minimal). → l'« absence » est **gérée** au sens où la
  requête rend un **état vide/non-présent** (DÉDUIT ; la valeur exacte « absent » dans l'OOL B est INCONNUE, jamais
  capturée). Mais surtout : **pour un OS Linux cette requête n'a pas d'objet** — elle sonde l'état d'un volume macOS.

## 3. Création d'un keybag neuf — VU / DÉDUIT / INCONNU

Deux chemins existent (symboles VU) ; **aucun** n'apparaît dans les 13 transactions déterministes du bring-up (§ trace).

### 3.1 `create_keybag` (op **0x01**, « create with data ») — VU
- `AppleKeyStore::create_keybag` (0xcc6904) → `__ipc_create_keybag_v4` (0xcf9a34) → submit sélecteur **`w1=1`** (VU).
- **Entrées** (VU struct) : un **blob de données de keybag** {ptr, len} (le contenu du keybag), plus des scalaires
  (type/`bag_type`, options, version, un couple d'identifiants 16 o = probable **uuid**), un champ de sortie = le
  **handle** attribué. → c'est **« créer À PARTIR de données »** : le keybag n'est pas fabriqué ex nihilo, il est
  **importé depuis un blob** fourni par l'appelant.
- **Qui l'appelle** (VU, `callers`) : **uniquement** le userclient `kAppleKeyStoreKeyBagCreateWithData` (0xcd0844),
  gardé par l'entitlement **`com.apple.keystore.keybag.create`** (string VU) et un sélecteur CoreAnalytics
  `com.apple.applekeystore.selector.keybag_create`. → **piloté par l'userland privilégié**, pas par le boot du kext.

### 3.2 `make_system_keybag` (op **0x0d**) — VU
- `__ipc_make_system_keybag_v1` (0xcdbce4) → submit sélecteur **`w1=0xd`** (VU). Construit une struct 0x80 o
  (une constante 8 o de `__const` + scalaires x22..x26 = paramètres de session/type), **pas de blob secret visible**.
- **Qui l'appelle** (VU, `callers`) : `AppleKeyStore::identity_load` (0xcf79a8) et
  `AppleKeyStore::set_device_keybag` (0xcc7c4c). → c'est l'étape **IDENTITÉ / keybag d'appareil** (famille
  `identity_create`/`identity_load`/`identity_verify`/`identity_migrate`, strings VU), pas FileVault. Le **« system
  keybag »** est le keybag d'appareil que le SEP fabrique lui-même (clé interne), par opposition au keybag utilisateur.
- **Entrées** : des scalaires (type, génération, flags) — **aucun passcode/seed en clair visible** côté AP (le
  matériel de clé est interne au SEP). (VU absence de blob secret ; DÉDUIT = keybag fabriqué par le SEP.)

### 3.3 Scellement / persistance — INCONNU (partiel)
- Le kext expose `escrow_stash_*`, `com.apple.keystore.stash.persist`, et `aks_fv_stash_commit` (0xcb72d28, symbole
  VU) : il existe un **mécanisme de stash/escrow** — DÉDUIT : un keybag/identité peut être **persisté** (vraisem­blable­ment
  via le xART 0x13 / gigalocker, cohérent avec la route native qui ACK les SAVE xART). **Le lien exact create/`make_system`
  → SAVE xART n'est PAS tracé dans ce kext** (la persistance est côté endpoint/SEPManager, hors bundle). → **INCONNU** si
  `create_keybag`/`make_system_keybag` déclenche un SAVE, et si le résultat survit à un reboot sans re-scellement.
- **Rejouable depuis Linux ?** `create_keybag` exige un **blob de keybag existant** (import) + l'entitlement : un OS
  Linux devrait **fabriquer un blob de keybag valide** (format INCONNU, jamais capturé) — mur. `make_system_keybag`
  fabrique un keybag interne mais via le chemin **identité d'appareil** (entitlements, état SEP) : faisabilité et effet
  sur le gating bio **INCONNU**.

## 4. Déverrouillage par mot de passe — `fv_unwrap_vek` (0x41) puis `device_state_transition` (0x18) — VU / DÉDUIT / INCONNU

- **0x41 = `fv_unwrap_vek`** (VU) : `pf_fv_unwrap_vek` (0xcc5768) → `fv_unwrap_vek_with_acm` (0xcf5ba4) →
  `__ipc_fv_unwrap_vek_v1` (0xcfd5cc), submit sélecteur **0x41**. **Signature VU** :
  `fv_unwrap_vek_with_acm(unsigned long long handle, aks_fv_param_s*, unsigned, aks_fv_data_s* ×3, aks_fv_key_s*, …)`.
  - Il **désenveloppe le VEK** (Volume Encryption Key) d'un volume FileVault à partir de : le **handle de keybag**
    (1er scalaire `y`, = `bh`), plusieurs **blobs OOL** (le **VEK enveloppé** + un **KEK** + l'enregistrement de
    déverrouillage, tous `{ptr,len}` lus du disque APFS, mêmes callers qu'au §2) et un **contexte d'auth / credential**.
  - **Le passcode** : le kext tente d'en **extraire** une valeur (string VU `"Failed to extract passcode f…"` dans
    `fv_unwrap_vek_with_acm`, helper 0xcf4fa4) depuis un **blob de credential / ACM** fourni (un des `aks_fv_data_s`).
    → Le passcode **n'est pas un champ texte à part** : il arrive **dans un blob OOL** (credential ACM ou matériel
    pré-dérivé). **Clair vs dérivé côté AP : INCONNU** au niveau octet (OOL 0x12 jamais capturé) — **non extrait**
    (règle « aucun secret »). Indices symboles : `_aks_setPassphrase`, `ACMCredentialDataPassphraseEntered` (cf.
    `sks_protocol.md` §4/§5). DÉDUIT : la logique de dérivation/vérification est **dans le SEP** ; l'AP transporte le
    secret (ou un pré-dérivé) sans détenir la clé finale.
  - **Ce que rend le SEP** : un `aks_fv_key_s` (le **VEK déchiffré**, secret — non extrait) + code d'état. Au bring-up
    c12, `0x41` req 0x240 → resp 0xa0 (VU trace). Ce n'est PAS l'état `sls`/`ss` directement : c'est la clé de volume.
- **0x18 = `device_state_transition`** (VU) : `AppleKeyStore::device_state_transition` (0xcc3b44) →
  `__ipc_device_state_transition` (0xcfb078), submit sélecteur **0x18**. Prend un **handle** + des scalaires d'état,
  rend deux mots d'état (`stp x9,x8`). → **DÉDUIT** : fait **transiter l'état de verrouillage** du keybag/appareil
  (c'est l'étape qui, combinée au VEK désenveloppé, **bascule le keybag en déverrouillé** et émet la notif `TAG 0x00`
  « unlock, DATA=handle »). L'état déverrouillé se relit ensuite dans `ss`/**`sls`** (clé du gating bio, `sks_protocol.md`
  §2). Octets exacts de 0x18 : INCONNU (jamais capturé).
- **Quel `bh`** : le **handle de keybag** passé en 1er scalaire (`y`), pas un champ DER. Au boot macOS, c'est le
  keybag de volume (-6) puis l'utilisateur (-501) (VU notifs, `messages.md`). DÉDUIT.

---

## 5. VERDICT — un keybag déverrouillé est-il atteignable depuis Linux natif ?

**INCERTAIN, et la voie 0x32/0x48/0x41/0x18 telle quelle est un cul-de-sac pour Linux.** Détail :

1. **La chaîne 0x32 → 0x48 → 0x41 → 0x18 est le déverrouillage d'un VOLUME FileVault APFS macOS, pas « le keybag »
   abstrait.** VU : tous ses blobs (clé média enveloppée, enregistrement de déverrouillage, VEK/KEK enveloppés) sont
   lus **du disque APFS macOS** par `AppleAPFSContainer`/`CoreStorageFamily`/`apfs_keybag_*` et passés au SEP. **Un OS
   Linux n'a aucun de ces blobs** → il **ne peut pas rejouer** 0x32/0x41, et 0x48 **n'a pas d'objet** (il sonde l'état
   d'un volume qui n'existe pas). **MUR dur** : blobs scellés propres au volume macOS + passcode de l'utilisateur macOS,
   tous deux absents et non fabricables hors-ligne (et secrets — non extraits).

2. **Mais ces 4 opcodes sont très probablement CONTOURNABLES pour Touch ID.** Ils servent à monter le **volume de
   données macOS**, pas à ouvrir la session biométrique. Ce qui gate sbio, c'est l'**état `sls`/verrouillage d'un
   keybag** connu du SEP — pas le VEK du volume. En **seal frais** (route native), « rien à déverrouiller → sbio répond
   direct » (`sks_sequence_c12.md`) : la pile FileVault n'y est jamais jouée. Donc **sauter 0x32/0x48/0x41/0x18**
   est cohérent avec ce qui est déjà observé. **À instruire** : vérifier que le SEP accepte le reste du bring-up sans
   eux (classe neuve → go d'Albert) — c'est la piste la moins chère (déjà notée `sks_protocol.md` §2.3.6).

3. **La vraie question = « poser un keybag déverrouillé que le SEP relie au gating bio ».** Deux leviers VU :
   - `create_keybag` (op 0x01) : **importe un blob de keybag** → nécessite de **fabriquer un blob valide** (format
     INCONNU, jamais capturé) + entitlement `keybag.create`. **Mur : format du blob + entitlement.**
   - `make_system_keybag` (op 0x0d) via le chemin **identité d'appareil** : le SEP fabrique le keybag lui-même (pas de
     secret AP) — **le plus prometteur** (pas de blob à inventer), mais **effet sur le gating bio INCONNU** et
     **persistance/scellement xART INCONNU** (hors bundle).

4. **Le mot de passe** (0x41) n'est **pas** un champ clair séparé : il voyage **dans un blob OOL de credential/ACM** ;
   clair vs dérivé côté AP = **INCONNU** (non extrait). De toute façon, sur Linux il n'y a **pas** de credential ACM
   macOS à présenter.

**Conclusion opérationnelle.** Atteindre « keybag déverrouillé » en **copiant la séquence macOS** (0x32/0x48/0x41/0x18) :
**NON** (dépend de blobs/passcode du volume macOS, absents et secrets). Atteindre un **état keystore qui ungate sbio**
sur Linux : **INCERTAIN, mais pas via FileVault** — la piste réaliste est (a) **ne pas jouer** la pile FileVault et
tester si le reste du bring-up suffit, puis (b) **`make_system_keybag`/identité d'appareil** pour poser un keybag que
le SEP déverrouille. Les deux murs restants sont **non tranchables par ce binaire** : (i) le **gating bio est une
politique interne au SEP** (le kext ne lit jamais, à la réception, un verdict du SEP liant un keybag précis au bio) ;
(ii) la **persistance xART** d'un keybag créé est côté endpoint/SEPManager, hors AppleSEPKeyStore. → À trancher sur
**matériel** (classe neuve → go d'Albert), pas au désassemblage.

### Points ouverts (honnêtes)
- Contenu octet des OOL 0x32/0x48/0x41/0x18 : **jamais capturé** (seules les tailles/sélecteurs sont VU).
- Valeur « absent » rendue par `fv_get_blob_state` : INCONNU.
- Format du blob d'entrée de `create_keybag` : INCONNU.
- `make_system_keybag` déclenche-t-il un SAVE xART ? survit-il à un reboot ? INCONNU (hors bundle).
- Le SEP ungate-t-il sbio sur un keybag créé par Linux, ou exige-t-il le keybag d'identité d'appareil d'origine ? INCONNU.
- 0x32/0x48/0x41/0x18 réellement contournables au bring-up (le SEP accepte-t-il la suite sans eux) ? À tester (go d'Albert).
