#!/usr/bin/env bash
# Écran d'appel affiché dans la fenêtre ouverte par tools/appel_albert.sh. N'importe quelle touche ferme.
MSG="${1:-}"
[ -z "$MSG" ] && MSG="$(cat "$(dirname "$0")/../.appel_msg" 2>/dev/null)"
[ -z "$MSG" ] && MSG="J’ai besoin de toi"
B=$'\e[1m'; N=$'\e[0m'
COLORS=(31 33 32 36 34 35)
BLAGUES=(
  "Le SEP refuse de parler à quelqu'un d'autre que ton doigt. C'est mignon, en vrai."
  "J'ai essayé avec mon doigt. Problème : je n'ai pas de doigt."
  "Le capteur Touch ID s'ennuie. Il a compté 0 empreinte depuis 10 minutes."
  "Rappel : le capteur, on le CARESSE. On ne l'écrase pas, c'est aussi le bouton power."
  "Ctrl+Cmd+Q, pas Cmd+Q. Sinon c'est le Finder qui pleure."
  "Le M1 Max attend. Il a 10 cœurs et zéro patience."
  "Si tu lis ça, le Mac a plus de vie sociale que moi ce soir."
  "Statut : 25 messages SBIO prêts à être déclenchés par un seul index. Pression."
  "Aucun SEP n'a été maltraité pendant cette expérience. Lecture seule, juré."
)
FRAMES=(
'      _______________
     |  ___________  |
     | |   (o_o)   | |     ☝
     | |  TOUCH ME | |    /
     | |___________| |   /
     |_______________|  /
       \_____________\'
'      _______________
     |  ___________  |
     | |   (O_O)   | |       ☝
     | |  TOUCH ME | |      /
     | |___________| |     /
     |_______________|    /
       \_____________\'
'      _______________
     |  ___________  |
     | |   (^_^)   | |   ☝
     | |  TOUCH ME | |  /
     | |___________| | /
     |_______________|/
       \_____________\'
)
tput civis; trap 'tput cnorm' EXIT
start=$(date +%s); i=0; blague="${BLAGUES[RANDOM % ${#BLAGUES[@]}]}"
while :; do
  c=${COLORS[i % ${#COLORS[@]}]}
  clear
  printf '\e[%sm' "$c"; figlet -c -w "$(tput cols)" "ALBERT !" 2>/dev/null || echo "   A L B E R T !"
  printf '%s\n' "${FRAMES[i % 3]}"; printf '%s' "$N"
  echo
  echo "  ${B}Claude a besoin de toi :${N}"
  echo "  ${B}$(printf '\e[%sm' "$c")$MSG${N}"
  echo
  echo "  💬 $blague"
  echo
  echo "  ⏱  ça fait $(( $(date +%s) - start )) s que je t'attends. (n'importe quelle touche = fermer)"
  (( i % 25 == 24 )) && blague="${BLAGUES[RANDOM % ${#BLAGUES[@]}]}"
  if read -rsn1 -t 0.4 _; then break; fi
  i=$((i+1))
done
