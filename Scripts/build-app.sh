#!/bin/zsh
# Builds Prompter with SwiftPM and assembles a runnable Prompter.app bundle.
# Usage: Scripts/build-app.sh [debug|release] [--run]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
RUN=0
for arg in "$@"; do [[ "$arg" == "--run" ]] && RUN=1; done

# Release builds are universal so the app runs on Intel Macs as well as Apple silicon.
ARCH_FLAGS=()
[[ "$CONFIG" == "release" ]] && ARCH_FLAGS=(--arch arm64 --arch x86_64)

LOG="$(mktemp)"
if ! swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" >"$LOG" 2>&1; then
  grep -E "error|warning" "$LOG" | head -40 >&2
  rm -f "$LOG"
  echo "build failed" >&2
  exit 1
fi
rm -f "$LOG"
BIN_DIR="$(swift build -c "$CONFIG" "${ARCH_FLAGS[@]}" --show-bin-path)"
[[ -x "$BIN_DIR/Prompter" ]] || { echo "build failed: no binary at $BIN_DIR/Prompter" >&2; exit 1; }

APP="build/Prompter.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Prompter" "$APP/Contents/MacOS/Prompter"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# SwiftPM resource bundle (strings, sample scripts) lives next to the binary.
if [[ -d "$BIN_DIR/Prompter_Prompter.bundle" ]]; then
  cp -R "$BIN_DIR/Prompter_Prompter.bundle" "$APP/Contents/Resources/"
fi
[[ -f Resources/AppIcon.icns ]] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
echo -n "APPL????" > "$APP/Contents/PkgInfo"

# Ad-hoc signature is enough for local use; it gives TCC a stable identity for
# microphone / speech permission grants.
codesign --force --sign - --identifier com.nielcody.prompter "$APP" >/dev/null
echo "built $APP ($CONFIG, $(lipo -archs "$APP/Contents/MacOS/Prompter"))"

if [[ $RUN -eq 1 ]]; then
  pkill -x Prompter 2>/dev/null || true
  open "$APP"
fi
