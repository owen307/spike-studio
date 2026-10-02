#!/usr/bin/env bash
# Release .app for macOS. Run this on a Mac with Xcode command-line tools.
# Bluetooth entitlement is already in macos/Runner/*.entitlements.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This script has to run on macOS." >&2
  exit 1
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on PATH." >&2
  exit 1
fi

flutter config --enable-macos-desktop
flutter pub get
flutter build macos --release
echo "App: build/macos/Build/Products/Release/Spike Prime Studio.app"
