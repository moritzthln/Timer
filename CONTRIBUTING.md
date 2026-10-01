# Contributing to Timer

Thanks for taking a look. Timer is a small, opinionated app — bug reports and
focused pull requests are very welcome.

## Ways to help

- **Report a bug** — open an [issue](https://github.com/moritzthln/focus-timer-mac/issues/new/choose)
  with your macOS version, what you did and what you expected. For anything
  around the focus block, mention whether the app was in fullscreen and whether
  Accessibility is granted (Settings → Permissions).
- **Suggest a feature** — please open an issue *before* writing code. Timer
  deliberately does few things; a short discussion saves you building something
  that will not be merged.
- **Pick up an issue** — issues labelled
  [`good first issue`](https://github.com/moritzthln/focus-timer-mac/labels/good%20first%20issue)
  are small and self-contained. Comment on the issue so nobody does it twice.
- **Translate** — the interface is English and German. Every string lives at its
  call site as `tr("Deutsch", "English")`.

Security problems go through [private reporting](SECURITY.md), never a public issue.

By contributing you agree that your contribution is licensed under the
project's [PolyForm Noncommercial License](LICENSE), like the rest of the code.

## Setting up

You need macOS 13 or newer and Swift 5.9+. Xcode works; the Command Line Tools
alone (`xcode-select --install`) are enough.

```bash
git clone https://github.com/<your-username>/focus-timer-mac.git
cd focus-timer-mac
swift build                    # debug build
swift run TimerAppTestRunner   # test suite
./build.sh                     # build, sign and install to /Applications
```

The tests use a small custom runner instead of XCTest, so they run without Xcode.

A debug build started from the terminal (`.build/debug/TimerApp`) keeps its
settings separate from an installed Timer. The activity history in
`~/Library/Application Support/Timer/` is shared, though — pause tracking in the
debug build's settings if you do not want it to write there.

## Workflow

1. **Fork** the repository and create a branch from `main`:
   `feat/short-name`, `fix/short-name` or `docs/short-name`.
2. **Make your change** in small, focused commits.
3. **Run the tests** — `swift run TimerAppTestRunner` must pass.
4. **Open a pull request** against `main`. The template asks for what, why and
   how you tested; CI builds the app and runs the suite automatically.
5. A maintainer reviews. Small follow-up commits on the same branch are fine;
   the pull request is squash-merged at the end.

### Commit messages

[Conventional Commits](https://www.conventionalcommits.org/), in English and in
the imperative:

```
feat: add a weekly goal to the statistics
fix: keep the popover anchored after a phase change
docs: explain the Automation permission
```

The body explains *why*, not what — the diff already shows what.

## Code guidelines

- **Logic belongs in `TimerCore` and gets a test.** `TimerApp` gathers state from
  the system and acts on decisions made in `TimerCore`. If something can be
  decided without AppKit, it should be.
- **Every visible string is bilingual:** `tr("Deutsch", "English")`. A missing
  translation should be a compile error, not a blank label.
- **Nothing leaves the Mac.** No network access, no telemetry, no analytics.
- **Gentle by design.** The focus block hides and switches away; it never quits
  apps or closes the user's work.
- **Size limits:** files under 800 lines, functions under 80. Split along a real
  seam when you get close.
- **Comments explain why.** Especially around macOS behaviour that surprised
  you — the next person will hit the same surprise.

## Releases

The project uses [Semantic Versioning](https://semver.org/): `patch` for fixes,
`minor` for new features, `major` for changes that break existing behaviour.

Every pull request adds a line to the `[Unreleased]` section of
[`CHANGELOG.md`](CHANGELOG.md). A maintainer then cuts a release with one command:

```bash
Scripts/release.sh patch     # or minor / major / an explicit 1.4.2
```

The script refuses to run unless `main` is clean and in sync, and unless the
changelog actually says what changed. It runs the tests, bumps the version in
`Resources/Info.plist`, dates the changelog entry, commits, tags and pushes.
The tag starts the release workflow, which checks that tag and app version
match, builds the universal app and publishes it on GitHub Releases with the
changelog entry as release notes.
