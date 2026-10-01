# Contributing

Thanks for taking a look. Timer is a small, opinionated app — bug reports and
focused pull requests are very welcome.

## Before you start

- **Bugs:** open an issue with your macOS version, what you did, and what you
  expected. For anything around the focus block, mention whether the app was in
  fullscreen and whether Accessibility is granted (Settings → Permissions).
- **Features:** please open an issue first. Timer deliberately does few things;
  a short discussion saves you building something that will not be merged.

## Development

```bash
swift build                    # debug build
swift run TimerAppTestRunner   # test suite
./build.sh                     # build, sign and install to /Applications
```

The tests use a small custom runner instead of XCTest, so they run with the
Command Line Tools alone.

## Guidelines

- **Logic goes into `TimerCore` and gets a test.** `TimerApp` gathers state from
  the system and acts on decisions made in `TimerCore`.
- **Every visible string is bilingual:** `tr("Deutsch", "English")`. A missing
  translation should be a compile error, not a blank label.
- **Nothing leaves the Mac.** No network access, no telemetry, no analytics.
- **Gentle by design.** The block hides and switches away; it never quits apps
  or closes work.
- Keep files under 800 lines and functions under 80.
- Commits follow Conventional Commits (`feat:`, `fix:`, `docs:`, `chore:`).
