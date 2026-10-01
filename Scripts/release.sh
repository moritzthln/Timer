#!/usr/bin/env bash
# Cuts a release: tests, version bump, changelog, commit, tag, push.
# The tag push triggers .github/workflows/release.yml, which builds the
# universal app and publishes it on GitHub Releases.
#
#   Scripts/release.sh patch        1.0.0 -> 1.0.1   bug fixes
#   Scripts/release.sh minor        1.0.0 -> 1.1.0   new features
#   Scripts/release.sh major        1.0.0 -> 2.0.0   breaking changes
#   Scripts/release.sh 1.4.2        an explicit version
#
# Add --yes to skip the final confirmation.
set -euo pipefail
cd "$(dirname "$0")/.."

PLIST="Resources/Info.plist"
CHANGELOG="CHANGELOG.md"
REPO_URL="https://github.com/moritzthln/Timer"

fail() { echo "✗ $*" >&2; exit 1; }

BUMP="${1:-}"
CONFIRM=1
[[ "${2:-}" == "--yes" || "${1:-}" == "--yes" ]] && CONFIRM=0
[[ -z "$BUMP" || "$BUMP" == "--yes" ]] && fail "usage: Scripts/release.sh <patch|minor|major|X.Y.Z> [--yes]"

# --- Preconditions: a release is always cut from a clean, current main.
[[ "$(git branch --show-current)" == "main" ]] || fail "releases are cut from main"
[[ -z "$(git status --porcelain)" ]] || fail "working tree is not clean"
git fetch -q origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] \
  || fail "main is not in sync with origin/main — pull or push first"

CURRENT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
IFS=. read -r MAJ MIN PAT <<< "$CURRENT"
case "$BUMP" in
  patch) NEXT="$MAJ.$MIN.$((PAT + 1))" ;;
  minor) NEXT="$MAJ.$((MIN + 1)).0" ;;
  major) NEXT="$((MAJ + 1)).0.0" ;;
  *)     [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "not a version: $BUMP"
         NEXT="$BUMP" ;;
esac
git rev-parse -q --verify "refs/tags/v$NEXT" >/dev/null && fail "tag v$NEXT already exists"

# --- The changelog must say what is in the release.
UNRELEASED="$(awk '/^## \[Unreleased\]/{f=1;next} /^## \[/{f=0} f' "$CHANGELOG" | grep -v '^[[:space:]]*$' || true)"
[[ -n "$UNRELEASED" ]] || fail "the [Unreleased] section of $CHANGELOG is empty — describe the changes first"

echo "Release $CURRENT → $NEXT (build $((BUILD + 1)))"
echo
echo "$UNRELEASED"
echo
if (( CONFIRM )); then
  read -r -p "Tag and publish v$NEXT? [y/N] " answer
  [[ "$answer" == [yY] ]] || fail "aborted"
fi

echo "▸ Running tests…"
swift run TimerAppTestRunner 2>&1 | tail -1 | grep -q " 0 failures" || fail "tests failed"

echo "▸ Bumping version…"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEXT" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"

echo "▸ Dating the changelog…"
TODAY="$(date +%Y-%m-%d)"
python3 - "$CHANGELOG" "$CURRENT" "$NEXT" "$TODAY" "$REPO_URL" <<'PY'
import sys, re
path, prev, nxt, today, url = sys.argv[1:]
s = open(path).read()
s = s.replace("## [Unreleased]", f"## [Unreleased]\n\n## [{nxt}] - {today}", 1)
s = re.sub(r"^\[Unreleased\]: .*$",
           f"[Unreleased]: {url}/compare/v{nxt}...HEAD\n[{nxt}]: {url}/compare/v{prev}...v{nxt}",
           s, count=1, flags=re.M)
open(path, "w").write(s)
PY

git add "$PLIST" "$CHANGELOG"
git commit -q -m "chore(release): v$NEXT"
git tag -a "v$NEXT" -m "Timer $NEXT"
git push -q origin main "v$NEXT"

echo "✓ v$NEXT pushed. GitHub is building the release:"
echo "  $REPO_URL/actions/workflows/release.yml"
