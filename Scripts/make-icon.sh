#!/bin/zsh
# Regenerates Resources/AppIcon.icns from Scripts/make-icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)/AppIcon.iconset"
swiftc -O -o "$(dirname "$TMP")/make-icon" Scripts/make-icon.swift 2>/dev/null
"$(dirname "$TMP")/make-icon" "$TMP"
iconutil -c icns "$TMP" -o Resources/AppIcon.icns
echo "wrote Resources/AppIcon.icns"
