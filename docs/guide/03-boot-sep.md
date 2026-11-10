# 3. Séquence de boot du SEP

Le boot du SEP s'observe sur les endpoints de ROM (0xFF, `Boot255`), de boot/mémoire partagée
(0xFE, `Boot254`) et de découverte (0xFD). Les types ci-dessous proviennent du code public m1n1
(`BootRomMsg` dans `hw/sep.py` / `src/sep.c`) ; voir `docs/messages.md` § « Boot ROM ».

## Séquence ROM (EP 0xFF / 0xFE)

Observée sous macOS (C1) et reproduite sous m1n1 seul (2026-11-09) :

1. `> 0xFF TYPE 2` **GET_STATUS** → `< 0x66` STATUS_OK.
2. `> 0xFF TYPE 5` **BOOT_TZ0** → `< 0x69` (noyau : « SEP accepted Tz0 »), puis `< 0xD2`.
3. `> 0xFF TYPE 6` **BOOT_IMG4** (DATA = IOVA du firmware ≫ 12) → `< 0x6A` (« SEP accepted IMG4 »).
4. `> 0xFE SET_SHMEM` : installe la mémoire partagée du SEP. m1n1 emploie `TYPE 0x18` ;
   macOS emploie `TYPE 0x1c` (DATA = IOVA ≫ 12). **Hypothèse** sur l'équivalence des deux types.

`GETRAND` (`> 0xFF TYPE 16`) renvoie 4 octets aléatoires de la ROM : **Vérifié** sans macOS
(trace `20261109-212150_sep_getrand`, 4 octets obtenus, aucun plantage).

En tête de C1, deux messages `> 0xFF TYPE 0x1b` / `< 0x7f` restent **inexpliqués** (absents de
m1n1). **Hypothèse** : rôle inconnu.

## Annonce des endpoints (EP 0xFD)

Après le boot de SEPOS, le SEP annonce ses endpoints par des messages `< EP=0xFD TYPE=0x00`,
dont la DATA contient le nom ASCII de l'endpoint (ex. `sbio`, `xarm`). Le `TYPE 0x01` associé
porte quatre octets interprétés comme des tailles de buffers OOL. **Hypothèse** (2 cas
discriminants) : voir `docs/messages.md` § Endpoints. **Correction vérifiée** : l'ordre
d'annonce n'est **pas** fixe (trois ordres observés sur huit boots) ; tout code doit chercher
les endpoints par nom, pas par rang.

## Boot du SEP sous m1n1 seul, sans macOS

Trace SEP-BOOT (`20261109-221029_sep_boot`), via `pending/sep_boot.sh` (code public m1n1,
DART `t6000`) : le SEP démarre (« BOOT OK », les quatre réponses attendues reçues).

**Vérifié (fait)** : sur les douze endpoints, **sept sont annoncés** — `cntl`, `hdcp`, `xars`,
`xarm`, `hibe`, `pnon`, `stac`. **Cinq sont absents** — `sbio`, `sks`, `scrd`, `sse`, `skdl`.

**Hypothèse** : les cinq absents ne sont annoncés qu'après l'échange xART mené par l'AP ; sous
m1n1, personne ne tient cet échange, d'où 7/12. Cette dépendance est détaillée au
[chapitre 5](05-xart.md). Confirmé côté macOS : dans 19 boots, les cinq (dont `sbio`) arrivent
quelques secondes après la première réponse de l'AP sur l'endpoint xART.

## Incident à noter

Après l'unique boot du SEP par m1n1, macOS a exigé une reconnexion au compte Apple au
redémarrage suivant. **Cause non établie** (un seul cas ; ~20 captures sous hyperviseur
antérieures n'avaient rien provoqué). Décision en vigueur : pas de nouveau boot du SEP par
m1n1 sans décision explicite d'Albert. Voir `docs/messages.md` et [chapitre 10](10-regles-et-risques.md).
