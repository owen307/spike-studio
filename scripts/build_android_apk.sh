#!/usr/bin/env bash
# Debug APK for arm64 Android. Output: dist/spike-prime-studio-arm64-debug.apk
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

if [[ -z "${ANDROID_HOME:-}" && -d "${HOME}/android-sdk" ]]; then
  export ANDROID_HOME="${HOME}/android-sdk"
  export ANDROID_SDK_ROOT="${ANDROID_HOME}"
fi
if [[ -z "${ANDROID_HOME:-}" ]]; then
  echo "ANDROID_HOME is not set. Install Android SDK platforms 35+ and build-tools, then re-run." >&2
  exit 1
fi

flutter pub get
flutter build apk --debug --target-platform android-arm64
mkdir -p dist
src=""
for candidate in \
  build/app/outputs/flutter-apk/app-arm64-v8a-debug.apk \
  build/app/outputs/flutter-apk/app-arm64-debug.apk \
  build/app/outputs/flutter-apk/app-debug.apk
do
  if [[ -f "$candidate" ]]; then
    src="$candidate"
    break
  fi
done
if [[ -z "$src" ]]; then
  echo "APK was not produced under build/app/outputs/flutter-apk/." >&2
  exit 1
fi
cp -f "$src" dist/spike-prime-studio-arm64-debug.apk
echo "Wrote dist/spike-prime-studio-arm64-debug.apk from $src"
