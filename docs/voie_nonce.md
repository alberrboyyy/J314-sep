# Voie « nonce / établissement de session » — instruction de l'hypothèse B′

> Agent : analyste (Claude Opus 4.8). Date : **2026-11-18**. Phase 2.
> Statut global : **hypothèse** (rien n'est marqué vérifié ici ; aucune expérience nouvelle n'a été menée).
> Méthode : LECTURE SEULE sur `traces/`, relecture `docs/kext_sepmanager.md` §8/§9, `docs/messages.md`,
> `m1n1/proxyclient/m1n1/hw/sep.py`. Aucune action matérielle, aucune écriture SEP.

## 0. La question (rappel)

Hypothèse B′ (du sceptique) : sous macOS, le SEP **RESTAURE** son xART puis **RE-SCELLE** sous le nonce de
boot établi par iBoot/macOS ; notre amorçage m1n1 (`pending/sep_boot.sh`) **n'établit jamais** ce contexte
→ le SEP re-scelle quoi qu'on serve. Si c'est vrai, la vraie voie Touch ID = reproduire l'établissement du
nonce, pas rejouer un coffre.

Verdict de ce rapport, en une phrase : **la forme littérale de B′ est contredite par l'ordre de boot observé**
(le SEP restaure et annonce `sbio`/`sks` AVANT tout échange pnon), et **l'idée générale** (le re-scellement
vient d'un nonce de fraîcheur non reproductible) reste cohérente avec le kext §9 mais **bloquée côté AP** faute
de levier. Détail ci-dessous.

---

## 1. VU — la séquence nonce / pnon (EP 0x15) au boot macOS

### 1.1 Où est le trafic pnon, où il n'est pas

- La capture de référence `traces/20261111-113919_snew-reel/sep.log` est **filtrée `eps=0x13`** (en-tête L1 :
  `eps=0x13`). Elle **n'enregistre aucun message pnon** : `grep EP=0x15 TAG` → **0**. L'EP 0x15 y est seulement
  **annoncé** (L9 : `# epname … EP=0x15 NAME='pnon'`). Donc snew-reel ne dit **rien** sur le contenu pnon.
- Le trafic pnon réel n'existe que dans les captures **`eps=all`** (boot macOS complet, OOL ≠ 0x15). Présent et
  **stable à 44 messages EP 0x15** dans ~20 captures (c1, c2a, c2b, c3, c4, c5…c25). Référence détaillée :
  `traces/20261108-010915_c9-boot-ool-persist/sep.log` (L264–L778).

### 1.2 Forme des messages pnon (c9, L264–L293)

- **Ouverture d'un tampon OOL pour l'EP 0x15** via CNTL, juste avant le 1er message pnon
  (c9 L256–L263) : `> EP=0x00 TYPE=0x04 PARAM=0x15 DATA=0x00010000` / `TYPE=0x02 PARAM=0x15` /
  `TYPE=0x05 PARAM=0x15 DATA=0x00008000` / `TYPE=0x03 PARAM=0x15`. **Même mécanique OOL que l'EP 0x13**
  (buffers A/B de 0x8000). → la charge utile pnon transite par OOL, pas par le champ DATA (toujours
  `0x00000000` dans les messages pnon).
- Dialogue pnon : TAG constant `0x01`. Opcodes **AP→SEP** vus : `TYPE=0x20` (×13), `0x30` (×7), `0x28` (×1),
  `0x24` (×1) ; **SEP→AP** : `0x50` (×16), `0x24` (×4), `0x20` (×2). Tous `DATA=0x00000000`.
- **Contenu OOL pnon NON capturé** : dans toutes nos traces `eps=all`, l'OOL est configuré pour l'EP 0x08
  (`ool=on(eps=0x08…)`), jamais pour 0x15. On a donc les **enveloppes** des messages pnon, **pas les octets**
  échangés. (Faille à combler si on veut vraiment instruire pnon.)

### 1.3 Qui initie, et QUAND — l'ordre est le point décisif

Le 1er message pnon est **AP→SEP** (`> EP=0x15 … TYPE=0x20`, c9 L264). C'est donc **l'AP (macOS)** qui ouvre le
dialogue pnon, pas le SEP seul. Mais surtout, **le pnon arrive APRÈS la restauration xART et après l'annonce des
endpoints biométriques**. Chronologie c9 :

| ts (host) | événement | ligne |
|---|---|---|
| 1794096569.19 | début échange xART (EP 0x13), op 0x0e (état fw) | L30 |
| 1794096572.00–572.14 | **restauration xART** : FETCH SEP-xART (op 0x00), UUID (op 0x13), FETCH USER-xART | L99–L105 |
| 1794096572.26 | **SEP annonce `sbio`** (puis skdl/sse/scrd/sks) | L106–L164 |
| 1794096587.07 | **1er message pnon (EP 0x15)** | L264 |

Soit **~15 s entre l'annonce `sbio` et le 1er pnon**. Ce n'est pas propre à c9 : vérifié sur **6 boots** (c9, c1,
c2a, c12, c19, c25), toujours `xart_restore_fetch < sbio_announce < first_pnon`, le pnon tombant **15–16 s
après** `sbio`. Exemples (ts du 1er FETCH op 0x00 / annonce sbio / 1er pnon) :

