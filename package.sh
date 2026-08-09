#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) Timer.app and zips it for sharing.
# Unlike build.sh this never touches /Applications — the result lands in share/.
set -euo pipefail
cd "$(dirname "$0")"

# Universal builds via `swift build --arch` need full Xcode (xcbuild); with
# Command Line Tools only we build each slice by triple and lipo them together.
echo "▸ Building Apple Silicon slice…"
swift build -c release --triple arm64-apple-macosx13.0 2>&1 | tail -1
echo "▸ Building Intel slice…"
swift build -c release --triple x86_64-apple-macosx13.0 2>&1 | tail -1

ARM=".build/arm64-apple-macosx/release/TimerApp"
INTEL=".build/x86_64-apple-macosx/release/TimerApp"
BINARY="$(mktemp -d)/TimerApp"
echo "▸ Merging into a universal binary…"
lipo -create "$ARM" "$INTEL" -output "$BINARY"

APP="share/Timer.app"
rm -rf share
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Sounds"

cp "$BINARY" "$APP/Contents/MacOS/TimerApp"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Sounds/*.caf "$APP/Contents/Resources/Sounds/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Code signing (ad-hoc)…"
codesign --force --deep -s - "$APP"

cat > share/INSTALLATION.txt <<'TXT'
Timer — Installation
====================

1. Timer.app in den Ordner "Programme" ziehen.

2. WICHTIG beim ersten Start: NICHT doppelklicken, sondern
   Rechtsklick auf Timer.app -> "Öffnen" -> im Dialog nochmal "Öffnen".
   (Die App ist nicht über den App Store signiert, deshalb fragt macOS
   einmalig nach. Danach startet sie normal per Doppelklick.)

   Falls macOS meldet, die App sei "beschädigt": einmal dieses Kommando
   im Programm "Terminal" ausführen (kopieren, Enter):

       xattr -dr com.apple.quarantine /Applications/Timer.app

3. Die App erscheint oben rechts in der Menüleiste (kein Dock-Symbol).
   Klick auf das Timer-Symbol öffnet die Bedienung.

4. Berechtigungen: Einstellungen (⋯ -> Einstellungen…) -> Tab "Rechte".
   Dort steht, was wofür gebraucht wird:
   - Automation (Safari/Chrome/Arc): Website-Statistik + Website-Block
   - Bedienungshilfen: Blocken von Apps im Vollbild
   - Kurzbefehle: optionale "Nicht stören"-Kopplung
   Nichts davon ist Pflicht — ohne die Rechte funktionieren Timer,
   Pomodoro und Statistik trotzdem.

Voraussetzung: macOS 13 oder neuer (Apple Silicon und Intel).
Alle Daten bleiben lokal auf dem Mac, die App sendet nichts ins Netz.
TXT

echo "▸ Zipping…"
(cd share && ditto -c -k --sequesterRsrc --keepParent Timer.app Timer.zip)

echo "✓ Fertig:"
echo "  $(pwd)/share/Timer.zip"
echo "  $(pwd)/share/INSTALLATION.txt"
lipo -info "$APP/Contents/MacOS/TimerApp"
