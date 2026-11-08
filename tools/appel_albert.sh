#!/usr/bin/env bash
# Appelle Albert : fenêtre animée sur le bureau 2 (Hyprland, sans voler le focus) + ding + notification.
# Usage : ./tools/appel_albert.sh "message court"     (APPEL_WS=n pour un autre bureau)
cd "$(dirname "$0")/.."
MSG="${1:-J’ai besoin de toi}"
WS="${APPEL_WS:-2}"
printf '%s\n' "$MSG" > .appel_msg
for _ in 1 2 3; do pw-play /usr/share/sounds/freedesktop/stereo/bell.oga 2>/dev/null; done &
command -v notify-send >/dev/null && notify-send -u critical "🔔 Claude t'appelle (bureau $WS)" "$MSG" 2>/dev/null
TUI="$PWD/tools/appel_albert_tui.sh"
if command -v hyprctl >/dev/null && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] \
   && hyprctl eval "hl.exec_cmd(\"alacritty --class sep-appel --title ALBERT -e $TUI\", { workspace = \"$WS silent\" })" | grep -q '^ok'; then
  :
else
  alacritty --class sep-appel --title ALBERT -e "$TUI" >/dev/null 2>&1 &
fi
echo "APPEL : $MSG"
