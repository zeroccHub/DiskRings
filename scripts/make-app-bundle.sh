#!/usr/bin/env bash
# Builds DiskRings.app from the SwiftPM executable (macOS only).
# Usage: scripts/make-app-bundle.sh [--universal]
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "$(uname)" != "Darwin" ]]; then
  echo "This script must run on macOS (needs AppKit + codesign)." >&2
  exit 1
fi

ARCH_FLAGS=()
if [[ "${1:-}" == "--universal" ]]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release --product DiskRings "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release --show-bin-path "${ARCH_FLAGS[@]}")"

APP="dist/DiskRings.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DiskRings" "$APP/Contents/MacOS/DiskRings"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$APP/Contents/Resources/"

# Ad-hoc signature so the app launches locally. Use a Developer ID identity
# (and notarize) if you ever distribute it.
codesign --force --sign - "$APP"
echo "Built $APP"
echo "Run with: open $APP"
