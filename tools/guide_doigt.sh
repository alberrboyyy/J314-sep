#!/usr/bin/env bash
# Session doigt courte et guidée. Le marqueur est posé AU « DING » : fais l'action exactement à ce moment-là.
# Usage : ./tools/guide_doigt.sh   (pendant une capture en cours)
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
res() { read -r -p "    Résultat ? (o = déverrouillé, n = refusé, autre = texte) " r; note "res_$1 $r"; }

echo "${B}Session doigt.${N} Verrouiller = ${B}Ctrl+Cmd+Q${N} uniquement. Doigt à plat ~2 s, sans appuyer."
read -r -p "Quand l'ÉCRAN DE CONNEXION est affiché sur le Mac : Entrée (ne te connecte pas encore)… " _
mark loginwin
go pw_login "tape ton MOT DE PASSE + Entrée sur le Mac"
wait_s 25
for i in 1 2 3; do
  go lock_g$i "Ctrl+Cmd+Q (verrouiller)"; wait_s 15
  go fp_good_$i "BON doigt sur le capteur"; wait_s 5; res fp_good_$i; wait_s 15
done
for i in 1 2; do
  go lock_b$i "Ctrl+Cmd+Q (verrouiller)"; wait_s 15
  go fp_bad_$i "MAUVAIS doigt (non enrôlé) sur le capteur"; wait_s 5; res fp_bad_$i
  go pw_unlock_$i "déverrouille au MOT DE PASSE"; wait_s 15
done
mark end; ding
read -r -p "Commentaire (doigts enrôlés ? anomalies ?) " r; note "fin $r"
echo "${G}${B}Terminé, merci !${N}"
