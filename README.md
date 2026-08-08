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

### Focus block

- Arm the **Fokus-Block** shield toggle in the popover (Timer or Pomodoro
  tab; the last state sticks). While a focus session runs, blocklisted
  apps are terminated and blocklisted websites' tabs are closed, each with
  a short "Geblockt: …" toast at the top of the screen.
- Blocklists live in Settings → Fokus-Block: pick running apps from a
  menu (or "Andere…" from /Applications) and add domains like
  `instagram.com` (subdomains match automatically).
- Website blocking polls the frontmost tab of Safari, Google Chrome, and
  Arc every 2 s via AppleScript — macOS asks for the automation
  permission per browser on first contact; a denied browser is skipped
  silently.
- Pomodoro breaks and paused sessions never block — breaks and stepping
  away are free time. Apps with unsaved changes are asked to quit, never
  force-killed.
- **Honest limits:** this is determined nudging, not enforcement.
  Stopping the timer (or toggling the shield off) lifts the block
  immediately, and there is no system-wide network filter — that would
  need Apple entitlements an ad-hoc-signed app cannot get.

### Statistics

- Focus time (running single timers + pomodoro focus phases) is counted
  per day; breaks and pauses are not. Aborting a timer still credits the
  elapsed minutes.
- The popover's idle view shows "Heute … · Woche …" under the presets;
  click it (or the chart icon in the footer) for the stats window:
  today/week tiles plus a 7-day bar chart.
- Data is stored locally in UserDefaults and kept forever (it is tiny).

### Global hotkeys

Two system-wide shortcuts, configured in Settings → Hotkeys (click a
recorder field, press a combo with ⌘/⌃/⌥; Esc cancels, "×" clears):

- **Popover öffnen** — opens the popover with the input focused.
- **Sofort-Start** — idle: starts the last duration; running: pauses;
  paused: resumes; finished: dismisses and starts the last duration.

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
- **Fokus-Block:** blocked apps (running-apps menu + "Andere…" file
  picker; the Timer itself, Finder, and the default browser are not
  blockable) and blocked domains, with a hint about the automation
  permission.
- **Hotkeys:** the two recorder fields; duplicate combos are rejected
  with an inline hint.

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
