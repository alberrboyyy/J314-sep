#!/usr/bin/env bash
# Session doigt C11 « tranchante » (EXPÉRIENCE HUMAINE, ≤ 10 min après l'écran de connexion).
# Protocole : docs/hypotheses.md, « Revue sceptique de C8 », section « C10 — Session doigt tranchante »
# (renommée C11 : C10 = boot de contrôle traces/20261108-011515_c10-boot-ool-stable).
# Le marqueur est posé AU « DING » : fais l'action exactement à ce moment-là.
# Usage : ./tools/guide_doigt_c11.sh   (dans un 2e terminal, pendant une capture en cours)
# Ce script ne parle pas au Mac : il pose seulement des marqueurs (tools/mark.sh) et écrit notes.txt.
#
# Capture recommandée (à lancer AVANT, même réglages que C8 + 0x6c en lecture complète) :
#   SEP_OOL_EPS=0x08 SEP_OOL_BYTES=0x400 SEP_OOL_SPLIT_DIR=1 \
#   SEP_OOL_FULL_TYPES=0x09,0x21,0x45,0x54,0x5b,0x5f,0x65,0x6c,0x6d \
#   TRACE_TIMEOUT=1500 ./tools/boot_and_trace.sh c11-doigt-tranchant
#   - 0x6c : lu en entier (B, 0x4000) seulement sur EP 0x08, 3 morceaux après chaque succès (HO).
#     Supporté par hv/trace_sep_filtered.py : SEP_OOL_FULL_TYPES passe par _parse_eps (toute valeur 0..0xff),
#     test `typ in full_types` dans _ool_dump. Ne change rien aux autres EP (0x6c y est un TYPE sans lecture OOL).
#   - TRACE_TIMEOUT=1500 : C8 = 1200 s pour ~7 min de session ; ici ~2 min de boot + ≤ 10 min + marge
#     pour un retard humain. Fin : ./tools/stop_capture.sh (reboot() HV = arrêt NON propre de macOS ;
#     piège (a) de HO : si Albert veut tester la persistance au boot suivant, arrêt propre de macOS
#     d'abord (menu Pomme > Éteindre), comportement sous HV non vérifié).
#   - Ne rien changer d'autre (pas de SEP_OOL_SPLIT_DIR=0 ici : un seul réglage modifié à la fois).
#
# But de chaque étape (prédictions détaillées : tableau de la section citée) :
#   loginwin, pw_login         référence mot de passe (chemin SKS sans doigt, HL).
#   lock_m1, fp_bad_1, fp_good_1   mauvais PUIS bon doigt dans le MÊME verrouillage (ordre inversé vs C8) :
#                              HJ (+0x44 identique ?), HG (+0x28 lié au doigt ou au verrouillage),
#                              HE/HF (0x09 = -1 et +0xc24=0x2e même en début de session).
#   lock_m2, fp_tap_1..3, fp_good_2  effleurements < 0,3 s pour provoquer des abandons : HG
#                              (+0x06..07 = 00 00 à chaque abandon, 01 01 si 0x09 suit).
#   lock_m3, fp_tip_1, fp_good_3     bout du doigt : HF (code de refus ≠ 0x2e, ou éventail = score).
#   fp_good_*                  HE (0x1f5 + identifiant), HO (blob 0x6c complet, à retrouver au boot C12).
#   fp_app_prompt/good, fp_app_prompt2/bad  Touch ID session ouverte, keybag déjà déverrouillé :
#                              HE alternative 1 et HL (notif <12 TAG=0 DATA=0xfffffe0b attendue ABSENTE).
#   uid_check                  HN / HB : uid 501 ? GeneratedUID = FE6003D8-CEA5-414F-B48A-0338DC7C371B ?
#                              (lecture seule dans Terminal, recopié dans notes.txt).
#
# Invite Touch ID choisie : Réglages Système > Mots de passe (macOS 13) demande Touch ID pour s'ouvrir
# si « Touch ID pour le remplissage des mots de passe » est actif ; quitter Réglages Système la reverrouille
# (non vérifié ici : si l'invite n'apparaît pas, voir le repli dans la consigne).
set -u
cd "$(dirname "$0")/.."
B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; N=$'\e[0m'
ding() { pw-play /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null & }
mark() { ./tools/mark.sh "$1" >/dev/null || echo "  (marqueur $1 refusé : capture en cours ?)"; }
note() { echo "$(date +%s.%6N) $1" >> "$(sed -n 1p .current_capture 2>/dev/null)/notes.txt"; }
go() {  # go <étiquette> <consigne>
  echo; echo "${B}Prochaine action : $2${N}"
  read -r -p "    Prêt ? ${Y}Entrée${N} (ne fais rien encore)… " _
  for s in 3 2 1; do printf "\r    %s… " "$s"; sleep 1; done
  mark "$1"; ding; printf "\r    ${B}${G}MAINTENANT !${N}  (%s)\n" "$1"
}
wait_s() { for s in $(seq "$1" -1 1); do printf "\r    attends %2d s (ne touche à rien) " "$s"; sleep 1; done; printf "\r%40s\r" ""; }
res() { read -r -p "    Résultat ? (o = accepté, n = refusé, autre = texte) " r; note "res_$1 $r"; }

