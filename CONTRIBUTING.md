# Contributing to Timer

Thanks for taking a look. Timer is a small, opinionated app — bug reports and
focused pull requests are very welcome.

## Ways to help

- **Report a bug** — open an [issue](https://github.com/moritzthln/Timer/issues/new/choose)
  with your macOS version, what you did and what you expected. For anything
  around the focus block, mention whether the app was in fullscreen and whether
  Accessibility is granted (Settings → Permissions).
- **Suggest a feature** — please open an issue *before* writing code. Timer
  deliberately does few things; a short discussion saves you building something
  that will not be merged.
- **Pick up an issue** — issues labelled
  [`good first issue`](https://github.com/moritzthln/Timer/labels/good%20first%20issue)
  are small and self-contained. Comment on the issue so nobody does it twice.
- **Translate** — the interface is English and German. Every string lives at its
  call site as `tr("Deutsch", "English")`.

Security problems go through [private reporting](SECURITY.md), never a public issue.

## Setting up

You need macOS 13 or newer and Swift 5.9+. Xcode works; the Command Line Tools
alone (`xcode-select --install`) are enough.

```bash
git clone https://github.com/<your-username>/Timer.git
cd Timer
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

Maintainers only: update `CHANGELOG.md`, bump `CFBundleShortVersionString` in
`Resources/Info.plist`, then push a tag:

```bash
git tag -a v1.1.0 -m "Timer 1.1.0"
git push origin v1.1.0
```

The release workflow runs the tests, builds the universal app and publishes it
with a SHA-256 checksum.

## Code of Conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
