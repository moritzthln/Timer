# Timer

Minimal macOS menu bar countdown timer (personal Onigiri replacement).
Lives in the menu bar only — no Dock icon, no window.

## Usage

### Single timer

- Click the menu bar timer glyph → popover opens (Timer tab).
- Type minutes and press Enter, or click a preset chip to start
  (presets editable in Settings, defaults 5/10/15/25/45/60).
- While running, the menu bar shows **only the time** (no icon);
  paused shows a pause icon plus the time.
- When time is up: popover opens automatically and a chime plays
  (mute via the speaker toggle in the popover, volume in Settings).
- Pause/resume/stop from the popover. Quit via ⌘Q (popover open) or
  right-click the menu bar icon → "Timer beenden".
- A running timer survives app restarts and Mac sleep.

### Pomodoro mode

- Switch the popover to the **Pomodoro** tab and hit "Pomodoro starten".
- Cycles focus → break → … automatically; after the configured number of
  rounds the break is a long break, then the cycle restarts. Runs until
  you stop it.
- Every phase change: chime + popover auto-opens. During breaks the menu
  bar shows a cup symbol next to the time; focus phases show time only.
- Controls while running: Pause/Weiter, **Skip** (jump to the next phase,
  silent), Stopp.
- Durations and rounds (defaults 25/5/15/4) are configured in Settings;
  changes apply from the next start.
- Sleep or relaunch past phase boundaries fast-forwards to the current
  phase with at most one chime.

### Floating display

- Draggable always-on-top mini window: time, progress bar, and (in
  Pomodoro mode) the phase. Shows over fullscreen apps and all Spaces.
- Appears whenever a session runs and the floating toggle is on
  (popover footer icon or Settings → "Floating Display"; default on).
- Hover reveals Pause/Stopp; drag anywhere on the panel to move it
  (position is remembered). First appearance: top-right below the menu bar.

### Settings

Open via the "⋯" button in the popover footer. All changes save
immediately:

- **Presets:** the six quick-start chips (1–720 min each).
- **Pomodoro:** focus/break/long-break minutes (1–720) and rounds until
  long break (1–12).
- **Alarm:** chime volume slider + test button (mute toggle stays in the
  popover).
- **Allgemein:** "Beim Anmelden starten" (launch at login via
  `SMAppService`; if macOS rejects the ad-hoc-signed app an inline hint
  shows the manual path) and the floating display toggle.

## Build & install

    ./build.sh

Builds a release binary with Swift Package Manager (no Xcode required),
assembles `Timer.app`, ad-hoc signs it, and installs to `/Applications`
(falls back to `~/Applications`).

## Start at login

Settings → Allgemein → "Beim Anmelden starten". Manual fallback:
System Settings → General → Login Items → "+" → select `Timer.app`.

## Development

    swift run TimerAppTestRunner   # unit tests (custom runner — no XCTest with CLT)
    swift build                    # debug build
    .build/debug/TimerApp          # run unbundled