[ -s .current_capture ] || { echo "Pas de capture en cours (.current_capture absent) : lance d'abord boot_and_trace.sh."; exit 1; }

echo "${B}Session doigt C11.${N} Verrouiller = ${B}Ctrl+Cmd+Q${N} uniquement. Doigt à plat ~2 s, sans appuyer."
echo "Jamais la touche Touch ID. Si macOS exige le mot de passe : ${B}./tools/mark.sh anomalie${N}, tape-le, continue."
read -r -p "Quand l'ÉCRAN DE CONNEXION est affiché sur le Mac : Entrée (ne te connecte pas encore)… " _
mark loginwin
go pw_login "MOT DE PASSE + Entrée"
wait_s 25

# Cycle 1 : mauvais PUIS bon doigt, même verrouillage (HJ, HG +0x28, HE/HF)
go lock_m1 "Ctrl+Cmd+Q (verrouiller)"; wait_s 15
go fp_bad_1 "MAUVAIS doigt (non enrôlé)"; wait_s 5; res fp_bad_1
go fp_good_1 "BON doigt"; wait_s 5; res fp_good_1; wait_s 20

# Cycle 2 : 3 effleurements (abandons, HG), puis bon doigt
go lock_m2 "Ctrl+Cmd+Q (verrouiller)"; wait_s 15
go fp_tap_1 "EFFLEURE (< 0,3 s), bon doigt"; wait_s 4
go fp_tap_2 "EFFLEURE encore (< 0,3 s)"; wait_s 4
go fp_tap_3 "EFFLEURE encore (< 0,3 s)"; wait_s 4; res fp_tap
go fp_good_2 "BON doigt à plat"; wait_s 5; res fp_good_2; wait_s 20

# Cycle 3 : bout du doigt (HF), puis bon doigt
go lock_m3 "Ctrl+Cmd+Q (verrouiller)"; wait_s 15
go fp_tip_1 "BON doigt, SEULEMENT LE BOUT"; wait_s 5; res fp_tip_1
go fp_good_3 "BON doigt à plat"; wait_s 5; res fp_good_3; wait_s 20

# Session ouverte : invite Touch ID hors écran de verrouillage (HE alt. 1, HL)
echo; echo "  Invite = Réglages Système > Mots de passe. Pas d'icône Touch ID ? Échap, ./tools/mark.sh anomalie, Entrée partout."
go fp_app_prompt "ouvre Réglages Système > Mots de passe, attends l'invite (PAS de doigt)"; wait_s 5
go fp_app_good "BON doigt sur l'invite"; wait_s 5; res fp_app_good
go fp_app_quit "quitte Réglages Système (menu Réglages Système > Quitter)"; wait_s 5
go fp_app_prompt2 "rouvre Réglages Système > Mots de passe (invite, PAS de doigt)"; wait_s 5
go fp_app_bad "MAUVAIS doigt sur l'invite, puis Annuler"; wait_s 5; res fp_app_bad

# HN / HB : lecture seule
go uid_check "ouvre Terminal sur le Mac (rien d'autre)"
echo "    Tape :  ${B}id -u${N}"
read -r -p "    Recopie la sortie : " r; note "uid_id_u $r"
echo "    Tape :  ${B}dscl . -read /Users/\$(id -un) GeneratedUID${N}"
read -r -p "    Recopie la sortie : " r; note "uid_generateduid $r"

mark end; ding
read -r -p "Commentaire (anomalies ?) " r; note "fin $r"
echo "${G}${B}Terminé, merci !${N}  Fin : ./tools/stop_capture.sh (ou Pomme > Éteindre d'abord, voir en-tête)"
