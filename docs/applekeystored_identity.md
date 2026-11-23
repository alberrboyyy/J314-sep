# `applekeystored` — séquence de création/scellement de l'identité keybag d'appareil (source: userland)

2026-11-23 — agent reverseur (session **PC**, Opus 4.8, ipsw, hors-ligne). **Cible** : la **séquence de
création/scellement** de l'identité keybag (celle que le kext `load_bag` 0x6 / `make_system_keybag` 0x0d relit),
pour trancher **si un OS non-macOS peut la fabriquer**. **Portée protocole/format uniquement. Aucune clé, aucun
secret, aucun passcode, aucun UUID extraits. Aucun code Apple copié.** Désassemblage/chaînes seuls, rien lancé,
rien `vérifié`.

**Source binaire** : `applekeystored` (+`coreauthd`) extraits de l'IPSW public 27.2.1 (`UniversalMac_27.2.1_26B131`)
avec `ipsw extract --remote --ranged` (lecteur APFS natif, **sans apfs-fuse ni montage** : ~1,97 Go de **plages
d'octets** d'un fichier Apple public lues sur le CDN ; l'AEA est géré par ipsw). Mach-O universel → slice **arm64e**.
`applekeystored` = `/usr/libexec/applekeystored`, démon **Swift mince** (symboles strippés : la logique `AKSIdentity`
détaillée est partagée avec `AppleKeyStore.framework`, cf. `sks_userland_values.md` §2). Binaires gardés en
scratchpad (volatils, hors repo). **`source: userland`** (chaînes + surface XPC VU). **Convention** : **VU** = lu
(chaîne/symbole/section) ; **DÉDUIT** = interprété ; **INCONNU** = non tranché par ces binaires.
Réf. : `sks_userland_values.md`, `keybag_native_path.md` §1-§2, `acm_token.md`.

## 0. Résumé (≤ 15 lignes)

- **Persistance = FICHIERS sur disque** (VU) : keybags dans **`/var/keybags`** (et `/private/var/keybags`), plists
  utilisateur sous **`/private/var/db/users/`** + comptes **`dslocal`** (`/private/var/db/dslocal/nodes/Default`),
  blobs KEK/OTI committés **par user-uuid** sur le **volume Preboot** (entitlements `com.apple.rootless.volume.Preboot`).
  Opérations : `identity_commit_oti`, `identity_commit_user_plist`, `identity_update_blobs_on_disk`,
  `identity_load_from_disk_or_migrate_if_necessary`. → **survit au reboot** (sauvé puis rechargé).
- **UUID (VU)** : le démon ne **génère PAS** d'uuid aléatoire — il le **parse** (`CFUUIDCreateFromString`/
  `CFUUIDCreateWithBytes`, aucun `uuid_generate`/`arc4random` sur l'uuid) depuis un **user-uuid** (unlock records APFS
  `APFSVolumeListUUIDsOfUnlockRecords`, config `com.apple.keystore.config.set.user_uuid`, comptes dslocal). → l'UUID
  est un **identifiant de compte/volume**, fourni, **pas une constante d'appareil** ni un aléatoire du keystore.
- **Scellement SEP (VU/DÉDUIT)** : xART présent (`aks_delete_xart_leak`, `stash_*`) ; le SEP scelle, l'hôte garde le
  **blob sur Preboot** et le recharge — modèle « blob re-fourni à chaque boot » (confirme `keybag_native_path.md` §2).
- **Création (VU, décisif)** : chemin de **création à neuf réel** — « *Failed to load legacy keybag, we will just
  create a new one* » (et unlock). Gardé : « *Can't create keybag when OTI, kek or keybag already exists* ».
  **OTI (nouvelle identité) DÉSACTIVÉ sur ce build** (« *Starting applekeystored service (OTI disabled)* ») → chemin
  actif = **keybag legacy** dans `/var/keybags`.
