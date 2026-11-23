# Valeurs scalaires de la voie keybag : côté userland (qui appelle le userclient EP 0x12, et avec quoi)

2026-11-23 — agent reverseur (session **PC**, Opus 4.8, ipsw, hors-ligne). **Cible** : fixer, sans deviner, la
**source** des valeurs scalaires de la voie keybag (gabarits fil déjà connus : `sks_unlock_token.md`,
`keybag_native_path.md`) en désassemblant le **code userland** qui pilote le userclient `AppleSEPKeyStore`.
**Portée protocole/format uniquement. Aucune clé, aucun secret, aucun passcode, aucune valeur cryptographique
extraits. Aucun code Apple copié.** Désassemblage seul, rien lancé, rien `vérifié`.

**Source binaire** : cache dyld 27.2.1 déjà extrait `macos/ipsw27/out/26B131__MacBookPro18,2/dyld_shared_cache_arm64e`
(+ sous-caches), outil `ipsw` v3.1.750. **`source: userland`** (framework `AppleKeyStore` img #69, `MobileKeyBag`
img #231, `LocalAuthentication` #268). Adresses = VA dyld (`0x187…` AppleKeyStore, `0x197…` MobileKeyBag).
**Convention** : **VU** = lu au désassemblage ; **DÉDUIT** = interprété d'après noms/flot/structure ; **INCONNU** =
non tranché par les binaires présents. Réf. : `sks_unlock_token.md` (codecs kext, TAG 0x18/0x1c), `acm_token.md` §2.1
(dispatch userclient, sélecteur 0x26), `keybag_native_path.md` §1 (identity_load, uuid 16 o).

## 0. Résumé (≤ 15 lignes)

- **Architecture (VU, décisive)** : deux étages. (a) Les wrappers C `aks_*` (dans `AppleKeyStore.framework`) appellent
  **directement** `IOConnectCallMethod` sur le userclient AppleSEPKeyStore → ils fixent les **sélecteurs** et le
  **packing** des scalaires. (b) La **création d'identité d'appareil** (`AKSIdentityCreateKeybag[WithHash]`) n'est
  **PAS** un appel kext direct : c'est un **stub XPC vers le démon `applekeystored`** (VU : elle n'appelle que
  `_applekeystored_xpc_client_identity_create_keybag`). → l'UUID/identité est **détenu par le démon**, pas choisi par
  l'appelant.
- **Sélecteurs userclient EP 0x12 (VU)** : `create_bag`=**0x2** (7 scal), `load_bag`=**0x6** (blob en struct),
  `unlock_device`=**0x9** (4 scal), `auth_token_create`=**0x26** (4 scal + secret en struct), `backup_copy_bag_uuid`=
  **0x70** (lit 16 o), `invalidate_sync_bags`=0x42. Ce sont les index de dispatch (réception @0xcd0844), **distincts**
  des TAG fil SEP (0x03/0x0d/0x18/0x1c).
- **auth_token_create (0x1c)** — VU : `aks_auth_token_create` sél. 0x26, scalaires = {arg0=**handle de keybag**, arg3,
  arg1, arg2}, secret {ptr,len} en struct-input. Confirme `acm_token.md` §2.1. **u64 session (+0x58 kext)** = calculé
  **côté noyau** (`[sp+0xc8]` du dispatch), **pas fourni par l'AP** → valeur INCONNU mais **non choisie par l'hôte**.
  **sélecteur (+0x64 kext)** = arg3 de l'appelant (coreauthd) — valeur INCONNU (dans coreauthd).
- **device_state_transition (0x18)** — VU : `aks_unlock_device` sél. 0x9, 4 scalaires {sext(arg0), arg1, sext(arg2), 0}.
  Le **code d'état cible (+0x60 kext, ~ −501)** entre comme un **argument de l'appelant** (`MobileKeyBag`/coreauthd),
  pas une constante du wrapper → valeur INCONNU, source = étage supérieur.
