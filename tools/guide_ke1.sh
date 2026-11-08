#!/usr/bin/env bash
# Guide K-E1 (EXPÉRIENCE HUMAINE ≤ 4 min) : protocole docs/hypotheses.md, section K1 « EXPÉRIENCE HUMAINE K-E1 ».
# À lancer dans un 2e terminal, session macOS DÉJÀ ouverte, capture en cours. Ne parle pas au Mac : pose des marqueurs.
# Invite Touch ID : Réglages Système > Mots de passe (se reverrouille en quittant Réglages). Verrouiller = Ctrl+Cmd+Q.
set -u
cd "$(dirname "$0")/.."
B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; N=$'\e[0m'
ding() { pw-play /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null & }
mark() { ./tools/mark.sh "$1" >/dev/null || echo "  (marqueur $1 refusé : capture en cours ?)"; }
note() { echo "$(date +%s.%6N) $1" >> "$(sed -n 1p .current_capture 2>/dev/null)/notes.txt"; }
go() {
  echo; echo "${B}Action : $2${N}"
  read -r -p "    Prêt ? ${Y}Entrée${N} (ne fais rien encore)… " _
  for s in 3 2 1; do printf "\r    %s… " "$s"; sleep 1; done
  mark "$1"; ding; printf "\r    ${B}${G}MAINTENANT !${N}  (%s)\n" "$1"
}
res() { read -r -p "    Résultat ? (o = accepté, n = refusé, autre = texte) " r; note "res_$1 $r"; }
wait_s() { for s in $(seq "$1" -1 1); do printf "\r    attends %2d s (ne touche à rien) " "$s"; sleep 1; done; printf "\r%40s\r" ""; }

[ -s .current_capture ] || { echo "Pas de capture en cours : lance d'abord boot_and_trace.sh."; exit 1; }
echo "${B}K-E1.${N} Session ouverte. Doigt à plat ~2 s, sans appuyer. Jamais la touche Touch ID."
for i in 1 2 3; do
  go ke1_good_$i "Réglages Système > Mots de passe, BON doigt à l'invite"; res good_$i
  echo "    (quitte Réglages Système pour le reverrouiller)"; read -r -p "    Entrée quand c'est fait… " _
done
go ke1_bad_1 "Rouvre Réglages > Mots de passe, MAUVAIS doigt à l'invite"; res bad_1
read -r -p "    Annule l'invite, quitte Réglages. Entrée… " _
go ke1_lock_a "Verrouille : Ctrl+Cmd+Q"
go ke1_pw "MOT DE PASSE + Entrée"
go ke1_lock_b "Verrouille : Ctrl+Cmd+Q"; wait_s 5
go ke1_good_lockb "BON doigt sur l'écran de connexion"; res good_lockb
go ke1_lock_c "Verrouille : Ctrl+Cmd+Q"; wait_s 20
go ke1_good_lockc "BON doigt sur l'écran de connexion (après 20 s)"; res good_lockc
mark ke1_fin; echo; echo "${B}Terminé.${N} Dis « fini » à Claude."