- c1 : 892.51 / 892.76 / **909.24**
- c12 : …711.01 / …711.34 / **…726.84**
- c25 : …665.76 / …666.02 / **…679.39**

**Conclusion VU (6/6, reproductible) : l'établissement pnon n'est PAS un préalable à la restauration xART ni à
l'annonce des endpoints biométriques. macOS restaure d'abord, fait pnon bien plus tard.**

### 1.4 Ce qui précède la restauration, côté AP

Juste après l'annonce de pnon (le *nom*, pas le trafic) et avant la restauration xART, le SEP émet **spontanément**
`< EP=0x00 TYPE=0x0d` puis `0x29` (c9 L37–L38, « OS actif » / unsolicited — cf. messages.md rang 2). L'« ancrage »
que le SEP a sous la main au moment de restaurer est donc : **l'UUID d'OS** (op 0x13, `apfs-preboot-uuid`) + la
notification CNTL « OS actif » — **pas** un échange pnon.

### 1.5 Côté hv_uart — la piste Image4 (séparée de l'xART)

Dans ~tous les `hv_uart.log` : `[nvram] [write] nonce-seeds with data size 0x203`, et (c17)
`AppleImage4: nonce manager: error reading seeds` / `nonce blob has unexpected length`, plus le driver
`com.apple.driver.AppleMobileApNonce`. Ce sont les traces du **boot-nonce Image4 / personnalisation d'image**
(anti-rollback firmware), pas de la fraîcheur des lockers xART. Cohérent avec l'EP 0x15 = « boot policy ».

---

## 2. VU — ce que la doc interne dit déjà (kext §9, messages.md)

- **kext_sepmanager.md §9** (source: kext, hypothèse) :
  - Le nonce de fraîcheur xART est **généré par le SEP** (xART `nonce_generate`=0x0f / `nonce_read`=0x10 /
    `nonce_invalidate`, 20 o / 160 bits) et/ou par la **ROM** (`AppleSEPBooter::generateROMNonce`, opcode
    `ReportNonceWord`). **L'AP ne choisit pas la valeur.**
  - `generateROMNonce` n'est **pas** dans la séquence de boot automatique — il est appelé **à la demande**
    (user-client `DispatchUserClientGenerateROMNonce`). Message bootstrap AP = **constant** `0x00030100`
    (aucune graine) ; l'AP **lit** un nonce produit par la ROM.
  - **Aucune API `set_nonce` / `writeNonce` / `SeedNonce` / `bootNonce`** côté SEP/XART/Booter : « vide ».
    L'AP n'expose que generate / read / invalidate, **jamais set**.
  - NVRAM vue par AppleSEPManager : `oblit-inprogress`, `auto-boot`, `sep-debug-args` — **aucune** variable
    `boot-nonce`/graine alimentant l'xART. Le `nonce-seeds` NVRAM est **Image4** (personnalisation d'image),
    pas la fraîcheur xART.
- **messages.md** : pnon (0x15) = `02020404` tailles OOL T4=0x10000/T5=0x8000, « boot policy », rôle
  **connu-doc** (doc-asahi), endpoint **annoncé** au SEP-BOOT m1n1 sans macOS (L48, L101). Le *protocole* pnon
  (que font les 44 messages) n'est **pas** documenté/décodé — on n'a que les enveloppes.

---

## 3. VU/INTERPRÉTÉ — comparaison avec notre amorçage m1n1

`m1n1/proxyclient/m1n1/hw/sep.py :: SEP.boot()` (L104–L127) fait **exactement et seulement** :
`GET_STATUS` → `BOOT_TZ0` → attend `STATUS_BOOT_TZ0_DONE` → `GET_STATUS` → `BOOT_IMG4` + `SET_SHMEM` → attend
`STATUS_BOOT_IMG4_DONE`. Sur EP 0xFF/0xFE uniquement. **Aucune** référence `pnon`/`nonce`/`0x15` dans
`m1n1/proxyclient/` (grep : rien de pertinent). `pending/sep_boot.sh` reproduit cette séquence et rien d'autre.

Ce que **macOS fait et que m1n1 ne fait pas**, dans l'ordre temporel :
1. L'échange **xART** (EP 0x13) de restauration (FETCH op 0x00 ×2, UUID op 0x13) — *m1n1 l'atteint aussi* dès
   qu'on lui répond (c'est tout l'objet de `sep_xart_replay.sh` ; `sbio` a été annoncé lors des essais).
2. L'**échange pnon** (EP 0x15, 44 messages, OOL) — *m1n1 ne le fait jamais*, et macOS lui-même ne le fait
   **qu'après** la restauration et l'annonce `sbio` (§1.3).
3. Le **boot-nonce Image4** (nonce-seeds NVRAM / AppleImage4) — relève d'iBoot/Image4, hors de notre amorçage.

