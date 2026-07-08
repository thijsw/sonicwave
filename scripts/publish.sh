#!/bin/bash
# Publish a Sonicwave release to GitHub Releases (with the app as download):
#
#   scripts/publish.sh <version>        e.g. scripts/publish.sh 0.2.0
#
# Bumps MARKETING_VERSION (+ build number), commits, builds the notarized
# Developer ID zip via scripts/release.sh, tags vX.Y.Z, pushes, and creates
# the GitHub Release with the zip attached and auto-generated notes.
#
# Prerequisites: clean tree on main, `gh auth login` done, and the notary
# keychain profile from scripts/release.sh (the publish gate requires a
# Gatekeeper-accepted artifact — unnotarized builds are refused).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/publish.sh <version, e.g. 0.2.0>}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: version must be X.Y.Z" >&2; exit 2; }

[[ -z "$(git status --porcelain)" ]] || { echo "error: working tree not clean" >&2; exit 1; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "error: publish from main" >&2; exit 1; }
git tag --list | grep -qx "v$VERSION" && { echo "error: tag v$VERSION already exists" >&2; exit 1; }
gh auth status >/dev/null

echo "==> Bumping version to $VERSION"
PBXPROJ=Sonicwave.xcodeproj/project.pbxproj
BUILD_NUM=$(( $(sed -n 's/.*CURRENT_PROJECT_VERSION = \([0-9]*\);.*/\1/p' "$PBXPROJ" | head -1) + 1 ))
sed -i '' "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $VERSION;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $BUILD_NUM;/g" "$PBXPROJ"
git commit -am "release: v$VERSION (build $BUILD_NUM)"

echo "==> Building the notarized release"
scripts/release.sh developer-id

APP="build/export-developer-id/Sonicwave.app"
ZIP="build/Sonicwave-$VERSION.zip"
[[ -f "$ZIP" ]] || { echo "error: expected $ZIP from release.sh" >&2; exit 1; }
spctl --assess --type execute "$APP" || {
  echo "error: artifact is not Gatekeeper-accepted — notarization missing?" >&2
  echo "       (one-time setup is described in scripts/release.sh)" >&2
  exit 1
}

echo "==> Tagging and pushing"
git tag "v$VERSION"
git push origin main "v$VERSION"

echo "==> Creating the GitHub release"
gh release create "v$VERSION" "$ZIP" --title "Sonicwave $VERSION" --generate-notes
gh release view "v$VERSION" --json url -q .url
