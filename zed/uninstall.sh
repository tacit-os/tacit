#!/usr/bin/env bash
# Remove Zed Tacit theme integration.
set -euo pipefail

ZED_SCRIPTS="$HOME/.config/zed/scripts"
SYSTEMD_USER="$HOME/.config/systemd/user"

echo "==> Zed Tacit Theme Uninstaller"
echo

systemctl --user disable zed-tacit-theme-watch.service 2>/dev/null || true
systemctl --user stop zed-tacit-theme-watch.service 2>/dev/null || true
echo "   Stopped watcher"

rm -f "$ZED_SCRIPTS/zed-tacit-theme.sh" "$ZED_SCRIPTS/zed-tacit-watch.sh"
echo "   Removed scripts"

rm -f "$SYSTEMD_USER/zed-tacit-theme-watch.service"
systemctl --user daemon-reload
echo "   Removed service"

echo
echo "==> Uninstall complete."
echo "   Your existing Tacit.json theme remains in ~/.config/zed/themes/"
