# Politique native xART (EP 0x13) pour sep_native, à implémenter (J4, étape 7)

Source : session PC (orchestration), 2026-11-22. Tirée de `pending/sep_native_persist.sh`, éprouvé sur matériel
(n=4). Elle **remplace** `handler_0x13.md` §1 sur la réponse ABSENT. Le SEP envoie `<`, l'AP répond `>` avec le même TAG.

| `<` TYPE | sens | réponse AP native |
|---|---|---|
| 0x0e | état fw-boot | ACK, A vide, `DATA=0x100` |
| 0x13 | UUID d'OS | 16 o d'UUID écrits en A (UUID Linux ; à observer, cf. ouverts) |
| 0x00 | FETCH maître (sélecteur 0/1) | en store → SERVIR : A = 0x11 zéros + charge, longueur 0x11+len ; sinon ABSENT = longueur 0x11 (préfixe seul) |
| 0x05 | FETCH locker (UUID en B) | en store → servir ; sinon ABSENT = longueur 0 |
| 0x07 | notification « absent » du SEP | ACK (le SEP l'émet ; l'AP ne l'émet pas) |
| 0x1d | annonce d'EP | ACK `> TYPE 0x16 DATA=(DATA & 0xFFFFFF00)` |
| 0x01 | SAVE xART maître | ⚠️ ÉCRITURE. Lire B (longueur `PARAM \| DATA0<<8`), stocker par type (1=USER, 2=SEP), ACK `DATA & 0xFFFFFF00` |
| 0x06 | SAVE locker | ⚠️ ÉCRITURE. Lire B, stocker (clé = UUID), ACK |

- Longueur : `declen = (PARAM & 0xFF) | ((DATA0 & 0xFF) << 8)`. Pour SERVIR, recalculer depuis la taille réelle du
  blob, ne jamais rejouer la valeur capturée. `DATA[1]` = drapeau à ré-émettre depuis la requête. Le CRC est dans le
  blob (+0x16), pas dans le message.
- `MAX_SAVES = 48` : au-delà, sans stabilisation → Halt.
- Store chargé au boot et réécrit à chaque SAVE (`master_1.bin` / `master_2.bin`, lockers par UUID). En espace
  utilisateur (démon), pas dans le noyau.
- CNTL EP 0x00 bénins connus : spontanés 0x0d, 0x29, 0x10 (vus en J2), et `< 0x11 → > 0x12`.

## Ouverts, à observer au premier run (ne rien supposer)
1. L'UUID d'OS à renvoyer.
2. Le u16 à +0x1a de l'en-tête de slot (rôle inconnu, mis à 0) : à confirmer avant un vrai SAVE.
3. Dual-boot : re-sceller le MASTER (0x01) désynchronise macOS. À observer : le SEP accepte-t-il un master Linux
   distinct, ou n'a-t-il qu'un master partagé ?

## Gate
`allow_xart=1 allow_xart_save_ack=1` = classe d'écriture neuve → **go d'Albert**. C'est l'étape où l'enrôlement
Touch ID macOS est invalidé (macOS déclaré sacrifiable par Albert le 2026-11-22). Après le xART scellé, `sbio`
(EP 0x08) devrait s'annoncer (J3).

## Vérification orchestrateur (2026-11-22, `sep-touchid-c9`) — formes EXACTES + GO protocole
Relu octet-près contre `pending/sep_native_persist.sh` (run n=4). **GO protocole** pour J4 ; appliquer ces précisions :

- ⚠️ **Réponse FETCH = TYPE `0x00` (RESP_DONE, persist l.78) pour les DEUX** (maître 0x00 ET locker 0x05).
  On ne renvoie **PAS** TYPE 0x05 pour un FETCH locker → **TYPE 0x00**. (persist l.238/240)
- Encodage (persist l.226-240) : `sel = (DATA >> 8) & 0xFF`.
  - **Maître** : `mtype = 2 if (sel & 1) else 1` (**2 = SEP, 1 = USER**).
    - ABSENT → A = `0x11` zéros ; `TYPE 0x00, PARAM = 0x11, DATA = sel<<8`.
    - SERVI → A = `0x11` zéros + charge (`ln = 0x11+len`) ; `TYPE 0x00, PARAM = ln&0xFF, DATA = ((ln>>8)&0xFF) | (sel<<8)`.
  - **Locker** : UUID lu en B (16 o). ABSENT → A vide ; `TYPE 0x00, PARAM = 0, DATA = sel<<8`. SERVI → idem maître (sans le préfixe 0x11).
- **CNTL (EP 0)** : `SECMODE` = `TYPE 0x14, DATA 0, PARAM 0x00` (⚠️ pas 0x13) ; puis 4 ouvertures `PARAM 0x13` dans l'ordre
  `0x04`(A taille), `0x02`(A IOVA>>12), `0x05`(B taille), `0x03`(B IOVA>>12) ; ack = `TYPE 0x01` même TAG (≤5 s) ; TAG 1..8 ;
  **A = B = 0x8000**. (persist l.207-216)
- Annonce `0x1d` → `TYPE 0x16` (RESP_ANNOUNCE) `DATA & 0xFFFFFF00`. SAVE `0x01`/`0x06` → ACK `DATA & 0xFFFFFF00`.
  `<0x11 → >0x12` (EP 0). fw-boot `0x0e` → `DATA 0x100`.
- **UUID d'OS CONFIRMÉ** = `4c494e5558000…0` = la valeur du run éprouvé (`OS_UUID_MODE=fixed`, `LINUX_OS_UUID`,
  persist l.52-53), celle qui a scellé l'état frais (n=4). (« Bon » UUID théoriquement ouvert ; empiriquement celle-ci marche.)