- **UUID 16 o (load/identity)** — VU : `aks_load_bag` (sél. 0x6) prend un **blob keybag opaque** (l'UUID est DEDANS) ;
  `aks_backup_copy_current_bag_uuid` (sél. 0x70) **relit** un UUID de 16 o **déjà présent**. → les UUID de bag sont des
  **valeurs persistantes relues**, pas générées à la volée côté cache. La génération/source exacte = **applekeystored**.
- **Q4 (verdict franc, DÉDUIT fort)** : le chemin **ne forge pas** un keybag d'appareil ex nihilo pour un appelant
  quelconque. Il (re)fabrique **l'identité DE CET appareil** (clé interne SEP), médiatisée par un démon privilégié qui
  tient un **état scellé** (génération, memento, lock-states, variante `…WithHash`). Byte-exact (uuid généré vs lu sur
  disque/preboot) = **dans `applekeystored`**, **hors du cache** (exécutable disque ; apfs-fuse absent) → **je m'arrête
  là** (consigne : ne pas contourner).

---

## 1. Étage bas — wrappers `aks_*` → `IOConnectCallMethod` (VU)

Tous passent par `_get_aks_client_connection` puis `IOConnectCallMethod(conn, SEL, scalars, nScal, struct…, out…)`.
Le **sélecteur** (`w1`) est l'index de dispatch du userclient (réception kext @0xcd0844), **≠ TAG fil SEP**.

| wrapper (VU) | VA | sélecteur `w1` | scalaires (`w3`) | struct-in | rôle → op kext (DÉDUIT par nom) |
|---|---|---|---|---|---|
| `aks_create_bag`→`__create_bag` | 0x187dc6e74 | **0x2** | **7** | — | create_keybag (TAG fil 0x01) ; `aks_create_bag` force `w6=0xffffffff` |
| `aks_load_bag` | 0x187dc7150 | **0x6** | 0 | `x4`=blob ptr, `x5`=len | load_keybag (TAG fil 0x03) ; **UUID dans le blob** ; handle écrit en sortie |
| `aks_unlock_device` | 0x187d74b58 | **0x9** | **4** | — | device_state_transition / unlock (TAG fil 0x18) |
| `aks_auth_token_create` | 0x187dc8c70 | **0x26** | **4** | secret `{ptr,len}` @[sp] | authentication_token_create (TAG fil 0x1c) |
| `aks_backup_copy_current_bag_uuid` | 0x187dc7de0 | **0x70** | (pack_data) | — | relit un **UUID 16 o** (`w8=0x10`) déjà présent |
| `aks_invalidate_sync_bags` | 0x187d739b4 | 0x42 | 0 | — | — |

**Note de correspondance** : ces sélecteurs sont **VU** ; la mise en relation sélecteur → méthode C++ kext → TAG fil
est **DÉDUITE par le nom** (`aks_unlock_device`↔`unlock_the_device`, etc.). La preuve octet-près demanderait la table
`sExternalMethods` du userclient (@0xcd0844, kernelcache) — **non faite cette session** (prochaine étape propre).

### 1.1 `aks_auth_token_create` (TAG fil 0x1c) — packing VU (@0x187dc8cc4-0x187dc8ce8)
`sxtw x8,w25(arg0); mov w9,w24(arg3); stp x8,x9,[fp,-0x68]` ; `sxtw x8,w23(arg2); stp x22(arg1),x8,[fp,-0x58]` ;
`stp x20(arg4),x21(arg5),[sp]` ; `w1=0x26 ; w3=4 ; x2=fp-0x68`. → **4 scalaires** = {arg0, arg3, arg1, arg2} +
**secret {arg4,arg5} en struct-input**. `arg0` est l'`input[0]` que le kext passe à `effective_bag_handle_actual(0x26,…)`
→ **handle de keybag** (`acm_token.md` §2.1). Donc côté kext : `+0x60`(handle)=arg0, `+0x64`(sélecteur)=arg3,
`+0x58`(u64)=arg1 **OU** session noyau — le `acm_token.md` §2.1 a VU que l'arg « u64 session » du C++ vient de
`[sp+0xc8]` **du dispatch noyau**, donc **non fourni par l'AP**. **INCONNU** : valeur de arg3 (coreauthd) et du u64 session (noyau).

### 1.2 `aks_unlock_device` (TAG fil 0x18) — packing VU (@0x187d74b78-0x187d74b9c)
`sxtw x8,w0(arg0); stp x8,x1(arg1),[sp+0x18]` ; `sxtw x8,w2(arg2); stp x8,xzr,[sp+0x28]` ; `w1=0x9 ; w3=4 ; x2=sp+0x18`.
→ **4 scalaires** = {sext(arg0), arg1, sext(arg2), 0}. Le **code d'état cible** (kext `+0x60`, ~ −501, `sks_protocol.md`
§1.3) et l'u64 (`+0x68`) sont parmi ces scalaires mais **leurs valeurs viennent de l'appelant** (`MobileKeyBag`/
coreauthd), pas du wrapper. **INCONNU** : les valeurs numériques (étage supérieur) ; le passcode voyage à part, en
struct-input (secret), fourni à l'exécution.

