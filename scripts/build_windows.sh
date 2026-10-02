#!/usr/bin/env bash
# Release folder for Windows. Run this on Windows with Visual Studio C++ build tools.
# From PowerShell you can also run: flutter build windows --release
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) ;;
  *)
    echo "This script has to run on Windows." >&2
    exit 1
    ;;
esac

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is not on PATH." >&2
  exit 1
fi

flutter config --enable-windows-desktop
flutter pub get
flutter build windows --release
echo "Binary folder: build/windows/x64/runner/Release/"
