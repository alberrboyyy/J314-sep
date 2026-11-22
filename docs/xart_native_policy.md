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
