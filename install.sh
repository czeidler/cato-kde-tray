#!/usr/bin/env bash
# install.sh – Install or update the Cato VPN tray applet for KDE Plasma 6
#
# Usage: ./install.sh [--restart]
#   --restart   restart plasmashell afterwards so the system tray loads the applet
set -euo pipefail

APPLET_ID="org.kde.cato-kde-tray"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v kpackagetool6 >/dev/null 2>&1; then
    echo "ERROR: kpackagetool6 not found – this applet requires KDE Plasma 6." >&2
    exit 1
fi

# Stage only the package files so .git, scripts and docs are not copied along.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/$APPLET_ID"
cp -r "$SCRIPT_DIR/metadata.json" "$SCRIPT_DIR/contents" "$STAGE/$APPLET_ID/"

echo "==> Installing $APPLET_ID…"
if kpackagetool6 --type Plasma/Applet --list 2>/dev/null | grep -qx "$APPLET_ID"; then
    kpackagetool6 --type Plasma/Applet --upgrade "$STAGE/$APPLET_ID"
else
    kpackagetool6 --type Plasma/Applet --install "$STAGE/$APPLET_ID"
fi
echo "==> Installed to ~/.local/share/plasma/plasmoids/$APPLET_ID"

if [[ "${1:-}" == "--restart" ]]; then
    echo "==> Restarting plasmashell…"
    if systemctl --user is-active --quiet plasma-plasmashell.service; then
        systemctl --user restart plasma-plasmashell.service
    else
        kquitapp6 plasmashell || true
        (kstart plasmashell >/dev/null 2>&1 &)
    fi
    exit 0
fi

cat <<MSG

Restart the Plasma shell so the system tray picks up the applet:
    systemctl --user restart plasma-plasmashell.service
(or run: ./install.sh --restart)

The icon is enabled in the system tray automatically. If it does not appear:
right-click the tray arrow → Configure System Tray… → Entries → "Cato VPN Tray" → Always shown.
MSG
