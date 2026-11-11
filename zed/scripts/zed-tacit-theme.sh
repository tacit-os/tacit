#!/usr/bin/env bash
# Regenerate a Zed theme from Tacit's wallpaper-derived matugen palette.
# Source of truth: ~/.local/state/quickshell/user/generated/colors.json
# Output:    ~/.config/zed/themes/Tacit.json
# Transparency follows Zenburn Transparent's method:
#   "background.appearance": "blurred" + 8-digit hex RGBA colors for surfaces.
set -euo pipefail

COLORS="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/generated/colors.json"
OUT_DIR="$HOME/.config/zed/themes"
OUT="$OUT_DIR/Tacit.json"

[[ -f "$COLORS" ]] || { echo "zed-tacit-theme: matugen colors not found at $COLORS" >&2; exit 1; }
mkdir -p "$OUT_DIR"

# Read transparency mode from Tacit's config (mirrors GlassChoice.qml logic):
#   solid   = enable=false               -> opaque (FF)
#   frosted = enable=true, auto=true     -> 15% through (D9 alpha)
#   clear   = enable=true, auto=false    -> 70% opaque
CONFIG="$HOME/.config/illogical-impulse/config.json"

A_OPAQUE="FF"
A_SURFACE="FF"
A_ELEMENT="FF"
A_TAB="FF"
A_TRANSPARENT="00"

if [[ -f "$CONFIG" ]] && jq -e '.appearance.transparency.enable == true' "$CONFIG" >/dev/null 2>&1; then
    if jq -e '.appearance.transparency.automatic == true' "$CONFIG" >/dev/null 2>&1; then
        # frosted: 15% through -> opacity 0.85 -> D9
        A_SURFACE="D9"
        A_ELEMENT="D9"
        A_TAB="D9"
    else
        # clear: backgroundTransparency -> opacity = 1 - transparency
        TRANS=$(jq -r '.appearance.transparency.backgroundTransparency // 0.4' "$CONFIG")
        OPACITY=179  # 70% opaque
        A_SURFACE=$(printf "%02X" "$OPACITY")
        A_ELEMENT=$(printf "%02X" "$OPACITY")
        A_TAB=$(printf "%02X" "$OPACITY")
    fi
fi

A_SURFACE_BG="$A_SURFACE"
A_ELEMENT_BG="$A_SURFACE"
A_TAB_BG="$A_SURFACE"
A_EDITOR_BG="$A_SURFACE"
A_PANEL_BG="$A_SURFACE"

jq --slurpfile colors "$COLORS" \
  --arg a_opaque "$A_OPAQUE" \
  --arg a_surface "$A_SURFACE" \
  --arg a_element "$A_ELEMENT" \
  --arg a_tab "$A_TAB" \
  --arg a_transparent "$A_TRANSPARENT" \
  --arg a_surface_bg "$A_SURFACE_BG" \
  --arg a_element_bg "$A_ELEMENT_BG" \
  --arg a_tab_bg "$A_TAB_BG" \
  --arg a_editor_bg "$A_EDITOR_BG" \
  --arg a_panel_bg "$A_PANEL_BG" \
  -n '
def C($k): $colors[0][$k];
def alpha($k; $a): C($k) + $a;
# subtle vibrancy: tint text/syntax colors ~12% toward the wallpaper primary hue
def hex2rgb($s):
  ($s | ascii_upcase | .[1:7]) as $s |
  [$s[0:1],$s[1:2],$s[2:3],$s[3:4],$s[4:5],$s[5:6]] | map(. as $c | "0123456789ABCDEF" | index($c)) as $d |
  [$d[0]*16+$d[1], $d[2]*16+$d[3], $d[4]*16+$d[5]];
def rgb2hex($a):
  (("0123456789ABCDEF" | split("")) as $d |
   ("#" + (($a | map(($d[(./16 | floor)]) + $d[. - ((. / 16 | floor) * 16)])) | add)));
def mix($c1; $c2; $t):
  hex2rgb($c1) as $x | hex2rgb($c2) as $y |
  [$x[0]+($y[0]-$x[0])*$t, $x[1]+($y[1]-$x[1])*$t, $x[2]+($y[2]-$x[2])*$t] | map(round) | rgb2hex(.) ;
