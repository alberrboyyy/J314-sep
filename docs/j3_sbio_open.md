# J3 : ouvrir sbio (EP 0x08) + poignée 0x73, protocole vérifié (c9, 2026-11-22)

Source : `pending/sep_native_sbio.sh`, éprouvé sous m1n1 (0x73 vérifié n=3). But de J3 : **prouver que sbio est
vivant**, rien d'autre.

1. **Ouverture CNTL de 0x08**. Pas de 2e SECMODE : il est global, déjà envoyé pour 0x13.
   - A8 = B8 = **0x4000** octets, IOVA distinctes de celles du xART (l'allocateur choisit).
   - 4 messages CNTL avec PARAM=0x08, dans cet ordre : `0x04` (taille A8 = 0x4000), `0x02` (IOVA A8 >> 12),
     `0x05` (taille B8 = 0x4000), `0x03` (IOVA B8 >> 12). Chacun attend son ack TYPE 0x01, même TAG, 5 s max.
   - Le stream 15 n'est pas nécessaire (écarté par E1) : le stream 0 suffit.
2. **Poignée 0x73**. C'est un « bonjour » sans doigt, rejouable, pas encore lié à la session.
   - Charge A8 = le gt_packet 0x73 capturé, `traces/20261108-032454_c12-boot-ho/sep.log.ool/000300_08_A.bin`.
     Avant d'envoyer, vérifier `+0x00 == 1` et `+0x14 == 0x73`, sinon STOP.
   - Envoyer `> EP=0x08 TAG=0xfc TYPE=0x73 PARAM=0 DATA=0`, écouter EP 0x08 pendant environ 6 s, dumper B8.
   - **VIVANT** si `B8[0x00] == 1` et `B8[0x14] == 0x73`, ou si un message `EP=0x08 TAG=0xfc TYPE=0x73` (ou TAG=0x04)
     arrive. Sinon MUET : on diagnostique, on ne force pas.
3. **GT**. TAG `0xfc` = commande, `0xfe` = le SEP demande la suite, `0xfd` = continuation. TYPE = opcode,
   DATA = compteur << 16. OOL = gt_packet_t (en-tête 0x1c, version à +0x00, opcode à +0x14, fragments de 0x3fe4).
   Le 0x73 tient en un seul paquet.
4. **Notifications 0x08 non sollicitées** (TAG 0x01 = lockState, TAG 0x02-0x04) : les remonter dans le log, sans Halt.

Pièges : n'enchaîner ni 0x17, ni 0x15, ni 0x16 (c'est J5, lié à la session et au SPI du capteur). Le premier run de ce
chemin dans sep_native demande le go d'Albert.
## Store xART au prochain boot : verdicts de c9 (2026-11-22)
- (a) Servir le master stocké : **hypothèse**, jamais vérifiée. C'est le pari du chaînage d'un reboot à l'autre. Si
  le SEP juge le master périmé (compteur scellé avancé), il re-scelle.
- (b) Store neuf à chaque boot : **vérifié** (c'est ce qu'a fait J4), mais c'est une impasse. Le compteur avance de
  12 à chaque boot (usure inconnue), et surtout l'enrôlement est perdu à chaque boot.
- (c) Servir un locker (FETCH 0x05) : même forme que le master, **sans** le préfixe de 0x11 octets (forme vérifiée).
  L'indexation par UUID (offset de l'UUID dans le blob du SAVE) reste une **hypothèse**.
- **Décision pour le run J3 : servir `/var/lib/sepd` (option a)**, avec `allow_xart_save_ack=1` pour encaisser un
  éventuel re-scellement. Lecture du résultat : s'il n'y a pas de nouvelle rafale de SAVE, le chaînage marche et la
  persistance est viable ; s'il y a environ 12 SAVE, le master est rejeté (mur du dual-boot).
