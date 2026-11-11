#!/usr/bin/env bash
# Watch Tacit's wallpaper palette (colors.json) and transparency config and
# regenerate the Zed theme whenever either changes. No root needed — polls mtime (5 s).
set -euo pipefail

COLORS="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/colors.json"
CONFIG="$HOME/.config/illogical-impulse/config.json"
GEN="$HOME/.config/zed/scripts/zed-tacit-theme.sh"

prev_colors=""
prev_config=""

while true; do
  regen=0
  if [[ -f "$COLORS" ]]; then
    now=$(stat -c %Y "$COLORS" 2>/dev/null || echo 0)
    if [[ "$now" != "$prev_colors" && "$now" != "0" ]]; then
      prev_colors="$now"
      regen=1
    fi
  fi
  if [[ -f "$CONFIG" ]]; then
    now=$(stat -c %Y "$CONFIG" 2>/dev/null || echo 0)
    if [[ "$now" != "$prev_config" && "$now" != "0" ]]; then
      prev_config="$now"
      regen=1
    fi
  fi
  if [[ "$regen" == "1" ]]; then
    "$GEN" >/dev/null 2>&1 || true
  fi
  sleep 5
done