def V($k; $tint; $t): mix(C($k); C($tint); $t);
# apply_alpha appends an alpha hex to a 6-digit hex color
def apply_alpha($hex; $ah):
  if $hex == null or $hex == "" then $hex
  elif ($hex | tostring)[0:1] != "#" then $hex
  else (($hex | tostring)[0:7]) + $ah
  end;
# BG applies transparency alpha to a surface color
def BG($k; $ah):
  if C($k) == null then null
  else C($k) | apply_alpha(.; $ah)
  end;
{
  "$schema": "https://zed.dev/schema/themes/v0.2.0.json",
  "name": "Tacit",
  "author": "tacit",
  "themes": [
    {
      "name": "Tacit",
      "appearance": "dark",
      "style": {
        # Transparency via blurred appearance + alpha channels (Zenburn method)
        "background.appearance": "blurred",
        "border": BG("surface_container_high"; $a_opaque),
        "border.variant": C("outline"),
        "border.focused": alpha("primary"; "aa"),
        "border.selected": alpha("primary_container"; "ad"),
        "border.transparent": "#00000000",
        "border.disabled": null,
        "elevated_surface.background": BG("surface_container"; $a_surface_bg),
        "surface.background": BG("surface_container"; $a_surface_bg),
        "background": BG("surface_container"; $a_surface_bg),
        "element.background": BG("surface_container"; $a_surface_bg),
        "element.hover": BG("surface_container"; $a_surface_bg),
        "element.active": BG("surface_container"; $a_surface_bg),
        "element.selected": BG("surface_container"; $a_surface_bg),
        "element.disabled": alpha("on_background"; "30"),
        "drop_target.background": BG("surface_container"; $a_surface_bg),
        "ghost_element.background": "#00000000",
        "ghost_element.hover": alpha("primary"; "36"),
        "ghost_element.active": alpha("primary"; "50"),
        "ghost_element.selected": alpha("primary"; "25"),
        "ghost_element.disabled": "#ff5555ff",
        "text": V("on_background"; "primary"; 0.12),
        "text.muted": V("on_surface_variant"; "primary"; 0.10),
        "text.placeholder": V("outline_variant"; "primary"; 0.08),
        "text.disabled": C("outline"),
        "text.accent": C("on_surface_variant"),
        "icon": null,
        "icon.muted": null,
        "icon.disabled": null,
        "icon.placeholder": null,
        "icon.accent": null,
        "status_bar.background": BG("surface_container"; $a_surface_bg),
        "title_bar.background": BG("surface_container"; $a_surface_bg),
        "toolbar.background": BG("surface_container"; $a_surface_bg),
        "tab_bar.background": BG("surface_container"; $a_surface_bg),
        "tab.inactive_background": BG("surface_container"; $a_surface_bg),
        "tab.active_background": BG("surface_container"; $a_surface_bg),
        "search.match_background": alpha("primary"; "4f"),
        "panel.background": BG("surface_container"; $a_surface_bg),
        "panel.focused_border": null,
        "pane.focused_border": "#fffefe00",
        "scrollbar_thumb.background": BG("surface_container"; $a_surface_bg),
        "scrollbar.thumb.hover_background": BG("surface_container"; $a_surface_bg),
        "scrollbar.thumb.border": "#00000000",
        "scrollbar.track.background": BG("surface_container"; $a_surface_bg),
        "scrollbar.track.border": "#ededed0a",
        "editor.foreground": V("on_background"; "primary"; 0.12),
        "editor.background": BG("surface_container"; $a_surface_bg),
        "editor.gutter.background": BG("surface_container"; $a_surface_bg),
        "editor.subheader.background": BG("surface_container"; $a_surface_bg),
        "editor.active_line.background": BG("surface_container"; $a_surface_bg),
        "editor.highlighted_line.background": BG("surface_container"; $a_surface_bg),
        "editor.line_number": V("outline_variant"; "primary"; 0.10),
        "editor.active_line_number": V("on_surface_variant"; "primary"; 0.10),
        "editor.invisible": "#f8f8f230",
        "editor.wrap_guide": "#f7f2f629",
        "editor.active_wrap_guide": alpha("primary"; "59"),
        "editor.document_highlight.read_background": "#f8d7c642",
        "editor.document_highlight.write_background": "#414350",
        "link_text.hover": C("primary"),
        "conflict": C("primary"),
        "conflict.background": alpha("primary"; "33"),
        "conflict.border": C("outline"),
        "created": C("tertiary"),
        "created.background": C("tertiary_container"),
        "created.border": C("outline"),
        "deleted": C("error"),
        "deleted.background": BG("surface_container"; $a_surface_bg),
        "deleted.border": C("outline"),
        "error": C("error"),
        "error.background": BG("surface_container"; $a_surface_bg),
        "error.border": C("error"),
        "hidden": C("outline_variant"),
        "hidden.background": BG("surface_container"; $a_surface_bg),
        "hidden.border": C("outline_variant"),
        "hint": C("outline_variant"),
        "hint.background": null,
        "hint.border": null,
        "ignored": alpha("outline_variant"; "50"),
        "ignored.background": BG("surface_container"; $a_surface_bg),
        "ignored.border": null,
        "info": C("secondary"),
        "info.background": BG("surface_container"; $a_surface_bg),
        "info.border": C("secondary"),
        "modified": C("primary"),
        "modified.background": null,
        "modified.border": null,
        "predictive": C("on_background"),
        "predictive.background": null,
        "predictive.border": null,
        "renamed": null,
        "renamed.background": BG("surface_container"; $a_surface_bg),
        "renamed.border": null,
        "success": C("tertiary"),
        "success.background": BG("surface_container"; $a_surface_bg),
        "success.border": C("tertiary"),
        "unreachable": null,
        "unreachable.border": null,
        "warning": C("secondary"),
        "warning.background": BG("surface_container"; $a_surface_bg),
        "warning.border": C("secondary"),
        "players": [
          { "cursor": C("primary"), "background": C("primary"), "selection": alpha("primary"; "33") },
          { "cursor": C("secondary"), "background": C("secondary"), "selection": alpha("secondary"; "33") },
          { "cursor": C("tertiary"), "background": C("tertiary"), "selection": alpha("tertiary"; "33") },
          { "cursor": C("error"), "background": C("error"), "selection": alpha("error"; "33") },
          { "cursor": C("on_background"), "background": C("on_background"), "selection": alpha("on_background"; "33") },
          { "cursor": C("on_secondary"), "background": C("on_secondary"), "selection": alpha("on_secondary"; "33") },
          { "cursor": C("on_tertiary"), "background": C("on_tertiary"), "selection": alpha("on_tertiary"; "33") }
        ],
        "syntax": {
          "attribute": { "color": C("secondary"), "font_style": null, "font_weight": null },
          "boolean": { "color": C("primary"), "font_style": null, "font_weight": null },
          "comment": { "color": C("outline_variant"), "font_style": "italic", "font_weight": null },
          "comment.doc": { "color": C("outline_variant"), "font_style": "italic", "font_weight": null },
          "constant": { "color": C("primary"), "font_style": null, "font_weight": null },
          "constructor": { "color": C("primary"), "font_style": null, "font_weight": null },
          "embedded": { "color": C("on_background"), "font_style": null, "font_weight": null },
          "emphasis": { "color": C("secondary"), "font_style": "italic", "font_weight": null },
          "emphasis.strong": { "color": C("primary"), "font_style": null, "font_weight": 700 },
          "enum": { "color": C("secondary"), "font_style": null, "font_weight": null },
          "function": { "color": C("primary"), "font_style": null, "font_weight": null },
          "hint": { "color": C("tertiary"), "font_style": null, "font_weight": 700 },
          "keyword": { "color": C("error"), "font_style": null, "font_weight": null },
          "label": { "color": C("on_background"), "font_style": null, "font_weight": null },
          "link_text": { "color": C("primary"), "font_style": "normal", "font_weight": null },
          "link_uri": { "color": C("secondary"), "font_style": null, "font_weight": null },
          "number": { "color": C("secondary"), "font_style": null, "font_weight": null },
          "operator": { "color": C("outline"), "font_style": null, "font_weight": null },
          "predictive": { "color": null, "font_style": "italic", "font_weight": null },
          "preproc": { "color": C("tertiary"), "font_style": null, "font_weight": null },
          "primary": { "color": "#ffffff00", "font_style": null, "font_weight": null },
          "property": { "color": C("secondary"), "font_style": null, "font_weight": null },
          "punctuation": { "color": C("outline"), "font_style": null, "font_weight": null },
          "punctuation.bracket": { "color": C("on_background"), "font_style": null, "font_weight": null },
          "punctuation.delimiter": { "color": C("outline"), "font_style": null, "font_weight": null },
          "punctuation.list_marker": { "color": C("tertiary"), "font_style": null, "font_weight": null },
          "punctuation.special": { "color": C("outline"), "font_style": null, "font_weight": null },
          "string": { "color": C("tertiary"), "font_style": null, "font_weight": null },
          "string.escape": { "color": C("primary"), "font_style": null, "font_weight": null },
          "string.regex": { "color": C("error"), "font_style": null, "font_weight": null },
          "string.special": { "color": C("secondary"), "font_style": null, "font_weight": null },
          "string.special.symbol": { "color": C("tertiary"), "font_style": null, "font_weight": null },
          "tag": { "color": C("error"), "font_style": null, "font_weight": null },
          "text.literal": { "color": C("tertiary"), "font_style": null, "font_weight": null },
          "title": { "color": C("primary"), "font_style": null, "font_weight": null },
          "type": { "color": C("secondary"), "font_style": null, "font_weight": null },
          "type.interface": { "color": C("secondary"), "font_style": "italic", "font_weight": null },
          "type.super": { "color": C("secondary"), "font_style": "italic", "font_weight": null },
          "variable": { "color": C("on_background"), "font_style": null, "font_weight": null },
          "variable.member": { "color": C("on_background"), "font_style": null, "font_weight": null },
          "variable.parameter": { "color": C("tertiary"), "font_style": "italic", "font_weight": null },
          "variable.special": { "color": C("error"), "font_style": "italic", "font_weight": null },
          "variant": { "color": C("primary"), "font_style": null, "font_weight": null },
          "type.builtin": { "color": C("secondary"), "font_style": null, "font_weight": null },
          "function.method": { "color": "", "font_style": null, "font_weight": null },
          "function.special.definition": { "color": "", "font_style": null, "font_weight": null },
          "editor.foreground": { "color": "#ffffff00", "font_style": null, "font_weight": null }
        },
        "terminal.background": BG("surface_container"; $a_surface_bg),
        "terminal.foreground": C("on_background"),
        "terminal.bright_foreground": C("on_background"),
        "terminal.dim_foreground": C("on_surface_variant"),
        "terminal.ansi.black": BG("surface_container"; $a_surface_bg),
        "terminal.ansi.bright_black": C("outline_variant"),
        "terminal.ansi.dim_black": C("surface_dim"),
        "terminal.ansi.red": C("error"),
        "terminal.ansi.bright_red": C("error"),
        "terminal.ansi.dim_red": alpha("error"; "cc"),
        "terminal.ansi.green": C("tertiary"),
        "terminal.ansi.bright_green": C("tertiary"),
        "terminal.ansi.dim_green": alpha("tertiary"; "73"),
        "terminal.ansi.yellow": C("secondary"),
        "terminal.ansi.bright_yellow": C("secondary"),
        "terminal.ansi.dim_yellow": C("outline_variant"),
        "terminal.ansi.blue": C("primary"),
        "terminal.ansi.bright_blue": C("primary"),
        "terminal.ansi.dim_blue": C("outline_variant"),
        "terminal.ansi.magenta": C("primary"),
        "terminal.ansi.bright_magenta": C("primary"),
        "terminal.ansi.dim_magenta": C("outline_variant"),
        "terminal.ansi.cyan": C("secondary"),
        "terminal.ansi.bright_cyan": C("secondary"),
        "terminal.ansi.dim_cyan": C("outline_variant"),
        "terminal.ansi.white": C("on_background"),
        "terminal.ansi.bright_white": "ffffffff",
        "terminal.ansi.dim_white": C("on_surface_variant"),
        "status_bar.foreground": "#00000000",
        "tab.active_foreground": "#ffffff00"
      }
    }
  ]
}' > "$OUT"

echo "zed-tacit-theme: wrote $OUT from $COLORS"
