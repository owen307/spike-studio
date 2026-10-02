#!/usr/bin/env bash
# Release bundle for Linux x64. Output: dist/spike-prime-studio-linux-x64.tar.gz
# Needs Flutter Linux desktop deps: clang, cmake, ninja, pkg-config, GTK 3,
# libstdc++ (g++ or libstdc++-dev), liblzma, and BlueZ headers for a real hub.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  if [[ -x "${HOME}/flutter/bin/flutter" ]]; then
    export PATH="${HOME}/flutter/bin:${PATH}"
  else
    echo "flutter is not on PATH. Install the Flutter SDK, then re-run." >&2
    exit 1
  fi
fi

flutter config --enable-linux-desktop
flutter pub get
flutter build linux --release
mkdir -p dist
tar -C build/linux/x64/release/bundle -czf dist/spike-prime-studio-linux-x64.tar.gz .
echo "Wrote dist/spike-prime-studio-linux-x64.tar.gz"
echo "Run: tar -xzf dist/spike-prime-studio-linux-x64.tar.gz -C /tmp/spike-studio && /tmp/spike-studio/spike_prime_studio"
