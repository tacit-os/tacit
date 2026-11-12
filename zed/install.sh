#!/usr/bin/env bash
# Install Zed Tacit theme integration into the user's Zed config.
# Copies generator + watcher scripts, sets up systemd user service, generates theme.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ZED_DIR="$HOME/.config/zed"
ZED_SCRIPTS="$ZED_DIR/scripts"
ZED_THEMES="$ZED_DIR/themes"
SYSTEMD_USER="$HOME/.config/systemd/user"

echo "==> Zed Tacit Theme Installer"
echo

# Ensure directories exist
mkdir -p "$ZED_SCRIPTS" "$ZED_THEMES" "$SYSTEMD_USER"

# Copy scripts
cp "$SCRIPT_DIR/zed-tacit-theme.sh" "$ZED_SCRIPTS/"
cp "$SCRIPT_DIR/zed-tacit-watch.sh" "$ZED_SCRIPTS/"
chmod +x "$ZED_SCRIPTS/zed-tacit-theme.sh" "$ZED_SCRIPTS/zed-tacit-watch.sh"
echo "   Installed scripts to $ZED_SCRIPTS"

# Copy systemd service
cp "$PROJECT_ROOT/zed/systemd/zed-tacit-theme-watch.service" "$SYSTEMD_USER/"
echo "   Installed service to $SYSTEMD_USER"

# Generate initial theme
"$ZED_SCRIPTS/zed-tacit-theme.sh"
echo "   Generated $ZED_THEMES/Tacit.json"

# Enable + start watcher
systemctl --user daemon-reload
systemctl --user enable zed-tacit-theme-watch.service
systemctl --user restart zed-tacit-theme-watch.service
echo "   Started zed-tacit-theme-watch.service"

echo
echo "==> Install complete."
echo "   Restart Zed to load the Tacit theme."
echo "   Theme will auto-regenerate on wallpaper or transparency change."
