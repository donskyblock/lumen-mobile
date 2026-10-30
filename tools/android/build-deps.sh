#!/usr/bin/env bash
# Builds OpenSSL (for https streams) and FFmpeg as static libraries for Android, into android-deps/ffmpeg/<abi>/.
#   ANDROID_NDK_ROOT=~/Android/Sdk/ndk/27.2.12479018 tools/android/build-deps.sh [abi ...]
# ABIs: arm64-v8a (default), armeabi-v7a, x86_64. Needs: curl, tar, make, perl.
# Not run in the environment this was written in: check the first ABI by hand before building all of them.
set -euo pipefail

FFMPEG_VERSION="${FFMPEG_VERSION:-9.0.1}"       # 8.1.2 also works; Lumen uses only the current channel-layout/send-receive APIs
OPENSSL_VERSION="${OPENSSL_VERSION:-3.5.9}"      # 3.5 is the current LTS line
API="${ANDROID_API:-28}"                          # Qt's minimum
NDK="${ANDROID_NDK_ROOT:?set ANDROID_NDK_ROOT to the NDK Qt uses (r27c = 27.2.12479018)}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/android-deps"
WORK="${WORK_DIR:-$ROOT/android-deps/.work}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu)}"
case "$(uname -s)" in Darwin) HOST=darwin-x86_64 ;; *) HOST=linux-x86_64 ;; esac
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST"
export PATH="$TOOLCHAIN/bin:$PATH"
ABIS=("$@"); [ ${#ABIS[@]} -eq 0 ] && ABIS=(arm64-v8a)

mkdir -p "$WORK" "$OUT/ffmpeg"
cd "$WORK"
[ -d "openssl-$OPENSSL_VERSION" ] || { curl -fL "https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VERSION/openssl-$OPENSSL_VERSION.tar.gz" | tar xz; }
[ -d "FFmpeg-n$FFMPEG_VERSION" ] || { curl -fL "https://codeload.github.com/FFmpeg/FFmpeg/tar.gz/refs/tags/n$FFMPEG_VERSION" | tar xz; }

for abi in "${ABIS[@]}"; do
  case "$abi" in
    arm64-v8a)   OSSL=android-arm64;  ARCH=aarch64; CC_TRIPLE=aarch64-linux-android;   EXTRA="";;
    armeabi-v7a) OSSL=android-arm;    ARCH=arm;     CC_TRIPLE=armv7a-linux-androideabi; EXTRA="--cpu=armv7-a";;
    x86_64)      OSSL=android-x86_64; ARCH=x86_64;  CC_TRIPLE=x86_64-linux-android;    EXTRA="--disable-x86asm";;
    *) echo "unknown ABI $abi"; exit 1;;
  esac
  PREFIX="$OUT/ffmpeg/$abi"
  rm -rf "$PREFIX" "build-$abi"; mkdir -p "$PREFIX" "build-$abi"

  echo "== OpenSSL $OPENSSL_VERSION ($abi)"
  ( cd "openssl-$OPENSSL_VERSION" && make distclean >/dev/null 2>&1 || true
    ANDROID_NDK_ROOT="$NDK" ./Configure "$OSSL" -D__ANDROID_API__="$API" no-shared no-tests no-apps no-docs --prefix="$PREFIX/ssl" --libdir=lib
    make -j"$JOBS" build_libs && make install_dev )

  echo "== FFmpeg $FFMPEG_VERSION ($abi)"
  ( cd "build-$abi" && "../FFmpeg-n$FFMPEG_VERSION/configure" \
      --prefix="$PREFIX" --enable-cross-compile --target-os=android --arch="$ARCH" $EXTRA \
      --cc="$CC_TRIPLE$API-clang" --cxx="$CC_TRIPLE$API-clang++" --ar=llvm-ar --nm=llvm-nm --ranlib=llvm-ranlib --strip=llvm-strip \
      --enable-static --disable-shared --enable-pic \
      --disable-programs --disable-doc --disable-avdevice --disable-avfilter --disable-swscale \
      --disable-encoders --disable-muxers --disable-autodetect --disable-debug \
      --enable-zlib --enable-openssl --enable-version3 \
      --extra-cflags="-I$PREFIX/ssl/include" --extra-ldflags="-L$PREFIX/ssl/lib -Wl,-z,max-page-size=16384" \
    && make -j"$JOBS" && make install )
  echo "done: $PREFIX  (libav*.a, libswresample.a, ssl/lib/libssl.a + libcrypto.a)"
done