### 1.3 `aks_load_bag` (TAG fil 0x03) — VU (@0x187dc7194-0x187dc71c0)
`w1=0x6 ; x4=arg0`(blob keybag ptr) `; x5=sext(arg1)`(len) `; x6=fp-0x40`(sortie) `; x7=sp+0x1c`. Handle écrit dans
`[arg2]`. → le **blob keybag est opaque** (l'UUID/type sont **à l'intérieur**, pas des scalaires séparés ici). Donc,
côté fil, le « uuid 16 o » de `keybag_native_path.md` §1 appartient au **contenu du bag** fourni par le démon, pas à un
champ scalaire du userclient. **INCONNU** (hors cache) : la **fabrication** de ce blob (uuid/type) = `applekeystored`.

## 2. Étage haut — identité d'appareil = démon `applekeystored` (VU)

`_AKSIdentityCreateKeybag` (@0x187d78160) et `_AKSIdentityCreateKeybagWithHash` (@0x187d781a0) sont des **stubs minces**
qui n'appellent que `_applekeystored_xpc_client_identity_create_keybag[_with_hash]` puis `_create_error` — **aucun appel
kext direct** (VU). → la **logique d'identité** (choix de l'uuid, type, génération, scellement) est **dans le démon
`applekeystored`**, joignable seulement par XPC. Le framework ne porte que le modèle Swift `AKSIdentity` (type `State`
avec `generation`, `LockState` {locked/unlocked/gracePeriod/assertDelay/…}, `getMemento`, `getIdentityState`,
`getConfiguration`) — un état **persistant et typé**, cohérent avec une identité **établie/scellée**, pas forgée à la demande.

`applekeystored` **n'est pas dans le cache dyld** (c'est un exécutable `/usr/libexec` sur le système de fichiers racine).
Idem `coreauthd`/`LocalAuthentication` pour le secret du jeton (`acm_token.md` §2.2). Les extraire exigerait de **monter
le DMG racine de l'IPSW** (apfs-fuse) — **outil absent ici**, et le DMG 27.x est généralement **AEA-chiffré**. Conforme à
la consigne (« si une étape coince, arrête-toi, ne contourne pas »), **je n'ai pas tenté** d'installer apfs-fuse ni de
récupérer une clé AEA.

## 3. Réponses par cible

