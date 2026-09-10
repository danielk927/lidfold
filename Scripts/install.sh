#!/bin/bash
# Builds LidFold and installs it to /Applications. Only Command Line Tools are
# required — no Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/Applications/LidFold.app"

if ! xcode-select -p >/dev/null 2>&1; then
    echo "Xcode Command Line Tools are needed. Install them with:" >&2
    echo "    xcode-select --install" >&2
    exit 1
fi

"$ROOT/Scripts/build-app.sh"

echo "==> Installing to $DEST"
# A copy that is currently running can't be replaced cleanly.
pkill -f "LidFold.app/Contents/MacOS/LidFold" >/dev/null 2>&1 || true
sleep 1
rm -rf "$DEST"
cp -R "$ROOT/LidFold.app" "$DEST"

echo "==> Launching"
open "$DEST"

cat <<'DONE'

LidFold is running — look for the laptop icon in your menu bar.

macOS will ask for Screen Recording access. Grant it, then quit LidFold from
the menu bar icon and open it again from /Applications: the permission only
takes effect on the next launch.

Then just close your lid.
DONE
