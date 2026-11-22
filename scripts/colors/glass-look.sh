#!/usr/bin/env bash
# glass-look.sh [--start]: Settings > Appearance's See-through (Clear, Frosted or Solid, in config.json) where Hyprland
# reads it at every start and reload, generated/glass.json: for Solid hyprland.lua draws every window solid and none
# faded, as with the blur off. Then the terminals' alpha from it (applycolor.sh), and Hyprland reloaded when Solid came
# or went, so a look picked shows at once on the windows already open. The shell runs it whenever the look changes
# (shell.qml), and at its start with --start, which does nothing when the file already holds the look.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
generated="$XDG_STATE_HOME/quickshell/user/generated"
# a key the file lacks is the shell's default, Frosted
look=$(jq -r 'if .appearance.transparency.enable == false then "solid"
    elif .appearance.transparency.automatic == false then "clear" else "frosted" end' \
    "$XDG_CONFIG_HOME/illogical-impulse/config.json" 2>/dev/null)
[ -n "$look" ] || exit 0
was=$(jq -r '.look // ""' "$generated/glass.json" 2>/dev/null)
[ "$1" = --start ] && [ "$was" = "$look" ] && exit 0
if [ "$was" != "$look" ]; then
    mkdir -p "$generated"
    printf '{"look": "%s"}\n' "$look" > "$generated/glass.json.tmp" && mv -f "$generated/glass.json.tmp" "$generated/glass.json"
fi
# a new account has no palette yet: its first wallpaper makes one with this look (switchwall.sh)
[ -s "$generated/material_colors.scss" ] && "$SCRIPT_DIR/applycolor.sh"
# Clear and Frosted are the same to Hyprland
if [ "$was" != "$look" ] && { [ "$was" = solid ] || [ "$look" = solid ]; }; then
    hyprctl reload config-only > /dev/null 2>&1
fi
exit 0
