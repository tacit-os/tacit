#!/usr/bin/env bash
# Opens Tacit's Settings: `open.sh [page]` shows a page (a key of services/SettingsCatalog.qml),
# `open.sh --toggle` closes it when it has the focus and otherwise opens it.
# One window only: a running Settings is turned to the page and brought forward, and -n stops a
# second start from making a second window.
app="$(dirname "$(readlink -f "$0")")/../../tacit-settings.qml"
page="${1:-}"

if [ "$page" = "--toggle" ]; then
    if hyprctl activewindow -j 2>/dev/null | grep -q '"class": "settings"'; then
        exec qs -p "$app" ipc call settingsApp close
    fi
    page=""
fi

if qs -p "$app" ipc call settingsApp page "$page" >/dev/null 2>&1; then
    hyprctl dispatch 'hl.dsp.focus({ window = "class:settings" })' >/dev/null
else
    TACIT_SETTINGS_PAGE="$page" qs -n -d -p "$app" >/dev/null 2>&1
    # A Settings still starting (opened a moment ago) holds the instance but does not answer yet, so -n started
    # nothing and the page would be lost: ask it again until it answers. One this started has it already.
    [ -n "$page" ] || exit 0
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
        qs -p "$app" ipc call settingsApp page "$page" >/dev/null 2>&1 && exit 0
        sleep 0.1
    done
fi
