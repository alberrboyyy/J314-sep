#!/usr/bin/env bash
# BUT : J6 = préparer le PREMIER enrôlement puis le premier match Touch ID en Linux natif. CE SCRIPT NE LANCE RIEN
#       D'ENRÔLEMENT NI DE MATCH : il est un GARDE-FOU. L'analyse protocole (docs/j6_enroll_match_protocol.md)
#       montre que J6 est BLOQUÉ par trois murs non résolubles en lecture seule :
#         1. D2 : notre état natif n'a ni keybag ni gabarit (EP 0x12 SKS jamais ouvert) ; le 1er match suppose un
#            gabarit (enrôlement), et l'enrôlement et/ou le verdict 0x09 peuvent exiger le keybag (SEP-refus = non
#            tranché) ;
#         2. 0x03 commandStartEnroll porte un enroll_indata_v2_t de 68 octets de CONTENU INCONNU (biometrickitd) ;
#         3. 0x06 (0xa7 o, nonce par verrouillage) de CONTENU INCONNU, lié au keybag.
#       Donc on ne peut PAS émettre un enroll/match fidèle. Ce script refuse de tourner et imprime l'expérience la
#       moins chère qui tranche (E-enroll-start, §6 du doc), qui demande d'abord le « go » d'Albert ET un code dédié
#       qui n'existe pas encore (le noyau refuse allow_sbio_bio). Rien n'est envoyé au SEP.
# ENDPOINTS TOUCHÉS : AUCUN (le script s'arrête avant tout chargement de module). À terme, l'expérience E-enroll-start
#       toucherait l'EP 0x08 avec UN 0x03 (payload best-effort documenté), sans doigt, sans image, fail-closed.
# RISQUE : nul tel quel (ne lance rien). L'expérience E-enroll-start, quand elle sera codée et validée : classe
#       NEUVE (entrée en mode enrôlement), 1er run = « go » d'Albert ; power-cycle = Albert.
# RÉSULTAT ATTENDU : impression du blocage et de l'expérience à valider ; code de sortie 2 (non exécutable).
# PRÉPARÉ PAR : agent driver (session ALARM), 2026-11-22. JAMAIS LANCÉ (et non lançable en l'état).
# NOTE 2026-11-22 : l'expérience E-enroll-start est désormais codée à part (variante avec doigt) :
#       pending/j6a_enroll_start.sh (noyau allow_sbio_bio=1). Ce garde-fou reste non exécutable (enroll/match complets).
set -euo pipefail
cat <<'TXT'
J6 (enrôlement + match Touch ID natif) est BLOQUÉ — voir docs/j6_enroll_match_protocol.md.

Protocole établi :
  - MATCH (séquence fil VU C20/C11/C8/C6, verdict 0x09 VÉRIFIÉ) :
      doigt -> IRQ gpio195 -> lecture image SPI 0x7200 -> 0x23 0x06 0x65(image) 0x07 [0x1e] 0x09(verdict)
      0x1f 0x22 0x0b ; <03 -> 0x21 ; 0x70 (HRLB) ; après succès le gabarit s'adapte (0x6c export a persister).
      Verdict 0x09 (match_info_t 0xca2) : +0x00 = 0x1f5 (uid 501) / 0xffffffff (refus) ; +0x04 = id gabarit.
  - ENROLL (source: kext uniquement, AUCUNE trace) :
      0x03(enroll_indata 68 o) ; boucle { capture 0x23/0x06/0x65/0x07 -> 0x1e -> 0x08(enrollment_info 0xc98) }
      jusqu'a +0xbfe != 0 (COMPLETE, N decide par le SEP) ; export catacomb 0x6c a persister.

Murs (non resolubles en lecture seule) :
  1. D2 : ni keybag ni gabarit nativement (EP 0x12 SKS jamais ouvert). Rien a matcher ; enroll/0x09 peut exiger
     le keybag (SEP-refus non tranche).
  2. enroll_indata_v2_t (0x03, 68 o) : contenu INCONNU.
  3. 0x06 (0xa7 o, nonce par lock) : contenu INCONNU.

Expérience la moins chere qui tranche (E-enroll-start, SANS doigt) :
  apres J5c pass2, catacomb absent/vide, emettre UN SEUL 0x03 avec enroll_indata_v2_t minimal
  (u32[0]=1 = flag mode, reste 0 ; best-effort documente) et OBSERVER la reponse exacte du SEP
  (ack ? code d'erreur 0xe00000.. ? refus keybag ? silence ?). Une ecriture, fail-closed immediat.
  -> dit si l'EP 0x12 (keybag) est INDISPENSABLE avant d'investir dans le reverse de biometrickitd.

A FAIRE AVANT DE LANCER QUOI QUE CE SOIT :
  - valider E-enroll-start avec l'orchestrateur/sceptique (le payload 0x03 devine est une HYPOTHESE) ;
  - coder le niveau dedie (le noyau refuse aujourd'hui allow_sbio_bio != 0) ;
  - « go » d'Albert (classe neuve, 1er run).
TXT
echo "STOP : J6 non executable (voir ci-dessus et docs/j6_enroll_match_protocol.md §6)." >&2
exit 2
