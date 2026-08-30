#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) Timer.app and zips it for sharing.
# Unlike build.sh this never touches /Applications — the result lands in share/.
set -euo pipefail
cd "$(dirname "$0")"

# Works on both toolchains. `swift build --arch` needs full Xcode (xcbuild);
# with Command Line Tools selected we build each slice by triple and lipo them
# together. The active toolchain decides, not what happens to be installed.
if [ -x "$(xcode-select -p 2>/dev/null)/usr/bin/xcodebuild" ]; then
  echo "▸ Building universal release binary (Xcode toolchain)…"
  swift build -c release --arch arm64 --arch x86_64 2>&1 | tail -1
  BINARY=".build/apple/Products/Release/TimerApp"
else
  echo "▸ Building both slices (Command Line Tools)…"
  swift build -c release --triple arm64-apple-macosx13.0 2>&1 | tail -1
  swift build -c release --triple x86_64-apple-macosx13.0 2>&1 | tail -1
  BINARY="$(mktemp -d)/TimerApp"
  lipo -create ".build/arm64-apple-macosx/release/TimerApp" \
       ".build/x86_64-apple-macosx/release/TimerApp" -output "$BINARY"
fi

APP="share/Timer.app"
rm -rf share
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sounds"

cp "$BINARY" "$APP/Contents/MacOS/TimerApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Sounds/*.caf "$APP/Contents/Resources/Sounds/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Code signing (ad-hoc)…"
# Ad-hoc on purpose: this bundle is for other Macs, where a locally
# self-signed identity would be an unknown issuer rather than a known
# non-signature. The local install (build.sh) is the one that wants a stable
# identity, because TCC hangs its permissions on it.
codesign --force --deep -s - "$APP"

cat > share/INSTALLATION.txt <<'TXT'
Timer — Installation
====================

The app speaks English or German. It follows your system language, and you
can change it any time under Settings -> General -> Language.

1. Drag Timer.app into your "Applications" folder.

2. IMPORTANT on first launch: do NOT double-click. Right-click Timer.app ->
   "Open" -> in the dialog, click "Open" again. (The app is not signed
   through the App Store, so macOS asks once. After that a double-click
   works normally.)

   If macOS claims the app is "damaged", run this once in Terminal:

       xattr -dr com.apple.quarantine /Applications/Timer.app

3. The app lives in the menu bar at the top right — there is no Dock icon.
   Click the timer symbol to open it.

4. Permissions: Settings (the "..." menu -> Settings...) -> "Permissions" tab
   lists what is needed for what:
   - Automation (Safari/Chrome/Arc): website statistics + website blocking
   - Accessibility: taking blocked apps out of fullscreen
   - Shortcuts: the optional "Do Not Disturb" coupling
   None of it is required — the timer, pomodoro and statistics work without.

   Note: macOS ties these permissions to the exact app binary, so after
   installing a newer version you may have to grant Accessibility again
   (System Settings -> Privacy & Security -> Accessibility: remove the old
   "Timer" entry with "-", add the new one with "+").

Requires macOS 13 or newer (Apple Silicon and Intel).
All data stays local on your Mac; the app never sends anything anywhere.


Deutsch
=======

1. Timer.app in den Ordner "Programme" ziehen.
2. Beim ersten Start NICHT doppelklicken: Rechtsklick -> "Öffnen" -> im
   Dialog nochmal "Öffnen". Bei der Meldung "beschädigt" hilft im Terminal:
   xattr -dr com.apple.quarantine /Applications/Timer.app
3. Die App sitzt oben rechts in der Menüleiste, ohne Dock-Symbol.
4. Rechte im Tab "Rechte"; nichts davon ist Pflicht. Sprache umstellen unter
   Einstellungen -> Allgemein -> Sprache.
TXT

echo "▸ Zipping…"
(cd share && ditto -c -k --sequesterRsrc --keepParent Timer.app Timer.zip)

echo "✓ Fertig:"
echo "  $(pwd)/share/Timer.zip"
echo "  $(pwd)/share/INSTALLATION.txt"
lipo -info "$APP/Contents/MacOS/TimerApp"