INTERPRÉTÉ (hypothèse) : **la divergence observée à la voie C** (le SEP demande un SAVE op 0x01 au lieu de
continuer les FETCH de gigalockers) **ne s'explique pas par un « pnon manquant avant la restauration »**, puisque
macOS restaure sans pnon préalable. Elle s'explique mieux par le §9 : le coffre rejoué a été scellé sous un
**nonce de fraîcheur généré par le SEP** (ROM/xART, 20 o) à un **autre** boot ; le SEP courant a un autre nonce
interne ; il juge l'état « non courant » et re-scelle. L'AP n'ayant **aucun levier** pour fixer/reproduire ce
nonce, l'étape que « nous ne faisons pas » n'est **pas** une étape AP reproductible — c'est une valeur **interne
au SEP**.

---

## 4. CONCLUSION — la piste nonce est-elle plausible ou bloquée ?

**Sur la forme littérale de B′ (« établir le nonce AVANT pour que la puce RESTAURE ») : contredite par les
traces.** 6/6 boots macOS montrent restauration + annonce `sbio`/`sks` **avant** tout trafic pnon. Établir un
contexte pnon n'est donc pas la clé qui *débloque la restauration*. (Statut : observation reproductible ;
l'interprétation « donc pnon n'influence pas la décision de re-sceller plus tard » reste **hypothèse** — voir
réserve.)

**Sur l'idée générale (le re-scellement vient d'un nonce de fraîcheur) : cohérente mais BLOQUÉE côté AP.**
Le kext §9 établit (en hypothèse source: kext) qu'il n'existe **aucune API AP** pour semer/fixer le nonce xART :
il est produit par le SEP (ROM, 20 o) ; l'AP ne peut que *déclencher/lire/invalider*. Donc « reproduire
l'établissement du nonce pour que la puce restaure » **n'a pas de point d'entrée AP** → pour la partie
« nonce xART », la piste est **bloquée** (pas d'étape reproductible identifiée).

**Réserves honnêtes (ce qui n'est PAS tranché) :**
1. **Contenu pnon jamais capturé.** On a 44 enveloppes EP 0x15 mais zéro octet de leur OOL (OOL toujours réglé
   sur 0x08). On ne peut donc **pas exclure** que le dialogue pnon transmette au SEP une information qui
   influence une décision *ultérieure* de fraîcheur. Ce serait à instrumenter (capture OOL `eps=0x15`) avant de
   clore — mais rejouer pnon serait une **écriture EP 0x15 = ligne rouge** (boot policy), donc `pending/` +
   Albert, jamais l'agent.
2. **ROM interne non observable.** §9 prouve l'absence de levier *côté AP* ; ça n'exclut pas que la ROM du SEP
   lise une graine dans son **propre** stockage effaçable (non visible d'ici). B′ pourrait survivre sous cette
   forme-là, mais alors elle dépend d'un **secret hors de portée** (ROM/stockage interne SEP) → non reproductible.
3. **Image4 vs xART non séparés expérimentalement.** Le `nonce-seeds` NVRAM (Image4) et le nonce xART sont
   *documentés comme distincts* (§9), mais on ne l'a pas **prouvé par expérience**.

**Action utile suivante (si on veut vraiment fermer la piste), à proposer, pas à faire :**
- Capturer une fois un boot macOS avec **OOL sur l'EP 0x15** (`SEP_OOL_EPS=0x15`) pour **voir** les octets pnon
  (lecture seule, aucune écriture SEP) — c'est la seule inconnue factuelle qui reste côté AP. À demander au
  **tracer**.
- Tant que cette capture n'existe pas, et vu §9, la piste « établir le bon contexte de nonce côté AP pour que la
  puce restaure » est classée **BLOQUÉE côté AP (hypothèse)**, et le rejeu pur reste expliqué par un nonce de
  fraîcheur SEP non reproductible — à ne trancher définitivement que par écriture (Albert + image disque).

---

## Sources

- `traces/20261108-010915_c9-boot-ool-persist/sep.log` (L30–L164 restauration+annonces ; L256–L293 pnon).
- `traces/20261111-113919_snew-reel/sep.log` (L1 en-tête `eps=0x13` ; L9 annonce pnon ; 0 trafic pnon).
- Boots recoupés : c1, c2a, c12, c19, c25 (`sep.log`, ordre xART→sbio→pnon).
- `traces/*/hv_uart.log` (`nonce-seeds` NVRAM ; `AppleImage4: nonce manager` ; `AppleMobileApNonce`).
- `docs/kext_sepmanager.md` §8 (dispatch xART) et §9 (nonce : generateROMNonce/ReportNonceWord, nonce_*,
  absence de set_nonce, NVRAM) — source: kext, macOS 13.5.
- `docs/messages.md` L48/L101/rang 2 (pnon annoncé, boot policy, SEP-BOOT 7/12 EP).
- `m1n1/proxyclient/m1n1/hw/sep.py` L104–L127 (`boot()` : GET_STATUS/BOOT_TZ0/BOOT_IMG4/SET_SHMEM, pas de pnon).
- `pending/sep_boot.sh` (séquence d'amorçage m1n1).
