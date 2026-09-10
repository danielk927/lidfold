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

# Screen Recording consent is bound to the code signature. An ad-hoc signature
# is keyed to the binary's own hash, so every rebuild looks like a brand new app
# and macOS re-prompts. A real signing identity is stable across rebuilds, so
# the grant sticks. Set CODESIGN_IDENTITY to override the auto-detected one.
IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application|Apple Development/ { print $2; exit }')}"

if [ -n "$IDENTITY" ]; then
    echo "==> Signing ($IDENTITY)"
    codesign --force --deep --sign "$IDENTITY" "$APP"
else
    echo "==> Signing (ad-hoc — no identity found; expect a permission re-prompt per rebuild)"
    codesign --force --deep --sign - "$APP"
fi

echo "==> Built $APP"
echo "    Run it with: open '$APP'"
