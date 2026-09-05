#!/bin/zsh
# Cuts a release: bumps the version, builds Prompter.app in release configuration, signs it,
# zips it, tags the commit, and publishes a GitHub release with notes from CHANGELOG.md.
#
#   Scripts/release.sh 0.9.0            # publish
#   Scripts/release.sh 0.9.0 --dry-run  # build and zip only
#
# Signing: ad-hoc by default. Set DEVELOPER_ID="Developer ID Application: Name (TEAMID)" and
# NOTARY_PROFILE=<notarytool keychain profile> to sign with a Developer ID and notarize.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:$PATH"

VERSION="${1:?usage: release.sh <version> [--dry-run]}"
DRY_RUN=0; [[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1
PLIST=Resources/Info.plist
APP=build/Prompter.app
ZIP="build/Prompter-$VERSION.zip"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "version must look like 1.2.3" >&2; exit 1; }
grep -q "^## \[$VERSION\]" CHANGELOG.md || { echo "CHANGELOG.md has no '## [$VERSION]' section" >&2; exit 1; }
if [[ $DRY_RUN -eq 0 ]]; then
  [[ -z "$(git status --porcelain)" ]] || { echo "working tree not clean" >&2; exit 1; }
  command -v gh >/dev/null || { echo "gh not installed" >&2; exit 1; }
fi

# Version + monotonically increasing build number.
BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$PLIST"

Scripts/build-app.sh release

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --force --deep --options runtime --timestamp --sign "$DEVELOPER_ID" "$APP"
fi
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
if [[ -n "${DEVELOPER_ID:-}" && -n "${NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  rm -f "$ZIP"; ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
fi
echo "built $ZIP ($(du -h "$ZIP" | cut -f1))"

# Release notes: this version's section of the changelog.
NOTES="$(awk -v v="$VERSION" '
  $0 ~ "^## \\["v"\\]" { on=1; next }
  on && /^## \[/ { exit }
  on { print }' CHANGELOG.md | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [[ $DRY_RUN -eq 1 ]]; then
  echo "--- release notes ---"; echo "$NOTES"
  git checkout -- "$PLIST"
  exit 0
fi

git add "$PLIST"
git commit -q -m "Release $VERSION (build $BUILD)"
git tag -a "v$VERSION" -m "Prompter $VERSION"
git push -q origin main "v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "Prompter $VERSION" --notes "$NOTES"
echo "published https://github.com/niel-cody/prompter/releases/tag/v$VERSION"