- **Q4 (verdict franc)** : **pas de mur cryptographique pour CRÉER** — aucune donnée que seul macOS détient n'est
  requise pour *fabriquer* le keybag (le SEP a la clé d'appareil ; `make_system_keybag` blob vide), l'**uuid est
  choisi par l'hôte**, la **persistance est un simple fichier**. Le seul verrou restant est une **POLITIQUE SEP**
  (le SEP/enrôlement acceptera-t-il un keybag forgé par Linux, ou exige-t-il l'identité/génération posée par macOS ?)
  — **INCONNU, matériel uniquement**.

---

## 1. Où vit l'identité, et sous quelle forme (VU)

- **Chemins (chaînes VU)** : `/var/keybags`, `/private/var/keybags`, `/keybags` (blobs keybag) ;
  `/private/var/db/users/`, `/private/var/db/dslocal/nodes/Default` (plists/comptes utilisateur) ; blobs KEK/OTI sur
  le **volume Preboot** (entitlements `com.apple.rootless.volume.Preboot`/`iSCPreboot`). Logs VU : « Commiting plist
  for user %s/%{uuid} », « Commiting OTI for user … », « Could not save KEK blob … on disk », « Could not load blobs
  from disk for %{uuid} ».
- **Deux régimes (VU)** : **legacy keybag** (KB) vs **OTI** (identité moderne). « KB requests require AppleKeyStore/oti
  feature flag **OFF** », « Identity requests require … **ON** », et au démarrage « **OTI disabled** ». → sur 27.2.1
  macOS desktop, le keystore tourne en **mode keybag legacy** ; l'OTI est le futur modèle, inactif par défaut.
- **Surface XPC « identity » (VU, noms de méthodes)** : `identity_create_keybag`, `identity_create_keybag_with_hash`,
  `identity_create_v0/v1`, `identity_load`, `identity_load_from_disk_or_migrate_if_necessary`, `identity_copy_keybag_data`,
  `identity_commit_oti`, `identity_commit_user_plist`, `identity_get_blobs_on_disk`, `identity_update_blobs_on_disk`,
  `identity_exists`, `identity_delete[_kek|_oti|_user_plist]`, `identity_set_kek`, `identity_login[_with_acmcred]`,
  `identity_verify`, `identity_recover`, `identity_migrate_kek_to_oti`, `identity_transfer_ownership`,
  `identity_change_passcode_v0/v1`, `+srp/ntlm/persona`. Propriétés : `HasKEK/HasKeybag/HasOTI/HasKerberosSRP/HasNTLM/…`.

## 2. Q1 — l'UUID : généré ou relu ? (VU → DÉDUIT fort)

- **Relu/parsé, pas généré** — VU : le démon construit ses UUID avec `_CFUUIDCreateFromString` /
  `_CFUUIDCreateWithBytes` (à partir d'une valeur **existante**). **Aucun** `uuid_generate`/`CFUUIDCreate`(aléatoire)/
  `arc4random` appliqué à l'uuid (les `crypto_generate*` concernent des **clés**, pas l'uuid). 
- **Source = user-uuid de compte/volume** — VU : `APFSVolumeListUUIDsOfUnlockRecords` (uuid des **unlock records APFS**),
  `com.apple.keystore.config.set.user_uuid`, lecture dslocal (`/var/db/dslocal`). Logs : « *is not a user uuid* »,
  « *Could not get user uuid for this user* », « *Need either an existing or new user uuid* ». → l'uuid **désigne un
  utilisateur/volume** ; un « new user uuid » vient de la **création de compte en amont**, pas du keystore.
- **Conséquence** : l'uuid 16 o que le kext `identity_load`/`make_system_keybag` attend (`keybag_native_path.md` §1)
  **n'est pas un secret ni une constante d'appareil** : c'est un identifiant de compte/volume **que l'hôte fournit**.
  Un hôte Linux peut en **présenter un** (le sien). **INCONNU** : la valeur réelle (jamais extraite) et si le SEP
  **lie** l'enrôlement à l'uuid d'origine (politique, §5).

## 3. Q2 — séquence `AKSIdentityCreateKeybag[WithHash]` + type/flag (VU + DÉDUIT)

- **Pile (VU)** : client → `AKSIdentityCreateKeybag` (C, `AppleKeyStore.framework`) → XPC `service_identity_create_keybag`
  → `applekeystored` → logique Swift `AKSIdentity` → wrappers `aks_create_bag` (userclient **0x2**) / `aks_load_bag`
  (**0x6**) / `make_system_keybag` (`sks_userland_values.md` §1). 
- **`…_with_hash` (VU)** : exige des paramètres de hash **valides** et un **nombre d'itérations** valide (logs
  « *Invalid hash parameters / Invalid iterations for creating keybag with hash* ») → variante **épinglée** (le keybag
  est lié à un hash + PBKDF-like côté identité), cohérent avec `AKSIdentityCreateKeybagWithHash`.
- **type (+0x64) / flag / génération / Memento / LockState** : posés par la logique Swift `AKSIdentity` (type Swift
  `AKSIdentity.State` : `generation`, `LockState`, `Memento`, cf. `sks_userland_values.md` §2). Contrainte kext : **type
  ≤ −10** (`keybag_native_path.md` §1). **Valeurs numériques exactes = INCONNU** (méthodes Swift non désassemblées ;
  faible valeur marginale vs effort — les noms/sections suffisent pour l'architecture).

## 4. Q3 — scellement & persistance (VU → DÉDUIT)

- **Côté hôte = fichiers** (VU) : `identity_commit_oti` / `identity_commit_user_plist` / `identity_update_blobs_on_disk`
  / `commit_file` écrivent le blob d'identité (OTI), les blobs **KEK**, et le **plist utilisateur** sur disque
  (`/var/keybags`, Preboot, `/var/db/users`), **par user-uuid**. Au boot, `identity_load_from_disk_or_migrate_if_necessary`
  **recharge**. → **persiste au reboot** (enrôlement durable, pas recréé à chaque démarrage **si** le blob disque existe).
- **Côté SEP = xART** (VU/DÉDUIT) : symboles `aks_delete_xart_leak`, `stash_*`, `commit_file` → le SEP **scelle** le
  matériel de clé (xART) ; l'hôte conserve le **blob** et le re-fournit. Confirme le modèle de `keybag_native_path.md`
  §2 (persistance pilotée par l'hôte + notify-port ; scellement SEP en xART). **INCONNU** : le format octet du blob OTI
  (opaque) et le détail du scellement xART (hors de ces binaires).

## 5. Q4 — un OS non-macOS peut-il FABRIQUER une identité keybag neuve ? (verdict franc)

**OUI pour la CRÉATION — aucun mur cryptographique côté fabrication ; le seul verrou restant est une politique SEP,
à trancher sur matériel.** Pour/contre VU :

**POUR (VU/DÉDUIT fort) :**
1. **Création à neuf = chemin réel et exercé** : le démon lui-même « *…we will just create a new one* » quand le load/
   unlock du keybag legacy échoue (VU). La création n'est pas réservée à une cérémonie d'usine.
2. **Aucun secret macOS requis pour fabriquer** : `make_system_keybag` via identité envoie un **blob vide** — le **SEP**
   fabrique le keybag avec sa **clé d'appareil interne** (`keybag_native_path.md` §1). Rien que seul macOS détiendrait.
3. **UUID fourni par l'hôte** : c'est un **user-uuid parsé** (§2), pas une constante d'appareil ni un aléatoire scellé.
   Linux peut en présenter un.
4. **Persistance = simple fichier** : le blob vit dans `/var/keybags`/Preboot (§4). Linux peut le **stocker et recharger**
   lui-même (pas besoin d'un coffre macOS).

**CONTRE / risques (VU + INCONNU) :**
1. **Objet lié à un compte** : l'identité est **rattachée à un utilisateur** (dslocal, unlock records APFS). Linux
   devrait présenter un **uuid/compte cohérent**, pas un objet flottant.
2. **Garde d'unicité** : « *Can't create keybag when OTI, kek or keybag already exists* » → création refusée si un
   keybag existe déjà pour cet uuid (contournable avec un **uuid neuf**).
3. **Scellé au SEP (xART) + clé d'appareil** : le keybag obtenu est **celui de CE SEP**. **INCONNU décisif (matériel)** :
   le SEP/l'enrôlement sbio **honore-t-il** un keybag/identité **créé par Linux**, ou **lie-t-il** l'autorisation
   d'enrôlement à l'**identité/génération posée par macOS** (politique interne, invisible dans ces binaires) ?

**Conclusion** : **ce n'est pas un cul-de-sac cryptographique.** Fabriquer un keybag/identité d'appareil ne requiert
aucun secret macOS, l'uuid est choisi par l'hôte et la persistance est un fichier géré par l'hôte. **Le test qui
tranche** n'est donc pas « peut-on créer le keybag ? » (oui) mais « le SEP accepte-t-il d'**enrôler Touch ID** contre
une identité forgée par Linux ? » — **politique SEP, matériel uniquement, classe neuve → go d'Albert**. Rien ici n'est
matériel ; aucun uuid/secret extrait ; le passcode resterait fourni à l'exécution.

---

## 6. J10 — séquence de création à neuf : fil exact + valeurs (VU / DÉDUIT / INCONNU)

Ajout 2026-11-23 (session PC) pour préparer **J10 = créer un keybag d'appareil SANS passcode, voir si le SEP rend un
handle**. Côté kext = `source: kext` (kernelcache 27.2.1 `macos/kc/`), côté hôte = `source: userland`.

### 6.1 Mapping sélecteur userclient → méthode C++ → TAG fil
- **TAG fil des ops de création — VU** (immédiat `mov w1,#imm` juste avant le submit `mov x17,#0x392e ; blraa`) :
  - `AppleKeyStore::create_keybag` @0xcc6904 → builder `__ipc_create_keybag_v4` @0xcf9a34 (`mov w1,#1`) → **TAG fil 0x01**.
  - `AppleKeyStore::load_keybag` @0xcc6c3c → builder `__ipc_load_keybag` @0xcdb934 (`mov w1,#3`) → **TAG fil 0x03**.
  - `make_system_keybag` → builder `__ipc_make_system_keybag_v1` @0xcdbce4 (`mov w1,#0xd`) → **TAG fil 0x0d**. (= ce
    que le Mac avait vu ; recoupé.)
- **Dispatch userclient — VU** : `AppleKeyStoreUserClient::handleUserClientSelector(selector, args)` @0xcd0840 =
  **table de saut** sur `(selector − 1)` (`subs w28,w1,#1 ; cmp w28,#0xa8 ; ldrsw [table@0xcd8fbc + idx*4] ; br`).
  Le handler de création appelle `create_keybag` @0xcc6904 et logge « *Create keybag failed … Retrying* » (bloc
  @0xcd77e0) ; le handler de chargement appelle `load_keybag` @0xcc6c3c (@0xcd4dec). Les deux sont dans ce dispatch.
- **Sélecteurs userland — VU** (dyld, `sks_userland_values.md`) : `aks_create_bag` → **0x2**, `aks_load_bag` → **0x6**.
- **Binding sélecteur ↔ TAG — DÉDUIT fort** (par nom + les deux extrémités VU ; le byte-trace exact du jump-table
  n'est pas fait — cases entrelacées, branches `b` en avant) :
  **sélecteur 0x2 (create_bag) → `create_keybag` → TAG fil 0x01** ; **sélecteur 0x6 (load_bag) → `load_keybag` → TAG
  fil 0x03**. `make_system_keybag` (0x0d) n'est pas un simple sélecteur `aks_*` : c'est l'**étape d'identité**, atteinte
  par `AppleKeyStore::identity_load` @0xcf79a8 / `set_device_keybag` @0xcc7c48 (C++).

### 6.2 Ce que `create_keybag` (TAG 0x01) prend et rend — VU
Signature C++ (VU) : `create_keybag(this, u64 arg1, u32 classe, const u8* b1, u32 l1, const u8* b2, u32 l2, bool pin,
int* handle_out, int arg9)`. Le wrapper pose un **flag 0x100** si `pin!=0` (`csel … #0x100`), et appelle
`__ipc_create_keybag_v4`. → **entrées = une CLASSE (u32) + jusqu'à 2 blobs {ptr,len} (peuvent être VIDES) + un flag** ;
**sortie = un handle** (`int*`). **Aucun passcode/secret obligatoire pour l'appel create lui-même** (le secret se pose
plus tard via `aks_set_system`/unlock). → bon pour J10 : un `create_keybag` nu **doit rendre un handle**.
Codec OOL `_code_ipc_create_keybag` @0xcde0e4 (requête, après en-tête IPC 0x50) : `+0x50` état=0 (u32), `+0x58` u64,
`+0x60`/`+0x64` u32, puis **3 blocs blob** `+0x68/+0x70`, `+0x78/+0x80`, `+0x88/+0x90`, puis champs `+0x98`/`+0xa8`…
(message riche ; pour une création neuve, scalaires + **blobs vides**).

### 6.3 Séquence « créer à neuf » (le cas `/var/keybags` vide → « create a new one »)
Après `open EP 0x12` + `get_capabilities` (0x4d) + `set_env` (0x2a) [acquis J9a/J9b] :
1. **`create_keybag` (TAG fil 0x01)** — classe + blobs vides → **le SEP rend un handle** (VU : sortie `int*`). C'est
   l'op que J10 veut tester nue.
2. **`make_system_keybag` (TAG fil 0x0d)** — lie l'identité d'appareil : builder `__ipc_make_system_keybag_v1`, corps
   VU (`keybag_native_path.md` §1) = `+0x50` const 1, `+0x58` handle, `+0x60`/`+0x64` scalaires (**type au +0x64**),
   `+0x68/+0x70` blob **VIDE** (via `identity_load` → le SEP fabrique avec sa clé d'appareil), `+0x78` flag.
   Entrée via `identity_load` @0xcf79a8 : **OSData de 16 o OBLIGATOIRE** (VU `cmp w0,#0x10 ; b.ne`) = l'**uuid**.

### 6.4 Valeurs
- **uuid (16 o)** — **VU obligatoire** (`identity_load` exige une OSData de 0x10). C'est un **user-uuid fourni par
  l'hôte** (§2), pas un secret. Linux en présente un.
- **type (`make_system` +0x64)** — **contrainte VU : ≤ −10** (`identity_load` @0xcf7a30 : `cmn w21,#0xa ; b.gt`→**rejet
  si type > −10**). La **valeur exacte** est fournie par l'appelant Swift `AKSIdentity` (pas une constante kext) →
  **INCONNU précis**. Pour J10 : **balayer des valeurs ≤ −10**, ou **capturer** la valeur sur un macOS vivant. (Pas de
  constante nommée côté kext : `___der_key_keybag_type` est le champ DER de `perform_operation`, pas cet énum.)
- **classe (`create_keybag` arg2)** — petit énum de classe de bag ; **valeur exacte INCONNU** (posée par l'appelant).
- **génération initiale** — **DÉDUIT 0 à la création** (`AKSIdentity.State.generation`, Swift) ; valeur exacte INCONNU.

### 6.5 `create_keybag_with_hash` : sur le chemin de création à neuf ? — NON (DÉDUIT fort)
`create_keybag_with_hash` **exige des paramètres de hash ET un nombre d'itérations VALIDES** (VU, chaînes
`applekeystored` : « *Invalid hash parameters / Invalid iterations for creating keybag with hash* »). C'est la variante
**épinglée à un hash dérivé du passcode**. → le chemin **SANS passcode** (J10) utilise **`create_keybag` nu (TAG 0x01)**,
**pas** `_with_hash`. On ne pose un hash qu'au moment d'attacher un secret (étape ultérieure, hors J10).

### 6.6 Synthèse J10 (pour le script `pending/`)
`open 0x12 → getcap 0x4d → set_env 0x2a → create_keybag 0x01 (classe + blobs vides, flag) → [handle attendu] →
make_system_keybag 0x0d (handle + uuid 16 o + type ≤ −10, blob vide)`. **Byte-connu** : tous les TAG fil, l'en-tête IPC
(§1.6 `sks_protocol.md`, déjà en Rust J9c), les gabarits OOL. **À fournir/balayer au matériel** : la valeur de `classe`,
la valeur de `type` (≤ −10), l'uuid (celui de l'hôte). **Test J10 = voir si `create_keybag` nu rend un handle** (il le
doit, VU) — **classe neuve en écriture 0x12 → go d'Albert** ; power-cycle = Albert. Rien lancé ici.

---

## 7. Valeurs J10 (type / classe) — ce que le binaire fixe vraiment

Ajout 2026-11-23 (session PC), réponse à la PRIORITÉ 1 (fixer type/classe sans balayage). `source: kext` (27.2.1).

### 7.1 `type` (make_system_keybag +0x64) = **RÉSOLU PAR LE KEXT, pas choisi par l'hôte** — VU (découverte)
Le chemin d'identité (make_system via `identity_load`) est l'**op userclient sélecteur 0x78** (VU : cas jump-table
@0xcd4078 ; `handleUserClientSelector` @0xcd0840). Dans ce cas (VU @0xcd4078-0xcd411c) :
- entrée exigée : **1 struct-input** (`[x19,#0x28]==1`) = l'**uuid 16 o** ; **0 scalaire** (`[x19,#0x50]==0`).
- le **type n'est PAS un scalaire userspace** : le kext le **calcule** —
  `effective_bag_handle_actual(this, sel=0x78, input0=premier mot de l'uuid, int* out=&type)` @0xccfd20, qui appelle
  le résolveur `0xccff20(sel, input0)`, puis **écrit le type dans `[sp+0xf0]`** ; ce `[sp+0xf0]` devient `w3` d'
  `identity_load` (VU @0xcd4110 `ldr w3,[sp,#0xf0]`). `identity_load` rejette alors si **type > −10** (VU `cmn w21,#0xa ; b.gt`).
- **Conséquence J10 (importante)** : l'hôte **ne devine pas** le type. Il **sélectionne l'op 0x78 et fournit l'uuid** ;
  le **kext dérive le type** (≤ −10) de (0x78, uuid). → **pas de balayage de type nécessaire** : rejouer l'op 0x78 avec
  un uuid 16 o, exactement comme macOS.
- **Valeur numérique exacte** : produite par le résolveur `0xccff20` (multi-branches : masque de bits sur le sélecteur
  pour sel ≤ 0x23 ; pour 0x78 un chemin dépendant de `input0`/uuid) — **non réduite à une constante unique dans cette
  passe** (trace symbolique profonde). Les constantes voisines vues (−1/−2/−3/−6) sont **> −10** donc **pas** le type
  d'identité ; le type ≤ −10 vient d'une branche non entièrement évaluée. **INCONNU précis** (mécanisme VU). Pour J10,
  ce n'est **pas bloquant** : on émet 0x78+uuid et le kext pose le type. Si on veut la valeur écrite, option = finir la
  trace de `0xccff20` pour (0x78, input0), ou **capturer** sur macOS vivant.

### 7.2 `classe` (create_keybag arg2) — champ VU, valeur userland
- **Quel u32 du codec** : `create_keybag(this, u64 arg1, u32 CLASSE, …)` (VU sig @0xcc6904) ; le wrapper passe arg1→
  ctx+0x58 (u64), **arg2 (classe) → ctx+0x60 (u32)** (DÉDUIT positionnel, cohérent avec les autres codecs) ; l'autre
  u32 **+0x64** = l'argument suivant (un sous-type/flags du create). → **+0x60 = classe**, **+0x64 = param secondaire**.
- **Valeur** : le cas create (sélecteur 0x2 @0xcd3334) lit des **scalaires userspace** (`[x19,#0x50]`) → la classe est
  **fournie par l'appelant userland**, pas une constante kext. **Valeur exacte INCONNU** (posée par AKSIdentity/MKB).
  Classes de protection AKS usuelles = A/B/C/D (1..4) ; pour un keybag « système/device » la valeur précise reste à
  **capturer** (macOS vivant) ou **balayer en borné** (go d'Albert). Le `flag 0x100` (si `pin!=0`) est le seul autre
  champ non nul du create nu.

### 7.3 Récap décision J10
- **create_keybag nu (sélecteur 0x2 → TAG fil 0x01)** : rend un handle **sans passcode** (VU). Seule valeur à fournir =
  la **classe** (+0x60) → **INCONNU précis**, mais un create avec une classe plausible (ou balayage A..D borné) suffit
  pour le **test « le SEP rend-il un handle »**. C'est le test minimal J10.
- **make_system_keybag via op 0x78** : fournir **uuid 16 o** (struct-input) ; le **type est posé par le kext** (pas à
  deviner). → pas de balayage de type.
- **Reste INCONNU au binaire** (ALARM : balayage/capture matériel autorisé) : la **valeur de classe** du create système,
  et la **valeur numérique** du type écrit par `0xccff20` (non bloquant pour émettre l'op). Rien lancé ; écriture 0x12
  classe neuve → go d'Albert ; power-cycle = Albert.

### 7.4 Valeurs exactes pour le chemin NATIF (on pose +0x60 et +0x64 nous-mêmes) — verdict honnête
Pour le pilote natif (on émet le mot SEP brut, on EST le kext), il faut poser **classe (+0x60)** et **type (+0x64)**
nous-mêmes. Résultat du reverse : **ni l'un ni l'autre n'est une constante statique du binaire — ce sont des PARAMÈTRES
runtime.** Preuves VU :
- **type (+0x64)** : les **deux** appelants de make_system le passent en **variable** — `identity_load` (x4=x21, le type
  qu'il a reçu) et `set_device_keybag` (x4=x19, un **scalaire userspace** du userclient). Aucun `mov w4,#<const>`. La
  seule contrainte dure est **VU : ≤ −10** (`identity_load` @0xcf7a30 `cmn w21,#0xa ; b.gt`→rejet si > −10). Côté op
  d'identité (sélecteur 0x78), le type est **résolu dynamiquement** par `effective_bag_handle_actual`/`0xccff20`
  (petits négatifs −1/−2/−3/−6 pour un bag EXISTANT ; la branche « neuf » ≤ −10 est data-dépendante, **pas réductible à
  un littéral unique**).
- **classe (+0x60)** : le cas create (sélecteur 0x2 @0xcd3334) lit la classe d'un **scalaire userspace** (`[x19,#0x50]`,
  scalaire-count==1) ; le codec `_code_ipc_create_keybag` **ne valide aucune valeur** de +0x60 (pas de `cmp`). Le daemon
  ne nomme que les **classes de protection données A/B/C/D** (chaînes VU « CLASS A..D »). DÉDUIT : classe = classe de
  protection (A..D = 1..4) ; **aucune constante « system » dédiée** figée dans ces binaires.

**→ Verdict (franc, comme autorisé)** : **type et classe sont indéterminables au binaire comme constantes uniques.**
Deux options pour J10, par ordre de propreté :
1. **CAPTURE** (recommandé) : lire les mots **+0x60 (classe)** et **+0x64 (type)** directement **sur le fil** d'un
   `create_keybag` (0x01) et d'un `make_system_keybag` (0x0d) **émis par macOS vivant** (trace SEP). Source VU directe,
   zéro devinette.
2. **BALAYAGE BORNÉ** (go d'Albert) : classe ∈ {1,2,3,4} (A..D) ; type ∈ {−10, −11, −12, …} en partant de −10. Petit
   espace. Le test « le SEP rend-il un handle » sur `create_keybag` nu ne dépend **que de la classe** (make_system/type
   vient en 2e). Fail-closed à la 1re incohérence ; power-cycle = Albert.

---

## 8. `create_keybag` −13 (0xf3) : cause et correction — `source: kext` (27.2.1, kernelcache `macos/kc/`)

Ajout 2026-11-23 (session ALARM, Opus 4.8, capstone, hors-ligne). Explique le refus matériel J10 (journal 18:44,
`logs/20261123-184408_j10-sks-keybag-chained/`) : `> 0x12 TAG 0x01 (create_keybag) TYPE 0x03 DATA 0x007c0000` →
`< TAG 0x81 TYPE 0x03 PARAM 0xf3` = statut signé **−13 / −0xd**, longueur 0, pas de handle. Convention VU/DÉDUIT/INCONNU.
Désassemblage seul, rien lancé. **Verdict : ce n'est PAS une politique SEP ni un secret manquant — c'est un
DISCRIMINANT DE VERSION faux dans le corps du message (mauvais gabarit).**

### 8.1 Ce qu'est −0xd dans la couche IPC AKS — VU
Dans le kext, **−0xd est le code d'erreur générique du codec IPC** (pas une politique). Il est renvoyé par les
primitives de (dé)sérialisation du corps, **à chaque fois qu'un champ ne tient pas dans le tampon annoncé** (VU) :
- `__word` @0xcff1c0 → `mov w0,#-0xd` si moins de 4 o restants (`subs w10,w2,w10 ; b.lo` et `cmp w10,#4 ; b.lo`).
- `__blob` @0xcff218 → −0xd si le préfixe de longueur (aligné sur 4) dépasse le reste du tampon.
- `__lword` @0xcff38c (u64) et `__fv_data` @0xcff3e4 (= un `__blob` {ptr,len}) → −0xd même logique.
- `__ipc_msg_protect` @0xcecc84 → −0xd si `ctx` nul **ou** si **le bit0 « chiffré » des drapeaux (ctx+0x1c) est posé**
  (VU `ldrb w8,[x20,#0x1c] ; tbnz w8,#0 → -0xd`) : le codec **n'implémente pas** le canal chiffré. (C'est ce que
  `sks_protocol.md` §1.6.3/§1.7.1 appelait « chemin chiffré = −0xd ». Ici non pertinent : on envoie drapeaux = 0.)
- `__ipc_msg_process_header` @0xcecc70 → −0xd si son `x1` est nul.

**Nuance importante (VU)** : le codec AP `_code_ipc_create_keybag` **normalise toute erreur interne en −1** à sa fin
(`csinv w0,w8,wzr,ne` @0xcde6ec : succès → nb d'octets consommés ; échec → −1). Donc le −0xd **ne sort pas sur le fil
par CE binaire AP**. Le −0xd reçu est produit par **SEPOS** (sa propre copie du même code AKS), qui — DÉDUIT — propage
le −0xd brut de sa primitive de décodage sans cette normalisation. ⇒ **−0xd = « le corps du message ne se décode pas »
côté SEP** (cadre/longueur/version), pas un verdict d'autorisation.

### 8.2 `create_keybag` est un message VERSIONNÉ ; le discriminant est à ctx+0x50 — VU
`_code_ipc_create_keybag` @0xcde0e4 : après l'en-tête IPC (0x54 o), il (dé)code **un u32 à ctx+0x50** puis **branche sur
sa valeur** (VU @0xcde1b0 `ldur w8,[x21,#0x50]`, `switch(0..5)`, défaut → erreur). **Ce u32 n'est PAS « état = 0 » comme
pour `get_capabilities`/`set_env`** (codecs simples sans switch) : c'est le **numéro de variante/version du corps
`create_keybag`**. Gabarits VU (champs dans l'ordre fil, blobs = `__blob` préfixe u32 aligné 4) :

| ctx+0x50 | corps (après le u32 discriminant lui-même) |
|---|---|
| 0 | handle_y(u64 @0x58) + word(@0x60) + word(@0x64) + **1 blob**(@0x68) |
| 1 | … + **2 blobs**(@0x68,@0x78) |
| 3 | … + **3 blobs**(@0x68,@0x78,@0x88) |
| **4** | … + **3 blobs** + **`__fv_data` blob**(@0x98) + **u64**(@0xa8) |
| 5 | encore plus (fv_data + lwords @0xa8/@0xb0 + blob @0xb8) |

### 8.3 La variante que macOS émet = **4** — VU (constante)
Le sélecteur userclient 0x2 (`aks_create_bag`) → handler `AppleKeyStore::create_keybag` @0xcc6904 → builder
**`__ipc_create_keybag_v4`** @0xcf9a34. Ce builder **écrit le discriminant ctx+0x50 depuis une constante** :
`adrp x8,#0x7710000 ; ldr d0,[x8,#0x98] ; str d0,[sp,#0x88]` (@0xcf9aa8). Les 8 o lus à `__const` **0x7710098** =
`04 00 00 00 00 00 00 00` (VU) → **ctx+0x50 = 4**, ctx+0x54 = 0. (Les 8 o suivants `05 00 00 00…` servent à
`__ipc_create_keybag_v5` @0xcf9ba4 → variante 5.) Le builder remplit ensuite ctx+0x60/+0x64 = args w3/w4, les 3 couples
blob (ctx+0x68/+0x78/+0x88 {ptr,len}), et pose le **flag 0x100 si `pin!=0`** (VU handler @0xcc6938). → **le
`create_keybag` nu de macOS est un message de VARIANTE 4.**

### 8.4 Pourquoi notre requête J10 a pris −0xd — DÉDUIT (fort, VU des deux côtés)
Le pilote a posé **ctx+0x50 = 0** (cru « état ») mais a bâti un corps de **~40 o** (handle + 2 words + **3 blobs** +
un « flag »), soit un corps de **forme variante 3/4**. Le SEP décode selon le discriminant **= 0** → gabarit **variante
0** (1 seul blob, ~24 o de corps). Le reste du tampon ne correspond à aucun champ attendu de la variante 0 → la
primitive de décodage bute (longueur/cadre) → **−0xd**. Autrement dit : **corps d'une version, étiquette d'une autre.**
(Le −13 « longueur 0, pas de handle » est cohérent : le SEP abandonne au décodage, avant la logique keybag.)

### 8.5 Correction à tester en J10b — gabarit byte-exact VARIANTE 4
**Un seul changement conceptuel : émettre EXACTEMENT la variante 4 de macOS** (discriminant 4 + les 2 champs de fin que
le pilote omettait). Corps après l'en-tête IPC (OOL 0x54), petit-boutien :

| OOL off | taille | champ (ctx) | valeur J10b | vs J10 |
|---|---|---|---|---|
| 0x54 | 4 | discriminant (ctx+0x50) | **`04 00 00 00`** | **était `00 00 00 00`** |
| 0x58 | 8 | handle_y (ctx+0x58, u64) | 0 | inchangé |
| 0x60 | 4 | class (ctx+0x60) | 1 (ou classe à balayer) | inchangé |
| 0x64 | 4 | field2 (ctx+0x64) | 0 | inchangé |
| 0x68 | 4 | blob1 len=0 (ctx+0x68) | `00 00 00 00` | inchangé |
| 0x6c | 4 | blob2 len=0 (ctx+0x78) | `00 00 00 00` | inchangé |
| 0x70 | 4 | blob3 len=0 (ctx+0x88) | `00 00 00 00` | inchangé |
| 0x74 | 4 | **fv_data len=0** (ctx+0x98) | `00 00 00 00` | **NOUVEAU (remplace le « flag »)** |
| 0x78 | 8 | **u64 de fin** (ctx+0xa8) | `00…00` | **NOUVEAU** |

→ corps = **0x2c (44 o)**, message total **0x80** ⇒ **DATA = 0x00800000** (était 0x007c0000). **Recalculer le condensé
SHA-256/16 de l'en-tête** sur le nouveau corps (base §1.6.3 de `sks_protocol.md` ; le pilote le fait déjà pour
getcap/set_env). Drapeaux (ctx+0x1c) **restent 0** (ne JAMAIS poser le bit0 « chiffré » → sinon −0xd garanti, §8.1).

**Ordre de probabilité des corrections :**
1. **Variante 4 byte-exacte** (ci-dessus) — la seule à tester d'abord ; supprime l'ambiguïté version/cadre, qui est la
   cause VU la plus directe de −0xd.
2. Si −0xd persiste après la variante 4 : essayer **variante 5** (discriminant 5 + fv_data + lwords @0xa8/@0xb0 + blob
   @0xb8 ; corps plus long) — autre gabarit « moderne ».
3. Si −0xd persiste encore avec un corps au cadre VALIDE (décodage réussi) : alors **seulement** il s'agirait d'un code
   **sémantique** de `create_keybag` côté **SEPOS** (classe/handle/field2 invalides, précondition, ou politique) — **non
   lisible dans le kext AP** → mur, à trancher par capture d'un `create_keybag` macOS vivant (lire +0x50/+0x58/+0x60/
   +0x64 et les blobs réels sur le fil).

### 8.6 Points ouverts (honnêtes)
- **−0xd vient-il du décodeur de cadre SEPOS ou de la sémantique ?** DÉDUIT = cadre (version/longueur), car −0xd est
  partout le code du codec et notre étiquette de version était fausse. **Non prouvable sur le binaire AP** (codec AP
  normalise en −1 ; SEPOS non lisible). La correction variante 4 tranche empiriquement (classe neuve → go d'Albert).
- **field2 (ctx+0x64)** et **handle_y (ctx+0x58)** pour un create à neuf : valeurs réelles **INCONNU** (posées par
  l'appelant Swift ; §7). 0 est le pari de départ, pas une certitude.
- **class** : toujours la même INCONNU qu'en §7.2 (A..D = 1..4 plausibles ; capturer pour certitude).

---

## 9. `create_keybag` −11 (0xf5, variante 4) : cause et correction — `source: kext` (27.2.1, kernelcache `macos/kc/`)

Ajout 2026-11-23 (session ALARM, agent reverseur, Opus 4.8, capstone, hors-ligne). Explique le refus matériel J10b
(journal 19:15, `logs/20261123-191540_j10-sks-keybag-chained/`) : après correction en **variante 4** (§8.5), la requête
`> 0x12 TAG 0x01 (create_keybag) TYPE 0x03 DATA 0x00800000`, OOL = variante 4 byte-exacte, handle_y=0, class=1,
field2=0, **3 blobs vides + fv_data vide + u64 final 0**, drapeaux 0, condensé OK → `< TAG 0x81 TYPE 0x03 **PARAM 0xf5**` =
**−11 / −0xb**, longueur 0, pas de handle. getcap + set_env ACCEPTÉS juste avant. Convention VU/DÉDUIT/INCONNU ;
désassemblage seul, rien lancé. **Verdict : la variante 4 est bien décodée (plus de −0xd), le SEP rejette pour un code
SÉMANTIQUE −0xb = "argument requis NUL / hors borne" (BadArgument). Ce n'est PAS fv_data (réfuté, VU).**

### 9.1 −0xb = BadArgument (argument requis NUL ou hors borne) — VU (4 sites concordants)
Dans le kext, le littéral `mov w*,#-0xb` apparaît à **4 endroits**, toujours **juste avant un test de nullité `cbz`**
(ou une borne de longueur), jamais comme code de cadre/codec (le codec, lui, normalise en −1, §8.1) :
- `_encode_list_merge_dict` @0xcffd38 : `cbz x0 → mov w0,#-0xb ; ret` (dictionnaire d'entrée NUL). VU.
- `_encode_list_cstr_add_data` @0xd00284 : `mov w0,#-0xb` puis `cbz x20` (données NUL) **ou** `cmp x2,#0x10 ; b.hi`
  (clé > 16 o) → −0xb. VU.
- `_fv_import` @0xcf0208 / @0xcf02ec : `mov w23,#-0xb` suivi d'une rafale de `cbz x20/x21`, `ldr x8,[x24,#8] ; cbz`,
  `cbz x24` (pointeurs/longueurs de blobs FileVault NULs). VU.
- `__ZN13AppleKeyStore20pf_fv_derive_vek_keyE…` @0xcf2e78 : même motif. VU.
→ **−0xb est le code AKS « un argument/pointeur requis est NUL (ou une longueur hors borne) »** (BadArgument). Pas de
chaîne nommée pour ce code dans le kext (table d'erreurs→texte absente) ; le nom exact d'énum reste INCONNU, le
**comportement** est VU. (À distinguer de −0xd = cadre indécodable, §8.1, et −1 = erreur générique normalisée.)

### 9.2 Le −0xb vient de SEPOS, pas de l'AP — VU
- Le mot de réponse porte `PARAM = 0xf5` ; l'AP lit PARAM en **int8 signé** et, s'il est ≠ 0, **rend ce code sans
  décoder le corps** (§1.6.4 de `sks_protocol.md`). Donc −11 est littéralement l'octet PARAM **émis par le SEP**.
- Côté AP, le chemin create n'a **aucune garde −0xb** : `create_keybag` @0xcc6904 est un stub mince (réarrange les args,
  pose le flag 0x100 si `pin`, appelle `__ipc_create_keybag_v4` @0xcf9a34, puis **soumet** `blraa`), et le dispatch
  userclient `kAppleKeyStoreKeyBagCreateWithData` @0xcd0844 ne fait que **logger** « *Create keybag failed: %d. Retrying* »
  avec le code renvoyé par le SEP. **La logique de création (et sa validation sémantique) tourne dans SEPOS, absente de
  ce binaire** ; −0xb n'y est donc **pas directement traçable**. VU (stub) + DÉDUIT (SEPOS).

### 9.3 Ce n'est PAS fv_data — la variante 4 de macOS a elle-même fv_data VIDE — VU (réfute la piste "fv_data requis")
Désassemblage complet du builder `__ipc_create_keybag_v4` @0xcf9a34 (ctx = `sp+0x38`) :
- `ctx+0x50` = **4** (discriminant, const `__const` 0x7710098 = `04 00…`), `ctx+0x54`=0. VU (recoupe §8.3).
- `ctx+0x60` = **w3 = class**, `ctx+0x64` = **w4 = arg9** (le dernier `int` de `create_keybag`). VU.
- `ctx+0x58` = x2 = **arg1 (u64, handle_y)**. VU.
- `ctx+0x68/+0x70` = **blob1 {ptr,len}** = (b1, l1) ; `ctx+0x78/+0x80` = **blob2** = (b2, l2). VU.
- `ctx+0x88/+0x90` = **blob3**, `ctx+0x98/+0xa0` = **fv_data {ptr,len}**, `ctx+0xa8` = **u64 final** : remplis depuis des
  emplacements de pile que **l'unique appelant met à 0** (blob3/fv_data/u64 jamais alimentés par `create_keybag`). VU.

**Unique appelant de `create_keybag` = `kAppleKeyStoreKeyBagCreateWithData` @0xcd0844** (site @0xcd77e0 ; `callers`, VU).
Là, b1/b2 = **charges d'OSData fournies par le client** (via vmethods +0x160 longueur / +0x198 octets), **NUL si absentes**
(branches `cbz → str xzr`, VU). Donc **macOS lui-même, sur un create sans données, envoie une variante 4 avec blob3 +
fv_data + u64 final VIDES** — exactement ce que J10b a émis pour ces champs. ⇒ **fv_data vide est légitime ; la "piste la
plus probable" annoncée (fv_data = données FileVault requises en v4) est RÉFUTÉE (VU).**

### 9.4 Qu'est donc l'argument NUL que le SEP exige ? — DÉDUIT (fort) + INCONNU (byte)
−0xb est partout un **test de pointeur NUL** (`cbz`), rarement un scalaire 0. Or J10b a laissé **les deux blobs de données
b1/b2 VIDES** (len 0, ptr effectif nul). L'opération est littéralement « **CreateWith**Data » et son unique appelant
transporte des **OSData**. **Hypothèse la plus forte (DÉDUIT) : le moteur create de SEPOS exige au moins un blob de
données non vide (b1 `ctx+0x68` ou b2 `ctx+0x78`) ; nos blobs nuls déclenchent un `cbz` → −0xb.** Candidats secondaires :
- `ctx+0x64` (**arg9**) : dans le builder frère `__ipc_make_system_keybag_v1`, `+0x64` = **type de keybag** (contrainte
  ≤ −10, §7). Si create partage ce rôle, un **type = 0** est un BadArgument classique. Scalaire, pas pointeur → moins
  typique d'un `cbz`, mais plausible.
- `ctx+0x58` (**handle_y = arg1**) = 0 : moins probable (0/−1 = « aucun » usuel).
- `ctx+0x60` (**class = 1**) : non nul → ne tombe pas sur un `cbz`, le moins probable.
**Lequel exactement = INCONNU au binaire AP** (moteur create = SEPOS, non lisible). Ni −0xd (cadre) ni politique ici :
c'est un BadArgument sur un **champ qu'on a mis à 0/vide**.

### 9.5 Conséquence d'architecture : `create_keybag` (0x01) ≠ création d'un keybag VIDE — DÉDUIT (fort)
`create_keybag`/0x01 n'a qu'une entrée : **CreateWith**Data (import d'un blob de keybag fourni). La **création à neuf d'un
keybag système vide** (SEP fabrique avec sa clé d'appareil) est, elle, **`make_system_keybag` (TAG 0x0d)**, dont le
builder `__ipc_make_system_keybag_v1` envoie un **blob VIDE** (§6.3, `keybag_native_path.md` §1). ⇒ le plan J10
(create_keybag 0x01 nu → handle → make_system 0x0d) a probablement **mal choisi la 1re op** : pour un keybag vide, 0x01
n'est pas le bon verbe. (DÉDUIT ; cohérent avec « CreateWithData », l'unique appelant OSData, et −0xb = BadArgument sur
données absentes.)

### 9.6 Correction à tester — ordre de probabilité (le "byte-exact" et le repli)
1. **PIVOT d'opération (recommandé n°1)** : ne pas re-taper `create_keybag`/0x01 à vide. Tester **`make_system_keybag`
   (TAG fil 0x0d)** nu — c'est la **vraie op de création d'un keybag vide** (blob vide, SEP fabrique). Corps VU :
   `+0x50`=1, `+0x58`=handle, `+0x60`/`+0x64`=scalaires (**type au +0x64, ≤ −10**), `+0x68/+0x70` blob VIDE, `+0x78` flag
   (§6.3). L'entrée d'identité (op userclient 0x78) fournit l'**uuid 16 o**, le kext dérive le type (§7.1). Changement de
   message, pas d'octet dans la trame create.
2. **Si on reste sur `create_keybag`/0x01 (byte-exact, 1 mot)** : poser **`ctx+0x64` (OOL 0x64) = type de keybag non nul**
   au lieu de 0 (candidat le plus net après les blobs) — p. ex. la valeur ≤ −10 du chemin système, ou un petit positif
   1/2 à balayer. Un mot, OOL 0x64, petit-boutien. Probabilité moindre que (1) car −0xb vise surtout un pointeur NUL.
3. **CAPTURE (seule certitude byte)** : lire sur le fil un `create_keybag` (0x01) **et** un `make_system_keybag` (0x0d)
   **émis par macOS vivant** → valeurs réelles de `+0x58/+0x60/+0x64` et des blobs. Le moteur create étant dans SEPOS,
   c'est la seule source VU directe des arguments attendus.
4. **Mur honnête** : la validation sémantique de create vit dans **SEPOS, non lisible dans ce kernelcache**. On sait
   **quoi** (BadArgument, VU) mais pas **quel champ** avec certitude byte. La capture (3) ou le pivot (1) tranchent ;
   toute écriture 0x12 = classe neuve → go d'Albert ; power-cycle = Albert.

### 9.7 Points ouverts (honnêtes)
- **Quel argument exactement** déclenche −0xb (blob b1/b2 ? type +0x64 ? handle +0x58 ?) : **INCONNU au binaire AP**
  (moteur SEPOS). DÉDUIT = blob de données requis (op « WithData », −0xb = NUL-check).
- **Nom d'énum de −0xb** : non trouvé (pas de table code→texte dans le kext). Comportement = BadArgument, VU.
- **`make_system_keybag` acceptera-t-il un keybag vide forgé par Linux** (politique SEP d'enrôlement) : toujours INCONNU,
  matériel uniquement (§5).

---

## 10. `perform_operation` bring-up (DER exact) — PISTE A instruite — `source: kext` (27.2.1, kernelcache `macos/kc/`)

Ajout 2026-11-23 (session ALARM, agent reverseur, Opus 4.8, capstone, hors-ligne). **But** : extraire le DER octet-près
des `perform_operation` (TAG fil **0x22**) « d'identité système » que PISTE A veut émettre après `set_env` — sélecteurs
`osc` (sik_collection), `ogss` (get_sik_status), `oska` (system_key). **Protocole uniquement ; aucune clé/seed/secret
extrait ; aucun code Apple copié.** Désassemblage seul, rien lancé, rien `vérifié`. Convention VU/DÉDUIT/INCONNU.

> **Résultat net (à lire d'abord) :** la trame DER de chaque op `perform_operation` est **fabriquée par libaks** (famille
> `_aks_*` → `__create_operation_list` → `_encode_list_*` → `__aks_operation` → `_kern_perform_operation`). La **grammaire
> et les octets de clés/sélecteurs sont VU** (ci-dessous, byte-exact). Mais **deux corrections dures** à la prémisse de
> PISTE A, VU au binaire :
> 1. **`osc` (sik_collection) et `ogss` (get_sik_status) n'ont AUCUN builder dans le kernelcache.** Leurs constantes DER
>    existent mais ne sont référencées **que par le décodeur** `_ref_key_op_der_to_enum` (@0xd0155c) — **jamais par un
>    constructeur**. Ces deux ops sont émises **exclusivement par le userland** (libaks dans applekeystored/dyld cache).
>    Leur composition exacte **n'est pas dans le kernelcache** (et le dyld cache n'était pas déchiffrable cette session :
>    `ipsw` absent, fichiers `dsc/` en decmpfs).
> 2. **`oska` (system_key_attest) N'EST PAS « à froid » : il PORTE un `rk`** (il atteste un ref_key **existant**). Donc il
>    n'est **pas** émettable avant qu'une clé système ait été créée. (VU, §10.3.)
>
> Les seules ops « identité système » **réellement émettables sans `rk` ni `acmh`** (handle −1) et **entièrement lisibles
> au binaire** sont **`oskc2` (system_key_collect) et `oskgp` (system_key_get_public)** — PAS celles nommées dans la
> consigne. (VU, §10.2.)

### 10.1 Enveloppe commune sur le fil — VU (recoupe `sks_protocol.md` §1.6/§2.3.2)
Tout `perform_operation` part en : `> EP=0x12 TAG=0x22 TYPE=seq PARAM=0 DATA=(len_total<<16)`. L'OOL A contient, dans
l'ordre : en-tête IPC `0x54` o (u32 longueur=0x50 + 0x50 o : condensé SHA-256/16, version, horodatage µs, drapeaux=0,
bloc processus — §1.6 de `sks_protocol.md`) **puis** `état u32 = 0` **puis** `u64 = 1` **puis** `u32 longueur DER` **puis
le DER**. Donc **DER = len_total − 0x64**. Le DER est un **SET (`0x31`)** de paires **SEQUENCE (`0x30`){ UTF8String clé,
valeur }**, triées par **longueur de clé puis `memcmp`** (VU, §2 de `sks_protocol.md`). Le mot mailbox ne porte aucun
contenu. La réponse `< TAG 0xa2 TYPE seq PARAM statut DATA (len<<16|flag)` (PARAM int8 : 0=OK, sinon code rendu brut).

### 10.1b Octets exacts des briques DER — VU (`___der_key_*`, lus au binaire)
Sélecteurs (valeur du champ `o`, chaque constante = UTF8String DER pré-encodé) :

| op | octets du sélecteur (valeur de `o`) | builder kext ? |
|---|---|---|
| sik_collection `osc` | `0c 03 6f 73 63` | **NON** (userland seul) |
| sik_attest `osa` | `0c 03 6f 73 61` | oui (`__op_attest`, porte `rk`) |
| get_sik_status `ogss` | `0c 04 6f 67 73 73` | **NON** (userland seul) |
| gid_attest `oga` | `0c 03 6f 67 61` | oui |
| system_key_attest `oska` | `0c 04 6f 73 6b 61` | oui (**porte `rk`**) |
| system_key_collect `oskc2` | `0c 05 6f 73 6b 63 32` | **oui, à froid (handle −1)** |
| system_key_get_public `oskgp` | `0c 05 6f 73 6b 67 70` | **oui, à froid (handle −1)** |
| system_key_operate `osko` | `0c 04 6f 73 6b 6f` | oui |
| system_key_sign `osks` | `0c 04 6f 73 6b 73` | oui |

Clés de paires (nom → octets → type de valeur, VU) : `o`=`0c 01 6f` (UTF8) ; `skt`=`0c 03 73 6b 74` (INTEGER, type de
clé système) ; `skg`=`0c 03 73 6b 67` (INTEGER, génération) ; `skcs`=`0c 04 73 6b 63 73` (OCTET STRING, client_seed) ;
`sko`=`0c 03 73 6b 6f` ; `skos`=`0c 04 73 6b 6f 73` ; `skni`=`0c 04 73 6b 6e 69` ; `rk`=`0c 02 72 6b` (ref_key, **DER
brut recopié**). Une paire = `30 <len> <clé> <valeur>` ; p. ex. `o=oskc2` → `30 0a 0c 01 6f 0c 05 6f 73 6b 63 32`.

### 10.2 Les DEUX ops « à froid » lisibles au binaire — VU (composition complète)
Désassemblés cette session (capstone, `_OUTLINED_FUNCTION_*` expansés) :

**`oskc2` system_key_collect — `_aks_system_key_collection` @0xfffffe0009cefb74 — VU :**
```
op = oskc2            (chargé via GOT auth [0xcbb8a38] → ___der_key_op_system_key_collect)
__create_operation_list(op)                         → liste (SET)
si arg2 != 0 :  _encode_list_merge_dict(liste, arg2, len)   # fusionne un dict OPTIONNEL (c'est là que skcs irait)
_encode_list_add_number(liste, "skt", arg0)         # skt = INTEGER(arg0)
_encode_list_add_number(liste, "skg", arg1)         # skg = INTEGER(arg1)   (clé via GOT [0xcbb8a78] = generation)
_encode_list_dict(liste) → (ptr, len)
__aks_operation(handle = -1, ptr, len, …)           # handle −1 = AUCUN keybag  →  _kern_perform_operation (TAG 0x22)
(résultat rangé dans un global AP @0x8297930)
```
→ **Trame DER = `SET { o=oskc2, [dict fusionné optionnel], skt=INTEGER(arg0), skg=INTEGER(arg1) }`**. **PAS de `rk`,
PAS de `acmh`, handle −1.** Émettable sans keybag ni auth. (VU.)

**`oskgp` system_key_get_public — `_aks_system_key_get_public` @0xfffffe0009cefd68 — VU :** **structure IDENTIQUE** à
oskc2 (mêmes helpers, même `arg2` dict optionnel, mêmes `skt`/`skg`, même `handle = -1`), seul l'op change (`oskgp` via
GOT [0xcbb8a40]). → `SET { o=oskgp, [dict opt], skt=INTEGER(arg0), skg=INTEGER(arg1) }`.

**Ce que « arg0/arg1/arg2 » valent = RUNTIME, posés par l'appelant userland (INCONNU au binaire)** : `skt` (type de clé
système, petit entier), `skg` (génération, petit entier), et le **dict `arg2`** optionnel — **c'est très probablement là
que vit `skcs` (client_seed)**, l'OCTET STRING de ~16–20 o déduit en `sks_protocol.md` §2.3.2. **Si `skcs` est une
constante → trame rejouable ; si c'est un nonce → non rejouable. INDÉTERMINÉ ici** (le binaire kext ne fixe aucune de ces
valeurs ; elles arrivent par les arguments de la KPI). Aucune clé/seed extraite.

### 10.3 `oska` (system_key_attest) PORTE un `rk` — VU (correction de PISTE A)
`_aks_system_key_attest` @0xfffffe0009cbff50 (capstone) déréférence son arg ref_key `x23` : `[x23]`/`[x23+0x10]` = blob
de clé scellée, `[x23+0x28]` = handle. Il fait `__get_merged_params(ref_key,…)`, **retire puis ré-ajoute `rk`**
(`_encode_list_remove_key` + `_encode_list_add_der(rk, [x23], [x23+0x10])`), puis `skt=INTEGER(arg0)`,
`skg=INTEGER(arg1)`, et soumet avec `handle = [x23+0x28]`. → `SET { o=oska, <params fusionnés du ref_key>, rk=DER_brut,
skt=INTEGER, skg=INTEGER }`. **`oska` ne peut donc PAS être émise à froid : elle atteste une clé système DÉJÀ créée.**
(Idem `osa`/sik_attest via `__op_attest` @0xfffffe0009cefa88 : porte `rk`.) **Ceci réfute la ligne « oska … SANS rk donc
à froid » du handoff** (VU).

### 10.4 `osc` / `ogss` : userland uniquement — VU (preuve d'absence)
- Table GOT des pointeurs d'op @0xcbb8a00 décodée (rebase `cible = 0xfffffe0007004000 + offset`, VU) : slot **a10 →
  `osc`**, **a20 → `ogss`**. Un scan exhaustif des `adrp+add` du bundle AppleSEPKeyStore montre que **a10 et a20 ne sont
  chargés que par `_ref_key_op_der_to_enum`** (@0xd0155c, le **décodeur** chaîne→énum) — **par aucun constructeur**.
- Énumération de **tous** les appelants de `__create_operation_list` (@0xcbf828) dans le kext : on retrouve la famille
  ref_key (encrypt/decrypt/sign/wrap/unwrap/delete/…), `osa`/`oga` (attest), et `oska`/`oskc2`/`oskgp`/`osko`/`osks` —
  **jamais `osc` ni `ogss`**. (VU.)
- ⇒ **Les trames `osc` et `ogss` ne sont pas reconstructibles depuis le kernelcache.** Elles sont bâties par **libaks
  en userland** (applekeystored / dyld shared cache). Par analogie de source (même libaks), leur forme est
  vraisemblablement `SET { o=osc }` / `SET { o=ogss }` éventuellement + `skcs`/`skt` — **DÉDUIT, NON VU** ; byte-exact
  **INCONNU** tant que libaks userland n'est pas lu (dyld cache non déchiffré cette session).

### 10.5 Émetteur du bring-up : HORS kext — VU (confirme `sks_protocol.md` §2.3.4)
Scan global de **tout le kernelcache** (tous les bundles) : **zéro `bl`/`b`** vers `_aks_system_key_collection`,
`_aks_system_key_attest`, `_aks_sik_attest`, `_aks_system_key_operate/_get_public/_sign`. Ces builders sont une **KPI
libaks** appelée depuis l'**espace utilisateur** (applekeystored via l'userclient → `perform_operation`), pas depuis le
kext. Donc **le mapping txn3↔sélecteur / txn5↔sélecteur et les valeurs (`skt`/`skg`/`skcs`) restent INCONNU** : ils
vivent dans le runtime du démon + SEPOS. (VU côté absence d'appelant ; mapping INCONNU.)

### 10.6 La création du keybag dépend-elle de cette pré-séquence ? — VERDICT
- **Côté AP : INDÉPENDANT (VU).** Les builders keybag (`__ipc_create_keybag_v4` 0xcf9a34, `__ipc_make_system_keybag_v1`
  0xcdbce4, `__ipc_load_keybag` 0xcdb934 ; §6-9) **ne lisent aucun** des globaux où `_aks_system_key_*` rangent leur
  résultat (0x8297930 / 0x82979f0 / 0x8297970), et **n'appellent aucun** builder system_key/sik. Chaque `0x22` est
  **autonome sur le fil**. Rien dans le kext n'impose d'émettre `osc`/`oskc2`/… **avant** `create_keybag`/`make_system`.
- **Côté SEPOS : HYPOTHÈSE, non vérifiable au binaire.** Que le SEP **exige** que son identité d'appareil / SIK / clé
  système soit établie (par un `oskc2`/`osc` antérieur) avant d'accepter de forger un keybag est une **politique
  interne au firmware SEP, illisible** dans tout binaire AP. Rien ne l'étaie ni ne l'infirme ici.
- **Nuance qui penche CONTRE la piste A comme chaînon manquant (DÉDUIT) :** le refus observé est **−0xb = BadArgument =
  `cbz` d'un pointeur requis NUL** (§9), c.-à-d. « un **argument de CE message** manque », pas un code « précondition/
  état absent » (le SEP a d'autres codes pour ça). Un `cbz` sur un argument de la trame create colle **mieux** à un
  champ qu'on a mis à 0/vide (§9.4) qu'à une pré-séquence sautée. **DÉDUIT, non prouvé.**

**→ Réponse à la question d'Albert :** *la création du keybag dépend-elle de la pré-séquence `perform_operation` ?*
**Côté AP, NON (indépendant, VU).** Une dépendance côté **SEPOS reste possible mais c'est une HYPOTHÈSE non vérifiable
au binaire** ; et le reverse **ne la soutient pas** (le −0xb pointe vers un argument manquant dans NOTRE trame create,
pas vers un état préalable). **PISTE A est donc jouable mais spéculative**, et sa prémisse est **à corriger** : les ops
réellement émettables à froid sont **`oskc2`/`oskgp`** (pas `oska` qui exige un `rk`, pas `osc`/`ogss` absents du kext),
et leurs **valeurs (`skt`/`skg`/`skcs`) sont RUNTIME/INCONNU** — il faudrait les **capturer sur un macOS vivant** (ou
lire libaks du dyld cache déchiffré) avant de pouvoir émettre une trame byte-exacte.

### 10.7 Points ouverts (honnêtes)
- **Valeurs `skt`/`skg`/`skcs`** des ops de bring-up : **INCONNU** (runtime userland / SEPOS). Décident à elles seules de
  la rejouabilité (constante vs nonce). Seule source VU directe = capture OOL 0x12 sur matériel, ou libaks userland.
- **Trame byte-exacte de `osc`/`ogss`** : **INCONNU** au kernelcache (builders userland ; dyld cache non déchiffré —
  `ipsw` absent, `dsc/` en decmpfs). Reconstructible seulement en lisant libaks userland.
- **Mapping txn3/txn5 ↔ sélecteur** : **INCONNU** (émetteur userland non identifié ; §10.5).
- **Dépendance keybag ↔ pré-séquence côté SEPOS** : **HYPOTHÈSE non vérifiable au binaire** ; le reverse penche contre
  (§10.6). Trancher = expérience matériel (émettre `oskc2`/`oskgp` après `set_env`, puis re-tenter create — classe neuve
  → go d'Albert ; valeurs `skt`/`skg` à balayer ou capturer), **ou** capture macOS vivant de la séquence réelle.
