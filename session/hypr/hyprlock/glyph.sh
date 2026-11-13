#!/usr/bin/env bash
# The notch's status glyph on the lock screen, as a Material Symbols ligature name.
# Same order as the desktop: charging, then night light. Empty when nothing applies.
# Nothing either without the font: installs have no Material Symbols, and the name itself was drawn beside the
# time ("21:41 bedtime", test computer, 2026-10-29)
fc-list -q "Material Symbols Rounded" || exit 0
for d in /sys/class/power_supply/book4-ec-battery /sys/class/power_supply/*; do
  [[ -r $d/status && $(<"$d/type") == Battery ]] || continue
  [[ ! -r $d/scope || $(<"$d/scope") != Device ]] || continue
  [[ $(<"$d/status") == Charging ]] && { echo bolt; exit; }
  break
done
# a tint is on while hyprsunset's identity is off, as the desktop reads it (Hyprsunset.qml, hyprsunset 0.4): its
# temperature stays where it was when the night light was turned off, so that read a night light turned off as on
pidof hyprsunset >/dev/null || exit 0
[[ $(hyprctl hyprsunset identity get 2>/dev/null | head -1) == false ]] && echo bedtime
