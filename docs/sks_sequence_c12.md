# Séquence SKS/skdl/scrd au boot (c12) — ce qui GATE sbio sur un boot chaîné

Extrait par l'orchestrateur (`sep-touchid-c9`) de `traces/20261108-032454_c12-boot-ho/sep.log` (boot macOS **chaîné**,
Touch ID enrôlé, sbio fonctionnel). **But** : préparer le futur `pending/` SKS (classe neuve → go d'Albert).
**Pourquoi c'est critique** : sur un boot **chaîné** (état xART servi, pas re-scellé), **sbio ne répond au 0x73 qu'APRÈS**
que toute la pile keystore (skdl 0x17, sks 0x12, scrd 0x0a) a été ouverte+amorcée. En **seal frais**, rien à
déverrouiller → sbio répond direct. ⇒ **enrôlement persistant = implémenter cette séquence.** (cf. `xart_native_policy.md` Track B,
logs `logs/20261122-195701_j3d-chained-early/`). Statut : **VU (trace macOS), hypothèse pour le natif** ; le **contenu DER
des OOL n'est PAS capturé** (0x12 absent de `full_types` du tracer) — seules les formes/tailles/ordre/TAG sont ici.

## 1. Ordre global (ce qui précède le 0x73)
Après l'annonce `0x1d` de sbio (et l'ouverture **tôt** du CNTL 0x08, cf. Track B), macOS, AVANT le `> 0x08 TYPE 0x73` (@737.73) :
1. **ouvre skdl (0x17)** par CNTL (PARAM=0x17, A=B=0x4000, IOVA 0x64000/0x6c000) ; puis skdl `> TYPE 0x01` / `> TYPE 0x06` (TAG 0xfc, DATA=0).
2. **ouvre sks (0x12)** par CNTL (PARAM=0x12, **A=B=0x8000**, IOVA 0x74000/0x80000) ; puis la **séquence RPC sks** (§2).
3. **ouvre scrd (0x0a)** par CNTL (PARAM=0x0a, A=B=0x4000) ; puis scrd ops (§3).
4. sks atteint ~TYPE 0x17/0x18/0x19 + scrd → **ALORS** `> 0x08 TYPE 0x73` et sbio répond (TAG 0x04 puis TAG 0xfc TYPE 0x73).

## 2. SKS (EP 0x12) — motif RPC (AppleKeyStore, cf. kext_sepmanager.md §14b/§15)
- Requête `>` : `TAG=<t>`, **`TYPE`=opcode SÉQUENTIEL** (0x01, 0x02, 0x03, … il INCRÉMENTE à chaque appel), `PARAM=0x00`,
  `DATA = <longueur_req> << 16` (ex. `0x00640000` = requête 0x64 o). Le DER est dans l'**OOL A** (pas dans le mot).
- Réponse `<` : **`TAG = TAG_req | 0x80`** (0x4d→0xcd, 0x19→0x99, 0x48→0xc8, 0x04→0x84…), même `TYPE`, `PARAM`=statut
  (0x00=OK ; 0xff/0xfe/0xfd/0xfb = codes/fin/pas-de-données), `DATA = <longueur_resp> << 16`. DER de réponse dans l'**OOL B**.
- Les ~25 premiers opcodes (0x01→0x19) sont le **bring-up du keystore** qui gate sbio. La séquence CONTINUE après le 0x73
  (0x1a→0x5a+ : usage courant, re-keying, polling `TYPE 0x19/0x04` avec resp PARAM=0xfd DATA=0).
- Ordre + tailles VU (début, `>` req_len / `<` resp_len, en octets, ×0x100) :
  `01`(64/5c) `02`(470/58) `03`(8c/14c) `05`(90/b8) `04`(60/—ff) `06`(94/b4) `07`(1dc/110) `08`(230/110)
  `09`(240/a0) `0a`(230/110) `0b`(244/60) `0c`(b8/—fe) `0d`(b8/ec) `0e`(94/b4) `0f`(1dc/110) `10`(230/110)
  `11`(1dc/110) `12`(6c/—fd) `13`(94/60) `14`(90/a0) `15`(80/60) `16`(80/60) `17`(94/b4) `18`(1c0/—fb) `19`(68/—fd).
  (tailles = `DATA>>16` ; `—xx` = resp PARAM de statut avec DATA=0.) Détail complet des 0x1a→0x5a : relire le sep.log.

## 3. skdl (0x17) et scrd (0x0a)
- **skdl 0x17** : seulement `> TYPE 0x01` → `< 0x01`, `> TYPE 0x06` → `< 0x06` (TAG 0xfc, DATA=0). Ping d'init.
- **scrd 0x0a** (TAG 0x01) : `TYPE 0x08/0x09/0x0c/0x17/0x18/0x42` → réponses `TYPE 0x00/0x01/0x0f/0x15/0xb0` (petits, DATA=0).

## 4. Pour préparer le pending/ SKS
- Le transport (ouvrir 0x12 taille 0x8000, mot `TYPE` séquentiel + len<<16, DER en OOL A/B, resp TAG|0x80) = **codable**.
- Le **contenu DER** n'est PAS dans nos traces (0x12 hors `full_types`) et est **lié au keybag/session** → à reverser via
  `AppleKeyStore::sep_deliver_msg` (kext, `kext_sepmanager.md §15`) OU à re-tracer avec `full_types=0x12`. **C'est le vrai
  « extremely involved ».** Classe neuve (écriture SEP 0x12) → `pending/` + **go d'Albert**.
