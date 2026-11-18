#!/bin/zsh
# Собирает AppIcon.icns: рисунок из исходников приложения + сборщик из scripts/make-icon.swift.
#   ./scripts/make-icon.sh build/AppIcon.icns
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/AppIcon.icns}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat Sources/DevCleaner/Views/AppIconArt.swift scripts/make-icon.swift > "$TMP/make-icon.swift"
swift "$TMP/make-icon.swift" "$OUT"