| # | valeur demandée | statut | source (VU/DÉDUIT/INCONNU) |
|---|---|---|---|
| 1 | load_keybag : **UUID 16 o** | **dans le blob opaque** (pas un scalaire userclient) ; relu persistant (sél. 0x70) | VU (packing) ; **valeur/source INCONNU** = applekeystored |
| 1 | load_keybag : **handle y** (+0x58) | **sortie** du userclient (écrit par le kext), pas une entrée AP | VU (`aks_load_bag` écrit `[arg2]`) |
| 1 | load_keybag : **type** (+0x64, ≤ −10) | fourni par l'appelant du bag ; `aks_create_bag` pose des défauts (`w6=-1`) | VU packing ; **valeur INCONNU** (démon) |
| 2 | make_system_keybag : type/flag | même étage : stub XPC `AKSIdentityCreateKeybag` → démon | DÉDUIT ; **INCONNU** (démon) |
| 3 | device_state_transition **code** (+0x60) | entre via `aks_unlock_device` scal[2] (arg2) | VU chemin ; **valeur INCONNU** (MKB/coreauthd) |
| 3 | device_state_transition **u64** (+0x68) | scalaire userclient | VU champ ; **valeur INCONNU** |
| 3 | auth_token_create **u64 session** (+0x58) | **calculé côté noyau** (`[sp+0xc8]`), non choisi par l'AP | VU (acm §2.1) ; **non AP-fournissable** |
| 3 | auth_token_create **sélecteur** (+0x64) | = arg3 de `aks_auth_token_create` (coreauthd) | VU chemin ; **valeur INCONNU** (coreauthd) |

## 4. Q4 — crée-t-on un keybag d'appareil NEUF, ou charge-t-on une identité PRÉEXISTANTE ? (verdict franc)

**DÉDUIT fort : ni « pur ex nihilo libre », ni « identité enrôlée chez Apple obligatoire » — c'est l'identité
PROPRE DE CET APPAREIL, (re)fabriquée par le SEP, médiatisée par un démon qui tient un état scellé.** Appuis :

1. **Médiation par démon privilégié** (VU) : la création passe par `applekeystored` (XPC), pas par un `IOConnectCallMethod`
   que n'importe quel process poserait. Un hôte non-macOS devrait **reproduire le rôle du démon**, pas juste appeler le kext.
2. **Identité stateful/scellée** (VU, Swift `AKSIdentity`) : `generation` (compteur), `Memento`
   (`getMemento`/`…EffaceMementoBlob`), `LockState`, et surtout la variante **`…WithHash`** (création **épinglée à un
   hash**) → une identité **établie et versionnée sous scellé**, pas mintée à volonté.
3. **Clé d'appareil interne SEP** (recoupe `keybag_native_path.md` §1 : `identity_load` → `make_system_keybag` **blob
   VIDE** = le SEP fabrique le keybag **avec son propre matériel de clé**). → **bonne nouvelle Linux** : fabriquer le
   keybag d'appareil **n'exige aucun secret que seul macOS détiendrait** ; **mauvaise** : le keybag obtenu est **celui de
   ce SEP** (lié à la clé d'appareil), pas une ardoise vierge arbitraire.
4. **UUID persistant relu** (VU, sél. 0x70, 16 o) : les UUID de bag sont des **valeurs du système relues**, cohérent avec
   une **identité qui préexiste** (posée une fois), pas (ré)inventée à chaque appel.

**Conséquence pour Linux** : la voie identité reste la plus prometteuse (pas de mur cryptographique macOS pour *fabriquer*
le bag), MAIS il faut **rejouer la séquence exacte de `applekeystored`** (quel uuid, quel type, quelle génération, quel
scellement) — **inconnue tant que le démon n'est pas désassemblé**. **À trancher** en extrayant `applekeystored`
(+`coreauthd` pour le secret) du système de fichiers racine (montage DMG/apfs-fuse, outil à remonter) — **étape suivante
propre, hors de ce que le cache dyld permet**. Rien ici n'est matériel ; le passcode reste fourni à l'exécution, jamais extrait.
