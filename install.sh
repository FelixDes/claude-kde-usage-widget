#!/bin/bash
# Install, update, or remove the Claude Limits plasmoid for the current user.
#
# Usage:
#   ./install.sh             # install or update (auto-detected)
#   ./install.sh --restart   # same, then restart plasmashell
#   ./install.sh remove      # uninstall
set -euo pipefail

PLUGIN_ID="org.kde.plasma.claudelimits"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ACTION="install"
RESTART=false
for arg in "$@"; do
    case "$arg" in
        remove|uninstall) ACTION="remove" ;;
        --restart)        RESTART=true ;;
        -h|--help)        sed -n '2,8p' "$0"; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

KPKG=$(command -v kpackagetool6 || command -v kpackagetool5) \
    || { echo "Error: kpackagetool6 not found (install plasma-sdk or kpackage)" >&2; exit 1; }

is_installed() {
    "$KPKG" -t Plasma/Applet -l 2>/dev/null | grep -qx "$PLUGIN_ID"
}

restart_shell() {
    echo "Restarting plasmashell..."
    if systemctl --user restart plasma-plasmashell.service 2>/dev/null; then
        return
    fi
    kquitapp6 plasmashell 2>/dev/null || killall plasmashell 2>/dev/null || true
    nohup plasmashell --replace >/dev/null 2>&1 &
    disown
}

if [ "$ACTION" = "remove" ]; then
    if is_installed; then
        "$KPKG" -t Plasma/Applet -r "$PLUGIN_ID"
        echo "Removed $PLUGIN_ID"
    else
        echo "$PLUGIN_ID is not installed"
    fi
    $RESTART && restart_shell
    exit 0
fi

# Stage only package files so .git/.idea/tarballs don't get installed
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp "$SRC_DIR/metadata.json" "$STAGE/"
cp -r "$SRC_DIR/contents" "$STAGE/"
chmod +x "$STAGE/contents/code/fetch_limits.sh"

if is_installed; then
    "$KPKG" -t Plasma/Applet -u "$STAGE"
    echo "Updated $PLUGIN_ID"
else
    "$KPKG" -t Plasma/Applet -i "$STAGE"
    echo "Installed $PLUGIN_ID"
fi

if $RESTART; then
    restart_shell
else
    echo "Tip: run with --restart (or run 'plasmashell --replace &') to reload the widget"
fi
