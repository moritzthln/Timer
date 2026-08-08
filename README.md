# Timer

Minimal macOS menu bar countdown timer (personal Onigiri replacement).
Lives in the menu bar only — no Dock icon, no window.

## Usage

- Click the menu bar timer glyph → popover opens.
- Type minutes and press Enter, or click a preset (5/10/15/25/45/60) to start.
- Remaining time shows next to the menu bar icon.
- When time is up: popover opens automatically and a chime plays
  (mute via the speaker toggle in the popover).
- Pause/resume/stop from the popover. Quit via ⌘Q (popover open) or
  right-click the menu bar icon → "Timer beenden".
- A running timer survives app restarts and Mac sleep.

## Build & install

    ./build.sh

Builds a release binary with Swift Package Manager (no Xcode required),
assembles `Timer.app`, ad-hoc signs it, and installs to `/Applications`
(falls back to `~/Applications`).

## Start at login (optional)

System Settings → General → Login Items → "+" → select `Timer.app`.

## Development

    swift run TimerAppTestRunner   # unit tests (custom runner — no XCTest with CLT)
    swift build                    # debug build
    .build/debug/TimerApp          # run unbundled
