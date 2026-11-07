# Table des messages SEP

Format d'un message (doc Asahi) : bits 0-7 endpoint, 8-15 tag, 16-23 type, 24-31 param, 32-63 data.
Direction : `>` AP → SEP, `<` SEP → AP.

Statuts : `connu-doc` (doc publique Asahi), `hypothèse`, `vérifié` (confirmé par expérience).
Source : `doc-asahi`, `trace:<dossier>`, `kext` (phase 2 uniquement).

## Endpoints (point de départ : doc publique Asahi)

| EP | Nom | Rôle | Statut |
|----|-----|------|--------|
| 0x00 | CNTL | propriétés des endpoints | connu-doc |
| 0x08 | SBIO | authentification biométrique (Touch ID) | connu-doc |
| 0x0a | SCRD | probablement gestion des credentials utilisateur | connu-doc |
| 0x0c | sse | lié NFC / Apple Pay | connu-doc |
| 0x0e | HDCP | protection HDCP | connu-doc |
| 0x10 | xars | setup xART, startup/shutdown | connu-doc |
| 0x12 | SKS | Secure Key Store (chiffrement, clés) | connu-doc |
| 0x13 | xART manager | xARTs, gigalockers, keybags — requis pour SKS | connu-doc |
| 0x14 | hibe | hibernation | connu-doc |
| 0x15 | pnon | boot policy | connu-doc |
| 0x17 | skdl | kext deny list | connu-doc |
| 0x18 | stac | trusted accessory (Touch ID clavier externe ?) | connu-doc |
| 0xFD | debug | découverte : liste des endpoints + tailles OOL | connu-doc |
| 0xFE | Boot254 | boot SEPOS avec IMG4 | connu-doc |
| 0xFF | Boot255 | région mémoire protégée prête | connu-doc |

## Messages

| EP | Dir | Type | Param | Data | Rôle supposé | Statut | Source | Date |
|----|-----|------|-------|------|--------------|--------|--------|------|
| 0x13 | > | 0x0 | 0x0 | 0x100 | fetch d'un locker (gigalocker init) | connu-doc | doc-asahi | — |
| 0x13 | < | 0x5 | 0x10 | — | succès fetch/unwrap locker | connu-doc | doc-asahi | — |
| 0x13 | < | 0x7 | 0x10 | — | erreur (ex. locker utilisateur introuvable) | connu-doc | doc-asahi | — |
| 0x18 | > / < | 0xf | 0x0 | 0x0 | ping / pong | connu-doc | doc-asahi | — |
