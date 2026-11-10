# 4. Carte des endpoints

Les douze endpoints applicatifs du SEP, tels qu'annoncés dans C1 et confirmés identiques à la
liste de la doc Asahi (aucun en plus, aucun en moins). Le rôle est `connu-doc` (documentation
publique Asahi) sauf mention ; la correspondance nom → numéro est **Vérifiée** par recoupement
avec le log noyau macOS. Table source : `docs/messages.md` § Endpoints.

| EP | Nom | Rôle | Annoncé sans macOS (m1n1 seul) ? |
|------|--------|------------------------------------------|---|
| 0x00 | `cntl` | contrôle : propriétés et activation des endpoints, configuration des buffers OOL | oui |
| 0x08 | `sbio` | authentification biométrique (Touch ID) | **non** |
| 0x0a | `scrd` | credentials utilisateur (probable) | **non** |
| 0x0c | `sse`  | NFC / Apple Pay | **non** |
| 0x0e | `hdcp` | protection de contenu (HDCP) | oui |
| 0x10 | `xars` | mise en place xART | oui |
| 0x12 | `sks`  | Secure Key Store (keybag, [chapitre 7](07-sks-keystore.md)) | **non** |
| 0x13 | `xarm` | xART manager (échange du coffre, [chapitre 5](05-xart.md)) | oui |
| 0x14 | `hibe` | hibernation | oui |
| 0x15 | `pnon` | boot policy | oui |
| 0x17 | `skdl` | kext deny list | **non** |
| 0x18 | `stac` | trusted accessory | oui |

Endpoints de service : `0xFD` découverte (annonce des noms et tailles), `0xFE` boot/mémoire
partagée, `0xFF` ROM de boot ([chapitre 3](03-boot-sep.md)).

## Lecture transverse

Les sept endpoints présents sous m1n1 seul sont ceux annoncés **avant** tout échange AP → SEP
sur `xarm` (0x13). Les cinq absents — dont `sbio`, nécessaire à Touch ID — n'apparaissent
qu'**après** cet échange. C'est le blocage central du projet, traité au [chapitre 5](05-xart.md).

`cntl` (0x00) émet aussi des messages spontanés en début de boot (`< TYPE 0x0d`, `0x29`
« unsolicited », `0x10`) dont le rôle précis est **Hypothèse** ; et une requête `TYPE 0x14`
(SECMODE, réponse DATA=3) interprétée comme un mode de sécurité (**Hypothèse**, une seule valeur observée).

Les rôles applicatifs fins de `sbio` et `sks` sont détaillés aux chapitres 6 et 7 ; ceux de
`scrd`, `sse`, `hdcp`, `skdl`, `stac`, `hibe` ne sont pas étudiés au-delà de leur nom et de leur
présence. `hibe` est présent sans xART, ce qui le rendrait plus accessible que `sbio` ; mais
aucune activité n'a jamais été observée dessus (voir `docs/power_sep_options.md`).
