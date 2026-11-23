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
