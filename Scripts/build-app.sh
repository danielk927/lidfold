#!/bin/bash
# Builds LidFold.app. Only Command Line Tools are required — no Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/LidFold.app"

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/LidFold"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LidFold"
cp "$ROOT/Scripts/Info.plist" "$APP/Contents/Info.plist"

# Ad-hoc signature. Screen Recording consent is bound to the code signature,
# so an unsigned bundle would be re-prompted (and re-denied) on every launch.
# Ad-hoc still changes identity whenever the binary changes, which is why a
# rebuild makes macOS ask for permission again.
echo "==> Signing (ad-hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Built $APP"
echo "    Run it with: open '$APP'"
