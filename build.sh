#!/bin/bash
# Build claude-limits-widget-v<version>.tar.gz — installable plasmoid archive.
# The version is read from metadata.json.
#
# Install the result with:
#   kpackagetool6 -t Plasma/Applet -i claude-limits-widget-v<version>.tar.gz
# or upload it to the KDE Store.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["KPlugin"]["Version"])' "$SRC_DIR/metadata.json")
OUT="$SRC_DIR/claude-limits-widget-v$VERSION.tar.gz"

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp "$SRC_DIR/metadata.json" "$STAGE/"
cp -r "$SRC_DIR/contents" "$STAGE/"
[ -f "$SRC_DIR/LICENSE" ] && cp "$SRC_DIR/LICENSE" "$STAGE/"
chmod +x "$STAGE/contents/code/fetch_limits.sh" \
    "$STAGE/contents/code/fetch_status.sh" \
    "$STAGE/contents/code/fetch_model_limits.sh"

# Archive contents at top level (metadata.json in root) — the layout
# kpackagetool6 and the KDE Store expect.
tar -czf "$OUT" -C "$STAGE" .

echo "Built: $OUT"
tar -tzf "$OUT"
