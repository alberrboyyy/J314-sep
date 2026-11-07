#!/usr/bin/env bash
# « Ding » de sonnette quand Albert doit intervenir. Usage : ./tools/alert.sh "message"
MSG="${1:-Intervention humaine nécessaire}"
pw-play /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null || printf '\a'
command -v notify-send >/dev/null && notify-send "sep-touchid" "$MSG" 2>/dev/null
echo "ALERTE : $MSG"
