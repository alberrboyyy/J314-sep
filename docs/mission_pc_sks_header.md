# Mission session PC (c9) — en-tête OOL de l'EP 0x12 (SKS) et `get_capabilities`, octet près

Demandée par Albert le 2026-11-23 (session ALARM). À faire **sur le PC**, rien ne touche au Mac ni au SEP.
Règles : CLAUDE.md (protocole uniquement, aucune clé ni secret, aucune copie de code Apple dans `driver/`,
`source: kext` / `source: userland`).

## Pourquoi
- Sous Linux natif, le boot chaîné et l'init capteur complète marchent (J7b, J8 : vérifiés n=2, journal 2026-11-23).
- L'enrôlement (sbio 0x03) exige un jeton (AuthToken ou CredentialSet) produit après une authentification par code,
  adossée au keybag (`docs/biometrickit_protocol.md`). Il faut donc parler à SKS (EP 0x12).
- `docs/sks_protocol.md` (décompil 27.2.1 côté ALARM) a établi : noms du bring-up, déverrouillage 0x41 puis 0x18, DER
  des paramètres (racine SET 0x31, paires triées par clé, `o` = UTF8String), chemin du jeton (ACM →
  `authentication_token_create`).
- **Manque** : l'en-tête du tampon OOL A/B de l'EP 0x12 et les octets exacts de `get_capabilities` (TAG 0x4d, 0x64 o
  dans c12). Côté ALARM, ce point n'a pas pu être désassemblé. Un éventuel `docs/sks_ipc_negotiation.md` existe peut-être
  déjà côté PC : le pousser s'il existe.

## Matériel
- `macos/kernel.macho` (13.5) déjà sur le PC, et/ou l'IPSW public 27.2.1 (`UniversalMac_27.2.1_26B131_Restore.ipsw`,
  MacBookPro18,4 ; la version installée sur le Mac).
- Traces : c1/c12 (`traces/*/sep.log`, EP 0x12 : mots seulement, OOL 0x12 jamais capturé).

## Questions
1. Disposition de l'en-tête OOL A (requête) et B (réponse) de l'EP 0x12 : champs, tailles, ordre d'octets.
2. `get_capabilities` (TAG 0x4d) : contenu complet des 0x64 o ; pour chaque champ variable (horodatage, pid, cdhash,
   SHA tronqué…), sa source exacte et sur quelles données porte le SHA.
3. Lesquels de ces champs le SEP vérifie-t-il (si c'est lisible côté AP) ; un hôte non macOS peut-il les remplir.
4. Réponse attendue (TAG 0xcd) : forme et sens.

## Livrable
Compléter `docs/sks_protocol.md` (section en-tête OOL + get_capabilities, VU / DÉDUIT / INCONNU), entrée dans
`docs/journal.md`, push. La session ALARM préparera ensuite l'expérience « un seul get_capabilities » dans `pending/`
(classe neuve : go d'Albert).
