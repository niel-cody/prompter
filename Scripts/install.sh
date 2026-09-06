#!/bin/bash
# Installs the latest Prompter release into /Applications.
#
#   curl -fsSL https://raw.githubusercontent.com/niel-cody/prompter/main/Scripts/install.sh | bash
#
# Prompter isn't notarized by Apple yet, so a build downloaded through a browser is
# quarantined and macOS refuses to open it. This script fetches the release directly and
# clears that flag, so the app opens normally. Read it before you run it — that is the
# right instinct for any install one-liner.
set -euo pipefail

REPO="niel-cody/prompter"
APP="/Applications/Prompter.app"
MIN_MAJOR=26

say() { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# 1. Will it even run here?
OS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
if [ "$OS_MAJOR" -lt "$MIN_MAJOR" ]; then
  fail "Prompter needs macOS $MIN_MAJOR or later; this Mac is on $(sw_vers -productVersion).
       Its speech engine (SpeechAnalyzer) only exists on macOS $MIN_MAJOR+."
fi
say "✓ macOS $(sw_vers -productVersion) on $(uname -m)"

# 2. Find the latest release.
say "Looking up the latest release…"
API="https://api.github.com/repos/$REPO/releases/latest"
JSON="$(curl -fsSL -H 'Accept: application/vnd.github+json' "$API")" \
  || fail "couldn't reach GitHub. Check your connection."
URL="$(printf '%s' "$JSON" | /usr/bin/python3 -c '
import json,sys
r = json.load(sys.stdin)
z = [a["browser_download_url"] for a in r.get("assets", []) if a["name"].endswith(".zip")]
print(z[0] if z else "")')"
TAG="$(printf '%s' "$JSON" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("tag_name",""))')"
[ -n "$URL" ] || fail "the latest release has no .zip asset."
say "✓ found $TAG"

# 3. Download and unpack.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
say "Downloading…"
curl -fsSL --progress-bar -o "$TMP/Prompter.zip" "$URL" || fail "download failed."
ditto -x -k "$TMP/Prompter.zip" "$TMP/unpacked" || fail "couldn't unzip the download."
[ -d "$TMP/unpacked/Prompter.app" ] || fail "the download didn't contain Prompter.app."

# 4. Quit any running copy, wherever it was launched from, and wait for it to go.
if pgrep -x Prompter >/dev/null 2>&1; then
  say "Quitting the running copy…"
  osascript -e 'quit app "Prompter"' >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do
    pgrep -x Prompter >/dev/null 2>&1 || break
    sleep 0.25
  done
  pgrep -x Prompter >/dev/null 2>&1 && pkill -x Prompter 2>/dev/null || true
  for _ in $(seq 1 20); do
    pgrep -x Prompter >/dev/null 2>&1 || break
    sleep 0.25
  done
fi

# 5. Replace any existing copy.
[ -d "$APP" ] && { rm -rf "$APP" || fail "couldn't remove $APP. Quit Prompter and try again."; }
ditto "$TMP/unpacked/Prompter.app" "$APP" || fail "couldn't copy into /Applications."

# 6. Clear the quarantine flag so the app opens without a Gatekeeper detour.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

say ""
say "✓ Installed $APP ($TAG)"
say ""
say "Opening it now. Look for the ⌶ icon in the menu bar."
say "  Copy some text, then press ⌥⌘V to prompt it."
say ""
open "$APP"
