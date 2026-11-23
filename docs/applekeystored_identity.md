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