- **Délai 0x0e** : large (anneau RX bufferise ; marge énorme vs harnais USB). Répondre dès que sepd lit.
- Après le run : renvoyer le journal brut à `sep-touchid-c9` → vérifié/hypothèse (surtout : `sbio`+`sks` s'annoncent-ils
  après le SAVE ?) + MAJ `handoff.md`.

## Résultat J3 (2026-11-22) — chaînage + ouverture sbio
- **CHAÎNAGE cross-reboot = VÉRIFIÉ (n=1)** : au boot suivant, servir le master stocké (437o = 0x11 + 420) → le SEP
  l'**accepte sans re-sceller** (0 SAVE, annonces immédiates). ⇒ persistance de l'état (et donc de l'enrôlement) viable.
  Réserve : n=1, à reproduire ; les **lockers** doivent aussi être servis (voir ci-dessous).
- **Keying des lockers RÉSOLU** : la clé d'un locker = les **16 premiers octets de B au SAVE** (= l'UUID vu au FETCH 0x05).
  Donc au SAVE 0x06, indexer par `B[:16]` ; au FETCH 0x05, chercher par l'UUID lu en B et **servir le blob verbatim**
  (comme `serve_master` mais **sans** le préfixe 0x11 ; `TYPE 0x00, PARAM=ln&0xFF, DATA=((ln>>8)&0xFF)|(sel<<8)`).
- **Ouverture sbio (0x08) après chaînage** : J3 + J3bis (lockers servis) → open 0x08 NON acké (n=2). L'hypothèse
  « lockers manquants » est **réfutée**. Mais sbio **ouvre bien après un SEAL FRAIS** (J3c, vérifié). ⇒ tension
  persistance↔armement.
- **TRACK B — FIX du chaînage (comparaison c12, boot macOS CHAÎNÉ où sbio marche)** : la différence = **le TIMING de
  l'ouverture 0x08**. macOS ouvre le CNTL de 0x08 **~35 ms APRÈS l'annonce `0x1d 'sbio'`, ENTRELACÉ avec le service
  xART qui continue** (FETCH lockers après l'open), PAS après le « calme ». Nos essais ouvraient TARD (après calme) →
  refusés. ⇒ **au chaînage : dès réception du `0x1d 'sbio'`, ack 0x16 PUIS ouvrir tout de suite les 4 CNTL de 0x08**
  (A=B=0x4000, TYPE 0x04/0x02/0x05/0x03 PARAM 0x08), en continuant à servir les FETCH restants. Secondaire : macOS sert
  **les 2 masters (t2 ET t1) + ~15 lockers** ; servir tout le stocké. Source : `traces/20261108-032454_c12-boot-ho/sep.log`
  (0x1d sbio @711.336 ; open 0x08 @711.371 ; 0x73 @737.73). Statut : **hypothèse (à tester au prochain run chaîné)**.
