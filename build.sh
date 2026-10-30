#!/usr/bin/env bash
# Configure (when needed) and build Lumen from the repository root.
# Android APK (default): ./build.sh [abi]
# Desktop: ./build.sh --desktop
set -euo pipefail

cd "$(dirname "$0")"
jobs="$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)"

if [[ "${1:-}" == "--desktop" ]]; then
  shift
  build_dir="${LUMEN_BUILD_DIR:-build}"
  cmake -S . -B "$build_dir" -G Ninja
  cmake --build "$build_dir" --parallel "$jobs"
  exit 0
fi

if [[ "${1:-}" == "--android" ]]; then shift; fi
abi="${1:-arm64-v8a}"
case "$abi" in
  arm64-v8a) qt_abi=android_arm64_v8a ;;
  armeabi-v7a) qt_abi=android_armv7 ;;
  x86_64) qt_abi=android_x86_64 ;;
  *) echo "Unsupported Android ABI: $abi" >&2; exit 2 ;;
esac

sdk="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-$HOME/Android/Sdk}}"
ndk="${ANDROID_NDK_ROOT:-$sdk/ndk/27.2.12479018}"
qt_android="${QT_ANDROID_DIR:-}"
if [[ -z "$qt_android" ]]; then
  if [[ -n "${QT_ROOT:-}" ]]; then
    qt_android="$QT_ROOT/$qt_abi"
  else
    while IFS= read -r candidate; do qt_android="$candidate"; done < <(
      for candidate in "$HOME"/Qt/6.*/"$qt_abi"; do
        [[ -x "$candidate/bin/qt-cmake" ]] && printf '%s\n' "$candidate"
      done | sort -V
    )
  fi
fi
if [[ -z "$qt_android" ]]; then
  echo "Qt Android kit not found. Install Qt for Android or set QT_ANDROID_DIR (or QT_ROOT)." >&2
  exit 2
fi

if [[ ! -x "$qt_android/bin/qt-cmake" ]]; then
  echo "Qt Android kit not found: $qt_android/bin/qt-cmake" >&2
  exit 2
fi
if [[ ! -x "$sdk/platform-tools/adb" || ! -x "$sdk/cmdline-tools/latest/bin/sdkmanager" ]]; then
  echo "Android SDK is incomplete at $sdk. Install platform-tools and cmdline-tools/latest." >&2
  exit 2
fi
if [[ ! -d "$ndk/toolchains/llvm/prebuilt" ]]; then
  echo "Android NDK r27c not found at $ndk (set ANDROID_NDK_ROOT if it is elsewhere)." >&2
  exit 2
fi
for dep in android-deps/sqlite/sqlite3.c "android-deps/ffmpeg/$abi/lib/libavformat.a" "android-deps/ffmpeg/$abi/ssl/lib/libssl.a"; do
  if [[ ! -f "$dep" ]]; then
    echo "Missing Android dependency: $dep" >&2
    echo "Run tools/android/fetch-sqlite.sh and tools/android/build-deps.sh $abi first." >&2
    exit 2
  fi
done

export ANDROID_SDK_ROOT="$sdk" ANDROID_NDK_ROOT="$ndk"
export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk}"
build_dir="${LUMEN_BUILD_DIR:-build-android}"
"$qt_android/bin/qt-cmake" -S . -B "$build_dir" -G Ninja \
  -DANDROID_SDK_ROOT="$ANDROID_SDK_ROOT" \
  -DANDROID_NDK_ROOT="$ANDROID_NDK_ROOT" \
  -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
cmake --build "$build_dir" --target apk --parallel "$jobs"
