#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "▸ Building release binary…"
swift build -c release 2>&1 | tail -2

APP="dist/Timer.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/TimerApp "$APP/Contents/MacOS/TimerApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"

mkdir -p "$APP/Contents/Resources/Sounds"
cp Resources/Sounds/*.caf "$APP/Contents/Resources/Sounds/"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "▸ Generating app icon…"
  swift Scripts/generate_icon.swift dist/AppIcon.iconset
  iconutil -c icns dist/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Code signing (ad-hoc)…"
# TCC (Bedienungshilfen, Automation) keys an ad-hoc signature to the exact
# binary hash, so every rebuild silently revokes the granted permissions. A
# stable self-signed identity keeps them across builds — see README, section
# "Signatur". Falls back to ad-hoc when the identity is absent.
IDENTITY="Timer Local Signing"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY"; then
  codesign --force --deep -s "$IDENTITY" "$APP"
else
  codesign --force --deep -s - "$APP"
fi

echo "▸ Installing…"
pkill -x TimerApp 2>/dev/null || true
TARGET="/Applications/Timer.app"
if [ ! -w /Applications ]; then
  TARGET="$HOME/Applications/Timer.app"
  mkdir -p "$HOME/Applications"
fi
rm -rf "$TARGET"
ditto "$APP" "$TARGET"
echo "✓ Installed: $TARGET"
