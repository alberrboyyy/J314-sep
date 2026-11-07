#!/usr/bin/env bash
# Guide pas à pas de la session humaine C3 (Touch ID). Pose les marqueurs (tools/mark.sh) automatiquement.
# Usage : ./tools/c3_guide.sh   (pendant qu'une capture c3 tourne)
set -u
cd "$(dirname "$0")/.."
B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; N=$'\e[0m'
ding() { pw-play /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null & }
mark() { ./tools/mark.sh "$1" >/dev/null || echo "  (marqueur $1 refusé : capture en cours ?)"; }
n=0
act() {  # act <étiquette> <consigne>  : Entrée -> marqueur -> Albert fait l'action
  n=$((n+1)); ding
  echo; echo "${B}[$n] $2${N}"
  read -r -p "    ${Y}Entrée${N} puis fais-le tout de suite… " _
  mark "$1"; echo "    ${G}✓ $1${N}"
}
done_() {  # done_ <étiquette> <ce qu'on attend> : Entrée quand c'est arrivé
  read -r -p "    Entrée quand ${2}… " _
  mark "$1"; echo "    ${G}✓ $1${N}"
}
idle() {  # idle <étiquette> : 30 s sans toucher, décompte
  mark "$1"; echo "    ${B}Ne touche à rien${N} (30 s)"
  for s in $(seq 30 -1 1); do printf "\r    %2d s " "$s"; sleep 1; done; printf "\r    ${G}✓ %s${N}      \n" "$1"
}

echo "${B}C3 — session Touch ID guidée.${N} Verrouiller = ${B}Ctrl+Cmd+Q${N} uniquement (jamais la touche Touch ID)."
echo "Doigt : à plat, sans appuyer, ~2 s. Imprévu : Ctrl-C ici, puis ./tools/mark.sh anomalie."

echo; echo "${B}${Y}⚠ NE TE CONNECTE PAS tout de suite : le 1er essai se fait AVANT le mot de passe.${N}"
act  loginwin    "Quand l'ÉCRAN DE CONNEXION est affiché : Entrée, et NE TAPE RIEN sur le Mac."
idle idle0
act  fp_prelogin "Toujours SANS mot de passe : pose le BON doigt sur le capteur. Regarde ce que macOS affiche."
read -r -p "    Qu'a affiché macOS ? (texte libre) " r; echo "$(date +%s.%6N) note_fp_prelogin $r" >> "$(sed -n 1p .current_capture 2>/dev/null)/notes.txt"
idle idle1
act  pw_login    "Tape ton MOT DE PASSE + Entrée."
done_ pw_login_ok "le bureau est affiché"
idle idle2
act  lock1       "Verrouille : Ctrl+Cmd+Q."
idle idle3
act  pw_unlock   "Déverrouille au MOT DE PASSE."
done_ pw_unlock_ok "le bureau est affiché"
idle idle4
for i in 1 2 3; do
  act  lock_f$i     "Verrouille : Ctrl+Cmd+Q.  (doigt $i/3)"
  idle idle_f$i
  act  fp_good_$i   "Déverrouille avec le BON doigt."
  done_ fp_good_${i}_ok "le bureau est affiché"
  idle idle_f${i}b
done
act  lock_bad    "Verrouille : Ctrl+Cmd+Q."
idle idle_bad
act  fp_bad_1    "Pose un MAUVAIS doigt (non enrôlé), puis retire-le."
sleep 10
act  fp_bad_2    "Encore le MAUVAIS doigt, puis retire-le."
sleep 10
act  pw_after_bad "Déverrouille au MOT DE PASSE."
done_ pw_after_bad_ok "le bureau est affiché"
idle idle5
act  fp_noprompt "Session ouverte, rien demandé : pose le BON doigt ~2 s."
idle idle6
mark end; ding
echo; echo "${G}${B}Terminé, merci !${N} Tu peux lâcher le Mac : Claude s'occupe de l'arrêt et du reboot."
read -r -p "Un commentaire (anomalies, échecs) ? " r; echo "$(date +%s.%6N) note_fin $r" >> "$(sed -n 1p .current_capture 2>/dev/null)/notes.txt"
