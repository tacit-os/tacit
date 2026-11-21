#!/usr/bin/env bash
# measure-glass.sh: the glass scale for the wallpaper in use (seethrough.py) where none was measured yet, then the
# terminals' alpha and Hyprland's opacity rules from it, as a wallpaper change does (switchwall.sh). Run at every shell
# start (FirstRunExperience.qml): seethrough.json is written when a wallpaper is picked, so an account from before 1.1.3
# kept the unscaled glass on a light wallpaper until it picked one (the 1.1.3 update test, 2026-10-23).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
generated="$XDG_STATE_HOME/quickshell/user/generated"
config="$XDG_CONFIG_HOME/illogical-impulse/config.json"
wall=$(jq -r '.background.wallpaperPath // ""' "$config" 2>/dev/null)
ext="${wall##*.}"
case "${ext,,}" in mp4|webm|mkv|avi|mov) wall=$(jq -r '.background.thumbnailPath // ""' "$config" 2>/dev/null) ;; esac
need_seethrough=0
need_bar=0
[ -e "$generated/seethrough.json" ] || need_seethrough=1
[ -e "$generated/bar_luminance.json" ] || need_bar=1
[ "$need_seethrough" -eq 0 ] && [ "$need_bar" -eq 0 ] && exit 0
# a new account has no wallpaper yet: its first start picks dusk through switchwall.sh, which measures it
[ -f "$wall" ] && [ -f "$generated/colors.json" ] || exit 0
source "$SCRIPT_DIR/../venv.sh"
activate_shell_venv || exit 1
if [ "$need_seethrough" -eq 1 ]; then
    python3 "$SCRIPT_DIR/seethrough.py" "$wall" "$generated/colors.json" > /dev/null || exit 1
fi
if [ "$need_bar" -eq 1 ]; then
    python3 "$SCRIPT_DIR/bar_luminance.py" "$wall" > /dev/null || true
fi
deactivate
if [ "$need_seethrough" -eq 1 ]; then
    "$SCRIPT_DIR/applycolor.sh"
    hyprctl reload config-only > /dev/null 2>&1
fi
exit 0
