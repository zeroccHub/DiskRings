#!/usr/bin/env bash
# Linux-side verification used during development: builds the portable
# targets (the AppKit UI compiles to a CLI-only stub off macOS) and runs tests.
set -euo pipefail
cd "$(dirname "$0")/.."
swift --version
swift build
swift build --build-tests
swift test
swift run DiskRings --cli "${1:-/usr}"
