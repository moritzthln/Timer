# Timer

Minimal macOS menu bar countdown timer (personal Onigiri replacement).
Lives in the menu bar only — no Dock icon, no window.

## Usage

### Single timer

- Click the menu bar timer glyph → popover opens as one calm view
  (no tabs since v6). The big minute input is auto-focused — type and
  press Enter, hit a preset chip (defaults 5/15/25/45, editable in
  Settings), or click the full-width "Start" button. The chip matching
  the typed value is highlighted.
- The ⌃⌥T → type → Enter flow works exactly as before.
- While running, the menu bar shows **only the time** (no icon);
  paused shows a pause icon plus the time. Settings → Allgemein →
  Menüleiste can switch the time to a compact "25m" format or hide it
  entirely.
- When time is up: popover opens automatically and a ~5-second bell
  swell plays (bundled synthesized sound; mute via "Ton" in the
  popover's "⋯" menu, volume in Settings).
- Pause/resume/stop from the popover; **"+5"** extends a running or
  paused timer by five minutes (up to the 720-minute cap). Quit via ⌘Q
  (popover open), the "⋯" menu → "Timer beenden", or right-click the
  menu bar icon.
- A running timer survives app restarts and Mac sleep.

### Pomodoro mode

- No tab anymore: the full-width chip "Pomodoro · 25 / 5 · 4 Runden"
  (live values from Settings) starts the cycle with one click.
- Cycles focus → break → … automatically; after the configured number of
  rounds the break is a long break, then the cycle restarts. Runs until
  you stop it.
- Every phase change auto-opens the popover. A completed focus phase
  rings the full bell swell; a finished break plays a short soft chime
  (back to work — noticeable, not startling). During breaks the menu
  bar shows a cup symbol next to the time; focus phases show time only.
- Controls while running: Pause/Weiter, **+5** (extend the current
  phase by five minutes), **Skip** (jump to the next phase, silent),
  Stopp — since v9 compact icon pills with tooltips (only "+5" stays
  text).
- Durations and rounds (defaults 25/5/15/4) are configured in Settings;
  changes apply from the next start.
- Sleep or relaunch past phase boundaries fast-forwards to the current
  phase with at most one chime.

### Popover footer

- Left: the **Fokus-Block** shield toggle (icon + caption, green when
  armed). While the shield is on, a single mode chip showing the active
  mode — "Blockieren" or "Nur Erlaubte" — appears next to it (the
  shield collapses to its icon to make room); clicking the chip
  switches to the other mode, the tooltip explains both, the choice
  persists.
- Right: a chart button opening the stats window, and an "⋯" menu with
  "Ton", "Floating Display", "Einstellungen…", and "Timer beenden ⌘Q".
- The old "Heute … · Woche …" caption line is gone — stats live in the
  stats window.

### Floating display

- Draggable always-on-top mini window: time, progress bar, and (in
  Pomodoro mode) the phase. Shows over fullscreen apps and all Spaces.
- Appears whenever a session runs and the floating toggle is on
  (popover "⋯" menu or Settings → "Floating Display"; default on).
- Hover reveals Pause/+5/Stopp (since v9 as icon buttons with
  tooltips); drag anywhere on the panel to move it (position is
  remembered). First appearance: top-right below the menu bar.

### Focus block

- Arm the **Fokus-Block** shield toggle at the left of the popover
  footer (the state sticks). The shield has two modes (v15), switched
  via the mode chip next to it:
  - **Blockieren** (default): while a focus session runs, the block
    intervenes on blocklisted apps and blocklisted websites' tabs.
  - **Nur Erlaubte**: everything *except* the allowed list is blocked —
    regular apps not on the allowed list and browser tabs on non-allowed
    sites. The Timer itself, Finder, and System Settings are always
    allowed; internal/new-tab pages are never touched. Each part guards
    independently: an empty allowed-apps list blocks no apps, an empty
    allowed-domains list blocks no tabs. Mode changes during a session
    apply from the next launch/poll.
- **Gentle since v16 — nothing is destroyed.** A blocked app is hidden
  (macOS "Ausblenden"), never quit: it keeps running with every window
  and unsaved change intact, and everything the block hid reappears
  automatically when the session ends — also on pause, stop, a phase
  change into a break, and when the Timer itself quits. Apps you hid
  yourself stay hidden; re-opening a hidden blocked app during the
  session just hides it again.
- **Fullscreen-proof since v18, actually working since v21.** macOS
  ignores "Ausblenden" for apps in native fullscreen (own Space), so
  every block event walks an escalation ladder instead of hoping:
  hide → check ~0.25 s later whether it worked → if the app is still
  there, pull its windows out of fullscreen (needs the
  Bedienungshilfen permission) and hide again → **if the app is still
  in front, escape its Space** → cover the screen. The permission is
  only ever asked for the first time the second rung is actually
  needed — never at launch, never if plain hiding works.
- **The Space escape (v21)** is the rung that makes fullscreen apps
  blockable at all, and it needs no permission. A background app's
  window is never drawn inside another app's fullscreen Space, so the
  Timer puts its cover on its own Space and then *activates*: macOS
  follows the activated app and takes the screen away from the
  fullscreen app. Half a second later the ladder retries hiding — which
  now usually works — and takes the cover down again, so you land on
  your desktop with the app hidden and restorable as always. It fires
  whenever the app is still in front after the gentler rungs, no matter
  why they failed (Catalyst and Electron windows routinely refuse to
  leave fullscreen even with the permission granted), at most once per
  app per 3 s. ⌘-Tab back in and the 2 s poll pulls you out again.
- **The cover overlay** is both the vehicle of that escape and the last
  resort: an opaque window above everything (including fullscreen
  windows and the menu bar) with the popup's wording — plus "Vollbild
  beendet — zurück zum Fokus." when it came up for an escape. It
  swallows clicks, so the app underneath is unusable, but never the
  keyboard: ⌘Tab to another app and the cover disappears. It also goes
  on session end, pause, shield off, and when the Timer quits.
- **Relentless re-enforcement:** besides the launch and activation
  watchers, the 2 s poll checks whatever app is frontmost right now and
  runs the ladder again. Pushing a blocked app back into fullscreen or
  switching Spaces posts no notification — this tick is what catches it.
- Blocked websites keep their tab: instead of closing it, the browser
  switches to the neighboring tab — or to a fresh empty tab when the
  neighbor is blocked too or the window has only that one tab. The
  blocked tab waits in the background; after the session one click
  resumes it exactly where it was (no ⌘⇧T needed). Re-activating it
  during the session switches away again within ~2 s. Arc only: if
  Arc's scripting rejects the tab switch at runtime, its blocked tabs
  are closed as before — decided automatically, once per session.
- Every intervention shows a small centered popup (replacing the old
  top toast): "Fokus läuft · noch 12:34" and "<App/Website> wartet bis
  zum Ende" — the same wording in both modes. It ignores clicks,
  disappears after 2.5 s, and announces each target at most once per
  10 s.
- Both lists live in Settings → Fokus → Fokus-Block, split into "Blockieren"
  and "Nur Erlaubte" subsections with the same UI: the "App hinzufügen"
  button opens a menu of running apps (or "Andere…" from /Applications),
  the domain field takes entries like `instagram.com` (subdomains match
  automatically) via Enter or "Hinzufügen". Adding the first entry to an
  empty blocklist arms the shield automatically; the first entry into an
  empty allowlist also switches the mode to "Nur Erlaubte". The section
  header shows the live shield state ("Schild: an/aus").
- Website blocking polls the frontmost tab of Safari, Google Chrome, and
  Arc every 2 s via AppleScript — macOS asks for the automation
  permission per browser on first contact; a denied browser is skipped
  silently.
- Pomodoro breaks and paused sessions never block — breaks and stepping
  away are free time (everything hidden is restored on pause too).
- **Honest limits:** this is determined nudging, not enforcement.
  Stopping the timer (or toggling the shield off) lifts the block
  immediately, the cover overlay never locks the keyboard, and there is
  no system-wide network filter — that would need Apple entitlements an
  ad-hoc-signed app cannot get.

### Statistics

- Focus time (running single timers + pomodoro focus phases) is counted
  per day; breaks and pauses are not. Aborting a timer still credits the
  elapsed minutes.
- The chart button in the popover footer opens the stats window
  (freely resizable, default 560 × 560, size and position remembered;
  v9: the minimum size follows the content — the window only shrinks as
  far as everything stays visible). Its "Fokus" tab shows four metric
  tiles — Heute · Diese Woche · **Gesamt** (all-time focus total) ·
  **Ø pro Tag** (all-time ÷ days with focus time, "–" before the first
  one; hover explains the average) — in one row at the default width,
  wrapping 2×2 near the window minimum (v14), a 7-day
  bar chart with the minute value above each bar, and below it a
  12-month GitHub-style heatmap with month labels (today outlined).
  Heatmap shades are relative to the busiest day of the visible year —
  there is no goal to measure against (the daily goal was removed
  in v8).
- Focus totals are stored locally in UserDefaults — kept forever (it is
  tiny).

### Aktivität (activity tracking)

- Always-on local tracking answering three daily questions: **presence**
  (at the Mac from when to when, with gaps — screen lock, sleep, pause,
  and idle time past the threshold don't count), **apps** (which app was
  frontmost, for how long), and **websites** (browser time split by
  domain for Safari, Google Chrome, and Arc — same per-browser
  automation permission as the focus block).
- Stats window → "Aktivität" tab: navigate days with ‹ ›, see the
  presence line ("09:12 – 17:43 · aktiv 6 h 51 min"), a colored day
  timeline of app segments (gaps stay dark), and the app list with
  expandable per-domain breakdowns for browsers. Apps under one minute
  fold into "Sonstige"; empty days show "Keine Daten für diesen Tag".
- v9: the timeline zooms 1–16× (−/＋/1× buttons, trackpad pinch, or
  double-click on a spot; pan by scrolling horizontally), tick labels
  refine from start/mid/end to hourly and quarter-hourly, and hovering
  an app segment shows "App · 9:12–9:47 (35 min)". Zoom resets on date
  change and window reopen.
- v10 — week view: a "Tag | Woche" switcher tops the tab (defaults to
  Tag on every window open). Woche shows the ISO week (Mon–Sun) with a
  ‹ KW 32 · 4.–10. August › header (forward stops at the current week):
  seven slim day rows sharing **one** time axis — from the week's
  earliest first-activity to its latest last-activity, so columns align
  vertically — with hour ticks under the bottom row only, the week
  presence total ("Diese Woche · aktiv 32 h 10 min"), and the app list
  aggregated over the week (same rows, week-aggregated domains). App
  colors rank over week totals, so one app keeps one color in all seven
  rows. Clicking a day row jumps to that day's day view; empty days stay
  as blank rows.
- v10 — drill-down + sparklines: clicking an app row selects it — its
  timeline segments stay at full opacity while all other apps dim
  (day bar and all seven week rows); click again or elsewhere to
  deselect, and navigation or view switches reset the selection. Every
  app row carries a small 7-bar sparkline (the 7 days ending on the
  displayed day, or the displayed week), scaled to that app's own
  7-day maximum.
- v10 — focus traces: an accent line under the timelines marks where
  focus sessions (timer or pomodoro focus) ran; in the day view
  it zooms with the bar and shows "Fokus · 14:02–14:31" on hover.
  Traces exist from v10 onward — earlier focus time was only counted,
  not logged as intervals, and is not backfilled.
- v11 — focus overlay + week zoom: focus windows now also tint the
  timeline bars themselves (a light accent wash with 1 pt edge lines,
  day and week — app segments stay readable underneath), and the traces
  under the bars are thicker. The week view zooms and pans like the day
  view: −/＋/1× buttons, pinch, or double-click, with all seven rows
  moving synchronously while the day labels stay fixed; a single click
  on a row (or its label) still jumps to that day. Zoom resets on week
  navigation and view switches.
- v12 — focus-only filter: a "Nur Fokus-Zeit" checkbox next to the
  Tag | Woche switcher (per window session; survives switches and
  navigation, resets on reopen) narrows the whole tab to what
  overlapped focus sessions: app and domain durations are clipped to
  the focus intervals (week: summed over the seven days), rows with no
  focus time disappear and "Sonstige" folds the clipped rest, the
  header line shows the focus total ("Fokus-Zeit · 2 h 25 min"),
  sparklines use clipped seconds, and the timelines dim everything
  outside focus windows to ~0.15 (the wash and edge lines stay). A day
  or week without focus sessions shows the fully dimmed timeline plus
  "Keine Fokus-Sessions in diesem Zeitraum".
- v13 — promoted websites: a configurable domain list (Settings →
  Aktivität → "Eigene Einträge (Websites)", defaults `instagram.com`
  and `youtube.com`, both removable) whose usage appears as first-class
  rows in the app list instead of hiding inside the browser: label =
  the domain, cross-browser total (Safari + Chrome + Arc merge),
  subdomains match automatically (`m.youtube.com` → `youtube.com`),
  palette color and 7-day sparkline like any app row, clipped like the
  rest under "Nur Fokus-Zeit". The browsers' rows show the remainder
  (their domain breakdowns omit promoted domains), so nothing counts
  twice. The list change is display-time only — history follows the
  current list automatically.
- v14 — usage percentages: every main row of the app list (apps,
  promoted sites, browser remainders, "Sonstige") shows its share of
  the displayed period right of the duration — "2 h 41 min · 39 %".
  The basis is the sum of all rows including the folded rest; with
  "Nur Fokus-Zeit" on it is the focus-time sum, so shares answer "what
  fraction of my focus time went where". Whole percents, tiny shares
  render "<1 %", and the per-domain disclosure rows stay
  percentage-free.
- v19 — website drill-down: promoted rows click like app rows. Select
  instagram.com or youtube.com and the app segments dim while that
  domain's browsing spans light up on top in the row's color — in the
  day bar and in all seven week rows, on the same axis, so they stay
  aligned while you zoom and pan. Spans merge across browsers and
  include subdomains, "Nur Fokus-Zeit" trims them to the focus windows
  like everything else, and hovering one shows "youtube.com ·
  14:02–14:31 (29 min)". Click again to deselect; navigation and view
  switches reset it, exactly as for apps.
- v20 — the timeline mirrors the list: promoted time is cut out of the
  browser's bar and drawn in its own row color, always — not only while
  something is selected. A Chrome bar with two YouTube visits now reads
  as Chrome · YouTube · Chrome · YouTube · Chrome instead of one solid
  block, in the day bar and in all seven week rows. Selecting Chrome
  lights up only what is really Chrome, hovering a cut-out piece shows
  the site tooltip, and the numbers in the list and the colors in the
  bar finally tell the same story. Non-promoted domains keep living
  inside their browser.
- v21 — fullscreen apps are blockable at all: the block no longer draws
  into a Space you cannot see, it takes the screen away from the
  fullscreen app by activating the Timer, then hides the app and gets
  out of the way. Works without any permission, catches you again ~2 s
  after every ⌘-Tab back, and can be tried on demand in Rechte →
  "Vollbild-Block testen".
- **Privacy:** everything stays on this Mac — one JSON file per day
  under `~/Library/Application Support/Timer/activity/` (and, since
  v10, focus intervals under `…/Timer/focus/`), no network, ever.
  macOS exposes only the *age* of the last input, never what was
  typed or clicked.
- **Honest limits:** tracking runs only while the app runs (enable
  launch at login); Firefox has no automation interface and appears as
  a whole app without domain breakdown.
- Pause any time via Settings → Aktivität ("Tracking pausieren");
  paused stretches render as gaps. The idle threshold ("Inaktiv nach")
  defaults to 5 minutes (1–30).

### Nicht stören (do not disturb)

- Opt-in coupling to the macOS Focus mode via two Shortcuts. v8: pick
  them from two dropdowns listing your existing Shortcuts (refresh
  button included) — no more typing exact names. Defaults stay
  "Timer Fokus an" / "Timer Fokus aus", so v7 setups keep working.
- On at focus start, off at pause/stop/break; best-effort off when the
  app quits while a focus phase is active.
- Settings → Fokus → Nicht stören has the toggle, the two dropdowns, setup
  instructions (for users who have no suitable shortcut yet), a test
  button per shortcut, and a one-line status when a shortcut is missing
  or fails.

### Global hotkeys

Three system-wide shortcuts, configured in Settings → Allgemein →
Hotkeys (click a recorder field, press a combo with ⌘/⌃/⌥; Esc
cancels, "×" clears):

- **Popover öffnen** — opens the popover with the input focused.
- **Sofort-Start** — idle: starts the last duration; running: pauses;
  paused: resumes; finished: dismisses and starts the last duration.
- **Verlängern (+5 min)** — extends a running/paused timer; does
  nothing otherwise. Opt-in: no default combo (avoids collisions).

### Settings

Open via the popover's "⋯" menu → "Einstellungen…". Since v17 the
window is split into tabs behind a segmented switcher at the top —
**Timer**, **Fokus**, **Aktivität**, **Allgemein**, and since v18
**Rechte** (opens on Timer; the window height fits the tallest tab, so
nothing scrolls at default size). All changes save immediately — since v9 the number
fields save while you type, and input that does not parse into the
allowed range snaps back to the stored value when you leave the field
(switching tabs counts as leaving the field).

Tab **Timer**:

- **Presets:** the four quick-start chips (1–720 min each). A custom
  six-preset set from before v6 falls back to the 5/15/25/45 default
  (documented migration) — re-save your favorites once.
- **Pomodoro:** focus/break/long-break minutes (1–720) and rounds until
  long break (1–12).
- **Alarm:** volume slider + test button — the test plays the ~5 s
  bell swell (the mute toggle sits in the popover's "⋯" menu). The two
  alarm sounds are bundled .caf files; if they are missing the app
  falls back to the old four-chime Glass sequence, never silence.

Tab **Fokus**:

- **Fokus-Block:** two subsections since v15. "Blockieren" holds the
  blocked apps ("App hinzufügen" menu + "Andere…" file picker; the
  Timer itself, Finder, and the default browser are not blockable) and
  blocked domains (Enter or "Hinzufügen" commits; the list shows
  exactly what was stored). "Nur Erlaubte" holds the allowed apps and
  domains with the identical UI (the always-allowed Timer/Finder/System
  Settings are hidden from its picker; browsers are pickable) plus the
  caption "Leere Liste = dieser Teil blockt nichts." The first entry
  arms the shield automatically — an allowlist entry also switches the
  mode —, the header shows "Schild: an/aus", and captions explain when
  blocking is active and the automation permission.
- **Nicht stören:** the DND toggle, the two shortcut dropdowns with a
  refresh button, setup instructions, and the two test buttons.

Tab **Aktivität**:

- **Aktivität:** "Tracking pausieren" toggle (pausing fully stops the
  polling — no background wakeups while paused), the idle threshold
  "Inaktiv nach (min)" (1–30, default 5), and v13 "Eigene Einträge
  (Websites)" — the promoted-websites list (same domain UI as the
  block list: Enter or "Hinzufügen" commits, rows removable, the list
  shows exactly what was stored; an emptied list stays empty).

Tab **Allgemein**:

- **Allgemein:** "Beim Anmelden starten" with a live status line —
  "Aktiv", "Wartet auf Freigabe" (plus a button opening the Login
  Items pane), or "Aktiv (LaunchAgent)" when macOS rejected
  `SMAppService` and the app fell back to a user LaunchAgent
  (`~/Library/LaunchAgents/com.moritzthelen.timer.plist`). Toggling
  off removes whichever mechanism is active. Plus the floating display
  toggle.
- **Menüleiste:** time format "Standard" (24:37) or "Kompakt" (whole
  minutes rounded up — "25m", "1h 5m"), and "Nur Symbol" hiding the
  time entirely (each state keeps a distinguishable icon; caption
  recommends the floating display).
- **Hotkeys:** three recorder fields (popover, quick-start, extend);
  duplicate combos are rejected with an inline hint.

Tab **Rechte** (v18) — every permission the app depends on, in one
place, because macOS resets some of them on a reinstall. One row per
item with a traffic-light badge (green granted/active, amber
unknown/browser not open, red missing; hover for a one-line
explanation) and its buttons:

- **Bedienungshilfen (Vollbild-Block):** read live via
  `AXIsProcessTrusted()` (never prompts), "Öffnen" jumps into System
  Settings → Privacy → Accessibility. Nice to have, not required since
  v21 — the Space escape works without it.
- **Vollbild-Block testen (v21):** "Testen" starts a 3 s countdown —
  switch into the app you want to check (fullscreen is the interesting
  case) and the complete ladder runs against it once, without a block
  list and without a running session. The result appears in the
  caption: "WhatsApp — Space gewechselt", "… versteckt", "… aus
  Vollbild geholt", "… kein Eingriff nötig" or "… überdeckt". The
  tested app stays hidden, exactly as a real block would leave it (one
  Dock click brings it back); the cover comes down on its own.
- **Automation: Safari / Google Chrome / Arc:** one row each.
  "Prüfen" runs a harmless read against the **running** browser — the
  first one may raise the one-time macOS consent prompt, which is
  exactly why nothing is probed automatically when the tab opens.
  A browser that is not running reports "Browser nicht geöffnet".
- **Kurzbefehle (Nicht stören):** checks that both configured shortcut
  names appear in `shortcuts list`; the caption points to the Fokus tab
  where they are selected.
- **Beim Anmelden starten:** the same status as the Allgemein tab, with
  a button into Login Items.

"Alle prüfen" in the header re-runs everything at once. The
non-prompting checks (Accessibility, login item, shortcuts list) also
run when the window opens.

## Build & install

    ./build.sh

Builds a release binary with Swift Package Manager (no Xcode required),
assembles `Timer.app`, ad-hoc signs it, and installs to `/Applications`
(falls back to `~/Applications`).

## Start at login

Settings → Allgemein → "Beim Anmelden starten". The status line under
the toggle shows which mechanism is active; "Wartet auf Freigabe"
offers a button into System Settings → Login Items. If `SMAppService`
refuses the ad-hoc-signed app entirely, a user LaunchAgent takes over
automatically. A duplicate-start guard quits a second instance
immediately, so the two mechanisms can never double-launch the app.

## Development

    swift run TimerAppTestRunner   # unit tests (custom runner — no XCTest with CLT)
    swift build                    # debug build
    .build/debug/TimerApp          # run unbundled
